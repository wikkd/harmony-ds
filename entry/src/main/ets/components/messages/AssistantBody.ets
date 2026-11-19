import { Fonts } from '../../common/Fonts';
import { I18n } from '../../common/I18n';
import { Dim, Motion } from '../../common/DesignTokens';
import { pasteboard } from '@kit.BasicServicesKit';
import { AssistantMessage, TextPart, ThinkingPart } from '../../model/ChatTypes';
import { MarkdownView } from '../markdown/MarkdownView';
import { MarkdownParser } from '../markdown/MarkdownParser';
import { AppContextHolder } from '../../common/AppContextHolder';
import { common, Context, Want } from '@kit.AbilityKit';
import { Logger } from '../../common/Logger';
import { SpeechApi } from '../../service/speech/SpeechApi';
import { TtsPlayer } from '../../service/speech/TtsPlayer';
import { KeyVault } from '../../prefs/KeyVault';
import { SettingsStore } from '../../prefs/SettingsStore';
import { ApiError } from '../../model/ApiError';

/** 全局唯一 TTS 播放器（新朗读会停止旧的） */
class TtsActive {
  static current: TtsPlayer | null = null;

  static stop(): void {
    if (TtsActive.current !== null) {
      TtsActive.current.stop().catch(() => {});
      TtsActive.current = null;
    }
  }
}

class CitationCard {
  url: string = '';
  title: string = '';
}

function replyTextOf(m: AssistantMessage): string {
  let out = '';
  for (const b of m.blocks) {
    if (b.type === 'text') {
      out += b.textPart.text;
    }
  }
  return out;
}

/** 复制文本到剪贴板；成功提示由调用方（组件内，this 可用）用 UIContext 弹出 */
export async function copyToClipboard(text: string): Promise<void> {
  const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
  await pasteboard.getSystemPasteboard().setData(data);
}

function openUrl(url: string): void {
  try {
    const ability = AppContextHolder.get();
    // 开放链接到浏览器
    openLink(ability, url);
  } catch (err) {
    Logger.warn('MessageList', `open url failed: ${JSON.stringify(err)}`);
  }
}

function openLink(context: Context, url: string): void {
  const uiAbility = context as common.UIAbilityContext;
  const want: Want = {
    action: 'ohos.want.action.viewData',
    entities: ['entity.system.browsable'],
    uri: url,
  };
  uiAbility.startAbility(want).catch(() => {});
}

/** 助手消息正文：思考折叠块 + 文本渲染 + 引用来源抽屉 + 错误条 + 操作行（复制/朗读/重新生成） */
@ComponentV2
export struct AssistantBody {
  @Param message: AssistantMessage = new AssistantMessage('0', 0);
  @Param onRegenerate: () => void = () => {};
  @Local thinkingOpen: boolean = false;
  @Local ttsPlaying: boolean = false;
  /** 搜索来源抽屉展开态：默认收起 */
  @Local sourcesOpen: boolean = false;

  build() {
    Column({ space: 8 }) {
      // 思考折叠块：智能搜索会产生多段 reasoning，合并为一个抽屉展示
      if (this.thinkingBlocks().length > 0) {
        Column({ space: 8 }) {
          Row({ space: 6 }) {
            // 时钟图标：贴合“思考中/耗时”语义（原 code 方块图案不表意）
            Image($r('app.media.ic_public_time_filled'))
              .width(16)
              .height(16)
              .fillColor($r('app.color.text_tertiary'))
            Text(this.thinkingHeaderLabel())
              .fontSize(Fonts.body3())
              .fontColor($r('app.color.text_tertiary'))
            Blank()
            Image($r('app.media.ic_public_arrow_right'))
              .width(14)
              .height(14)
              .rotate({ angle: this.thinkingOpen ? 90 : 0 })
              .fillColor($r('app.color.text_tertiary'))
          }
          .width('100%')
          .onClick(() => {
            this.getUIContext().animateTo({ duration: Motion.animBase, curve: Curve.Smooth }, (): void => {
              this.thinkingOpen = !this.thinkingOpen;
            });
          })

          if (this.thinkingOpen) {
            Column({ space: 8 }) {
              ForEach(this.thinkingBlocks(), (t: ThinkingPart) => {
                Text(t.thinking)
                  .fontSize(Fonts.body3())
                  .lineHeight(20)
                  .fontColor($r('app.color.text_secondary'))
                  .width('100%')
              }, (t: ThinkingPart) => `th_${t.startedAt}`)
            }
            .width('100%')
            .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 8 }))
              .animation({ duration: Motion.animBase, curve: Curve.Smooth }))
          }
        }
        .padding(10)
        .backgroundColor($r('app.color.thinking_bg'))
        .borderRadius(Dim.radiusM)
        .width('100%')
      }

      ForEach(this.displaySources(), (src: string, si: number) => {
        Column() {
          // 流式期间用纯文本保性能；结束后 Markdown 富渲染
          if (this.message.status === 'streaming') {
            Text(src)
              .fontSize(Fonts.body1())
              .lineHeight(26)
              .fontColor($r('app.color.text_primary'))
              .width('100%')
          } else {
            MarkdownView({ source: src })
          }
        }
        .width('100%')
      }, (src: string, si: number) => `tx${si}_${src.length}`)

      // 引用来源：抽屉式收纳（默认收起，点标题展开），样式与思考折叠块一致
      if (this.citationCards().length > 0) {
        Column({ space: 8 }) {
          Row({ space: 6 }) {
            Image($r('app.media.ic_public_search'))
              .width(16)
              .height(16)
              .fillColor($r('app.color.text_tertiary'))
            Text(I18n.translate('sourcesCount', { 'count': `${this.citationCards().length}` }))
              .fontSize(Fonts.body3())
              .fontColor($r('app.color.text_tertiary'))
            Blank()
            Image($r('app.media.ic_public_arrow_right'))
              .width(14)
              .height(14)
              .rotate({ angle: this.sourcesOpen ? 90 : 0 })
              .fillColor($r('app.color.text_tertiary'))
          }
          .width('100%')
          .onClick(() => {
            this.getUIContext().animateTo({ duration: Motion.animBase, curve: Curve.Smooth }, (): void => {
              this.sourcesOpen = !this.sourcesOpen;
            });
          })

          if (this.sourcesOpen) {
            Column({ space: 8 }) {
              ForEach(this.citationCards(), (card: CitationCard, ci: number) => {
                Row({ space: 8 }) {
                  Text(`${ci + 1}`)
                    .fontSize(Fonts.caption())
                    .fontColor($r('app.color.text_primary_contrary'))
                    .width(18)
                    .height(18)
                    .borderRadius(9)
                    .backgroundColor($r('app.color.brand'))
                    .textAlign(TextAlign.Center)
                  Column({ space: 2 }) {
                    Text(card.title)
                      .fontSize(Fonts.body3())
                      .fontColor($r('app.color.text_primary'))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .width('100%')
                    Text(card.url)
                      .fontSize(Fonts.caption())
                      .fontColor($r('app.color.text_tertiary'))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .width('100%')
                  }
                  .layoutWeight(1)
                }
                .width('100%')
                .padding(8)
                .backgroundColor($r('app.color.code_block_bg'))
                .borderRadius(Dim.radiusS)
                .onClick(() => {
                  openUrl(card.url);
                })
              }, (card: CitationCard, ci: number) => `cite${ci}`)
            }
            .width('100%')
            .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 8 }))
              .animation({ duration: Motion.animBase, curve: Curve.Smooth }))
          }
        }
        .padding(10)
        .backgroundColor($r('app.color.thinking_bg'))
        .borderRadius(Dim.radiusM)
        .width('100%')
      }

      if (this.message.status === 'streaming' && this.textBlocks().length === 0
        && this.thinkingBlocks().length === 0) {
        Row({ space: 8 }) {
          LoadingProgress()
            .width(16)
            .height(16)
            .color($r('app.color.text_tertiary'))
          Text(I18n.translate('messageThinking'))
            .fontSize(Fonts.body3())
            .fontColor($r('app.color.text_tertiary'))
        }
        .width('100%')
      }

      if (this.message.status === 'error' && this.message.error !== null) {
        Row({ space: 8 }) {
          Image($r('app.media.ic_public_error'))
            .width(16)
            .height(16)
            .fillColor($r('app.color.warning'))
          Text(this.errorText())
            .fontSize(Fonts.body3())
            .fontColor($r('app.color.warning'))
            .layoutWeight(1)
        }
        .padding(10)
        .backgroundColor($r('app.color.thinking_bg'))
        .borderRadius(Dim.radiusM)
        .width('100%')
      }

      // 操作行：复制 / 朗读 / 重新生成
      if (this.message.status === 'done' || this.message.status === 'stopped') {
        Row({ space: 14 }) {
          Image($r('app.media.ic_public_copy'))
            .width(16)
            .height(16)
            .fillColor($r('app.color.text_tertiary'))
            .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.85 })
            .onClick(() => {
              copyToClipboard(replyTextOf(this.message)).then(() => {
                this.getUIContext().getPromptAction()
                  .showToast({ message: I18n.translate('copied'), duration: Motion.toastShort });
              }).catch((err: object) => {
                Logger.warn('MessageList', `copy failed: ${JSON.stringify(err)}`);
              });
            })
          if (!SettingsStore.get().customModel && SettingsStore.get().ttsEnabled) {
            Image(this.ttsPlaying ? $r('app.media.ic_public_sound_off') : $r('app.media.ic_public_sound'))
              .width(16)
              .height(16)
              .fillColor($r('app.color.text_tertiary'))
              .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.85 })
              .onClick(() => {
                this.toggleTts(this.message);
              })
          }
          Image($r('app.media.ic_public_refresh'))
            .width(16)
            .height(16)
            .fillColor($r('app.color.text_tertiary'))
            .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.85 })
            .onClick(() => {
              this.onRegenerate();
            })
        }
        .width('100%')
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  private thinkingBlocks(): ThinkingPart[] {
    const out: ThinkingPart[] = [];
    for (const b of this.message.blocks) {
      if (b.type === 'thinking') {
        out.push(b.thinkingPart);
      }
    }
    return out;
  }

  /** 文本块渲染源：流式分段把句末标点单独切开（独立段或下一段开头）时并回前一段，避免单独成行 */
  private displaySources(): string[] {
    const out: string[] = [];
    for (const b of this.message.blocks) {
      if (b.type !== 'text') {
        continue;
      }
      let t = b.textPart.text;
      if (out.length > 0) {
        // 开头独立成行的纯标点：挪回上一段末尾
        const nl = t.indexOf('\n');
        const firstLine = (nl < 0 ? t : t.substring(0, nl)).trim();
        if (firstLine !== '' && MarkdownParser.isPunctOnlyText(firstLine)) {
          out[out.length - 1] += (out[out.length - 1].endsWith('\n') ? '' : '\n\n') + firstLine;
          t = nl < 0 ? '' : t.substring(nl + 1);
          if (t.trim() === '') {
            continue;
          }
        }
        // 整段纯标点：并入上一段
        if (MarkdownParser.isPunctOnlyText(t)) {
          out[out.length - 1] += (out[out.length - 1].endsWith('\n') ? '' : '\n\n') + t;
          continue;
        }
      }
      out.push(t);
    }
    return out;
  }

  private textBlocks(): TextPart[] {
    const out: TextPart[] = [];
    for (const b of this.message.blocks) {
      if (b.type === 'text') {
        out.push(b.textPart);
      }
    }
    return out;
  }

  /** 合并思考头标题：任一段未结束显示“正在思考”，否则显示首段开始到末段结束的总时长 */
  private thinkingHeaderLabel(): string {
    const parts = this.thinkingBlocks();
    let running = false;
    let start = 0;
    let end = 0;
    for (const t of parts) {
      if (t.startedAt > 0 && (start === 0 || t.startedAt < start)) {
        start = t.startedAt;
      }
      if (t.endedAt === 0) {
        running = true;
      }
      if (t.endedAt > end) {
        end = t.endedAt;
      }
    }
    if (running || end === 0 || start === 0) {
      return I18n.translate('messageThinking');
    }
    const seconds = Math.max(1, Math.round((end - start) / 1000));
    return I18n.translate('messageThinkDuration', { 'count': `${seconds}` });
  }

  private errorText(): string {
    const err = this.message.error;
    if (err === null) {
      return I18n.translate('unknownError');
    }
    const key = ApiError.replyKeyFor(err.kind, err.status);
    if (key === 'requestFailed') {
      return I18n.translate(key, { 'message': err.message });
    }
    return I18n.translate(key);
  }

  /** 朗读 / 停止朗读（TTS 流式播放） */
  private toggleTts(m: AssistantMessage): void {
    if (this.ttsPlaying) {
      TtsActive.stop();
      this.ttsPlaying = false;
      return;
    }
    const text = replyTextOf(m).trim();
    if (text === '') {
      return;
    }
    KeyVault.load(AppContextHolder.get()).then((apiKey: string | null) => {
      if (apiKey === null || apiKey === '') {
        return;
      }
      const player = new TtsPlayer();
      TtsActive.current = player;
      this.ttsPlaying = true;
      player.start().then(() => {
        return new Promise<void>((resolve) => {
          SpeechApi.synthesize(apiKey, text, SettingsStore.get().ttsVoice, {
            onChunk: (chunk: ArrayBuffer) => {
              player.write(chunk);
            },
            onDone: () => {
              player.drain().then(() => player.stop()).catch(() => {});
              if (TtsActive.current === player) {
                TtsActive.current = null;
              }
              this.ttsPlaying = false;
              resolve();
            },
            onError: () => {
              player.stop().catch(() => {});
              if (TtsActive.current === player) {
                TtsActive.current = null;
              }
              this.ttsPlaying = false;
              resolve();
            },
          });
        });
      }).catch(() => {
        this.ttsPlaying = false;
      });
    });
  }

  /** 汇总正文引用为去重来源卡 */
  private citationCards(): CitationCard[] {
    const out: CitationCard[] = [];
    const seen: Set<string> = new Set();
    for (const b of this.message.blocks) {
      if (b.type !== 'text') {
        continue;
      }
      for (const c of b.textPart.citations) {
        if (seen.has(c.url)) {
          continue;
        }
        seen.add(c.url);
        const card = new CitationCard();
        card.url = c.url;
        card.title = c.title === null || c.title === '' ? c.url : c.title;
        out.push(card);
        if (out.length >= 8) {
          return out;
        }
      }
    }
    return out;
  }
}
