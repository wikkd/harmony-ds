import { Fonts } from '../../common/Fonts';
import { Dim } from '../../common/DesignTokens';

/**
 * 设置行通用组件：图标（可无）+ 标题 + 尾部三选一（灰色值 / 箭头 / Toggle）。
 * 用子组件而非 @Builder：真机（平板）上 @Builder 渲染的卡片文本/图标会被
 * 整体吞掉只剩 Blank（原因待查），子组件无此问题。
 */
@ComponentV2
export struct SettingRow {
  @Param label: string = '';
  /** null = 无图标（数据管理卡风格） */
  @Param icon: Resource | null = null;
  /** 灰色只读尾值，空串不显示 */
  @Param value: string = '';
  @Param showArrow: boolean = false;
  /** 危险操作：红字且不显示箭头/值 */
  @Param danger: boolean = false;
  /** 自带白卡圆角底（数据管理页风格）；false 时行由父级卡片容器包住 */
  @Param carded: boolean = false;
  /** 非 null 显示开关（开关行不走箭头/值分支） */
  @Param toggleOn: boolean | null = null;
  @Param tappable: boolean = false;
  @Param onRowTap: () => void = (): void => {};
  @Param onToggle: (on: boolean) => void = (): void => {};

  build() {
    Row({ space: 12 }) {
      if (this.icon !== null) {
        Image(this.icon)
          .width(22)
          .height(22)
          .fillColor($r('app.color.text_primary'))
      }
      Text(this.label)
        .fontSize(Fonts.body1())
        .fontColor(this.danger ? $r('app.color.warning') : $r('app.color.text_primary'))
        .layoutWeight(1)
      if (this.toggleOn !== null) {
        Toggle({ type: ToggleType.Switch, isOn: this.toggleOn === true })
          .onChange((on: boolean) => {
            this.onToggle(on);
          })
      } else {
        if (!this.danger && this.value !== '') {
          Text(this.value)
            .fontSize(Fonts.body2())
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: '46%' })
        }
        if (this.showArrow) {
          Image($r('app.media.ic_public_arrow_right'))
            .width(16)
            .height(16)
            .fillColor($r('app.color.text_tertiary'))
        }
      }
    }
    .width('100%')
    .height(Dim.rowHeight)
    .padding({ left: 16, right: 16 })
    .backgroundColor(this.carded ? $r('app.color.card_bg') : Color.Transparent)
    .borderRadius(this.carded ? Dim.radiusL : 0)
    .clickEffect(this.tappable ? { level: ClickEffectLevel.LIGHT, scale: 0.98 } : { level: ClickEffectLevel.LIGHT, scale: 1 })
    .onClick(() => {
      if (this.tappable) {
        this.onRowTap();
      }
    })
  }
}
