import { KeyboardAvoidMode } from '@ohos.arkui.UIContext';
import { common } from '@kit.AbilityKit';
import { I18n } from '../common/I18n';
import { SettingsStore } from '../prefs/SettingsStore';
import { Dim, Motion } from '../common/DesignTokens';
import { LegalDocPage, buildPrivacySections, buildAgreementSections, buildAiInfoSections, buildReportSections } from '../components/privacy/LegalDocPage';
import { SettingsPage } from '../components/settings/SettingsPage';
import { ModelConfigPage } from '../components/settings/ModelConfigPage';
import { DataManagePage } from '../components/settings/DataManagePage';
import { UsagePage } from '../components/usage/UsagePage';
import { PersonaPage } from '../components/persona/PersonaPage';
import { HomePage } from './HomePage';

/**
 * 应用根：Navigation 路由 + 首启隐私合规弹窗 + 返回键收抽屉。
 * 主页壳（抽屉/侧栏）见 HomePage，会话视图见 ChatView。
 */
@Entry
@Component
struct Index {
  pathStack: NavPathStack = new NavPathStack();

  aboutToAppear(): void {
    // 键盘避让改压缩模式：默认 OFFSET 整窗上移会把标题栏顶出屏幕；
    // RESIZE 压缩窗口高度，标题栏/欢迎区保持原位，输入面板整体浮到键盘上方
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
    // 首启隐私合规：未同意前强制弹窗，拒绝则退出应用（上架审核要求）
    if (!SettingsStore.get().privacyAccepted) {
      this.showPrivacyConsent();
    }
  }

  /** 首启隐私/协议同意弹窗：不可点外关闭，拒绝即退出，下次启动再问 */
  private showPrivacyConsent(): void {
    this.getUIContext().showAlertDialog({
      title: I18n.translate('privacyConsentTitle'),
      message: I18n.translate('privacyConsentMessage'),
      alignment: DialogAlignment.Center,
      autoCancel: false,
      secondaryButton: {
        value: I18n.translate('privacyConsentDecline'),
        fontColor: $r('app.color.text_secondary'),
        action: (): void => {
          // 拒绝即退出：不写入同意标记，下次启动再次询问
          (this.getUIContext().getHostContext() as common.UIAbilityContext).terminateSelf().catch(() => {});
        },
      },
      primaryButton: {
        value: I18n.translate('privacyConsentAgree'),
        fontColor: $r('app.color.brand_activated'),
        action: (): void => {
          SettingsStore.get().setPrivacyAccepted(true);
        },
      },
    });
  }

  /** 窄屏抽屉展开时，返回键/返回手势先收起抽屉 */
  onBackPress(): boolean {
    const narrow = (AppStorage.get<number>('bpWindowWidth') ?? 0) < Dim.siderPermanentBp;
    const progress = AppStorage.get<number>('drawerProgress') ?? 0;
    if (narrow && progress > 0.01) {
      // 弹簧曲线：时长由物理参数决定（可打断、继承速度），勿配 duration
      this.getUIContext().animateTo({ curve: Motion.spring }, (): void => {
        AppStorage.setOrCreate<number>('drawerProgress', 0);
      });
      return true;
    }
    return false;
  }

  build() {
    // Navigation 作为页面根：唯一可交互层，内部承载主页与子页面。
    // （不能用「透明 Navigation 叠在主页上」的结构——空 Navigation 也会拦截全部触摸）
    Navigation(this.pathStack) {
      HomePage({ pathStack: this.pathStack })
    }
    .navDestination(this.pageMap)
    .hideTitleBar(true)
    .hideToolBar(true)
    .backgroundColor($r('app.color.app_bg'))
    .mode(NavigationMode.Stack)
    // 沉浸式：Navigation 自身扩展进状态栏/手势条避让区，
    // 内容（主页标题栏、抽屉、遮罩）才能真正铺到屏幕物理边缘
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    // 注意：Navigation 不能加底部 padding —— 会在内容与导航条之间留下白色背景条；
    // 底部避让只由主页输入区自己承担（各子页背景直接铺到屏幕底）
  }

  @Builder
  pageMap(name: string) {
    if (name === 'privacy') {
      LegalDocPage({ titleKey: 'privacyPolicyTitle', sections: buildPrivacySections() })
    } else if (name === 'agreement') {
      LegalDocPage({ titleKey: 'userAgreementTitle', sections: buildAgreementSections() })
    } else if (name === 'aiinfo') {
      LegalDocPage({ titleKey: 'aiServiceInfoTitle', sections: buildAiInfoSections() })
    } else if (name === 'report') {
      LegalDocPage({ titleKey: 'reportAbuseTitle', sections: buildReportSections() })
    } else if (name === 'settings') {
      SettingsPage({ pathStack: this.pathStack })
    } else if (name === 'usage') {
      UsagePage()
    } else if (name === 'persona') {
      PersonaPage()
    } else if (name === 'model') {
      ModelConfigPage({ pathStack: this.pathStack })
    } else if (name === 'data') {
      DataManagePage({ pathStack: this.pathStack })
    }
  }
}
