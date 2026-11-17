import { I18n } from '../common/I18n';
import { SettingsStore } from '../prefs/SettingsStore';
import { ThemeHelper } from '../common/ThemeHelper';
import { AppContextHolder } from '../common/AppContextHolder';
import { Dim } from '../common/DesignTokens';
import { PrivacyPolicyPage } from '../components/privacy/PrivacyPolicyPage';

/**
 * M1：Navigation 骨架 + 欢迎页（鸿蒙设计语言）。
 * 侧栏会话列表 M3 接入、输入区 M2 接入、设置面板 M5 替换占位。
 */
@Entry
@Component
struct Index {
  pathStack: NavPathStack = new NavPathStack();
  @StorageLink('bpCurrent') bpCurrent: string = 'sm';

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
  @StorageLink('bpCurrent') bpCurrent: string = 'sm';

  build() {
    Column() {
      // 标题栏：鸿蒙小标题样式
      Row() {
        Row({ space: 8 }) {
          Image($r('app.media.startIcon'))
            .width(28)
            .height(28)
            .borderRadius(Dim.radiusS)
          Text(I18n.translate('appName'))
            .fontSize($r('app.float.font_headline8'))
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
        }
        .alignItems(VerticalAlign.Center)

        Blank()

        Row() {
          Image($r('app.media.ic_public_settings'))
            .width(24)
            .height(24)
            .fillColor($r('app.color.titlebar_icon'))
            .padding(2)
            .onClick(() => {
              this.pathStack.pushPathByName('settings', null);
            })
        }
        .width(40)
        .height(40)
        .borderRadius(20)
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')
      .height(56)
      .padding({ left: Dim.pagePadding, right: 8 })
      .alignItems(VerticalAlign.Center)

      Divider()
        .color($r('app.color.list_separator'))
        .strokeWidth(Dim.separator)

      // 欢迎区（平板上限制阅读宽度并居中）
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

      Text(I18n.translate('contentCaveat'))
        .fontSize($r('app.float.font_caption'))
        .fontColor($r('app.color.text_tertiary'))
        .margin({ bottom: 12 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_bg'))
  }
}

/** M1 设置占位页（M5 替换为完整设置面板） */
@Component
struct SettingsPlaceholderPage {
  pathStack: NavPathStack = new NavPathStack();
  @StorageLink('bpCurrent') bpCurrent: string = 'sm';

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

        List() {
          ListItem() {
            this.SettingRow('隐私政策', 'privacy')
          }
          ListItem() {
            ThemeRow()
          }
        }
        .width('100%')
        .margin({ top: 8 })
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.app_bg'))
    }
    .title('')
    .backgroundColor($r('app.color.app_bg'))
  }

  @Builder
  SettingRow(label: string, dest: string) {
    Row() {
      Text(label)
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
    .onClick(() => {
      this.pathStack.pushPathByName(dest, null);
    })
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
          // 循环切换 浅色→深色→跟随系统
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
  }
}
