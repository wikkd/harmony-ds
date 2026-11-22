import { Json } from '../../common/JsonHelper';
import {
  MessageUsage,
  ProtocolBlock,
  ProtocolFetchResultBlock,
  ProtocolSearchResultBlock,
  ProtocolServerToolUse,
  ProtocolTextBlock,
  ProtocolThinkingBlock,
  SearchResult,
  ServerToolAction,
  ServerToolInput,
  ServerToolKind,
  StopReason,
  StreamEvent,
  TextCitation,
} from '../../model/ApiTypes';

/**
 * 事件解析：对齐原项目 parseEvent.ts。
 * 未识别或无法安全消费的事件静默丢弃，不影响后续有效内容与正常结束。
 */

const SERVER_TOOL_KINDS: string[] = ['search', 'deep_search', 'read_link', 'image_search', 'deep_image_search'];
const SEARCH_RESULT_KINDS: string[] = ['search', 'deep_search', 'image_search', 'deep_image_search'];
const FETCH_KINDS: string[] = ['read_link', 'deep_search'];
const TOOL_NAMES: string[] = ['deepseek_web_search', 'deepseek_read_url'];
const STOP_REASONS: string[] = ['end_turn', 'max_tokens', 'tool_use', 'refusal'];

function parseCitation(value: Object | null | undefined): TextCitation | null {
  const r = Json.rec(value);
  if (r === null || Json.getStr(r, 'type') !== 'web_search_result_location') {
    return null;
  }
  const url = Json.getStr(r, 'url');
  if (url === null) {
    return null;
  }
  const c = new TextCitation();
  c.url = url;
  c.title = (Json.getStr(r, 'title') ?? null) as string | null;
  c.citedText = Json.getStr(r, 'cited_text') ?? '';
  return c;
}

function parseServerToolInput(input: Record<string, Object>): ServerToolInput | null {
  const action = Json.getStr(input, 'action');
  const out = new ServerToolInput();
  if (action === 'search') {
    const queries = Json.getArr(input, 'queries');
    if (queries === null) {
      return null;
    }
    out.action = 'search';
    out.query = Json.getStr(input, 'query') ?? '';
    for (const q of queries) {
      const s = Json.str(q);
      if (s === null) {
        return null;
      }
      out.queries.push(s);
    }
    return out;
  }
  if (action === 'open_page' || action === 'read_link') {
    const url = Json.getStr(input, 'url');
    if (url === null) {
      return null;
    }
    out.action = action as ServerToolAction;
    out.url = url;
    return out;
  }
  if (action === 'find_in_page') {
    const url = Json.getStr(input, 'url');
    const pattern = Json.getStr(input, 'pattern');
    if (url === null || pattern === null) {
      return null;
    }
    out.action = 'find_in_page';
    out.url = url;
    out.pattern = pattern;
    return out;
  }
  return null;
}

function parseBlock(value: Object | null | undefined): ProtocolBlock | null {
  const r = Json.rec(value);
  if (r === null) {
    return null;
  }
  const type = Json.getStr(r, 'type');
  if (type === 'text') {
    const text = Json.getStr(r, 'text');
    if (text === null) {
      return null;
    }
    const b = new ProtocolBlock();
    b.type = 'text';
    b.text = new ProtocolTextBlock();
    b.text.text = text;
    const citations = r['citations'];
    if (citations !== undefined) {
      const arr = Json.arr(citations);
      if (arr !== null) {
        for (const item of arr) {
          const c = parseCitation(item);
          if (c !== null) {
            b.text.citations.push(c);
          }
        }
      }
    }
    return b;
  }
  if (type === 'thinking') {
    const thinking = Json.getStr(r, 'thinking');
    if (thinking === null) {
      return null;
    }
    const b = new ProtocolBlock();
    b.type = 'thinking';
    b.thinking = new ProtocolThinkingBlock();
    b.thinking.thinking = thinking;
    b.thinking.signature = Json.getStr(r, 'signature') ?? '';
    return b;
  }
  if (type === 'server_tool_use') {
    const id = Json.getStr(r, 'id');
    const name = Json.getStr(r, 'name');
    const kind = Json.getStr(r, 'kind');
    const inputRec = Json.getRec(r, 'input');
    if (id === null || name === null || !TOOL_NAMES.includes(name)
      || kind === null || !SERVER_TOOL_KINDS.includes(kind) || inputRec === null) {
      return null;
    }
    const input = parseServerToolInput(inputRec);
    if (input === null) {
      return null;
    }
    const b = new ProtocolBlock();
    b.type = 'server_tool_use';
    b.rawJson = JSON.stringify(r);
    b.serverToolUse = new ProtocolServerToolUse();
    b.serverToolUse.id = id;
    b.serverToolUse.name = name;
    b.serverToolUse.kind = kind as ServerToolKind;
    b.serverToolUse.input = input;
    return b;
  }
  if (type === 'web_search_tool_result') {
    const toolUseId = Json.getStr(r, 'tool_use_id');
    const kind = Json.getStr(r, 'kind');
    const content = Json.getArr(r, 'content');
    if (toolUseId === null || kind === null || !SEARCH_RESULT_KINDS.includes(kind) || content === null) {
      return null;
    }
    const b = new ProtocolBlock();
    b.type = 'web_search_tool_result';
    b.rawJson = JSON.stringify(r);
    b.searchResult = new ProtocolSearchResultBlock();
    b.searchResult.toolUseId = toolUseId;
    b.searchResult.kind = kind as ServerToolKind;
    for (const item of content) {
      const ir = Json.rec(item);
      if (ir === null) {
        continue;
      }
      if (Json.getStr(ir, 'type') === 'web_search_tool_result_error') {
        if (Json.getStr(ir, 'error_code') !== null) {
          b.searchResult.hasError = true;
        }
        continue;
      }
      if (Json.getStr(ir, 'type') !== 'web_search_result') {
        continue;
      }
      const url = Json.getStr(ir, 'url');
      const title = Json.getStr(ir, 'title');
      if (url === null || title === null) {
        continue;
      }
      const res = new SearchResult();
      res.url = url;
      res.title = title;
      res.snippet = Json.getStr(ir, 'snippet') ?? '';
      res.siteIcon = Json.getStr(ir, 'site_icon') ?? null;
      res.siteName = Json.getStr(ir, 'site_name') ?? null;
      res.pageAge = Json.getStr(ir, 'page_age') ?? null;
      const img = Json.getStr(ir, 'image_url');
      res.imageUrl = img === null ? undefined : img;
      b.searchResult.results.push(res);
    }
    return b;
  }
  if (type === 'web_fetch_tool_result') {
    const toolUseId = Json.getStr(r, 'tool_use_id');
    const kind = Json.getStr(r, 'kind');
    const content = Json.getRec(r, 'content');
    if (toolUseId === null || kind === null || !FETCH_KINDS.includes(kind) || content === null) {
      return null;
    }
    const b = new ProtocolBlock();
    b.type = 'web_fetch_tool_result';
    b.rawJson = JSON.stringify(r);
    b.fetchResult = new ProtocolFetchResultBlock();
    b.fetchResult.toolUseId = toolUseId;
    b.fetchResult.kind = kind as ServerToolKind;
    const contentType = Json.getStr(content, 'type');
    if (contentType === 'web_fetch_tool_result_error') {
      b.fetchResult.errorCode = Json.getStr(content, 'error_code') ?? 'unavailable';
    } else if (contentType === 'web_fetch_result') {
      const url = Json.getStr(content, 'url');
      const inner = Json.getRec(content, 'content');
      if (url === null || inner === null) {
        return null;
      }
      b.fetchResult.url = url;
      b.fetchResult.title = Json.getStr(inner, 'title') ?? null;
    } else {
      return null;
    }
    b.fetchResult.signature = Json.getStr(r, 'signature') ?? '';
    return b;
  }
  if (type === 'tool_use') {
    // 不展示客户端工具内容；交给回复归并层关闭这条回复的续写能力。
    const b = new ProtocolBlock();
    b.type = 'tool_use';
    b.isToolUse = true;
    return b;
  }
  return null;
}

function parseDelta(event: StreamEvent, value: Object | null | undefined): boolean {
  const r = Json.rec(value);
  if (r === null) {
    return false;
  }
  const type = Json.getStr(r, 'type');
  if (type === 'text_delta') {
    const text = Json.getStr(r, 'text');
    if (text === null) {
      return false;
    }
    event.deltaText = text;
    return true;
  }
  if (type === 'thinking_delta') {
    const thinking = Json.getStr(r, 'thinking');
    if (thinking === null) {
      return false;
    }
    event.deltaThinking = thinking;
    return true;
  }
  if (type === 'signature_delta') {
    const signature = Json.getStr(r, 'signature');
    if (signature === null) {
      return false;
    }
    event.deltaSignature = signature;
    return true;
  }
  if (type === 'citations_delta') {
    const citation = parseCitation(r['citation']);
    if (citation === null) {
      return false;
    }
    event.deltaCitation = citation;
    return true;
  }
  return false;
}

function parseUsage(value: Object | null | undefined): MessageUsage | null {
  const r = Json.rec(value);
  if (r === null) {
    return null;
  }
  const input = Json.num(r['input_tokens']);
  const cc = Json.num(r['cache_creation_input_tokens']);
  const cr = Json.num(r['cache_read_input_tokens']);
  const output = Json.num(r['output_tokens']);
  if (input === null || cc === null || cr === null || output === null) {
    return null;
  }
  const u = new MessageUsage();
  u.inputTokens = input;
  u.cacheCreationInputTokens = cc;
  u.cacheReadInputTokens = cr;
  u.outputTokens = output;
  const stu = Json.getRec(r, 'server_tool_use');
  if (stu !== null) {
    u.webSearchRequests = Json.num(stu['web_search_requests']) ?? 0;
    u.toolSearch = Json.num(stu['tool_search']) ?? 0;
  }
  return u;
}

/** 解析一个 SSE data 帧；返回 null 表示静默丢弃 */
export function parseMessageEvent(payload: Record<string, Object>): StreamEvent | null {
  const type = Json.getStr(payload, 'type');
  if (type === null) {
    return null;
  }
  const event = new StreamEvent();
  event.type = type;
  if (type === 'message_start') {
    const message = Json.getRec(payload, 'message');
    if (message === null) {
      return null;
    }
    event.messageId = Json.getStr(message, 'id') ?? '';
    event.messageModel = Json.getStr(message, 'model') ?? '';
    event.messageUsage = parseUsage(message['usage']);
    return event;
  }
  if (type === 'content_block_start') {
    const index = Json.getInt(payload, 'index');
    const block = parseBlock(payload['content_block']);
    if (index === null || block === null) {
      return null;
    }
    event.index = index;
    event.block = block;
    return event;
  }
  if (type === 'content_block_delta') {
    const index = Json.getInt(payload, 'index');
    if (index === null || !parseDelta(event, payload['delta'])) {
      return null;
    }
    event.index = index;
    return event;
  }
  if (type === 'content_block_stop') {
    const index = Json.getInt(payload, 'index');
    if (index === null) {
      return null;
    }
    event.index = index;
    return event;
  }
  if (type === 'message_delta') {
    const delta = Json.getRec(payload, 'delta');
    if (delta === null) {
      return null;
    }
    const stopReason = Json.getStr(delta, 'stop_reason');
    if (stopReason === null || !STOP_REASONS.includes(stopReason)) {
      return null;
    }
    event.stopReason = stopReason as StopReason;
    event.isRefusal = stopReason === 'refusal';
    event.title = Json.getStr(delta, 'title');
    event.usage = parseUsage(payload['usage']);
    return event;
  }
  if (type === 'message_stop' || type === 'ping') {
    return event;
  }
  return null;
}
