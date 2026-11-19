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

/** AI 服务信息 3 节词条（服务说明/备案信息/生成内容标识） */
export function buildAiInfoSections(): LegalSection[] {
  const out: LegalSection[] = [];
  for (let i = 1; i <= 3; i++) {
    out.push(new LegalSection(`aiInfoSection${i}Title`, `aiInfoSection${i}Body`));
  }
  return out;
}

/** 投诉与举报 2 节词条（举报渠道/处理说明） */
export function buildReportSections(): LegalSection[] {
  const out: LegalSection[] = [];
  for (let i = 1; i <= 2; i++) {
    out.push(new LegalSection(`reportSection${i}Title`, `reportSection${i}Body`));
  }
  return out;
}

/** 法务文档页（隐私政策/用户协议共用骨架：滚动章节列表） */
@ComponentV2
export struct LegalDocPage {
  @Param titleKey: string = '';
  @Param sections: LegalSection[] = [];

  /**
   * 宽屏内容收窄：不能用 constraintSize(maxWidth)——7.0.0.111 实机回归，
   * 它出现在 NavDestination 子树会让后代节点挂载错乱（图标/箭头整体缺席）。
   * 改为 Scroll 自测宽后对内容列动态加水平 padding（手机不受影响）。
   */
  @Local contentPad: number = Dim.pagePadding;

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
          .padding({ left: this.contentPad, right: this.contentPad, top: Dim.pagePadding, bottom: 44 })
        }
        .layoutWeight(1)
        .onAreaChange((_o: Area, nv: Area) => {
          const w = Number(nv.width);
          const inner = Dim.contentMaxWidth - Dim.pagePadding * 2;
          this.contentPad = Math.max(Dim.pagePadding, (w - inner) / 2);
        })
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
