/**
 * Messages API（Anthropic 兼容格式）协议类型，对齐原项目 src/services/api/types.ts。
 * 流式事件在 EventParser 中解析为本文件类型。
 */

/** 正文引用：服务端把模型的引用标记还原为来源 */
export class TextCitation {
  url: string = '';
  title: string | null = null;
  citedText: string = '';
}

export class MessageUsage {
  inputTokens: number = 0;
  cacheCreationInputTokens: number = 0;
  cacheReadInputTokens: number = 0;
  outputTokens: number = 0;
  /** 仅当 message_delta 中有对外输出的搜索结果块时出现 */
  webSearchRequests: number = 0;
  toolSearch: number = 0;
}

export type StopReason = 'end_turn' | 'max_tokens' | 'tool_use' | 'refusal';

/** 服务端工具 kind */
export type ServerToolKind = 'search' | 'deep_search' | 'read_link' | 'image_search' | 'deep_image_search';

/** server_tool_use 的动作 */
export type ServerToolAction = 'search' | 'open_page' | 'find_in_page' | 'read_link';

export class ServerToolInput {
  action: ServerToolAction = 'search';
  query: string = '';
  queries: string[] = [];
  url: string = '';
  pattern: string = '';
}

export class SearchResult {
  url: string = '';
  title: string = '';
  snippet: string = '';
  siteIcon: string | null = null;
  siteName: string | null = null;
  imageUrl: string | undefined = undefined;
  pageAge: string | null = null;
}

// ---------- 协议内容块（服务端 → 客户端） ----------

export class ProtocolTextBlock {
  text: string = '';
  citations: TextCitation[] = [];
}

export class ProtocolThinkingBlock {
  thinking: string = '';
  signature: string = '';
}

export class ProtocolServerToolUse {
  id: string = '';
  name: string = '';
  kind: ServerToolKind = 'search';
  input: ServerToolInput = new ServerToolInput();
}

export class ProtocolSearchResultBlock {
  toolUseId: string = '';
  kind: ServerToolKind = 'search';
  results: SearchResult[] = [];
  /** content 中出现错误项 */
  hasError: boolean = false;
}

export class ProtocolFetchResultBlock {
  toolUseId: string = '';
  kind: ServerToolKind = 'read_link';
  /** 成功时有值 */
  url: string = '';
  title: string | null = null;
  /** 失败时有值 */
  errorCode: string | null = null;
  /** 成功时返回的加密页面，多轮请求原样回传 */
  signature: string = '';
}

/** 协议块联合：以 type 字段区分，消费方按 as 精确类型使用 */
export class ProtocolBlock {
  type: string = '';
  text: ProtocolTextBlock = new ProtocolTextBlock();
  thinking: ProtocolThinkingBlock = new ProtocolThinkingBlock();
  serverToolUse: ProtocolServerToolUse = new ProtocolServerToolUse();
  searchResult: ProtocolSearchResultBlock = new ProtocolSearchResultBlock();
  fetchResult: ProtocolFetchResultBlock = new ProtocolFetchResultBlock();
  /** tool_use（客户端工具）：不展示内容，仅用于关闭续写 */
  isToolUse: boolean = false;
}

// ---------- 流式事件 ----------

export class StreamEvent {
  type: string = '';
  /** message_start */
  messageId: string = '';
  messageModel: string = '';
  messageUsage: MessageUsage | null = null;
  /** content_block_* */
  index: number = -1;
  /** content_block_start */
  block: ProtocolBlock | null = null;
  /** content_block_delta（以下四选一） */
  deltaText: string | null = null;
  deltaThinking: string | null = null;
  deltaSignature: string | null = null;
  deltaCitation: TextCitation | null = null;
  /** message_delta */
  stopReason: StopReason | null = null;
  /** 拒绝时可能有说明 */
  isRefusal: boolean = false;
  title: string | null = null;
  usage: MessageUsage | null = null;
}
