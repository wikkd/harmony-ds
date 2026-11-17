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
import { UserMessage } from '../model/ChatTypes';
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
      SettingsPlaceholderPage({ pathStack: this.pathStack })
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
      })
    }
    .constraintSize({ maxWidth: Dim.contentMaxWidth + 32 })
    .width('100%')
    .height('100%')
    .alignSelf(ItemAlign.Center)
  }

  private dispatchSend(text: string): void {
    if (this.editingId !== '') {
      const id = this.editingId;
      this.editingId = '';
      this.draft = '';
      ReplyEngine.sendEdited(this.store.currentSessionId, id, text);
    } else {
      this.draft = '';
      ReplyEngine.send(this.store.currentSessionId, text);
    }
  }
}

/** M1 设置占位页：含 API Key 录入/验证（M5 替换为完整设置面板） */
@Component
struct SettingsPlaceholderPage {
  pathStack: NavPathStack = new NavPathStack();
  @State apiKey: string = '';
  @State verifyState: 'idle' | 'verifying' | 'ok' | 'fail' = 'idle';
  @State verifyMsg: string = '';
  @StorageLink('hasApiKey') hasApiKey: boolean = false;

  aboutToAppear(): void {
    KeyVault.load(AppContextHolder.get()).then((k: string | null) => {
      if (k !== null) {
        this.apiKey = k;
        this.verifyState = 'ok';
      }
    }).catch(() => {});
  }

  build() {
    NavDestination() {
      Column() {
        Row() {
          Image($r('app.media.ic_public_back'))
            .width(24)
            .height(24)
            .fillColor($r('app.color.titlebar_icon'))
            .onClick(() => {
              this.pathStack.pop();
            })
          Text(I18n.translate('settings'))
            .fontSize($r('app.float.font_headline8'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .margin({ left: 12 })
          Blank()
        }
        .width('100%')
        .height(56)
        .padding({ left: Dim.pagePadding, right: Dim.pagePadding })

        List({ space: 2 }) {
          ListItem() {
            Column({ space: 8 }) {
              Text(I18n.translate('apiKeyEdit'))
                .fontSize($r('app.float.font_body1'))
                .fontColor($r('app.color.text_primary'))
                .width('100%')
              Row({ space: 8 }) {
                TextInput({
                  text: this.apiKey,
                  placeholder: I18n.translate('apiKeyPlaceholder'),
                })
                  .type(InputType.Password)
                  .fontSize($r('app.float.font_body2'))
                  .fontColor($r('app.color.text_primary'))
                  .placeholderColor($r('app.color.text_tertiary'))
                  .backgroundColor($r('app.color.text_field_sub_bg'))
                  .borderRadius(Dim.radiusS)
                  .layoutWeight(1)
                  .onChange((v: string) => {
                    this.apiKey = v;
                    this.verifyState = 'idle';
                  })

                Button(this.verifyState === 'verifying' ? I18n.translate('apiKeyVerifying') : I18n.translate('confirm'))
                  .fontSize($r('app.float.font_body2'))
                  .backgroundColor($r('app.color.brand'))
                  .fontColor($r('app.color.text_primary_contrary'))
                  .enabled(this.verifyState !== 'verifying' && this.apiKey.trim().length > 0)
                  .onClick(() => {
                    this.verify();
                  })
              }
              .width('100%')

              if (this.verifyState === 'ok') {
                Text(I18n.translate('apiKeyStart'))
                  .fontSize($r('app.float.font_body3'))
                  .fontColor($r('app.color.success'))
                  .width('100%')
              } else if (this.verifyState === 'fail') {
                Text(this.verifyMsg)
                  .fontSize($r('app.float.font_body3'))
                  .fontColor($r('app.color.warning'))
                  .width('100%')
              }
            }
            .padding(Dim.pagePadding)
            .backgroundColor($r('app.color.card_bg'))
            .borderRadius(Dim.radiusM)
          }

          ListItem() {
            Row() {
              Text(I18n.translate('privacyPolicyTitle'))
                .fontSize($r('app.float.font_body1'))
                .fontColor($r('app.color.text_primary'))
              Blank()
              Image($r('app.media.ic_public_arrow_right'))
                .width(16)
                .height(16)
                .fillColor($r('app.color.text_tertiary'))
            }
            .width('100%')
            .height(Dim.listRowHeight)
            .padding({ left: Dim.pagePadding, right: Dim.pagePadding })
            .backgroundColor($r('app.color.card_bg'))
            .borderRadius(Dim.radiusM)
            .onClick(() => {
              this.pathStack.pushPathByName('privacy', null);
            })
          }

          ListItem() {
            ThemeRow()
          }
        }
        .width('100%')
        .padding(Dim.pagePadding)
        .margin({ top: 8 })
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.app_bg'))
    }
    .title('')
    .backgroundColor($r('app.color.app_bg'))
  }

  private verify(): void {
    const key = this.apiKey.trim();
    if (key === '') {
      return;
    }
    this.verifyState = 'verifying';
    ApiClient.verifyApiKey(key).then(() => {
      return KeyVault.save(AppContextHolder.get(), key).then(() => {
        this.verifyState = 'ok';
        this.hasApiKey = true;
        AppStorage.setOrCreate<boolean>('hasApiKey', true);
      });
    }).catch((err: ApiError) => {
      this.verifyState = 'fail';
      this.verifyMsg = I18n.translate(ApiError.i18nKeyFor(err));
      Logger.warn('Settings', `verify failed: ${JSON.stringify(err.message)}`);
    });
  }
}

@Component
struct ThemeRow {
  settings: SettingsStore = SettingsStore.get();

  private themeLabel(): string {
    const pref = this.settings.themePreference;
    if (pref === 'light') {
      return I18n.translate('avatarMenuSettingsDialogThemeSelectLightOption');
    }
    if (pref === 'dark') {
      return I18n.translate('avatarMenuSettingsDialogThemeSelectDarkOption');
    }
    return I18n.translate('avatarMenuSettingsDialogThemeSelectSystemOption');
  }

  private applyAndSave(): void {
    try {
      ThemeHelper.apply(AppContextHolder.get(), this.settings.themePreference);
    } catch (err) {
      // AppContextHolder 未就绪时忽略，EntryAbility 启动时会再应用
    }
  }

  build() {
    Row() {
      Text(I18n.translate('avatarMenuSettingsDialogThemeItemLabel'))
        .fontSize($r('app.float.font_body1'))
        .fontColor($r('app.color.text_primary'))
      Blank()
      Text(this.themeLabel())
        .fontSize($r('app.float.font_body2'))
        .fontColor($r('app.color.brand_activated'))
        .onClick(() => {
          if (this.settings.themePreference === 'light') {
            this.settings.setThemePreference('dark');
          } else if (this.settings.themePreference === 'dark') {
            this.settings.setThemePreference('system');
          } else {
            this.settings.setThemePreference('light');
          }
          this.applyAndSave();
        })
    }
    .width('100%')
    .height(Dim.listRowHeight)
    .padding({ left: Dim.pagePadding, right: Dim.pagePadding })
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(Dim.radiusM)
  }
}
