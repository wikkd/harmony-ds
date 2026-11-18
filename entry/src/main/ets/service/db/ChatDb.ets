import { relationalStore } from '@kit.ArkData';
import { Context } from '@kit.AbilityKit';
import {
  AssistantMessage,
  FileAttachment,
  Message,
  ReplyBlock,
  ReplyError,
  ReplyStatus,
  ServerToolPart,
  Session,
  TextPart,
  ThinkingPart,
  UserMessage,
} from '../../model/ChatTypes';
import { MessageUsage, StopReason, TextCitation } from '../../model/ApiTypes';
import { ApiErrorKind } from '../api/ApiError';
import { Logger } from '../../common/Logger';

const TAG: string = 'ChatDb';
const DB_NAME: string = 'chat.db';
/** schema 版本：结构变更时递增并在启动时迁移 */
const SCHEMA_VERSION: number = 2;

/**
 * RelationalStore 持久层：
 * - sessions(id,title,createdAt,updatedAt,rootMessageId)
 * - messages(id,sessionId,seq,role,parentId,selectedChildId,payloadJson)
 *   user 的 payloadJson={content,files}；assistant 的为 blocks/status 等完整快照
 */
export class ChatDb {
  private static store?: relationalStore.RdbStore;

  static async init(context: Context): Promise<void> {
    if (ChatDb.store !== undefined) {
      return;
    }
    const config: relationalStore.StoreConfig = {
      name: DB_NAME,
      securityLevel: relationalStore.SecurityLevel.S1,
    };
    const store = await relationalStore.getRdbStore(context, config);
    await store.executeSql(
      `CREATE TABLE IF NOT EXISTS sessions (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL DEFAULT '',
        createdAt INTEGER NOT NULL,
        updatedAt INTEGER NOT NULL,
        rootMessageId TEXT,
        compactAnchorId TEXT,
        compactSummary TEXT
      )`);
    await store.executeSql(
      `CREATE TABLE IF NOT EXISTS messages (
        id TEXT PRIMARY KEY,
        sessionId TEXT NOT NULL,
        seq INTEGER NOT NULL,
        role TEXT NOT NULL,
        parentId TEXT,
        selectedChildId TEXT,
        payloadJson TEXT NOT NULL
      )`);
    await store.executeSql(`CREATE INDEX IF NOT EXISTS idx_messages_session ON messages(sessionId, seq)`);
    // 迁移：v1 库补 compact 两列（列已存在则忽略）
    let version = 0;
    const vrs = await store.querySql('PRAGMA user_version');
    if (vrs.goToFirstRow()) {
      version = vrs.getLong(0);
    }
    vrs.close();
    if (version < 2) {
      try {
        await store.executeSql('ALTER TABLE sessions ADD COLUMN compactAnchorId TEXT');
      } catch (e) {
        // 列已存在
      }
      try {
        await store.executeSql('ALTER TABLE sessions ADD COLUMN compactSummary TEXT');
      } catch (e) {
        // 列已存在
      }
    }
    await store.executeSql(`PRAGMA user_version = ${SCHEMA_VERSION}`);
    ChatDb.store = store;
    Logger.info(TAG, 'db ready');
  }

  private static db(): relationalStore.RdbStore {
    if (ChatDb.store === undefined) {
      throw new Error('ChatDb not initialized');
    }
    return ChatDb.store;
  }

  // ---------- sessions ----------

  private static sessionBucket(s: Session): relationalStore.ValuesBucket {
    return {
      'id': s.id,
      'title': s.title,
      'createdAt': s.createdAt,
      'updatedAt': s.updatedAt,
      'rootMessageId': s.rootMessageId ?? '',
    };
  }

  static async upsertSession(s: Session): Promise<void> {
    await ChatDb.db().insert('sessions', ChatDb.sessionBucket(s));
  }

  static async updateSessionMeta(s: Session): Promise<void> {
    const db = ChatDb.db();
    const bucket: relationalStore.ValuesBucket = {
      'title': s.title,
      'updatedAt': s.updatedAt,
      // 根级分支切换/编辑首条消息会改 rootMessageId，必须一并落盘
      'rootMessageId': s.rootMessageId ?? '',
      'compactAnchorId': s.compactAnchorId,
      'compactSummary': s.compactSummary,
    };
    const predicates = new relationalStore.RdbPredicates('sessions');
    predicates.equalTo('id', s.id);
    await db.update(bucket, predicates);
  }

  static async deleteSession(id: string): Promise<void> {
    const db = ChatDb.db();
    const pMsg = new relationalStore.RdbPredicates('messages');
    pMsg.equalTo('sessionId', id);
    await db.delete(pMsg);
    const pSes = new relationalStore.RdbPredicates('sessions');
    pSes.equalTo('id', id);
    await db.delete(pSes);
  }

  static async deleteAllSessions(): Promise<void> {
    const db = ChatDb.db();
    await db.delete(new relationalStore.RdbPredicates('messages'));
    await db.delete(new relationalStore.RdbPredicates('sessions'));
  }

  /** 会话摘要列表（updatedAt 倒序），不含消息 */
  /** 全部 assistant 消息 payloadJson（用量统计用） */
  static async assistantPayloads(): Promise<string[]> {
    if (ChatDb.store === undefined) {
      return [];
    }
    const p = new relationalStore.RdbPredicates('messages');
    p.equalTo('role', 'assistant');
    const rs = await ChatDb.store.query(p, ['payloadJson']);
    const out: string[] = [];
    while (rs.goToNextRow()) {
      out.push(rs.getString(rs.getColumnIndex('payloadJson')));
    }
    rs.close();
    return out;
  }

  static async loadSessionList(): Promise<Session[]> {
    const db = ChatDb.db();
    const p = new relationalStore.RdbPredicates('sessions');
    p.orderByDesc('updatedAt');
    const rs = await db.query(p);
    const out: Session[] = [];
    while (rs.goToNextRow()) {
      const s = new Session(rs.getString(rs.getColumnIndex('id')), rs.getLong(rs.getColumnIndex('createdAt')));
      s.title = rs.getString(rs.getColumnIndex('title'));
      s.updatedAt = rs.getLong(rs.getColumnIndex('updatedAt'));
      const root = rs.getString(rs.getColumnIndex('rootMessageId'));
      s.rootMessageId = root === null || root === '' ? null : root;
      const anchor = rs.getString(rs.getColumnIndex('compactAnchorId'));
      s.compactAnchorId = anchor === null ? '' : anchor;
      const summary = rs.getString(rs.getColumnIndex('compactSummary'));
      s.compactSummary = summary === null ? '' : summary;
      out.push(s);
    }
    rs.close();
    return out;
  }

  /** 加载会话全部消息（含分支，按 seq 排序） */
  static async loadMessages(sessionId: string): Promise<Message[]> {
    const db = ChatDb.db();
    const p = new relationalStore.RdbPredicates('messages');
    p.equalTo('sessionId', sessionId).orderByAsc('seq');
    const rs = await db.query(p);
    const out: Message[] = [];
    while (rs.goToNextRow()) {
      const role = rs.getString(rs.getColumnIndex('role'));
      const id = rs.getString(rs.getColumnIndex('id'));
      const parentId = rs.getString(rs.getColumnIndex('parentId'));
      const selectedChildId = rs.getString(rs.getColumnIndex('selectedChildId'));
      const payload = rs.getString(rs.getColumnIndex('payloadJson'));
      try {
        const obj: Record<string, Object> = JSON.parse(payload) as Record<string, Object>;
        if (role === 'user') {
          const um = ChatDb.userFromJson(id, obj);
          um.parentId = parentId === '' ? null : parentId;
          um.selectedChildId = selectedChildId === '' ? null : selectedChildId;
          out.push(um);
        } else {
          const am = ChatDb.assistantFromJson(id, obj);
          am.parentId = parentId === '' ? null : parentId;
          am.selectedChildId = selectedChildId === '' ? null : selectedChildId;
          out.push(am);
        }
      } catch (e) {
        Logger.warn(TAG, `skip broken message ${id}`);
      }
    }
    rs.close();
    return out;
  }

  // ---------- messages ----------

  private static messageBucket(sessionId: string, seq: number, m: Message): relationalStore.ValuesBucket {
    return {
      'id': m.id,
      'sessionId': sessionId,
      'seq': seq,
      'role': m.role,
      'parentId': m.parentId ?? '',
      'selectedChildId': m.selectedChildId ?? '',
      'payloadJson': m.role === 'user' ? ChatDb.userToJson(m as UserMessage) : ChatDb.assistantToJson(m as AssistantMessage),
    };
  }

  static async upsertMessage(sessionId: string, seq: number, m: Message): Promise<void> {
    await ChatDb.db().insert('messages', ChatDb.messageBucket(sessionId, seq, m));
  }

  /** 原子替换全部会话（历史导入用）：任何一步失败都回滚，保留原数据 */
  static async replaceAllSessions(sessions: Session[]): Promise<void> {
    const db = ChatDb.db();
    const tx = await db.createTransaction();
    try {
      await tx.delete(new relationalStore.RdbPredicates('messages'));
      await tx.delete(new relationalStore.RdbPredicates('sessions'));
      for (const s of sessions) {
        await tx.insert('sessions', ChatDb.sessionBucket(s));
        for (let i = 0; i < s.messages.length; i++) {
          await tx.insert('messages', ChatDb.messageBucket(s.id, i, s.messages[i]));
        }
      }
      await tx.commit();
    } catch (err) {
      try {
        await tx.rollback();
      } catch (e) {
        // 回滚失败时保留原始错误
      }
      throw err as Error;
    }
  }

  static async updateMessage(sessionId: string, seq: number, m: Message): Promise<void> {
    const db = ChatDb.db();
    const bucket: relationalStore.ValuesBucket = {
      'selectedChildId': m.selectedChildId ?? '',
      'payloadJson': m.role === 'user' ? ChatDb.userToJson(m as UserMessage) : ChatDb.assistantToJson(m as AssistantMessage),
    };
    const p = new relationalStore.RdbPredicates('messages');
    p.equalTo('id', m.id).and().equalTo('sessionId', sessionId);
    const rows = await db.update(bucket, p);
    if (rows === 0) {
      await ChatDb.upsertMessage(sessionId, seq, m);
    }
  }

  // ---------- 序列化 ----------

  private static userToJson(m: UserMessage): string {
    const files: Array<Object> = [];
    for (const f of m.files) {
      const fo: Record<string, Object> = {
        'id': f.id, 'serverId': f.serverId ?? '', 'name': f.name, 'size': f.size,
        'isImage': f.isImage, 'mimeType': f.mimeType,
      };
      files.push(fo);
    }
    const obj: Record<string, Object> = {
      'content': m.content,
      'files': files,
      'createdAt': m.createdAt,
    };
    return JSON.stringify(obj);
  }

  private static userFromJson(id: string, obj: Record<string, Object>): UserMessage {
    const m = new UserMessage(id, (obj['content'] as string) ?? '', (obj['createdAt'] as number) ?? Date.now());
    const files = obj['files'];
    if (files instanceof Array) {
      for (const fo of files as Array<Object>) {
        const f = fo as Record<string, Object>;
        const a = new FileAttachment();
        a.id = (f['id'] as string) ?? '';
        a.serverId = (f['serverId'] as string) === '' ? null : (f['serverId'] as string) ?? null;
        a.name = (f['name'] as string) ?? '';
        a.size = (f['size'] as number) ?? 0;
        a.isImage = (f['isImage'] as boolean) ?? false;
        a.mimeType = (f['mimeType'] as string) ?? '';
        m.files.push(a);
      }
    }
    return m;
  }

  private static assistantToJson(m: AssistantMessage): string {
    const blocks: Array<Object> = [];
    for (const b of m.blocks) {
      if (b.type === 'text') {
        const citations: Array<Object> = [];
        for (const c of b.textPart.citations) {
          const co: Record<string, Object> = {
            'url': c.url, 'title': c.title ?? '', 'citedText': c.citedText,
          };
          citations.push(co);
        }
        const bo: Record<string, Object> = {
          'type': 'text', 'text': b.textPart.text, 'isTemplate': b.textPart.isTemplate,
          'citations': citations,
        };
        blocks.push(bo);
      } else if (b.type === 'thinking') {
        const bo: Record<string, Object> = {
          'type': 'thinking', 'thinking': b.thinkingPart.thinking, 'signature': b.thinkingPart.signature,
          'startedAt': b.thinkingPart.startedAt, 'endedAt': b.thinkingPart.endedAt,
        };
        blocks.push(bo);
      } else {
        const bo: Record<string, Object> = {
          'type': 'tool', 'toolJson': JSON.stringify(b.toolPart),
        };
        blocks.push(bo);
      }
    }
    const errObj: Record<string, Object> | null = m.error === null ? null : {
      'kind': m.error.kind, 'message': m.error.message, 'status': m.error.status ?? 0,
    };
    const obj: Record<string, Object> = {
      'createdAt': m.createdAt,
      'model': m.model ?? '',
      'thinking': m.thinking,
      'search': m.search,
      'latestReminder': m.latestReminder,
      'prefix': m.prefix,
      'status': m.status,
      'blocks': blocks,
      'stopReason': m.stopReason ?? '',
      'usage': m.usage === null ? '' : JSON.stringify(m.usage),
    };
    if (errObj !== null) {
      obj['error'] = errObj;
    }
    return JSON.stringify(obj);
  }

  private static assistantFromJson(id: string, obj: Record<string, Object>): AssistantMessage {
    const m = new AssistantMessage(id, (obj['createdAt'] as number) ?? Date.now());
    m.model = (obj['model'] as string) === '' ? null : (obj['model'] as string) ?? null;
    m.thinking = (obj['thinking'] as boolean) ?? false;
    m.search = (obj['search'] as boolean) ?? false;
    m.latestReminder = (obj['latestReminder'] as string) ?? '';
    m.prefix = (obj['prefix'] as boolean) ?? true;
    m.status = ((obj['status'] as string) ?? 'done') as ReplyStatus;
    const sr = (obj['stopReason'] as string) ?? '';
    m.stopReason = sr === '' ? null : (sr as StopReason);
    const usageStr = obj['usage'];
    if (typeof usageStr === 'string' && usageStr !== '') {
      try {
        m.usage = JSON.parse(usageStr) as MessageUsage;
      } catch (e) {
        m.usage = null;
      }
    }
    const err = obj['error'];
    if (err !== null && err !== undefined && typeof err === 'object') {
      const er = err as Record<string, Object>;
      const re = new ReplyError();
      re.kind = ((er['kind'] as string) ?? 'network') as ApiErrorKind | 'upload';
      re.message = (er['message'] as string) ?? '';
      re.status = (er['status'] as number) || undefined;
      m.error = re;
    }
    const blocks = obj['blocks'];
    if (blocks instanceof Array) {
      for (const bo of blocks as Array<Object>) {
        const b = bo as Record<string, Object>;
        const rb = new ReplyBlock();
        const type = (b['type'] as string) ?? 'text';
        if (type === 'text') {
          rb.type = 'text';
          rb.textPart = new TextPart();
          rb.textPart.text = (b['text'] as string) ?? '';
          rb.textPart.isTemplate = (b['isTemplate'] as boolean) ?? false;
          const citations = b['citations'];
          if (citations instanceof Array) {
            for (const co of citations as Array<Object>) {
              const c = co as Record<string, Object>;
              const tc = new TextCitation();
              tc.url = (c['url'] as string) ?? '';
              tc.title = (c['title'] as string) === '' ? null : (c['title'] as string) ?? null;
              tc.citedText = (c['citedText'] as string) ?? '';
              rb.textPart.citations.push(tc);
            }
          }
        } else if (type === 'thinking') {
          rb.type = 'thinking';
          rb.thinkingPart = new ThinkingPart();
          rb.thinkingPart.thinking = (b['thinking'] as string) ?? '';
          rb.thinkingPart.signature = (b['signature'] as string) ?? '';
          rb.thinkingPart.startedAt = (b['startedAt'] as number) ?? 0;
          rb.thinkingPart.endedAt = (b['endedAt'] as number) ?? 0;
        } else {
          rb.type = 'tool';
          rb.toolPart = new ServerToolPart();
          try {
            const toolJson = (b['toolJson'] as string) ?? '';
            if (toolJson !== '') {
              rb.toolPart = JSON.parse(toolJson) as ServerToolPart;
            }
          } catch (e) {
            // 跳过损坏的工具块
          }
        }
        m.blocks.push(rb);
      }
    }
    return m;
  }
}
