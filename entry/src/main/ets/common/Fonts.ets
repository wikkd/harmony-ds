import { SettingsStore } from '../prefs/SettingsStore';

/**
 * 字体助手：全局字号缩放，读取设置即时生效。
 * 替代 $r('app.float.font_*') 资源引用（资源无法运行时缩放）。
 * 基准值与 float.json 一致（fp）。
 */
export class Fonts {
  /** 当前缩放系数 */
  static scale(): number {
    return SettingsStore.get().fontScaleValue();
  }

  static headline6(): number {
    return Math.round(30 * Fonts.scale() * 10) / 10;
  }

  static headline7(): number {
    return Math.round(24 * Fonts.scale() * 10) / 10;
  }

  static headline8(): number {
    return Math.round(20 * Fonts.scale() * 10) / 10;
  }

  static headline9(): number {
    return Math.round(18 * Fonts.scale() * 10) / 10;
  }

  static body1(): number {
    return Math.round(16 * Fonts.scale() * 10) / 10;
  }

  static body2(): number {
    return Math.round(14 * Fonts.scale() * 10) / 10;
  }

  static body3(): number {
    return Math.round(12 * Fonts.scale() * 10) / 10;
  }

  static caption(): number {
    return Math.round(10 * Fonts.scale() * 10) / 10;
  }

  /**
   * 官方字重阶梯（「文本排版」）：Title 档 Bold，Subtitle 与 Body_L Medium，Body_M/S、Caption Regular。
   * 阶梯对应：headline6~9=Title/Subtitle 档，body1=Body_L，body2=Body_M，body3/caption=Caption 档。
   */
  static weightTitle(): FontWeight {
    return FontWeight.Bold;
  }

  static weightMedium(): FontWeight {
    return FontWeight.Medium;
  }

  static weightRegular(): FontWeight {
    return FontWeight.Normal;
  }
}
