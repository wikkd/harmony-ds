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
      if (round.user.content === '' ) {
        continue;
      }
      appendReminder(round.reply.latestReminder);
      const um: Record<string, Object> = { 'role': 'user', 'content': round.user.content };
      messages.push(um);
      const am: Record<string, Object> = { 'role': 'assistant', 'content': RequestBodyBuilder.assistantTextParam(round.reply) };
      messages.push(am);
    }
    appendReminder(latestReminder);
    const q: Record<string, Object> = { 'role': 'user', 'content': RequestBodyBuilder.userParam(question) };
    messages.push(q);
    if (prefix !== null && prefix.prefix) {
      const text = RequestBodyBuilder.assistantTextParam(prefix);
      const hasContent = (text as Array<Object>).some((b) => {
        const r = b as Record<string, Object>;
        return typeof r['text'] === 'string' && (r['text'] as string).trim() !== '';
      });
      if (hasContent) {
        const am: Record<string, Object> = { 'role': 'assistant', 'content': text };
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

  /** 历史中「提问 + 有回答」成对的轮次（M2 线性版） */
  static getContextRounds(history: Message[]): Array<UserAssistantPair> {
    const rounds: Array<UserAssistantPair> = [];
    for (let i = 0; i + 1 < history.length; i++) {
      const u = history[i];
      const r = history[i + 1];
      if (isUser(u) && isAssistant(r)) {
        const a = r as AssistantMessage;
        const usable = (a.status === 'done' || a.status === 'stopped')
          && a.stopReason !== 'refusal' && RequestBodyBuilder.replyText(a) !== '';
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

  /** 用户消息参数：有文件时先文件块后文本块 */
  private static userParam(m: UserMessage): Object {
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
    if (m.content !== '') {
      const tb: Record<string, Object> = { 'type': 'text', 'text': m.content };
      blocks.push(tb);
    }
    if (blocks.length === 0) {
      return '';
    }
    return blocks;
  }

  /** assistant 历史参数：相邻文本拼接（citations 去除），M2 只回传文本 */
  static assistantTextParam(reply: AssistantMessage): Array<Object> {
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
}
