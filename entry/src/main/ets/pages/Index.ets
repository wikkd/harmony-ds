import { Fonts } from '../common/Fonts';
import { KeyboardAvoidMode } from '@ohos.arkui.UIContext';
import { common } from '@kit.AbilityKit';
import { I18n } from '../common/I18n';
import { SettingsStore } from '../prefs/SettingsStore';
import { ThemeHelper } from '../common/ThemeHelper';
import { AppContextHolder } from '../common/AppContextHolder';
import { ApiClient } from '../service/api/ApiClient';
import { ApiError } from '../model/ApiError';
import { KeyVault } from '../prefs/KeyVault';
import { ChatStore } from '../service/chat/ChatStore';
import { ReplyEngine } from '../service/chat/ReplyEngine';
import { Dim } from '../common/DesignTokens';
import { DrawerButton, StatusCapsule } from '../components/titlebar/TopControls';
import { LegalDocPage, LegalSection, buildPrivacySections, buildAgreementSections } from '../components/privacy/LegalDocPage';
import { MessageList } from '../components/messages/MessageList';
import { ChatInput } from '../components/chatinput/ChatInput';
import { Sider } from '../components/sider/Sider';
import { SettingsPage } from '../components/settings/SettingsPage';
import { ModelConfigPage } from '../components/settings/ModelConfigPage';
import { DataManagePage } from '../components/settings/DataManagePage';
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

  aboutToAppear(): void {
    // 键盘避让改压缩模式：默认 OFFSET 整窗上移会把标题栏顶出屏幕；
    // RESIZE 压缩窗口高度，标题栏/欢迎区保持原位，输入面板整体浮到键盘上方
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
    // 首启隐私合规：未同意前强制弹窗，拒绝则退出应用（上架审核要求）
    if (!SettingsStore.get().privacyAccepted) {
      this.showPrivacyConsent();
    }
  }

  /** 首启隐私/协议同意弹窗：不可点外关闭，拒绝即退出，下次启动再问 */
  private showPrivacyConsent(): void {
    this.getUIContext().showAlertDialog({
      title: I18n.translate('privacyConsentTitle'),
      message: I18n.translate('privacyConsentMessage'),
      alignment: DialogAlignment.Center,
      autoCancel: false,
      secondaryButton: {
        value: I18n.translate('privacyConsentDecline'),
        fontColor: $r('app.color.text_secondary'),
        action: (): void => {
          // 拒绝即退出：不写入同意标记，下次启动再次询问
          (this.getUIContext().getHostContext() as common.UIAbilityContext).terminateSelf().catch(() => {});
        },
      },
      primaryButton: {
        value: I18n.translate('privacyConsentAgree'),
        fontColor: $r('app.color.brand_activated'),
        action: (): void => {
          SettingsStore.get().setPrivacyAccepted(true);
        },
      },
    });
  }

  /** 窄屏抽屉展开时，返回键/返回手势先收起抽屉 */
  onBackPress(): boolean {
    const narrow = (AppStorage.get<number>('bpWindowWidth') ?? 0) < Dim.siderPermanentBp;
    const progress = AppStorage.get<number>('drawerProgress') ?? 0;
    if (narrow && progress > 0.01) {
      this.getUIContext().animateTo({ duration: 300, curve: Curve.Smooth }, (): void => {
        AppStorage.setOrCreate<number>('drawerProgress', 0);
      });
      return true;
    }
    return false;
  }

  build() {
    // Navigation 作为页面根：唯一可交互层，内部承载主页与子页面。
    // （不能用「透明 Navigation 叠在主页上」的结构——空 Navigation 也会拦截全部触摸）
    Navigation(this.pathStack) {
      HomePage({ pathStack: this.pathStack })
    }
    .navDestination(this.pageMap)
    .hideTitleBar(true)
    .hideToolBar(true)
    .backgroundColor($r('app.color.app_bg'))
    .mode(NavigationMode.Stack)
    // 沉浸式：Navigation 自身扩展进状态栏/手势条避让区，
    // 内容（主页标题栏、抽屉、遮罩）才能真正铺到屏幕物理边缘
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    // 注意：Navigation 不能加底部 padding —— 会在内容与导航条之间留下白色背景条；
    // 底部避让只由主页输入区自己承担（各子页背景直接铺到屏幕底）
  }

  @Builder
  pageMap(name: string) {
    if (name === 'privacy') {
      LegalDocPage({ titleKey: 'privacyPolicyTitle', sections: buildPrivacySections() })
    } else if (name === 'agreement') {
      LegalDocPage({ titleKey: 'userAgreementTitle', sections: buildAgreementSections() })
    } else if (name === 'settings') {
      SettingsPage({ pathStack: this.pathStack })
    } else if (name === 'usage') {
      UsagePage()
    } else if (name === 'persona') {
      PersonaPage()
    } else if (name === 'model') {
      ModelConfigPage({ pathStack: this.pathStack })
    } else if (name === 'data') {
      DataManagePage({ pathStack: this.pathStack })
    }
  }
}

@Component
struct HomePage {
  pathStack: NavPathStack = new NavPathStack();
  @StorageProp('safeBottomVp') safeBottom: number = 0;
  /** 抽屉进度 0 收起 / 1 展开：驱动侧栏滑入与主内容推出，AppStorage 供 Index.onBackPress 读取 */
  @StorageLink('drawerProgress') drawerProgress: number = 0;
  @StorageLink('bpWindowWidth') winWidth: number = 0;
  /** 拖动过程中的起始进度与有效标记 */
  private dragBase: number = 0;
  private dragActive: boolean = false;

  private isWide(): boolean {
    return this.winWidth >= Dim.siderPermanentBp;
  }

  build() {
    Stack({ alignContent: Alignment.Start }) {
      // 主内容：抽屉展开时被整体向右推出屏幕，收起时拉回
      Column() {
        Stack({ alignContent: Alignment.Top }) {
          Column() {
            ChatView({
              safeBottom: this.safeBottom,
              onNeedKey: (): void => {
                this.pathStack.pushPathByName('settings', null);
              },
            })
          }
          .width('100%')
          .height('100%')
          .backgroundColor($r('app.color.app_bg'))
          // 聊天页延伸到物理上下边缘：列表视口与输入面板都铺满，底部不留安全区死空间
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

          // 顶部浮层控件行：左抽屉钮、右胶囊（毛玻璃半遮挡）。
          // 用 Row+padding 定位——position 下的 margin 不生效
          Row() {
            DrawerButton({
              onTap: (): void => {
                if (this.drawerProgress > 0.5) {
                  this.closeDrawer();
                } else {
                  this.openDrawer();
                }
              },
            })
              .visibility(this.isWide() ? Visibility.None : Visibility.Visible)
            Blank()
            StatusCapsule({
              onOpenSettings: (): void => {
                this.pathStack.pushPathByName('settings', null);
              },
            })
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
          .padding({ left: 12, right: 12, top: 12 })
        }
        .width('100%')
        .height('100%')
      }
      .width('100%')
      .height('100%')
      // 宽屏常驻侧栏必须用 padding 让位（布局级）：translate 不改布局宽度，
      // width('100%') 子件仍按全窗宽居中/铺开，欢迎态与输入面板会整体右偏、右缘被裁。
      // translate 只承担窄屏抽屉动画。
      .padding({ left: this.isWide() ? Dim.siderWidth : 0 })
      .translate({ x: this.contentShift() })

      // 抽屉展开期间的透明触控层：无压暗、无渐变，仅用于点击空白处收起抽屉
      if (!this.isWide() && this.drawerProgress > 0.01) {
        Column()
          .width('100%')
          .height('100%')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .onClick(() => {
            this.closeDrawer();
          })
      }

      // 侧栏抽屉：实底面板直接从屏幕左缘拉出（宽屏常驻），无投影无渐变，边缘干净
      Column() {
        Sider({
          onSessionSelected: () => {
            if (!this.isWide()) {
              this.closeDrawer();
            }
          },
        })
      }
      .width(Dim.siderWidth)
      .height('100%')
      .backgroundColor($r('app.color.sider_bg'))
      .translate({ x: this.siderShift() })
      // 上下扩展只作用于绘制：灰底铺进状态栏/手势条区域，内容仍在安全区内排布
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .visibility(this.isWide() || this.drawerProgress > 0.01 ? Visibility.Visible : Visibility.None)
    }
    .width('100%')
    .height('100%')
    // 整页沉浸到物理边缘：状态栏与手势条区域都铺底色，不再有安全区分界线
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    // 平行手势：横向拖动驱动抽屉，不拦截列表纵向滚动与子件点击
    .parallelGesture(this.drawerPan())
  }

  /** 主内容水平位移：宽屏由 padding 让位（位移 0），窄屏随抽屉进度向右推出 */
  private contentShift(): number {
    return this.isWide() ? 0 : Dim.siderWidth * this.drawerProgress;
  }

  /** 侧栏水平位移：收起时完全藏在屏幕左缘外 */
  private siderShift(): number {
    return this.isWide() ? 0 : (this.drawerProgress - 1) * Dim.siderWidth;
  }

  private openDrawer(): void {
    this.getUIContext().animateTo({ duration: 300, curve: Curve.Smooth }, (): void => {
      this.drawerProgress = 1;
    });
  }

  private closeDrawer(): void {
    this.getUIContext().animateTo({ duration: 300, curve: Curve.Smooth }, (): void => {
      this.drawerProgress = 0;
    });
  }

  /** 抽屉横向拖动：展开时任意位置拖回，收起时仅左缘 80vp 内可拖出；松手按进度/速度吸附 */
  private drawerPan(): PanGestureInterface {
    return PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 10 })
      .onActionStart((e: GestureEvent) => {
        this.dragBase = this.drawerProgress;
        const startX = e.fingerList.length > 0 ? e.fingerList[0].globalX : 0;
        this.dragActive = !this.isWide() && (this.dragBase > 0.01 || startX <= 80);
      })
      .onActionUpdate((e: GestureEvent) => {
        if (!this.dragActive || this.isWide()) {
          return;
        }
        const p = this.dragBase + e.offsetX / Dim.siderWidth;
        this.drawerProgress = Math.min(Math.max(p, 0), 1);
      })
      .onActionEnd((e: GestureEvent) => {
        if (!this.dragActive) {
          return;
        }
        this.dragActive = false;
        if (this.drawerProgress > 0.5 || e.velocityX > 360) {
          this.openDrawer();
        } else {
          this.closeDrawer();
        }
      })
      .onActionCancel(() => {
        if (!this.dragActive) {
          return;
        }
        this.dragActive = false;
        if (this.drawerProgress > 0.5) {
          this.openDrawer();
        } else {
          this.closeDrawer();
        }
      });
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
  /** 输入面板实际高度（vp）：列表底部留白按它动态计算，不再写死 */
  @Local dockH: number = 170;
  /** 「立即」待发项：停止当前流后优先发出 */
  private immediatePending: QueuedSend | null = null;
  @Param onNeedKey: () => void = () => {};
  /** 手势条高度（vp）：输入区底部避让 */
  @Param safeBottom: number = 0;

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

  /** 「立即」：出队 → 停止当前流，由 onStreamingEnd 统一优先发出（避免与回调竞态） */
  private sendQueuedNow(item: QueuedSend): void {
    const idx = this.queue.indexOf(item);
    if (idx >= 0) {
      this.queue.splice(idx, 1);
    }
    const streamingId = this.store.streamingSessionId;
    if (streamingId !== null) {
      this.immediatePending = item;
      ReplyEngine.stop(streamingId);
      return;
    }
    this.sendNow(item);
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
      // 消息区：列表/欢迎页占满，提示语在底部输入面板下方
      Column() {
        if (this.store.visible.length === 0) {
          Column() {
            Blank()
            Image($r('app.media.ic_public_message_filled'))
              .width(56)
              .height(56)
              .fillColor($r('app.color.brand'))
              .margin({ bottom: 20 })
            Text(I18n.translate('welcomeMessageChat250808'))
              .fontSize(Fonts.headline6())
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .textAlign(TextAlign.Center)
            Blank()
          }
          .constraintSize({ maxWidth: Dim.contentMaxWidth })
          .width('100%')
          .layoutWeight(1)
          .padding({ bottom: 190 })
        } else {
          MessageList({
            session: this.store.current(),
            visible: this.store.visible,
            editingId: this.editingId,
            bottomPad: this.dockH + 10,
            onEdit: (m: UserMessage) => {
              this.editingId = m.id;
              this.draft = m.content;
            },
          })
          .width('100%')
          .layoutWeight(1)
        }
      }
      .width('100%')
      .height('100%')

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

      // 面板水平留白由父容器承担（子组件 width('100%') + margin 不生效）
      Column() {
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
        onCapture: (): void => {
          this.attachFiles(AttachmentService.capture(this.draftFiles.length));
        },
        onPickPhotos: (): void => {
          this.attachFiles(AttachmentService.pickPhotos(this.draftFiles.length));
        },
        onPickDocs: (): void => {
          this.attachFiles(AttachmentService.pickDocs(this.draftFiles.length));
        },
        onRemoveFile: (f: FileAttachment) => {
          const idx = this.draftFiles.indexOf(f);
          if (idx >= 0) {
            this.draftFiles.splice(idx, 1);
          }
        },
      })
      }
      .padding({ left: Dim.pagePadding, right: Dim.pagePadding })
      .width('100%')

      // AI 生成提示：对话框下方、导航条（手势条）上方
      if (this.store.visible.length > 0) {
        Text(I18n.translate('contentCaveat'))
          .fontSize(Fonts.caption())
          .fontColor($r('app.color.text_tertiary'))
          .textAlign(TextAlign.Center)
          .width('100%')
          .margin({ top: 2 })
      }
      }
      .width('100%')
      // 手势条为半透明浮层，底部少避让 20vp 让输入面板贴近屏幕底（对齐官方观感）
      .padding({ bottom: Math.max(this.safeBottom - 20, 8) })
      .onAreaChange((_o: Area, nv: Area) => {
        this.dockH = Number(nv.height);
      })
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
    // 空会话没有可压缩的上下文：直接拒绝，不发摘要请求
    if (this.store.visible.length === 0) {
      this.getUIContext().getPromptAction()
        .showToast({ message: I18n.translate('compactEmpty'), duration: 2000 });
      return;
    }
    // 低上下文压缩无意义：摘要丢细节还白耗一次请求，占用达到阈值才允许
    const minTokens = ModelInfo.CONTEXT_LIMIT * ModelInfo.COMPACT_MIN_RATIO;
    if (this.stat.used < minTokens) {
      const percent = `${Math.round(ModelInfo.COMPACT_MIN_RATIO * 100)}%`;
      this.getUIContext().getPromptAction()
        .showToast({ message: I18n.translate('compactLowContext', { 'percent': percent }), duration: 2000 });
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

  /** 附件选择结果并入草稿 */
  private attachFiles(pending: Promise<FileAttachment[]>): void {
    pending.then((picked: FileAttachment[]) => {
      for (const f of picked) {
        this.draftFiles.push(f);
      }
    }).catch(() => {});
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
    // 上下文将满：弹窗询问是否先压缩再发送（编辑重发同样适用）
    if (ModelInfo.isContextFull(this.stat.used)) {
      const editingId = this.editingId;
      this.editingId = '';
      this.draft = '';
      this.confirmCompactThenSend(text, files, editingId);
      return;
    }
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

  /** 上下文将满的发送确认：压缩并发送（成功后自动续发）/ 直接发送 */
  private confirmCompactThenSend(text: string, files: FileAttachment[], editingId: string): void {
    const deliver = (): void => {
      if (editingId !== '') {
        ReplyEngine.sendEdited(this.store.currentSessionId, editingId, text, files);
      } else {
        ReplyEngine.send(this.store.currentSessionId, text, files);
      }
    };
    this.getUIContext().showAlertDialog({
      title: I18n.translate('compactAskTitle'),
      message: I18n.translate('compactAskMessage'),
      alignment: DialogAlignment.Center,
      autoCancel: true,
      secondaryButton: {
        value: I18n.translate('compactAskSendOnly'),
        fontColor: $r('app.color.text_secondary'),
        action: (): void => {
          deliver();
        },
      },
      primaryButton: {
        value: I18n.translate('compactAskCompactSend'),
        fontColor: $r('app.color.brand_activated'),
        action: (): void => {
          this.getUIContext().getPromptAction()
            .showToast({ message: I18n.translate('compactRunning'), duration: 3000 });
          ReplyEngine.compact(this.store.currentSessionId).then((): void => {
            deliver();
          }).catch((): void => {
            // 压缩失败不阻断发送：上下文若真超限由 API 错误路径提示
            this.getUIContext().getPromptAction()
              .showToast({ message: I18n.translate('compactFailed'), duration: 2500 });
            deliver();
          });
        },
      },
    });
  }
}

/** 排队待发消息 */
class QueuedSend {
  id: string = '';
  text: string = '';
  files: FileAttachment[] = [];
}

/** 会话上下文用量统计 */
class ContextStat {
  used: number = 0;
  lastOutput: number = 0;
  sessionInput: number = 0;
  sessionOutput: number = 0;
}
