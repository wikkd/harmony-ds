import { Fonts } from '../../common/Fonts';
import { I18n } from '../../common/I18n';
import { Dim, Motion } from '../../common/DesignTokens';
import { SettingsStore } from '../../prefs/SettingsStore';
import { CharacterCard } from '../../common/CharacterCard';
import { picker } from '@kit.CoreFileKit';
import { Logger } from '../../common/Logger';

/** 个性化编辑页：自定义人格与回复要求提示词（角色扮演） */
@ComponentV2
export struct PersonaPage {
  settings: SettingsStore = SettingsStore.get();
  @Local text: string = '';

  aboutToAppear(): void {
    this.text = this.settings.personalization;
  }

  build() {
    NavDestination() {
      Column({ space: 12 }) {
        Column({ space: 12 }) {
        Text(I18n.translate('personalizationHint'))
          .fontSize(Fonts.caption())
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')

        Stack({ alignContent: Alignment.BottomEnd }) {
          TextArea({
            text: this.text,
            placeholder: I18n.translate('personalizationPlaceholder'),
          })
            .constraintSize({ minHeight: 220, maxHeight: 400 })
            .fontSize(Fonts.body1())
            .fontColor($r('app.color.text_primary'))
            .placeholderColor($r('app.color.text_tertiary'))
            .placeholderFont({ size: 14 })
            .backgroundColor($r('app.color.text_field_sub_bg'))
            .borderRadius(Dim.radiusM)
            .padding(12)
            .maxLength(2000)
            .showCounter(false)
            .onChange((v: string) => {
              this.text = v;
            })
          Text(`${this.text.length}/2000`)
            .fontSize(Fonts.caption())
            .fontColor($r('app.color.text_tertiary'))
            .margin(8)
        }
        .width('100%')

        Row({ space: 12 }) {
          Button(I18n.translate('personaImport'))
            .fontSize(Fonts.body2())
            .backgroundColor($r('app.color.component_normal'))
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
            .onClick(() => {
              this.importCard();
            })
          Button(I18n.translate('personalizationClear'))
            .fontSize(Fonts.body2())
            .backgroundColor($r('app.color.component_normal'))
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
            .onClick(() => {
              this.text = '';
              this.settings.setPersonalization('');
              this.toastSaved();
            })
          Button(I18n.translate('confirm'))
            .fontSize(Fonts.body2())
            .backgroundColor($r('app.color.brand'))
            .fontColor($r('app.color.text_primary_contrary'))
            .layoutWeight(1)
            .onClick(() => {
              this.settings.setPersonalization(this.text);
              this.toastSaved();
            })
        }
        .width('100%')

        Blank()
        }
        .constraintSize({ maxWidth: Dim.contentMaxWidth })
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .padding(Dim.pagePadding)
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Center)
    }
    .title(I18n.translate('personalization'))
    .backgroundColor($r('app.color.app_bg'))
    // 底色延伸进手势条避让区，页底不露分界线
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  private toastSaved(): void {
    this.getUIContext().getPromptAction()
      .showToast({ message: I18n.translate('settingsSaved'), duration: Motion.toastShort });
  }

  /** 导入角色卡 md：选择文件 → 解析填入草稿（不自动保存，用户确认后生效） */
  private async importCard(): Promise<void> {
    try {
      const docPicker = new picker.DocumentViewPicker();
      const opts = new picker.DocumentSelectOptions();
      opts.maxSelectNumber = 1;
      // 不设后缀过滤：角色卡可能是 .md/.json/.txt 或无后缀，过滤会让文件在选择器里不可见
      const res = await docPicker.select(opts);
      if (res.length === 0) {
        return; // 用户取消
      }
      const raw = await CharacterCard.readText(res[0]);
      const card = CharacterCard.parse(raw);
      if (card === '') {
        this.toast(I18n.translate('personaImportFailed'));
        return;
      }
      this.text = card;
      this.toast(I18n.translate('personaImported'));
    } catch (err) {
      Logger.warn('PersonaPage', `import card failed: ${JSON.stringify(err)}`);
      this.toast(I18n.translate('personaImportFailed'));
    }
  }

  private toast(msg: string): void {
    this.getUIContext().getPromptAction()
      .showToast({ message: msg, duration: Motion.toastMid });
  }
}
