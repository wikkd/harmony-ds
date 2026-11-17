import { preferences } from '@kit.ArkData';
import { Context } from '@kit.AbilityKit';
import { i18n } from '@kit.LocalizationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Locale, ThemePreference, TtsVoice, UserLocation } from '../model/SettingsTypes';
import { Logger } from '../common/Logger';

const TAG: string = 'SettingsStore';
const PREF_NAME: string = 'chat_demo_settings';

/** 首选项键名，对齐原项目 chat-demo:* 前缀语义 */
const KEY_API_ORIGIN: string = 'chat-demo:api-origin';
const KEY_LOCALE: string = 'chat-demo:locale';
const KEY_LOCATION: string = 'chat-demo:location';
const KEY_THEME: string = 'chat-demo:theme-preference';
const KEY_TTS_VOICE: string = 'chat-demo:tts-voice';
const KEY_THINKING: string = 'chat-demo:thinking';
const KEY_SEARCH: string = 'chat-demo:search';
const KEY_SIDER_COLLAPSED: string = 'chat-demo:sider-collapsed';
const KEY_ONBOARDED: string = 'chat-demo:onboarded';

export const DEFAULT_API_ORIGIN: string = 'https://api.deepseek.com';

/**
 * 全局设置单例（V2 状态管理）。
 * 注意：API Key 不在这里存，走 KeyVault（加密关键资产）。
 */
@ObservedV2
export class SettingsStore {
  @Trace apiOrigin: string = DEFAULT_API_ORIGIN;
  @Trace locale: Locale = 'zh-CN';
  @Trace themePreference: ThemePreference = 'system';
  @Trace ttsVoice: TtsVoice = 'stella';
  @Trace thinking: boolean = false;
  @Trace search: boolean = false;
  @Trace siderCollapsed: boolean = false;
  @Trace location: UserLocation | null = null;
  /** 是否完成首次引导（填过 Key） */
  @Trace onboarded: boolean = false;

  private static instance?: SettingsStore;
  private store?: preferences.Preferences;

  private constructor() {
  }

  static get(): SettingsStore {
    if (!SettingsStore.instance) {
      SettingsStore.instance = new SettingsStore();
    }
    return SettingsStore.instance;
  }

  /** 在 Ability onCreate 时调用一次 */
  async init(context: Context): Promise<void> {
    try {
      this.store = preferences.getPreferencesSync(context, { name: PREF_NAME });
      this.apiOrigin = this.store.getSync(KEY_API_ORIGIN, DEFAULT_API_ORIGIN) as string;
      const savedLocale = this.store.getSync(KEY_LOCALE, '') as string;
      if (savedLocale === 'zh-CN' || savedLocale === 'en-US') {
        this.locale = savedLocale;
      } else {
        // 首次启动跟随系统语言
        try {
          const sys: string = i18n.System.getSystemLanguage();
          this.locale = sys.toLowerCase().startsWith('en') ? 'en-US' : 'zh-CN';
        } catch (e) {
          this.locale = 'zh-CN';
        }
      }
      this.themePreference = (this.store.getSync(KEY_THEME, 'system') as ThemePreference);
      this.ttsVoice = (this.store.getSync(KEY_TTS_VOICE, 'stella') as TtsVoice) === 'tide' ? 'tide' : 'stella';
      this.thinking = this.store.getSync(KEY_THINKING, false) as boolean;
      this.search = this.store.getSync(KEY_SEARCH, false) as boolean;
      this.siderCollapsed = this.store.getSync(KEY_SIDER_COLLAPSED, false) as boolean;
      this.onboarded = this.store.getSync(KEY_ONBOARDED, false) as boolean;
      const locJson = this.store.getSync(KEY_LOCATION, '') as string;
      if (locJson) {
        try {
          const obj: Record<string, Object> = JSON.parse(locJson) as Record<string, Object>;
          const loc = new UserLocation();
          loc.region = (obj['region'] as string | null) ?? 'CN';
          loc.province = (obj['province'] as string | null) ?? null;
          loc.city = (obj['city'] as string | null) ?? null;
          this.location = loc;
        } catch (e) {
          this.location = null;
        }
      }
      Logger.info(TAG, `init ok, locale=${this.locale}`);
    } catch (err) {
      Logger.error(TAG, `init failed: ${JSON.stringify(err)}`);
    }
  }

  private async put(key: string, value: preferences.ValueType): Promise<void> {
    if (!this.store) {
      return;
    }
    try {
      await this.store.put(key, value);
      await this.store.flush();
    } catch (err) {
      Logger.error(TAG, `put ${key} failed: ${JSON.stringify(err)}`);
    }
  }

  setApiOrigin(origin: string): void {
    const trimmed = origin.trim().length > 0 ? origin.trim() : DEFAULT_API_ORIGIN;
    this.apiOrigin = trimmed;
    this.put(KEY_API_ORIGIN, trimmed);
  }

  setLocale(locale: Locale): void {
    this.locale = locale;
    this.put(KEY_LOCALE, locale);
  }

  setThemePreference(pref: ThemePreference): void {
    this.themePreference = pref;
    this.put(KEY_THEME, pref);
  }

  setTtsVoice(voice: TtsVoice): void {
    this.ttsVoice = voice;
    this.put(KEY_TTS_VOICE, voice);
  }

  setThinking(on: boolean): void {
    this.thinking = on;
    this.put(KEY_THINKING, on);
  }

  setSearch(on: boolean): void {
    this.search = on;
    this.put(KEY_SEARCH, on);
  }

  setSiderCollapsed(on: boolean): void {
    this.siderCollapsed = on;
    this.put(KEY_SIDER_COLLAPSED, on);
  }

  setOnboarded(on: boolean): void {
    this.onboarded = on;
    this.put(KEY_ONBOARDED, on);
  }

  setLocation(loc: UserLocation | null): void {
    this.location = loc;
    if (loc) {
      this.put(KEY_LOCATION, JSON.stringify(loc));
    } else {
      this.put(KEY_LOCATION, '');
    }
  }
}
