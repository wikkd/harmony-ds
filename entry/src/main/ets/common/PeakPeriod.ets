/**
 * 峰谷时段判定（对齐官方定价规则）：
 * - 高峰：北京时间周一至周五 9:00–12:00、14:00–18:00（法定节假日除外）
 * - 空闲：其余时段（夜间、周末、法定节假日全天），价格约为高峰一半
 * 节假日按国务院办公厅年度通知维护；未收录年份退化为仅按周末+工作日时间窗规则。
 */

/** 节假日区间 [起始月, 起始日, 结束月, 结束日]（北京时间，含首尾） */
type HolidayRange = number[];

export class PeakPeriod {
  private static readonly HOLIDAY_RANGES: Record<string, HolidayRange[]> = {
    '2026': [
      [1, 1, 1, 3],     // 元旦
      [2, 15, 2, 23],   // 春节
      [4, 4, 4, 6],     // 清明节
      [5, 1, 5, 5],     // 劳动节
      [6, 19, 6, 21],   // 端午节
      [9, 25, 9, 27],   // 中秋节
      [10, 1, 10, 7],   // 国庆节
    ],
    '2027': [
      [1, 1, 1, 3],     // 元旦
      [2, 5, 2, 13],    // 春节（后续节日待官方通知后补全）
    ],
  };

  private static readonly PEAK_WINDOWS: number[][] = [
    [9 * 60, 12 * 60],
    [14 * 60, 18 * 60],
  ];

  /** 任意时刻 → 北京时间墙钟（+8h 后用 UTC 读取字段；与设备时区无关） */
  private static beijingMs(now: Date): number {
    return now.getTime() + 480 * 60000;
  }

  private static isHoliday(y: number, mo: number, d: number): boolean {
    const ranges = PeakPeriod.HOLIDAY_RANGES[`${y}`];
    if (ranges === undefined) {
      return false;
    }
    const today = (mo + 1) * 100 + d;
    for (const r of ranges) {
      const start = r[0] * 100 + r[1];
      const end = r[2] * 100 + r[3];
      if (today >= start && today <= end) {
        return true;
      }
    }
    return false;
  }

  /** 判断「北京墙钟字段」是否高峰 */
  private static peakAtFields(y: number, mo: number, d: number, minutes: number): boolean {
    const weekday = new Date(Date.UTC(y, mo, d)).getUTCDay();
    if (weekday < 1 || weekday > 5) {
      return false;
    }
    if (PeakPeriod.isHoliday(y, mo, d)) {
      return false;
    }
    for (const w of PeakPeriod.PEAK_WINDOWS) {
      if (minutes >= w[0] && minutes < w[1]) {
        return true;
      }
    }
    return false;
  }

  /** 当前是否高峰时段（红） */
  static isPeak(now: Date): boolean {
    const bj = new Date(PeakPeriod.beijingMs(now));
    const minutes = bj.getUTCHours() * 60 + bj.getUTCMinutes();
    return PeakPeriod.peakAtFields(bj.getUTCFullYear(), bj.getUTCMonth(), bj.getUTCDate(), minutes);
  }

  /** 下一次峰→谷/谷→峰切换的时刻（绝对 ms）；7 天内必有切换 */
  static nextTransition(now: Date): number {
    const bjMs = PeakPeriod.beijingMs(now);
    const bj = new Date(bjMs);
    const y = bj.getUTCFullYear();
    const mo = bj.getUTCMonth();
    const d = bj.getUTCDate();
    const minutes = bj.getUTCHours() * 60 + bj.getUTCMinutes();
    const peakNow = PeakPeriod.peakAtFields(y, mo, d, minutes);
    if (peakNow) {
      // 当前窗口的结束（12:00 或 18:00）
      for (const w of PeakPeriod.PEAK_WINDOWS) {
        if (minutes >= w[0] && minutes < w[1]) {
          return Date.UTC(y, mo, d, Math.floor(w[1] / 60), w[1] % 60);
        }
      }
    }
    // 空闲中：向后找下一个高峰开始（8 天覆盖跨周与节假日）
    for (let offset = 0; offset <= 8; offset++) {
      for (const w of PeakPeriod.PEAK_WINDOWS) {
        const cand = Date.UTC(y, mo, d + offset, Math.floor(w[0] / 60), w[0] % 60);
        if (cand <= bjMs) {
          continue;
        }
        const c = new Date(cand);
        if (PeakPeriod.peakAtFields(c.getUTCFullYear(), c.getUTCMonth(), c.getUTCDate(), w[0])) {
          return cand;
        }
      }
    }
    return bjMs;
  }

  /** 绝对时刻 → 北京墙钟展示文本：M月D日 HH:mm */
  static formatBeijing(ms: number): string {
    const bj = new Date(ms + 480 * 60000);
    const hh = `${bj.getUTCHours()}`.padStart(2, '0');
    const mm = `${bj.getUTCMinutes()}`.padStart(2, '0');
    return `${bj.getUTCMonth() + 1}月${bj.getUTCDate()}日 ${hh}:${mm}`;
  }
}
