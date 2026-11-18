import { Fonts } from '../../common/Fonts';
import { I18n } from '../../common/I18n';
import { Dim } from '../../common/DesignTokens';
import { SettingsStore } from '../../prefs/SettingsStore';
import { KeyVault } from '../../prefs/KeyVault';
import { ApiClient } from '../../service/api/ApiClient';
import { ApiError } from '../../service/api/ApiError';
import { AppContextHolder } from '../../common/AppContextHolder';
import { ThemeHelper } from '../../common/ThemeHelper';
import { ChatStore } from '../../service/chat/ChatStore';
import { HistoryArchive, ArchiveError } from '../../service/history/HistoryArchive';
import { NotifyService } from '../../service/notify/NotifyService';
import { LiveViewService } from '../../service/notify/LiveViewService';
import { UserLocation, ThemePreference, ThinkingEffort } from '../../model/SettingsTypes';
import { promptAction } from '@kit.ArkUI';
import { picker } from '@kit.CoreFileKit';
import fs from '@ohos.file.fs';
import { Logger } from '../../common/Logger';

/** 省份/地区（位置信息用于联网搜索本地化） */
const PROVINCES: string[] = [
  '北京', '天津', '河北', '山西', '内蒙古', '辽宁', '吉林', '黑龙江', '上海', '江苏',
  '浙江', '安徽', '福建', '江西', '山东', '河南', '湖北', '湖南', '广东', '广西',
  '海南', '重庆', '四川', '贵州', '云南', '西藏', '陕西', '甘肃', '青海', '宁夏', '新疆',
  '香港', '澳门', '台湾',
];

/** 完整设置页（List+SubHeader 鸿蒙布局） */
@ComponentV2
export struct SettingsPage {
  @Param pathStack: NavPathStack = new NavPathStack();
  settings: SettingsStore = SettingsStore.get();
  store: ChatStore = ChatStore.get();
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

  build() {
    NavDestination() {
      Stack() {
        Scroll() {
          Column({ space: 12 }) {
            // ---------- API Key ----------
            this.subHeader('apiKeyEdit')
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
            .padding(Dim.cardPadding)
            .backgroundColor($r('app.color.card_bg'))
            .borderRadius(Dim.radiusM)
            .width('100%')

            // ---------- 模型与服务 ----------
            this.subHeader('modelAndService')
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
                    .showToast({ message: I18n.translate('settingsSaved'), duration: 1500 });
                })

              Text(I18n.translate('customModelHint'))
                .fontSize(Fonts.caption())
                .fontColor($r('app.color.text_tertiary'))
                .width('100%')
            }
            .padding(Dim.cardPadding)
            .backgroundColor($r('app.color.card_bg'))
            .borderRadius(Dim.radiusM)
            .width('100%')

            // ---------- 外观 ----------
            this.subHeader('settingsGroupAppearance')
            Column() {
              this.selectRow('fontSizeLabel', ['fontOptSmall', 'fontOptStandard', 'fontOptLarge', 'fontOptXl'],
                (): number => {
                  const idx: string[] = ['small', 'standard', 'large', 'xl'];
                  return idx.indexOf(this.settings.fontScale);
                },
                (idx: number): void => {
                  const scales: string[] = ['small', 'standard', 'large', 'xl'];
                  this.settings.setFontScale(scales[idx]);
                })
              this.rowDivider()
              this.selectRow('fontFamilyLabel', ['fontOptDefault', 'fontOptSans', 'fontOptSerif', 'fontOptMono'],
                (): number => {
                  const fams: string[] = ['', 'sans-serif', 'serif', 'monospace'];
                  return fams.indexOf(this.settings.fontFamily);
                },
                (idx: number): void => {
                  const fams: string[] = ['', 'sans-serif', 'serif', 'monospace'];
                  this.settings.setFontFamily(fams[idx]);
                })
              this.rowDivider()
              this.selectRow('avatarMenuSettingsDialogThemeItemLabel',
                [
                  'avatarMenuSettingsDialogThemeSelectSystemOption',
                  'avatarMenuSettingsDialogThemeSelectLightOption',
                  'avatarMenuSettingsDialogThemeSelectDarkOption',
                ],
                (): number => this.settings.themePreference === 'system' ? 0
                  : (this.settings.themePreference === 'light' ? 1 : 2),
                (idx: number): void => {
                  const prefs: ThemePreference[] = ['system', 'light', 'dark'];
                  this.settings.setThemePreference(prefs[idx]);
                  this.applyTheme();
                })
            }
            .backgroundColor($r('app.color.card_bg'))
            .borderRadius(Dim.radiusM)
            .width('100%')

            // ---------- 对话 ----------
            this.subHeader('settingsGroupChat')
            Column() {
              this.actionRowWithState('personalization', (): string =>
                this.settings.personalization === '' ? '' : I18n.translate('personalizationEnabled'),
              (): void => {
                this.pathStack.pushPathByName('persona', null);
              })
              this.rowDivider()
              this.toggleRow('thinkingSwitch', (): boolean => this.settings.thinking, (on: boolean): void => {
                this.settings.setThinking(on);
              })
              this.rowDivider()
              Column() {
                this.selectRow('thinkingEffortLabel', ['thinkingEffortLow', 'thinkingEffortStandard', 'thinkingEffortMax'],
                  (): number => this.settings.thinkingEffort === 'low' ? 0
                    : (this.settings.thinkingEffort === 'high' ? 1 : 2),
                  (idx: number): void => {
                    const efforts: ThinkingEffort[] = ['low', 'high', 'max'];
                    this.settings.setThinkingEffort(efforts[idx]);
                  })
              }
              .opacity(this.settings.thinking ? 1 : 0.4)
              this.rowDivider()
              this.toggleRow('search', (): boolean => this.settings.search, (on: boolean): void => {
                this.settings.setSearch(on);
              })
              this.rowDivider()
              this.selectRow('settingsTtsVoice', ['settingsTtsVoiceStella', 'settingsTtsVoiceTide'],
                (): number => this.settings.ttsVoice === 'stella' ? 0 : 1,
                (idx: number): void => {
                  this.settings.setTtsVoice(idx === 0 ? 'stella' : 'tide');
                })
            }
            .backgroundColor($r('app.color.card_bg'))
            .borderRadius(Dim.radiusM)
            .width('100%')

            // ---------- 通知 ----------
            this.subHeader('settingsGroupNotify')
            Column() {
              this.toggleRow('notifyOnReply', (): boolean => this.settings.notifyOnReply, (on: boolean): void => {
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
              this.rowDivider()
              this.toggleRow('liveViewOnReply', (): boolean => this.settings.liveViewOnReply, (on: boolean): void => {
                this.settings.setLiveViewOnReply(on);
                if (!on) {
                  LiveViewService.replyEnded().catch(() => {});
                }
              })
            }
            .backgroundColor($r('app.color.card_bg'))
            .borderRadius(Dim.radiusM)
            .width('100%')

            // ---------- 语言与地区 ----------
            this.subHeader('settingsGroupLocale')
            Column() {
              this.selectRow('settingsLocalePreference', ['settingsLocaleZhCN', 'settingsLocaleEnUS'],
                (): number => this.settings.locale === 'zh-CN' ? 0 : 1,
                (idx: number): void => {
                  this.settings.setLocale(idx === 0 ? 'zh-CN' : 'en-US');
                })
              this.rowDivider()
              this.selectRow('settingsLocation', ['settingsLocationNone', ...PROVINCES],
                (): number => {
                  const loc = this.settings.location;
                  if (loc === null || loc.province === null) {
                    return 0;
                  }
                  const idx = PROVINCES.indexOf(loc.province);
                  return idx >= 0 ? idx + 1 : 0;
                },
                (idx: number): void => {
                  if (idx === 0) {
                    this.settings.setLocation(null);
                    return;
                  }
                  const loc = new UserLocation();
                  loc.region = 'CN';
                  loc.province = PROVINCES[idx - 1];
                  this.settings.setLocation(loc);
                })
            }
            .backgroundColor($r('app.color.card_bg'))
            .borderRadius(Dim.radiusM)
            .width('100%')

            // ---------- 数据 ----------
            this.subHeader('settingsGroupData')
            Column() {
              this.actionRow('usageStats', (): void => {
                this.pathStack.pushPathByName('usage', null);
              })
              this.rowDivider()
              this.actionRow('historyImport', (): void => {
                this.confirmImport();
              })
              this.rowDivider()
              this.actionRow('exportAllLabel', (): void => {
                this.doExport();
              })
              this.rowDivider()
              this.actionRowDanger('deleteAllSessions', (): void => {
                this.confirmDeleteAll();
              })
            }
            .backgroundColor($r('app.color.card_bg'))
            .borderRadius(Dim.radiusM)
            .width('100%')

            // ---------- 关于 ----------
            this.subHeader('about')

            Column({ space: 6 }) {
              Row() {
                Text(I18n.translate('version'))
                  .fontSize(Fonts.body1())
                  .fontColor($r('app.color.text_primary'))
                Blank()
                Text('1.0.0')
                  .fontSize(Fonts.body2())
                  .fontColor($r('app.color.text_secondary'))
              }
              .width('100%')

              Row() {
                Text(I18n.translate('modelLabel'))
                  .fontSize(Fonts.body1())
                  .fontColor($r('app.color.text_primary'))
                Blank()
                Text(this.settings.model)
                  .fontSize(Fonts.body2())
                  .fontColor($r('app.color.text_secondary'))
              }
              .width('100%')

              Row() {
                Text(I18n.translate('serverAddress'))
                  .fontSize(Fonts.body1())
                  .fontColor($r('app.color.text_primary'))
                Blank()
                Text(this.settings.apiOrigin)
                  .fontSize(Fonts.caption())
                  .fontColor($r('app.color.text_secondary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .constraintSize({ maxWidth: '55%' })
              }
              .width('100%')

              Text(I18n.translate('portingFrom'))
                .fontSize(Fonts.caption())
                .fontColor($r('app.color.text_tertiary'))
                .width('100%')
            }
            .padding(Dim.cardPadding)
            .backgroundColor($r('app.color.card_bg'))
            .borderRadius(Dim.radiusM)
            .width('100%')
          }
          .padding(Dim.pagePadding)
          .constraintSize({ maxWidth: Dim.contentMaxWidth })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.Top)
      }
      .width('100%')
      .height('100%')
    }
    .title(I18n.translate('settings'))
    .backgroundColor($r('app.color.app_bg'))
  }

  @Builder
  subHeader(titleKey: string) {
    Text(I18n.translate(titleKey))
      .fontSize(Fonts.body2())
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.text_tertiary'))
      .width('100%')
      .padding({ top: 8, left: 4 })
  }

  /**
   * 下拉选择行：label 用词条 key、选项数组与选中索引在 @Builder 体内求值，
   * 读取 @Trace（locale/设置项），语言与状态切换即时刷新（传值参数不响应更新）。
   */
  @Builder
  selectRow(labelKey: string, optionKeys: string[], selectedFn: () => number, onSelect: (idx: number) => void) {
    Row() {
      Text(I18n.translate(labelKey))
        .fontSize(Fonts.body1())
        .fontColor($r('app.color.text_primary'))
      Blank()
      Select(this.selectOptions(optionKeys))
        .selected(selectedFn())
        .font({ size: Fonts.body2() })
        .onSelect((idx: number, _value: string) => {
          onSelect(idx);
        })
    }
    .width('100%')
    .height(Dim.listRowHeight)
    .padding({ left: Dim.cardPadding, right: Dim.cardPadding })
  }

  /** 开关行（鸿蒙 Toggle 开关） */
  @Builder
  toggleRow(labelKey: string, isOnFn: () => boolean, onChange: (on: boolean) => void) {
    Row() {
      Text(I18n.translate(labelKey))
        .fontSize(Fonts.body1())
        .fontColor($r('app.color.text_primary'))
      Blank()
      Toggle({ type: ToggleType.Switch, isOn: isOnFn() })
        .onChange((on: boolean) => {
          onChange(on);
        })
    }
    .width('100%')
    .height(Dim.listRowHeight)
    .padding({ left: Dim.cardPadding, right: Dim.cardPadding })
  }

  /** 动作行（整行点击，右侧可选状态值） */
  @Builder
  actionRowWithState(labelKey: string, valueFn: () => string, onTap: () => void) {
    Row() {
      Text(I18n.translate(labelKey))
        .fontSize(Fonts.body1())
        .fontColor($r('app.color.text_primary'))
      Blank()
      Text(valueFn())
        .fontSize(Fonts.body2())
        .fontColor(valueFn() === '' ? $r('app.color.text_tertiary') : $r('app.color.brand_activated'))
    }
    .width('100%')
    .height(Dim.listRowHeight)
    .padding({ left: Dim.cardPadding, right: Dim.cardPadding })
    .onClick(() => {
      onTap();
    })
  }

  /** 危险动作行（红色标签，如删除） */
  @Builder
  actionRowDanger(labelKey: string, onTap: () => void) {
    Row() {
      Text(I18n.translate(labelKey))
        .fontSize($r('app.float.font_body1'))
        .fontColor($r('app.color.warning'))
    }
    .width('100%')
    .height(Dim.listRowHeight)
    .padding({ left: Dim.cardPadding, right: Dim.cardPadding })
    .onClick(() => {
      onTap();
    })
  }

  /** 组内行分隔线（左右缩进） */
  @Builder
  rowDivider() {
    Divider()
      .color($r('app.color.list_separator'))
      .strokeWidth(Dim.separator)
      .margin({ left: Dim.cardPadding, right: Dim.cardPadding })
  }

  /** 动作行（整行点击） */
  @Builder
  actionRow(labelKey: string, onTap: () => void) {
    Row() {
      Text(I18n.translate(labelKey))
        .fontSize(Fonts.body1())
        .fontColor($r('app.color.text_primary'))
    }
    .width('100%')
    .height(Dim.listRowHeight)
    .padding({ left: Dim.cardPadding, right: Dim.cardPadding })
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(Dim.radiusM)
    .onClick(() => {
      onTap();
    })
  }

  /** 词条 key → Select 选项（体内调用以保持 locale 响应式） */
  private selectOptions(optionKeys: string[]): SelectOption[] {
    const arr: SelectOption[] = [];
    for (const k of optionKeys) {
      const o: SelectOption = { value: I18n.translate(k) };
      arr.push(o);
    }
    return arr;
  }

  private applyTheme(): void {
    ThemeHelper.apply(AppContextHolder.get(), this.settings.themePreference);
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
        this.getUIContext().getPromptAction().showToast({ message: I18n.translate('apiKeyStart'), duration: 1500 });
      });
    }).catch((err: ApiError) => {
      this.verifyState = 'fail';
      this.verifyMsg = I18n.translate(ApiError.i18nKeyFor(err));
      Logger.warn('SettingsPage', `verify failed: ${err.message}`);
    });
  }

  private confirmDeleteAll(): void {
    const buttons: Array<promptAction.Button> = [];
    const bCancel: promptAction.Button = { text: I18n.translate('cancel'), color: '#66000000' };
    const bDelete: promptAction.Button = { text: I18n.translate('delete'), color: '#E84026' };
    buttons.push(bCancel);
    buttons.push(bDelete);
    const options: promptAction.ShowDialogOptions = {
      title: I18n.translate('deleteAllSessionsModalTitle'),
      message: I18n.translate('deleteAllSessionsModalDescription'),
      buttons: buttons,
      alignment: DialogAlignment.Center,
    };
    try {
      this.getUIContext().getPromptAction().showDialog(options).then((result) => {
        if (result.index === 1) {
          this.store.deleteAll();
          this.getUIContext().getPromptAction().showToast({ message: I18n.translate('historyDeleted'), duration: 1500 });
        }
      });
    } catch (err) {
      // 忽略
    }
  }

  /** 导入历史对话：选择 ZIP → 确认覆盖 → 解析替换 */
  private confirmImport(): void {
    const buttons: Array<promptAction.Button> = [];
    const bCancel: promptAction.Button = { text: I18n.translate('cancel'), color: '#66000000' };
    const bConfirm: promptAction.Button = { text: I18n.translate('historyImportConfirm'), color: '#0A59F7' };
    buttons.push(bCancel);
    buttons.push(bConfirm);
    const options: promptAction.ShowDialogOptions = {
      title: I18n.translate('historyImportConfirmTitle'),
      message: I18n.translate('historyImportConfirmDescription'),
      buttons: buttons,
      alignment: DialogAlignment.Center,
    };
    try {
      this.getUIContext().getPromptAction().showDialog(options).then((result) => {
        if (result.index === 1) {
          this.pickAndImport();
        }
      });
    } catch (err) {
      // 忽略
    }
  }

  private async pickAndImport(): Promise<void> {
    try {
      const docPicker = new picker.DocumentViewPicker();
      const selectOptions = new picker.DocumentSelectOptions();
      selectOptions.fileSuffixFilters = ['.zip'];
      const uris = await docPicker.select(selectOptions);
      if (uris.length === 0) {
        return;
      }
      const context = AppContextHolder.get();
      const tmp = `${context.cacheDir}/import_${Date.now()}.zip`;
      fs.copyFileSync(uris[0], tmp);
      const count = await HistoryArchive.importZip(tmp);
      await this.store.reloadAfterImport();
      try {
        fs.unlinkSync(tmp);
      } catch (e) {
        // 忽略
      }
      this.getUIContext().getPromptAction().showToast({
        message: I18n.translate(count === 1 ? 'historyImportedOne' : 'historyImported', { 'count': `${count}` }),
        duration: 2000,
      });
    } catch (err) {
      const key = err instanceof ArchiveError ? (err as ArchiveError).key : 'historyImportFailed';
      this.getUIContext().getPromptAction().showToast({ message: I18n.translate(key), duration: 2500 });
      Logger.warn('SettingsPage', `import failed: ${JSON.stringify(err)}`);
    }
  }

  /** 导出全部会话到用户选择的 ZIP */
  private async doExport(): Promise<void> {
    try {
      const produced = await HistoryArchive.exportZip();
      // 另存为
      const docPicker = new picker.DocumentViewPicker();
      const saveOptions = new picker.DocumentSaveOptions();
      saveOptions.newFileNames = [HistoryArchive.baseName(produced)];
      const result = await docPicker.save(saveOptions);
      if (result.length > 0) {
        fs.copyFileSync(produced, result[0]);
        this.getUIContext().getPromptAction().showToast({ message: I18n.translate('historyExported'), duration: 1500 });
      }
    } catch (err) {
      const message = err instanceof Error ? (err as Error).message : `${JSON.stringify(err)}`;
      this.getUIContext().getPromptAction().showToast({ message: I18n.translate('historyExportFailed', { 'message': message }), duration: 2500 });
      Logger.warn('SettingsPage', `export failed: ${JSON.stringify(err)}`);
    }
  }
}
