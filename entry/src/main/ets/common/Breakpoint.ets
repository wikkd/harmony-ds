import { Dim } from './DesignTokens';

/**
 * 窗口断点：EntryAbility 里把窗口宽度(vp)与当前断点写入 AppStorage，
 * UI 组件用 @StorageLink 读取并做自适应。断点阈值取官方规范：sm<600<=md<840<=lg。
 */
export class BreakpointUtil {
  static readonly KEY_WIDTH: string = 'bpWindowWidth';
  static readonly KEY_BP: string = 'bpCurrent';

  static updateWindowWidth(vpWidth: number): void {
    AppStorage.setOrCreate<number>(BreakpointUtil.KEY_WIDTH, vpWidth);
    let bp: string;
    if (vpWidth < Dim.bpSmMax) {
      bp = 'sm';
    } else if (vpWidth < Dim.bpMdMax) {
      bp = 'md';
    } else {
      bp = 'lg';
    }
    AppStorage.setOrCreate<string>(BreakpointUtil.KEY_BP, bp);
  }

  static windowWidth(): number {
    return AppStorage.get<number>(BreakpointUtil.KEY_WIDTH) ?? 360;
  }

  /** 是否宽屏（侧栏常驻双栏） */
  static isWide(): boolean {
    return BreakpointUtil.windowWidth() >= Dim.siderPermanentBp;
  }
}
