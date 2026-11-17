import { I18n } from '../../common/I18n';
import { Dim } from '../../common/DesignTokens';
import { pasteboard } from '@kit.BasicServicesKit';
import { promptAction } from '@kit.ArkUI';
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
import { ChatStore } from '../../service/chat/ChatStore';
import { ReplyEngine } from '../../service/chat/ReplyEngine';
import { Logger } from '../../common/Logger';

/**
 * 消息列表：用户右侧品牌色气泡，助手左侧排版（鸿蒙设计语言）。
 * 支持分支版本切换、复制、编辑重发、重新生成。Markdown 渲染 M4 接入。
 */
@ComponentV2
export struct MessageList {
  @Param session: Session = new Session('0', 0);
  @Param visible: Message[] = [];
  @Param editingId: string = '';
  @Param onEdit: (m: UserMessage) => void = () => {};
  private store: ChatStore = ChatStore.get();
  private scroller: Scroller = new Scroller();

  build() {
    List({ scroller: this.scroller, space: 12 }) {
      ForEach(this.visible, (m: Message) => {
        ListItem() {
          if (isUser(m)) {
            this.userRow(m as UserMessage)
          } else if (isAssistant(m)) {
            this.assistantRow(m as AssistantMessage)
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

  @Builder
  userRow(m: UserMessage) {
    Column({ space: 4 }) {
      this.branchSwitcher(m)
      Row({ space: 4 }) {
        Blank()
        // 操作：编辑 / 复制
        Image($r('app.media.ic_public_edit'))
          .width(16)
          .height(16)
          .fillColor($r('app.color.text_tertiary'))
          .onClick(() => {
            if (!this.isLocked(m)) {
              this.onEdit(m);
            }
          })
        Image($r('app.media.ic_public_copy'))
          .width(16)
          .height(16)
          .fillColor($r('app.color.text_tertiary'))
          .onClick(() => {
            copyToClipboard(m.content);
          })
        Text(m.content)
          .fontSize($r('app.float.font_body1'))
          .fontColor($r('app.color.text_primary_contrary'))
          .lineHeight(24)
          .constraintSize({ maxWidth: `${Dim.bubbleMaxPercent}%` })
          .padding({ left: 14, right: 14, top: 10, bottom: 10 })
          .backgroundColor(m.id === this.editingId ? $r('app.color.brand_pressed') : $r('app.color.brand'))
          .borderRadius(Dim.radiusL)
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)
    }
    .width('100%')
  }

  @Builder
  assistantRow(m: AssistantMessage) {
    Column({ space: 6 }) {
      this.branchSwitcher(m)
      AssistantBody({ message: m })
      Row({ space: 12 }) {
        if (m.status === 'done' || m.status === 'stopped') {
          Image($r('app.media.ic_public_copy'))
            .width(16)
            .height(16)
            .fillColor($r('app.color.text_tertiary'))
            .onClick(() => {
              copyToClipboard(replyTextOf(m));
            })
          Image($r('app.media.ic_public_refresh'))
            .width(16)
            .height(16)
            .fillColor($r('app.color.text_tertiary'))
            .onClick(() => {
              if (!this.isLocked(m)) {
                this.regenerate(m);
              }
            })
        }
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  branchSwitcher(m: Message) {
    Row({ space: 8 }) {
      Text('‹')
        .fontSize($r('app.float.font_body2'))
        .fontColor($r('app.color.brand_activated'))
        .onClick(() => {
          this.store.switchVersion(this.session.id, m, -1);
        })
      Text(`${this.siblingIndex(m) + 1}/${this.siblingCount(m)}`)
        .fontSize($r('app.float.font_caption'))
        .fontColor($r('app.color.text_tertiary'))
      Text('›')
        .fontSize($r('app.float.font_body2'))
        .fontColor($r('app.color.brand_activated'))
        .onClick(() => {
          this.store.switchVersion(this.session.id, m, 1);
        })
    }
    .visibility(this.siblingCount(m) > 1 ? Visibility.Visible : Visibility.None)
  }

  private isLocked(m: Message): boolean {
    return this.store.streamingSessionId !== null;
  }

  private siblingCount(m: Message): number {
    return this.store.siblingsOf(this.session, m).length;
  }

  private siblingIndex(m: Message): number {
    const siblings = this.store.siblingsOf(this.session, m);
    for (let i = 0; i < siblings.length; i++) {
      if (siblings[i].id === m.id) {
        return i;
      }
    }
    return 0;
  }

  /** 重新生成：在用户消息下新建 assistant 兄弟并重发 */
  private regenerate(reply: AssistantMessage): void {
    const user = reply.parentId === null ? null : this.store.findMessage(this.session, reply.parentId);
    if (user === null || !isUser(user)) {
      return;
    }
    const question = (user as UserMessage).content;
    if (question.trim() === '') {
      return;
    }
    ReplyEngine.regenerate(this.session.id, user.id, question);
  }
}

function replyTextOf(m: AssistantMessage): string {
  let out = '';
  for (const b of m.blocks) {
    if (b.type === 'text') {
      out += b.textPart.text;
    }
  }
  return out;
}

function copyToClipboard(text: string): void {
  try {
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    pasteboard.getSystemPasteboard().setData(data).then(() => {
      promptAction.showToast({ message: I18n.translate('copied'), duration: 1200 });
    });
  } catch (err) {
    Logger.warn('MessageList', `copy failed: ${JSON.stringify(err)}`);
  }
}


@ComponentV2
struct AssistantBody {
  @Param message: AssistantMessage = new AssistantMessage('0', 0);
  @Local thinkingOpen: boolean = false;

  build() {
    Column({ space: 8 }) {
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
