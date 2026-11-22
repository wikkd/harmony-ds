import { curves } from '@kit.ArkUI';

/**
 * 设计常量：取自官方 HarmonyOS Design 规范（developer.huawei.com 设计指南，数值表见
 * docs/design-spec-harmonyos.md / harmonyos-design skill）。
 * 颜色与字号走 resources（base/dark 自动切换），此处只放不随主题变化的尺寸与动效 token。
 */
export class Dim {
  /** 列表行高（官方规范 48vp） */
  static readonly listRowHeight: number = 48;
  /** 设置页行高（56vp，含 PageHeader） */
  static readonly rowHeight: number = 56;
  /**
   * 圆角对齐官方分档：同层统一、层级越高圆角越大。
   * 4=标签角标 / 8=图片图标 / 16=通知卡片与内容容器 / 20=按钮菜单气泡 / 32=半模态弹出框。
   */
  static readonly radiusS: number = 8;
  static readonly radiusM: number = 16;
  static readonly radiusL: number = 20;
  static readonly radiusXL: number = 32;
  /** 页面左右边距（官方间隔表：手机 16vp） */
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
  /** 聊天主列最大宽度（contentMaxWidth + 两侧 pagePadding）：宽屏居中列，顶部浮层行须同步收拢对齐 */
  static readonly chatColumnMax: number = Dim.contentMaxWidth + Dim.pagePadding * 2;
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

/**
 * 动效 token：时长与曲线对齐官方「动效属性」规范。
 * 时长分档（设计原则）：短距离 ≤250ms / 较短 ≤150ms；小范围 150 / 局部 200 / 全屏 350。
 * 曲线规则：视线内运动用标准贝塞尔；新元素入场用减速贝塞尔；跟手与松手/转场用弹簧曲线
 * （弹簧时长由物理参数自动计算，传 duration 无效，勿再配 duration）。
 */
export class Motion {
  /** 小范围/颜色类动效（官方简单动画 100ms、小范围 150ms） */
  static readonly animFast: number = 150;
  /** 局部范围动效（官方：局部 200ms，如删一条列表） */
  static readonly animBase: number = 200;
  /** 短距离转场（官方 ≤250ms；同时满足转场下限 ≥200ms） */
  static readonly animSlow: number = 250;
  static readonly toastShort: number = 1500;
  static readonly toastMid: number = 2000;
  static readonly toastLong: number = 2500;
  /** 需要阅读的提示（导入/导出结果） */
  static readonly toastMax: number = 3000;
  /** 视线内运动（图片缩放/开关/Tab 切换）：标准曲线 cubic-bezier(0.40,0.00,0.20,1.00) */
  static readonly curveStd: Curve = Curve.FastOutSlowIn;
  /** 新元素入场（弹框/卡片出现）：减速曲线 cubic-bezier(0.00,0.00,0.40,1.00) */
  static readonly curveIn: curves.ICurve = curves.cubicBezierCurve(0, 0, 0.4, 1);
  /** 元素出场消失：加速曲线（规范仅图示未给参数，取常规近似） */
  static readonly curveOut: curves.ICurve = curves.cubicBezierCurve(0.4, 0, 1, 1);
  /** 松手释放/可打断转场：官方物理弹簧（interpolatingSpring(128,12,1,0) 的等价参数） */
  static readonly spring: curves.ICurve = curves.springMotion(0.555, 0.53);
  /** 手势跟手阶段：响应式弹簧（与 springMotion 联用，跟手→松手自然衔接） */
  static readonly springFollow: curves.ICurve = curves.responsiveSpringMotion();
}
