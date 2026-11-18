import { notificationManager } from '@kit.NotificationKit';
import { wantAgent, WantAgent, Want, common } from '@kit.AbilityKit';
import { AppContextHolder } from '../../common/AppContextHolder';
import { SettingsStore } from '../../prefs/SettingsStore';
import { I18n } from '../../common/I18n';
import { Logger } from '../../common/Logger';

const TAG: string = 'NotifyService';

/**
 * 系统通知：应用在后台时提醒回复完成/失败；前台静默不打扰。
 * 授权通过 requestEnableNotification 系统弹窗获取（拒绝后需到系统设置开启）。
 */
export class NotifyService {
  /** 请求通知授权（系统弹窗），返回是否已允许 */
  static async requestEnable(): Promise<boolean> {
    try {
      const ctx = AppContextHolder.get() as common.UIAbilityContext;
      await notificationManager.requestEnableNotification(ctx);
      return true;
    } catch (err) {
      Logger.warn(TAG, `requestEnable failed: ${JSON.stringify(err)}`);
      return false;
    }
  }

  /** 回复结束通知（done/error）；应用前台或未开启设置时不发布 */
  static async replySettled(sessionTitle: string, failed: boolean): Promise<void> {
    try {
      if (AppStorage.get<boolean>('appForeground') === true) {
        return;
      }
      if (!SettingsStore.get().notifyOnReply) {
        return;
      }
      const ctx = AppContextHolder.get() as common.UIAbilityContext;
      const want: Want = { bundleName: ctx.abilityInfo.bundleName };
      const info: wantAgent.WantAgentInfo = { wants: [want], requestCode: 0 };
      const agent: WantAgent = await wantAgent.getWantAgent(info);
      const title = sessionTitle === '' ? I18n.translate('appName') : sessionTitle;
      const text = I18n.translate(failed ? 'notifyReplyFailed' : 'notifyReplyDone');
      const request: notificationManager.NotificationRequest = {
        id: 1001,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: { title: title, text: text },
        },
        wantAgent: agent,
      };
      await notificationManager.publish(request);
    } catch (err) {
      Logger.warn(TAG, `publish failed: ${JSON.stringify(err)}`);
    }
  }
}
