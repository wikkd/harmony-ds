import { Fonts } from '../../common/Fonts';
import { I18n } from '../../common/I18n';
import { Dim } from '../../common/DesignTokens';
import { SettingsStore } from '../../prefs/SettingsStore';
import { ThemeHelper } from '../../common/ThemeHelper';
import { AppContextHolder } from '../../common/AppContextHolder';
import { NotifyService } from '../../service/notify/NotifyService';
import { LiveViewService } from '../../service/notify/LiveViewService';
import { UserLocation, ThemePreference, ThinkingEffort } from '../../model/SettingsTypes';
import { promptAction } from '@kit.ArkUI';
import { PageHeader } from './PageHeader';

/** 省份/地区（位置信息用于联网搜索本地化） */
const PROVINCES: string[] = [
  '北京', '天津', '河北', '山西', '内蒙古', '辽宁', '吉林', '黑龙江', '上海', '江苏',
  '浙江', '安徽', '福建', '江西', '山东', '河南', '湖北', '湖南', '广东', '广西',
  '海南', '重庆', '四川', '贵州', '云南', '西藏', '陕西', '甘肃', '青海', '宁夏', '新疆',
  '香港', '澳门', '台湾',
];

/** 选项词条（顺序即索引，与设置值映射表配套） */
const THEME_KEYS: string[] = [
  'avatarMenuSettingsDialogThemeSelectSystemOption',
  'avatarMenuSettingsDialogThemeSelectLightOption',
  'avatarMenuSettingsDialogThemeSelectDarkOption',
];
const FONT_SCALE_KEYS: string[] = ['fontOptSmall', 'fontOptStandard', 'fontOptLarge', 'fontOptXl'];
const FONT_SCALES: string[] = ['small', 'standard', 'large', 'xl'];
const EFFORT_KEYS: string[] = ['thinkingEffortLow', 'thinkingEffortStandard', 'thinkingEffortMax'];
const EFFORTS: ThinkingEffort[] = ['low', 'high', 'max'];
const LOCALE_KEYS: string[] = ['settingsLocaleZhCN', 'settingsLocaleEnUS'];

/**
 * 设置页（仿官方 DeepSeek App）：
 * 圆形返回钮 + 居中标题；小灰分组头 + 白圆角卡；行 = 图标 + 标题 + 灰色当前值 + 箭头。
 * 选择类行点开居中单选弹窗（鸿蒙 Radio + 确认按钮，确认才生效）；
 * 朗读音色为底部面板（Swiper 音色卡轮播 + 确认）；数据/模型/个性化/隐私跳独立子页。
 */
@ComponentV2
export struct SettingsPage {
  @Param pathStack: NavPathStack = new NavPathStack();
  settings: SettingsStore = SettingsStore.get();
  /** 居中单选弹窗状态 */
  @Local dialogVisible: boolean = false;
  @Local dialogHasIcon: boolean = false;
  @Local dialogIcon: Resource | null = null;
  @Local dialogTitle: string = '';
  @Local dialogOptions: string[] = [];
  @Local dialogSelected: number = -1;
  @Local dialogPending: number = -1;
  private dialogOnSelect: (idx: number) => void = (): void => {};
  /** 朗读音色底部面板状态 */
  @Local voiceSheetVisible: boolean = false;
  @Local voicePending: number = 0;

  build() {
    NavDestination() {
      Stack() {
        Column() {
          PageHeader({
            title: I18n.translate('settings'),
            onBack: (): void => {
              this.pathStack.pop();
            },
          })
          Scroll() {
            Column({ space: 16 }) {
              // ---------- 模型与服务 ----------
              this.sectionHeader('modelAndService')
              Column() {
                this.optionRow('modelAndService', $r('app.media.ic_public_settings'),
                  (): string => this.settings.model, (): void => {
                    this.pathStack.pushPathByName('model', null);
                  })
              }
              .backgroundColor($r('app.color.card_bg'))
              .borderRadius(Dim.radiusL)
              .width('100%')
              .padding({ top: 6, bottom: 6 })

              // ---------- 外观 ----------
              this.sectionHeader('settingsGroupAppearance')
              Column() {
                this.optionRow('avatarMenuSettingsDialogThemeItemLabel', $r('app.media.ic_public_brightness'),
                  (): string => this.selectedLabel(THEME_KEYS, (): number => this.themeIdx()),
                  (): void => {
                    this.openRadio('', THEME_KEYS, (): number => this.themeIdx(), (idx: number): void => {
                      const prefs: ThemePreference[] = ['system', 'light', 'dark'];
                      this.settings.setThemePreference(prefs[idx]);
                      this.applyTheme();
                    })
                  })
                this.optionRow('fontSizeLabel', $r('app.media.ic_public_text'),
                  (): string => this.selectedLabel(FONT_SCALE_KEYS, (): number => this.scaleIdx()),
                  (): void => {
                    this.openRadio('fontSizeLabel', FONT_SCALE_KEYS, (): number => this.scaleIdx(),
                      (idx: number): void => {
                        this.settings.setFontScale(FONT_SCALES[idx]);
                      })
                  })
              }
              .backgroundColor($r('app.color.card_bg'))
              .borderRadius(Dim.radiusL)
              .width('100%')
              .padding({ top: 6, bottom: 6 })

              // ---------- 对话 ----------
              this.sectionHeader('settingsGroupChat')
              Column() {
                this.toggleRow('thinkingSwitch', $r('app.media.ic_public_favor'),
                  (): boolean => this.settings.thinking, (on: boolean): void => {
                    this.settings.setThinking(on);
                  })
                Column() {
                  this.optionRow('thinkingEffortLabel', $r('app.media.ic_public_stopwatch'),
                    (): string => this.selectedLabel(EFFORT_KEYS, (): number => this.effortIdx()),
                    (): void => {
                      this.openRadio('thinkingEffortLabel', EFFORT_KEYS, (): number => this.effortIdx(),
                        (idx: number): void => {
                          this.settings.setThinkingEffort(EFFORTS[idx]);
                        })
                    })
                }
                .width('100%')
                .opacity(this.settings.thinking ? 1 : 0.4)
                this.toggleRow('search', $r('app.media.ic_public_search'),
                  (): boolean => this.settings.search, (on: boolean): void => {
                    this.settings.setSearch(on);
                  })
                this.optionRow('personalization', $r('app.media.ic_public_emoji'),
                  (): string => this.settings.personalization === '' ? '' : I18n.translate('personalizationEnabled'),
                  (): void => {
                    this.pathStack.pushPathByName('persona', null);
                  })
              }
              .backgroundColor($r('app.color.card_bg'))
              .borderRadius(Dim.radiusL)
              .width('100%')
              .padding({ top: 6, bottom: 6 })

              // ---------- 语音 ----------
              this.sectionHeader('settingsGroupVoice')
              Column() {
                this.toggleRow('settingsTtsEnable', $r('app.media.ic_public_ring'),
                  (): boolean => this.settings.ttsEnabled, (on: boolean): void => {
                    this.settings.setTtsEnabled(on);
                  })
                this.optionRow('settingsTtsVoice', $r('app.media.ic_public_sound'),
                  (): string => this.voiceLabel(), (): void => {
                    this.openVoiceSheet();
                  })
              }
              .backgroundColor($r('app.color.card_bg'))
              .borderRadius(Dim.radiusL)
              .width('100%')
              .padding({ top: 6, bottom: 6 })

              // ---------- 语言与地区 ----------
              this.sectionHeader('settingsGroupLocale')
              Column() {
                this.optionRow('settingsLocalePreference', $r('app.media.ic_public_translate'),
                  (): string => this.selectedLabel(LOCALE_KEYS, (): number => this.localeIdx()),
                  (): void => {
                    this.openRadio('settingsLocalePreference', LOCALE_KEYS, (): number => this.localeIdx(),
                      (idx: number): void => {
                        this.settings.setLocale(idx === 0 ? 'zh-CN' : 'en-US');
                      }, $r('app.media.ic_public_translate'))
                  })
                this.optionRow('settingsLocation', $r('app.media.ic_public_gps'),
                  (): string => {
                    const loc = this.settings.location;
                    return loc === null || loc.province === null
                      ? I18n.translate('settingsLocationNone') : loc.province;
                  },
                  (): void => {
                    this.openRadio('settingsLocation', ['settingsLocationNone', ...PROVINCES],
                      (): number => {
                        const loc = this.settings.location;
                        if (loc === null || loc.province === null) {
                          return 0;
                        }
                        const idx = PROVINCES.indexOf(loc.province);
                        return idx >= 0 ? idx + 1 : 0;
                      }, (idx: number): void => {
                        if (idx === 0) {
                          this.settings.setLocation(null);
                          return;
                        }
                        const loc = new UserLocation();
                        loc.region = 'CN';
                        loc.province = PROVINCES[idx - 1];
                        this.settings.setLocation(loc);
                      }, $r('app.media.ic_public_gps'))
                  })
              }
              .backgroundColor($r('app.color.card_bg'))
              .borderRadius(Dim.radiusL)
              .width('100%')
              .padding({ top: 6, bottom: 6 })

              // ---------- 通知 ----------
              this.sectionHeader('settingsGroupNotify')
              Column() {
                this.toggleRow('notifyOnReply', $r('app.media.ic_public_ring'),
                  (): boolean => this.settings.notifyOnReply, (on: boolean): void => {
                    if (!on) {
                      this.settings.setNotifyOnReply(false);
                      return;
                    }
                    NotifyService.requestEnable().then((granted: boolean) => {
                      if (granted) {
                        this.settings.setNotifyOnReply(true);
                      } else {
                        this.getUIContext().getPromptAction()
                          .showToast({ message: I18n.translate('notifyPermissionDenied'), duration: 2500 });
                      }
                    }).catch(() => {});
                  })
                this.toggleRow('liveViewOnReply', $r('app.media.ic_public_clock'),
                  (): boolean => this.settings.liveViewOnReply, (on: boolean): void => {
                    this.settings.setLiveViewOnReply(on);
                    if (!on) {
                      LiveViewService.replyEnded().catch(() => {});
                    }
                  })
              }
              .backgroundColor($r('app.color.card_bg'))
              .borderRadius(Dim.radiusL)
              .width('100%')
              .padding({ top: 6, bottom: 6 })

              // ---------- 数据 ----------
              this.sectionHeader('settingsGroupData')
              Column() {
                this.optionRow('dataManage', $r('app.media.ic_public_storage'), (): string => '', (): void => {
                  this.pathStack.pushPathByName('data', null);
                })
              }
              .backgroundColor($r('app.color.card_bg'))
              .borderRadius(Dim.radiusL)
              .width('100%')
              .padding({ top: 6, bottom: 6 })

              // ---------- 关于 ----------
              this.sectionHeader('about')
              Column() {
                this.infoRow('version', $r('app.media.ic_public_upgrade'), '1.0.0')
                this.optionRow('privacyPolicyTitle', $r('app.media.ic_public_privacy'), (): string => '', (): void => {
                  this.pathStack.pushPathByName('privacy', null);
                })
              }
              .backgroundColor($r('app.color.card_bg'))
              .borderRadius(Dim.radiusL)
              .width('100%')
              .padding({ top: 6, bottom: 6 })
              Text(I18n.translate('portingFrom'))
                .fontSize(Fonts.caption())
                .fontColor($r('app.color.text_tertiary'))
                .width('100%')
                .padding({ left: 16, bottom: 44 })
            }
            .padding({ left: Dim.pagePadding, right: Dim.pagePadding, top: 4 })
            .constraintSize({ maxWidth: Dim.contentMaxWidth })
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .align(Alignment.Top)
          // 内容滚动手势条下方：行滚到底部只被手势条浮层遮住，不在安全区分界线被裁切
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
        }
        .width('100%')
        .height('100%')

        // 居中单选弹窗（遮罩 + 卡片，仿官方；确认才生效）
        if (this.dialogVisible) {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor('rgba(0,0,0,0.35)')
            .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 1 })
            .onClick(() => {
              this.closeDialog();
            })
            .transition(TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.Smooth }))
          Column() {
            if (this.dialogHasIcon && this.dialogIcon !== null) {
              Image(this.dialogIcon)
                .width(28)
                .height(28)
                .fillColor($r('app.color.text_primary'))
                .margin({ top: 20 })
            }
            Text(this.dialogTitle)
              .fontSize(Fonts.body1())
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .textAlign(TextAlign.Center)
              .width('100%')
              .padding({ left: 20, right: 20, top: 18, bottom: 10 })
            List({ space: 0 }) {
              ForEach(this.dialogOptions, (opt: string, idx: number) => {
                ListItem() {
                  Row({ space: 12 }) {
                    Radio({ value: `${idx}`, group: 'settingsRadio' })
                      .checked(idx === this.dialogPending)
                      .onChange((on: boolean) => {
                        if (on) {
                          this.dialogPending = idx;
                        }
                      })
                    Text(opt)
                      .fontSize(Fonts.body1())
                      .fontColor($r('app.color.text_primary'))
                      .layoutWeight(1)
                  }
                  .width('100%')
                  .height(48)
                  .padding({ left: 20, right: 20 })
                  .onClick(() => {
                    this.dialogPending = idx;
                  })
                }
              }, (opt: string, idx: number) => `${idx}_${opt}`)
            }
            .width('100%')
            .constraintSize({ maxHeight: 360 })
            Divider()
              .color($r('app.color.list_separator'))
              .strokeWidth(Dim.separator)
            Text(I18n.translate('confirm'))
              .fontSize(Fonts.body1())
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.brand_activated'))
              .textAlign(TextAlign.Center)
              .width('100%')
              .height(52)
              .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
              .onClick(() => {
                this.applyDialog();
              })
          }
          .width('82%')
          .constraintSize({ maxWidth: 360 })
          .backgroundColor($r('app.color.dialog_bg'))
          .borderRadius(Dim.radiusL)
          .clip(true)
          .transition(TransitionEffect.OPACITY.combine(TransitionEffect.scale({ x: 0.95, y: 0.95 }))
            .animation({ duration: 200, curve: Curve.Smooth }))
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.settings_bg'))
      .bindSheet(!!this.voiceSheetVisible, this.voiceSheet(), {
        height: SheetSize.FIT_CONTENT,
        dragBar: true,
        showClose: false,
        backgroundColor: $r('app.color.dialog_bg'),
        onDisappear: (): void => {
          this.voiceSheetVisible = false;
        },
      })
    }
    .hideTitleBar(true)
    .backgroundColor($r('app.color.settings_bg'))
    // 灰底延伸进手势条避让区，否则 Navigation 白底在页面底部露条
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  /** 分组小灰头 */
  @Builder
  sectionHeader(titleKey: string) {
    Text(I18n.translate(titleKey))
      .fontSize(Fonts.caption())
      .fontColor($r('app.color.text_tertiary'))
      .width('100%')
      .padding({ left: 16, top: 4, bottom: 2 })
  }

  /** 选项行：图标 + 标题 + 灰色当前值（空则隐藏）+ 箭头，整行可点 */
  @Builder
  optionRow(labelKey: string, icon: Resource, valueFn: () => string, onTap: () => void) {
    Row({ space: 12 }) {
      Image(icon)
        .width(22)
        .height(22)
        .fillColor($r('app.color.text_primary'))
      Text(I18n.translate(labelKey))
        .fontSize(Fonts.body1())
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
      if (valueFn() !== '') {
        Text(valueFn())
          .fontSize(Fonts.body2())
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: '46%' })
      }
      Image($r('app.media.ic_public_arrow_right'))
        .width(16)
        .height(16)
        .fillColor($r('app.color.text_tertiary'))
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 16 })
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.98 })
    .onClick(() => {
      onTap();
    })
  }

  /** 信息行：图标 + 标题 + 只读值（无箭头） */
  @Builder
  infoRow(labelKey: string, icon: Resource, value: string) {
    Row({ space: 12 }) {
      Image(icon)
        .width(22)
        .height(22)
        .fillColor($r('app.color.text_primary'))
      Text(I18n.translate(labelKey))
        .fontSize(Fonts.body1())
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
      Text(value)
        .fontSize(Fonts.body2())
        .fontColor($r('app.color.text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: '46%' })
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 16 })
  }

  /** 开关行：图标 + 标题 + Toggle */
  @Builder
  toggleRow(labelKey: string, icon: Resource, isOnFn: () => boolean, onChange: (on: boolean) => void) {
    Row({ space: 12 }) {
      Image(icon)
        .width(22)
        .height(22)
        .fillColor($r('app.color.text_primary'))
      Text(I18n.translate(labelKey))
        .fontSize(Fonts.body1())
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: isOnFn() })
        .onChange((on: boolean) => {
          onChange(on);
        })
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 16 })
  }

  /** 居中单选弹窗：点行换待选，点确认才落盘生效 */
  private openRadio(labelKey: string, optionKeys: string[], selectedFn: () => number,
    onSelect: (idx: number) => void, icon?: Resource): void {
    const opts: string[] = [];
    for (const k of optionKeys) {
      opts.push(I18n.translate(k));
    }
    this.dialogTitle = labelKey === '' ? I18n.translate('settingsGroupAppearance') : I18n.translate(labelKey);
    this.dialogOptions = opts;
    this.dialogPending = selectedFn();
    this.dialogOnSelect = onSelect;
    this.dialogHasIcon = icon !== undefined;
    this.dialogIcon = icon !== undefined ? icon : null;
    this.getUIContext().animateTo({ duration: 200, curve: Curve.Smooth }, () => {
      this.dialogVisible = true;
    });
  }

  private applyDialog(): void {
    this.dialogOnSelect(this.dialogPending);
    this.closeDialog();
  }

  private closeDialog(): void {
    this.getUIContext().animateTo({ duration: 200, curve: Curve.Smooth }, () => {
      this.dialogVisible = false;
    });
  }

  /** 音色底部面板（官方：标题居中 + 右上关闭圆钮 + 卡片轮播 + 圆点 + 确认胶囊） */
  private openVoiceSheet(): void {
    this.voicePending = this.voiceIdx();
    this.voiceSheetVisible = true;
  }

  private voiceLabel(): string {
    return this.voiceIdx() === 0 ? I18n.translate('settingsTtsVoiceStella') : I18n.translate('settingsTtsVoiceTide');
  }

  @Builder
  voiceSheet() {
    Column() {
      Stack({ alignContent: Alignment.End }) {
        Text(I18n.translate('settingsTtsVoice'))
          .fontSize(Fonts.body1())
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
          .textAlign(TextAlign.Center)
        Row() {
          Image($r('app.media.ic_public_cancel'))
            .width(16)
            .height(16)
            .fillColor($r('app.color.text_secondary'))
        }
        .width(32)
        .height(32)
        .borderRadius(16)
        .backgroundColor($r('app.color.component_normal'))
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.9 })
        .onClick(() => {
          this.voiceSheetVisible = false;
        })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 4 })

      Swiper() {
        // 海星（女声）：浅蓝柔光
        Column({ space: 10 }) {
          Column()
            .width(200)
            .height(104)
            .borderRadius(52)
            .linearGradient({
              angle: 135,
              colors: [['#EAF1FF', 0], ['#AFC7FF', 0.55], ['#DCE7FF', 1]],
            })
          Text(I18n.translate('settingsTtsVoiceStella'))
            .fontSize(Fonts.body1())
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text(I18n.translate('settingsTtsVoiceStellaDesc'))
            .fontSize(Fonts.caption())
            .fontColor($r('app.color.text_tertiary'))
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)

        // 暗潮（男声）：靛蓝沉稳
        Column({ space: 10 }) {
          Column()
            .width(200)
            .height(104)
            .borderRadius(52)
            .linearGradient({
              angle: 135,
              colors: [['#E3E9FF', 0], ['#8CA5EA', 0.55], ['#C6D2F2', 1]],
            })
          Text(I18n.translate('settingsTtsVoiceTide'))
            .fontSize(Fonts.body1())
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text(I18n.translate('settingsTtsVoiceTideDesc'))
            .fontSize(Fonts.caption())
            .fontColor($r('app.color.text_tertiary'))
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
      }
      .index(this.voicePending)
      .indicator(false)
      .loop(false)
      .itemSpace(16)
      .width('100%')
      .height(190)
      .margin({ top: 12 })
      .onChange((idx: number) => {
        this.voicePending = idx;
      })

      // 圆点页码（手动绘制，激活点品牌蓝）
      Row({ space: 10 }) {
        Circle({ width: 6, height: 6 })
          .fill(this.voicePending === 0
            ? $r('app.color.brand_activated')
            : $r('app.color.component_normal'))
        Circle({ width: 6, height: 6 })
          .fill(this.voicePending === 1
            ? $r('app.color.brand_activated')
            : $r('app.color.component_normal'))
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .margin({ top: 14 })

      Button(I18n.translate('confirm'))
        .fontSize(Fonts.body1())
        .fontWeight(FontWeight.Medium)
        .backgroundColor($r('app.color.brand'))
        .fontColor($r('app.color.text_primary_contrary'))
        .width('86%')
        .height(46)
        .borderRadius(23)
        .margin({ top: 22 })
        .onClick(() => {
          this.settings.setTtsVoice(this.voicePending === 0 ? 'stella' : 'tide');
          this.voiceSheetVisible = false;
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, bottom: 28 })
    .alignItems(HorizontalAlign.Center)
  }

  /** 当前选中项文案（索引越界返回空串） */
  private selectedLabel(optionKeys: string[], selectedFn: () => number): string {
    const idx = selectedFn();
    return idx >= 0 && idx < optionKeys.length ? I18n.translate(optionKeys[idx]) : '';
  }

  private themeIdx(): number {
    return this.settings.themePreference === 'system' ? 0 : (this.settings.themePreference === 'light' ? 1 : 2);
  }

  private scaleIdx(): number {
    return FONT_SCALES.indexOf(this.settings.fontScale);
  }

  private effortIdx(): number {
    return this.settings.thinkingEffort === 'low' ? 0 : (this.settings.thinkingEffort === 'high' ? 1 : 2);
  }

  private voiceIdx(): number {
    return this.settings.ttsVoice === 'stella' ? 0 : 1;
  }

  private localeIdx(): number {
    return this.settings.locale === 'zh-CN' ? 0 : 1;
  }

  private applyTheme(): void {
    ThemeHelper.apply(AppContextHolder.get(), this.settings.themePreference);
  }
}
