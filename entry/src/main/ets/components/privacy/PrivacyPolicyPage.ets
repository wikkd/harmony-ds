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
            this.section(I18n.translate('privacyPolicySection4Title'), I18n.translate('privacyPolicySection4Body'));
            this.section(I18n.translate('privacyPolicySection5Title'), I18n.translate('privacyPolicySection5Body'));
            this.section(I18n.translate('privacyPolicySection6Title'), I18n.translate('privacyPolicySection6Body'));
            this.section(I18n.translate('privacyPolicySection7Title'), I18n.translate('privacyPolicySection7Body'));
            this.section(I18n.translate('privacyPolicySection8Title'), I18n.translate('privacyPolicySection8Body'));
            this.section(I18n.translate('privacyPolicySection9Title'), I18n.translate('privacyPolicySection9Body'));
          }
          .alignItems(HorizontalAlign.Start)
          .padding({ left: Dim.pagePadding, right: Dim.pagePadding, top: Dim.pagePadding, bottom: 44 })
          .constraintSize({ maxWidth: Dim.contentMaxWidth })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.Top)
        // 内容滚动手势条下方：末段文字只被手势条浮层遮住，不在安全区分界线被裁切
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      }
      .width('100%')
      .height('100%')
    }
    .title(I18n.translate('privacyPolicyTitle'))
    .backgroundColor($r('app.color.app_bg'))
    // 底色延伸进手势条避让区，页底不露分界线
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
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
