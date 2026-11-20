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
  /** 粘底跟随：流式增量/结构变化自动滚到最新内容；用户上滚（距底 >100vp）解除，回底（≤40vp）恢复 */
  @Local followBottom: boolean = true;
  private lastFollowAt: number = 0;
  private jumpedInitial: boolean = false;

  /** 会话切换→落底；可见链变化→跟随中贴底（V2 无 @Watch，用 @Monitor 监听 @Param 重指派） */
  @Monitor('session', 'visible')
  onStateSwap(monitor: IMonitor): void {
    if (monitor.dirty.includes('session')) {
      this.onSessionSwap();
    }
    if (monitor.dirty.includes('visible')) {
      this.onVisibleSwap();
    }
  }

  aboutToAppear(): void {
    this.store.onStreamTick = (): void => this.followTick();
    this.store.onMessageAppended = (): void => this.jumpFollow();
  }

  aboutToDisappear(): void {
    if (this.store.onStreamTick !== null) {
      this.store.onStreamTick = null;
    }
    if (this.store.onMessageAppended !== null) {
      this.store.onMessageAppended = null;
    }
  }

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

  /**
   * 列表顶部内边距：让出悬浮头部（抽屉钮/状态胶囊）的高度。
   * 头部 Row = 12vp 边距 + 控件内部再让 safeTop，高约 44vp；
   * 不让位时滚动到顶，首条消息会钻进胶囊后面（手机端实测遮挡过半）。
   * 列表因 expandSafeArea 以屏幕顶为原点，故需显式加回 safeTop。
   */
  private topPad(): number {
    return (AppStorage.get<number>('safeTopVp') ?? 0) + 62;
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

  /** 滚到列表底部：scrollTo 到末项底边（scrollEdge 的 ScrollEdgeOptions 无动画开关） */
  private scrollToBottom(animated: boolean): void {
    const n = this.visible.length;
    if (n === 0 || this.viewportH <= 0) {
      this.scroller.scrollEdge(Edge.Bottom);
      return;
    }
    try {
      const last = this.scroller.getItemRect(n - 1);
      const cur = this.scroller.currentOffset().yOffset;
      const max = Math.max(last.y + last.height + cur - this.viewportH, 0);
      this.scroller.scrollTo({ xOffset: 0, yOffset: max, animation: animated });
    } catch (e) {
      this.scroller.scrollEdge(Edge.Bottom); // 末项尚未布局：默认行为兜底
    }
  }

  /** 用户上滚判定：距底 >100vp 解除跟随，≤40vp 恢复（迟滞防边界抖动） */
  private syncFollow(): void {
    const max = this.maxScrollOffset();
    if (max <= 0) {
      return; // 内容未溢出或末项尚未布局：不判定
    }
    const dist = max - this.scroller.currentOffset().yOffset;
    if (this.followBottom && dist > 100) {
      this.followBottom = false;
    } else if (!this.followBottom && dist <= 40) {
      this.followBottom = true;
    }
  }

  /** 粘底跟随：节流 200ms，免逐 delta 滚动抖动 */
  private followTick(): void {
    if (!this.followBottom || this.thumbHolding) {
      return;
    }
    const now = Date.now();
    if (now - this.lastFollowAt < 200) {
      return;
    }
    this.lastFollowAt = now;
    this.scrollToBottom(false);
  }

  /** 新消息入链（发送/重发）：强制恢复跟随并动画跳底——用户在半途阅读也回到最新 */
  private jumpFollow(): void {
    if (this.thumbHolding) {
      return;
    }
    this.followBottom = true;
    // 延后一拍：等新消息排进布局再滚，才能落到位
    setTimeout((): void => {
      if (this.followBottom) {
        this.lastFollowAt = Date.now();
        this.scrollToBottom(true);
      }
    }, 0);
  }

  /** 会话切换：按官方行为落到最新消息（无动画直落） */
  private onSessionSwap(): void {
    this.followBottom = true;
    setTimeout((): void => {
      this.scrollToBottom(false);
    }, 0);
  }

  /** 可见链变化（入链/收尾/分支切换）：跟随中则贴住底部，阅读中不打扰 */
  private onVisibleSwap(): void {
    this.followTick();
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
            .animation({ duration: Motion.animBase, curve: Motion.curveIn }))
        }, (m: Message) => m.id)
      }
      .width('100%')
      .height('100%')
      .padding({ left: Dim.pagePadding, right: Dim.pagePadding, top: this.topPad(), bottom: this.bottomPad })
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .onDidScroll(() => {
        this.syncFollow();
        this.refreshLocate();
      })
      .onAreaChange((_o: Area, nv: Area) => {
        this.viewportH = Number(nv.height);
        this.refreshLocate();
        // 首次布局落底：打开会话即最新消息（对齐官方），之后仅靠会话切换驱动
        if (!this.jumpedInitial) {
          this.jumpedInitial = true;
          setTimeout((): void => {
            this.scrollToBottom(false);
          }, 0);
        }
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

      // 回到底部：跟随被用户上滚解除后出现（官方同款右下圆钮，悬浮在输入面板上方）
      if (!this.followBottom && this.locateOn) {
        Column() {
          Column() {
            Image($r('app.media.ic_public_arrow_up_0'))
              .width(18)
              .height(18)
              .fillColor($r('app.color.text_secondary'))
              .rotate({ angle: 180 })
          }
          .width(36)
          .height(36)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .borderRadius(18)
          .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
          .stateStyles({
            pressed: {
              .backgroundColor($r('app.color.interactive_pressed'))
            },
          })
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.92 })
          .onClick(() => {
            this.followBottom = true;
            this.lastFollowAt = Date.now();
            this.scrollToBottom(true);
          })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.End)
        .alignItems(HorizontalAlign.End)
        .padding({ right: 12, bottom: this.bottomPad + 8 })
        .hitTestBehavior(HitTestMode.None)
        .transition(TransitionEffect.OPACITY.combine(TransitionEffect.scale({ x: 0.9, y: 0.9 }))
          .animation({ duration: Motion.animBase, curve: Motion.curveIn }))
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
          // 热区外扩到 40×40（UX 2.1.3.3）
          .responseRegion({ x: -12, y: -12, width: 40, height: 40 })
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
          .responseRegion({ x: -12, y: -12, width: 40, height: 40 })
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
        // 版本切换箭头热区外扩到 40×40（UX 2.1.3.3）
        .responseRegion({ x: -14, y: -14, width: 40, height: 40 })
        .onClick(() => {
          this.store.switchVersion(this.session.id, m, -1);
        })
      Text(`${this.siblingIndex(m) + 1}/${this.siblingCount(m)}`)
        .fontSize(Fonts.caption())
        .fontColor($r('app.color.text_tertiary'))
      Text('›')
        .fontSize(Fonts.body2())
        .fontColor($r('app.color.brand_activated'))
        .responseRegion({ x: -14, y: -14, width: 40, height: 40 })
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

