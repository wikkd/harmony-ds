import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window, display } from '@kit.ArkUI';
import { SettingsStore } from '../prefs/SettingsStore';
import { KeyVault } from '../prefs/KeyVault';
import { ThemeHelper } from '../common/ThemeHelper';
import { BreakpointUtil } from '../common/Breakpoint';
import { AppContextHolder } from '../common/AppContextHolder';

const DOMAIN = 0x0000;
const TAG = 'EntryAbility';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'Ability onCreate');
    AppContextHolder.set(this.context);
    SettingsStore.get().init(this.context);
    KeyVault.exists(this.context).then((has: boolean) => {
      AppStorage.setOrCreate<boolean>('hasApiKey', has);
    }).catch(() => {
      AppStorage.setOrCreate<boolean>('hasApiKey', false);
    });
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, 'Ability onWindowStageCreate');
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'Failed to load content: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, TAG, 'Succeeded in loading content.');
    });

    try {
      // 主题按设置应用（默认跟随系统）
      const settings = SettingsStore.get();
      ThemeHelper.apply(this.context, settings.themePreference);
      settings.init(this.context).then(() => {
        ThemeHelper.apply(this.context, settings.themePreference);
      });
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to set colorMode: %{public}s', JSON.stringify(err));
    }

    // 断点监听：窗口尺寸变化 → AppStorage（vp = px / densityPixels）
    try {
      const mainWin = windowStage.getMainWindowSync();
      const update = (): void => {
        try {
          const props: window.WindowProperties = mainWin.getWindowProperties();
          const density: number = display.getDefaultDisplaySync().densityPixels || 2;
          BreakpointUtil.updateWindowWidth(props.windowRect.width / density);
        } catch (e) {
          hilog.warn(DOMAIN, TAG, 'breakpoint update failed: %{public}s', JSON.stringify(e));
        }
      };
      mainWin.on('windowSizeChange', () => update());
      update();
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'windowSizeChange register failed: %{public}s', JSON.stringify(err));
    }
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, 'Ability onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, 'Ability onBackground');
  }
}
