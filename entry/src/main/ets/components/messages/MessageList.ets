import { I18n } from '../../common/I18n';
import { Dim } from '../../common/DesignTokens';
import {
  AssistantMessage,
  Message,
  Session,
  TextPart,
  ThinkingPart,
  UserMessage,
  isAssistant,
  isUser,
} from '../../model/ChatTypes';

/**
 * 消息列表：用户右侧品牌色气泡，助手左侧排版（鸿蒙设计语言）。
 * V2 状态管理：嵌套 @Trace 变化直接驱动刷新。Markdown 渲染 M4 接入。
 */
@ComponentV2
export struct MessageList {
  @Param session: Session = new Session('0', 0);
  private scroller: Scroller = new Scroller();

  build() {
    List({ scroller: this.scroller, space: 12 }) {
      ForEach(this.session.messages, (m: Message) => {
        ListItem() {
          if (isUser(m)) {
            UserBubble({ message: m as UserMessage })
          } else if (isAssistant(m)) {
            AssistantBlock({ message: m as AssistantMessage })
          }
        }
      }, (m: Message) => m.id)
    }
    .layoutWeight(1)
    .width('100%')
    .padding({ left: Dim.pagePadding, right: Dim.pagePadding, top: 12 })
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
  }
}

@ComponentV2
struct UserBubble {
  @Param message: UserMessage = new UserMessage('0', '', 0);

  build() {
    Row() {
      Blank()
      Text(this.message.content)
        .fontSize($r('app.float.font_body1'))
        .fontColor($r('app.color.text_primary_contrary'))
        .lineHeight(24)
        .constraintSize({ maxWidth: `${Dim.bubbleMaxPercent}%` })
        .padding({ left: 14, right: 14, top: 10, bottom: 10 })
        .backgroundColor($r('app.color.brand'))
        .borderRadius(Dim.radiusL)
    }
    .width('100%')
    .alignItems(VerticalAlign.Bottom)
  }
}

@ComponentV2
struct AssistantBlock {
  @Param message: AssistantMessage = new AssistantMessage('0', 0);
  @Local thinkingOpen: boolean = false;

  build() {
    Column({ space: 8 }) {
      // 思考折叠块
      ForEach(this.thinkingBlocks(), (t: ThinkingPart) => {
        Column() {
          Row({ space: 6 }) {
            Image($r('app.media.ic_public_code'))
              .width(16)
              .height(16)
              .fillColor($r('app.color.text_tertiary'))
            Text(this.thinkingLabel(t))
              .fontSize($r('app.float.font_body3'))
              .fontColor($r('app.color.text_tertiary'))
            Blank()
            Image($r('app.media.ic_public_arrow_right'))
              .width(14)
              .height(14)
              .rotate({ angle: this.thinkingOpen ? 90 : 0 })
              .fillColor($r('app.color.text_tertiary'))
          }
          .width('100%')
          .onClick(() => {
            this.thinkingOpen = !this.thinkingOpen;
          })

          if (this.thinkingOpen) {
            Text(t.thinking)
              .fontSize($r('app.float.font_body3'))
              .lineHeight(20)
              .fontColor($r('app.color.text_secondary'))
              .padding({ top: 8 })
              .width('100%')
          }
        }
        .padding(10)
        .backgroundColor($r('app.color.thinking_bg'))
        .borderRadius(Dim.radiusM)
        .width('100%')
      }, (t: ThinkingPart) => `th_${t.startedAt}`)

      // 文本块
      ForEach(this.textBlocks(), (t: TextPart) => {
        Column() {
          Text(t.text)
            .fontSize($r('app.float.font_body1'))
            .lineHeight(26)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
        }
        .width('100%')
      }, (t: TextPart) => `tx_${t.text.length}_${t.citations.length}`)

      // 流式中的占位提示
      if (this.message.status === 'streaming' && this.textBlocks().length === 0
        && this.thinkingBlocks().length === 0) {
        Row({ space: 8 }) {
          LoadingProgress()
            .width(16)
            .height(16)
            .color($r('app.color.text_tertiary'))
          Text(I18n.translate('messageThinking'))
            .fontSize($r('app.float.font_body3'))
            .fontColor($r('app.color.text_tertiary'))
        }
        .width('100%')
      }

      // 错误态
      if (this.message.status === 'error' && this.message.error !== null) {
        Row({ space: 8 }) {
          Image($r('app.media.ic_public_error'))
            .width(16)
            .height(16)
            .fillColor($r('app.color.warning'))
          Text(this.errorText())
            .fontSize($r('app.float.font_body3'))
            .fontColor($r('app.color.warning'))
            .layoutWeight(1)
        }
        .padding(10)
        .backgroundColor($r('app.color.thinking_bg'))
        .borderRadius(Dim.radiusM)
        .width('100%')
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  private thinkingBlocks(): ThinkingPart[] {
    const out: ThinkingPart[] = [];
    for (const b of this.message.blocks) {
      if (b.type === 'thinking') {
        out.push(b.thinkingPart);
      }
    }
    return out;
  }

  private textBlocks(): TextPart[] {
    const out: TextPart[] = [];
    for (const b of this.message.blocks) {
      if (b.type === 'text') {
        out.push(b.textPart);
      }
    }
    return out;
  }

  private thinkingLabel(t: ThinkingPart): string {
    if (t.endedAt > 0) {
      const seconds = Math.max(1, Math.round((t.endedAt - t.startedAt) / 1000));
      return I18n.translate('messageThinkDuration', { 'count': `${seconds}` });
    }
    return I18n.translate('messageThinking');
  }

  private errorText(): string {
    const err = this.message.error;
    if (err === null) {
      return I18n.translate('unknownError');
    }
    return I18n.translate('apiKeyVerificationFailed', { 'message': err.message });
  }
}
