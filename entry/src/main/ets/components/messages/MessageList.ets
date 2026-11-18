import { Fonts } from '../../common/Fonts';
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
import { MarkdownParser } from '../markdown/MarkdownParser';
import { AppContextHolder } from '../../common/AppContextHolder';
import { common, Context, Want } from '@kit.AbilityKit';
import { Logger } from '../../common/Logger';
import { SpeechApi } from '../../service/speech/SpeechApi';
import { TtsPlayer } from '../../service/speech/TtsPlayer';
import { KeyVault } from '../../prefs/KeyVault';
import { SettingsStore } from '../../prefs/SettingsStore';
import { ApiError } from '../../service/api/ApiError';

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
  /** 底部留白（浮动输入条高度），列表内容可滚过输入条毛玻璃 */
  @Param bottomPad: number = 12;
  @Param onEdit: (m: UserMessage) => void = () => {};
  private store: ChatStore = ChatStore.get();
  private scroller: Scroller = new Scroller();
  /** 快速定位条：滑块高度/位置与是否显示 */
  @Local locateThumbH: number = 0;
  @Local locateThumbY: number = 0;
  @Local locateOn: boolean = false;
  /** 全屏图片预览的本地路径与开关（isShow 需直绑布尔才响应） */
  @Local previewPath: string = '';
  @Local previewOn: boolean = false;
  private viewportH: number = 0;
  private thumbHolding: boolean = false;
  private thumbDragBase: number = 0;

  /** 列表最大可滚动距离（vp）：末项底边 + 当前偏移 - 视口高 */
  private maxScrollOffset(): number {
    const n = this.visible.length;
    if (n === 0 || this.viewportH <= 0) {
      return 0;
    }
    try {
      const last = this.scroller.getItemRect(n - 1);
      const cur = this.scroller.currentOffset().yOffset;
      return Math.max(last.y + last.height + cur - this.viewportH, 0);
    } catch (e) {
      return 0;
    }
  }

  /** 依据当前滚动位置刷新定位滑块 */
  private refreshLocate(): void {
    if (this.thumbHolding) {
      return;
    }
    const vh = this.viewportH;
    const max = this.maxScrollOffset();
    this.locateOn = max > 24;
    if (!this.locateOn || vh <= 0) {
      return;
    }
    const pad = 10;
    const track = vh - pad * 2;
    const th = Math.max(Math.min(vh * vh / (max + vh), track), 40);
    const cur = this.scroller.currentOffset().yOffset;
    this.locateThumbH = th;
    this.locateThumbY = pad + (max > 0 ? cur / max : 0) * (track - th);
  }

  build() {
    Stack({ alignContent: Alignment.TopEnd }) {
      List({ scroller: this.scroller, space: 12 }) {
        ForEach(this.visible, (m: Message) => {
          ListItem() {
            Column() {
              if (isUser(m)) {
                this.userRow(m as UserMessage)
              } else if (isAssistant(m)) {
                this.assistantRow(m as AssistantMessage)
              }
              if (m.id !== '' && m.id === this.session.compactAnchorId) {
                Text(I18n.translate('compactMarker'))
                  .fontSize(Fonts.caption())
                  .fontColor($r('app.color.text_tertiary'))
                  .width('100%')
                  .textAlign(TextAlign.Center)
                  .margin({ top: 6 })
              }
            }
            .width('100%')
          }
          .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 20 }))
            .animation({ duration: 280, curve: Curve.Smooth }))
        }, (m: Message) => m.id)
      }
      .width('100%')
      .height('100%')
      .padding({ left: Dim.pagePadding, right: Dim.pagePadding, top: 12, bottom: this.bottomPad })
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .onDidScroll(() => {
        this.refreshLocate();
      })
      .onAreaChange((_o: Area, nv: Area) => {
        this.viewportH = Number(nv.height);
        this.refreshLocate();
      })

      // 快速定位条：拖动滑块按比例跳转消息位置（仅内容可滚动时出现）
      if (this.locateOn) {
        Column() {
          Column()
            .width(4)
            .height(this.locateThumbH)
            .borderRadius(2)
            .backgroundColor(this.thumbHolding ? $r('app.color.text_secondary') : $r('app.color.text_fourth'))
        }
        .width(20)
        .height(this.locateThumbH + 16)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .margin({ right: 1, top: Math.max(this.locateThumbY - 8, 0) })
        .gesture(PanGesture({ fingers: 1, direction: PanDirection.Vertical, distance: 2 })
          .onActionStart((_e: GestureEvent) => {
            this.thumbHolding = true;
            this.thumbDragBase = this.locateThumbY;
          })
          .onActionUpdate((e: GestureEvent) => {
            const pad = 10;
            const track = this.viewportH - pad * 2 - this.locateThumbH;
            if (track <= 0) {
              return;
            }
            const max = this.maxScrollOffset();
            const ny = Math.min(Math.max(this.thumbDragBase + e.offsetY, pad), pad + track);
            this.locateThumbY = ny;
            this.scroller.scrollTo({ xOffset: 0, yOffset: (ny - pad) / track * max, animation: false });
          })
          .onActionEnd(() => {
            this.thumbHolding = false;
          })
        )
      }

      // 全屏图片预览层（树内覆盖，点击任意处关闭）
      if (this.previewOn) {
        this.previewBuilder()
      }
    }
    .width('100%')
    .height('100%')
    // 列表视口延伸到物理上下边缘：底部留白不再被安全区分界线截断
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  previewBuilder() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Image(`file://${this.previewPath}`)
        .objectFit(ImageFit.Contain)
        .width('100%')
        .height('100%')
      Image($r('app.media.ic_public_cancel'))
        .width(26)
        .height(26)
        .fillColor($r('app.color.text_primary_contrary'))
        .margin({
          top: (AppStorage.get<number>('safeTopVp') ?? 0) + 12,
          right: 16,
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F0000000')
    .onClick(() => {
      this.previewOn = false;
    })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  /** 文件条 chip（非图片附件；图片加载失败时也降级成它） */
  @Builder
  fileChip(f: FileAttachment) {
    Row({ space: 4 }) {
      Image(f.isImage ? $r('app.media.ic_public_picture') : $r('app.media.ic_public_file'))
        .width(14)
        .height(14)
        .fillColor($r('app.color.text_primary_contrary'))
      Text(f.name)
        .fontSize(Fonts.caption())
        .fontColor($r('app.color.text_primary_contrary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: 140 })
    }
    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
    .backgroundColor($r('app.color.brand_pressed'))
    .borderRadius(Dim.radiusS)
  }

  @Builder
  userRow(m: UserMessage) {
    Column({ space: 4 }) {
      this.branchSwitcher(m)      // 附件：图片直接出缩略图（点击全屏预览），其余出文件条
      if (m.files.length > 0) {
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.End }) {
          ForEach(m.files, (f: FileAttachment) => {
            if (f.isImage && f.localPath !== '') {
              AttPreview({
                path: f.localPath,
                name: f.name,
                onOpen: (p: string): void => {
                  this.previewPath = p;
                  this.previewOn = true;
                },
              })
            } else {
              this.fileChip(f)
            }
          }, (f: FileAttachment) => f.id)
        }
        .width('100%')
      }
      // 气泡（右对齐）
      Row() {
        Blank()
        Text(m.content)
          .fontSize(Fonts.body1())
          .fontColor($r('app.color.text_primary_contrary'))
          .lineHeight(24)
          .constraintSize({ maxWidth: `${Dim.bubbleMaxPercent}%` })
          .padding({ left: 14, right: 14, top: 10, bottom: 10 })
          .backgroundColor(m.id === this.editingId ? $r('app.color.brand_pressed') : $r('app.color.brand'))
          .borderRadius(Dim.radiusL)
      }
      .width('100%')

      // 气泡下方操作行：复制 / 编辑（灰色小图标右对齐，官方排版一致）
      Row({ space: 14 }) {
        Blank()
        Image($r('app.media.ic_public_copy'))
          .width(16)
          .height(16)
          .fillColor($r('app.color.text_tertiary'))
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.85 })
          .onClick(() => {
            copyToClipboard(m.content).then(() => {
              this.getUIContext().getPromptAction()
                .showToast({ message: I18n.translate('copied'), duration: 1200 });
            }).catch((err: object) => {
              Logger.warn('MessageList', `copy failed: ${JSON.stringify(err)}`);
            });
          })
        Image($r('app.media.ic_public_edit'))
          .width(16)
          .height(16)
          .fillColor($r('app.color.text_tertiary'))
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.85 })
          .onClick(() => {
            if (!this.isLocked(m)) {
              this.onEdit(m);
            }
          })
      }
      .width('100%')
      .margin({ top: 2, right: 4 })
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
        .fontSize(Fonts.body2())
        .fontColor($r('app.color.brand_activated'))
        .onClick(() => {
          this.store.switchVersion(this.session.id, m, -1);
        })
      Text(`${this.siblingIndex(m) + 1}/${this.siblingCount(m)}`)
        .fontSize(Fonts.caption())
        .fontColor($r('app.color.text_tertiary'))
      Text('›')
        .fontSize(Fonts.body2())
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

/** 复制文本到剪贴板；成功提示由调用方（组件内，this 可用）用 UIContext 弹出 */
async function copyToClipboard(text: string): Promise<void> {
  const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
  await pasteboard.getSystemPasteboard().setData(data);
}


@ComponentV2
struct AssistantBody {
  @Param message: AssistantMessage = new AssistantMessage('0', 0);
  @Param onRegenerate: () => void = () => {};
  @Local thinkingOpen: boolean = false;
  @Local ttsPlaying: boolean = false;
  /** 搜索来源抽屉展开态：默认收起 */
  @Local sourcesOpen: boolean = false;

  build() {
    Column({ space: 8 }) {
      // 思考折叠块：智能搜索会产生多段 reasoning，合并为一个抽屉展示
      if (this.thinkingBlocks().length > 0) {
        Column({ space: 8 }) {
          Row({ space: 6 }) {
            // 时钟图标：贴合“思考中/耗时”语义（原 code 方块图案不表意）
            Image($r('app.media.ic_public_time_filled'))
              .width(16)
              .height(16)
              .fillColor($r('app.color.text_tertiary'))
            Text(this.thinkingHeaderLabel())
              .fontSize(Fonts.body3())
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
            this.getUIContext().animateTo({ duration: 240, curve: Curve.Smooth }, (): void => {
              this.thinkingOpen = !this.thinkingOpen;
            });
          })

          if (this.thinkingOpen) {
            Column({ space: 8 }) {
              ForEach(this.thinkingBlocks(), (t: ThinkingPart) => {
                Text(t.thinking)
                  .fontSize(Fonts.body3())
                  .lineHeight(20)
                  .fontColor($r('app.color.text_secondary'))
                  .width('100%')
              }, (t: ThinkingPart) => `th_${t.startedAt}`)
            }
            .width('100%')
            .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 8 }))
              .animation({ duration: 240, curve: Curve.Smooth }))
          }
        }
        .padding(10)
        .backgroundColor($r('app.color.thinking_bg'))
        .borderRadius(Dim.radiusM)
        .width('100%')
      }

      ForEach(this.displaySources(), (src: string, si: number) => {
        Column() {
          // 流式期间用纯文本保性能；结束后 Markdown 富渲染
          if (this.message.status === 'streaming') {
            Text(src)
              .fontSize(Fonts.body1())
              .lineHeight(26)
              .fontColor($r('app.color.text_primary'))
              .width('100%')
          } else {
            MarkdownView({ source: src })
          }
        }
        .width('100%')
      }, (src: string, si: number) => `tx${si}_${src.length}`)

      // 引用来源：抽屉式收纳（默认收起，点标题展开），样式与思考折叠块一致
      if (this.citationCards().length > 0) {
        Column({ space: 8 }) {
          Row({ space: 6 }) {
            Image($r('app.media.ic_public_search'))
              .width(16)
              .height(16)
              .fillColor($r('app.color.text_tertiary'))
            Text(I18n.translate('sourcesCount', { 'count': `${this.citationCards().length}` }))
              .fontSize(Fonts.body3())
              .fontColor($r('app.color.text_tertiary'))
            Blank()
            Image($r('app.media.ic_public_arrow_right'))
              .width(14)
              .height(14)
              .rotate({ angle: this.sourcesOpen ? 90 : 0 })
              .fillColor($r('app.color.text_tertiary'))
          }
          .width('100%')
          .onClick(() => {
            this.getUIContext().animateTo({ duration: 240, curve: Curve.Smooth }, (): void => {
              this.sourcesOpen = !this.sourcesOpen;
            });
          })

          if (this.sourcesOpen) {
            Column({ space: 8 }) {
              ForEach(this.citationCards(), (card: CitationCard, ci: number) => {
                Row({ space: 8 }) {
                  Text(`${ci + 1}`)
                    .fontSize(Fonts.caption())
                    .fontColor($r('app.color.text_primary_contrary'))
                    .width(18)
                    .height(18)
                    .borderRadius(9)
                    .backgroundColor($r('app.color.brand'))
                    .textAlign(TextAlign.Center)
                  Column({ space: 2 }) {
                    Text(card.title)
                      .fontSize(Fonts.body3())
                      .fontColor($r('app.color.text_primary'))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .width('100%')
                    Text(card.url)
                      .fontSize(Fonts.caption())
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
            }
            .width('100%')
            .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 8 }))
              .animation({ duration: 240, curve: Curve.Smooth }))
          }
        }
        .padding(10)
        .backgroundColor($r('app.color.thinking_bg'))
        .borderRadius(Dim.radiusM)
        .width('100%')
      }

      if (this.message.status === 'streaming' && this.textBlocks().length === 0
        && this.thinkingBlocks().length === 0) {
        Row({ space: 8 }) {
          LoadingProgress()
            .width(16)
            .height(16)
            .color($r('app.color.text_tertiary'))
          Text(I18n.translate('messageThinking'))
            .fontSize(Fonts.body3())
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
            .fontSize(Fonts.body3())
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
            .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.85 })
            .onClick(() => {
              copyToClipboard(replyTextOf(this.message)).then(() => {
                this.getUIContext().getPromptAction()
                  .showToast({ message: I18n.translate('copied'), duration: 1200 });
              }).catch((err: object) => {
                Logger.warn('MessageList', `copy failed: ${JSON.stringify(err)}`);
              });
            })
          if (!SettingsStore.get().customModel && SettingsStore.get().ttsEnabled) {
            Image(this.ttsPlaying ? $r('app.media.ic_public_sound_off') : $r('app.media.ic_public_sound'))
              .width(16)
              .height(16)
              .fillColor($r('app.color.text_tertiary'))
              .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.85 })
              .onClick(() => {
                this.toggleTts(this.message);
              })
          }
          Image($r('app.media.ic_public_refresh'))
            .width(16)
            .height(16)
            .fillColor($r('app.color.text_tertiary'))
            .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.85 })
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

  /** 文本块渲染源：流式分段把句末标点单独切开（独立段或下一段开头）时并回前一段，避免单独成行 */
  private displaySources(): string[] {
    const out: string[] = [];
    for (const b of this.message.blocks) {
      if (b.type !== 'text') {
        continue;
      }
      let t = b.textPart.text;
      if (out.length > 0) {
        // 开头独立成行的纯标点：挪回上一段末尾
        const nl = t.indexOf('\n');
        const firstLine = (nl < 0 ? t : t.substring(0, nl)).trim();
        if (firstLine !== '' && MarkdownParser.isPunctOnlyText(firstLine)) {
          out[out.length - 1] += (out[out.length - 1].endsWith('\n') ? '' : '\n\n') + firstLine;
          t = nl < 0 ? '' : t.substring(nl + 1);
          if (t.trim() === '') {
            continue;
          }
        }
        // 整段纯标点：并入上一段
        if (MarkdownParser.isPunctOnlyText(t)) {
          out[out.length - 1] += (out[out.length - 1].endsWith('\n') ? '' : '\n\n') + t;
          continue;
        }
      }
      out.push(t);
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

  /** 合并思考头标题：任一段未结束显示“正在思考”，否则显示首段开始到末段结束的总时长 */
  private thinkingHeaderLabel(): string {
    const parts = this.thinkingBlocks();
    let running = false;
    let start = 0;
    let end = 0;
    for (const t of parts) {
      if (t.startedAt > 0 && (start === 0 || t.startedAt < start)) {
        start = t.startedAt;
      }
      if (t.endedAt === 0) {
        running = true;
      }
      if (t.endedAt > end) {
        end = t.endedAt;
      }
    }
    if (running || end === 0 || start === 0) {
      return I18n.translate('messageThinking');
    }
    const seconds = Math.max(1, Math.round((end - start) / 1000));
    return I18n.translate('messageThinkDuration', { 'count': `${seconds}` });
  }

  private errorText(): string {
    const err = this.message.error;
    if (err === null) {
      return I18n.translate('unknownError');
    }
    const key = ApiError.replyKeyFor(err.kind, err.status);
    if (key === 'requestFailed') {
      return I18n.translate(key, { 'message': err.message });
    }
    return I18n.translate(key);
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

/** 会话区图片预览缩略图：加载失败（缓存被清等）自动降级为文件条 */
@ComponentV2
struct AttPreview {
  @Param path: string = '';
  @Param name: string = '';
  @Param onOpen: (path: string) => void = (): void => {};
  @Local failed: boolean = false;

  build() {
    if (this.failed) {
      Row({ space: 4 }) {
        Image($r('app.media.ic_public_picture'))
          .width(14)
          .height(14)
          .fillColor($r('app.color.text_primary_contrary'))
        Text(this.name)
          .fontSize(Fonts.caption())
          .fontColor($r('app.color.text_primary_contrary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: 140 })
      }
      .padding({ left: 8, right: 8, top: 4, bottom: 4 })
      .backgroundColor($r('app.color.brand_pressed'))
      .borderRadius(Dim.radiusS)
    } else {
      // 沙箱路径需要 file:// 方案，纯绝对路径 Image 不认
      Image(`file://${this.path}`)
        .width(168)
        .height(168)
        .objectFit(ImageFit.Cover)
        .borderRadius(Dim.radiusL)
        .alt($r('app.media.ic_public_picture'))
        .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 })
        .onClick(() => {
          this.onOpen(this.path);
        })
        .onError(() => {
          this.failed = true;
        })
    }
  }
}
