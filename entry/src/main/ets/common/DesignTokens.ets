/**
 * 设计常量：取自官方 HarmonyOS Component Library（手机折叠屏平板-SKETCH）规范。
 * 颜色与字号走 resources（base/dark 自动切换），此处只放不随主题变化的尺寸。
 */
export class Dim {
  /** 列表行高（官方规范 48vp） */
  static readonly listRowHeight: number = 48;
  /** 卡片圆角（官方规范 12vp / 大卡 24vp） */
  static readonly radiusS: number = 8;
  static readonly radiusM: number = 12;
  static readonly radiusL: number = 24;
  /** 页面左右边距 */
  static readonly pagePadding: number = 16;
  /** 卡片内边距 */
  static readonly cardPadding: number = 12;
  /** 列表项间距 */
  static readonly listGap: number = 4;
  /** 分隔线厚度 */
  static readonly separator: number = 0.5;
  /** 输入区最大宽度（平板上避免无限拉伸） */
  static readonly inputMaxWidth: number = 800;
  /** 消息区最大宽度（平板双栏下的阅读宽度） */
  static readonly contentMaxWidth: number = 760;
  /** 侧栏宽度 */
  static readonly siderWidth: number = 300;
  /** 气泡最大占比 */
  static readonly bubbleMaxPercent: number = 82;
  /** 官方断点：sm < 600vp <= md < 840vp <= lg */
  static readonly bpSmMax: number = 600;
  static readonly bpMdMax: number = 840;
  /** 侧栏抽屉从 sm/md 展开的阈值 */
  static readonly siderPermanentBp: number = 840;
}
