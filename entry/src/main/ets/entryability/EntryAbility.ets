import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window, display } from '@kit.ArkUI';
import { SettingsStore } from '../prefs/SettingsStore';
import { KeyVault } from '../prefs/KeyVault';
import { ChatStore } from '../service/chat/ChatStore';
import { ThemeHelper } from '../common/ThemeHelper';
import { BreakpointUtil } from '../common/Breakpoint';
import { AppContextHolder } from '../common/AppContextHolder';
import { TestHarness } from '../common/TestHarness';

const DOMAIN = 0x0000;
const TAG = 'EntryAbility';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'Ability onCreate');
    AppStorage.setOrCreate<boolean>('appForeground', false);
    AppContextHolder.set(this.context);
    SettingsStore.get().init(this.context);
    ChatStore.get().restore().catch(() => {});
    KeyVault.exists(this.context).then((has: boolean) => {
      AppStorage.setOrCreate<boolean>('hasApiKey', has);
    }).catch(() => {
      AppStorage.setOrCreate<boolean>('hasApiKey', false);
    });
    TestHarness.handle(want);
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // 已在运行时经 aa start --ps 再次拉起：走同样的注入入口
    TestHarness.handle(want);
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
          // 手势条（导航指示条）区域系统默认不避让，读取高度供页面底部留白
          const indicator: window.AvoidArea =
            mainWin.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
          AppStorage.setOrCreate<number>('safeBottomVp', indicator.bottomRect.height / density);
          // 系统默认避让区（TYPE_SYSTEM）的 topRect 即状态栏高度：
          // 顶部浮层控件（抽屉钮/胶囊）按此定位在其下方
          const status: window.AvoidArea =
            mainWin.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
          AppStorage.setOrCreate<number>('safeTopVp', status.topRect.height / density);
          hilog.info(DOMAIN, TAG, `safeTop px=${status.topRect.height} density=${density} vp=${status.topRect.height / density} winH=${props.windowRect.height}`);
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
    AppStorage.setOrCreate<boolean>('appForeground', true);
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, 'Ability onBackground');
    AppStorage.setOrCreate<boolean>('appForeground', false);
  }
}
