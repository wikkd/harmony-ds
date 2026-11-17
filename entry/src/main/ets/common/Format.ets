import { util } from '@kit.ArkTS';

/** 时间格式化与 ID 生成 */

export class Format {
  /** yyyy-MM-dd（本地时区，latestReminder 用） */
  static formatDate(d: Date): string {
    const y = d.getFullYear();
    const m = `${d.getMonth() + 1}`.padStart(2, '0');
    const day = `${d.getDate()}`.padStart(2, '0');
    return `${y}-${m}-${day}`;
  }

  /** HH:mm（消息时间戳展示） */
  static formatTime(d: Date): string {
    const h = `${d.getHours()}`.padStart(2, '0');
    const min = `${d.getMinutes()}`.padStart(2, '0');
    return `${h}:${min}`;
  }

  /** 星期长名（latestReminder 用，intl 标准输出） */
  static weekdayLong(localeTag: string, d: Date): string {
    try {
      const fmt = new Intl.DateTimeFormat(localeTag.replace('-', '_'), { weekday: 'long' });
      return fmt.format(d);
    } catch (e) {
      const names: string[] = ['星期日', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六'];
      const namesEn: string[] = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
      return localeTag.startsWith('en') ? namesEn[d.getDay()] : names[d.getDay()];
    }
  }
}

/** 短随机 ID（无依赖 uuid：时间戳 + 随机段） */
export class Id {
  static next(): string {
    const rand = util.generateRandomUUID(false) as string;
    return rand.replace(/-/g, '').substring(0, 20);
  }
}
