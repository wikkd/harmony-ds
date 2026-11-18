import { Fonts } from '../../common/Fonts';
import { I18n } from '../../common/I18n';
import { Dim } from '../../common/DesignTokens';
import { KeyVault } from '../../prefs/KeyVault';
import { AppContextHolder } from '../../common/AppContextHolder';
import { SettingsStore } from '../../prefs/SettingsStore';
import { VoiceButton } from './VoiceButton';
import { FileAttachment } from '../../model/ChatTypes';
import { ModelInfo } from '../../model/ModelInfo';
import { Logger } from '../../common/Logger';
import { promptAction } from '@kit.ArkUI';

/** 底部输入区：圆角容器 + TextArea + 发送/停止按钮（鸿蒙设计语言） */
@ComponentV2
export struct ChatInput {
  @Param text: string = '';
  @Param streaming: boolean = false;
  @Param editing: boolean = false;
  @Param onTextChange: (v: string) => void = () => {};
  @Param onSend: (text: string) => void = () => {};
  @Param onCancelEdit: () => void = () => {};
  @Param onStop: () => void = () => {};
  /** 未配置 API Key 时点击发送：提示并引导到设置 */
  @Param onNeedKey: () => void = () => {};
  /** 压缩会话（用量悬浮窗内触发） */
  @Param onCompact: () => void = () => {};
  settings: SettingsStore = SettingsStore.get();
  @Local voiceActive: boolean = false;
  @Param files: FileAttachment[] = [];
  @Param onPickFiles: () => void = () => {};
  @Param onRemoveFile: (f: FileAttachment) => void = () => {};
  /** 上下文用量：可见链最近一轮 input+cache+output（0 表示尚无回执） */
  @Param contextUsed: number = 0;
  @Param contextLimit: number = 1;
  @Param lastOutputTokens: number = 0;
  @Param sessionInputTokens: number = 0;
  @Param sessionOutputTokens: number = 0;
  @Local showUsagePopup: boolean = false;

  @Builder
  attachChip(f: FileAttachment) {
    Row({ space: 4 }) {
      Image(f.isImage ? $r('app.media.ic_public_picture') : $r('app.media.ic_public_file'))
        .width(14)
        .height(14)
        .fillColor($r('app.color.text_secondary'))
      Text(f.name)
        .fontSize(Fonts.caption())
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: 120 })
      Image($r('app.media.ic_public_close'))
        .width(12)
        .height(12)
        .fillColor($r('app.color.text_tertiary'))
        .onClick(() => {
          this.onRemoveFile(f);
        })
    }
    .padding({ left: 8, right: 6, top: 4, bottom: 4 })
    .backgroundColor($r('app.color.component_normal'))
    .borderRadius(Dim.radiusS)
  }

  @Builder
  toggle(labelKey: string, on: boolean, onTap: () => void) {
    Row({ space: 4 }) {
      Text(I18n.translate(labelKey))
        .fontSize(Fonts.body3())
        .fontColor(on ? $r('app.color.brand_activated') : $r('app.color.text_tertiary'))
    }
    .padding({ left: 10, right: 10, top: 5, bottom: 5 })
    .borderRadius(14)
    .backgroundColor(on ? $r('app.color.thinking_bg') : $r('app.color.component_normal'))
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.93 })
    .onClick(() => {
      onTap();
    })
  }

  /** 用量明细悬浮窗：占比环 + token 统计 */
  @Builder
  usagePopup() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text(I18n.translate('contextUsageTitle'))
          .fontSize(Fonts.body2())
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Text(ModelInfo.NAME)
          .fontSize(Fonts.caption())
          .fontColor($r('app.color.text_tertiary'))
      }
      .width('100%')

      Stack() {
        DataPanel({
          values: [this.contextUsed],
          max: this.contextLimit,
          type: DataPanelType.Circle,
        })
          .width(64)
          .height(64)
          .strokeWidth(7)
          .valueColors([$r('app.color.brand')])
          .trackBackgroundColor($r('app.color.component_normal'))
        Column({ space: 1 }) {
          Text(this.usedPercentText())
            .fontSize(Fonts.body1())
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
          Text(I18n.translate('contextUsed'))
            .fontSize(Fonts.caption())
            .fontColor($r('app.color.text_tertiary'))
        }
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')

      this.usageRow(I18n.translate('contextUsed'), this.fmtTokens(this.contextUsed))
      this.usageRow(I18n.translate('contextRemaining'), this.fmtTokens(Math.max(0, this.contextLimit - this.contextUsed)))
      this.usageRow(I18n.translate('contextLastOutput'), this.fmtTokens(this.lastOutputTokens))
      this.usageRow(I18n.translate('contextSessionTotal'),
        `${this.fmtTokens(this.sessionInputTokens)} / ${this.fmtTokens(this.sessionOutputTokens)}`)
      if (this.contextUsed > 0) {
        Divider().color($r('app.color.list_separator')).strokeWidth(1)
        Row() {
          Text(I18n.translate('compactAction'))
            .fontSize($r('app.float.font_body3'))
            .fontColor($r('app.color.brand_activated'))
        }
        .width('100%')
        .height(32)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.showUsagePopup = false;
          this.onCompact();
        })
      }
    }
    .padding(14)
    .width(236)
  }

  @Builder
  usageRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(Fonts.caption())
        .fontColor($r('app.color.text_secondary'))
      Blank()
      Text(value)
        .fontSize(Fonts.caption())
        .fontColor($r('app.color.text_primary'))
    }
    .width('100%')
  }

  build() {
    Column() {
      if (this.voiceActive) {
        // 语音输入激活面板
        VoiceButton({
          onText: (text: string) => {
            this.switchVoice(false);
            this.onTextChange(text);
          },
          onDismiss: () => {
            this.switchVoice(false);
          },
        })
        .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 30 }))
          .animation({ duration: 260, curve: Curve.Smooth }))
      } else if (!this.settings.customModel) {
        // 自定义模型：不显示 DeepSeek 专有工具（语音/思考/搜索/附件/用量环）
        // 工具行：语音 / 深度思考 / 智能搜索 / 附件
        Row({ space: 8 }) {
          Image($r('app.media.ic_public_voice'))
            .width(24)
            .height(24)
            .padding(1)
            .fillColor($r('app.color.text_secondary'))
            .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.85 })
            .onClick(() => {
              this.switchVoice(true);
            })
          this.toggle('thinkingSwitch', this.settings.thinking, (): void => {
            this.settings.setThinking(!this.settings.thinking);
          })
          this.toggle('search', this.settings.search, (): void => {
            this.settings.setSearch(!this.settings.search);
          })
          Image($r('app.media.ic_public_add'))
            .width(24)
            .height(24)
            .padding(1)
            .fillColor($r('app.color.text_secondary'))
            .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.85 })
            .onClick(() => {
              this.onPickFiles();
            })
          Blank()
          // 上下文占用占比环：点击弹出用量明细
          DataPanel({
            values: [this.contextUsed],
            max: this.contextLimit,
            type: DataPanelType.Circle,
          })
            .width(22)
            .height(22)
            .strokeWidth(3)
            .valueColors([$r('app.color.brand')])
            .trackBackgroundColor($r('app.color.component_normal'))
            .onClick(() => {
              this.showUsagePopup = !this.showUsagePopup;
            })
            .bindPopup(!!this.showUsagePopup, {
              builder: (): void => {
                this.usagePopup()
              },
              placement: Placement.Top,
              popupColor: $r('app.color.dialog_bg'),
              enableArrow: true,
              autoCancel: true,
            })
        }
        .width('100%')
        .padding({ left: Dim.pagePadding, right: Dim.pagePadding, bottom: 4 })
      }

      // 草稿附件 chips
      if (this.files.length > 0) {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.files, (f: FileAttachment) => {
            this.attachChip(f)
          }, (f: FileAttachment) => f.id)
        }
        .width('100%')
        .padding({ left: Dim.pagePadding, right: Dim.pagePadding, bottom: 4 })
      }

      if (this.editing) {
        // 编辑模式提示条
        Row({ space: 8 }) {
          Text(I18n.translate('editMessage'))
            .fontSize(Fonts.body3())
            .fontColor($r('app.color.brand_activated'))
            .layoutWeight(1)
          Image($r('app.media.ic_public_close'))
            .width(16)
            .height(16)
            .fillColor($r('app.color.text_tertiary'))
            .onClick(() => {
              this.onCancelEdit();
            })
        }
        .padding({ left: 16, right: 16, top: 6 })
      }
      Row({ space: 8 }) {
        TextArea({
          text: this.text,
          placeholder: I18n.translate('chatInputPlaceholderChat'),
        })
          .constraintSize({ minHeight: 40, maxHeight: 120 })
          .fontSize(Fonts.body1())
          .fontColor($r('app.color.text_primary'))
          .placeholderColor($r('app.color.text_tertiary'))
          .placeholderFont({ size: 16 })
          .backgroundColor(Color.Transparent)
          .fontFamily(Fonts.family())
          .padding({ left: 4, right: 4 })
          .layoutWeight(1)
          .onChange((value: string) => {
            this.onTextChange(value);
          })

        if (this.streaming) {
          if (this.canSend()) {
            Image($r('app.media.ic_public_arrow_up_0'))
              .width(32)
              .height(32)
              .padding(5)
              .fillColor($r('app.color.brand'))
              .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.85 })
              .onClick(() => {
                this.send();
              })
          }
          Row() {
            Rect()
              .width(10)
              .height(10)
              .fill($r('app.color.text_primary'))
          }
          .width(36)
          .height(36)
          .borderRadius(18)
          .backgroundColor($r('app.color.component_normal'))
          .justifyContent(FlexAlign.Center)
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.85 })
          .onClick(() => {
            this.onStop();
          })
        } else {
          Image($r('app.media.ic_public_arrow_up_0'))
            .width(36)
            .height(36)
            .padding(6)
            .fillColor(this.canSend() ? $r('app.color.brand') : $r('app.color.text_fourth'))
            .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.85 })
            .onClick(() => {
              this.send();
            })
        }
      }
      .alignItems(VerticalAlign.Bottom)
      .padding({ left: 12, right: 8, top: 6, bottom: 6 })
      .backgroundColor($r('app.color.text_field_bg'))
      .borderRadius(Dim.radiusL)
      .constraintSize({ maxWidth: Dim.inputMaxWidth })
      .width('100%')
    }
    .padding({ left: Dim.pagePadding, right: Dim.pagePadding, bottom: 8, top: 4 })
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  /** 语音面板开关（含进出场动画作用域） */
  private switchVoice(on: boolean): void {
    this.getUIContext().animateTo({ duration: 260, curve: Curve.Smooth }, () => {
      this.voiceActive = on;
    });
  }

  private canSend(): boolean {
    return this.text.trim().length > 0;
  }

  /** token 数格式化：1.2K / 3.4M / 原值 */
  private fmtTokens(n: number): string {
    if (n >= 1000000) {
      return `${(n / 1000000).toFixed(2)}M`;
    }
    if (n >= 1000) {
      return `${(n / 1000).toFixed(1)}K`;
    }
    return `${n}`;
  }

  private usedPercentText(): string {
    if (this.contextUsed <= 0) {
      return '—';
    }
    const pct = Math.min(100, this.contextUsed / this.contextLimit * 100);
    return `${pct < 1 ? pct.toFixed(1) : Math.round(pct)}%`;
  }

  private send(): void {
    const value = this.text.trim();
    if (value === '') {
      return;
    }
    KeyVault.load(AppContextHolder.get()).then((key: string | null) => {
      if (key === null || key === '') {
        Logger.warn('ChatInput', 'no api key');
        this.getUIContext().getPromptAction().showToast({ message: I18n.translate('apiKeyRequired'), duration: 2000 });
        this.onNeedKey();
        return;
      }
      this.onSend(value);
    }).catch(() => {});
  }
}
