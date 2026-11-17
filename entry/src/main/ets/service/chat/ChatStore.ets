import { AssistantMessage, Message, Session, UserMessage } from '../../model/ChatTypes';
import { Id } from '../../common/Format';
import { I18n } from '../../common/I18n';

/**
 * 会话内存状态（M2）。
 * M3 换 RelationalStore 持久化 + 多会话；接口保持稳定。
 */
@ObservedV2
export class ChatStore {
  private static instance?: ChatStore;

  @Trace sessions: Session[] = [];
  @Trace currentSessionId: string = '';
  /** 正在流式回复的会话 id；null 表示空闲 */
  @Trace streamingSessionId: string | null = null;

  private constructor() {
    this.newSession();
  }

  /** 流式状态统一入口：同步 AppStorage 供 V1 组件读取 */
  setStreaming(id: string | null): void {
    this.streamingSessionId = id;
    AppStorage.setOrCreate<string>('streamingId', id ?? '');
  }

  static get(): ChatStore {
    if (!ChatStore.instance) {
      ChatStore.instance = new ChatStore();
    }
    return ChatStore.instance;
  }

  newSession(): Session {
    const now = Date.now();
    const s = new Session(Id.next(), now);
    s.title = '';
    this.sessions.unshift(s);
    this.currentSessionId = s.id;
    return s;
  }

  current(): Session {
    for (const s of this.sessions) {
      if (s.id === this.currentSessionId) {
        return s;
      }
    }
    // 兜底：重建一个
    return this.newSession();
  }

  sessionById(id: string): Session | null {
    for (const s of this.sessions) {
      if (s.id === id) {
        return s;
      }
    }
    return null;
  }

  removeSession(id: string): void {
    const idx = this.sessions.findIndex((s) => s.id === id);
    if (idx >= 0) {
      this.sessions.splice(idx, 1);
    }
    if (this.currentSessionId === id && this.sessions.length > 0) {
      this.currentSessionId = this.sessions[0].id;
    }
  }

  /** 会话无标题时用自动标题；仍无则显示「新对话」 */
  setSessionTitleIfEmpty(sessionId: string, title: string): void {
    const s = this.sessionById(sessionId);
    if (s !== null && s.title === '' && title.trim() !== '') {
      s.title = title.trim();
    }
  }

  displayTitle(s: Session): string {
    return s.title !== '' ? s.title : I18n.translate('untitledChat');
  }

  appendUserMessage(session: Session, text: string): UserMessage {
    const m = new UserMessage(Id.next(), text, Date.now());
    session.messages.push(m);
    session.updatedAt = Date.now();
    return m;
  }

  appendAssistantPlaceholder(session: Session, thinking: boolean, search: boolean): AssistantMessage {
    const m = new AssistantMessage(Id.next(), Date.now());
    m.thinking = thinking;
    m.search = search;
    session.messages.push(m);
    session.updatedAt = Date.now();
    return m;
  }

  /** 停止后刷新一条消息（触发列表重排） */
  touchSession(session: Session): void {
    session.updatedAt = Date.now();
  }

  findMessage(session: Session, id: string): Message | null {
    for (const m of session.messages) {
      if (m.id === id) {
        return m;
      }
    }
    return null;
  }
}
