import { picker } from '@kit.CoreFileKit';
import fs from '@ohos.file.fs';
import { Context } from '@kit.AbilityKit';
import { Session, Message, isAssistant, isUser, UserMessage, AssistantMessage, getReplyText } from '../../model/ChatTypes';
import { ChatDb } from '../db/ChatDb';
import { ChatStore } from '../chat/ChatStore';
import { AppContextHolder } from '../../common/AppContextHolder';
import { I18n } from '../../common/I18n';
import { Logger } from '../../common/Logger';

const TAG: string = 'MarkdownExport';

/**
 * 会话导出为 Markdown：选中文链 → 拼接 md → 系统另存为对话框。
 */
export class MarkdownExport {
  static async exportSession(sessionId: string): Promise<boolean> {
    try {
      const store = ChatStore.get();
      const session = store.sessionById(sessionId);
      if (session === null) {
        return false;
      }
      if (session.messages.length === 0) {
        session.messages = await ChatDb.loadMessages(sessionId);
      }
      const md = MarkdownExport.build(store.displayTitle(session), session);
      const context = AppContextHolder.get() as Context;
      const docPicker = new picker.DocumentViewPicker();
      const options = new picker.DocumentSaveOptions();
      options.newFileNames = [MarkdownExport.safeName(store.displayTitle(session)) + '.md'];
      const result = await docPicker.save(options);
      if (result.length === 0) {
        return false; // 用户取消
      }
      const tmp = `${context.cacheDir}/export_${Date.now()}.md`;
      const tmpFile = fs.openSync(tmp, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(tmpFile.fd, md);
      fs.closeSync(tmpFile);
      fs.copyFileSync(tmp, result[0]);
      try {
        fs.unlinkSync(tmp);
      } catch (e) {
        // 忽略
      }
      return true;
    } catch (err) {
      Logger.warn(TAG, `export md failed: ${JSON.stringify(err)}`);
      return false;
    }
  }

  /** 选中文链：rootMessageId → selectedChildId */
  private static build(title: string, session: Session): string {
    const chain: Message[] = [];
    let cur: Message | null = null;
    if (session.rootMessageId !== null) {
      cur = MarkdownExport.find(session, session.rootMessageId);
    }
    if (cur === null && session.messages.length > 0) {
      cur = session.messages[0];
    }
    let guard = 0;
    while (cur !== null && guard < 10000) {
      chain.push(cur);
      guard++;
      if (cur.selectedChildId === null) {
        break;
      }
      cur = MarkdownExport.find(session, cur.selectedChildId);
    }
    return MarkdownExport.render(title, chain);
  }

  private static find(session: Session, id: string): Message | null {
    for (const m of session.messages) {
      if (m.id === id) {
        return m;
      }
    }
    return null;
  }

  private static render(title: string, chain: Message[]): string {
    const now = new Date();
    const pad = (n: number): string => `${n}`.padStart(2, '0');
    const stamp = `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())} ${pad(now.getHours())}:${pad(now.getMinutes())}`;
    const NL = String.fromCharCode(10);
    const parts: string[] = [];
    parts.push(`# ${title}`);
    parts.push('');
    parts.push(`> ${I18n.translate('exportMdFrom')} ${stamp}`);
    parts.push('');
    for (const m of chain) {
      if (isUser(m)) {
        const u = m as UserMessage;
        parts.push('---');
        parts.push('');
        parts.push(`**${I18n.translate('exportMdUser')}**`);
        parts.push('');
        parts.push(u.content);
        if (u.files.length > 0) {
          const names: string[] = [];
          for (const f of u.files) {
            names.push(f.name);
          }
          parts.push('');
          parts.push(`> ${I18n.translate('exportMdFiles')} ${names.join(', ')}`);
        }
        parts.push('');
      } else if (isAssistant(m)) {
        const a = m as AssistantMessage;
        const text = getReplyText(a);
        if (text === '') {
          continue;
        }
        parts.push('---');
        parts.push('');
        parts.push(`**${I18n.translate('exportMdAssistant')}**`);
        parts.push('');
        parts.push(text);
        parts.push('');
      }
    }
    parts.push('---');
    parts.push('');
    return parts.join(NL);
  }

  private static safeName(title: string): string {
    const pattern = /["*<>?|/\\:]+/g;
    const cleaned = title.replace(pattern, '_').trim();
    return cleaned === '' ? I18n.translate('untitledChat') : cleaned.slice(0, 40);
  }
}
