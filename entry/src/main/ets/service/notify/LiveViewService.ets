import { liveViewManager } from '@kit.LiveViewKit';
import { AppContextHolder } from '../../common/AppContextHolder';
import { SettingsStore } from '../../prefs/SettingsStore';
import { I18n } from '../../common/I18n';
import { Logger } from '../../common/Logger';

const TAG: string = 'LiveViewService';

/**
 * 实况窗（灵动岛）：流式回复期间展示「正在回复」胶囊，结束即移除。
 * 使用 LiveViewKit 本地 API；设备不支持或权益未开通时静默降级。
 */
export class LiveViewService {
  private static active: boolean = false;
  private static sequence: number = 0;
  private static readonly ID: number = 2001;

  /** 流式开始：启动实况窗胶囊 */
  static async replyStarted(sessionTitle: string): Promise<void> {
    try {
      if (LiveViewService.active || !SettingsStore.get().liveViewOnReply) {
        return;
      }
      const enabled = await liveViewManager.isLiveViewEnabled();
      if (!enabled) {
        Logger.info(TAG, 'live view not enabled on device');
        return;
      }
      const ctx = AppContextHolder.get();
      const appName = I18n.translate('appName');
      const title = sessionTitle === '' ? appName : sessionTitle;
      const replying = I18n.translate('liveViewReplying');
      const rich: liveViewManager.RichText = { text: replying };
      const primary: liveViewManager.PrimaryData = { title: title, content: [rich] };
      const capsule: liveViewManager.TextCapsule = {
        type: liveViewManager.CapsuleType.CAPSULE_TYPE_TEXT,
        status: 1,
        title: appName,
        content: replying,
      };
      const data: liveViewManager.LiveViewData = { primary: primary, capsule: capsule };
      LiveViewService.sequence++;
      const lv: liveViewManager.LiveView = {
        id: LiveViewService.ID,
        event: 'start',
        sequence: LiveViewService.sequence,
        isMute: true,
        lifeCycleMode: liveViewManager.LifeCycleMode.AUTO_STOP_WHEN_APP_TERMINATE,
        liveViewData: data,
      };
      const result = await liveViewManager.startLiveView(lv);
      if (result.resultCode === 0) {
        LiveViewService.active = true;
        Logger.info(TAG, 'live view started');
      } else {
        Logger.warn(TAG, `startLiveView result: ${result.resultCode}`);
      }
    } catch (err) {
      Logger.warn(TAG, `startLiveView failed: ${JSON.stringify(err)}`);
    }
  }

  /** 流式结束：移除实况窗 */
  static async replyEnded(): Promise<void> {
    if (!LiveViewService.active) {
      return;
    }
    LiveViewService.active = false;
    try {
      LiveViewService.sequence++;
      const appName = I18n.translate('appName');
      const rich: liveViewManager.RichText = { text: I18n.translate('liveViewReplying') };
      const primary: liveViewManager.PrimaryData = { title: appName, content: [rich] };
      const data: liveViewManager.LiveViewData = { primary: primary };
      const lv: liveViewManager.LiveView = {
        id: LiveViewService.ID,
        event: 'end',
        sequence: LiveViewService.sequence,
        liveViewData: data,
      };
      await liveViewManager.stopLiveView(lv);
      Logger.info(TAG, 'live view stopped');
    } catch (err) {
      Logger.warn(TAG, `stopLiveView failed: ${JSON.stringify(err)}`);
    }
  }
}
