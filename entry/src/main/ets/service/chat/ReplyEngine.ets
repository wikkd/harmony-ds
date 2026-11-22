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
  Session,
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
/** 附件失效重试上限与退避基数（对齐官方 store.ts） */
const FILE_RETRY_LIMIT: number = 2;
const FILE_RETRY_BASE_DELAY: number = 1000;
/** 流式过程落盘节流间隔 */
const STREAM_PERSIST_INTERVAL_MS: number = 2000;

interface PendingSend {
  sessionId: string;
  assistantId: string;
  wantTitle: boolean;
  receivedContent: boolean;
}

/** 一次流式运行的可中断句柄：requestStop 触发全部已注册的中断回调 */
class RunHandle {
  stopRequested: boolean = false;
  private interruptors: Array<() => void> = [];

  onInterrupt(fn: () => void): void {
    if (this.stopRequested) {
      fn();
      return;
    }
    this.interruptors.push(fn);
  }

  removeInterrupt(fn: () => void): void {
    const idx = this.interruptors.indexOf(fn);
    if (idx >= 0) {
      this.interruptors.splice(idx, 1);
    }
  }

  requestStop(): void {
    if (this.stopRequested) {
      return;
    }
    this.stopRequested = true;
    const fns = this.interruptors.slice();
    this.interruptors = [];
    for (const fn of fns) {
      fn();
    }
  }
}

/** 一次流式请求的计划（历史为发送前的可见链快照，消息为活引用） */
class StreamPlan {
  sessionId: string = '';
  replyId: string = '';
  questionId: string = '';
  prefix: AssistantMessage | null = null;
  history: Message[] = [];
  wantTitle: boolean = true;
}

/** 单次流式结果 */
class StreamOutcome {
  kind: 'done' | 'error' | 'stopped' = 'done';
  error: ApiError | null = null;

  constructor(kind: 'done' | 'error' | 'stopped', error: ApiError | null) {
    this.kind = kind;
    this.error = error;
  }
}

/**
 * 回复引擎：请求构建、事件合并、附件补传与失效重传、停止与重试（对齐官方 store.ts streamReply）。
 * 入口只做链变更与计划快照，runStream 内统一重试、收尾与落盘。
 */
export class ReplyEngine {
  private static aborters: Map<string, StreamAborter> = new Map();
  private static blockIndexes: Map<string, Map<number, number>> = new Map();
  private static pending: Map<string, PendingSend> = new Map();
  private static runHandles: Map<string, RunHandle> = new Map();
  private static lastStreamPersist: Map<string, number> = new Map();
  private static hooksInstalled: boolean = false;

  /** 注入 Store 的回调（幂等） */
  private static installHooks(): void {
    if (ReplyEngine.hooksInstalled) {
      return;
    }
    ReplyEngine.hooksInstalled = true;
    const store = ChatStore.get();
    store.onAbortStream = (sessionId: string): void => {
      ReplyEngine.stop(sessionId);
    };
    store.onSessionRenamed = (sessionId: string): void => {
      // 会话已有标题（手动/本地回退），撤销本流的自动标题请求
      const pending = ReplyEngine.pending.get(sessionId);
      if (pending !== undefined) {
        pending.wantTitle = false;
      }
    };
    store.onBackgroundFlush = (): void => {
      // 退后台：冲刷全部进行中的流式落盘
      const ids: string[] = [];
      for (const entry of ReplyEngine.pending) {
        ids.push(entry[0]);
      }
      for (const sessionId of ids) {
        ReplyEngine.flushStreamPersist(sessionId);
      }
    };
  }

  static isStreaming(sessionId: string): boolean {
    return ChatStore.get().streamingSessionId === sessionId;
  }

  /** 停止指定会话的在途流：请求中断由 runStream 收尾落盘 */
  static stop(sessionId: string): void {
    const handle = ReplyEngine.runHandles.get(sessionId);
    if (handle !== undefined) {
      handle.requestStop();
      return;
    }
    const store = ChatStore.get();
    if (store.streamingSessionId === sessionId) {
      store.setStreaming(null);
    }
  }

  // ---------- 入口 ----------

  /** 发送一条用户消息并流式接收回复 */
  static async send(sessionId: string, question: string, files: FileAttachment[] = []): Promise<void> {
    ReplyEngine.installHooks();
    const store = ChatStore.get();
    const session = store.sessionById(sessionId);
    if (session === null || store.streamingSessionId !== null) {
      return;
    }
    const apiKey = await ReplyEngine.entryKey();
    if (apiKey === null) {
      return;
    }
    const settings = SettingsStore.get();
    if (settings.customModel) {
      // 外部模型不支持 Files API 与 title 生成
      files = [];
      if (session.title === '') {
        store.renameSession(sessionId, question.trim().slice(0, 24)).catch(() => {});
      }
    }

    const preVisible = store.visible;
    const parentId = preVisible.length > 0 ? preVisible[preVisible.length - 1].id : null;
    const userMsg = store.appendUserMessage(session, question, parentId);
    userMsg.files = files;
    const reply = store.appendAssistantPlaceholder(session, userMsg.id, settings.thinking, settings.search);
    store.refreshVisible(session);
    store.notifyMessageAppended(); // 发送即跳底：用户在半途阅读也回到最新

    const plan = new StreamPlan();
    plan.sessionId = sessionId;
    plan.replyId = reply.id;
    plan.questionId = userMsg.id;
    plan.history = preVisible;
    plan.wantTitle = session.title === '' && !settings.customModel;
    const handle = ReplyEngine.beginRun(sessionId, plan);

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

    await ReplyEngine.runStream(apiKey, plan, handle);
  }

  /** 重新生成：在指定用户消息下新建 assistant 兄弟并重发同一问题 */
  static async regenerate(sessionId: string, userMsgId: string, question: string): Promise<void> {
    ReplyEngine.installHooks();
    const store = ChatStore.get();
    const session = store.sessionById(sessionId);
    if (session === null || store.streamingSessionId !== null) {
      return;
    }
    const apiKey = await ReplyEngine.entryKey();
    if (apiKey === null) {
      return;
    }
    const userMsg = store.findMessage(session, userMsgId);
    if (userMsg === null || !isUser(userMsg)) {
      return;
    }
    const preVisible = store.visible;
    const idx = preVisible.findIndex((m) => m.id === userMsgId);
    if (idx < 0) {
      return;
    }
    const settings = SettingsStore.get();
    const reply = store.appendAssistantPlaceholder(session, userMsgId, settings.thinking, settings.search);
    store.refreshVisible(session);
    store.notifyMessageAppended(); // 重新生成同样跳底

    const plan = new StreamPlan();
    plan.sessionId = sessionId;
    plan.replyId = reply.id;
    plan.questionId = userMsgId;
    plan.history = preVisible.slice(0, idx);
    plan.wantTitle = session.title === '' && !settings.customModel;
    const handle = ReplyEngine.beginRun(sessionId, plan);

    try {
      await store.persistMessage(session, reply);
      await store.persistMessage(session, userMsg as UserMessage);
    } catch (err) {
      ReplyEngine.failPersist(sessionId, reply, err as object);
      return;
    }

    await ReplyEngine.runStream(apiKey, plan, handle);
  }

  /** 编辑重发：在原用户消息的父节点下新建用户分支并发送 */
  static async sendEdited(sessionId: string, originalUserId: string, newText: string, files: FileAttachment[] = []): Promise<void> {
    ReplyEngine.installHooks();
    const store = ChatStore.get();
    const session = store.sessionById(sessionId);
    if (session === null || store.streamingSessionId !== null) {
      return;
    }
    const apiKey = await ReplyEngine.entryKey();
    if (apiKey === null) {
      return;
    }
    const original = store.findMessage(session, originalUserId);
    if (original === null || !isUser(original)) {
      return;
    }
    const preVisible = store.visible;
    const idx = preVisible.findIndex((m) => m.id === originalUserId);
    if (idx < 0) {
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
    store.notifyMessageAppended();

    const plan = new StreamPlan();
    plan.sessionId = sessionId;
    plan.replyId = reply.id;
    plan.questionId = userMsg.id;
    plan.history = preVisible.slice(0, idx);
    plan.wantTitle = session.title === '' && !settings.customModel;
    const handle = ReplyEngine.beginRun(sessionId, plan);

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

    await ReplyEngine.runStream(apiKey, plan, handle);
  }

  /** 继续最后一条可续写的回答：保留原消息与开关，新流内容追加到原块之后 */
  static async continueReply(sessionId: string, messageId: string): Promise<void> {
    ReplyEngine.installHooks();
    const store = ChatStore.get();
    const session = store.sessionById(sessionId);
    if (session === null || store.streamingSessionId !== null) {
      return;
    }
    const path = store.visible;
    if (path.length < 2) {
      return;
    }
    const question = path[path.length - 2];
    const previous = path[path.length - 1];
    if (!isUser(question) || !isAssistant(previous) || previous.id !== messageId
      || !RequestBodyBuilder.canContinueReply(previous as AssistantMessage)) {
      return;
    }
    const apiKey = await ReplyEngine.entryKey();
    if (apiKey === null) {
      return;
    }
    const assistant = previous as AssistantMessage;
    const settings = SettingsStore.get();
    // 复位续写状态：保留原块，未记录模型时用默认模型
    assistant.status = 'pending';
    assistant.stopReason = null;
    assistant.error = null;
    if (assistant.model === null) {
      assistant.model = settings.model;
    }

    const plan = new StreamPlan();
    plan.sessionId = sessionId;
    plan.replyId = assistant.id;
    plan.questionId = question.id;
    plan.prefix = assistant;
    plan.history = path.slice(0, path.length - 2);
    plan.wantTitle = session.title === '' && !settings.customModel;
    const handle = ReplyEngine.beginRun(sessionId, plan);

    try {
      await store.persistMessage(session, assistant);
    } catch (err) {
      ReplyEngine.failPersist(sessionId, assistant, err as object);
      return;
    }

    await ReplyEngine.runStream(apiKey, plan, handle);
  }

  /** 附件补传失败后重试：保留原回答位置，重新补传并请求 */
  static async retryUpload(sessionId: string, messageId: string): Promise<void> {
    ReplyEngine.installHooks();
    const store = ChatStore.get();
    const session = store.sessionById(sessionId);
    if (session === null || store.streamingSessionId !== null) {
      return;
    }
    const path = store.visible;
    const idx = path.findIndex((m) => m.id === messageId);
    if (idx < 1) {
      return;
    }
    const question = path[idx - 1];
    const previous = path[idx];
    if (!isUser(question) || !isAssistant(previous)) {
      return;
    }
    const assistant = previous as AssistantMessage;
    if (assistant.error === null || assistant.error.kind !== 'upload') {
      return;
    }
    const apiKey = await ReplyEngine.entryKey();
    if (apiKey === null) {
      return;
    }
    const settings = SettingsStore.get();
    // 保留 stopReason：可能已收到部分内容
    assistant.status = 'pending';
    assistant.error = null;

    const plan = new StreamPlan();
    plan.sessionId = sessionId;
    plan.replyId = assistant.id;
    plan.questionId = question.id;
    plan.history = path.slice(0, idx - 1);
    plan.wantTitle = session.title === '' && !settings.customModel;
    const handle = ReplyEngine.beginRun(sessionId, plan);

    try {
      await store.persistMessage(session, assistant);
    } catch (err) {
      ReplyEngine.failPersist(sessionId, assistant, err as object);
      return;
    }

    await ReplyEngine.runStream(apiKey, plan, handle);
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
      const am: Record<string, Object> = { 'role': 'assistant', 'content': RequestBodyBuilder.assistantParam(round.reply) };
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

  // ---------- 运行时 ----------

  /** 入口加载 API Key：空 Key 或等待期间有其它流进入时放弃 */
  private static async entryKey(): Promise<string | null> {
    const apiKey = await KeyVault.load(AppContextHolder.get());
    if (apiKey === null || apiKey === '') {
      Logger.warn(TAG, 'no api key');
      return null;
    }
    // KeyVault 读取是异步的：并发调用可能都通过入口检查，进入前再确认一次
    if (ChatStore.get().streamingSessionId !== null) {
      Logger.warn(TAG, 'another stream started while loading key');
      return null;
    }
    return apiKey;
  }

  /** 标记会话进入流式并登记运行句柄（与 setStreaming 同步完成，停止无竞态窗口） */
  private static beginRun(sessionId: string, plan: StreamPlan): RunHandle {
    const handle = new RunHandle();
    const store = ChatStore.get();
    store.setStreaming(sessionId);
    ReplyEngine.runHandles.set(sessionId, handle);
    ReplyEngine.pending.set(sessionId, {
      sessionId,
      assistantId: plan.replyId,
      wantTitle: plan.wantTitle,
      receivedContent: false,
    });
    return handle;
  }

  /** 清理一次运行的全部登记 */
  private static cleanupRun(sessionId: string): void {
    ReplyEngine.runHandles.delete(sessionId);
    ReplyEngine.blockIndexes.delete(sessionId);
    ReplyEngine.aborters.delete(sessionId);
    ReplyEngine.pending.delete(sessionId);
    ReplyEngine.lastStreamPersist.delete(sessionId);
  }

  /** 持久化失败收尾（流式启动前）：清理流式态并把回复标为本地错误，避免 UI 永久卡死 */
  private static failPersist(sessionId: string, reply: AssistantMessage, err: object): void {
    Logger.error(TAG, `persist after streaming-start failed: ${JSON.stringify(err)}`);
    const store = ChatStore.get();
    ReplyEngine.cleanupRun(sessionId);
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
      store.persistMessageSafe(session, reply);
    }
  }

  /**
   * 请求并消费流：先补齐附件 serverId，再发请求；服务端判定 file_id 失效时
   * 重传后重发（退避、次数上限）；完成、失败或停止后统一收尾落盘。
   */
  private static async runStream(apiKey: string, plan: StreamPlan, handle: RunHandle): Promise<void> {
    const store = ChatStore.get();
    const session = store.sessionById(plan.sessionId);
    if (session === null) {
      ReplyEngine.cleanupRun(plan.sessionId);
      return;
    }
    LiveViewService.replyStarted(store.displayTitle(session)).catch(() => {});
    let status: 'done' | 'stopped' | 'error' = 'stopped';
    let error: ReplyError | null = null;
    try {
      if (handle.stopRequested) {
        return;
      }
      for (let attempt = 0; ; attempt++) {
        /** 附件补齐前出错属于上传失败，请求还没有发出 */
        let preparing = true;
        try {
          await ReplyEngine.prepareFiles(apiKey, plan, session, handle);
          preparing = false;
          if (handle.stopRequested) {
            return;
          }
          const liveSession = store.sessionById(plan.sessionId);
          if (liveSession === null) {
            return;
          }
          const foundReply = store.findMessage(liveSession, plan.replyId);
          const foundQuestion = store.findMessage(liveSession, plan.questionId);
          if (foundReply === null || !isAssistant(foundReply) || foundQuestion === null || !isUser(foundQuestion)) {
            return;
          }
          const assistant = foundReply as AssistantMessage;
          const question = foundQuestion as UserMessage;
          // 本轮信息：续写沿用原快照，其余场景新建
          assistant.latestReminder = plan.prefix !== null ? plan.prefix.latestReminder : LatestReminder.create();
          const pending = ReplyEngine.pending.get(plan.sessionId);
          if (pending !== undefined) {
            pending.receivedContent = false;
          }
          const outcome = await ReplyEngine.awaitStream(apiKey, plan, liveSession, assistant, question, handle);
          if (outcome.kind === 'done') {
            status = 'done';
            return;
          }
          if (outcome.kind === 'stopped') {
            return;
          }
          if (handle.stopRequested) {
            return;
          }
          const err = outcome.error as ApiError;
          // 附件失效：重传后重发。收到过内容块（含丢弃的客户端工具）后不自动重发。
          const pend = ReplyEngine.pending.get(plan.sessionId);
          const receivedContent = pend !== undefined ? pend.receivedContent : false;
          if (attempt < FILE_RETRY_LIMIT && !receivedContent
            && ReplyEngine.reuploadInvalidatedFiles(store, liveSession, plan, err)) {
            await ReplyEngine.waitForRetry(attempt, handle);
            if (handle.stopRequested) {
              return;
            }
            continue;
          }
          if (err.kind === 'interrupted' && assistant.stopReason !== null) {
            // 已收到 message_delta 的结束原因，只是缺了结尾的 message_stop
            status = 'done';
            return;
          }
          const re = new ReplyError();
          re.kind = err.kind;
          re.message = err.message;
          re.status = err.status;
          status = 'error';
          error = re;
          return;
        } catch (err) {
          if (handle.stopRequested) {
            return;
          }
          if (preparing) {
            const e = err as ApiError;
            const re = new ReplyError();
            re.kind = 'upload';
            re.message = e.message;
            status = 'error';
            error = re;
            return;
          }
          const re = new ReplyError();
          re.kind = 'protocol';
          re.message = `${JSON.stringify(err)}`;
          status = 'error';
          error = re;
          return;
        }
      }
    } finally {
      ReplyEngine.cleanupRun(plan.sessionId);
      const live = store.sessionById(plan.sessionId);
      if (live !== null) {
        const found = store.findMessage(live, plan.replyId);
        if (found !== null && isAssistant(found)) {
          const assistant = found as AssistantMessage;
          ReplyEngine.settle(assistant, status, Date.now(), error);
          store.refreshVisible(live);
          store.persistMessageSafe(live, assistant);
        }
      }
      if (store.streamingSessionId === plan.sessionId) {
        store.setStreaming(null);
      }
      LiveViewService.replyEnded().catch(() => {});
      if (live !== null && status !== 'stopped' && (status === 'done' || error === null || error.kind !== 'upload')) {
        NotifyService.replySettled(store.displayTitle(live), status === 'error').catch(() => {});
      }
    }
  }

  /** 发起一次流式请求；中断/完成/失败只决议一次 */
  private static awaitStream(apiKey: string, plan: StreamPlan, session: Session, assistant: AssistantMessage,
    question: UserMessage, handle: RunHandle): Promise<StreamOutcome> {
    return new Promise<StreamOutcome>((resolve) => {
      let settled = false;
      let aborter: StreamAborter | null = null;
      const settleOnce = (outcome: StreamOutcome): void => {
        if (settled) {
          return;
        }
        settled = true;
        handle.removeInterrupt(interruptFn);
        resolve(outcome);
      };
      const interruptFn = (): void => {
        if (aborter !== null) {
          aborter.abort();
        }
        settleOnce(new StreamOutcome('stopped', null));
      };
      if (handle.stopRequested) {
        interruptFn();
        return;
      }
      handle.onInterrupt(interruptFn);
      const store = ChatStore.get();
      const pending = ReplyEngine.pending.get(plan.sessionId);
      const needTitle = pending !== undefined && pending.wantTitle && session.title === '';
      const withFiles = ReplyEngine.requestHasFiles(plan, question);
      const body = RequestBodyBuilder.build(
        plan.history, question, plan.prefix, assistant.thinking, assistant.search,
        needTitle, assistant.latestReminder, withFiles,
        session.compactAnchorId, session.compactSummary);
      const indexes = new Map<number, number>();
      ReplyEngine.blockIndexes.set(plan.sessionId, indexes);
      aborter = ApiClient.streamMessage(apiKey, body, {
        onEvent: (event: StreamEvent) => {
          ReplyEngine.handleEvent(plan.sessionId, event);
        },
        onError: (err: ApiError) => {
          settleOnce(new StreamOutcome('error', err));
        },
        onDone: () => {
          settleOnce(new StreamOutcome('done', null));
        },
      }, withFiles);
      if (settled) {
        // 竞态：中断先于流建立——立即中止刚创建的请求
        aborter.abort();
      }
    });
  }

  /** 请求体是否含文件块（决定 files beta 头） */
  private static requestHasFiles(plan: StreamPlan, question: UserMessage): boolean {
    for (const f of question.files) {
      if (f.serverId !== null) {
        return true;
      }
    }
    const rounds = RequestBodyBuilder.getContextRounds(plan.history);
    for (const round of rounds) {
      for (const f of round.user.files) {
        if (f.serverId !== null) {
          return true;
        }
      }
    }
    return false;
  }

  /**
   * 发送前补齐附件 serverId：
   * - 本轮提问的附件逐个补齐，任一失败整体失败（已成功的照常写回，重试时复用）；
   * - 历史轮次（仅进入上下文的）中没有 serverId 的附件，从最新消息往前逐张补传，失败静默跳过。
   * 停止生成立即生效；上传任务本身不取消，完成后照常写回。
   */
  private static async prepareFiles(apiKey: string, plan: StreamPlan, session: Session, handle: RunHandle): Promise<void> {
    const store = ChatStore.get();
    const foundQuestion = store.findMessage(session, plan.questionId);
    if (foundQuestion === null || !isUser(foundQuestion)) {
      return;
    }
    const question = foundQuestion as UserMessage;
    for (const f of question.files) {
      if (f.serverId !== null || f.localPath === '') {
        // 已上传或本地没有原件（导入的只有元数据）：仅展示、不进入请求
        continue;
      }
      try {
        await ReplyEngine.raceInterrupt(AttachmentService.ensureUploaded(apiKey, f), handle);
      } catch (err) {
        store.persistMessageSafe(session, question);
        throw err as ApiError;
      }
    }
    store.persistMessageSafe(session, question);
    const rounds = RequestBodyBuilder.getContextRounds(plan.history);
    for (let i = rounds.length - 1; i >= 0; i--) {
      const found = store.findMessage(session, rounds[i].user.id);
      if (found === null || !isUser(found)) {
        continue;
      }
      const live = found as UserMessage;
      for (const f of live.files) {
        if (f.serverId !== null || f.localPath === '') {
          continue;
        }
        try {
          await ReplyEngine.raceInterrupt(AttachmentService.ensureUploaded(apiKey, f), handle);
          store.persistMessageSafe(session, live);
        } catch (err) {
          if (handle.stopRequested) {
            throw new ApiError('interrupted', 'stopped during prepare');
          }
          // 历史附件失败静默跳过：该附件不进入本次请求，下次发送时再试
        }
      }
    }
  }

  /** 与停止信号竞速：停止时立即以 interrupted 拒绝，上传任务本身继续 */
  private static raceInterrupt<T>(p: Promise<T>, handle: RunHandle): Promise<T> {
    return new Promise<T>((resolve, reject) => {
      let done = false;
      const interruptFn = (): void => {
        if (done) {
          return;
        }
        done = true;
        reject(new ApiError('interrupted', 'stopped during prepare'));
      };
      handle.onInterrupt(interruptFn);
      p.then((v: T) => {
        if (done) {
          return;
        }
        done = true;
        handle.removeInterrupt(interruptFn);
        resolve(v);
      }).catch((e: ApiError) => {
        if (done) {
          return;
        }
        done = true;
        handle.removeInterrupt(interruptFn);
        reject(e);
      });
    });
  }

  /** 服务端是否判定 file_id 失效 */
  private static isFileInvalidError(err: ApiError): boolean {
    const msg = err.message.toLowerCase();
    return msg.indexOf('file_id') >= 0 || msg.indexOf('file-id') >= 0
      || msg.indexOf('file not found') >= 0 || msg.indexOf('invalid file') >= 0;
  }

  /** 从报错文案提取被点名的 file_id */
  private static extractFileIds(message: string): string[] {
    const out: string[] = [];
    const found = message.match(/file-[0-9a-zA-Z]{10,}/g);
    if (found !== null) {
      for (const f of found) {
        out.push(f);
      }
    }
    return out;
  }

  /**
   * 服务端判定 file_id 失效时清掉对应附件的 serverId，下一次补传会重新上传。
   * 报错里点名了 file_id 就只重置这些；没点名则重置本次请求用到的全部附件。
   */
  private static reuploadInvalidatedFiles(store: ChatStore, session: Session, plan: StreamPlan, err: ApiError): boolean {
    if (!ReplyEngine.isFileInvalidError(err)) {
      return false;
    }
    const targets: Set<string> = new Set();
    const mentioned = ReplyEngine.extractFileIds(err.message);
    if (mentioned.length > 0) {
      for (const id of mentioned) {
        targets.add(id);
      }
    } else {
      const foundQuestion = store.findMessage(session, plan.questionId);
      if (foundQuestion !== null && isUser(foundQuestion)) {
        for (const f of (foundQuestion as UserMessage).files) {
          if (f.serverId !== null) {
            targets.add(f.serverId);
          }
        }
      }
      const rounds = RequestBodyBuilder.getContextRounds(plan.history);
      for (const round of rounds) {
        const found = store.findMessage(session, round.user.id);
        if (found === null || !isUser(found)) {
          continue;
        }
        for (const f of (found as UserMessage).files) {
          if (f.serverId !== null) {
            targets.add(f.serverId);
          }
        }
      }
    }
    if (targets.size === 0) {
      return false;
    }
    let changed = false;
    for (const m of session.messages) {
      if (!isUser(m)) {
        continue;
      }
      const um = m as UserMessage;
      let msgChanged = false;
      for (const f of um.files) {
        if (f.serverId !== null && targets.has(f.serverId)) {
          f.serverId = null;
          f.uploadStatus = 'local';
          msgChanged = true;
        }
      }
      if (msgChanged) {
        changed = true;
        store.persistMessageSafe(session, um);
      }
    }
    return changed;
  }

  /** 重传前的退避等待；停止生成时立即返回，由调用方按已停止收尾 */
  private static waitForRetry(attempt: number, handle: RunHandle): Promise<void> {
    return new Promise<void>((resolve) => {
      let done = false;
      const interruptFn = (): void => {
        if (done) {
          return;
        }
        done = true;
        clearTimeout(timerId);
        resolve();
      };
      const timerId = setTimeout((): void => {
        if (done) {
          return;
        }
        done = true;
        handle.removeInterrupt(interruptFn);
        resolve();
      }, FILE_RETRY_BASE_DELAY * Math.pow(2, attempt));
      handle.onInterrupt(interruptFn);
    });
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

    // 自动标题：仅无标题会话、本流尚未生成过标题
    if (event.type === 'message_delta' && event.title !== null && event.title.trim() !== ''
      && pending.wantTitle && session.title === '') {
      store.setSessionTitleIfEmpty(sessionId, event.title.trim());
      pending.wantTitle = false;
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
      pending.receivedContent = true;
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
        rb.toolPart.rawJson = block.rawJson;
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
      store.notifyStreamTick(); // 新块入列：列表跟随最新内容
      ReplyEngine.scheduleStreamPersist(sessionId);
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
      store.notifyStreamTick(); // 内容增长：列表粘底跟随
      ReplyEngine.scheduleStreamPersist(sessionId);
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
      ReplyEngine.scheduleStreamPersist(sessionId);
      return;
    }
  }

  /** 流式过程节流落盘：进程被杀最多丢一个节流窗口的内容 */
  private static scheduleStreamPersist(sessionId: string): void {
    const now = Date.now();
    const last = ReplyEngine.lastStreamPersist.get(sessionId);
    if (last !== undefined && now - last < STREAM_PERSIST_INTERVAL_MS) {
      return;
    }
    ReplyEngine.lastStreamPersist.set(sessionId, now);
    ReplyEngine.flushStreamPersist(sessionId);
  }

  /** 立即落盘当前流式回复 */
  private static flushStreamPersist(sessionId: string): void {
    const store = ChatStore.get();
    const session = store.sessionById(sessionId);
    const pending = ReplyEngine.pending.get(sessionId);
    if (session === null || pending === undefined) {
      return;
    }
    const found = store.findMessage(session, pending.assistantId);
    if (found !== null) {
      store.persistMessageSafe(session, found);
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
