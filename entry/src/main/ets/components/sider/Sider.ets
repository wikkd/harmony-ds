import { Fonts } from '../../common/Fonts';
import { I18n } from '../../common/I18n';
import { Dim } from '../../common/DesignTokens';
import { ChatStore } from '../../service/chat/ChatStore';
import { MarkdownExport } from '../../service/history/MarkdownExport';
import { Session } from '../../model/ChatTypes';
import { promptAction } from '@kit.ArkUI';

/**
 * 会话侧栏（鸿蒙 SideBarContainer 内容）：新对话 + 时间分组会话列表 + 重命名/删除。
 * 窄屏在抽屉中展示，宽屏常驻（Index 控制）。
 */
@ComponentV2
export struct Sider {
  store: ChatStore = ChatStore.get();
  @Param onSessionSelected: () => void = () => {};
  @Local renamingId: string = '';
  @Local renameText: string = '';
  @Local showRenameSheet: boolean = false;

  build() {
    Stack() {
      Column() {
        // 新对话
        Row({ space: 10 }) {
          Image($r('app.media.ic_public_add'))
            .width(20)
            .height(20)
            .fillColor($r('app.color.text_primary'))
          Text(I18n.translate('newChat'))
            .fontSize(Fonts.body1())
            .fontColor($r('app.color.text_primary'))
          Blank()
        }
        .width('100%')
        .height(44)
        .borderRadius(Dim.radiusM)
        .padding({ left: 12 })
        .backgroundColor($r('app.color.component_normal'))
        .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
        .onClick(() => {
          this.store.newSession();
          this.onSessionSelected();
        })

        // 分组列表
        List({ space: 2 }) {
          ForEach(this.groups(), (g: SiderGroup) => {
            ListItem() {
              Text(g.label)
                .fontSize(Fonts.body3())
                .fontColor($r('app.color.text_tertiary'))
                .width('100%')
                .padding({ left: 12, top: 14, bottom: 6 })
            }
            ForEach(g.items, (s: Session) => {
              ListItem() {
                Row() {
                  Text(this.store.displayTitle(s))
                    .fontSize(Fonts.body2())
                    .fontColor(s.id === this.store.currentSessionId ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .layoutWeight(1)
                  Image($r('app.media.ic_public_more'))
                    .width(18)
                    .height(18)
                    .fillColor($r('app.color.text_tertiary'))
                    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.85 })
                    .bindMenu(this.sessionMenu(s))
                }
                .width('100%')
                .height(44)
                .borderRadius(Dim.radiusM)
                .padding({ left: 12, right: 8 })
                .backgroundColor(s.id === this.store.currentSessionId ? $r('app.color.thinking_bg') : Color.Transparent)
                .onClick(() => {
                  this.store.switchTo(s.id);
                  this.onSessionSelected();
                })
              }
            }, (s: Session) => s.id + '_' + s.updatedAt)
          }, (g: SiderGroup) => g.label)
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('100%')
      .padding(8)
    }
    .width('100%')
    .height('100%')
    // 重命名：半模态面板（鸿蒙习惯，替代自绘遮罩弹层）
    .bindSheet(!!this.showRenameSheet, this.renameSheet(), {
      height: 300,
      dragBar: true,
      backgroundColor: Color.Transparent,
    })
  }

  /** 重命名半模态面板内容 */
  @Builder
  renameSheet() {
    Column({ space: 16 }) {
      Text(I18n.translate('sessionItemMenuRenameOption'))
        .fontSize(Fonts.headline9())
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      TextInput({
        text: this.renameText,
        placeholder: I18n.translate('untitledChat'),
      })
        .fontSize(Fonts.body1())
        .fontColor($r('app.color.text_primary'))
        .backgroundColor($r('app.color.text_field_sub_bg'))
        .borderRadius(Dim.radiusS)
        .onChange((v: string) => {
          this.renameText = v;
        })
      Row({ space: 12 }) {
        Button(I18n.translate('cancel'))
          .fontSize(Fonts.body2())
          .backgroundColor($r('app.color.component_normal'))
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .onClick(() => {
            this.showRenameSheet = false;
          })
        Button(I18n.translate('confirm'))
          .fontSize(Fonts.body2())
          .backgroundColor($r('app.color.brand'))
          .fontColor($r('app.color.text_primary_contrary'))
          .layoutWeight(1)
          .onClick(() => {
            this.store.renameSession(this.renamingId, this.renameText);
            this.showRenameSheet = false;
          })
      }
      .width('100%')
    }
    .padding({ left: 24, right: 24, top: 8, bottom: 24 })
    .width('100%')
    .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
    .backgroundColor($r('app.color.blur_dialog'))
  }

  private groups(): SiderGroup[] {
    const now = Date.now();
    const dayMs = 24 * 3600 * 1000;
    const startOfToday = new Date(new Date().getFullYear(), new Date().getMonth(), new Date().getDate()).getTime();
    const groups: SiderGroup[] = [
      new SiderGroup(I18n.translate('sessionHistoryTimelineLabelToday')),
      new SiderGroup(I18n.translate('sessionHistoryTimelineLabelYesterday')),
      new SiderGroup(I18n.translate('sessionHistoryTimelineLabel7days')),
      new SiderGroup(I18n.translate('sessionHistoryTimelineLabel30days')),
      new SiderGroup('···'),
    ];
    for (const s of this.store.sessions) {
      let g = groups[4];
      if (s.updatedAt >= startOfToday) {
        g = groups[0];
      } else if (s.updatedAt >= startOfToday - dayMs) {
        g = groups[1];
      } else if (s.updatedAt >= startOfToday - 7 * dayMs) {
        g = groups[2];
      } else if (s.updatedAt >= startOfToday - 30 * dayMs) {
        g = groups[3];
      }
      g.items.push(s);
    }
    return groups.filter((g) => g.items.length > 0);
  }

  /** 会话 ⋯ 菜单（鸿蒙 bindMenu，替代网页式按钮对话框） */
  private sessionMenu(s: Session): MenuElement[] {
    const rename: MenuElement = {
      value: I18n.translate('sessionItemMenuRenameOption'),
      icon: $r('app.media.ic_public_edit'),
      action: () => {
        this.openRename(s);
      },
    };
    const del: MenuElement = {
      value: I18n.translate('delete'),
      icon: $r('app.media.ic_public_delete'),
      action: () => {
        this.confirmDelete(s);
      },
    };
    const exportMd: MenuElement = {
      value: I18n.translate('exportMd'),
      icon: $r('app.media.ic_public_share'),
      action: () => {
        MarkdownExport.exportSession(s.id).then((ok: boolean) => {
          if (ok) {
            this.getUIContext().getPromptAction()
              .showToast({ message: I18n.translate('exportMdDone'), duration: 1500 });
          }
        }).catch(() => {
          this.getUIContext().getPromptAction()
            .showToast({ message: I18n.translate('exportMdFailed'), duration: 2000 });
        });
      },
    };
    const menu: MenuElement[] = [];
    menu.push(rename);
    menu.push(exportMd);
    menu.push(del);
    return menu;
  }

  private openRename(s: Session): void {
    this.renameText = this.store.displayTitle(s);
    this.renamingId = s.id;
    this.showRenameSheet = true;
  }

  private confirmDelete(s: Session): void {
    const buttons: Array<promptAction.Button> = [];
    const bCancel: promptAction.Button = { text: I18n.translate('cancel'), color: '#66000000' };
    const bDelete: promptAction.Button = { text: I18n.translate('delete'), color: '#E84026' };
    buttons.push(bCancel);
    buttons.push(bDelete);
    const options: promptAction.ShowDialogOptions = {
      title: I18n.translate('deleteSessionModalContentTitle'),
      message: I18n.translate('deleteSessionWithFilesDescription'),
      buttons: buttons,
      alignment: DialogAlignment.Center,
    };
    try {
      this.getUIContext().getPromptAction().showDialog(options).then((result) => {
        if (result.index === 1) {
          this.store.deleteSession(s.id);
        }
      });
    } catch (err) {
      // 忽略
    }
  }
}

class SiderGroup {
  label: string;
  items: Session[] = [];

  constructor(label: string) {
    this.label = label;
  }
}
