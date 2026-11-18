import { Fonts } from '../../common/Fonts';
import { I18n } from '../../common/I18n';
import { Dim } from '../../common/DesignTokens';

/** 用户协议（上架合规：服务说明、行为规范、免责声明） */
@Component
export struct UserAgreementPage {
  build() {
    NavDestination() {
      Column() {
        Scroll() {
          Column({ space: 16 }) {
            this.section(I18n.translate('agreementSection1Title'), I18n.translate('agreementSection1Body'));
            this.section(I18n.translate('agreementSection2Title'), I18n.translate('agreementSection2Body'));
            this.section(I18n.translate('agreementSection3Title'), I18n.translate('agreementSection3Body'));
            this.section(I18n.translate('agreementSection4Title'), I18n.translate('agreementSection4Body'));
            this.section(I18n.translate('agreementSection5Title'), I18n.translate('agreementSection5Body'));
            this.section(I18n.translate('agreementSection6Title'), I18n.translate('agreementSection6Body'));
            this.section(I18n.translate('agreementSection7Title'), I18n.translate('agreementSection7Body'));
            this.section(I18n.translate('agreementSection8Title'), I18n.translate('agreementSection8Body'));
            this.section(I18n.translate('agreementSection9Title'), I18n.translate('agreementSection9Body'));
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
    .title(I18n.translate('userAgreementTitle'))
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
