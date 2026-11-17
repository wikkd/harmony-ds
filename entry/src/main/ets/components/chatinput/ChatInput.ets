import { I18n } from '../../common/I18n';
import { Dim } from '../../common/DesignTokens';
import { KeyVault } from '../../prefs/KeyVault';
import { AppContextHolder } from '../../common/AppContextHolder';
import { SettingsStore } from '../../prefs/SettingsStore';
import { VoiceButton } from './VoiceButton';
import { FileAttachment } from '../../model/ChatTypes';
import { Logger } from '../../common/Logger';

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
  settings: SettingsStore = SettingsStore.get();
  @Local voiceActive: boolean = false;
  @Param files: FileAttachment[] = [];
  @Param onPickFiles: () => void = () => {};
  @Param onRemoveFile: (f: FileAttachment) => void = () => {};

  @Builder
  attachChip(f: FileAttachment) {
    Row({ space: 4 }) {
      Image(f.isImage ? $r('app.media.ic_public_picture') : $r('app.media.ic_public_file'))
        .width(14)
        .height(14)
        .fillColor($r('app.color.text_secondary'))
      Text(f.name)
        .fontSize($r('app.float.font_caption'))
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
  toggle(label: string, on: boolean, onTap: () => void) {
    Row({ space: 4 }) {
      Text(label)
        .fontSize($r('app.float.font_body3'))
        .fontColor(on ? $r('app.color.brand_activated') : $r('app.color.text_tertiary'))
    }
    .padding({ left: 10, right: 10, top: 5, bottom: 5 })
    .borderRadius(14)
    .backgroundColor(on ? $r('app.color.thinking_bg') : $r('app.color.component_normal'))
    .onClick(() => {
      onTap();
    })
  }

  build() {
    Column() {
      if (this.voiceActive) {
        // 语音输入激活面板
        VoiceButton({
          onText: (text: string) => {
            this.voiceActive = false;
            this.onTextChange(text);
          },
          onDismiss: () => {
            this.voiceActive = false;
          },
        })
      } else {
        // 工具行：语音 / 深度思考 / 智能搜索 / 附件
        Row({ space: 8 }) {
          Image($r('app.media.ic_public_voice'))
            .width(24)
            .height(24)
            .padding(1)
            .fillColor($r('app.color.text_secondary'))
            .onClick(() => {
              this.voiceActive = true;
            })
          this.toggle(I18n.translate('thinkingSwitch'), this.settings.thinking, (): void => {
            this.settings.setThinking(!this.settings.thinking);
          })
          this.toggle(I18n.translate('search'), this.settings.search, (): void => {
            this.settings.setSearch(!this.settings.search);
          })
          Image($r('app.media.ic_public_add'))
            .width(24)
            .height(24)
            .padding(1)
            .fillColor($r('app.color.text_secondary'))
            .onClick(() => {
              this.onPickFiles();
            })
          Blank()
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
            .fontSize($r('app.float.font_body3'))
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
          .fontSize($r('app.float.font_body1'))
          .fontColor($r('app.color.text_primary'))
          .placeholderColor($r('app.color.text_tertiary'))
          .placeholderFont({ size: 16 })
          .backgroundColor(Color.Transparent)
          .padding({ left: 4, right: 4 })
          .layoutWeight(1)
          .onChange((value: string) => {
            this.onTextChange(value);
          })

        if (this.streaming) {
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
          .onClick(() => {
            this.onStop();
          })
        } else {
          Image($r('app.media.ic_public_arrow_up_0'))
            .width(36)
            .height(36)
            .padding(6)
            .fillColor(this.canSend() ? $r('app.color.brand') : $r('app.color.text_fourth'))
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

  private canSend(): boolean {
    return this.text.trim().length > 0;
  }

  private send(): void {
    const value = this.text.trim();
    if (value === '') {
      return;
    }
    KeyVault.load(AppContextHolder.get()).then((key: string | null) => {
      if (key === null || key === '') {
        Logger.warn('ChatInput', 'no api key');
        return;
      }
      this.onSend(value);
    }).catch(() => {});
  }
}
