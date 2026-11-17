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
import { PrivacyPolicyPage } from '../components/privacy/PrivacyPolicyPage';
import { MessageList } from '../components/messages/MessageList';
import { ChatInput } from '../components/chatinput/ChatInput';
import { Sider } from '../components/sider/Sider';
import { SettingsPage } from '../components/settings/SettingsPage';
import { UserMessage, FileAttachment } from '../model/ChatTypes';
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

  build() {
    Navigation(this.pathStack) {
      HomePage({ pathStack: this.pathStack })
    }
    .navDestination(this.pageMap)
    .hideTitleBar(true)
    .hideToolBar(true)
    .backgroundColor($r('app.color.app_bg'))
    .mode(NavigationMode.Stack)
  }

  @Builder
  pageMap(name: string) {
    if (name === 'privacy') {
      PrivacyPolicyPage()
    } else if (name === 'settings') {
      SettingsPage()
    }
  }
}

@Component
struct HomePage {
  pathStack: NavPathStack = new NavPathStack();
  @State siderOpen: boolean = false;
  @StorageLink('bpWindowWidth') winWidth: number = 0;

  private isWide(): boolean {
    return this.winWidth >= Dim.siderPermanentBp;
  }

  build() {
    SideBarContainer(SideBarContainerType.Embed) {
      // 侧栏
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
      .backgroundColor($r('app.color.sub_bg'))

      // 主区
      Column() {
        this.titleBar()
        Divider()
          .color($r('app.color.list_separator'))
          .strokeWidth(Dim.separator)
        ChatView()
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.app_bg'))
    }
    .showSideBar(this.isWide() || this.siderOpen)
    .autoHide(false)
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
    Row() {
      Row({ space: 8 }) {
        Image($r('app.media.startIcon'))
          .width(28)
          .height(28)
          .borderRadius(Dim.radiusS)
          .onClick(() => {
            if (!this.isWide()) {
              this.siderOpen = !this.siderOpen;
            }
          })
        Text(I18n.translate('appName'))
          .fontSize($r('app.float.font_headline8'))
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .onClick(() => {
            if (!this.isWide()) {
              this.siderOpen = !this.siderOpen;
            }
          })
      }
      .alignItems(VerticalAlign.Center)

      Blank()

      Row({ space: 4 }) {
        // 窄屏抽屉按钮
        Image($r('app.media.ic_public_drawer_filled'))
          .width(24)
          .height(24)
          .fillColor($r('app.color.titlebar_icon'))
          .padding(2)
          .visibility(this.isWide() ? Visibility.None : Visibility.Visible)
          .onClick(() => {
            this.siderOpen = !this.siderOpen;
          })
        // 新对话
        Image($r('app.media.ic_public_add'))
          .width(24)
          .height(24)
          .fillColor($r('app.color.titlebar_icon'))
          .padding(2)
          .onClick(() => {
            ChatStore.get().newSession();
          })
        // 设置
        Image($r('app.media.ic_public_settings'))
          .width(24)
          .height(24)
          .fillColor($r('app.color.titlebar_icon'))
          .padding(2)
          .onClick(() => {
            this.pathStack.pushPathByName('settings', null);
          })
      }
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(56)
    .padding({ left: Dim.pagePadding + 32, right: 8 })
    .alignItems(VerticalAlign.Center)
  }
}

/** 会话主视图（V2）：欢迎态 / 可见链消息列表 + 受控输入 */
@ComponentV2
struct ChatView {
  store: ChatStore = ChatStore.get();
  @Local draft: string = '';
  @Local editingId: string = '';
  @Local draftFiles: FileAttachment[] = [];

  build() {
    Column() {
      if (this.store.visible.length === 0) {
        Column() {
          Blank()
          Text(I18n.translate('welcomeMessageChat250808'))
            .fontSize($r('app.float.font_headline6'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .textAlign(TextAlign.Center)
          Text(I18n.translate('portingFrom'))
            .fontSize($r('app.float.font_caption'))
            .fontColor($r('app.color.text_tertiary'))
            .margin({ top: 12 })
            .textAlign(TextAlign.Center)
          Blank()
        }
        .constraintSize({ maxWidth: Dim.contentMaxWidth })
        .width('100%')
        .layoutWeight(1)
      } else {
        MessageList({
          session: this.store.current(),
          visible: this.store.visible,
          editingId: this.editingId,
          onEdit: (m: UserMessage) => {
            this.editingId = m.id;
            this.draft = m.content;
          },
        })
      }

      Text(I18n.translate('contentCaveat'))
        .fontSize($r('app.float.font_caption'))
        .fontColor($r('app.color.text_tertiary'))
        .margin({ bottom: 4 })

      ChatInput({
        text: this.draft,
        streaming: this.store.streamingSessionId !== null,
        editing: this.editingId !== '',
        files: this.draftFiles,
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
        onPickFiles: () => {
          AttachmentService.pick().then((picked: FileAttachment[]) => {
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
    .constraintSize({ maxWidth: Dim.contentMaxWidth + 32 })
    .width('100%')
    .height('100%')
    .alignSelf(ItemAlign.Center)
  }

  private dispatchSend(text: string): void {
    const files = this.draftFiles;
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
