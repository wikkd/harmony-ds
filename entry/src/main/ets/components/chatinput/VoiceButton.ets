import { Fonts } from '../../common/Fonts';
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { AppContextHolder } from '../../common/AppContextHolder';
import { Recorder } from '../../service/speech/Recorder';
import { SpeechApi } from '../../service/speech/SpeechApi';
import { KeyVault } from '../../prefs/KeyVault';
import { I18n } from '../../common/I18n';
import { Dim } from '../../common/DesignTokens';
import { Logger } from '../../common/Logger';

/**
 * 语音输入激活态面板：录音计时 / 取消 / 结束并转写。
 * 由 ChatInput 在 voiceActive 时渲染；转写结果经 onText 回填输入框。
 */
@ComponentV2
export struct VoiceButton {
  @Param onText: (text: string) => void = () => {};
  @Param onDismiss: () => void = () => {};
  @Local recMs: number = 0;
  @Local transcribing: boolean = false;
  private recorder?: Recorder;

  aboutToAppear(): void {
    this.begin();
  }

  aboutToDisappear(): void {
    if (this.recorder !== undefined) {
      this.recorder.cancel();
      this.recorder = undefined;
    }
  }

  build() {
    Row({ space: 8 }) {
      if (this.transcribing) {
        LoadingProgress()
          .width(18)
          .height(18)
          .color($r('app.color.brand'))
        Text(I18n.translate('voiceInputCancel'))
          .fontSize(Fonts.body3())
          .fontColor($r('app.color.text_secondary'))
          .layoutWeight(1)
          .onClick(() => {
            this.onDismiss();
          })
      } else {
        Circle()
          .width(10)
          .height(10)
          .fill($r('app.color.warning'))
        Text(I18n.translate('voiceInputTimer', { 'seconds': `${Math.floor(this.recMs / 1000)}` }))
          .fontSize(Fonts.body3())
          .fontColor($r('app.color.text_primary'))
        Blank()
        // 取消
        Image($r('app.media.ic_public_close'))
          .width(20)
          .height(20)
          .fillColor($r('app.color.text_tertiary'))
          .onClick(() => {
            this.cancelOnly();
          })
        // 结束并转写
        Image($r('app.media.ic_public_ok'))
          .width(20)
          .height(20)
          .fillColor($r('app.color.brand'))
          .onClick(() => {
            this.finish();
          })
      }
    }
    .width('100%')
    .padding({ left: Dim.pagePadding, right: Dim.pagePadding, top: 6, bottom: 6 })
  }

  private async begin(): Promise<void> {
    try {
      const context = AppContextHolder.get() as common.UIAbilityContext;
      const atManager = abilityAccessCtrl.createAtManager();
      const result = await atManager.requestPermissionsFromUser(context,
        ['ohos.permission.MICROPHONE'] as Array<Permissions>);
      let granted = false;
      for (const r of result.authResults) {
        if (r === 0) {
          granted = true;
        }
      }
      if (!granted) {
        Logger.warn('VoiceButton', 'mic permission denied');
        this.onDismiss();
        return;
      }
    } catch (err) {
      Logger.warn('VoiceButton', `perm request failed: ${JSON.stringify(err)}`);
      this.onDismiss();
      return;
    }
    const rec = new Recorder();
    rec.onTick = (ms: number) => {
      this.recMs = ms;
    };
    this.recorder = rec;
    try {
      await rec.start();
      this.recMs = 0;
    } catch (err) {
      Logger.warn('VoiceButton', `start failed: ${JSON.stringify(err)}`);
      this.recorder = undefined;
      this.onDismiss();
    }
  }

  private async finish(): Promise<void> {
    const rec = this.recorder;
    if (rec === undefined) {
      this.onDismiss();
      return;
    }
    this.recorder = undefined;
    this.transcribing = true;
    try {
      const path = await rec.stop();
      if (path === null) {
        this.onDismiss();
        return;
      }
      const apiKey = await KeyVault.load(AppContextHolder.get());
      if (apiKey === null || apiKey === '') {
        this.onDismiss();
        return;
      }
      const text = await SpeechApi.transcribe(apiKey, path);
      this.transcribing = false;
      if (text.trim() !== '') {
        this.onText(text.trim());
      } else {
        this.onDismiss();
      }
    } catch (err) {
      Logger.warn('VoiceButton', `asr failed: ${JSON.stringify(err)}`);
      this.onDismiss();
    }
  }

  private cancelOnly(): void {
    if (this.recorder !== undefined) {
      this.recorder.cancel();
      this.recorder = undefined;
    }
    this.onDismiss();
  }
}
