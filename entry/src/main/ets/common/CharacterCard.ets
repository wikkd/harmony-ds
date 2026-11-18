import { util } from '@kit.ArkTS';
import fs from '@ohos.file.fs';
import { Logger } from './Logger';

const TAG = 'CharacterCard';

/** 角色卡已知 frontmatter 键 → 提示词条目标签 */
const KNOWN_KEYS: Record<string, string> = {
  'name': '角色名',
  'description': '角色设定',
  'personality': '性格',
  'scenario': '场景',
  'first_mes': '开场白',
  'greeting': '开场白',
  'mes_example': '对话示例',
};
/** 组装顺序（名字在前，开场白收尾） */
const KEY_ORDER: string[] = ['name', 'description', 'personality', 'scenario', 'first_mes', 'mes_example'];
/** 与个性化输入框 maxLength 保持一致 */
const MAX_LEN: number = 2000;

/**
 * 角色卡 md 导入解析：
 * - 带 YAML frontmatter（SillyTavern 等社区通行格式）：取已知键组装成
 *   【标签】值 的可读提示词，正文追加在后；未知键忽略
 * - 无 frontmatter：正文原样作为人格文本
 * 解析为纯函数（不依赖 UI/区域设置），超长截断到个性化输入框上限。
 */
export class CharacterCard {

  static parse(raw: string): string {
    const text = raw.replace(/\r\n/g, '\n').trim();
    if (text.startsWith('{')) {
      return CharacterCard.parseJson(text);
    }
    if (!text.startsWith('---')) {
      return CharacterCard.clamp(text);
    }
    const close = CharacterCard.frontmatterClose(text);
    if (close < 0) {
      // 只有开头的 --- 视为普通正文（可能是分隔线开头）
      return CharacterCard.clamp(text);
    }
    const values = CharacterCard.parseFrontmatter(text.substring(3, close));
    const body = text.substring(close + 4).trim();
    return CharacterCard.clamp(CharacterCard.assemble(values, body));
  }

  /** 已知键按序组装为【标签】值 段落，正文追加在后 */
  private static assemble(values: Map<string, string>, body: string): string {
    let out = '';
    for (const key of KEY_ORDER) {
      const v = values.get(key);
      if (v !== undefined && v !== '') {
        out += `【${KNOWN_KEYS[key]}】${v}\n\n`;
      }
    }
    if (body !== '') {
      out += body;
    }
    return out.trim();
  }

  /** 从选择的文档 URI 读文本（上限 1MB，角色卡远小于此） */
  static async readText(uri: string): Promise<string> {
    const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    try {
      const stat = fs.statSync(file.fd);
      const size = Math.min(stat.size, 1024 * 1024);
      const buf = new ArrayBuffer(size);
      fs.readSync(file.fd, buf);
      return util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(buf));
    } catch (e) {
      Logger.warn(TAG, `read failed: ${JSON.stringify(e)}`);
      return '';
    } finally {
      try {
        fs.closeSync(file);
      } catch (e) {
        // 忽略
      }
    }
  }

  /** SillyTavern JSON 卡（含 chara_card_v2 的 data 嵌套）：取已知字段组装，非法 JSON 返回空串 */
  private static parseJson(text: string): string {
    let obj: Record<string, Object>;
    try {
      obj = JSON.parse(text) as Record<string, Object>;
    } catch (e) {
      return '';
    }
    const data = obj['data'];
    if (data !== null && data !== undefined && typeof data === 'object') {
      obj = data as Record<string, Object>;
    }
    const values = new Map<string, string>();
    for (const key of KEY_ORDER) {
      const v = obj[key];
      if (typeof v === 'string' && v.trim() !== '') {
        values.set(key, v.trim());
      }
    }
    return CharacterCard.clamp(CharacterCard.assemble(values, ''));
  }


  /** frontmatter 结束位置（独立成行的 ---），找不到返回 -1 */
  private static frontmatterClose(text: string): number {
    let idx = text.indexOf('\n---', 3);
    while (idx >= 0) {
      const after = idx + 4;
      if (after >= text.length || text.charAt(after) === '\n') {
        return idx;
      }
      idx = text.indexOf('\n---', idx + 1);
    }
    return -1;
  }

  /** 宽容解析 top-level 键值：续行（缩进/非键行）并入当前键；剥离成对引号 */
  private static parseFrontmatter(block: string): Map<string, string> {
    const values = new Map<string, string>();
    let current = '';
    for (const line of block.split('\n')) {
      const m = line.match(/^([A-Za-z][A-Za-z0-9_-]*)\s*:\s*(.*)$/);
      if (m !== null) {
        current = m[1].toLowerCase();
        if (KNOWN_KEYS[current] !== undefined) {
          // 块标量指示符（| > 及折叠变体）本身不进值，内容取后续缩进行
          const v = /^[|>][+-]?\s*$/.test(m[2]) ? '' : CharacterCard.stripQuotes(m[2]).trim();
          values.set(current, v);
        } else {
          current = '';
        }
        continue;
      }
      // 续行：并入最近一个已知键（块标量/多行描述）
      if (current !== '' && line.trim() !== '' && (line.startsWith(' ') || line.startsWith('-'))) {
        const prev = values.get(current) ?? '';
        values.set(current, prev === '' ? line.trim() : `${prev}\n${line.trim()}`);
      }
    }
    return values;
  }

  private static stripQuotes(v: string): string {
    if (v.length >= 2 && ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'")))) {
      return v.substring(1, v.length - 1);
    }
    return v;
  }

  private static clamp(text: string): string {
    return text.length > MAX_LEN ? text.substring(0, MAX_LEN) : text;
  }
}
