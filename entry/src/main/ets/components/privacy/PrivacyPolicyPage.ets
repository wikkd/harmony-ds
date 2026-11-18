import { Fonts } from '../../common/Fonts';
import { I18n } from '../../common/I18n';
import { Dim } from '../../common/DesignTokens';

/** 隐私政策（上架合规：数据去向说明） */
@Component
export struct PrivacyPolicyPage {
  build() {
    NavDestination() {
      Column() {
        Scroll() {
          Column({ space: 16 }) {
            this.section(I18n.translate('privacyPolicySection1Title'), I18n.translate('privacyPolicySection1Body'));
            this.section(I18n.translate('privacyPolicySection2Title'), I18n.translate('privacyPolicySection2Body'));
            this.section(I18n.translate('privacyPolicySection3Title'), I18n.translate('privacyPolicySection3Body'));
          }
          .alignItems(HorizontalAlign.Start)
          .padding(Dim.pagePadding)
          .constraintSize({ maxWidth: Dim.contentMaxWidth })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('100%')
    }
    .title(I18n.translate('privacyPolicyTitle'))
    .backgroundColor($r('app.color.app_bg'))
  }

  @Builder
  section(title: string, body: string) {
    Column({ space: 8 }) {
      Text(title)
        .fontSize(Fonts.headline9())
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
      Text(body)
        .fontSize(Fonts.body2())
        .lineHeight(22)
        .fontColor($r('app.color.text_secondary'))
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }
}
