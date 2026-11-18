import { describe, it, expect } from '@ohos/hypium';
import { ServerSentEventDecoder } from '../../../main/ets/service/api/SseDecoder';
import { MarkdownParser, BlockNode } from '../../../main/ets/components/markdown/MarkdownParser';
import { MathConverter } from '../../../main/ets/components/markdown/MathView';
import { ApiError } from '../../../main/ets/service/api/ApiError';
import { PeakPeriod } from '../../../main/ets/common/PeakPeriod';
import { ModelInfo } from '../../../main/ets/model/ModelInfo';

export default function coreTests(): void {
  describe('sseDecoder', () => {
    it('parses single event', 0, () => {
      const d = new ServerSentEventDecoder();
      const events = d.push('event: message_start\ndata: {"a":1}\n\n');
      expect(events.length === 1).assertTrue();
      expect(events[0].event === 'message_start').assertTrue();
      expect(events[0].data === '{"a":1}').assertTrue();
    });
    it('handles crlf and multi-line data', 0, () => {
      const d = new ServerSentEventDecoder();
      const events = d.push('data: line1\r\ndata: line2\r\n\r\n');
      expect(events.length === 1).assertTrue();
      expect(events[0].data === 'line1\nline2').assertTrue();
    });
    it('ignores comments and buffers partial cr', 0, () => {
      const d = new ServerSentEventDecoder();
      let events = d.push(': keep-alive\n');
      expect(events.length === 0).assertTrue();
      events = d.push('data: {"b":2}\r');
      expect(events.length === 0).assertTrue();
      events = d.push('\n');
      expect(events.length === 1).assertTrue();
    });
    it('multi-line data joined with newline', 0, () => {
      const d = new ServerSentEventDecoder();
      const events = d.push('data: a\ndata: b\n\n');
      expect(events[0].data === 'a\nb').assertTrue();
    });
  });

  describe('markdownParser', () => {
    it('parses heading', 0, () => {
      const blocks: BlockNode[] = MarkdownParser.parse('## 标题');
      expect(blocks.length === 1).assertTrue();
      expect(blocks[0].type === 'h2').assertTrue();
    });
    it('parses fenced code with lang', 0, () => {
      const blocks: BlockNode[] = MarkdownParser.parse('```ts\nlet a = 1;\n```');
      expect(blocks.length === 1).assertTrue();
      expect(blocks[0].type === 'code').assertTrue();
      expect(blocks[0].codeLang === 'ts').assertTrue();
      expect(blocks[0].codeText === 'let a = 1;').assertTrue();
    });
    it('parses task list', 0, () => {
      const blocks: BlockNode[] = MarkdownParser.parse('- [x] 完成\n- [ ] 待办');
      expect(blocks.length === 1).assertTrue();
      expect(blocks[0].type === 'list').assertTrue();
      expect(blocks[0].items.length === 2).assertTrue();
      expect(blocks[0].items[0].taskDone === true).assertTrue();
      expect(blocks[0].items[1].taskDone === false).assertTrue();
    });
    it('parses table', 0, () => {
      const blocks: BlockNode[] = MarkdownParser.parse('| a | b |\n| --- | ---: |\n| 1 | 2 |');
      expect(blocks.length === 1).assertTrue();
      expect(blocks[0].type === 'table').assertTrue();
      expect(blocks[0].headCells.length === 2).assertTrue();
      expect(blocks[0].rows.length === 1).assertTrue();
      expect(blocks[0].aligns[1] === 'right').assertTrue();
    });
    it('parses inline bold and code', 0, () => {
      const blocks: BlockNode[] = MarkdownParser.parse('**加粗** 与 `code`');
      expect(blocks[0].inlines[0].type === 'strong').assertTrue();
      const hasCode = blocks[0].inlines.some((n) => n.type === 'code');
      expect(hasCode).assertTrue();
    });
    it('parses $$ display math single line', 0, () => {
      const blocks: BlockNode[] = MarkdownParser.parse('$$x=1$$');
      expect(blocks.length === 1).assertTrue();
      expect(blocks[0].type === 'math').assertTrue();
      expect(blocks[0].mathText === 'x=1').assertTrue();
    });
    it('parses \\[...\\] display math (DeepSeek format)', 0, () => {
      const blocks: BlockNode[] = MarkdownParser.parse('\\[ e^{i\\pi}+1=0 \\]');
      expect(blocks.length === 1).assertTrue();
      expect(blocks[0].type === 'math').assertTrue();
      expect(blocks[0].mathText === 'e^{i\\pi}+1=0').assertTrue();
    });
    it('parses multi-line \\[ math block', 0, () => {
      const blocks: BlockNode[] = MarkdownParser.parse('\\[\nE=mc^2\n\\]');
      expect(blocks.length === 1).assertTrue();
      expect(blocks[0].type === 'math').assertTrue();
      expect(blocks[0].mathText === 'E=mc^2').assertTrue();
    });
    it('parses inline \\(...\\) math (DeepSeek format)', 0, () => {
      const blocks: BlockNode[] = MarkdownParser.parse('由 \\(E=mc^2\\) 可知');
      expect(blocks[0].type === 'p').assertTrue();
      const math = blocks[0].inlines.find((n): boolean => n.type === 'math');
      expect(math !== undefined).assertTrue();
      expect(math !== undefined && math.text === 'E=mc^2').assertTrue();
    });
  });

  describe('apiErrorKey', () => {
    it('maps network and interrupted to network key', 0, () => {
      expect(ApiError.replyKeyFor('network') === 'commonNetworkErrorToast').assertTrue();
      expect(ApiError.replyKeyFor('interrupted') === 'commonNetworkErrorToast').assertTrue();
    });
    it('maps status codes to localized keys', 0, () => {
      expect(ApiError.replyKeyFor('http', 401) === 'replyInvalidApiKey').assertTrue();
      expect(ApiError.replyKeyFor('http', 402) === 'replyInsufficientBalance').assertTrue();
      expect(ApiError.replyKeyFor('http', 429) === 'replyRateLimited').assertTrue();
      expect(ApiError.replyKeyFor('http', 503) === 'completionServerBusyToast').assertTrue();
      expect(ApiError.replyKeyFor('stream', 529) === 'completionServerBusyToast').assertTrue();
    });
    it('maps upload and generic failures', 0, () => {
      expect(ApiError.replyKeyFor('upload') === 'uploadFileStatusFailed').assertTrue();
      expect(ApiError.replyKeyFor('http', 400) === 'requestFailed').assertTrue();
      expect(ApiError.replyKeyFor('protocol') === 'requestFailed').assertTrue();
    });
    it('keeps i18nKeyFor compatible', 0, () => {
      const err = new ApiError('http', 'unauthorized', 401);
      expect(ApiError.i18nKeyFor(err) === 'replyInvalidApiKey').assertTrue();
    });
  });

  describe('peakPeriod', () => {
    it('peak on weekday morning window', 0, () => {
      // 2026-01-07 周三 10:00 北京时间
      expect(PeakPeriod.isPeak(new Date(Date.UTC(2026, 0, 7, 2, 0)))).assertTrue();
    });
    it('idle at noon boundary', 0, () => {
      expect(PeakPeriod.isPeak(new Date(Date.UTC(2026, 0, 7, 4, 0)))).assertFalse();
    });
    it('idle on weekend', 0, () => {
      expect(PeakPeriod.isPeak(new Date(Date.UTC(2026, 0, 3, 2, 0)))).assertFalse();
    });
    it('idle on holiday weekday', 0, () => {
      // 2026-02-18 周三，春节假期内
      expect(PeakPeriod.isPeak(new Date(Date.UTC(2026, 1, 18, 2, 0)))).assertFalse();
    });
  });

  describe('modelInfo', () => {
    it('detects builtin models', 0, () => {
      expect(ModelInfo.isBuiltin('deepseek-flash')).assertTrue();
      expect(ModelInfo.isBuiltin('deepseek-v4-pro')).assertTrue();
      expect(ModelInfo.isBuiltin('claude-sonnet')).assertFalse();
    });
    it('estimates peak and idle cost', 0, () => {
      const peak = ModelInfo.replyCost(true, 1000000, 0, 0, 0);
      const idle = ModelInfo.replyCost(false, 1000000, 0, 0, 0);
      expect(Math.abs(peak - 2) < 1e-9).assertTrue();
      expect(Math.abs(idle - 1) < 1e-9).assertTrue();
    });
  });

  describe('mathConverter', () => {
    it('maps greek letters', 0, () => {
      const spans = MathConverter.convert('\\alpha + \\beta');
      let joined = '';
      for (const s of spans) {
        joined += s.text;
      }
      expect(joined.includes('α')).assertTrue();
      expect(joined.includes('β')).assertTrue();
    });
    it('converts superscript to unicode', 0, () => {
      const spans = MathConverter.convert('x^2 + y^{10}');
      let joined = '';
      for (const s of spans) {
        joined += s.text;
      }
      expect(joined.includes('²')).assertTrue();
      expect(joined.includes('¹⁰')).assertTrue();
    });
    it('converts frac inline', 0, () => {
      const spans = MathConverter.convert('\\frac{a}{b}');
      let joined = '';
      for (const s of spans) {
        joined += s.text;
      }
      expect(joined === '(a)/(b)').assertTrue();
    });
    it('flattens nested frac and sqrt args', 0, () => {
      // 求根公式：frac/sqrt 的参数要先递归转换（\pm→±、^2→²）再拼回
      const spans = MathConverter.convert('\\frac{-b\\pm\\sqrt{b^2-4ac}}{2a}');
      let joined = '';
      for (const s of spans) {
        joined += s.text;
      }
      expect(joined === '(-b±√(b²-4ac))/(2a)').assertTrue();
    });
    it('falls back to ^{...} for unmappable superscript', 0, () => {
      // π 无上标 Unicode：整组映射失败应回退 ^{...}，而不是逐字符硬映射出乱码
      const spans = MathConverter.convert('e^{i\\pi}+1=0');
      let joined = '';
      for (const s of spans) {
        joined += s.text;
      }
      expect(joined === 'e^{iπ}+1=0').assertTrue();
    });
    it('converts subscript to unicode', 0, () => {
      const spans = MathConverter.convert('x_1+x_2');
      let joined = '';
      for (const s of spans) {
        joined += s.text;
      }
      expect(joined === 'x₁+x₂').assertTrue();
    });
    it('converts E=mc^2 to unicode superscript', 0, () => {
      const spans = MathConverter.convert('E=mc^2');
      let joined = '';
      for (const s of spans) {
        joined += s.text;
      }
      expect(joined === 'E=mc²').assertTrue();
    });
  });
}
