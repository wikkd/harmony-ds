import { Fonts } from '../../common/Fonts';
import { I18n } from '../../common/I18n';
import { Dim, Motion } from '../../common/DesignTokens';
import { KeyVault } from '../../prefs/KeyVault';
import { AppContextHolder } from '../../common/AppContextHolder';
import { SettingsStore } from '../../prefs/SettingsStore';
import { VoiceButton } from './VoiceButton';
import { FileAttachment } from '../../model/ChatTypes';
import { ModelInfo } from '../../model/ModelInfo';
import { Logger } from '../../common/Logger';
import { promptAction } from '@kit.ArkUI';

/**
 * 底部输入面板（仿 DeepSeek 官方 App）：
 * 单张圆角毛玻璃卡片 = 上输入区 + 下工具行（chips 居左，圆钮居右）。
 */
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
  /** 附件面板（拍照/相册/文件）展开状态 */
  @Local attachPanelOpen: boolean = false;
  @Param files: FileAttachment[] = [];
  @Param onCapture: () => void = () => {};
  @Param onPickPhotos: () => void = () => {};
  @Param onPickDocs: () => void = () => {};
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
      if (f.isImage && f.localPath !== '') {
        // 待发图片出小缩略图，与消息区预览一致（沙箱路径需 file:// 方案）
        Image(`file://${f.localPath}`)
          .width(22)
          .height(22)
          .borderRadius(4)
          .objectFit(ImageFit.Cover)
      } else {
        Image(f.isImage ? $r('app.media.ic_public_picture') : $r('app.media.ic_public_file'))
          .width(15)
          .height(15)
          .fillColor($r('app.color.text_secondary'))
      }
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

  /**
   * 功能 chip：图标 + 文字（开启=蓝底蓝字，关闭=灰底灰字）。
   * 开关状态经 on() 读取而非按值传参：@Builder 按值参数不随状态刷新
   */
  @Builder
  toggle(labelKey: string, icon: Resource, on: () => boolean, onTap: () => void) {
    Row({ space: 5 }) {
      Image(icon)
        .width(15)
        .height(15)
        .fillColor(on() ? $r('app.color.brand_activated') : $r('app.color.text_tertiary'))
      Text(I18n.translate(labelKey))
        .fontSize(Fonts.body3())
        .fontColor(on() ? $r('app.color.brand_activated') : $r('app.color.text_tertiary'))
    }
    .padding({ left: 12, right: 12, top: 7, bottom: 7 })
    .borderRadius(18)
    .backgroundColor(on() ? $r('app.color.thinking_bg') : $r('app.color.component_normal'))
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.93 })
    .onClick(() => {
      onTap();
    })
  }

  /** 线框圆钮（附件 / 语音），仿官方 + 与按住说话按钮 */
  @Builder
  outlineCircle(icon: Resource, onTap: () => void) {
    Row() {
      Image(icon)
        .width(18)
        .height(18)
        .fillColor($r('app.color.text_secondary'))
    }
    .width(29)
    .height(29)
    .borderRadius(14.5)
    .border({ width: 1.5, color: $r('app.color.text_secondary') })
    .justifyContent(FlexAlign.Center)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.85 })
    .onClick(() => {
      onTap();
    })
  }

  /** 附件圆钮：面板展开时变为 X（状态在 builder 体内经 this 读取才可刷新） */
  @Builder
  attachCircle() {
    Row() {
      Image(this.attachPanelOpen ? $r('app.media.ic_public_cancel') : $r('app.media.ic_public_add'))
        .width(18)
        .height(18)
        .fillColor($r('app.color.text_secondary'))
    }
    .width(29)
    .height(29)
    .borderRadius(14.5)
    .border({ width: 1.5, color: $r('app.color.text_secondary') })
    .justifyContent(FlexAlign.Center)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.85 })
    .onClick(() => {
      this.toggleAttachPanel();
    })
  }

  /** 附件面板动作卡：图标 + 文字（仿官方三宫格） */
  @Builder
  attachAction(icon: Resource, labelKey: string, onTap: () => void) {
    Column({ space: 10 }) {
      Image(icon)
        .width(22)
        .height(22)
        .fillColor($r('app.color.text_primary'))
      Text(I18n.translate(labelKey))
        .fontSize(Fonts.body2())
        .fontColor($r('app.color.text_primary'))
    }
    .layoutWeight(1)
    .height(80)
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.component_normal'))
    .borderRadius(14)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 })
    .onClick(() => {
      onTap();
    })
  }

  /** 附件面板：拍照 / 相册 / 文件 */
  @Builder
  attachPanel() {
    Row({ space: 8 }) {
      this.attachAction($r('app.media.ic_public_camera'), 'attachPhoto', (): void => {
        this.toggleAttachPanel(false);
        this.onCapture();
      })
      this.attachAction($r('app.media.ic_public_picture'), 'attachAlbum', (): void => {
        this.toggleAttachPanel(false);
        this.onPickPhotos();
      })
      this.attachAction($r('app.media.ic_public_file'), 'attachFile', (): void => {
        this.toggleAttachPanel(false);
        this.onPickDocs();
      })
    }
    .width('100%')
    .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 24 }))
      .animation({ duration: Motion.animFast, curve: Curve.Smooth }))
  }

  /** 发送圆钮（品牌蓝底白箭头） */
  @Builder
  sendCircle() {
    Row() {
      Image($r('app.media.ic_public_arrow_up_0'))
        .width(18)
        .height(18)
        .fillColor($r('app.color.text_primary_contrary'))
    }
    .width(29)
    .height(29)
    .borderRadius(14.5)
    .backgroundColor($r('app.color.brand'))
    .justifyContent(FlexAlign.Center)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.85 })
    .onClick(() => {
      this.send();
    })
  }

  /** 停止圆钮（流式期间） */
  @Builder
  stopCircle() {
    Row() {
      Rect()
        .width(10)
        .height(10)
        .fill($r('app.color.text_primary'))
    }
    .width(29)
    .height(29)
    .borderRadius(14.5)
    .border({ width: 1.5, color: $r('app.color.text_secondary') })
    .justifyContent(FlexAlign.Center)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.85 })
    .onClick(() => {
      this.onStop();
    })
  }

  /** 编辑模式提示条 */
  @Builder
  editBar() {
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
    .padding({ left: 14, right: 14, top: 10 })
    .width('100%')
  }

  /** 输入区（透明 TextArea） */
  @Builder
  inputArea() {
    TextArea({
      text: this.text,
      placeholder: I18n.translate('chatInputPlaceholderChat'),
    })
      .constraintSize({ minHeight: 44, maxHeight: 140 })
      .fontSize(Fonts.body1())
      .fontColor($r('app.color.text_primary'))
      .placeholderColor($r('app.color.text_tertiary'))
        .placeholderFont({ size: Fonts.body1() })
        .backgroundColor(Color.Transparent)
        .padding({ left: 10, right: 10, top: 6, bottom: 2 })
      .onChange((value: string) => {
        this.onTextChange(value);
      })
      .onFocus(() => {
        // 点输入框：收起附件面板
        this.toggleAttachPanel(false);
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
      // 低于压缩阈值不展示入口：低占用压缩无意义，避免点了才被告知拒绝
      if (this.contextUsed >= this.contextLimit * ModelInfo.COMPACT_MIN_RATIO) {
        Divider().color($r('app.color.list_separator')).strokeWidth(1)
        Row() {
          Text(I18n.translate('compactAction'))
            .fontSize(Fonts.body3())
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
    Column({ space: 10 }) {
      Column() {
        if (this.voiceActive) {
          // 语音输入面板（替换面板内容）
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
            .animation({ duration: Motion.animBase, curve: Curve.Smooth }))
        } else if (this.settings.customModel) {
          // 自定义模型：仅输入 + 发送（DeepSeek 专有工具不可用）
          if (this.editing) {
            this.editBar()
          }
          Row({ space: 8 }) {
            Column() {
              this.inputArea()
            }
            .layoutWeight(1)

            if (this.streaming) {
              if (this.canSend()) {
                this.sendCircle()
              }
              this.stopCircle()
            } else {
              this.sendCircle()
            }
          }
          .alignItems(VerticalAlign.Bottom)
          .width('100%')
          .padding({ left: 10, right: 10, top: 2, bottom: 8 })
        } else {
          // 草稿附件 chips
          if (this.files.length > 0) {
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.files, (f: FileAttachment) => {
                this.attachChip(f)
              }, (f: FileAttachment) => f.id)
            }
            .width('100%')
            .padding({ left: 14, right: 14, top: 12, bottom: 2 })
          }
          if (this.editing) {
            this.editBar()
          }

          this.inputArea()

          // 工具行：chips 居左；用量环 / 附件 / 语音|发送 居右
          Row({ space: 8 }) {
            this.toggle('thinkingSwitch', $r('app.media.ic_public_favor'), (): boolean => this.settings.thinking,
              (): void => {
                this.settings.setThinking(!this.settings.thinking);
              })
            this.toggle('search', $r('app.media.ic_public_search'), (): boolean => this.settings.search,
              (): void => {
                this.settings.setSearch(!this.settings.search);
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
            this.attachCircle()
            if (this.streaming) {
              if (this.canSend()) {
                this.sendCircle()
              }
              this.stopCircle()
            } else if (this.canSend()) {
              this.sendCircle()
            } else {
              this.outlineCircle($r('app.media.ic_public_voice'), (): void => {
                this.switchVoice(true);
              })
            }
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .padding({ left: 10, right: 10, top: 6, bottom: 8 })
        }
      }
      .width('100%')
      .margin({ bottom: 2 })
      .padding({ top: 4 })
      .alignItems(HorizontalAlign.Center)
      .borderRadius(28)
      // 毛玻璃：半透明底色（blur_input 72% 不透明度）+ 组件实时模糊，
      // 消息从面板下方滚过时透出内容（与顶部胶囊同款质感）
      .backgroundBlurStyle(BlurStyle.COMPONENT_THIN)
      .backgroundColor($r('app.color.blur_input'))
      .shadow({ radius: 16, color: 'rgba(0,0,0,0.06)', offsetY: -4 })

      if (this.attachPanelOpen && !this.voiceActive) {
        this.attachPanel()
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  /** 附件面板开合（展开前收起键盘；含进出场动画作用域） */
  private toggleAttachPanel(force?: boolean): void {
    const next = force === undefined ? !this.attachPanelOpen : force;
    if (next === this.attachPanelOpen) {
      return;
    }
    if (next) {
      this.getUIContext().getFocusController().clearFocus();
    }
    this.getUIContext().animateTo({ duration: Motion.animFast, curve: Curve.Smooth }, () => {
      this.attachPanelOpen = next;
    });
  }

  /** 语音面板开关（含进出场动画作用域） */
  private switchVoice(on: boolean): void {
    this.getUIContext().animateTo({ duration: Motion.animBase, curve: Curve.Smooth }, () => {
      this.attachPanelOpen = false;
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
    this.toggleAttachPanel(false);
    KeyVault.load(AppContextHolder.get()).then((key: string | null) => {
      if (key === null || key === '') {
        Logger.warn('ChatInput', 'no api key');
        this.getUIContext().getPromptAction().showToast({ message: I18n.translate('apiKeyRequired'), duration: Motion.toastMid });
        this.onNeedKey();
        return;
      }
      this.onSend(value);
    }).catch(() => {});
  }
}
