import {
  MessageUsage,
  ProtocolFetchResultBlock,
  ProtocolSearchResultBlock,
  ProtocolServerToolUse,
  StopReason,
  TextCitation,
} from './ApiTypes';
import { ApiErrorKind } from '../service/api/ApiError';

/**
 * 本地会话数据模型，对齐原项目 src/services/chat/types.ts。
 * 分支树字段 M3 接入；附件字段 M7 接入。
 * 流式更新依赖 @ObservedV2 + @Trace（嵌套块属性也需可观察）。
 */

/** 消息附件（M7 完整实现） */
@ObservedV2
export class FileAttachment {
  @Trace id: string = '';
  @Trace serverId: string | null = null;
  @Trace name: string = '';
  @Trace size: number = 0;
  @Trace isImage: boolean = false;
  @Trace mimeType: string = '';
}

/** 思考块 */
@ObservedV2
export class ThinkingPart {
  @Trace thinking: string = '';
  @Trace signature: string = '';
  startedAt: number = 0;
  endedAt: number = 0;
}

/** 文本块 */
@ObservedV2
export class TextPart {
  @Trace text: string = '';
  @Trace citations: TextCitation[] = [];
  /** 服务端提示文案，仅展示，不进入上下文 */
  @Trace isTemplate: boolean = false;
}

/** 服务端工具块：协议块原样保存 */
@ObservedV2
export class ServerToolPart {
  @Trace toolUse: ProtocolServerToolUse | null = null;
  @Trace searchResult: ProtocolSearchResultBlock | null = null;
  @Trace fetchResult: ProtocolFetchResultBlock | null = null;
}

/** 回复内容块联合：type 区分 text/thinking/tool */
export class ReplyBlock {
  type: 'text' | 'thinking' | 'tool' = 'text';
  textPart: TextPart = new TextPart();
  thinkingPart: ThinkingPart = new ThinkingPart();
  toolPart: ServerToolPart = new ServerToolPart();
}

export type ReplyStatus = 'pending' | 'streaming' | 'done' | 'stopped' | 'error';

export class ReplyError {
  kind: ApiErrorKind | 'upload' = 'network';
  message: string = '';
  status?: number;
  retryable?: boolean;
}

@ObservedV2
export class AssistantMessage {
  readonly id: string;
  readonly role: string = 'assistant';
  readonly createdAt: number;
  @Trace model: string | null = null;
  /** 请求时是否开启深度思考 */
  @Trace thinking: boolean = false;
  /** 请求时是否声明 deepseek_web_search */
  @Trace search: boolean = false;
  /** 本轮请求的系统信息快照 */
  @Trace latestReminder: string = '';
  /** 是否允许作为续写前缀 */
  @Trace prefix: boolean = true;
  @Trace status: ReplyStatus = 'pending';
  @Trace blocks: ReplyBlock[] = [];
  @Trace stopReason: StopReason | null = null;
  @Trace usage: MessageUsage | null = null;
  @Trace error: ReplyError | null = null;
  // M3 分支树
  parentId: string | null = null;
  selectedChildId: string | null = null;

  constructor(id: string, createdAt: number) {
    this.id = id;
    this.createdAt = createdAt;
  }
}

@ObservedV2
export class UserMessage {
  readonly id: string;
  readonly role: string = 'user';
  @Trace content: string;
  @Trace files: FileAttachment[] = [];
  readonly createdAt: number;
  parentId: string | null = null;
  selectedChildId: string | null = null;

  constructor(id: string, content: string, createdAt: number) {
    this.id = id;
    this.content = content;
    this.createdAt = createdAt;
  }
}

export type Message = UserMessage | AssistantMessage;

export function isUser(m: Message): boolean {
  return m.role === 'user';
}

export function isAssistant(m: Message): boolean {
  return m.role === 'assistant';
}

@ObservedV2
export class Session {
  readonly id: string;
  @Trace title: string = '';
  readonly createdAt: number;
  @Trace updatedAt: number;
  @Trace messages: Message[] = [];
  /** 包含所有分支的消息，按创建顺序存储（M3 启用分支） */
  rootMessageId: string | null = null;

  constructor(id: string, createdAt: number) {
    this.id = id;
    this.createdAt = createdAt;
    this.updatedAt = createdAt;
  }
}

/** 回复里所有文本块拼起来，用于复制与判断是否有回答 */
export function getReplyText(reply: AssistantMessage): string {
  let out = '';
  for (const block of reply.blocks) {
    if (block.type === 'text') {
      out += block.textPart.text;
    }
  }
  return out;
}
