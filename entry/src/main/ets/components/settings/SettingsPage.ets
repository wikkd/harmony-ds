import { I18n } from '../../common/I18n';
import { Dim } from '../../common/DesignTokens';
import { SettingsStore } from '../../prefs/SettingsStore';
import { KeyVault } from '../../prefs/KeyVault';
import { ApiClient } from '../../service/api/ApiClient';
import { ApiError } from '../../service/api/ApiError';
import { AppContextHolder } from '../../common/AppContextHolder';
import { ThemeHelper } from '../../common/ThemeHelper';
import { ChatStore } from '../../service/chat/ChatStore';
import { UserLocation } from '../../model/SettingsTypes';
import { promptAction } from '@kit.ArkUI';
import { Logger } from '../../common/Logger';

/** 省份/地区（位置信息用于联网搜索本地化） */
const PROVINCES: string[] = [
  '北京', '天津', '河北', '山西', '内蒙古', '辽宁', '吉林', '黑龙江', '上海', '江苏',
  '浙江', '安徽', '福建', '江西', '山东', '河南', '湖北', '湖南', '广东', '广西',
  '海南', '重庆', '四川', '贵州', '云南', '西藏', '陕西', '甘肃', '青海', '宁夏', '新疆',
  '香港', '澳门', '台湾',
];

/** 完整设置页（List+SubHeader 鸿蒙布局） */
@ComponentV2
export struct SettingsPage {
  pathStack: NavPathStack = new NavPathStack();
  settings: SettingsStore = SettingsStore.get();
  store: ChatStore = ChatStore.get();
  @Local apiKey: string = '';
  @Local verifyState: 'idle' | 'verifying' | 'ok' | 'fail' = 'idle';
  @Local verifyMsg: string = '';
  @Local provincePicker: boolean = false;

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
      Stack() {
        Scroll() {
          Column({ space: 12 }) {
            // ---------- API Key ----------
            this.subHeader(I18n.translate('apiKeyEdit'))
            Column({ space: 8 }) {
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
            .padding(Dim.cardPadding)
            .backgroundColor($r('app.color.card_bg'))
            .borderRadius(Dim.radiusM)
            .width('100%')

            // ---------- 通用 ----------
            this.subHeader(I18n.translate('settingDialogAsideGeneralOptionLabel'))

            this.row(I18n.translate('settingsLocalePreference'), this.localeLabel(), (): void => {
              this.settings.setLocale(this.settings.locale === 'zh-CN' ? 'en-US' : 'zh-CN');
            })

            this.row(I18n.translate('avatarMenuSettingsDialogThemeItemLabel'), this.themeLabel(), (): void => {
              if (this.settings.themePreference === 'light') {
                this.settings.setThemePreference('dark');
              } else if (this.settings.themePreference === 'dark') {
                this.settings.setThemePreference('system');
              } else {
                this.settings.setThemePreference('light');
              }
              this.applyTheme();
            })

            this.row(I18n.translate('settingsLocation'), this.locationLabel(), (): void => {
              this.provincePicker = !this.provincePicker;
            })

            if (this.provincePicker) {
              Column() {
                Text(I18n.translate('settingsLocationProvince'))
                  .fontSize($r('app.float.font_body3'))
                  .fontColor($r('app.color.text_tertiary'))
                  .width('100%')
                // 省份网格
                Flex({ wrap: FlexWrap.Wrap }) {
                  ForEach(PROVINCES, (p: string) => {
                    Text(p)
                      .fontSize($r('app.float.font_body3'))
                      .fontColor($r('app.color.text_primary'))
                      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                      .margin(4)
                      .backgroundColor($r('app.color.component_normal'))
                      .borderRadius(Dim.radiusS)
                      .onClick(() => {
                        const loc = new UserLocation();
                        loc.region = 'CN';
                        loc.province = p;
                        this.settings.setLocation(loc);
                        this.provincePicker = false;
                      })
                  }, (p: string) => p)
                }
                .width('100%')
                Text(I18n.translate('cancel'))
                  .fontSize($r('app.float.font_body3'))
                  .fontColor($r('app.color.brand_activated'))
                  .padding(6)
                  .onClick(() => {
                    this.settings.setLocation(null);
                    this.provincePicker = false;
                  })
              }
              .padding(Dim.cardPadding)
              .backgroundColor($r('app.color.card_bg'))
              .borderRadius(Dim.radiusM)
              .width('100%')
            }

            this.row(I18n.translate('thinkingSwitch'), this.settings.thinking ? '✓' : '', (): void => {
              this.settings.setThinking(!this.settings.thinking);
            })

            this.row(I18n.translate('search'), this.settings.search ? '✓' : '', (): void => {
              this.settings.setSearch(!this.settings.search);
            })

            this.row(I18n.translate('settingsTtsVoice'), this.voiceLabel(), (): void => {
              this.settings.setTtsVoice(this.settings.ttsVoice === 'stella' ? 'tide' : 'stella');
            })

            // ---------- 数据管理 ----------
            this.subHeader(I18n.translate('settingDialogAsideDataOptionLabel'))

            this.row(I18n.translate('deleteAllSessions'), '', (): void => {
              this.confirmDeleteAll();
            })

            this.row(I18n.translate('historyImport') + ' / ' + I18n.translate('exportAllLabel'), '', (): void => {
              promptAction.showToast({ message: 'M8', duration: 1200 });
            })

            // ---------- 关于 ----------
            this.subHeader(I18n.translate('about'))

            Column({ space: 6 }) {
              Row() {
                Text(I18n.translate('version'))
                  .fontSize($r('app.float.font_body1'))
                  .fontColor($r('app.color.text_primary'))
                Blank()
                Text('1.0.0')
                  .fontSize($r('app.float.font_body2'))
                  .fontColor($r('app.color.text_secondary'))
              }
              .width('100%')

              Row() {
                Text(I18n.translate('serverAddress'))
                  .fontSize($r('app.float.font_body1'))
                  .fontColor($r('app.color.text_primary'))
                Blank()
                Text(this.settings.apiOrigin)
                  .fontSize($r('app.float.font_caption'))
                  .fontColor($r('app.color.text_secondary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .constraintSize({ maxWidth: '55%' })
              }
              .width('100%')

              Text(I18n.translate('portingFrom'))
                .fontSize($r('app.float.font_caption'))
                .fontColor($r('app.color.text_tertiary'))
                .width('100%')
            }
            .padding(Dim.cardPadding)
            .backgroundColor($r('app.color.card_bg'))
            .borderRadius(Dim.radiusM)
            .width('100%')
          }
          .padding(Dim.pagePadding)
          .constraintSize({ maxWidth: Dim.contentMaxWidth })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.Top)
      }
      .width('100%')
      .height('100%')
    }
    .title(I18n.translate('settings'))
    .backgroundColor($r('app.color.app_bg'))
  }

  @Builder
  subHeader(title: string) {
    Text(title)
      .fontSize($r('app.float.font_body2'))
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.text_tertiary'))
      .width('100%')
      .padding({ top: 8, left: 4 })
  }

  @Builder
  row(label: string, value: string, onTap: () => void) {
    Row() {
      Text(label)
        .fontSize($r('app.float.font_body1'))
        .fontColor($r('app.color.text_primary'))
      Blank()
      Text(value)
        .fontSize($r('app.float.font_body2'))
        .fontColor(value === '' ? $r('app.color.text_tertiary') : $r('app.color.brand_activated'))
    }
    .width('100%')
    .height(Dim.listRowHeight)
    .padding({ left: Dim.cardPadding, right: Dim.cardPadding })
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(Dim.radiusM)
    .onClick(() => {
      onTap();
    })
  }

  private localeLabel(): string {
    return I18n.translate(this.settings.locale === 'zh-CN' ? 'settingsLocaleZhCN' : 'settingsLocaleEnUS');
  }

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

  private locationLabel(): string {
    const loc = this.settings.location;
    if (loc === null) {
      return I18n.translate('settingsLocationRegion');
    }
    return loc.province ?? loc.region;
  }

  private voiceLabel(): string {
    return I18n.translate(this.settings.ttsVoice === 'stella' ? 'settingsTtsVoiceStella' : 'settingsTtsVoiceTide');
  }

  private applyTheme(): void {
    ThemeHelper.apply(AppContextHolder.get(), this.settings.themePreference);
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
        AppStorage.setOrCreate<boolean>('hasApiKey', true);
        promptAction.showToast({ message: I18n.translate('apiKeyStart'), duration: 1500 });
      });
    }).catch((err: ApiError) => {
      this.verifyState = 'fail';
      this.verifyMsg = I18n.translate(ApiError.i18nKeyFor(err));
      Logger.warn('SettingsPage', `verify failed: ${err.message}`);
    });
  }

  private confirmDeleteAll(): void {
    const buttons: Array<promptAction.Button> = [];
    const bCancel: promptAction.Button = { text: I18n.translate('cancel'), color: '#66000000' };
    const bDelete: promptAction.Button = { text: I18n.translate('delete'), color: '#E84026' };
    buttons.push(bCancel);
    buttons.push(bDelete);
    const options: promptAction.ShowDialogOptions = {
      title: I18n.translate('deleteAllSessionsModalTitle'),
      message: I18n.translate('deleteAllSessionsModalDescription'),
      buttons: buttons,
      alignment: DialogAlignment.Center,
    };
    try {
      promptAction.showDialog(options).then((result) => {
        if (result.index === 1) {
          this.store.deleteAll();
          promptAction.showToast({ message: I18n.translate('historyDeleted'), duration: 1500 });
        }
      });
    } catch (err) {
      // 忽略
    }
  }
}
