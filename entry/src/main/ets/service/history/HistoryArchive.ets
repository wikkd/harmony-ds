import zlib from '@ohos.zlib';
import fs from '@ohos.file.fs';
import { AppContextHolder } from '../../common/AppContextHolder';
import { Logger } from '../../common/Logger';
import { ChatDb } from '../db/ChatDb';
import {
  AssistantMessage,
  FileAttachment,
  Message,
  ReplyBlock,
  ReplyError,
  ServerToolPart,
  Session,
  TextPart,
  ThinkingPart,
  UserMessage,
} from '../../model/ChatTypes';
import { MessageUsage, ProtocolFetchResultBlock, ProtocolSearchResultBlock, StopReason, TextCitation } from '../../model/ApiTypes';
import { Id } from '../../common/Format';

const TAG: string = 'HistoryArchive';

/** 导出 JSON 对象：可空字段需显式 null（web 校验要求） */
type J = Record<string, Object | null>;
/** 与 DeepSeek web 导出互通的格式版本 */
const EXPORT_FORMAT_VERSION: number = 3;

export class ArchiveError extends Error {
  key: string;

  constructor(key: string) {
    super(key);
    this.key = key;
  }
}

/**
 * 历史导入导出（ZIP v3，对齐官方 chat_sessions/{id}.json + manifest + index 结构）。
 * 导入支持 DeepSeek 官方导出文件：新版来源协议（TOOL_SEARCH/TOOL_OPEN）还原为文本块引用，
 * 与直播 citations_delta 落点一致；导出可供 web 版导入（图片原件包含，API Key 排除）。
 */
export class HistoryArchive {
  // ---------- 导入 ----------

  /** 导入 ZIP（已拷贝到沙箱的路径），完全替换本地会话 */
  static async importZip(zipPath: string): Promise<number> {
    const context = AppContextHolder.get();
    const destDir = `${context.cacheDir}/import_${Date.now()}`;
    try {
      fs.mkdirSync(destDir, true);
      const options: zlib.Options = { level: 1 };
      await zlib.unzipFile(zipPath, destDir, options);
      // manifest 校验（首个条目约定，解压后直接读）
      const manifestPath = `${destDir}/manifest.json`;
      if (!fs.accessSync(manifestPath)) {
        throw new ArchiveError('backupUnrecognized');
      }
      const manifest = JSON.parse(fs.readTextSync(manifestPath)) as Record<string, Object>;
      const version = manifest['export_format_version'];
      if (typeof version !== 'number') {
        throw new ArchiveError('backupInvalidVersion');
      }
      if (version > EXPORT_FORMAT_VERSION) {
        throw new ArchiveError('backupNewerVersion');
      }
      if (version !== EXPORT_FORMAT_VERSION) {
        throw new ArchiveError('backupInvalidVersion');
      }
      // 会话索引
      const indexPath = `${destDir}/chat_session_index.json`;
      if (!fs.accessSync(indexPath)) {
        throw new ArchiveError('backupIncomplete');
      }
      const index = JSON.parse(fs.readTextSync(indexPath)) as Array<Object>;
      // 逐会话解析（先全部进内存，再一次性替换数据库）
      const sessionsDir = `${destDir}/chat_sessions`;
      const imported: Session[] = [];
      let processed = 0;
      for (const item of index) {
        const entry = item as Record<string, Object>;
        const sid = entry['id'];
        if (typeof sid !== 'string' || sid.includes('/') || sid.includes('\\') || sid === '') {
          throw new ArchiveError('backupIncomplete');
        }
        const jsonPath = `${sessionsDir}/${sid}.json`;
        if (!fs.accessSync(jsonPath)) {
          throw new ArchiveError('backupIncomplete');
        }
        const sessionFile = JSON.parse(fs.readTextSync(jsonPath)) as Record<string, Object>;
        const session = HistoryArchive.sessionFromArchive(sid, sessionFile, destDir);
        imported.push(session);
        // 大包（数百会话）逐个让出主线程，避免整段同步解析阻塞 UI
        if (++processed % 64 === 0) {
          await new Promise<void>((resolve: () => void) => setTimeout(resolve, 0));
        }
      }
      // 单事务替换：中途失败回滚，原会话与附件保持可用
      await ChatDb.replaceAllSessions(imported);
      Logger.info(TAG, `imported ${imported.length} sessions`);
      return imported.length;
    } finally {
      try {
        fs.rmdirSync(destDir);
      } catch (e) {
        // 忽略清理失败
      }
    }
  }

  // ---------- 导出 ----------

  /** 导出全部会话（含本地图片原件）到 ZIP，返回输出路径 */
  static async exportZip(): Promise<string> {
    const context = AppContextHolder.get();
    const workDir = `${context.cacheDir}/export_${Date.now()}`;
    fs.mkdirSync(`${workDir}/chat_sessions`, true);
    // manifest（首条目）
    const wf1 = fs.openSync(`${workDir}/manifest.json`, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    fs.writeSync(wf1.fd, JSON.stringify({ 'export_format_version': EXPORT_FORMAT_VERSION }));
    fs.closeSync(wf1);
    const index: Array<Object> = [];
    const sessions = await ChatDb.loadSessionList();
    for (const summary of sessions) {
      const messages = await ChatDb.loadMessages(summary.id);
      const session = summary;
      session.messages = messages;
      const fileMap: Map<string, string> = new Map(); // attId -> archive relative path
      // 会话 JSON
      const doc = HistoryArchive.sessionToArchive(session, fileMap);
      const wf2 = fs.openSync(`${workDir}/chat_sessions/${session.id}.json`, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    fs.writeSync(wf2.fd, JSON.stringify(doc));
    fs.closeSync(wf2);
      // 图片原件
      const filesDir = `${workDir}/chat_sessions/${session.id}_files`;
      for (const attId of fileMap.keys()) {
        const localPath = fileMap.get(attId) ?? '';
        if (localPath === '' || !fs.accessSync(localPath)) {
          continue;
        }
        fs.mkdirSync(filesDir, true);
        fs.copyFileSync(localPath, `${filesDir}/${attId}_${HistoryArchive.safeName(localPath)}`);
      }
      const entry: J = {
        'id': session.id,
        'title': session.title === '' ? null : session.title,
        'message_count': session.messages.length,
        'inserted_at': HistoryArchive.iso(session.createdAt),
        'updated_at': HistoryArchive.iso(session.updatedAt),
      };
      index.push(entry);
    }
    const wf3 = fs.openSync(`${workDir}/chat_session_index.json`, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    fs.writeSync(wf3.fd, JSON.stringify(index));
    fs.closeSync(wf3);
    // 打包（zipFile 压缩目录；秒级时间戳命名，避免同日重复导出撞已存在目标导致压缩失败）
    const outZip = `${context.filesDir}/deepseek_data-${HistoryArchive.dateStamp()}.zip`;
    try {
      fs.unlinkSync(outZip);
    } catch (e) {
      // 目标不存在属正常
    }
    const zipOptions: zlib.Options = { level: 0 };
    await zlib.zipFile(workDir, outZip, zipOptions);
    try {
      fs.rmdirSync(workDir);
    } catch (e) {
      // 忽略
    }
    Logger.info(TAG, `exported to ${outZip}`);
    return outZip;
  }

  // ---------- 归档 → 本地 ----------

  private static sessionFromArchive(sid: string, doc: Record<string, Object>, rootDir: string): Session {
    const messages = doc['messages'];
    if (!(messages instanceof Array)) {
      throw new ArchiveError('backupIncomplete');
    }
    const currentId = doc['current_message_id'];
    const title = doc['title'];
    const inserted = HistoryArchive.parseTime(doc['inserted_at']);
    const updated = HistoryArchive.parseTime(doc['updated_at']);
    const session = new Session(sid, inserted);
    session.updatedAt = updated;
    session.title = typeof title === 'string' ? title : '';
    // 转换全部消息（按 id 升序构建树）
    const locals: Message[] = [];
    const idMap: Map<number, string> = new Map();
    const arr = messages as Array<Object>;
    // 先排序（父 id 必须小于子 id）
    const sorted = arr.slice().sort((a, b) => HistoryArchive.msgId(a) - HistoryArchive.msgId(b));
    for (const m of sorted) {
      const rec = m as Record<string, Object>;
      const numericId = HistoryArchive.msgId(m);
      const parentId = rec['parent_id'];
      let parentLocalId: string | null = null;
      if (typeof parentId === 'number') {
        parentLocalId = idMap.get(parentId) ?? null;
      }
      const role = rec['role'];
      const converted = role === 'USER'
        ? HistoryArchive.userFromArchive(rec, numericId, parentLocalId, rootDir, sid)
        : HistoryArchive.assistantFromArchive(rec, numericId, parentLocalId);
      idMap.set(numericId, converted.id);
      locals.push(converted);
    }
    // 校验根为提问（容器级错误直接失败）
    if (locals.length > 0 && locals[0].role !== 'user') {
      throw new ArchiveError('backupInvalidBranches');
    }
    // 还原选中链：current_message_id 决定当前分支，其他节点默认最大子
    session.messages = locals;
    HistoryArchive.rebuildSelection(session, typeof currentId === 'number' ? currentId : null, idMap);
    return session;
  }

  private static msgId(m: Object): number {
    const rec = m as Record<string, Object>;
    const v = rec['id'];
    return typeof v === 'number' ? v : 0;
  }

  private static rebuildSelection(session: Session, currentId: number | null, idMap: Map<number, string>): void {
    // children 映射
    const children: Map<string, Message[]> = new Map();
    let root: Message | null = null;
    for (const m of session.messages) {
      if (m.parentId === null) {
        if (root === null) {
          root = m; // 多 root 异常包体：默认取最早的主链
        }
        continue;
      }
      const list = children.get(m.parentId) ?? [];
      list.push(m);
      children.set(m.parentId, list);
    }
    // 默认选最大 id（数组有序，取最后）
    for (const list of children.values()) {
      const parent = session.messages.find((m) => m.id === list[0].parentId);
      if (parent !== undefined) {
        parent.selectedChildId = list[list.length - 1].id;
      }
    }
    if (root !== null) {
      session.rootMessageId = root.id;
    }
    if (currentId !== null) {
      // 从 current 消息回溯路径，逐级把父的 selectedChildId 指向该路径
      const localId = idMap.get(currentId);
      let cur: Message | null = localId === undefined ? null : HistoryArchive.findLocal(session, localId);
      while (cur !== null && cur.parentId !== null) {
        const parent = HistoryArchive.findLocal(session, cur.parentId);
        if (parent === null) {
          break;
        }
        parent.selectedChildId = cur.id;
        cur = parent;
      }
      // 根取当前链顶端：current_message_id 所在分支才是用户正在看的会话
      if (cur !== null && cur.parentId === null) {
        session.rootMessageId = cur.id;
      }
    }
  }

  private static userFromArchive(rec: Record<string, Object>, numericId: number, parentId: string | null,
    rootDir: string, sessionId: string): UserMessage {
    const inserted = HistoryArchive.parseTime(rec['inserted_at']);
    let content = '';
    const files: FileAttachment[] = [];
    const fragments = rec['fragments'];
    if (fragments instanceof Array) {
      for (const f of fragments as Array<Object>) {
        const fr = f as Record<string, Object>;
        const type = fr['type'];
        if (type === 'REQUEST' && typeof fr['content'] === 'string') {
          content = fr['content'] as string;
        } else if (type === 'FILE') {
          const list = fr['files'];
          if (list instanceof Array) {
            for (const fo of list as Array<Object>) {
              const fe = fo as Record<string, Object>;
              const att = new FileAttachment();
              const fileId = typeof fe['id'] === 'string' ? fe['id'] as string : Id.next();
              att.id = fileId;
              att.serverId = null; // 导入附件首次使用时重新上传
              att.name = typeof fe['file_name'] === 'string' ? fe['file_name'] as string : 'file';
              att.size = typeof fe['file_size'] === 'number' ? fe['file_size'] as number : 0;
              att.isImage = fe['is_image'] === true;
              att.mimeType = '';
              // 图片原件（export_path 来自外部 ZIP，必须校验防目录穿越）
              const exportPath = typeof fe['export_path'] === 'string'
                ? HistoryArchive.safeArchivePath(fe['export_path'] as string) : null;
              if (att.isImage && exportPath !== null) {
                const localPath = `${rootDir}/${exportPath}`;
                try {
                  if (fs.accessSync(localPath)) {
                    const dst = `${AppContextHolder.get().cacheDir}/att_${Id.next()}_${HistoryArchive.safeFileName(att.name)}`;
                    fs.copyFileSync(localPath, dst);
                    att.localPath = dst;
                  }
                } catch (e) {
                  // 缺原件保留元数据
                }
              }
              files.push(att);
            }
          }
        }
      }
    }
    const m = new UserMessage(Id.next(), content, inserted);
    m.parentId = parentId;
    m.files = files;
    return m;
  }

  private static assistantFromArchive(rec: Record<string, Object>, numericId: number, parentId: string | null): AssistantMessage {
    const inserted = HistoryArchive.parseTime(rec['inserted_at']);
    const m = new AssistantMessage(Id.next(), inserted);
    m.parentId = parentId;
    m.thinking = rec['thinking_enabled'] === true;
    m.search = rec['search_enabled'] === true;
    m.latestReminder = '';
    m.prefix = false; // 导入的回复不能续写
    // 状态映射
    const status = rec['status'];
    const usageTotal = rec['accumulated_token_usage'];
    if (typeof usageTotal === 'number') {
      const usage = new MessageUsage();
      usage.outputTokens = usageTotal;
      m.usage = usage;
    }
    // 来源引用：TOOL_SEARCH/TOOL_OPEN（官方新版协议）→ 文本块 citations
    const citations: TextCitation[] = [];
    const seenUrls: Set<string> = new Set();
    const fragments = rec['fragments'];
    if (fragments instanceof Array) {
      for (const f of fragments as Array<Object>) {
        HistoryArchive.collectCitations(f, citations, seenUrls);
        const block = HistoryArchive.fragmentToBlock(f, inserted);
        if (block !== null) {
          m.blocks.push(block);
        }
      }
    }
    if (status === 'FINISHED') {
      m.status = 'done';
      m.stopReason = 'end_turn' as StopReason;
    } else if (status === 'CONTENT_FILTER') {
      m.status = 'done';
      m.stopReason = 'refusal' as StopReason;
      // 拒绝：丢弃普通正文与思考，仅保留模板
      const kept: ReplyBlock[] = [];
      for (const b of m.blocks) {
        if (b.type === 'text' && b.textPart.isTemplate) {
          kept.push(b);
        }
      }
      m.blocks = kept;
    } else if (status === 'INCOMPLETE' || status === 'WIP' || status === 'TIMEOUT' || status === 'CONTEXT_LENGTH_EXCEEDED') {
      // 超时/上下文截断：官方表现为模板提示的未完成回复，按手动停止处理而非错误
      m.status = 'stopped';
    } else {
      m.status = 'error';
      const re = new ReplyError();
      re.kind = 'stream';
      re.message = '';
      m.error = re;
    }
    HistoryArchive.attachCitations(m, citations);
    return m;
  }

  private static fragmentToBlock(f: Object, inserted: number): ReplyBlock | null {
    const fr = f as Record<string, Object>;
    const type = fr['type'];
    const rb = new ReplyBlock();
    if (type === 'RESPONSE') {
      rb.type = 'text';
      rb.textPart = new TextPart();
      rb.textPart.text = typeof fr['content'] === 'string' ? fr['content'] as string : '';
      return rb;
    }
    if (type === 'TEMPLATE_RESPONSE') {
      rb.type = 'text';
      rb.textPart = new TextPart();
      rb.textPart.text = typeof fr['content'] === 'string' ? fr['content'] as string : '';
      rb.textPart.isTemplate = true;
      return rb;
    }
    if (type === 'THINK') {
      rb.type = 'thinking';
      rb.thinkingPart = new ThinkingPart();
      rb.thinkingPart.thinking = typeof fr['content'] === 'string' ? fr['content'] as string : '';
      const elapsed = fr['elapsed_secs'];
      if (typeof elapsed === 'number' && elapsed > 0) {
        rb.thinkingPart.startedAt = inserted;
        rb.thinkingPart.endedAt = inserted + elapsed * 1000;
      }
      return rb;
    }
    if (type === 'READ_LINK') {
      rb.type = 'tool';
      rb.toolPart = new ServerToolPart();
      const block = new ProtocolFetchResultBlock();
      block.toolUseId = Id.next();
      block.kind = 'read_link';
      const results = fr['results'];
      if (results instanceof Array && (results as Array<Object>).length > 0) {
        const first = (results as Array<Object>)[0] as Record<string, Object>;
        block.signature = typeof first['signature'] === 'string' ? first['signature'] as string : '';
        block.url = typeof first['url'] === 'string' ? first['url'] as string : '';
        block.title = typeof first['title'] === 'string' ? first['title'] as string : null;
      }
      rb.toolPart.fetchResult = block;
      return rb;
    }
    // TOOL_OPEN 已在 collectCitations 转引用；TIP/CONTENT_RISK/PARTIAL_FILE_READ/TOOL_IMAGE_SEARCH/FILE 等无展示映射：丢弃
    return null;
  }

  /** TOOL_SEARCH.results / TOOL_OPEN（官方新版来源协议）→ 引用：同 URL 去重，无 URL 的占位条目丢弃 */
  private static collectCitations(f: Object, out: TextCitation[], seen: Set<string>): void {
    const fr = f as Record<string, Object>;
    const type = fr['type'];
    if (type !== 'TOOL_SEARCH' && type !== 'TOOL_OPEN') {
      return;
    }
    let entries: Array<Object> = [];
    if (type === 'TOOL_OPEN') {
      entries = [f];
    } else if (fr['results'] instanceof Array) {
      entries = fr['results'] as Array<Object>;
    }
    for (const e of entries) {
      const er = e as Record<string, Object>;
      const url = typeof er['url'] === 'string' ? er['url'] as string : '';
      if (url === '' || seen.has(url)) {
        continue;
      }
      seen.add(url);
      const c = new TextCitation();
      c.url = url;
      c.title = typeof er['title'] === 'string' && (er['title'] as string).length > 0 ? er['title'] as string : null;
      out.push(c);
    }
  }

  /** 引用挂到最末正文块（与直播 citations_delta 落点一致）；仅模板文本时挂模板块；无文本块丢弃 */
  private static attachCitations(m: AssistantMessage, citations: TextCitation[]): void {
    if (citations.length === 0) {
      return;
    }
    for (let i = m.blocks.length - 1; i >= 0; i--) {
      const b = m.blocks[i];
      if (b.type === 'text' && !b.textPart.isTemplate) {
        for (const c of citations) {
          b.textPart.citations.push(c);
        }
        return;
      }
    }
    for (const b of m.blocks) {
      if (b.type === 'text') {
        for (const c of citations) {
          b.textPart.citations.push(c);
        }
        return;
      }
    }
  }

  // ---------- 本地 → 归档 ----------

  private static sessionToArchive(session: Session, fileMap: Map<string, string>): J {
    const messages: Array<Object> = [];
    const numericIds: Map<string, number> = new Map();
    let nextId = 1;
    // 全树按创建顺序编号（父先于子：按 messages 顺序，父总先创建）
    for (const m of session.messages) {
      numericIds.set(m.id, nextId);
      nextId++;
    }
    for (const m of session.messages) {
      const parentId = m.parentId === null ? null : (numericIds.get(m.parentId) ?? null);
      if (m.role === 'user') {
        const um = m as UserMessage;
        const fragments: Array<Object> = [];
        if (um.files.length > 0) {
          const fileList: Array<Object> = [];
          for (const f of um.files) {
            let exportPath: string | null = null;
            if (f.isImage && f.localPath !== '') {
              exportPath = `chat_sessions/${session.id}_files/${f.id}_${HistoryArchive.safeName(f.localPath)}`;
              fileMap.set(f.id, f.localPath);
            }
            const fe: J = {
              'id': f.id,
              'file_name': f.name,
              'file_size': f.size,
              'token_usage': null,
              'inserted_at': HistoryArchive.iso(um.createdAt),
              'export_path': exportPath,
              'is_image': f.isImage,
              'width': null,
              'height': null,
            };
            fileList.push(fe);
          }
          const ff: Record<string, Object> = { 'type': 'FILE', 'files': fileList };
          fragments.push(ff);
        }
        const req: J = { 'type': 'REQUEST', 'content': um.content };
        fragments.push(req);
        const mo: J = {
          'id': numericIds.get(um.id) ?? 0,
          'parent_id': parentId,
          'role': 'USER',
          'status': 'FINISHED',
          'thinking_enabled': false,
          'search_enabled': false,
          'accumulated_token_usage': 0,
          'inserted_at': HistoryArchive.iso(um.createdAt),
          'fragments': fragments,
        };
        messages.push(mo);
      } else {
        const am = m as AssistantMessage;
        const fragments = HistoryArchive.assistantToArchiveFragments(am);
        const status = HistoryArchive.archiveStatus(am);
        const mo: J = {
          'id': numericIds.get(am.id) ?? 0,
          'parent_id': parentId,
          'role': 'ASSISTANT',
          'status': status,
          'thinking_enabled': am.thinking,
          'search_enabled': am.search,
          'accumulated_token_usage': am.usage !== null ? am.usage.outputTokens : 0,
          'inserted_at': HistoryArchive.iso(am.createdAt),
          'fragments': fragments,
        };
        messages.push(mo);
      }
    }
    // current_message_id：沿可见链最后一个消息
    let currentNumeric = 0;
    if (session.messages.length > 0) {
      let cur = session.rootMessageId !== null ? HistoryArchive.findLocal(session, session.rootMessageId) : null;
      while (cur !== null) {
        currentNumeric = numericIds.get(cur.id) ?? currentNumeric;
        cur = cur.selectedChildId !== null ? HistoryArchive.findLocal(session, cur.selectedChildId) : null;
      }
    }
    const doc: J = {
      'id': session.id,
      'title': session.title === '' ? null : session.title,
      'current_message_id': currentNumeric,
      'inserted_at': HistoryArchive.iso(session.createdAt),
      'updated_at': HistoryArchive.iso(session.updatedAt),
      'messages': messages,
    };
    return doc;
  }

  private static assistantToArchiveFragments(am: AssistantMessage): Array<Object> {
    const fragments: Array<Object> = [];
    let stageId = 0;
    for (const b of am.blocks) {
      if (b.type === 'thinking') {
        const secs = b.thinkingPart.startedAt > 0 && b.thinkingPart.endedAt > b.thinkingPart.startedAt
          ? Math.max(1, Math.round((b.thinkingPart.endedAt - b.thinkingPart.startedAt) / 1000)) : null;
        const fr: J = {
          'type': 'THINK', 'content': b.thinkingPart.thinking, 'elapsed_secs': secs,
        };
        fragments.push(fr);
      } else if (b.type === 'text') {
        // 引用来源 → TOOL_OPEN 组（官方新版来源协议，stage_id 按组自增，供官方导入还原来源卡）
        if (b.textPart.citations.length > 0) {
          stageId++;
          for (const c of b.textPart.citations) {
            const fo: J = {
              'type': 'TOOL_OPEN', 'status': 'FINISHED', 'url': c.url, 'title': c.title,
              'snippet': null, 'site_name': null, 'published_at': null, 'site_icon': null, 'stage_id': stageId,
            };
            fragments.push(fo);
          }
        }
        const fr: Record<string, Object> = b.textPart.isTemplate
          ? { 'type': 'TEMPLATE_RESPONSE', 'content': b.textPart.text }
          : { 'type': 'RESPONSE', 'content': b.textPart.text };
        fragments.push(fr);
      } else if (b.type === 'tool') {
        if (b.toolPart.searchResult !== null) {
          const results: Array<Object> = [];
          for (const r of b.toolPart.searchResult.results) {
            const ro: J = {
              'url': r.url, 'title': r.title, 'snippet': r.snippet,
              'published_at': null, 'site_name': r.siteName,
            };
            results.push(ro);
          }
          const fr: J = {
            'type': 'TOOL_SEARCH', 'queries': [], 'results': results, 'status': 'FINISHED',
          };
          fragments.push(fr);
        } else if (b.toolPart.fetchResult !== null) {
          const entry: J = {
            'signature': b.toolPart.fetchResult.signature,
          };
          if (b.toolPart.fetchResult.url !== '') {
            entry['url'] = b.toolPart.fetchResult.url;
          }
          if (b.toolPart.fetchResult.title !== null) {
            entry['title'] = b.toolPart.fetchResult.title;
          }
          const results: Array<Object> = [];
          results.push(entry);
          const fr: J = { 'type': 'READ_LINK', 'results': results };
          fragments.push(fr);
        }
      }
    }
    return fragments;
  }

  private static archiveStatus(am: AssistantMessage): string {
    if (am.status === 'done' && am.stopReason === 'refusal') {
      return 'CONTENT_FILTER';
    }
    if (am.status === 'done') {
      return 'FINISHED';
    }
    if (am.status === 'stopped') {
      return 'INCOMPLETE';
    }
    return 'FAILED';
  }

  private static findLocal(session: Session, id: string): Message | null {
    for (const m of session.messages) {
      if (m.id === id) {
        return m;
      }
    }
    return null;
  }

  private static safeName(path: string): string {
    const slash = path.lastIndexOf('/');
    return slash >= 0 ? path.substring(slash + 1) : path;
  }

  /** 归档内相对路径校验：拒绝绝对路径、盘符与 .. 段，防止导出路径穿越 */
  private static safeArchivePath(rel: string): string | null {
    const normalized = rel.replace(/\\/g, '/');
    if (normalized === '' || normalized.startsWith('/') || /^[A-Za-z]:/.test(normalized)) {
      return null;
    }
    for (const part of normalized.split('/')) {
      if (part === '' || part === '.' || part === '..') {
        return null;
      }
    }
    return normalized;
  }

  /** 附件落地文件名：只取末段，去掉控制字符，避免写出 cacheDir */
  private static safeFileName(name: string): string {
    let base = name.replace(/\\/g, '/');
    const slash = base.lastIndexOf('/');
    if (slash >= 0) {
      base = base.substring(slash + 1);
    }
    base = base.replace(/[\u0000-\u001f]/g, '').trim();
    if (base === '' || base === '.' || base === '..') {
      return 'file';
    }
    return base;
  }

  /** 导出文件名（deepseek_data-YYYYMMDD.zip） */
  static baseName(zipPath: string): string {
    return HistoryArchive.safeName(zipPath);
  }

  private static iso(ms: number): string {
    const d = new Date(ms);
    return d.toISOString().replace(/\.\d{3}Z$/, 'Z');
  }

  private static parseTime(v: Object | undefined | null): number {
    if (typeof v !== 'string') {
      return Date.now();
    }
    const t = Date.parse(v as string);
    return Number.isFinite(t) ? t : Date.now();
  }

  /** 导出包名时间戳：YYYYMMDD-HHmmss（秒级，规避同日多次导出同名冲突） */
  private static dateStamp(): string {
    const d = new Date();
    const m = `${d.getMonth() + 1}`.padStart(2, '0');
    const day = `${d.getDate()}`.padStart(2, '0');
    const h = `${d.getHours()}`.padStart(2, '0');
    const min = `${d.getMinutes()}`.padStart(2, '0');
    const s = `${d.getSeconds()}`.padStart(2, '0');
    return `${d.getFullYear()}${m}${day}-${h}${min}${s}`;
  }
}
