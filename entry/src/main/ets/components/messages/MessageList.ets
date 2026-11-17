import { I18n } from '../../common/I18n';
import { Dim } from '../../common/DesignTokens';
import { pasteboard } from '@kit.BasicServicesKit';
import { promptAction } from '@kit.ArkUI';
import {
  AssistantMessage,
  FileAttachment,
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
import { MarkdownView } from '../markdown/MarkdownView';
import { AppContextHolder } from '../../common/AppContextHolder';
import { common, Context, Want } from '@kit.AbilityKit';
import { Logger } from '../../common/Logger';
import { SpeechApi } from '../../service/speech/SpeechApi';
import { TtsPlayer } from '../../service/speech/TtsPlayer';
import { KeyVault } from '../../prefs/KeyVault';
import { SettingsStore } from '../../prefs/SettingsStore';

/** 全局唯一 TTS 播放器（新朗读会停止旧的） */
class TtsActive {
  static current: TtsPlayer | null = null;

  static stop(): void {
    if (TtsActive.current !== null) {
      TtsActive.current.stop().catch(() => {});
      TtsActive.current = null;
    }
  }
}

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
      // 附件 chips
      if (m.files.length > 0) {
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.End }) {
          ForEach(m.files, (f: FileAttachment) => {
            Row({ space: 4 }) {
              Image(f.isImage ? $r('app.media.ic_public_picture') : $r('app.media.ic_public_file'))
                .width(14)
                .height(14)
                .fillColor($r('app.color.text_primary_contrary'))
              Text(f.name)
                .fontSize($r('app.float.font_caption'))
                .fontColor($r('app.color.text_primary_contrary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .constraintSize({ maxWidth: 140 })
            }
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .backgroundColor($r('app.color.brand_pressed'))
            .borderRadius(Dim.radiusS)
          }, (f: FileAttachment) => f.id)
        }
        .width('100%')
      }
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
      AssistantBody({ message: m, onRegenerate: (): void => {
        if (!this.isLocked(m)) {
          this.regenerate(m);
        }
      } })
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
  @Param onRegenerate: () => void = () => {};
  @Local thinkingOpen: boolean = false;
  @Local ttsPlaying: boolean = false;

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

      ForEach(this.textBlocks(), (t: TextPart) => {
        Column() {
          // 流式期间用纯文本保性能；结束后 Markdown 富渲染
          if (this.message.status === 'streaming') {
            Text(t.text)
              .fontSize($r('app.float.font_body1'))
              .lineHeight(26)
              .fontColor($r('app.color.text_primary'))
              .width('100%')
          } else {
            MarkdownView({ source: t.text })
          }
        }
        .width('100%')
      }, (t: TextPart) => `tx_${t.text.length}_${t.citations.length}`)

      // 引用来源卡片（正文块 citations 汇总去重）
      ForEach(this.citationCards(), (card: CitationCard, ci: number) => {
        Row({ space: 8 }) {
          Text(`${ci + 1}`)
            .fontSize($r('app.float.font_caption'))
            .fontColor($r('app.color.text_primary_contrary'))
            .width(18)
            .height(18)
            .borderRadius(9)
            .backgroundColor($r('app.color.brand'))
            .textAlign(TextAlign.Center)
          Column({ space: 2 }) {
            Text(card.title)
              .fontSize($r('app.float.font_body3'))
              .fontColor($r('app.color.text_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
            Text(card.url)
              .fontSize($r('app.float.font_caption'))
              .fontColor($r('app.color.text_tertiary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
          .layoutWeight(1)
        }
        .width('100%')
        .padding(8)
        .backgroundColor($r('app.color.code_block_bg'))
        .borderRadius(Dim.radiusS)
        .onClick(() => {
          openUrl(card.url);
        })
      }, (card: CitationCard, ci: number) => `cite${ci}`)

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

      // 操作行：复制 / 朗读 / 重新生成
      if (this.message.status === 'done' || this.message.status === 'stopped') {
        Row({ space: 14 }) {
          Image($r('app.media.ic_public_copy'))
            .width(16)
            .height(16)
            .fillColor($r('app.color.text_tertiary'))
            .onClick(() => {
              copyToClipboard(replyTextOf(this.message));
            })
          Image(this.ttsPlaying ? $r('app.media.ic_public_sound_off') : $r('app.media.ic_public_sound'))
            .width(16)
            .height(16)
            .fillColor($r('app.color.text_tertiary'))
            .onClick(() => {
              this.toggleTts(this.message);
            })
          Image($r('app.media.ic_public_refresh'))
            .width(16)
            .height(16)
            .fillColor($r('app.color.text_tertiary'))
            .onClick(() => {
              this.onRegenerate();
            })
        }
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

  /** 朗读 / 停止朗读（TTS 流式播放） */
  private toggleTts(m: AssistantMessage): void {
    if (this.ttsPlaying) {
      TtsActive.stop();
      this.ttsPlaying = false;
      return;
    }
    const text = replyTextOf(m).trim();
    if (text === '') {
      return;
    }
    KeyVault.load(AppContextHolder.get()).then((apiKey: string | null) => {
      if (apiKey === null || apiKey === '') {
        return;
      }
      const player = new TtsPlayer();
      TtsActive.current = player;
      this.ttsPlaying = true;
      player.start().then(() => {
        return new Promise<void>((resolve) => {
          SpeechApi.synthesize(apiKey, text, SettingsStore.get().ttsVoice, {
            onChunk: (chunk: ArrayBuffer) => {
              player.write(chunk);
            },
            onDone: () => {
              player.drain().then(() => player.stop()).catch(() => {});
              if (TtsActive.current === player) {
                TtsActive.current = null;
              }
              this.ttsPlaying = false;
              resolve();
            },
            onError: () => {
              player.stop().catch(() => {});
              if (TtsActive.current === player) {
                TtsActive.current = null;
              }
              this.ttsPlaying = false;
              resolve();
            },
          });
        });
      }).catch(() => {
        this.ttsPlaying = false;
      });
    });
  }

  /** 汇总正文引用为去重来源卡 */
  private citationCards(): CitationCard[] {    const out: CitationCard[] = [];
    const seen: Set<string> = new Set();
    for (const b of this.message.blocks) {
      if (b.type !== 'text') {
        continue;
      }
      for (const c of b.textPart.citations) {
        if (seen.has(c.url)) {
          continue;
        }
        seen.add(c.url);
        const card = new CitationCard();
        card.url = c.url;
        card.title = c.title === null || c.title === '' ? c.url : c.title;
        out.push(card);
        if (out.length >= 8) {
          return out;
        }
      }
    }
    return out;
  }
}

class CitationCard {
  url: string = '';
  title: string = '';
}

function openUrl(url: string): void {
  try {
    const ability = AppContextHolder.get();
    // 开放链接到浏览器
    openLink(ability, url);
  } catch (err) {
    Logger.warn('MessageList', `open url failed: ${JSON.stringify(err)}`);
  }
}

function openLink(context: Context, url: string): void {
  const uiAbility = context as common.UIAbilityContext;
  const want: Want = {
    action: 'ohos.want.action.viewData',
    entities: ['entity.system.browsable'],
    uri: url,
  };
  uiAbility.startAbility(want).catch(() => {});
}
