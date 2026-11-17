import { ConfigurationConstant } from '@kit.AbilityKit';
import { Context } from '@kit.AbilityKit';
import { ThemePreference } from '../model/SettingsTypes';

/** 主题应用：设置变更后调用，跟随/浅色/深色三态 */
export class ThemeHelper {
  static apply(context: Context, pref: ThemePreference): void {
    try {
      const appContext = context.getApplicationContext();
      if (pref === 'light') {
        appContext.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
      } else if (pref === 'dark') {
        appContext.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
      } else {
        appContext.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
      }
    } catch (err) {
      // 忽略
    }
  }
}
