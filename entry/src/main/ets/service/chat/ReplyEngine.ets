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
import { SettingsStore } from '../../prefs/SettingsStore';
import { KeyVault } from '../../prefs/KeyVault';
import { AppContextHolder } from '../../common/AppContextHolder';

const TAG: string = 'ReplyEngine';
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
        ReplyEngine.settle(reply as AssistantMessage, 'stopped', Date.now(), null);
        store.touchSession(session);
      }
      ReplyEngine.pending.delete(sessionId);
    }
  }

  /** 发送一条用户消息并流式接收回复 */
  static async send(sessionId: string, question: string): Promise<void> {
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
    const settings = SettingsStore.get();

    const userMsg = store.appendUserMessage(session, question);
    const reply = store.appendAssistantPlaceholder(session, settings.thinking, settings.search);
    store.setStreaming(sessionId);
    ReplyEngine.pending.set(sessionId, { sessionId, assistantId: reply.id, question });

    const latestReminder = LatestReminder.create();
    reply.latestReminder = latestReminder;

    const body = ReplyEngine.buildRequestBody(
      session.messages, userMsg, null, apiKey, reply.thinking, reply.search,
      session.title === '', latestReminder);

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
    });
    ReplyEngine.aborters.set(sessionId, aborter);
  }

  /** M3 的 regenerate/continue 复用这里 */
  private static buildRequestBody(
    history: Message[],
    question: UserMessage,
    prefix: AssistantMessage | null,
    apiKey: string,
    thinking: boolean,
    search: boolean,
    needTitle: boolean,
    latestReminder: string
  ): string {
    const messages: Array<Object> = [];
    let previousReminder = '';
    const appendReminder = (reminder: string): void => {
      if (reminder !== '' && reminder !== previousReminder) {
        const m: Record<string, Object> = { 'role': 'latest_reminder', 'content': reminder };
        messages.push(m);
        previousReminder = reminder;
      }
    };
    for (const round of ReplyEngine.getContextRounds(history)) {
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
    const q: Record<string, Object> = { 'role': 'user', 'content': question.content };
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
    const body: Record<string, Object> = {
      'model': 'deepseek-flash',
      'system': SYSTEM_PROMPT,
      'messages': messages,
      'thinking': thinkingObj,
      'safety_check': safetyObj,
      'tools': tools,
      'stream': true,
    };
    if (needTitle) {
      const titleObj: Record<string, Object> = { 'enabled': true };
      body['title'] = titleObj;
    }
    return JSON.stringify(body);
  }

  /** 历史中「提问 + 有回答」成对的轮次（M2 线性版） */
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
      store.touchSession(session);
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
      store.touchSession(session);
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
export class UserAssistantPair {
  user: UserMessage;
  reply: AssistantMessage;

  constructor(user: UserMessage, reply: AssistantMessage) {
    this.user = user;
    this.reply = reply;
  }
}
