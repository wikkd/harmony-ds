import { Fonts } from '../../common/Fonts';
import { I18n } from '../../common/I18n';
import { Dim, Motion } from '../../common/DesignTokens';
import {
  AssistantMessage,
  FileAttachment,
  Message,
  Session,
  UserMessage,
  isAssistant,
  isUser,
} from '../../model/ChatTypes';
import { ChatStore } from '../../service/chat/ChatStore';
import { ReplyEngine } from '../../service/chat/ReplyEngine';
import { Logger } from '../../common/Logger';
import { AssistantBody, copyToClipboard } from './AssistantBody';
import { AttPreview } from './AttPreview';



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
            .animation({ duration: Motion.animBase, curve: Curve.Smooth }))
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
    .backgroundColor($r('app.color.photo_scrim'))
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
      // 7.0.0.111 实机回归：列表内数字 constraintSize(maxWidth) 会毒化子树，改代码级截断
      Text(f.name.length > 16 ? `${f.name.slice(0, 16)}…` : f.name)
        .fontSize(Fonts.caption())
        .fontColor($r('app.color.text_primary_contrary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
    .backgroundColor($r('app.color.brand_pressed'))
    .borderRadius(Dim.radiusS)
  }

  @Builder
  userRow(m: UserMessage) {
    Column({ space: 4 }) {
      this.branchSwitcher(m)
      if (m.files.length > 0) {
        // 附件：图片直接出缩略图（点击全屏预览），其余出文件条
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
                .showToast({ message: I18n.translate('copied'), duration: Motion.toastShort });
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

