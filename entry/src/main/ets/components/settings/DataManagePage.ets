import { Fonts } from '../../common/Fonts';
import { I18n } from '../../common/I18n';
import { Dim } from '../../common/DesignTokens';
import { ChatStore } from '../../service/chat/ChatStore';
import { HistoryArchive, ArchiveError } from '../../service/history/HistoryArchive';
import { AppContextHolder } from '../../common/AppContextHolder';
import { promptAction } from '@kit.ArkUI';
import { picker } from '@kit.CoreFileKit';
import fs from '@ohos.file.fs';
import { Logger } from '../../common/Logger';
import { PageHeader } from './PageHeader';

/**
 * 数据管理子页（仿官方）：每行独立白卡 + 大间距，无分组头、行不带图标；
 * 导入卡下方附灰色说明文字；删除行为红字独立卡。
 */
@ComponentV2
export struct DataManagePage {
  @Param pathStack: NavPathStack = new NavPathStack();
  store: ChatStore = ChatStore.get();

  build() {
    NavDestination() {
      Column() {
        PageHeader({
          title: I18n.translate('dataManage'),
          onBack: (): void => {
            this.pathStack.pop();
          },
        })
        Scroll() {
          Column({ space: 20 }) {
            this.actionCard('usageStats', (): void => {
              this.pathStack.pushPathByName('usage', null);
            })
            Column({ space: 8 }) {
              this.actionCard('historyImport', (): void => {
                this.confirmImport();
              })
              Text(I18n.translate('historyImportDescription'))
                .fontSize(Fonts.caption())
                .fontColor($r('app.color.text_tertiary'))
                .width('100%')
                .padding({ left: 4, right: 4 })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            this.actionCard('exportAllLabel', (): void => {
              this.doExport();
            })
            this.dangerCard('deleteAllSessions', (): void => {
              this.confirmDeleteAll();
            })
          }
          .padding({ left: Dim.pagePadding, right: Dim.pagePadding, top: 8, bottom: 44 })
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
      .backgroundColor($r('app.color.settings_bg'))
      .alignItems(HorizontalAlign.Center)
    }
    .hideTitleBar(true)
    .backgroundColor($r('app.color.settings_bg'))
    // 灰底延伸进手势条避让区，否则 Navigation 白底在页面底部露条
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  /** 独立动作卡：标题 + 箭头 */
  @Builder
  actionCard(labelKey: string, onTap: () => void) {
    Row() {
      Text(I18n.translate(labelKey))
        .fontSize(Fonts.body1())
        .fontColor($r('app.color.text_primary'))
      Blank()
      Image($r('app.media.ic_public_arrow_right'))
        .width(16)
        .height(16)
        .fillColor($r('app.color.text_tertiary'))
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 16 })
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(Dim.radiusL)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.98 })
    .onClick(() => {
      onTap();
    })
  }

  /** 独立危险卡：红字无箭头 */
  @Builder
  dangerCard(labelKey: string, onTap: () => void) {
    Row() {
      Text(I18n.translate(labelKey))
        .fontSize(Fonts.body1())
        .fontColor($r('app.color.warning'))
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 16 })
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(Dim.radiusL)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.98 })
    .onClick(() => {
      onTap();
    })
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
      // 导入会整库替换：先中止在途回复，避免旧流继续写库
      this.store.abortStreaming();
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
      Logger.warn('DataManagePage', `import failed: ${JSON.stringify(err)}`);
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
      Logger.warn('DataManagePage', `export failed: ${JSON.stringify(err)}`);
    }
  }
}
