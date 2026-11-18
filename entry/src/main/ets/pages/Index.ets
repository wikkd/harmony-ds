import { Fonts } from '../common/Fonts';
import { I18n } from '../common/I18n';
import { SettingsStore } from '../prefs/SettingsStore';
import { ThemeHelper } from '../common/ThemeHelper';
import { AppContextHolder } from '../common/AppContextHolder';
import { ApiClient } from '../service/api/ApiClient';
import { ApiError } from '../service/api/ApiError';
import { KeyVault } from '../prefs/KeyVault';
import { ChatStore } from '../service/chat/ChatStore';
import { ReplyEngine } from '../service/chat/ReplyEngine';
import { Dim } from '../common/DesignTokens';
import { PeakPeriod } from '../common/PeakPeriod';
import { PrivacyPolicyPage } from '../components/privacy/PrivacyPolicyPage';
import { MessageList } from '../components/messages/MessageList';
import { ChatInput } from '../components/chatinput/ChatInput';
import { Sider } from '../components/sider/Sider';
import { SettingsPage } from '../components/settings/SettingsPage';
import { UsagePage } from '../components/usage/UsagePage';
import { PersonaPage } from '../components/persona/PersonaPage';
import { UserMessage, FileAttachment, AssistantMessage, isAssistant, Message } from '../model/ChatTypes';
import { ModelInfo } from '../model/ModelInfo';
import { Id } from '../common/Format';
import { AttachmentService } from '../service/attachments/AttachmentService';
import { Logger } from '../common/Logger';

/**
 * M3：Navigation + 侧栏多会话（抽屉/常驻）+ 分支消息链 + 编辑重发。
 * 完整设置面板 M5 替换占位。
 */
@Entry
@Component
struct Index {
  pathStack: NavPathStack = new NavPathStack();
  @StorageProp('safeBottomVp') safeBottom: number = 0;

  build() {
    Navigation(this.pathStack) {
      HomePage({ pathStack: this.pathStack })
    }
    .navDestination(this.pageMap)
    .hideTitleBar(true)
    .hideToolBar(true)
    .backgroundColor($r('app.color.app_bg'))
    .mode(NavigationMode.Stack)
    .padding({ bottom: this.safeBottom })
  }

  @Builder
  pageMap(name: string) {
    if (name === 'privacy') {
      PrivacyPolicyPage()
    } else if (name === 'settings') {
      SettingsPage({ pathStack: this.pathStack })
    } else if (name === 'usage') {
      UsagePage()
    } else if (name === 'persona') {
      PersonaPage()
    }
  }
}

@Component
struct HomePage {
  pathStack: NavPathStack = new NavPathStack();
  @State siderOpen: boolean = false;
  @StorageLink('bpWindowWidth') winWidth: number = 0;
  /** 峰谷红绿灯：定时刷新使圆点随时段切换 */
  @State periodTick: number = 0;
  @State showPeakPopup: boolean = false;
  private periodTimer: number = -1;

  aboutToAppear(): void {
    this.periodTimer = setInterval((): void => {
      this.periodTick++;
    }, 30000);
  }

  aboutToDisappear(): void {
    if (this.periodTimer >= 0) {
      clearInterval(this.periodTimer);
      this.periodTimer = -1;
    }
  }

  private isPeakNow(): boolean {
    // 读取 periodTick 建立刷新依赖，每 30 秒重估
    const _tick = this.periodTick;
    return PeakPeriod.isPeak(new Date());
  }

  private isWide(): boolean {
    return this.winWidth >= Dim.siderPermanentBp;
  }

  build() {
    SideBarContainer(SideBarContainerType.AUTO) {
      // 侧栏（overlay 抽屉时毛玻璃浮层）
      Column() {
        Sider({
          onSessionSelected: () => {
            if (!this.isWide()) {
              this.siderOpen = false;
            }
          },
        })
      }
      .width(Dim.siderWidth)
      .backgroundColor($r('app.color.blur_sider'))
      .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)

      // 主区（沉浸式：内容延伸至标题栏下方，标题栏毛玻璃分层）
      Column() {
        Stack({ alignContent: Alignment.Top }) {
          Column() {
            ChatView({
              onNeedKey: (): void => {
                this.pathStack.pushPathByName('settings', null);
              },
            })
          }
          .width('100%')
          .height('100%')
          .padding({ top: 60 })
          .backgroundColor($r('app.color.app_bg'))

          this.titleBar()
        }
        .width('100%')
        .height('100%')
      }
      .width('100%')
      .height('100%')
    }
    .showSideBar(this.isWide() || this.siderOpen)
    .autoHide(false)
    .showControlButton(false)
    .sideBarWidth(Dim.siderWidth)
    .minContentWidth(320)
    .onChange((open: boolean) => {
      if (!open && !this.isWide()) {
        this.siderOpen = false;
      }
    })
  }

  @Builder
  titleBar() {
    Row({ space: 12 }) {
      // 窄屏抽屉按钮（宽屏侧栏常驻，隐藏）
      Image($r('app.media.ic_public_drawer_filled'))
        .width(24)
        .height(24)
        .fillColor($r('app.color.titlebar_icon'))
        .padding(2)
        .visibility(this.isWide() ? Visibility.None : Visibility.Visible)
        .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.85 })
        .onClick(() => {
          this.siderOpen = !this.siderOpen;
        })
      Row({ space: 8 }) {
        Image($r('app.media.startIcon'))
          .width(28)
          .height(28)
          .borderRadius(Dim.radiusS)
        Text(I18n.translate('appName'))
          .fontSize(Fonts.headline8())
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        // 峰谷红绿灯：红=高峰时段，绿=空闲时段（点击查看说明）
        Circle({ width: 10, height: 10 })
          .fill(this.isPeakNow() ? $r('app.color.warning') : $r('app.color.success'))
          .accessibilityText(this.isPeakNow() ? I18n.translate('peakLightPeakNow') : I18n.translate('peakLightIdleNow'))
          .bindPopup(this.showPeakPopup, {
            builder: (): void => {
              this.peakPopup()
            },
            placement: Placement.Bottom,
            popupColor: $r('app.color.dialog_bg'),
            enableArrow: true,
            autoCancel: true,
            onStateChange: (e: PopupStateChangeParam) => {
              this.showPeakPopup = e.isVisible;
            },
          })
          .onClick(() => {
            this.showPeakPopup = !this.showPeakPopup;
          })
      }
      .alignItems(VerticalAlign.Center)

      Blank()

      Row({ space: 4 }) {
        // 新对话
        Image($r('app.media.ic_public_add'))
          .width(24)
          .height(24)
          .fillColor($r('app.color.titlebar_icon'))
          .padding(2)
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.85 })
          .onClick(() => {
            ChatStore.get().newSession();
          })
        // 设置
        Image($r('app.media.ic_public_settings'))
          .width(24)
          .height(24)
          .fillColor($r('app.color.titlebar_icon'))
          .padding(2)
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.85 })
          .onClick(() => {
            this.pathStack.pushPathByName('settings', null);
          })
      }
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(56)
    .padding({ left: Dim.pagePadding, right: 8 })
    .alignItems(VerticalAlign.Center)
    .backgroundBlurStyle(BlurStyle.COMPONENT_THIN)
    .backgroundColor($r('app.color.blur_titlebar'))
  }

  /** 峰谷说明悬浮窗 */
  @Builder
  peakPopup() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Circle({ width: 10, height: 10 })
          .fill(this.isPeakNow() ? $r('app.color.warning') : $r('app.color.success'))
        Text(this.isPeakNow() ? I18n.translate('peakLightPeak') : I18n.translate('peakLightIdle'))
          .fontSize(Fonts.body2())
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Text(this.isPeakNow() ? I18n.translate('peakLightNextIdle') : I18n.translate('peakLightNextPeak'))
          .fontSize(Fonts.caption())
          .fontColor($r('app.color.text_tertiary'))
      }
      .width('100%')

      Text(this.isPeakNow() ? I18n.translate('peakLightPeakNow') : I18n.translate('peakLightIdleNow'))
        .fontSize(Fonts.caption())
        .fontColor($r('app.color.text_secondary'))
        .width('100%')

      Text(I18n.translate('peakLightWindows'))
        .fontSize(Fonts.caption())
        .fontColor($r('app.color.text_tertiary'))
        .width('100%')

      Text(`${I18n.translate('peakLightBeijingTime')} ${PeakPeriod.formatBeijing(PeakPeriod.nextTransition(new Date()))}`)
        .fontSize(Fonts.caption())
        .fontColor($r('app.color.brand_activated'))
        .width('100%')
    }
    .padding(12)
    .width(248)
  }
}

/** 会话主视图（V2）：欢迎态 / 可见链消息列表 + 受控输入 */
@ComponentV2
struct ChatView {
  store: ChatStore = ChatStore.get();
  settings: SettingsStore = SettingsStore.get();
  @Local draft: string = '';
  @Local editingId: string = '';
  @Local draftFiles: FileAttachment[] = [];
  /** 排队消息：流式期间发送自动入队，回复结束按序自动发出 */
  @Local queue: QueuedSend[] = [];
  /** 「立即」待发项：停止当前流后优先发出 */
  private immediatePending: QueuedSend | null = null;
  @Param onNeedKey: () => void = () => {};

  aboutToAppear(): void {
    this.store.onStreamingEnd = (): void => this.drainOnStreamEnd();
  }

  aboutToDisappear(): void {
    if (this.store.onStreamingEnd === this.drainOnStreamEnd) {
      this.store.onStreamingEnd = null;
    }
  }

  /** 流结束：优先发出「立即」项，否则按序续发队首 */
  private drainOnStreamEnd(): void {
    if (this.immediatePending !== null) {
      const item = this.immediatePending;
      this.immediatePending = null;
      this.sendNow(item);
      return;
    }
    if (this.queue.length === 0) {
      return;
    }
    const head = this.queue[0];
    this.queue.splice(0, 1);
    this.sendNow(head);
  }

  private sendNow(item: QueuedSend): void {
    const files = this.settings.customModel ? [] : item.files;
    ReplyEngine.send(this.store.currentSessionId, item.text, files);
  }

  /** 「立即」：出队 → 停止当前流 → 立即发出 */
  private sendQueuedNow(item: QueuedSend): void {
    if (this.store.streamingSessionId !== null) {
      const idx = this.queue.indexOf(item);
      if (idx >= 0) {
        this.queue.splice(idx, 1);
      }
      this.immediatePending = item;
      ReplyEngine.stop(this.store.currentSessionId);
    }
    if (this.immediatePending === item && this.store.streamingSessionId === null) {
      this.immediatePending = null;
      this.sendNow(item);
    }
  }

  private removeQueued(item: QueuedSend): void {
    const idx = this.queue.indexOf(item);
    if (idx >= 0) {
      this.queue.splice(idx, 1);
    }
  }

  /** 可见链 usage 统计（@Computed：依赖 @Trace 自动重算） */
  @Computed
  get stat(): ContextStat {
    const stat = new ContextStat();
    for (const m of this.store.visible) {
      if (!isAssistant(m)) {
        continue;
      }
      const a = m as AssistantMessage;
      if (a.usage === null) {
        continue;
      }
      const u = a.usage;
      const inputSide = u.inputTokens + u.cacheReadInputTokens + u.cacheCreationInputTokens;
      stat.sessionInput += inputSide;
      stat.sessionOutput += u.outputTokens;
      stat.lastOutput = u.outputTokens;
      stat.used = inputSide + u.outputTokens;
    }
    return stat;
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      if (this.store.visible.length === 0) {
        Column() {
          Blank()
          Image($r('app.media.ic_public_message_filled'))
            .width(44)
            .height(44)
            .fillColor($r('app.color.brand'))
            .margin({ bottom: 20 })
          Text(I18n.translate('welcomeMessageChat250808'))
            .fontSize(Fonts.headline6())
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .fontFamily(Fonts.family())
            .textAlign(TextAlign.Center)
          Text(I18n.translate('portingFrom'))
            .fontSize(Fonts.caption())
            .fontColor($r('app.color.text_tertiary'))
            .margin({ top: 12 })
            .textAlign(TextAlign.Center)
          Blank()
        }
        .constraintSize({ maxWidth: Dim.contentMaxWidth })
        .width('100%')
        .height('100%')
        .padding({ bottom: 190 })
      } else {
        MessageList({
          session: this.store.current(),
          visible: this.store.visible,
          editingId: this.editingId,
          bottomPad: 190,
          onEdit: (m: UserMessage) => {
            this.editingId = m.id;
            this.draft = m.content;
          },
        })
        .width('100%')
        .height('100%')
      }

      Column() {
        if (this.queue.length > 0) {
          Column({ space: 6 }) {
            ForEach(this.queue, (q: QueuedSend) => {
              Row({ space: 8 }) {
                Image($r('app.media.ic_public_message_filled'))
                  .width(14)
                  .height(14)
                  .fillColor($r('app.color.text_tertiary'))
                Text(q.text)
                  .fontSize(Fonts.body3())
                  .fontColor($r('app.color.text_secondary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
                if (q.files.length > 0) {
                  Text(`+${q.files.length}`)
                    .fontSize(Fonts.caption())
                    .fontColor($r('app.color.text_tertiary'))
                }
                Text(I18n.translate('sendNow'))
                  .fontSize(Fonts.body3())
                  .fontColor($r('app.color.brand_activated'))
                  .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.9 })
                  .onClick(() => {
                    this.sendQueuedNow(q);
                  })
                Image($r('app.media.ic_public_close'))
                  .width(14)
                  .height(14)
                  .fillColor($r('app.color.text_tertiary'))
                  .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.85 })
                  .onClick(() => {
                    this.removeQueued(q);
                  })
              }
              .width('100%')
              .height(36)
              .padding({ left: 12, right: 12 })
              .backgroundColor($r('app.color.component_normal'))
              .borderRadius(Dim.radiusM)
            }, (q: QueuedSend) => q.id)
          }
          .width('100%')
          .padding({ left: Dim.pagePadding, right: Dim.pagePadding, bottom: 4 })
        }

        Text(I18n.translate('contentCaveat'))
          .fontSize(Fonts.caption())
          .fontColor($r('app.color.text_tertiary'))
          .margin({ bottom: 4 })

      ChatInput({
        text: this.draft,
        streaming: this.store.streamingSessionId !== null,
        editing: this.editingId !== '',
        files: this.draftFiles,
        contextUsed: this.stat.used,
        contextLimit: ModelInfo.CONTEXT_LIMIT,
        lastOutputTokens: this.stat.lastOutput,
        sessionInputTokens: this.stat.sessionInput,
        sessionOutputTokens: this.stat.sessionOutput,
        onTextChange: (v: string) => {
          this.draft = v;
        },
        onSend: (text: string) => {
          this.dispatchSend(text);
        },
        onCancelEdit: () => {
          this.editingId = '';
          this.draft = '';
        },
        onStop: () => {
          ReplyEngine.stop(this.store.currentSessionId);
        },
        onNeedKey: (): void => {
          this.onNeedKey();
        },
        onCompact: (): void => {
          this.doCompact();
        },
        onPickFiles: () => {
          AttachmentService.pick(this.draftFiles.length).then((picked: FileAttachment[]) => {
            for (const f of picked) {
              this.draftFiles.push(f);
            }
          }).catch(() => {});
        },
        onRemoveFile: (f: FileAttachment) => {
          const idx = this.draftFiles.indexOf(f);
          if (idx >= 0) {
            this.draftFiles.splice(idx, 1);
          }
        },
      })
      }
      .width('100%')
      .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THIN)
      .backgroundColor($r('app.color.blur_input'))
    }
    .constraintSize({ maxWidth: Dim.contentMaxWidth + 32 })
    .width('100%')
    .height('100%')
    .alignSelf(ItemAlign.Center)
  }

  /** 压缩会话：摘要请求 → 写入会话 → 提示结果 */
  private doCompact(): void {
    if (this.store.streamingSessionId !== null) {
      return;
    }
    this.getUIContext().getPromptAction()
      .showToast({ message: I18n.translate('compactRunning'), duration: 3000 });
    ReplyEngine.compact(this.store.currentSessionId).then((r: string) => {
      const key = r === 'ok' ? 'compactDone' : 'compactTooShort';
      this.getUIContext().getPromptAction().showToast({ message: I18n.translate(key), duration: 2000 });
    }).catch(() => {
      this.getUIContext().getPromptAction()
        .showToast({ message: I18n.translate('compactFailed'), duration: 2500 });
    });
  }

  private dispatchSend(text: string): void {
    // 斜杠命令：/compact 与 /压缩（会话）等价，触发会话压缩而非发送
    const trimmed = text.trim();
    const cmd = trimmed.toLowerCase();
    if (cmd === '/compact' || trimmed === '/压缩' || trimmed === '/压缩会话') {
      this.editingId = '';
      this.draft = '';
      this.draftFiles = [];
      this.doCompact();
      return;
    }
    // 流式期间：入队（回复结束后自动按序发出）
    if (this.store.streamingSessionId !== null) {
      const q = new QueuedSend();
      q.id = Id.next();
      q.text = trimmed;
      q.files = this.settings.customModel ? [] : this.draftFiles;
      this.queue.push(q);
      this.draft = '';
      this.draftFiles = [];
      this.editingId = '';
      this.getUIContext().getPromptAction()
        .showToast({ message: I18n.translate('messageQueued'), duration: 2000 });
      return;
    }
    let files = this.draftFiles;
    if (this.settings.customModel) {
      files = [];
    }
    this.draftFiles = [];
    if (this.editingId !== '') {
      const id = this.editingId;
      this.editingId = '';
      this.draft = '';
      ReplyEngine.sendEdited(this.store.currentSessionId, id, text, files);
    } else {
      this.draft = '';
      ReplyEngine.send(this.store.currentSessionId, text, files);
    }
  }
}

/** 排队待发消息 */
export class QueuedSend {
  id: string = '';
  text: string = '';
  files: FileAttachment[] = [];
}

/** 会话上下文用量统计 */
export class ContextStat {
  used: number = 0;
  lastOutput: number = 0;
  sessionInput: number = 0;
  sessionOutput: number = 0;
}
