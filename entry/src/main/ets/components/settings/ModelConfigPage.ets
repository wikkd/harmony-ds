import { Fonts } from '../../common/Fonts';
import { I18n } from '../../common/I18n';
import { Dim, Motion } from '../../common/DesignTokens';
import { SettingsStore } from '../../prefs/SettingsStore';
import { KeyVault } from '../../prefs/KeyVault';
import { ApiClient } from '../../service/api/ApiClient';
import { ApiError } from '../../model/ApiError';
import { AppContextHolder } from '../../common/AppContextHolder';
import { Logger } from '../../common/Logger';
import { promptAction } from '@kit.ArkUI';
import { PageHeader } from './PageHeader';

/** 模型与服务配置子页：API Key 校验 + 模型名称 + 服务地址（从设置页迁入） */
@ComponentV2
export struct ModelConfigPage {
  @Param pathStack: NavPathStack = new NavPathStack();
  settings: SettingsStore = SettingsStore.get();
  @Local apiKey: string = '';
  @Local verifyState: 'idle' | 'verifying' | 'ok' | 'fail' = 'idle';
  @Local verifyMsg: string = '';
  @Local modelInput: string = '';
  @Local originInput: string = '';

  aboutToAppear(): void {
    KeyVault.load(AppContextHolder.get()).then((k: string | null) => {
      if (k !== null) {
        this.apiKey = k;
        this.verifyState = 'ok';
      }
    }).catch(() => {});
    this.modelInput = this.settings.model;
    this.originInput = this.settings.apiOrigin;
  }

  /**
   * 宽屏内容收窄：不能用 constraintSize(maxWidth)——7.0.0.111 实机回归，
   * 它出现在 NavDestination 子树会让后代节点挂载错乱（图标/箭头整体缺席）。
   * 改为 Scroll 自测宽后对内容列动态加水平 padding（手机不受影响）。
   */
  @Local contentPad: number = Dim.pagePadding;

  build() {
    NavDestination() {
      Column() {
        PageHeader({
          title: I18n.translate('modelAndService'),
          onBack: (): void => {
            this.pathStack.pop();
          },
        })
        Scroll() {
          Column({ space: 16 }) {
            Column({ space: 8 }) {
              Row({ space: 8 }) {
                TextInput({
                  text: this.apiKey,
                  placeholder: I18n.translate('apiKeyPlaceholder'),
                })
                  .type(InputType.Password)
                  .fontSize(Fonts.body2())
                  .fontColor($r('app.color.text_primary'))
                  .placeholderColor($r('app.color.text_tertiary'))
                  .backgroundColor($r('app.color.text_field_sub_bg'))
                  .borderRadius(Dim.radiusS)
                  .layoutWeight(1)
                  .onChange((v: string) => {
                    this.apiKey = v;
                    this.verifyState = 'idle';
                  })
                Button(this.verifyState === 'verifying' ? I18n.translate('apiKeyVerifying') : I18n.translate('confirm'))
                  .fontSize(Fonts.body2())
                  .backgroundColor($r('app.color.brand'))
                  .fontColor($r('app.color.text_primary_contrary'))
                  .enabled(this.verifyState !== 'verifying' && this.apiKey.trim().length > 0)
                  .onClick(() => {
                    this.verify();
                  })
              }
              .width('100%')

              if (this.verifyState === 'ok') {
                Text(I18n.translate('apiKeyStart'))
                  .fontSize(Fonts.body3())
                  .fontColor($r('app.color.success'))
                  .width('100%')
              } else if (this.verifyState === 'fail') {
                Text(this.verifyMsg)
                  .fontSize(Fonts.body3())
                  .fontColor($r('app.color.warning'))
                  .width('100%')
              }
            }
            .padding(16)
            .backgroundColor($r('app.color.card_bg'))
            .borderRadius(Dim.radiusL)
            .width('100%')

            Column({ space: 8 }) {
              Column({ space: 4 }) {
                Text(I18n.translate('modelLabel'))
                  .fontSize(Fonts.caption())
                  .fontColor($r('app.color.text_tertiary'))
                  .width('100%')
                TextInput({
                  text: this.modelInput,
                  placeholder: I18n.translate('modelPlaceholder'),
                })
                  .fontSize(Fonts.body2())
                  .fontColor($r('app.color.text_primary'))
                  .placeholderColor($r('app.color.text_tertiary'))
                  .backgroundColor($r('app.color.text_field_sub_bg'))
                  .borderRadius(Dim.radiusS)
                  .onChange((v: string) => {
                    this.modelInput = v;
                  })
              }
              .width('100%')

              Column({ space: 4 }) {
                Text(I18n.translate('serviceAddressLabel'))
                  .fontSize(Fonts.caption())
                  .fontColor($r('app.color.text_tertiary'))
                  .width('100%')
                TextInput({
                  text: this.originInput,
                  placeholder: I18n.translate('serviceAddressPlaceholder'),
                })
                  .fontSize(Fonts.body2())
                  .fontColor($r('app.color.text_primary'))
                  .placeholderColor($r('app.color.text_tertiary'))
                  .backgroundColor($r('app.color.text_field_sub_bg'))
                  .borderRadius(Dim.radiusS)
                  .onChange((v: string) => {
                    this.originInput = v;
                  })
              }
              .width('100%')

              Button(I18n.translate('confirm'))
                .fontSize(Fonts.body2())
                .backgroundColor($r('app.color.brand'))
                .fontColor($r('app.color.text_primary_contrary'))
                .width('100%')
                .onClick(() => {
                  this.settings.setModel(this.modelInput);
                  this.settings.setApiOrigin(this.originInput);
                  this.getUIContext().getPromptAction()
                    .showToast({ message: I18n.translate('settingsSaved'), duration: Motion.toastShort });
                })

              Text(I18n.translate('customModelHint'))
                .fontSize(Fonts.caption())
                .fontColor($r('app.color.text_tertiary'))
                .width('100%')
            }
            .padding(16)
            .backgroundColor($r('app.color.card_bg'))
            .borderRadius(Dim.radiusL)
            .width('100%')
          }
          .padding({ left: this.contentPad, right: this.contentPad, top: 4, bottom: 44 })
        }
        .layoutWeight(1)
        .onAreaChange((_o: Area, nv: Area) => {
          const w = Number(nv.width);
          const inner = Dim.contentMaxWidth - Dim.pagePadding * 2;
          this.contentPad = Math.max(Dim.pagePadding, (w - inner) / 2);
        })
        .scrollBar(BarState.Off)
        .align(Alignment.Top)
        // 内容滚动手势条下方：行滚到底部只被手势条浮层遮住，不在安全区分界线被裁切
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.settings_bg'))
      .alignItems(HorizontalAlign.Center)
    }
    .hideTitleBar(true)
    .backgroundColor($r('app.color.settings_bg'))
    // 灰底延伸进手势条避让区，否则 Navigation 白底在页面底部露条
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  private verify(): void {
    const key = this.apiKey.trim();
    if (key === '') {
      return;
    }
    this.verifyState = 'verifying';
    ApiClient.verifyApiKey(key).then(() => {
      return KeyVault.save(AppContextHolder.get(), key).then(() => {
        this.verifyState = 'ok';
        AppStorage.setOrCreate<boolean>('hasApiKey', true);
        this.getUIContext().getPromptAction().showToast({ message: I18n.translate('apiKeyStart'), duration: Motion.toastShort });
      });
    }).catch((err: ApiError) => {
      this.verifyState = 'fail';
      this.verifyMsg = I18n.translate(ApiError.i18nKeyFor(err));
      Logger.warn('ModelConfigPage', `verify failed: ${err.message}`);
    });
  }
}
