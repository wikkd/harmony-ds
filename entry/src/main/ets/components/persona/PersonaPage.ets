import { Fonts } from '../../common/Fonts';
import { I18n } from '../../common/I18n';
import { Dim } from '../../common/DesignTokens';
import { SettingsStore } from '../../prefs/SettingsStore';

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
            .fontFamily(Fonts.family())
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
  }

  private toastSaved(): void {
    this.getUIContext().getPromptAction()
      .showToast({ message: I18n.translate('settingsSaved'), duration: 1500 });
  }
}
