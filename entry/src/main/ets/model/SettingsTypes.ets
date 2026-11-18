/** 应用语言 */
export type Locale = 'zh-CN' | 'en-US';

/** 主题偏好；默认跟随系统 */
export type ThemePreference = 'light' | 'dark' | 'system';

/** TTS 音色 */
export type TtsVoice = 'stella' | 'tide';

/** 思考强度（output_config.effort，仅 low/high/max 三档有效值） */
export type ThinkingEffort = 'low' | 'high' | 'max';

/** 位置信息（用于搜索结果本地化，对齐原项目 UserLocation） */
export class UserLocation {
  region: string = 'CN';
  province: string | null = null;
  city: string | null = null;
}
