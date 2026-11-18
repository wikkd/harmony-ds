import { preferences } from '@kit.ArkData';
import { Context } from '@kit.AbilityKit';
import { i18n } from '@kit.LocalizationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Locale, ThemePreference, ThinkingEffort, TtsVoice, UserLocation } from '../model/SettingsTypes';
import { ModelInfo } from '../model/ModelInfo';
import { Logger } from '../common/Logger';

const TAG: string = 'SettingsStore';
const PREF_NAME: string = 'chat_demo_settings';

/** 首选项键名，对齐原项目 chat-demo:* 前缀语义 */
const KEY_API_ORIGIN: string = 'chat-demo:api-origin';
const KEY_LOCALE: string = 'chat-demo:locale';
const KEY_LOCATION: string = 'chat-demo:location';
const KEY_THEME: string = 'chat-demo:theme-preference';
const KEY_TTS_VOICE: string = 'chat-demo:tts-voice';
const KEY_TTS_ENABLED: string = 'chat-demo:tts-enabled';
const KEY_THINKING: string = 'chat-demo:thinking';
const KEY_MODEL: string = 'chat-demo:model';
const KEY_PERSONALIZATION: string = 'chat-demo:personalization';
const KEY_FONT_SCALE: string = 'chat-demo:font-scale';
const KEY_NOTIFY_ON_REPLY: string = 'chat-demo:notify-on-reply';
const KEY_LIVE_VIEW: string = 'chat-demo:live-view';

/** 字号档位 → 缩放系数 */
const FONT_SCALES: Record<string, number> = {
  'small': 0.9,
  'standard': 1.0,
  'large': 1.15,
  'xl': 1.3,
};
const KEY_THINKING_EFFORT: string = 'chat-demo:thinking-effort';
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
  /** 模型 ID：内置 deepseek 模型走完整协议；自定义模型走标准 Anthropic 兼容协议 */
  @Trace model: string = ModelInfo.NAME;
  @Trace locale: Locale = 'zh-CN';
  @Trace themePreference: ThemePreference = 'system';
  @Trace ttsVoice: TtsVoice = 'stella';
  /** 朗读总开关：关闭后消息不出现朗读按钮 */
  @Trace ttsEnabled: boolean = true;
  @Trace thinking: boolean = false;
  /** 思考强度，深度思考开启时随请求发送 output_config.effort */
  @Trace thinkingEffort: ThinkingEffort = 'high';
  /** 个性化提示词：用户自定义人格与回复要求，注入所有新回复的 system */
  @Trace personalization: string = '';
  /** 字号档位：small | standard | large | xl */
  @Trace fontScale: string = 'standard';
  /** 回复完成/失败时（应用在后台）发系统通知 */
  @Trace notifyOnReply: boolean = false;
  /** 流式回复期间显示实况窗（灵动岛）胶囊 */
  @Trace liveViewOnReply: boolean = false;
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
      const savedModel = (this.store.getSync(KEY_MODEL, ModelInfo.NAME) as string).trim();
      this.model = savedModel === '' ? ModelInfo.NAME : savedModel;
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
      this.ttsEnabled = this.store.getSync(KEY_TTS_ENABLED, true) as boolean;
      this.thinking = this.store.getSync(KEY_THINKING, false) as boolean;
      const savedEffort = this.store.getSync(KEY_THINKING_EFFORT, 'high') as string;
      this.thinkingEffort = (savedEffort === 'low' || savedEffort === 'max') ? savedEffort : 'high';
      this.personalization = (this.store.getSync(KEY_PERSONALIZATION, '') as string).trim();
      const savedScale = this.store.getSync(KEY_FONT_SCALE, 'standard') as string;
      this.fontScale = FONT_SCALES[savedScale] !== undefined ? savedScale : 'standard';
      this.notifyOnReply = this.store.getSync(KEY_NOTIFY_ON_REPLY, false) as boolean;
      this.liveViewOnReply = this.store.getSync(KEY_LIVE_VIEW, false) as boolean;
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

  setModel(model: string): void {
    const trimmed = model.trim();
    this.model = trimmed === '' ? ModelInfo.NAME : trimmed;
    this.put(KEY_MODEL, this.model);
  }

  /** 是否为外部自定义模型（外部模型不发 DeepSeek 专有字段/工具/语音/附件） */
  get customModel(): boolean {
    return !ModelInfo.isBuiltin(this.model);
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

  setTtsEnabled(on: boolean): void {
    this.ttsEnabled = on;
    this.put(KEY_TTS_ENABLED, on);
  }

  setThinking(on: boolean): void {
    this.thinking = on;
    this.put(KEY_THINKING, on);
  }

  setSearch(on: boolean): void {
    this.search = on;
    this.put(KEY_SEARCH, on);
  }

  setThinkingEffort(effort: ThinkingEffort): void {
    this.thinkingEffort = effort;
    this.put(KEY_THINKING_EFFORT, effort);
  }

  setPersonalization(text: string): void {
    this.personalization = text.trim();
    this.put(KEY_PERSONALIZATION, this.personalization);
  }

  setFontScale(scale: string): void {
    this.fontScale = FONT_SCALES[scale] !== undefined ? scale : 'standard';
    this.put(KEY_FONT_SCALE, this.fontScale);
  }

  setNotifyOnReply(on: boolean): void {
    this.notifyOnReply = on;
    this.put(KEY_NOTIFY_ON_REPLY, on);
  }

  setLiveViewOnReply(on: boolean): void {
    this.liveViewOnReply = on;
    this.put(KEY_LIVE_VIEW, on);
  }

  /** 字号缩放系数（Fonts 助手读取） */
  fontScaleValue(): number {
    const v = FONT_SCALES[this.fontScale];
    return v === undefined ? 1.0 : v;
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
