import { Fonts } from '../../common/Fonts';
import { I18n } from '../../common/I18n';
import { Dim, Motion } from '../../common/DesignTokens';
import { ChatStore } from '../../service/chat/ChatStore';
import { HistoryArchive, ArchiveError } from '../../service/history/HistoryArchive';
import { promptAction } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import fs from '@ohos.file.fs';
import { Logger } from '../../common/Logger';
import { PageHeader } from './PageHeader';

/**
 * 从 DeepSeek 官方导出链接导入：粘贴链接 → 识别官方域名 → 下载 ZIP → 覆盖导入。
 * 剪贴板静默读取需要 system_basic 级 READ_PASTEBOARD 权限（三方应用不可得），
 * 故采用粘贴输入框；extractExportUrl 支持从整段邮件文本中提取链接。
 */
@ComponentV2
export struct ImportLinkPage {
  @Param pathStack: NavPathStack = new NavPathStack();
  store: ChatStore = ChatStore.get();
  @Local linkInput: string = '';
  @Local recognizedLink: string = '';
  @Local busy: boolean = false;
  /** 进行中提示：'' | 'historyDownloading' | 'historyImporting' */
  @Local phase: string = '';

  /**
   * 宽屏内容收窄：不能用 constraintSize(maxWidth)——7.0.0.111 实机回归，
   * 它出现在 NavDestination 子树会让后代节点挂载错乱（图标/箭头整体缺席）。
   * 改为 Scroll 自测宽后对内容列动态加水平 padding（手机不受影响）。
   */
  @Local contentPad: number = Dim.pagePadding;

  build() {
    NavDestination() {
      Column() {
        PageHeader({
          title: I18n.translate('historyImportFromLink'),
          onBack: (): void => {
            this.pathStack.pop();
          },
        })
        Scroll() {
          Column({ space: 20 }) {
            Column({ space: 12 }) {
              Text(I18n.translate('historyImportLinkHint'))
                .fontSize(Fonts.body3())
                .fontColor($r('app.color.text_secondary'))
                .width('100%')
              TextInput({
                text: this.linkInput,
                placeholder: I18n.translate('historyImportLinkPlaceholder'),
              })
                .fontSize(Fonts.body2())
                .fontColor($r('app.color.text_primary'))
                .placeholderColor($r('app.color.text_tertiary'))
                .backgroundColor($r('app.color.text_field_sub_bg'))
                .borderRadius(Dim.radiusS)
                .width('100%')
                .enabled(!this.busy)
                .onChange((v: string) => {
                  this.linkInput = v;
                  this.recognizedLink = HistoryArchive.extractExportUrl(v) ?? '';
                })
              if (this.recognizedLink !== '') {
                Text(I18n.translate('historyImportLinkRecognized'))
                  .fontSize(Fonts.caption())
                  .fontColor($r('app.color.success'))
                  .width('100%')
              } else if (this.linkInput.trim() !== '') {
                Text(I18n.translate('historyImportLinkInvalid'))
                  .fontSize(Fonts.caption())
                  .fontColor($r('app.color.warning'))
                  .width('100%')
              }
              if (this.phase !== '') {
                Text(I18n.translate(this.phase))
                  .fontSize(Fonts.body3())
                  .fontColor($r('app.color.text_secondary'))
                  .width('100%')
              }
              Button(I18n.translate('historyImportLinkDownload'))
                .fontSize(Fonts.body2())
                .backgroundColor($r('app.color.brand'))
                .fontColor($r('app.color.text_primary_contrary'))
                .width('100%')
                .enabled(!this.busy && this.recognizedLink !== '')
                .onClick(() => {
                  this.confirmImport();
                })
            }
            .padding(16)
            .backgroundColor($r('app.color.card_bg'))
            .borderRadius(Dim.radiusM)
            .width('100%')

            Text(I18n.translate('historyImportLinkRowHint'))
              .fontSize(Fonts.caption())
              .fontColor($r('app.color.text_tertiary'))
              .width('100%')
              .padding({ left: 4, right: 4 })
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
    .hideTitleBar(true)
    .backgroundColor($r('app.color.settings_bg'))
    // 灰底延伸进手势条避让区，否则 Navigation 白底在页面底部露条
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  /** 下载前确认覆盖（与文件导入流程一致） */
  private confirmImport(): void {
    if (this.recognizedLink === '' || this.busy) {
      return;
    }
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
          this.runImport();
        }
      });
    } catch (err) {
      // 忽略
    }
  }

  private async runImport(): Promise<void> {
    const link = this.recognizedLink;
    if (link === '' || this.busy) {
      return;
    }
    this.busy = true;
    this.phase = 'historyDownloading';
    // 下载+导入均为整库替换：先中止在途回复，避免旧流继续写库
    this.store.abortStreaming();
    try {
      const zipPath = await HistoryArchive.downloadZip(link);
      this.phase = 'historyImporting';
      const count = await HistoryArchive.importZip(zipPath);
      await this.store.reloadAfterImport();
      try {
        fs.unlinkSync(zipPath);
      } catch (e) {
        // 忽略
      }
      this.getUIContext().getPromptAction().showToast({
        message: I18n.translate(count === 1 ? 'historyImportedOne' : 'historyImported', { 'count': `${count}` }),
        duration: Motion.toastMid,
      });
      this.pathStack.pop();
    } catch (err) {
      const key = err instanceof ArchiveError ? (err as ArchiveError).key : 'historyDownloadFailed';
      this.getUIContext().getPromptAction().showToast({ message: I18n.translate(key), duration: Motion.toastLong });
      const ibe = err as BusinessError;
      Logger.warn('ImportLinkPage', `import from link failed: code=${ibe.code} message=${ibe.message}`);
      this.busy = false;
      this.phase = '';
    }
  }
}
