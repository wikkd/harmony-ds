import { ApiClient, StreamAborter } from '../api/ApiClient';
import { ApiError } from '../../model/ApiError';
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
import { RequestBodyBuilder, SYSTEM_PROMPT, NL2 } from './RequestBodyBuilder';
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
    ReplyEngine.blockIndexes.delete(sessionId);
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
        store.persistMessage(session, a).catch((e: object) => {
          Logger.warn(TAG, `persist stopped reply failed: ${JSON.stringify(e)}`);
        });
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
    // 持久化提问与占位回复（失败不能卡死流式态：清理后以本地错误收尾）
    try {
      await store.persistMessage(session, userMsg);
      await store.persistMessage(session, reply);
      if (userMsg.parentId !== null) {
        const parent = store.findMessage(session, userMsg.parentId);
        if (parent !== null) {
          await store.persistMessage(session, parent);
        }
      }
    } catch (err) {
      ReplyEngine.failPersist(sessionId, reply, err as object);
      return;
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

    const body = RequestBodyBuilder.build(
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
      store.persistMessage(session, reply).catch((e: object) => {
        Logger.warn(TAG, `persist error reply failed: ${JSON.stringify(e)}`);
      });
    }
  }

  /** 持久化失败收尾（流式启动前）：清理流式态并把占位回复标为本地错误，避免 UI 永久卡死 */
  private static failPersist(sessionId: string, reply: AssistantMessage, err: object): void {
    Logger.error(TAG, `persist after streaming-start failed: ${JSON.stringify(err)}`);
    const store = ChatStore.get();
    ReplyEngine.pending.delete(sessionId);
    if (store.streamingSessionId === sessionId) {
      store.setStreaming(null);
    }
    const re = new ReplyError();
    re.kind = 'protocol';
    re.message = 'persist failed';
    const session = store.sessionById(sessionId);
    if (session !== null) {
      store.refreshVisible(session);
      ReplyEngine.settle(reply, 'error', Date.now(), re);
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
    try {
      await store.persistMessage(session, reply);
      await store.persistMessage(session, userMsg as UserMessage);
    } catch (err) {
      ReplyEngine.failPersist(sessionId, reply, err as object);
      return;
    }

    const latestReminder = LatestReminder.create();
    reply.latestReminder = latestReminder;

    const body = RequestBodyBuilder.build(
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
    try {
      await store.persistMessage(session, userMsg);
      await store.persistMessage(session, reply);
      if (parentId !== null) {
        const parent = store.findMessage(session, parentId);
        if (parent !== null) {
          await store.persistMessage(session, parent);
        }
      }
    } catch (err) {
      ReplyEngine.failPersist(sessionId, reply, err as object);
      return;
    }

    const latestReminder = LatestReminder.create();
    reply.latestReminder = latestReminder;

    const body = RequestBodyBuilder.build(
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


  /**
   * compact：把当前可见链压缩为摘要存入会话（压缩点=最后一条可见消息）。
   * 返回 'ok' | 'too_short' | 'busy'（流式进行中拒绝）；请求失败抛 ApiError。
   */
  static async compact(sessionId: string): Promise<string> {
    const store = ChatStore.get();
    const session = store.sessionById(sessionId);
    if (session === null) {
      return 'too_short';
    }
    if (store.streamingSessionId !== null) {
      // 语义区分：流式进行中≠会话太短，UI 提示不同文案
      return 'busy';
    }
    const visible = store.visible;
    const rounds = RequestBodyBuilder.getContextRounds(visible);
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
      const am: Record<string, Object> = { 'role': 'assistant', 'content': RequestBodyBuilder.assistantTextParam(round.reply) };
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
      store.persistMessage(session, reply).catch((e: object) => {
        Logger.warn(TAG, `persist done reply failed: ${JSON.stringify(e)}`);
      });
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
      store.persistMessage(session, reply).catch((e: object) => {
        Logger.warn(TAG, `persist error reply failed: ${JSON.stringify(e)}`);
      });
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
