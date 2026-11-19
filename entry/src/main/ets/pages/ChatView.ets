import { Fonts } from '../common/Fonts';
import { I18n } from '../common/I18n';
import { SettingsStore } from '../prefs/SettingsStore';
import { Dim, Motion } from '../common/DesignTokens';
import { MessageList } from '../components/messages/MessageList';
import { ChatInput } from '../components/chatinput/ChatInput';
import { ChatStore } from '../service/chat/ChatStore';
import { ReplyEngine } from '../service/chat/ReplyEngine';
import { UserMessage, FileAttachment, AssistantMessage, isAssistant } from '../model/ChatTypes';
import { ModelInfo } from '../model/ModelInfo';
import { Id } from '../common/Format';
import { AttachmentService, AttachPickResult } from '../service/attachments/AttachmentService';

/** 会话主视图（V2）：欢迎态 / 可见链消息列表 + 受控输入 */
@ComponentV2
export struct ChatView {
  store: ChatStore = ChatStore.get();
  settings: SettingsStore = SettingsStore.get();
  @Local draft: string = '';
  @Local editingId: string = '';
  @Local draftFiles: FileAttachment[] = [];
  /** 排队消息：流式期间发送自动入队，回复结束按序自动发出 */
  @Local queue: QueuedSend[] = [];
  /** 输入面板实际高度（vp）：列表底部留白按它动态计算，不再写死 */
  @Local dockH: number = 170;
  /** 「立即」待发项：停止当前流后优先发出 */
  private immediatePending: QueuedSend | null = null;
  @Param onNeedKey: () => void = () => {};
  /** 手势条高度（vp）：输入区底部避让 */
  @Param safeBottom: number = 0;

  aboutToAppear(): void {
    this.store.onStreamingEnd = (): void => this.drainOnStreamEnd();
  }

  aboutToDisappear(): void {
    if (this.store.onStreamingEnd === this.drainOnStreamEnd) {
      this.store.onStreamingEnd = null;
    }
  }

  private drainOnStreamEnd(): void {
    if (this.immediatePending !== null) {
      const item = this.immediatePending;
      this.immediatePending = null;
      this.sendNow(item);
      return;
    }
    if (this.queue.length === 0) {
      return;
    }
    const head = this.queue[0];
    this.queue.splice(0, 1);
    this.sendNow(head);
  }

  private sendNow(item: QueuedSend): void {
    const files = this.settings.customModel ? [] : item.files;
    ReplyEngine.send(this.store.currentSessionId, item.text, files);
  }

  /** 「立即」：出队 → 停止当前流，由 onStreamingEnd 统一优先发出（避免与回调竞态） */
  private sendQueuedNow(item: QueuedSend): void {
    const idx = this.queue.indexOf(item);
    if (idx >= 0) {
      this.queue.splice(idx, 1);
    }
    const streamingId = this.store.streamingSessionId;
    if (streamingId !== null) {
      this.immediatePending = item;
      ReplyEngine.stop(streamingId);
      return;
    }
    this.sendNow(item);
  }

  private removeQueued(item: QueuedSend): void {
    const idx = this.queue.indexOf(item);
    if (idx >= 0) {
      this.queue.splice(idx, 1);
    }
  }

  /** 可见链 usage 统计（@Computed：依赖 @Trace 自动重算） */
  @Computed
  get stat(): ContextStat {
    const stat = new ContextStat();
    for (const m of this.store.visible) {
      if (!isAssistant(m)) {
        continue;
      }
      const a = m as AssistantMessage;
      if (a.usage === null) {
        continue;
      }
      const u = a.usage;
      const inputSide = u.inputTokens + u.cacheReadInputTokens + u.cacheCreationInputTokens;
      stat.sessionInput += inputSide;
      stat.sessionOutput += u.outputTokens;
      stat.lastOutput = u.outputTokens;
      stat.used = inputSide + u.outputTokens;
    }
    return stat;
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 消息区：列表/欢迎页占满，提示语在底部输入面板下方
      Column() {
        if (this.store.visible.length === 0) {
          Column() {
            Blank()
            // 秩序感编排：图标→标语错峰入场（官方「成组元素有节奏的时间差」）
            Image($r('app.media.ic_public_message_filled'))
              .width(56)
              .height(56)
              .fillColor($r('app.color.brand'))
              .margin({ bottom: 20 })
              .transition(TransitionEffect.OPACITY.combine(TransitionEffect.scale({ x: 0.9, y: 0.9 }))
                .animation({ duration: Motion.animBase, curve: Motion.curveIn }))
            Text(I18n.translate('welcomeMessageChat250808'))
              .fontSize(Fonts.headline6())
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .textAlign(TextAlign.Center)
              .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 10 }))
                .animation({ duration: Motion.animBase, curve: Motion.curveIn, delay: 80 }))
            Blank()
          }
          .constraintSize({ maxWidth: Dim.contentMaxWidth })
          .width('100%')
          .layoutWeight(1)
          .padding({ bottom: 190 })
        } else {
          MessageList({
            session: this.store.current(),
            visible: this.store.visible,
            editingId: this.editingId,
            bottomPad: this.dockH + 10,
            onEdit: (m: UserMessage) => {
              this.editingId = m.id;
              this.draft = m.content;
            },
          })
          .width('100%')
          .layoutWeight(1)
        }
      }
      .width('100%')
      .height('100%')

      Column() {
        if (this.queue.length > 0) {
          Column({ space: 6 }) {
            ForEach(this.queue, (q: QueuedSend) => {
              Row({ space: 8 }) {
                Image($r('app.media.ic_public_message_filled'))
                  .width(14)
                  .height(14)
                  .fillColor($r('app.color.text_tertiary'))
                Text(q.text)
                  .fontSize(Fonts.body3())
                  .fontColor($r('app.color.text_secondary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
                if (q.files.length > 0) {
                  Text(`+${q.files.length}`)
                    .fontSize(Fonts.caption())
                    .fontColor($r('app.color.text_tertiary'))
                }
                Text(I18n.translate('sendNow'))
                  .fontSize(Fonts.body3())
                  .fontColor($r('app.color.brand_activated'))
                  .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.9 })
                  .onClick(() => {
                    this.sendQueuedNow(q);
                  })
                Image($r('app.media.ic_public_close'))
                  .width(14)
                  .height(14)
                  .fillColor($r('app.color.text_tertiary'))
                  .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.85 })
                  .onClick(() => {
                    this.removeQueued(q);
                  })
              }
              .width('100%')
              .height(36)
              .padding({ left: 12, right: 12 })
              .backgroundColor($r('app.color.component_normal'))
              .borderRadius(Dim.radiusM)
              // 队列条进出场：弹簧（可打断）
              .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 8 }))
                .animation({ curve: Motion.spring }))
            }, (q: QueuedSend) => q.id)
          }
          .width('100%')
          .padding({ left: Dim.pagePadding, right: Dim.pagePadding, bottom: 4 })
        }

      // 面板水平留白由父容器承担（子组件 width('100%') + margin 不生效）
      Column() {
      ChatInput({
        text: this.draft,
        streaming: this.store.streamingSessionId !== null,
        editing: this.editingId !== '',
        files: this.draftFiles,
        contextUsed: this.stat.used,
        contextLimit: ModelInfo.CONTEXT_LIMIT,
        lastOutputTokens: this.stat.lastOutput,
        sessionInputTokens: this.stat.sessionInput,
        sessionOutputTokens: this.stat.sessionOutput,
        onTextChange: (v: string) => {
          this.draft = v;
        },
        onSend: (text: string) => {
          this.dispatchSend(text);
        },
        onCancelEdit: () => {
          this.editingId = '';
          this.draft = '';
        },
        onStop: () => {
          ReplyEngine.stop(this.store.currentSessionId);
        },
        onNeedKey: (): void => {
          this.onNeedKey();
        },
        onCompact: (): void => {
          this.doCompact();
        },
        onCapture: (): void => {
          this.attachFiles(AttachmentService.capture(this.draftFiles.length));
        },
        onPickPhotos: (): void => {
          this.attachFiles(AttachmentService.pickPhotos(this.draftFiles.length));
        },
        onPickDocs: (): void => {
          this.attachFiles(AttachmentService.pickDocs(this.draftFiles.length));
        },
        onRemoveFile: (f: FileAttachment) => {
          const idx = this.draftFiles.indexOf(f);
          if (idx >= 0) {
            this.draftFiles.splice(idx, 1);
          }
        },
      })
      }
      .padding({ left: Dim.pagePadding, right: Dim.pagePadding })
      .width('100%')

      // AI 生成提示：对话框下方、导航条（手势条）上方
      if (this.store.visible.length > 0) {
        Text(I18n.translate('contentCaveat'))
          .fontSize(Fonts.caption())
          .fontColor($r('app.color.text_tertiary'))
          .textAlign(TextAlign.Center)
          .width('100%')
          .margin({ top: 2 })
      }
      }
      .width('100%')
      // 手势条为半透明浮层，底部少避让 20vp 让输入面板贴近屏幕底（对齐官方观感）
      .padding({ bottom: Math.max(this.safeBottom - 20, 8) })
      .onAreaChange((_o: Area, nv: Area) => {
        this.dockH = Number(nv.height);
      })
    }
    .constraintSize({ maxWidth: Dim.contentMaxWidth + 32 })
    .width('100%')
    .height('100%')
    .alignSelf(ItemAlign.Center)
  }

  /** 压缩会话：摘要请求 → 写入会话 → 提示结果 */
  private doCompact(): void {
    if (this.store.streamingSessionId !== null) {
      return;
    }
    // 空会话没有可压缩的上下文：直接拒绝，不发摘要请求
    if (this.store.visible.length === 0) {
      this.getUIContext().getPromptAction()
        .showToast({ message: I18n.translate('compactEmpty'), duration: Motion.toastMid });
      return;
    }
    // 低上下文压缩无意义：摘要丢细节还白耗一次请求，占用达到阈值才允许
    const minTokens = ModelInfo.CONTEXT_LIMIT * ModelInfo.COMPACT_MIN_RATIO;
    if (this.stat.used < minTokens) {
      const percent = `${Math.round(ModelInfo.COMPACT_MIN_RATIO * 100)}%`;
      this.getUIContext().getPromptAction()
        .showToast({ message: I18n.translate('compactLowContext', { 'percent': percent }), duration: Motion.toastMid });
      return;
    }
    this.getUIContext().getPromptAction()
      .showToast({ message: I18n.translate('compactRunning'), duration: Motion.toastMax });
    ReplyEngine.compact(this.store.currentSessionId).then((r: string) => {
      const key = r === 'ok' ? 'compactDone' : (r === 'busy' ? 'compactBusy' : 'compactTooShort');
      this.getUIContext().getPromptAction().showToast({ message: I18n.translate(key), duration: Motion.toastMid });
    }).catch(() => {
      this.getUIContext().getPromptAction()
        .showToast({ message: I18n.translate('compactFailed'), duration: Motion.toastLong });
    });
  }

  /** 附件选择结果并入草稿；被拒文件给提示（类型/大小），不再静默吞掉 */
  private attachFiles(pending: Promise<AttachPickResult>): void {
    pending.then((picked: AttachPickResult) => {
      for (const f of picked.files) {
        this.draftFiles.push(f);
      }
      if (picked.rejectedKey !== '') {
        this.getUIContext().getPromptAction().showToast({
          message: I18n.translate(picked.rejectedKey, {
            'name': picked.rejectedName,
            'limit': `${picked.rejectedLimit}`,
          }),
          duration: Motion.toastMid,
        });
      }
    }).catch(() => {});
  }

  private dispatchSend(text: string): void {
    // 斜杠命令：/compact 与 /压缩（会话）等价，触发会话压缩而非发送
    const trimmed = text.trim();
    const cmd = trimmed.toLowerCase();
    if (cmd === '/compact' || trimmed === '/压缩' || trimmed === '/压缩会话') {
      this.editingId = '';
      this.draft = '';
      this.draftFiles = [];
      this.doCompact();
      return;
    }
    // 流式期间：入队（回复结束后自动按序发出）
    if (this.store.streamingSessionId !== null) {
      const q = new QueuedSend();
      q.id = Id.next();
      q.text = trimmed;
      q.files = this.settings.customModel ? [] : this.draftFiles;
      this.queue.push(q);
      this.draft = '';
      this.draftFiles = [];
      this.editingId = '';
      this.getUIContext().getPromptAction()
        .showToast({ message: I18n.translate('messageQueued'), duration: Motion.toastMid });
      return;
    }
    let files = this.draftFiles;
    if (this.settings.customModel) {
      files = [];
    }
    this.draftFiles = [];
    // 上下文将满：弹窗询问是否先压缩再发送（编辑重发同样适用）
    if (ModelInfo.isContextFull(this.stat.used)) {
      const editingId = this.editingId;
      this.editingId = '';
      this.draft = '';
      this.confirmCompactThenSend(text, files, editingId);
      return;
    }
    if (this.editingId !== '') {
      const id = this.editingId;
      this.editingId = '';
      this.draft = '';
      ReplyEngine.sendEdited(this.store.currentSessionId, id, text, files);
    } else {
      this.draft = '';
      ReplyEngine.send(this.store.currentSessionId, text, files);
    }
  }

  /** 上下文将满的发送确认：压缩并发送（成功后自动续发）/ 直接发送 */
  private confirmCompactThenSend(text: string, files: FileAttachment[], editingId: string): void {
    const deliver = (): void => {
      if (editingId !== '') {
        ReplyEngine.sendEdited(this.store.currentSessionId, editingId, text, files);
      } else {
        ReplyEngine.send(this.store.currentSessionId, text, files);
      }
    };
    this.getUIContext().showAlertDialog({
      title: I18n.translate('compactAskTitle'),
      message: I18n.translate('compactAskMessage'),
      alignment: DialogAlignment.Center,
      autoCancel: true,
      secondaryButton: {
        value: I18n.translate('compactAskSendOnly'),
        fontColor: $r('app.color.text_secondary'),
        action: (): void => {
          deliver();
        },
      },
      primaryButton: {
        value: I18n.translate('compactAskCompactSend'),
        fontColor: $r('app.color.brand_activated'),
        action: (): void => {
          this.getUIContext().getPromptAction()
            .showToast({ message: I18n.translate('compactRunning'), duration: Motion.toastMax });
          ReplyEngine.compact(this.store.currentSessionId).then((): void => {
            deliver();
          }).catch((): void => {
            // 压缩失败不阻断发送：上下文若真超限由 API 错误路径提示
            this.getUIContext().getPromptAction()
              .showToast({ message: I18n.translate('compactFailed'), duration: Motion.toastLong });
            deliver();
          });
        },
      },
    });
  }
}

/** 排队待发消息 */
class QueuedSend {
  id: string = '';
  text: string = '';
  files: FileAttachment[] = [];
}

/** 会话上下文用量统计 */
class ContextStat {
  used: number = 0;
  lastOutput: number = 0;
  sessionInput: number = 0;
  sessionOutput: number = 0;
}
