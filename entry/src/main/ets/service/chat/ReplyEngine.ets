import { ApiClient, StreamAborter } from '../api/ApiClient';
import { ApiError } from '../api/ApiError';
import { StreamEvent } from '../../model/ApiTypes';
import {
  AssistantMessage,
  Message,
  ReplyBlock,
  ReplyError,
  ReplyStatus,
  ServerToolPart,
  TextPart,
  ThinkingPart,
  UserMessage,
  isAssistant,
  isUser,
} from '../../model/ChatTypes';
import { ChatStore } from './ChatStore';
import { LatestReminder } from './LatestReminder';
import { Logger } from '../../common/Logger';
import { NotifyService } from '../notify/NotifyService';
import { LiveViewService } from '../notify/LiveViewService';
import { I18n } from '../../common/I18n';
import { ChatDb } from '../db/ChatDb';
import { SettingsStore } from '../../prefs/SettingsStore';
import { KeyVault } from '../../prefs/KeyVault';
import { AppContextHolder } from '../../common/AppContextHolder';
import { AttachmentService } from '../attachments/AttachmentService';
import { FileAttachment } from '../../model/ChatTypes';
import { ModelInfo } from '../../model/ModelInfo';

const TAG: string = 'ReplyEngine';
const NL2: string = String.fromCharCode(10) + String.fromCharCode(10);
/** 对齐原项目 store.ts */
const SYSTEM_PROMPT: string = '该助手为DeepSeek，由深度求索公司创造。';

interface PendingSend {
  sessionId: string;
  assistantId: string;
  question: string;
}

/**
 * 回复引擎：请求构建、事件合并（applyEvent/settleReply 逐行移植）、标题提取、停止。
 * M2 文本闭环；工具块仅保存展示所需字段；分支/附件后续里程碑接入。
 */
export class ReplyEngine {
  private static aborters: Map<string, StreamAborter> = new Map();
  private static blockIndexes: Map<string, Map<number, number>> = new Map();
  private static pending: Map<string, PendingSend> = new Map();
  private static hooksInstalled: boolean = false;

  /** 注入 Store 的流中止回调（幂等）：删除会话/清空数据时能真正断开 HTTP */
  private static installHooks(): void {
    if (ReplyEngine.hooksInstalled) {
      return;
    }
    ReplyEngine.hooksInstalled = true;
    ChatStore.get().onAbortStream = (sessionId: string): void => {
      ReplyEngine.stop(sessionId);
    };
  }

  static isStreaming(sessionId: string): boolean {
    return ChatStore.get().streamingSessionId === sessionId;
  }

  static stop(sessionId: string): void {
    const aborter = ReplyEngine.aborters.get(sessionId);
    if (aborter !== undefined) {
      aborter.abort();
      ReplyEngine.aborters.delete(sessionId);
    }
    const store = ChatStore.get();
    if (store.streamingSessionId === sessionId) {
      store.setStreaming(null);
    }
    const pending = ReplyEngine.pending.get(sessionId);
    if (pending !== undefined) {
      const session = store.sessionById(sessionId);
      const reply = session !== null ? store.findMessage(session, pending.assistantId) : null;
      if (session !== null && reply !== null && isAssistant(reply)) {
        const a = reply as AssistantMessage;
        ReplyEngine.settle(a, 'stopped', Date.now(), null);
        store.refreshVisible(session);
        store.persistMessage(session, a).catch(() => {});
      }
      ReplyEngine.pending.delete(sessionId);
    }
  }

  /** 发送一条用户消息并流式接收回复 */
  static async send(sessionId: string, question: string, files: FileAttachment[] = []): Promise<void> {
    ReplyEngine.installHooks();
    const store = ChatStore.get();
    const session = store.sessionById(sessionId);
    if (session === null || store.streamingSessionId !== null) {
      return;
    }
    const apiKey = await KeyVault.load(AppContextHolder.get());
    if (apiKey === null || apiKey === '') {
      Logger.warn(TAG, 'no api key');
      return;
    }
    // KeyVault 读取是异步的：并发调用可能都通过入口检查，进入前再确认一次
    if (store.streamingSessionId !== null) {
      Logger.warn(TAG, 'another stream started while loading key');
      return;
    }
    const settings = SettingsStore.get();
    if (settings.customModel) {
      // 外部模型不支持 Files API
      files = [];
      // 外部模型无 title 生成，本地回退：取首条提问截断
      if (session.title === '') {
        store.renameSession(sessionId, question.trim().slice(0, 24));
      }
    }

    // 挂到当前可见链尾部
    const visible = store.visible;
    const parentId = visible.length > 0 ? visible[visible.length - 1].id : null;
    const userMsg = store.appendUserMessage(session, question, parentId);
    userMsg.files = files;
    const reply = store.appendAssistantPlaceholder(session, userMsg.id, settings.thinking, settings.search);
    store.refreshVisible(session);
    store.setStreaming(sessionId);
    ReplyEngine.pending.set(sessionId, { sessionId, assistantId: reply.id, question });
    // 持久化提问与占位回复
    await store.persistMessage(session, userMsg);
    await store.persistMessage(session, reply);
    if (userMsg.parentId !== null) {
      const parent = store.findMessage(session, userMsg.parentId);
      if (parent !== null) {
        await store.persistMessage(session, parent);
      }
    }

    const latestReminder = LatestReminder.create();
    reply.latestReminder = latestReminder;

    try {
      await ReplyEngine.prepareFiles(apiKey, userMsg);
    } catch (err) {
      const e = err as ApiError;
      ReplyEngine.failUpload(sessionId, reply, e);
      return;
    }

    const body = ReplyEngine.buildRequestBody(
      store.visible, userMsg, null, reply.thinking, reply.search,
      session.title === '', latestReminder, userMsg.files.length > 0,
      session.compactAnchorId, session.compactSummary);

    const indexes = new Map<number, number>();
    ReplyEngine.blockIndexes.set(sessionId, indexes);
    const aborter = ApiClient.streamMessage(apiKey, body, {
      onEvent: (event: StreamEvent) => {
        ReplyEngine.handleEvent(sessionId, event);
      },
      onError: (err: ApiError) => {
        ReplyEngine.finishWithError(sessionId, err);
      },
      onDone: () => {
        ReplyEngine.finishWithDone(sessionId);
      },
    }, userMsg.files.length > 0);
    ReplyEngine.aborters.set(sessionId, aborter);
    LiveViewService.replyStarted(store.displayTitle(session)).catch(() => {});
  }

  /** 上传失败收尾：请求未发出，按 upload 错误归类 */
  private static failUpload(sessionId: string, reply: AssistantMessage, err: ApiError): void {
    const store = ChatStore.get();
    ReplyEngine.blockIndexes.delete(sessionId);
    ReplyEngine.aborters.delete(sessionId);
    ReplyEngine.pending.delete(sessionId);
    if (store.streamingSessionId === sessionId) {
      store.setStreaming(null);
    }
    LiveViewService.replyEnded().catch(() => {});
    const re = new ReplyError();
    re.kind = 'upload';
    re.message = err.message;
    const session = store.sessionById(sessionId);
    if (session !== null) {
      store.refreshVisible(session);
      ReplyEngine.settle(reply, 'error', Date.now(), re);
      store.persistMessage(session, reply).catch(() => {});
    }
  }

  /** 附件补传：serverId 为空且有本地原件的文件逐个上传 */
  private static async prepareFiles(apiKey: string, userMsg: UserMessage): Promise<void> {
    for (const f of userMsg.files) {
      if (f.serverId === null) {
        await AttachmentService.upload(apiKey, f);
      }
    }
  }

  /** 重新生成：在指定用户消息下新建 assistant 兄弟并重发同一问题 */
  static async regenerate(sessionId: string, userMsgId: string, question: string): Promise<void> {
    ReplyEngine.installHooks();
    const store = ChatStore.get();
    const session = store.sessionById(sessionId);
    if (session === null || store.streamingSessionId !== null) {
      return;
    }
    const apiKey = await KeyVault.load(AppContextHolder.get());
    if (apiKey === null || apiKey === '') {
      Logger.warn(TAG, 'no api key');
      return;
    }
    if (store.streamingSessionId !== null) {
      Logger.warn(TAG, 'another stream started while loading key');
      return;
    }
    const settings = SettingsStore.get();
    const userMsg = store.findMessage(session, userMsgId);
    if (userMsg === null || !isUser(userMsg)) {
      return;
    }
    const reply = store.appendAssistantPlaceholder(session, userMsgId, settings.thinking, settings.search);
    store.refreshVisible(session);
    store.setStreaming(sessionId);
    ReplyEngine.pending.set(sessionId, { sessionId, assistantId: reply.id, question });
    await store.persistMessage(session, reply);
    await store.persistMessage(session, userMsg as UserMessage);

    const latestReminder = LatestReminder.create();
    reply.latestReminder = latestReminder;

    const body = ReplyEngine.buildRequestBody(
      store.visible, userMsg as UserMessage, null, reply.thinking, reply.search,
      session.title === '', latestReminder, (userMsg as UserMessage).files.length > 0,
      session.compactAnchorId, session.compactSummary);

    const indexes = new Map<number, number>();
    ReplyEngine.blockIndexes.set(sessionId, indexes);
    const aborter = ApiClient.streamMessage(apiKey, body, {
      onEvent: (event: StreamEvent) => {
        ReplyEngine.handleEvent(sessionId, event);
      },
      onError: (err: ApiError) => {
        ReplyEngine.finishWithError(sessionId, err);
      },
      onDone: () => {
        ReplyEngine.finishWithDone(sessionId);
      },
    }, (userMsg as UserMessage).files.length > 0);
    ReplyEngine.aborters.set(sessionId, aborter);
    LiveViewService.replyStarted(store.displayTitle(session)).catch(() => {});
  }

  /** 编辑重发：在原用户消息的父节点下新建用户分支并发送 */
  static async sendEdited(sessionId: string, originalUserId: string, newText: string, files: FileAttachment[] = []): Promise<void> {
    ReplyEngine.installHooks();
    const store = ChatStore.get();
    const session = store.sessionById(sessionId);
    if (session === null || store.streamingSessionId !== null) {
      return;
    }
    const apiKey = await KeyVault.load(AppContextHolder.get());
    if (apiKey === null || apiKey === '') {
      Logger.warn(TAG, 'no api key');
      return;
    }
    if (store.streamingSessionId !== null) {
      Logger.warn(TAG, 'another stream started while loading key');
      return;
    }
    const original = store.findMessage(session, originalUserId);
    if (original === null || !isUser(original)) {
      return;
    }
    const parentId = (original as UserMessage).parentId;
    const settings = SettingsStore.get();
    if (settings.customModel) {
      files = [];
    }

    const userMsg = store.appendUserMessage(session, newText, parentId);
    userMsg.files = files;
    const reply = store.appendAssistantPlaceholder(session, userMsg.id, settings.thinking, settings.search);
    store.refreshVisible(session);
    store.setStreaming(sessionId);
    ReplyEngine.pending.set(sessionId, { sessionId, assistantId: reply.id, question: newText });
    await store.persistMessage(session, userMsg);
    await store.persistMessage(session, reply);
    if (parentId !== null) {
      const parent = store.findMessage(session, parentId);
      if (parent !== null) {
        await store.persistMessage(session, parent);
      }
    }

    const latestReminder = LatestReminder.create();
    reply.latestReminder = latestReminder;

    const body = ReplyEngine.buildRequestBody(
      store.visible, userMsg, null, reply.thinking, reply.search,
      session.title === '', latestReminder, userMsg.files.length > 0);

    const indexes = new Map<number, number>();
    ReplyEngine.blockIndexes.set(sessionId, indexes);
    const aborter = ApiClient.streamMessage(apiKey, body, {
      onEvent: (event: StreamEvent) => {
        ReplyEngine.handleEvent(sessionId, event);
      },
      onError: (err: ApiError) => {
        ReplyEngine.finishWithError(sessionId, err);
      },
      onDone: () => {
        ReplyEngine.finishWithDone(sessionId);
      },
    }, userMsg.files.length > 0);
    ReplyEngine.aborters.set(sessionId, aborter);
    LiveViewService.replyStarted(store.displayTitle(session)).catch(() => {});
  }

  /** M3 的 regenerate/continue 复用这里 */
  private static buildRequestBody(
    history: Message[],
    question: UserMessage,
    prefix: AssistantMessage | null,
    thinking: boolean,
    search: boolean,
    needTitle: boolean,
    latestReminder: string,
    withFiles: boolean,
    compactAnchorId: string = '',
    compactSummary: string = ''
  ): string {
    const settings = SettingsStore.get();
    const custom = settings.customModel;
    const messages: Array<Object> = [];
    let previousReminder = '';
    const appendReminder = (reminder: string): void => {
      if (custom) {
        // latest_reminder 为 DeepSeek 专有 role，外部模型不发送
        return;
      }
      if (reminder !== '' && reminder !== previousReminder) {
        const m: Record<string, Object> = { 'role': 'latest_reminder', 'content': reminder };
        messages.push(m);
        previousReminder = reminder;
      }
    };
    let anchorPassed = compactAnchorId === '';
    for (const round of ReplyEngine.getContextRounds(history)) {
      if (!anchorPassed) {
        // 压缩点（含）之前的轮次已进入摘要
        if (round.user.id === compactAnchorId) {
          anchorPassed = true;
        }
        continue;
      }
      if (round.user.content === '' ) {
        continue;
      }
      appendReminder(round.reply.latestReminder);
      const um: Record<string, Object> = { 'role': 'user', 'content': round.user.content };
      messages.push(um);
      const am: Record<string, Object> = { 'role': 'assistant', 'content': ReplyEngine.assistantTextParam(round.reply) };
      messages.push(am);
    }
    appendReminder(latestReminder);
    const q: Record<string, Object> = { 'role': 'user', 'content': ReplyEngine.userParam(question) };
    messages.push(q);
    if (prefix !== null && prefix.prefix) {
      const text = ReplyEngine.assistantTextParam(prefix);
      const hasContent = (text as Array<Object>).some((b) => {
        const r = b as Record<string, Object>;
        return typeof r['text'] === 'string' && (r['text'] as string).trim() !== '';
      });
      if (hasContent) {
        const am: Record<string, Object> = { 'role': 'assistant', 'content': text };
        messages.push(am);
      }
    }

    const body: Record<string, Object> = {
      'model': settings.model,
      'messages': messages,
      'stream': true,
    };
    const persona = settings.personalization;
    const summaryText = compactSummary === '' ? '' :
      I18n.translate('compactSystemLabel') + NL2 + compactSummary;
    if (custom) {
      // 外部模型：仅标准 Anthropic 字段（max_tokens 协议必填）；个性化/摘要作为 system
      body['max_tokens'] = ModelInfo.EXTERNAL_MAX_TOKENS;
      const sysParts: string[] = [];
      if (persona !== '') {
        sysParts.push(persona);
      }
      if (summaryText !== '') {
        sysParts.push(summaryText);
      }
      if (sysParts.length > 0) {
        body['system'] = sysParts.join(NL2);
      }
      return JSON.stringify(body);
    }

    const tools: Array<Object> = [];
    const readUrl: Record<string, Object> = {
      'type': 'deepseek_read_url', 'name': 'deepseek_read_url',
    };
    tools.push(readUrl);
    if (search) {
      const webSearch: Record<string, Object> = {
        'type': 'deepseek_web_search', 'name': 'deepseek_web_search',
      };
      tools.push(webSearch);
    }

    const thinkingObj: Record<string, Object> = {
      'type': thinking ? 'enabled' : 'disabled',
    };
    const safetyObj: Record<string, Object> = { 'level': 'high' };
    let sys = persona === '' ? SYSTEM_PROMPT : `${SYSTEM_PROMPT}

${persona}`;
    if (summaryText !== '') {
      sys = sys + NL2 + summaryText;
    }
    body['system'] = sys;
    body['thinking'] = thinkingObj;
    body['safety_check'] = safetyObj;
    body['tools'] = tools;
    if (needTitle) {
      const titleObj: Record<string, Object> = { 'enabled': true };
      body['title'] = titleObj;
    }
    if (thinking) {
      // 思考强度（官方 output_config.effort；thinking.budget_tokens 会被服务端忽略）
      const effortObj: Record<string, Object> = { 'effort': settings.thinkingEffort };
      body['output_config'] = effortObj;
    }
    return JSON.stringify(body);
  }

  /** 历史中「提问 + 有回答」成对的轮次（M2 线性版） */
  /**
   * compact：把当前可见链压缩为摘要存入会话（压缩点=最后一条可见消息）。
   * 返回 'ok' | 'too_short'；请求失败抛 ApiError。
   */
  static async compact(sessionId: string): Promise<string> {
    const store = ChatStore.get();
    const session = store.sessionById(sessionId);
    if (session === null || store.streamingSessionId !== null) {
      return 'too_short';
    }
    const visible = store.visible;
    const rounds = ReplyEngine.getContextRounds(visible);
    if (rounds.length < 2) {
      return 'too_short';
    }
    const apiKey = await KeyVault.load(AppContextHolder.get());
    if (apiKey === null || apiKey === '') {
      throw new ApiError('network', 'no api key');
    }
    const settings = SettingsStore.get();
    const custom = settings.customModel;
    const messages: Array<Object> = [];
    for (const round of rounds) {
      const um: Record<string, Object> = { 'role': 'user', 'content': round.user.content };
      messages.push(um);
      const am: Record<string, Object> = { 'role': 'assistant', 'content': ReplyEngine.assistantTextParam(round.reply) };
      messages.push(am);
    }
    const instr: Record<string, Object> = { 'role': 'user', 'content': I18n.translate('compactInstruction') };
    messages.push(instr);
    const body: Record<string, Object> = {
      'model': settings.model,
      'messages': messages,
      'stream': false,
    };
    if (custom) {
      body['max_tokens'] = ModelInfo.EXTERNAL_MAX_TOKENS;
      if (settings.personalization !== '') {
        body['system'] = settings.personalization;
      }
    } else {
      body['system'] = settings.personalization === '' ?
        SYSTEM_PROMPT : SYSTEM_PROMPT + NL2 + settings.personalization;
      const thinkingObj: Record<string, Object> = { 'type': 'disabled' };
      body['thinking'] = thinkingObj;
      const safetyObj: Record<string, Object> = { 'level': 'high' };
      body['safety_check'] = safetyObj;
    }
    const summary = await ApiClient.completeOnce(apiKey, JSON.stringify(body));
    if (summary === '') {
      throw new ApiError('protocol', 'empty summary');
    }
    const lastMsg = visible[visible.length - 1];
    session.compactAnchorId = lastMsg.id;
    session.compactSummary = summary;
    session.updatedAt = Date.now();
    await ChatDb.updateSessionMeta(session);
    return 'ok';
  }

  private static getContextRounds(history: Message[]): Array<UserAssistantPair> {
    const rounds: Array<UserAssistantPair> = [];
    for (let i = 0; i + 1 < history.length; i++) {
      const u = history[i];
      const r = history[i + 1];
      if (isUser(u) && isAssistant(r)) {
        const a = r as AssistantMessage;
        const usable = (a.status === 'done' || a.status === 'stopped')
          && a.stopReason !== 'refusal' && ReplyEngine.replyText(a) !== '';
        if (usable) {
          rounds.push(new UserAssistantPair(u as UserMessage, a));
          i++;
        }
      }
    }
    return rounds;
  }

  private static replyText(reply: AssistantMessage): string {
    let out = '';
    for (const block of reply.blocks) {
      if (block.type === 'text') {
        out += block.textPart.text;
      }
    }
    return out;
  }

  /** 用户消息参数：有文件时先文件块后文本块 */
  private static userParam(m: UserMessage): Object {
    const blocks: Array<Object> = [];
    for (const f of m.files) {
      if (f.serverId === null) {
        continue;
      }
      const source: Record<string, Object> = { 'type': 'file', 'file_id': f.serverId };
      const b: Record<string, Object> = {
        'type': f.isImage ? 'image' : 'document',
        'source': source,
      };
      blocks.push(b);
    }
    if (m.content !== '') {
      const tb: Record<string, Object> = { 'type': 'text', 'text': m.content };
      blocks.push(tb);
    }
    if (blocks.length === 0) {
      return '';
    }
    return blocks;
  }

  /** assistant 历史参数：相邻文本拼接（citations 去除），M2 只回传文本 */
  private static assistantTextParam(reply: AssistantMessage): Array<Object> {
    const content: Array<Object> = [];
    let current: Record<string, Object> | null = null;
    for (const block of reply.blocks) {
      if (block.type !== 'text' || block.textPart.isTemplate) {
        current = null;
        continue;
      }
      if (current !== null) {
        const prev = current['text'] as string;
        current['text'] = prev + block.textPart.text;
      } else {
        const textBlock: Record<string, Object> = { 'type': 'text', 'text': block.textPart.text };
        current = textBlock;
        content.push(textBlock);
      }
    }
    return content;
  }

  // ---------- 事件合并（applyEvent 移植） ----------

  private static handleEvent(sessionId: string, event: StreamEvent): void {
    const store = ChatStore.get();
    const session = store.sessionById(sessionId);
    if (session === null) {
      return;
    }
    const pending = ReplyEngine.pending.get(sessionId);
    if (pending === undefined) {
      return;
    }
    const found = store.findMessage(session, pending.assistantId);
    if (found === null || !isAssistant(found)) {
      return;
    }
    const reply = found as AssistantMessage;

    // 自动标题：仅无标题会话，message_delta.title
    if (event.type === 'message_delta' && event.title !== null && event.title.trim() !== ''
      && session.title === '') {
      store.setSessionTitleIfEmpty(sessionId, event.title.trim());
    }

    if (reply.status !== 'streaming') {
      reply.status = 'streaming';
    }
    const indexes = ReplyEngine.blockIndexes.get(sessionId);
    if (indexes === undefined) {
      return;
    }

    if (event.type === 'message_start') {
      if (event.messageUsage !== null) {
        reply.usage = event.messageUsage;
      }
      return;
    }
    if (event.type === 'content_block_start') {
      indexes.delete(event.index);
      const block = event.block;
      if (block === null) {
        return;
      }
      if (block.isToolUse) {
        reply.prefix = false;
        return;
      }
      const rb = new ReplyBlock();
      if (block.type === 'text') {
        rb.type = 'text';
        rb.textPart = new TextPart();
        rb.textPart.text = block.text.text;
        for (const c of block.text.citations) {
          rb.textPart.citations.push(c);
        }
      } else if (block.type === 'thinking') {
        rb.type = 'thinking';
        rb.thinkingPart = new ThinkingPart();
        rb.thinkingPart.thinking = block.thinking.thinking;
        rb.thinkingPart.signature = block.thinking.signature;
        rb.thinkingPart.startedAt = Date.now();
      } else if (block.type === 'server_tool_use' || block.type === 'web_search_tool_result'
        || block.type === 'web_fetch_tool_result') {
        rb.type = 'tool';
        rb.toolPart = new ServerToolPart();
        if (block.type === 'server_tool_use') {
          rb.toolPart.toolUse = block.serverToolUse;
        } else if (block.type === 'web_search_tool_result') {
          rb.toolPart.searchResult = block.searchResult;
        } else {
          rb.toolPart.fetchResult = block.fetchResult;
        }
      } else {
        return;
      }
      indexes.set(event.index, reply.blocks.length);
      reply.blocks.push(rb);
      return;
    }
    if (event.type === 'content_block_delta') {
      const idx = indexes.get(event.index);
      if (idx === undefined) {
        return;
      }
      const block = reply.blocks[idx];
      if (block === undefined) {
        return;
      }
      if (block.type === 'text' && event.deltaText !== null) {
        block.textPart.text += event.deltaText;
      } else if (block.type === 'thinking' && event.deltaThinking !== null) {
        block.thinkingPart.thinking += event.deltaThinking;
      } else if (block.type === 'thinking' && event.deltaSignature !== null) {
        block.thinkingPart.signature += event.deltaSignature;
      } else if (block.type === 'text' && event.deltaCitation !== null && event.deltaCitation !== undefined) {
        block.textPart.citations.push(event.deltaCitation);
      }
      return;
    }
    if (event.type === 'content_block_stop') {
      const idx = indexes.get(event.index);
      if (idx === undefined) {
        return;
      }
      indexes.delete(event.index);
      const block = reply.blocks[idx];
      if (block !== undefined && block.type === 'thinking' && block.thinkingPart.startedAt > 0
        && block.thinkingPart.endedAt === 0) {
        block.thinkingPart.endedAt = Date.now();
      }
      return;
    }
    if (event.type === 'message_delta') {
      reply.stopReason = event.stopReason;
      if (event.usage !== null) {
        reply.usage = event.usage;
      }
      return;
    }
  }

  private static finishWithDone(sessionId: string): void {
    const store = ChatStore.get();
    const pending = ReplyEngine.pending.get(sessionId);
    ReplyEngine.blockIndexes.delete(sessionId);
    ReplyEngine.aborters.delete(sessionId);
    ReplyEngine.pending.delete(sessionId);
    if (store.streamingSessionId === sessionId) {
      store.setStreaming(null);
    }
    const session = store.sessionById(sessionId);
    if (session === null || pending === undefined) {
      return;
    }
    const found = store.findMessage(session, pending.assistantId);
    if (found !== null && isAssistant(found)) {
      const reply = found as AssistantMessage;
      ReplyEngine.settle(reply, 'done', Date.now(), null);
      store.refreshVisible(session);
      store.persistMessage(session, reply).catch(() => {});
      NotifyService.replySettled(store.displayTitle(session), false).catch(() => {});
      LiveViewService.replyEnded().catch(() => {});
    }
  }
  private static finishWithError(sessionId: string, err: ApiError): void {
    const store = ChatStore.get();
    const pending = ReplyEngine.pending.get(sessionId);
    ReplyEngine.blockIndexes.delete(sessionId);
    ReplyEngine.aborters.delete(sessionId);
    ReplyEngine.pending.delete(sessionId);
    if (store.streamingSessionId === sessionId) {
      store.setStreaming(null);
    }
    const session = store.sessionById(sessionId);
    if (session === null || pending === undefined) {
      return;
    }
    const found = store.findMessage(session, pending.assistantId);
    if (found !== null && isAssistant(found)) {
      const reply = found as AssistantMessage;
      const re = new ReplyError();
      re.kind = err.kind;
      re.message = err.message;
      re.status = err.status;
      reply.error = re;
      ReplyEngine.settle(reply, 'error', Date.now(), re);
      store.refreshVisible(session);
      store.persistMessage(session, reply).catch(() => {});
      NotifyService.replySettled(store.displayTitle(session), true).catch(() => {});
      LiveViewService.replyEnded().catch(() => {});
    }
  }

  /**
   * 回复结束：未结束的思考块收尾；refusal 时丢弃已下发的思考与正文（协议要求）。
   */
  private static settle(reply: AssistantMessage, status: ReplyStatus, now: number, error: ReplyError | null): void {
    reply.status = status;
    reply.error = error;
    if (reply.stopReason === 'refusal') {
      const kept: ReplyBlock[] = [];
      for (const block of reply.blocks) {
        if (block.type === 'thinking' || block.type === 'text') {
          continue;
        }
        kept.push(block);
      }
      reply.blocks = kept;
      return;
    }
    for (const block of reply.blocks) {
      if (block.type === 'thinking' && block.thinkingPart.startedAt > 0 && block.thinkingPart.endedAt === 0) {
        block.thinkingPart.endedAt = now;
      }
    }
  }
}

/** 历史轮次对 */
class UserAssistantPair {
  user: UserMessage;
  reply: AssistantMessage;

  constructor(user: UserMessage, reply: AssistantMessage) {
    this.user = user;
    this.reply = reply;
  }
}
