import { Fonts } from '../../common/Fonts';
import { I18n } from '../../common/I18n';
import { Dim, Motion } from '../../common/DesignTokens';
import { ChatStore } from '../../service/chat/ChatStore';
import { HistoryArchive, ArchiveError } from '../../service/history/HistoryArchive';
import { AppContextHolder } from '../../common/AppContextHolder';
import { promptAction } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { picker } from '@kit.CoreFileKit';
import fs from '@ohos.file.fs';
import { Logger } from '../../common/Logger';
import { PageHeader } from './PageHeader';
import { SettingRow } from './SettingRow';

/**
 * 数据管理子页（仿官方）：每行独立白卡 + 大间距，无分组头、行不带图标；
 * 导入卡下方附灰色说明文字；删除行为红字独立卡。
 * 行统一用 SettingRow 子组件（carded 自带白卡底）：真机（平板）上 @Builder
 * 渲染的卡片文本/图标会被整体吞掉只剩 Blank，子组件无此问题。
 */

@ComponentV2
export struct DataManagePage {
  @Param pathStack: NavPathStack = new NavPathStack();
  store: ChatStore = ChatStore.get();

  /**
   * 宽屏内容收窄：不能用 constraintSize(maxWidth)——7.0.0.111 实机回归，
   * 它出现在 NavDestination 子树会让后代节点挂载错乱（图标/箭头整体缺席）。
   * 改为 Scroll 自测宽后对内容列动态加水平 padding（手机不受影响）。
   */
  @Local contentPad: number = Dim.pagePadding;

  build() {
    NavDestination() {
      Stack() {
        Column() {
          PageHeader({
            title: I18n.translate('dataManage'),
            onBack: (): void => {
              this.pathStack.pop();
            },
          })
          Scroll() {
          Column({ space: 20 }) {
            SettingRow({
              label: I18n.translate('usageStats'),
              carded: true,
              showArrow: true,
              tappable: true,
              onRowTap: (): void => {
                this.pathStack.pushPathByName('usage', null);
              },
            })
            Column({ space: 8 }) {
              SettingRow({
                label: I18n.translate('historyImport'),
                carded: true,
                tappable: true,
                onRowTap: (): void => {
                  this.confirmImport();
                },
              })
              Text(I18n.translate('historyImportDescription'))
                .fontSize(Fonts.caption())
                .fontColor($r('app.color.text_tertiary'))
                .width('100%')
                .padding({ left: 4, right: 4 })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            SettingRow({
              label: I18n.translate('exportAllLabel'),
              carded: true,
              tappable: true,
              onRowTap: (): void => {
                this.doExport();
              },
            })
            SettingRow({
              label: I18n.translate('deleteAllSessions'),
              carded: true,
              danger: true,
              tappable: true,
              onRowTap: (): void => {
                this.confirmDeleteAll();
              },
            })
          }
          .padding({ left: this.contentPad, right: this.contentPad, top: 8, bottom: 44 })
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
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .backgroundColor($r('app.color.settings_bg'))
    // 灰底延伸进手势条避让区，否则 Navigation 白底在页面底部露条
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  private confirmDeleteAll(): void {
    const buttons: Array<promptAction.Button> = [];
    const bCancel: promptAction.Button = { text: I18n.translate('cancel'), color: $r('app.color.dialog_btn_secondary') };
    const bDelete: promptAction.Button = { text: I18n.translate('delete'), color: $r('app.color.warning') };
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
          this.getUIContext().getPromptAction().showToast({ message: I18n.translate('historyDeleted'), duration: Motion.toastShort });
        }
      });
    } catch (err) {
      // 忽略
    }
  }

  /** 导入历史对话：选择 ZIP → 确认覆盖 → 解析替换 */
  private confirmImport(): void {
    const buttons: Array<promptAction.Button> = [];
    const bCancel: promptAction.Button = { text: I18n.translate('cancel'), color: $r('app.color.dialog_btn_secondary') };
    const bConfirm: promptAction.Button = { text: I18n.translate('historyImportConfirm'), color: $r('app.color.brand_activated') };
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
      // 大包（数百会话）解析需数十秒：先给进行中提示（时长超出常规 toast 分档，防中途消失）
      this.getUIContext().getPromptAction().showToast({ message: I18n.translate('historyImporting'), duration: 10000 });
      const count = await HistoryArchive.importZip(tmp);
      await this.store.reloadAfterImport();
      try {
        fs.unlinkSync(tmp);
      } catch (e) {
        // 忽略
      }
      this.getUIContext().getPromptAction().showToast({
        message: I18n.translate(count === 1 ? 'historyImportedOne' : 'historyImported', { 'count': `${count}` }),
        duration: Motion.toastMid,
      });
    } catch (err) {
      const key = err instanceof ArchiveError ? (err as ArchiveError).key : 'historyImportFailed';
      this.getUIContext().getPromptAction().showToast({ message: I18n.translate(key), duration: Motion.toastLong });
      const ibe = err as BusinessError;
      Logger.warn('DataManagePage', `import failed: code=${ibe.code} message=${ibe.message}`);
    }
  }

  /** 导出全部会话到用户选择的 ZIP */
  private async doExport(): Promise<void> {
    let produced: string | null = null;
    try {
      produced = await HistoryArchive.exportZip();
      // 另存为
      const docPicker = new picker.DocumentViewPicker();
      const saveOptions = new picker.DocumentSaveOptions();
      saveOptions.newFileNames = [HistoryArchive.baseName(produced)];
      const result = await docPicker.save(saveOptions);
      if (result.length > 0) {
        fs.copyFileSync(produced, result[0]);
        this.getUIContext().getPromptAction().showToast({ message: I18n.translate('historyExported'), duration: Motion.toastShort });
      }
    } catch (err) {
      const message = err instanceof Error ? (err as Error).message : `${err}`;
      this.getUIContext().getPromptAction().showToast({ message: I18n.translate('historyExportFailed', { 'message': message }), duration: Motion.toastLong });
      // BusinessError 的 code/message 非枚举属性，JSON.stringify 只会得到 {}——逐字段记录
      const be = err as BusinessError;
      Logger.warn('DataManagePage', `export failed: code=${be.code} message=${be.message}`);
    } finally {
      // 沙箱内产物用完即删（用户取消另存/拷贝失败也不残留，避免 filesDir 逐日累积）
      if (produced !== null) {
        try {
          fs.unlinkSync(produced);
        } catch (e) {
          // 已不存在属正常
        }
      }
    }
  }
}
