import { Fonts } from '../../common/Fonts';
import { I18n } from '../../common/I18n';
import { Dim, Motion } from '../../common/DesignTokens';
import { SettingsStore } from '../../prefs/SettingsStore';
import { ThemeHelper } from '../../common/ThemeHelper';
import { AppContextHolder } from '../../common/AppContextHolder';
import { NotifyService } from '../../service/notify/NotifyService';
import { LiveViewService } from '../../service/notify/LiveViewService';
import { UserLocation, ThemePreference, ThinkingEffort } from '../../model/SettingsTypes';
import { promptAction } from '@kit.ArkUI';
import { PageHeader } from './PageHeader';
import { SettingRow } from './SettingRow';

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
/** 音色卡装饰渐变（与主题无关的固定视觉） */
const STELLA_GRADIENT: Array<[ResourceColor, number]> = [['#EAF1FF', 0], ['#AFC7FF', 0.55], ['#DCE7FF', 1]];
const TIDE_GRADIENT: Array<[ResourceColor, number]> = [['#E3E9FF', 0], ['#8CA5EA', 0.55], ['#C6D2F2', 1]];

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
  /**
   * 宽屏内容收窄：不能用 constraintSize(maxWidth)——7.0.0.111 实机回归，
   * 它出现在 NavDestination 子树会让后代节点挂载错乱（图标/开关整体缺席）。
   * 改为 Scroll 自测宽后对内容列动态加水平 padding（手机不受影响）。
   */
  @Local contentPad: number = Dim.pagePadding;

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
                SettingRow({
                  label: I18n.translate('modelAndService'),
                  icon: $r('app.media.ic_public_settings'),
                  value: this.settings.model,
                  showArrow: true,
                  tappable: true,
                  onRowTap: (): void => {
                    this.pathStack.pushPathByName('model', null);
                  },
                })
              }
              .backgroundColor($r('app.color.card_bg'))
              .borderRadius(Dim.radiusL)
              .width('100%')
              .padding({ top: 6, bottom: 6 })

              // ---------- 外观 ----------
              this.sectionHeader('settingsGroupAppearance')
              Column() {
                SettingRow({
                  label: I18n.translate('avatarMenuSettingsDialogThemeItemLabel'),
                  icon: $r('app.media.ic_public_brightness'),
                  value: this.selectedLabel(THEME_KEYS, (): number => this.themeIdx()),
                  showArrow: true,
                  tappable: true,
                  onRowTap: (): void => {
                    this.openRadio('', THEME_KEYS, (): number => this.themeIdx(), (idx: number): void => {
                      const prefs: ThemePreference[] = ['system', 'light', 'dark'];
                      this.settings.setThemePreference(prefs[idx]);
                      this.applyTheme();
                    })
                  },
                })
                SettingRow({
                  label: I18n.translate('fontSizeLabel'),
                  icon: $r('app.media.ic_public_text'),
                  value: this.selectedLabel(FONT_SCALE_KEYS, (): number => this.scaleIdx()),
                  showArrow: true,
                  tappable: true,
                  onRowTap: (): void => {
                    this.openRadio('fontSizeLabel', FONT_SCALE_KEYS, (): number => this.scaleIdx(),
                      (idx: number): void => {
                        this.settings.setFontScale(FONT_SCALES[idx]);
                      })
                  },
                })
              }
              .backgroundColor($r('app.color.card_bg'))
              .borderRadius(Dim.radiusL)
              .width('100%')
              .padding({ top: 6, bottom: 6 })

              // ---------- 对话 ----------
              this.sectionHeader('settingsGroupChat')
              Column() {
                SettingRow({
                  label: I18n.translate('thinkingSwitch'),
                  icon: $r('app.media.ic_public_favor'),
                  toggleOn: this.settings.thinking,
                  onToggle: (on: boolean): void => {
                    this.settings.setThinking(on);
                  },
                })
                Column() {
                  SettingRow({
                    label: I18n.translate('thinkingEffortLabel'),
                    icon: $r('app.media.ic_public_stopwatch'),
                    value: this.selectedLabel(EFFORT_KEYS, (): number => this.effortIdx()),
                    showArrow: true,
                    tappable: true,
                    onRowTap: (): void => {
                      this.openRadio('thinkingEffortLabel', EFFORT_KEYS, (): number => this.effortIdx(),
                        (idx: number): void => {
                          this.settings.setThinkingEffort(EFFORTS[idx]);
                        })
                    },
                  })
                }
                .width('100%')
                .opacity(this.settings.thinking ? 1 : 0.4)
                SettingRow({
                  label: I18n.translate('search'),
                  icon: $r('app.media.ic_public_search'),
                  toggleOn: this.settings.search,
                  onToggle: (on: boolean): void => {
                    this.settings.setSearch(on);
                  },
                })
                SettingRow({
                  label: I18n.translate('personalization'),
                  icon: $r('app.media.ic_public_emoji'),
                  value: this.settings.personalization === '' ? '' : I18n.translate('personalizationEnabled'),
                  showArrow: true,
                  tappable: true,
                  onRowTap: (): void => {
                    this.pathStack.pushPathByName('persona', null);
                  },
                })
              }
              .backgroundColor($r('app.color.card_bg'))
              .borderRadius(Dim.radiusL)
              .width('100%')
              .padding({ top: 6, bottom: 6 })

              // ---------- 语音 ----------
              this.sectionHeader('settingsGroupVoice')
              Column() {
                SettingRow({
                  label: I18n.translate('settingsTtsEnable'),
                  icon: $r('app.media.ic_public_ring'),
                  toggleOn: this.settings.ttsEnabled,
                  onToggle: (on: boolean): void => {
                    this.settings.setTtsEnabled(on);
                  },
                })
                SettingRow({
                  label: I18n.translate('settingsTtsVoice'),
                  icon: $r('app.media.ic_public_sound'),
                  value: this.voiceLabel(),
                  showArrow: true,
                  tappable: true,
                  onRowTap: (): void => {
                    this.openVoiceSheet();
                  },
                })
              }
              .backgroundColor($r('app.color.card_bg'))
              .borderRadius(Dim.radiusL)
              .width('100%')
              .padding({ top: 6, bottom: 6 })

              // ---------- 语言与地区 ----------
              this.sectionHeader('settingsGroupLocale')
              Column() {
                SettingRow({
                  label: I18n.translate('settingsLocalePreference'),
                  icon: $r('app.media.ic_public_translate'),
                  value: this.selectedLabel(LOCALE_KEYS, (): number => this.localeIdx()),
                  showArrow: true,
                  tappable: true,
                  onRowTap: (): void => {
                    this.openRadio('settingsLocalePreference', LOCALE_KEYS, (): number => this.localeIdx(),
                      (idx: number): void => {
                        this.settings.setLocale(idx === 0 ? 'zh-CN' : 'en-US');
                      }, $r('app.media.ic_public_translate'))
                  },
                })
                SettingRow({
                  label: I18n.translate('settingsLocation'),
                  icon: $r('app.media.ic_public_gps'),
                  value: this.locationLabel(),
                  showArrow: true,
                  tappable: true,
                  onRowTap: (): void => {
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
                  },
                })
              }
              .backgroundColor($r('app.color.card_bg'))
              .borderRadius(Dim.radiusL)
              .width('100%')
              .padding({ top: 6, bottom: 6 })

              // ---------- 通知 ----------
              this.sectionHeader('settingsGroupNotify')
              Column() {
                SettingRow({
                  label: I18n.translate('notifyOnReply'),
                  icon: $r('app.media.ic_public_ring'),
                  toggleOn: this.settings.notifyOnReply,
                  onToggle: (on: boolean): void => {
                    if (!on) {
                      this.settings.setNotifyOnReply(false);
                      return;
                    }
                    NotifyService.requestEnable().then((granted: boolean) => {
                      if (granted) {
                        this.settings.setNotifyOnReply(true);
                      } else {
                        this.getUIContext().getPromptAction()
                          .showToast({ message: I18n.translate('notifyPermissionDenied'), duration: Motion.toastLong });
                      }
                    }).catch(() => {});
                  },
                })
                SettingRow({
                  label: I18n.translate('liveViewOnReply'),
                  icon: $r('app.media.ic_public_clock'),
                  toggleOn: this.settings.liveViewOnReply,
                  onToggle: (on: boolean): void => {
                    this.settings.setLiveViewOnReply(on);
                    if (!on) {
                      LiveViewService.replyEnded().catch(() => {});
                    }
                  },
                })
              }
              .backgroundColor($r('app.color.card_bg'))
              .borderRadius(Dim.radiusL)
              .width('100%')
              .padding({ top: 6, bottom: 6 })

              // ---------- 数据 ----------
              this.sectionHeader('settingsGroupData')
              Column() {
                SettingRow({
                  label: I18n.translate('dataManage'),
                  icon: $r('app.media.ic_public_storage'),
                  showArrow: true,
                  tappable: true,
                  onRowTap: (): void => {
                    this.pathStack.pushPathByName('data', null);
                  },
                })
              }
              .backgroundColor($r('app.color.card_bg'))
              .borderRadius(Dim.radiusL)
              .width('100%')
              .padding({ top: 6, bottom: 6 })

              // ---------- 关于 ----------
              this.sectionHeader('about')
              Column() {
                SettingRow({
                  label: I18n.translate('version'),
                  icon: $r('app.media.ic_public_upgrade'),
                  value: '1.0.0',
                })
                SettingRow({
                  label: I18n.translate('userAgreementTitle'),
                  icon: $r('app.media.ic_public_text'),
                  showArrow: true,
                  tappable: true,
                  onRowTap: (): void => {
                    this.pathStack.pushPathByName('agreement', null);
                  },
                })
                SettingRow({
                  label: I18n.translate('privacyPolicyTitle'),
                  icon: $r('app.media.ic_public_privacy'),
                  showArrow: true,
                  tappable: true,
                  onRowTap: (): void => {
                    this.pathStack.pushPathByName('privacy', null);
                  },
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
            .padding({ left: this.contentPad, right: this.contentPad, top: 4 })
          }
          .layoutWeight(1)
          // 7.0.0.111 实机回归：constraintSize 出现在 NavDestination 子树会让后代节点挂载错乱
          // （图标/开关整体缺席），宽屏收窄改用自测宽 + 内容列动态水平 padding 实现
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
            .transition(TransitionEffect.OPACITY.animation({ duration: Motion.animFast, curve: Curve.Smooth }))
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
            .animation({ duration: Motion.animFast, curve: Curve.Smooth }))
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

  /** 位置行尾值 */
  private locationLabel(): string {
    const loc = this.settings.location;
    return loc === null || loc.province === null ? I18n.translate('settingsLocationNone') : loc.province;
  }

  /** 选项/信息/开关行统一由 SettingRow 子组件实现（共用 SettingRow.ets） */

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
    this.getUIContext().animateTo({ duration: Motion.animFast, curve: Curve.Smooth }, () => {
      this.dialogVisible = true;
    });
  }

  private applyDialog(): void {
    this.dialogOnSelect(this.dialogPending);
    this.closeDialog();
  }

  private closeDialog(): void {
    this.getUIContext().animateTo({ duration: Motion.animFast, curve: Curve.Smooth }, () => {
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
              colors: STELLA_GRADIENT,
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
              colors: TIDE_GRADIENT,
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
