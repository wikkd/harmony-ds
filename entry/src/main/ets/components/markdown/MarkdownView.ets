import { Fonts } from '../../common/Fonts';
import { BlockNode, InlineNode, MarkdownParser } from './MarkdownParser';
import { CodeBlock } from './CodeBlock';
import { MathBlock, MathInline, MathConverter } from './MathView';
import { MermaidView } from './MermaidView';
import { Dim } from '../../common/DesignTokens';

/** 扁平行内 Span：Text 只能包含 Span，因此把嵌套强调拍平为带样式的一层 */
export class FlatSpan {
  text: string = '';
  bold: boolean = false;
  italic: boolean = false;
  del: boolean = false;
  code: boolean = false;
  math: boolean = false;
  link: boolean = false;
  url: string = '';
}

/** 软换行两侧是否都为 CJK 字符：是则不产生空格 */
function isCjkChar(ch: string): boolean {
  if (ch === '') {
    return false;
  }
  const c = ch.codePointAt(0) ?? 0;
  return (c >= 0x2E80 && c <= 0x9FFF) || (c >= 0xAC00 && c <= 0xD7AF)
    || (c >= 0xF900 && c <= 0xFAFF) || (c >= 0x3000 && c <= 0x303F) || (c >= 0xFF00 && c <= 0xFFEF)
    || (c >= 0x2018 && c <= 0x201F);
}

function lastCharOf(s: string): string {
  return s.length > 0 ? s.charAt(s.length - 1) : '';
}

/** 取行内节点树中第一个可见字符（递归穿过强调/链接等容器） */
function firstCharOfNode(n: InlineNode | null): string {
  if (n === null) {
    return '';
  }
  if (n.type === 'text' || n.type === 'code' || n.type === 'math' || n.type === 'image') {
    return n.text.length > 0 ? n.text.charAt(0) : '';
  }
  for (const c of n.children) {
    const ch = firstCharOfNode(c);
    if (ch !== '') {
      return ch;
    }
  }
  return '';
}

export class Flatten {
  static run(nodes: InlineNode[], base: FlatSpan | null): FlatSpan[] {
    const out: FlatSpan[] = [];
    for (let i = 0; i < nodes.length; i++) {
      const n = nodes[i];
      if (n.type === 'softbreak') {
        // CJK 之间的软换行不产生空格：既避免句中出现多余空格，
        // 也消除该空格引入的断行点（句末标点被单独挤到下一行）
        const prevLast = out.length > 0 ? lastCharOf(out[out.length - 1].text) : '';
        const nextFirst = firstCharOfNode(i + 1 < nodes.length ? nodes[i + 1] : null);
        if (!(isCjkChar(prevLast) && isCjkChar(nextFirst))) {
          const s = new FlatSpan();
          s.text = ' ';
          out.push(s);
        }
        continue;
      }
      if (n.type === 'math') {
        // 行内公式：过 MathConverter 转 Unicode 子集（\pi→π、x^2→x²），
        // 否则 Flatten 会把 LaTeX 原文直接当文本显示
        const spans = MathConverter.convert(n.text);
        for (const ms of spans) {
          const s = new FlatSpan();
          s.text = ms.text;
          if (base !== null) {
            s.bold = base.bold;
            s.italic = base.italic;
            s.del = base.del;
            s.link = base.link;
            s.url = base.url;
          }
          s.math = true;
          out.push(s);
        }
        continue;
      }
      if (n.type === 'text' || n.type === 'code') {
        const s = new FlatSpan();
        s.text = n.text;
        if (base !== null) {
          s.bold = base.bold;
          s.italic = base.italic;
          s.del = base.del;
          s.link = base.link;
          s.url = base.url;
        }
        s.code = n.type === 'code';
        out.push(s);
        continue;
      }
      if (n.type === 'image') {
        const s = new FlatSpan();
        s.text = n.text === '' ? '[图片]' : `[${n.text}]`;
        if (base !== null) {
          s.bold = base.bold;
          s.italic = base.italic;
          s.del = base.del;
        }
        s.link = true;
        s.url = n.url;
        out.push(s);
        continue;
      }
      // strong/em/del/link：继承并叠加样式
      const style = new FlatSpan();
      if (base !== null) {
        style.bold = base.bold;
        style.italic = base.italic;
        style.del = base.del;
        style.link = base.link;
        style.url = base.url;
      }
      if (n.type === 'strong') {
        style.bold = true;
      } else if (n.type === 'em') {
        style.italic = true;
      } else if (n.type === 'del') {
        style.del = true;
      } else if (n.type === 'link') {
        style.link = true;
        style.url = n.url;
      }
      for (const s of Flatten.run(n.children, style)) {
        out.push(s);
      }
    }
    return out;
  }
}

/**
 * Markdown 视图：把 MarkdownParser AST 渲染为 ArkUI 组件树。
 * 流式更新时整块重渲（父层控制节流）。
 */
@ComponentV2
export struct MarkdownView {
  @Param source: string = '';

  build() {
    Column({ space: 8 }) {
      ForEach(MarkdownParser.parse(this.source), (b: BlockNode, idx: number) => {
        BlockView({ block: b })
      }, (b: BlockNode, idx: number) => `bk${idx}`)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

@ComponentV2
struct BlockView {
  @Param block: BlockNode = new BlockNode();

  build() {
    if (this.block.type === 'code') {
      CodeBlock({ code: this.block.codeText, lang: this.block.codeLang })
    } else if (this.block.type === 'math') {
      MathBlock({ latex: this.block.mathText })
    } else if (this.block.type === 'hr') {
      Divider().color($r('app.color.list_separator')).strokeWidth(1)
    } else if (this.block.type === 'blockquote') {
      // 引用竖条用左边框绘制：Rect+height('100%') 在自适应高度容器里会按
      // 父级下发的视口约束解析，把整条引用撑到近一屏高（下方全是空白）
      Column({ space: 6 }) {
        ForEach(this.block.children, (c: BlockNode, i: number) => {
          BlockView({ block: c })
        }, (c: BlockNode, i: number) => `q${i}`)
      }
      .width('100%')
      .padding({ left: 12 })
      .border({ width: { left: 3 }, color: { left: $r('app.color.quote_bar') } })
    } else if (this.block.type === 'list') {
      Column({ space: 4 }) {
        ForEach(this.block.items, (item: BlockNode, i: number) => {
          Row({ space: 8 }) {
            if (item.task) {
              Text(item.taskDone ? '☑' : '☐')
                .fontSize(Fonts.body1())
                .fontColor($r('app.color.brand'))
            } else if (this.block.ordered) {
              Text(`${this.block.start + i}.`)
                .fontSize(Fonts.body1())
                .fontColor($r('app.color.text_primary'))
            } else {
              Text('•')
                .fontSize(Fonts.body1())
                .fontColor($r('app.color.text_secondary'))
            }
            Column({ space: 4 }) {
              ForEach(item.children, (c: BlockNode, j: number) => {
                BlockView({ block: c })
              }, (c: BlockNode, j: number) => `li${i}_${j}`)
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
        }, (item: BlockNode, i: number) => `it${i}`)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    } else if (this.block.type === 'table') {
      Column() {
        Row() {
          ForEach(this.block.headCells, (cell: InlineNode[], ci: number) => {
            Column() {
              InlineText({ inlines: cell, bold: true })
            }
            .layoutWeight(1)
            .padding(6)
            .alignItems(this.cellAlign(ci))
          }, (cell: InlineNode[], ci: number) => `hc${ci}`)
        }
        .width('100%')
        .border({ width: { bottom: 1 }, color: { bottom: $r('app.color.list_separator') } })
        ForEach(this.block.rows, (row: InlineNode[][], ri: number) => {
          Row() {
            ForEach(row, (cell: InlineNode[], ci: number) => {
              Column() {
                InlineText({ inlines: cell })
              }
              .layoutWeight(1)
              .padding(6)
              .alignItems(this.cellAlign(ci))
            }, (cell: InlineNode[], ci: number) => `r${ri}c${ci}`)
          }
          .width('100%')
        }, (row: InlineNode[], ri: number) => `row${ri}`)
      }
      .width('100%')
      .backgroundColor($r('app.color.code_block_bg'))
      .borderRadius(Dim.radiusS)
    } else {
      // 段落与标题
      Text() {
        ForEach(Flatten.run(this.block.inlines, null), (s: FlatSpan, i: number) => {
          Span(s.text)
            .fontWeight(s.bold ? FontWeight.Bold : (this.block.type.startsWith('h') ? FontWeight.Medium : FontWeight.Normal))
            .fontStyle(s.italic ? FontStyle.Italic : FontStyle.Normal)
            .decoration(s.del ? { type: TextDecorationType.LineThrough } :
              (s.link ? { type: TextDecorationType.Underline, color: $r('app.color.hyperlink') } : { type: TextDecorationType.None }))
            .fontColor(s.code ? $r('app.color.brand_activated') :
              (s.link ? $r('app.color.hyperlink') : $r('app.color.text_primary')))
            .fontFamily(s.math ? 'serif' : (s.code ? 'monospace' : 'sans-serif'))
        }, (s: FlatSpan, i: number) => `f${i}`)
      }
      .fontSize(this.fontSize())
      .lineHeight(Math.round((this.block.type.startsWith('h') ? 32 : 26) * Fonts.scale()))
      .width('100%')
    }
  }

  private fontSize(): number {
    const t = this.block.type;
    if (t === 'h1') {
      return Fonts.headline6();
    }
    if (t === 'h2') {
      return Fonts.headline7();
    }
    if (t === 'h3') {
      return Fonts.headline8();
    }
    if (t === 'h4' || t === 'h5' || t === 'h6') {
      return Fonts.headline9();
    }
    return Fonts.body1();
  }

  private cellAlign(ci: number): HorizontalAlign {
    const a = ci < this.block.aligns.length ? this.block.aligns[ci] : 'left';
    if (a === 'center') {
      return HorizontalAlign.Center;
    }
    if (a === 'right') {
      return HorizontalAlign.End;
    }
    return HorizontalAlign.Start;
  }
}

/** 表格单元格文本 */
@ComponentV2
struct InlineText {
  @Param inlines: InlineNode[] = [];
  @Param bold: boolean = false;

  build() {
    Text() {
      ForEach(Flatten.run(this.inlines, null), (s: FlatSpan, i: number) => {
        Span(s.text)
          .fontWeight(this.bold || s.bold ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(s.code ? $r('app.color.brand_activated') : $r('app.color.text_primary'))
      }, (s: FlatSpan, i: number) => `c${i}`)
    }
    .fontSize(Fonts.body2())
    .width('100%')
  }
}
