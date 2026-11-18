import { Fonts } from '../../common/Fonts';
import { CodeSpan, Highlighter } from './Highlighter';
import { pasteboard } from '@kit.BasicServicesKit';
import { promptAction } from '@kit.ArkUI';
import { I18n } from '../../common/I18n';
import { Dim } from '../../common/DesignTokens';

class LineSpans {
  spans: CodeSpan[] = [];
}

/** 代码块：语言标签 + 复制按钮 + Span 混排高亮（横向滚动，不换行） */
@ComponentV2
export struct CodeBlock {
  @Param code: string = '';
  @Param lang: string = '';

  build() {
    Column() {
      Row() {
        Text(this.lang === '' ? 'text' : this.lang)
          .fontSize(Fonts.caption())
          .fontColor($r('app.color.text_secondary'))
        Blank()
        Image($r('app.media.ic_public_copy'))
          .width(16)
          .height(16)
          .fillColor($r('app.color.text_secondary'))
          .onClick(() => {
            this.copy();
          })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 6, bottom: 2 })

      Scroll() {
        Column() {
          ForEach(this.lines(), (line: LineSpans, idx: number) => {
            Text() {
              ForEach(line.spans, (span: CodeSpan) => {
                Span(span.text)
                  .fontColor(this.colorFor(span.kind))
              }, (span: CodeSpan, i: number) => `${i}`)
            }
            .fontSize(Fonts.body2())
            .fontFamily('monospace')
            .width('100%')
          }, (line: LineSpans, idx: number) => `ln_${idx}`)
        }
        .alignItems(HorizontalAlign.Start)
        .constraintSize({ minWidth: '100%' })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      .padding({ left: 12, right: 12, bottom: 12, top: 4 })
    }
    .backgroundColor($r('app.color.code_block_bg'))
    .borderRadius(Dim.radiusM)
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 高亮结果按行分组 */
  private lines(): LineSpans[] {
    const all = Highlighter.highlight(this.code, this.lang);
    const out: LineSpans[] = [];
    let current = new LineSpans();
    for (const span of all) {
      const parts = span.text.split('\n');
      for (let i = 0; i < parts.length; i++) {
        if (i > 0) {
          out.push(current);
          current = new LineSpans();
        }
        if (parts[i] !== '') {
          const s = new CodeSpan();
          s.text = parts[i];
          s.kind = span.kind;
          current.spans.push(s);
        }
      }
    }
    out.push(current);
    // 去掉尾部空行
    while (out.length > 1) {
      const last = out[out.length - 1];
      if (last.spans.length === 0) {
        out.pop();
      } else {
        break;
      }
    }
    return out;
  }

  private colorFor(kind: string): ResourceColor {
    if (kind === 'keyword') {
      return $r('app.color.brand_activated');
    }
    if (kind === 'string') {
      return $r('app.color.success');
    }
    if (kind === 'comment') {
      return $r('app.color.text_tertiary');
    }
    if (kind === 'number') {
      return $r('app.color.alert');
    }
    if (kind === 'func') {
      return $r('app.color.brand_activated');
    }
    if (kind === 'type') {
      return $r('app.color.brand');
    }
    if (kind === 'punct') {
      return $r('app.color.text_secondary');
    }
    return $r('app.color.text_primary');
  }

  private copy(): void {
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.code);
      pasteboard.getSystemPasteboard().setData(data).then(() => {
        this.getUIContext().getPromptAction().showToast({ message: I18n.translate('copied'), duration: 1200 });
      });
    } catch (err) {
      // 忽略
    }
  }
}
