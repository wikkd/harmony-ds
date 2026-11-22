import { I18n } from '../../common/I18n';
import { SettingsStore } from '../../prefs/SettingsStore';
import {
  AssistantMessage,
  Message,
  UserMessage,
  isAssistant,
  isUser,
} from '../../model/ChatTypes';
import { ModelInfo } from '../../model/ModelInfo';

export const NL2: string = String.fromCharCode(10) + String.fromCharCode(10);
/** 对齐原项目 store.ts */
export const SYSTEM_PROMPT: string = '该助手为DeepSeek，由深度求索公司创造。';

class UserAssistantPair {
  user: UserMessage;
  reply: AssistantMessage;

  constructor(user: UserMessage, reply: AssistantMessage) {
    this.user = user;
    this.reply = reply;
  }
}

/**
 * 请求体构建：历史轮次拼装、system/persona/压缩摘要、搜索与思考工具开关。
 * buildRequestBody 自 ReplyEngine 拆出（纯函数，无流式状态）。
 */
export class RequestBodyBuilder {
  /** M3 的 regenerate/continue 复用这里 */
  static build(
    history: Message[],
    question: UserMessage,
    prefix: AssistantMessage | null,
    thinking: boolean,
    search: boolean,
    needTitle: boolean,
    latestReminder: string,
    withFiles: boolean,
    compactAnchorId: string = '',
    compactSummary: string = ''
  ): string {
    const settings = SettingsStore.get();
    const custom = settings.customModel;
    const messages: Array<Object> = [];
    let previousReminder = '';
    const appendReminder = (reminder: string): void => {
      if (custom) {
        // latest_reminder 为 DeepSeek 专有 role，外部模型不发送
        return;
      }
      if (reminder !== '' && reminder !== previousReminder) {
        const m: Record<string, Object> = { 'role': 'latest_reminder', 'content': reminder };
        messages.push(m);
        previousReminder = reminder;
      }
    };
    let anchorPassed = compactAnchorId === '';
    for (const round of RequestBodyBuilder.getContextRounds(history)) {
      if (!anchorPassed) {
        // 压缩点（含）之前的轮次已进入摘要
        if (round.user.id === compactAnchorId) {
          anchorPassed = true;
        }
        continue;
      }
      if (round.user.content === '' && !RequestBodyBuilder.hasServerFile(round.user)) {
        // 历史提问没有文字、附件也都没有 serverId 时，连同回答一起省略
        continue;
      }
      appendReminder(round.reply.latestReminder);
      const um: Record<string, Object> = { 'role': 'user', 'content': RequestBodyBuilder.userParam(round.user) };
      messages.push(um);
      const am: Record<string, Object> = { 'role': 'assistant', 'content': RequestBodyBuilder.assistantParam(round.reply) };
      messages.push(am);
    }
    appendReminder(latestReminder);
    const q: Record<string, Object> = { 'role': 'user', 'content': RequestBodyBuilder.userParam(question) };
    messages.push(q);
    if (prefix !== null && prefix.prefix) {
      const blocks = RequestBodyBuilder.assistantParam(prefix, true, thinking);
      // 没有非空白正文或有效思考时直接重发原问题，避免服务端拒绝空 Prefill
      const hasContent = blocks.some((b) => {
        const r = b as Record<string, Object>;
        if (r['type'] === 'text' && typeof r['text'] === 'string') {
          return (r['text'] as string).trim() !== '';
        }
        if (r['type'] === 'thinking' && typeof r['thinking'] === 'string') {
          return (r['thinking'] as string).trim() !== '';
        }
        return false;
      });
      if (hasContent) {
        const am: Record<string, Object> = { 'role': 'assistant', 'content': blocks };
        messages.push(am);
      }
    }

    const body: Record<string, Object> = {
      'model': settings.model,
      'messages': messages,
      'stream': true,
    };
    const persona = settings.personalization;
    const summaryText = compactSummary === '' ? '' :
      I18n.translate('compactSystemLabel') + NL2 + compactSummary;
    if (custom) {
      // 外部模型：仅标准 Anthropic 字段（max_tokens 协议必填）；个性化/摘要作为 system
      body['max_tokens'] = ModelInfo.EXTERNAL_MAX_TOKENS;
      const sysParts: string[] = [];
      if (persona !== '') {
        sysParts.push(persona);
      }
      if (summaryText !== '') {
        sysParts.push(summaryText);
      }
      if (sysParts.length > 0) {
        body['system'] = sysParts.join(NL2);
      }
      return JSON.stringify(body);
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
    let sys = persona === '' ? SYSTEM_PROMPT : `${SYSTEM_PROMPT}

${persona}`;
    if (summaryText !== '') {
      sys = sys + NL2 + summaryText;
    }
    body['system'] = sys;
    body['thinking'] = thinkingObj;
    body['safety_check'] = safetyObj;
    body['tools'] = tools;
    if (needTitle) {
      const titleObj: Record<string, Object> = { 'enabled': true };
      body['title'] = titleObj;
    }
    if (thinking) {
      // 思考强度（官方 output_config.effort；thinking.budget_tokens 会被服务端忽略）
      const effortObj: Record<string, Object> = { 'effort': settings.thinkingEffort };
      body['output_config'] = effortObj;
    }
    return JSON.stringify(body);
  }

  /** 历史中「提问 + 有回答」成对的轮次（对齐官方 getContextRounds） */
  static getContextRounds(history: Message[]): Array<UserAssistantPair> {
    const rounds: Array<UserAssistantPair> = [];
    for (let i = 0; i + 1 < history.length; i++) {
      const u = history[i];
      const r = history[i + 1];
      if (isUser(u) && isAssistant(r) && RequestBodyBuilder.isUsableReply(r as AssistantMessage)) {
        rounds.push(new UserAssistantPair(u as UserMessage, r as AssistantMessage));
        i++;
      }
    }
    return rounds;
  }

  /** 已结束或停止且有回答文本的回复才放进上下文；被安全拒绝、含服务端模板提示的轮次不回传 */
  static isUsableReply(reply: AssistantMessage): boolean {
    if (reply.status !== 'done' && reply.status !== 'stopped') {
      return false;
    }
    if (reply.stopReason === 'refusal') {
      return false;
    }
    for (const block of reply.blocks) {
      if (block.type === 'text' && block.textPart.isTemplate) {
        return false;
      }
    }
    return RequestBodyBuilder.getReplyText(reply) !== '';
  }

  /** 回复里所有文本块拼起来，用于复制与判断是否有回答 */
  static getReplyText(reply: AssistantMessage): string {
    let out = '';
    for (const block of reply.blocks) {
      if (block.type === 'text') {
        out += block.textPart.text;
      }
    }
    return out;
  }

  /** 用户消息是否带有效（已上传）文件 */
  static hasServerFile(m: UserMessage): boolean {
    for (const f of m.files) {
      if (f.serverId !== null) {
        return true;
      }
    }
    return false;
  }

  /** 用户消息参数：无文件时纯文本；有文件时先文件块后文本块 */
  static userParam(m: UserMessage): Object {
    const blocks: Array<Object> = [];
    for (const f of m.files) {
      if (f.serverId === null) {
        continue;
      }
      const source: Record<string, Object> = { 'type': 'file', 'file_id': f.serverId };
      const b: Record<string, Object> = {
        'type': f.isImage ? 'image' : 'document',
        'source': source,
      };
      blocks.push(b);
    }
    if (blocks.length === 0) {
      return m.content;
    }
    if (m.content !== '') {
      const tb: Record<string, Object> = { 'type': 'text', 'text': m.content };
      blocks.push(tb);
    }
    return blocks;
  }

  /**
   * assistant 内容块转换（对齐官方 toAssistantParam）：
   * - 历史思考及其签名不回传；续写时保留本轮非空白思考及其签名；
   * - 文本块相邻拼接，被思考或工具隔开的文本用空行连接；
   * - 工具调用和结果只回传 read_link：缺签名的成功阅读链接整对不回传，
   *   其余原样回传（rawJson，保留 signature/content），服务端解密后拼回正文。
   */
  static assistantParam(reply: AssistantMessage, prefix: boolean = false, thinking: boolean = false): Array<Object> {
    const content: Array<Object> = [];
    const unsignedReadLinks: Set<string> = new Set();
    for (const block of reply.blocks) {
      const fr = block.toolPart.fetchResult;
      if (block.type === 'tool' && fr !== null && fr.kind === 'read_link'
        && fr.url !== '' && fr.signature.trim() === '') {
        unsignedReadLinks.add(fr.toolUseId);
      }
    }
    let text: Record<string, Object> | null = null;
    for (const block of reply.blocks) {
      if (prefix && block.type === 'thinking' && block.thinkingPart.thinking.trim() === '') {
        // 空思考不改变续写位置，也不应把两段正文隔开
        continue;
      }
      if (block.type === 'text') {
        const t = block.textPart.text;
        if (text !== null) {
          text['text'] = (text['text'] as string) + t;
        } else {
          let start = t;
          if (content.length > 0) {
            const pr = content[content.length - 1] as Record<string, Object>;
            if (pr['type'] === 'text') {
              start = NL2 + t;
            }
          }
          const tb: Record<string, Object> = { 'type': 'text', 'text': start };
          text = tb;
          content.push(tb);
        }
        continue;
      }
      text = null;
      if (prefix && thinking && block.type === 'thinking') {
        const tb: Record<string, Object> = {
          'type': 'thinking',
          'thinking': block.thinkingPart.thinking,
          'signature': block.thinkingPart.signature,
        };
        content.push(tb);
      } else if (block.type === 'tool' && block.toolPart.toolUse !== null) {
        const tu = block.toolPart.toolUse;
        if (tu.kind === 'read_link' && !unsignedReadLinks.has(tu.id) && block.toolPart.rawJson !== '') {
          content.push(JSON.parse(block.toolPart.rawJson) as Record<string, Object>);
        }
      } else if (block.type === 'tool' && block.toolPart.fetchResult !== null) {
        const fr = block.toolPart.fetchResult;
        if (fr.kind === 'read_link' && !unsignedReadLinks.has(fr.toolUseId) && block.toolPart.rawJson !== '') {
          content.push(JSON.parse(block.toolPart.rawJson) as Record<string, Object>);
        }
      }
    }
    const out: Array<Object> = [];
    for (const item of content) {
      const r = item as Record<string, Object>;
      if (r['type'] === 'text' && (r['text'] as string) === '') {
        continue;
      }
      out.push(item);
    }
    return out;
  }

  /**
   * 只有达到输出上限或被停止的回复可续写，报错回复不能续写。
   * 拒绝和客户端工具调用不能续写；本轮含服务端工具调用或结果的回复不能续写；
   * 服务端模板提示不能作为续写前缀。
   */
  static canContinueReply(reply: AssistantMessage): boolean {
    if (!reply.prefix || reply.stopReason === 'refusal' || reply.stopReason === 'tool_use') {
      return false;
    }
    for (const block of reply.blocks) {
      if (block.type === 'tool') {
        return false;
      }
      if (block.type === 'text' && block.textPart.isTemplate) {
        return false;
      }
    }
    return reply.status === 'stopped' || (reply.status === 'done' && reply.stopReason === 'max_tokens');
  }
}
