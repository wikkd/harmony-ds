import { AssistantMessage, Message, Session, UserMessage, isAssistant } from '../../model/ChatTypes';
import { ChatDb } from '../db/ChatDb';
import { Id } from '../../common/Format';
import { I18n } from '../../common/I18n';
import { Logger } from '../../common/Logger';
import { AppContextHolder } from '../../common/AppContextHolder';

/**
 * 会话状态（M3）：RelationalStore 持久化 + 分支树。
 * session.messages 保存全部分支消息（创建顺序）；visibleMessages() 沿
 * selectedChildId 计算当前可见链。列表页只放摘要，消息懒加载。
 */
@ObservedV2
export class ChatStore {
  private static instance?: ChatStore;

  @Trace sessions: Session[] = [];
  @Trace currentSessionId: string = '';
  /** 正在流式回复的会话 id；null 表示空闲 */
  @Trace streamingSessionId: string | null = null;
  /** 当前会话可见链版本号：切换会话/切分支时自增驱动列表刷新 */
  @Trace visibleVersion: number = 0;
  /** 当前可见链（由 visibleVersion 驱动重算） */
  @Trace visible: Message[] = [];

  private ready: boolean = false;
  private loadedSessions: Set<string> = new Set();

  private constructor() {
  }

  static get(): ChatStore {
    if (!ChatStore.instance) {
      ChatStore.instance = new ChatStore();
    }
    return ChatStore.instance;
  }

  /** Ability onCreate 调用：初始化 DB 并恢复会话列表 */
  async restore(): Promise<void> {
    if (this.ready) {
      return;
    }
    try {
      await ChatDb.init(AppContextHolder.get());
      this.sessions = await ChatDb.loadSessionList();
      this.ready = true;
      if (this.sessions.length > 0) {
        await this.switchTo(this.sessions[0].id);
      } else {
        await this.newSession();
      }
      Logger.info('ChatStore', `restored ${this.sessions.length} sessions`);
    } catch (err) {
      Logger.error('ChatStore', `restore failed: ${JSON.stringify(err)}`);
      this.ready = true;
      await this.newSession();
    }
  }

  /** 流式状态统一入口：同步 AppStorage 供 V1 组件读取 */
  setStreaming(id: string | null): void {
    this.streamingSessionId = id;
    AppStorage.setOrCreate<string>('streamingId', id ?? '');
  }

  sessionById(id: string): Session | null {
    for (const s of this.sessions) {
      if (s.id === id) {
        return s;
      }
    }
    return null;
  }

  current(): Session {
    const s = this.sessionById(this.currentSessionId);
    if (s !== null) {
      return s;
    }
    // 同步兜底：恢复在异步中，首次渲染可能还没有会话
    const created = new Session(Id.next(), Date.now());
    this.sessions.unshift(created);
    this.currentSessionId = created.id;
    ChatDb.upsertSession(created).catch(() => {});
    return created;
  }

  /** 懒加载会话消息并计算可见链 */
  async switchTo(id: string): Promise<void> {
    this.currentSessionId = id;
    const s = this.sessionById(id);
    if (s === null) {
      return;
    }
    if (!this.loadedSessions.has(id)) {
      s.messages = await ChatDb.loadMessages(id);
      this.loadedSessions.add(id);
    }
    this.recomputeVisible(s);
    this.visibleVersion++;
  }

  /** 新建会话（有未命名空会话时直接复用） */
  async newSession(): Promise<Session> {
    if (this.currentSessionId !== '') {
      const cur = this.sessionById(this.currentSessionId);
      if (cur !== null && cur.title === '' && cur.messages.length === 0) {
        await this.switchTo(cur.id);
        return cur;
      }
    }
    const now = Date.now();
    const s = new Session(Id.next(), now);
    this.sessions.unshift(s);
    this.currentSessionId = s.id;
    this.loadedSessions.add(s.id);
    this.recomputeVisible(s);
    this.visibleVersion++;
    await ChatDb.upsertSession(s);
    return s;
  }

  async renameSession(id: string, title: string): Promise<void> {
    const s = this.sessionById(id);
    if (s === null) {
      return;
    }
    s.title = title.trim();
    s.updatedAt = Date.now();
    await ChatDb.updateSessionMeta(s);
  }

  async deleteSession(id: string): Promise<void> {
    const abortInStream = this.streamingSessionId === id;
    if (abortInStream) {
      this.setStreaming(null);
    }
    const idx = this.sessions.findIndex((s) => s.id === id);
    if (idx >= 0) {
      this.sessions.splice(idx, 1);
    }
    this.loadedSessions.delete(id);
    await ChatDb.deleteSession(id);
    if (this.currentSessionId === id) {
      if (this.sessions.length > 0) {
        await this.switchTo(this.sessions[0].id);
      } else {
        await this.newSession();
      }
    }
  }

  async deleteAll(): Promise<void> {
    this.setStreaming(null);
    this.sessions = [];
    this.loadedSessions.clear();
    this.visible = [];
    await ChatDb.deleteAllSessions();
    await this.newSession();
  }

  /** 会话无标题时用自动标题 */
  async setSessionTitleIfEmpty(sessionId: string, title: string): Promise<void> {
    const s = this.sessionById(sessionId);
    if (s !== null && s.title === '' && title.trim() !== '') {
      s.title = title.trim();
      s.updatedAt = Date.now();
      await ChatDb.updateSessionMeta(s);
    }
  }

  displayTitle(s: Session): string {
    return s.title !== '' ? s.title : I18n.translate('untitledChat');
  }

  // ---------- 消息树 ----------

  appendUserMessage(session: Session, text: string, parentId: string | null): UserMessage {
    const m = new UserMessage(Id.next(), text, Date.now());
    m.parentId = parentId;
    session.messages.push(m);
    session.updatedAt = Date.now();
    if (parentId === null) {
      session.rootMessageId = m.id;
    } else {
      const parent = this.findMessage(session, parentId);
      if (parent !== null) {
        parent.selectedChildId = m.id;
      }
    }
    return m;
  }

  appendAssistantPlaceholder(session: Session, parentId: string, thinking: boolean, search: boolean): AssistantMessage {
    const m = new AssistantMessage(Id.next(), Date.now());
    m.parentId = parentId;
    m.thinking = thinking;
    m.search = search;
    const parent = this.findMessage(session, parentId);
    if (parent !== null) {
      parent.selectedChildId = m.id;
    }
    session.messages.push(m);
    session.updatedAt = Date.now();
    return m;
  }

  findMessage(session: Session, id: string): Message | null {
    for (const m of session.messages) {
      if (m.id === id) {
        return m;
      }
    }
    return null;
  }

  /** 会话的根消息：优先 rootMessageId，否则取最早的 parentId 为空的消息 */
  rootOf(session: Session): Message | null {
    if (session.rootMessageId !== null) {
      const root = this.findMessage(session, session.rootMessageId);
      if (root !== null) {
        return root;
      }
    }
    let root: Message | null = null;
    for (const m of session.messages) {
      if (m.parentId === null && (root === null || m.createdAt < (root as Message).createdAt)) {
        root = m;
      }
    }
    return root;
  }

  /** 沿 selectedChildId 计算当前可见链 */
  recomputeVisible(session: Session): void {
    const out: Message[] = [];
    let cur = this.rootOf(session);
    let guard = 0;
    while (cur !== null && guard < 10000) {
      out.push(cur);
      guard++;
      if (cur.selectedChildId === null) {
        break;
      }
      const next = this.findMessage(session, cur.selectedChildId);
      cur = next;
    }
    this.visible = out;
  }

  /** 同态刷新：追加消息后调用（轻量重算 + 版本自增） */
  refreshVisible(session: Session): void {
    this.recomputeVisible(session);
    this.visibleVersion++;
  }

  /** 兄弟节点（同 parentId 的消息），用于版本切换计数 */
  siblingsOf(session: Session, m: Message): Message[] {
    const out: Message[] = [];
    for (const other of session.messages) {
      if (other.parentId === m.parentId && other.role === m.role) {
        out.push(other);
      }
    }
    return out;
  }

  /** 切换到指定消息的上一/下一版本，返回是否切换成功 */
  async switchVersion(sessionId: string, m: Message, direction: number): Promise<boolean> {
    const session = this.sessionById(sessionId);
    if (session === null) {
      return false;
    }
    const siblings = this.siblingsOf(session, m);
    if (siblings.length <= 1) {
      return false;
    }
    let idx = -1;
    for (let i = 0; i < siblings.length; i++) {
      if (siblings[i].id === m.id) {
        idx = i;
        break;
      }
    }
    const target = idx + direction;
    if (target < 0 || target >= siblings.length) {
      return false;
    }
    const parent = m.parentId === null ? null : this.findMessage(session, m.parentId);
    if (parent !== null) {
      parent.selectedChildId = siblings[target].id;
    } else {
      // 根级别：换 root
      session.rootMessageId = siblings[target].id;
      await ChatDb.updateSessionMeta(session);
    }
    if (parent !== null) {
      const seq = session.messages.length;
      await ChatDb.updateMessage(sessionId, seq, parent);
    }
    this.recomputeVisible(session);
    this.visibleVersion++;
    return true;
  }

  /** 导入完成后重建本地状态 */
  async reloadAfterImport(): Promise<void> {
    this.setStreaming(null);
    this.sessions = [];
    this.loadedSessions.clear();
    this.visible = [];
    this.ready = false;
    await this.restore();
  }

  /** 持久化一条消息（upsert） */
  async persistMessage(session: Session, m: Message): Promise<void> {
    await ChatDb.updateMessage(session.id, session.messages.length, m);
    await ChatDb.updateSessionMeta(session);
  }

  /** 持久化会话元数据 */
  async persistSessionMeta(session: Session): Promise<void> {
    await ChatDb.updateSessionMeta(session);
  }
}
