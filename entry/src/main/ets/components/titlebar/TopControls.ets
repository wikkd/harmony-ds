import { Fonts } from '../../common/Fonts';
import { I18n } from '../../common/I18n';
import { Dim } from '../../common/DesignTokens';
import { PeakPeriod } from '../../common/PeakPeriod';

/**
 * 顶部浮层控件：左侧抽屉按钮（无底色，不遮挡消息）+
 * 右侧「红绿灯+设置」胶囊（毛玻璃半透明，半遮挡消息会话）。
 * 消息列表从两者下方滚过。
 * 沉浸光感：半透明毛玻璃（THIN 模糊 + 低不透明度蒙层），文字滚过时可见地被模糊；
 * 触控区 ≥40×40vp（UX 硬性标准）。
 */

/** 侧边栏抽屉按钮：与 StatusCapsule 同款毛玻璃胶囊（单图标） */
@ComponentV2
export struct DrawerButton {
  @Param onTap: () => void = () => {};

  build() {
    Row() {
      Image($r('app.media.ic_public_drawer_filled'))
        .width(24)
        .height(24)
        .fillColor($r('app.color.titlebar_icon'))
        .padding(2)
    }
    .width(44)
    .height(40)
    .justifyContent(FlexAlign.Center)
    .borderRadius(Dim.radiusL)
    // 毛玻璃半透明：低不透明度蒙层 + THIN 模糊，文字从下方滚过时可见地被模糊
    .backgroundBlurStyle(BlurStyle.COMPONENT_THIN)
    .backgroundColor($r('app.color.blur_titlebar'))
    .shadow({ radius: 12, color: 'rgba(0,0,0,0.10)', offsetY: 1 })
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.9 })
    .onClick(() => {
      this.onTap();
    })
  }
}

/** 红绿灯 + 设置 胶囊：半透明毛玻璃 */
@ComponentV2
export struct StatusCapsule {
  @Param onOpenSettings: () => void = () => {};
  @Local showPeakPopup: boolean = false;
  /** 峰谷红绿灯：定时刷新使圆点随时段切换 */
  @Local periodTick: number = 0;
  private periodTimer: number = -1;

  aboutToAppear(): void {
    this.periodTimer = setInterval((): void => {
      this.periodTick++;
    }, 30000);
  }

  aboutToDisappear(): void {
    if (this.periodTimer >= 0) {
      clearInterval(this.periodTimer);
      this.periodTimer = -1;
    }
  }

  private isPeakNow(): boolean {
    // 读取 periodTick 建立刷新依赖，每 30 秒重估
    const _tick = this.periodTick;
    return PeakPeriod.isPeak(new Date());
  }

  build() {
    Row({ space: 4 }) {
      // 峰谷红绿灯：红=高峰时段，绿=空闲时段（点击查看说明）。
      // 圆点仅 10vp，绑点击不合规——外包 40×40 触控区（UX 2.1.3.3）
      Row() {
        Circle({ width: 10, height: 10 })
          .fill(this.isPeakNow() ? $r('app.color.warning') : $r('app.color.success'))
          .accessibilityText(this.isPeakNow() ? I18n.translate('peakLightPeakNow') : I18n.translate('peakLightIdleNow'))
      }
      .width(40)
      .height(40)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.9 })
      .bindPopup(this.showPeakPopup, {
        builder: (): void => {
          this.peakPopup()
        },
        placement: Placement.Bottom,
        popupColor: $r('app.color.dialog_bg'),
        enableArrow: true,
        autoCancel: true,
        onStateChange: (e: PopupStateChangeParam) => {
          this.showPeakPopup = e.isVisible;
        },
      })
      .onClick(() => {
        this.showPeakPopup = !this.showPeakPopup;
      })

      // 设置入口：图标 24vp，外包 40×40 触控区
      Row() {
        Image($r('app.media.ic_public_settings'))
          .width(24)
          .height(24)
          .fillColor($r('app.color.titlebar_icon'))
          .padding(2)
      }
      .width(40)
      .height(40)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.85 })
      .onClick(() => {
        this.onOpenSettings();
      })
    }
    .height(40)
    .borderRadius(Dim.radiusL)
    .alignItems(VerticalAlign.Center)
    // 毛玻璃半透明：低不透明度蒙层 + THIN 模糊，文字从下方滚过时可见地被模糊
    .backgroundBlurStyle(BlurStyle.COMPONENT_THIN)
    .backgroundColor($r('app.color.blur_titlebar'))
    .shadow({ radius: 12, color: 'rgba(0,0,0,0.10)', offsetY: 1 })
  }

  /** 峰谷说明悬浮窗 */
  @Builder
  peakPopup() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Circle({ width: 10, height: 10 })
          .fill(this.isPeakNow() ? $r('app.color.warning') : $r('app.color.success'))
        Text(this.isPeakNow() ? I18n.translate('peakLightPeak') : I18n.translate('peakLightIdle'))
          .fontSize(Fonts.body2())
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Text(this.isPeakNow() ? I18n.translate('peakLightNextIdle') : I18n.translate('peakLightNextPeak'))
          .fontSize(Fonts.caption())
          .fontColor($r('app.color.text_tertiary'))
      }
      .width('100%')

      Text(this.isPeakNow() ? I18n.translate('peakLightPeakNow') : I18n.translate('peakLightIdleNow'))
        .fontSize(Fonts.caption())
        .fontColor($r('app.color.text_secondary'))
        .width('100%')

      Text(I18n.translate('peakLightWindows'))
        .fontSize(Fonts.caption())
        .fontColor($r('app.color.text_tertiary'))
        .width('100%')

      Text(`${I18n.translate('peakLightBeijingTime')} ${PeakPeriod.formatBeijing(PeakPeriod.nextTransition(new Date()))}`)
        .fontSize(Fonts.caption())
        .fontColor($r('app.color.brand_activated'))
        .width('100%')
    }
    .padding(12)
    .width(248)
  }
}
