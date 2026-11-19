import { SettingsStore } from '../prefs/SettingsStore';
import { ZH_COMMON, EN_COMMON } from './i18n/I18nCommon';
import { ZH_LEGAL, EN_LEGAL } from './i18n/I18nLegal';
import { ZH_SESSIONS, EN_SESSIONS } from './i18n/I18nSessions';
import { ZH_CHAT, EN_CHAT } from './i18n/I18nChat';
import { ZH_ERRORS, EN_ERRORS } from './i18n/I18nErrors';
import { ZH_SETTINGS, EN_SETTINGS } from './i18n/I18nSettings';
import { ZH_BACKUP, EN_BACKUP } from './i18n/I18nBackup';
import { ZH_USAGE, EN_USAGE } from './i18n/I18nUsage';

/**
 * 双语词条：按域拆分在 common/i18n/，此处合并；键名与原项目 src/i18n 对齐。
 * translate() 在 build 中读取 SettingsStore.locale（@Trace），语言切换即时生效。
 */

function mergeDicts(parts: Record<string, string>[]): Record<string, string> {
  const out: Record<string, string> = {};
  for (const p of parts) {
    const ks: string[] = Object.keys(p);
    for (const k of ks) {
      out[k] = p[k];
    }
  }
  return out;
}

export const zh: Record<string, string> = mergeDicts([ZH_COMMON, ZH_LEGAL, ZH_SESSIONS, ZH_CHAT, ZH_ERRORS, ZH_SETTINGS, ZH_BACKUP, ZH_USAGE]);
export const en: Record<string, string> = mergeDicts([EN_COMMON, EN_LEGAL, EN_SESSIONS, EN_CHAT, EN_ERRORS, EN_SETTINGS, EN_BACKUP, EN_USAGE]);

export class I18n {
  static translate(key: string, params?: Record<string, string>): string {
    const locale = SettingsStore.get().locale;
    const dict = locale === 'en-US' ? en : zh;
    let text: string = dict[key] ?? zh[key] ?? key;
    if (params) {
      const keys: string[] = Object.keys(params);
      for (const k of keys) {
        text = text.split(`{${k}}`).join(params[k]);
      }
    }
    return text;
  }
}
