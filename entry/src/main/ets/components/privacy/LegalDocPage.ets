import { Fonts } from '../../common/Fonts';
import { I18n } from '../../common/I18n';
import { Dim } from '../../common/DesignTokens';

/** 法务文档章节：i18n 词条键对 */
export class LegalSection {
  titleKey: string;
  bodyKey: string;

  constructor(titleKey: string, bodyKey: string) {
    this.titleKey = titleKey;
    this.bodyKey = bodyKey;
  }
}

/** 隐私政策 9 节词条 */
export function buildPrivacySections(): LegalSection[] {
  const out: LegalSection[] = [];
  for (let i = 1; i <= 9; i++) {
    out.push(new LegalSection(`privacyPolicySection${i}Title`, `privacyPolicySection${i}Body`));
  }
  return out;
}

/** 用户协议 9 节词条 */
export function buildAgreementSections(): LegalSection[] {
  const out: LegalSection[] = [];
  for (let i = 1; i <= 9; i++) {
    out.push(new LegalSection(`agreementSection${i}Title`, `agreementSection${i}Body`));
  }
  return out;
}

/** 法务文档页（隐私政策/用户协议共用骨架：滚动章节列表） */
@ComponentV2
export struct LegalDocPage {
  @Param titleKey: string = '';
  @Param sections: LegalSection[] = [];

  build() {
    NavDestination() {
      Column() {
        Scroll() {
          Column({ space: 16 }) {
            ForEach(this.sections, (s: LegalSection, idx: number) => {
              this.section(I18n.translate(s.titleKey), I18n.translate(s.bodyKey), idx)
            }, (s: LegalSection) => s.titleKey)
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
    .title(I18n.translate(this.titleKey))
    .backgroundColor($r('app.color.app_bg'))
    // 底色延伸进手势条避让区，页底不露分界线
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  @Builder
  section(title: string, body: string, idx: number) {
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
