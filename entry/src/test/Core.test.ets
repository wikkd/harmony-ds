import { describe, it, expect } from '@ohos/hypium';
import { ServerSentEventDecoder } from '../../main/ets/service/api/SseDecoder';
import { MarkdownParser, BlockNode } from '../../main/ets/components/markdown/MarkdownParser';
import { MathConverter } from '../../main/ets/components/markdown/MathView';

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
  });
}
