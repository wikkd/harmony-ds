import { Format } from '../../common/Format';
import { I18n } from '../../common/I18n';
import { SettingsStore } from '../../prefs/SettingsStore';
import { UserLocation } from '../../model/SettingsTypes';

/** 模型约定的五项信息，对齐原项目 latestReminder.ts */
export class LatestReminder {
  static locationName(location: UserLocation | null, locale: string): string {
    if (location === null) {
      return '';
    }
    return location.region === 'CN' ? (location.province ?? '中国') : location.region;
  }

  static create(now: Date = new Date()): string {
    const settings = SettingsStore.get();
    const locale = settings.locale;
    return [
      Format.formatDate(now),
      Format.weekdayLong(locale, now),
      LatestReminder.locationName(settings.location, locale),
      'Web',
      I18n.translate('latestReminderLanguage'),
    ].join(',');
  }
}
