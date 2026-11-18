/**
 * Markdown 解析器（GFM 常用子集）：块级结构 + 行内标记 → 类型化 AST。
 * 覆盖：标题/段落/围栏代码/引用/有序无序任务列表/表格/分隔线/行内样式/链接/图片/行内代码/行内公式。
 * 输出给 MarkdownView 渲染为 ArkUI 组件树。
 */

// ---------- 行内 ----------

export class InlineNode {
  type: string = 'text'; // text | strong | em | del | code | link | image | math | softbreak
  text: string = '';
  url: string = '';
  children: InlineNode[] = [];
}

// ---------- 块级 ----------

export class BlockNode {
  type: string = 'p'; // p | h1..h6 | code | blockquote | ul | ol | table | hr | math
  /** 文本的块（段落/标题）：行内节点 */
  inlines: InlineNode[] = [];
  /** 代码块 */
  codeLang: string = '';
  codeText: string = '';
  /** 数学块 */
  mathText: string = '';
  /** 引用/列表项的子块 */
  children: BlockNode[] = [];
  /** 列表 */
  ordered: boolean = false;
  start: number = 1;
  items: BlockNode[] = [];
  /** 列表项/表格单元格内的行内内容 */
  task: boolean = false;
  taskDone: boolean = false;
  /** 表格 */
  headCells: InlineNode[][] = [];
  rows: InlineNode[][][] = [];
  aligns: string[] = [];
}

export class MarkdownParser {
  /** 解析整篇 */
  static parse(src: string): BlockNode[] {
    const lines = src.replace(/\r\n/g, '\n').replace(/\r/g, '\n').split('\n');
    return MarkdownParser.mergeLonePunct(MarkdownParser.parseBlocks(lines, 0, lines.length));
  }

  /** 收集行内节点树的全部可见文本（递归穿过强调/链接容器） */
  private static inlineText(nodes: InlineNode[]): string {
    let out = '';
    for (const n of nodes) {
      if (n.type === 'text' || n.type === 'code' || n.type === 'math') {
        out += n.text;
      } else {
        out += MarkdownParser.inlineText(n.children);
      }
    }
    return out;
  }

  /** 纯标点文本判定（句末标点被模型/分段单独切开时用于回并） */
  static isPunctOnlyText(t: string): boolean {
    const s = t.trim();
    if (s === '') {
      return false;
    }
    const closers = '。，、；：！？!?,.;:…‥·~～—）】》〉」』”’"\'' + '-';
    for (const ch of s) {
      if (closers.indexOf(ch) < 0) {
        return false;
      }
    }
    return true;
  }

  /** 是否为「纯标点段落」：模型偶发把句末标点单独断成一段（常伴空行） */
  private static isPunctOnly(b: BlockNode): boolean {
    if (b.type !== 'p') {
      return false;
    }
    return MarkdownParser.isPunctOnlyText(MarkdownParser.inlineText(b.inlines));
  }

  /** 把纯标点段落并入前一个块（段落/列表末项/引用末段），渲染为紧接前文的标点 */
  private static mergeLonePunct(blocks: BlockNode[]): BlockNode[] {
    const out: BlockNode[] = [];
    for (const b of blocks) {
      if (out.length > 0 && MarkdownParser.isPunctOnly(b)) {
        const prev = out[out.length - 1];
        let target: BlockNode | null = null;
        if (prev.type === 'p') {
          target = prev;
        } else if (prev.type === 'list' && prev.items.length > 0) {
          const kids = prev.items[prev.items.length - 1].children;
          if (kids.length > 0 && kids[kids.length - 1].type === 'p') {
            target = kids[kids.length - 1];
          }
        } else if (prev.type === 'blockquote' && prev.children.length > 0
          && prev.children[prev.children.length - 1].type === 'p') {
          target = prev.children[prev.children.length - 1];
        }
        if (target !== null) {
          const br = new InlineNode();
          br.type = 'softbreak';
          target.inlines.push(br);
          for (const n of b.inlines) {
            target.inlines.push(n);
          }
          continue;
        }
      }
      out.push(b);
    }
    return out;
  }

  private static parseBlocks(lines: string[], start: number, end: number): BlockNode[] {
    const blocks: BlockNode[] = [];
    let i = start;
    while (i < end) {
      const line = lines[i];
      const trimmed = line.trim();
      if (trimmed === '') {
        i++;
        continue;
      }
      // 围栏代码
      if (trimmed.startsWith('```')) {
        const fence = new BlockNode();
        fence.type = 'code';
        fence.codeLang = trimmed.substring(3).trim();
        let codeLines: string[] = [];
        i++;
        while (i < end && lines[i].trim() !== '```') {
          codeLines.push(lines[i]);
          i++;
        }
        i++; // 跳过闭合 ```（或流式未闭合时 i===end）
        fence.codeText = codeLines.join('\n');
        blocks.push(fence);
        continue;
      }
      // 数学块 $$...$$
      if (trimmed.startsWith('$$')) {
        const math = new BlockNode();
        math.type = 'math';
        if (trimmed.length > 2 && trimmed.endsWith('$$')) {
          math.mathText = trimmed.substring(2, trimmed.length - 2).trim();
          i++;
        } else {
          let inner: string[] = [];
          if (trimmed.length > 2) {
            inner.push(trimmed.substring(2));
          }
          i++;
          while (i < end && lines[i].trim() !== '$$') {
            inner.push(lines[i]);
            i++;
          }
          i++;
          math.mathText = inner.join('\n').trim();
        }
        blocks.push(math);
        continue;
      }
      // 数学块 \[...\]（DeepSeek 实际输出格式）
      if (trimmed.startsWith('\\[')) {
        const math = new BlockNode();
        math.type = 'math';
        if (trimmed.length > 2 && trimmed.endsWith('\\]')) {
          math.mathText = trimmed.substring(2, trimmed.length - 2).trim();
          i++;
        } else {
          let inner: string[] = [];
          if (trimmed.length > 2) {
            inner.push(trimmed.substring(2));
          }
          i++;
          while (i < end && lines[i].trim() !== '\\]') {
            inner.push(lines[i]);
            i++;
          }
          i++;
          math.mathText = inner.join('\n').trim();
        }
        blocks.push(math);
        continue;
      }
      // ATX 标题
      const heading = MarkdownParser.headingLevel(trimmed);
      if (heading > 0) {
        const h = new BlockNode();
        h.type = `h${heading}`;
        h.inlines = MarkdownParser.parseInlines(trimmed.substring(heading).trim());
        blocks.push(h);
        i++;
        continue;
      }
      // 分隔线
      if (MarkdownParser.isHr(trimmed)) {
        const hr = new BlockNode();
        hr.type = 'hr';
        blocks.push(hr);
        i++;
        continue;
      }
      // 引用
      if (trimmed.startsWith('>')) {
        const quote = new BlockNode();
        quote.type = 'blockquote';
        const inner: string[] = [];
        while (i < end && (lines[i].trim().startsWith('>') ||
          (lines[i].trim() !== '' && inner.length > 0))) {
          const l = lines[i].trim();
          if (l.startsWith('>')) {
            inner.push(l.substring(1).replace(/^ /, ''));
          } else {
            inner.push(l);
          }
          i++;
        }
        quote.children = MarkdownParser.parseBlocks(inner, 0, inner.length);
        blocks.push(quote);
        continue;
      }
      // 列表（含任务项）
      const listMatch = MarkdownParser.listMarker(line);
      if (listMatch !== null) {
        const list = new BlockNode();
        list.type = 'list';
        list.ordered = listMatch.ordered;
        list.start = listMatch.num;
        let currentItem: BlockNode | null = null;
        let itemLines: string[] = [];
        const flushItem = (): void => {
          if (currentItem !== null) {
            currentItem.children = MarkdownParser.parseBlocks(itemLines, 0, itemLines.length);
            list.items.push(currentItem);
            currentItem = null;
            itemLines = [];
          }
        };
        while (i < end) {
          const m = MarkdownParser.listMarker(lines[i]);
          const l = lines[i].trim();
          if (m !== null && m.ordered === listMatch.ordered) {
            // 新列表项
            flushItem();
            currentItem = new BlockNode();
            currentItem.type = 'item';
            currentItem.task = m.task;
            currentItem.taskDone = m.taskDone;
            itemLines = [lines[i].substring(m.contentStart)];
            i++;
            // 同项续行（缩进行）
            while (i < end && lines[i].trim() !== '' && MarkdownParser.listMarker(lines[i]) === null
              && (lines[i].startsWith(' ') || lines[i].startsWith('\t'))) {
              itemLines.push(lines[i].trim());
              i++;
            }
            continue;
          }
          if (l === '') {
            // 空行结束列表
            break;
          }
          // 非标记非空行：CommonMark 滞后延续，并入当前项。
          // 模型偶发把句末标点单独断行（如孤立的“。”），原逻辑会把它拆成独立段落/列表项
          if (currentItem !== null) {
            itemLines.push(l);
            i++;
            continue;
          }
          break;
        }
        flushItem();
        if (list.items.length > 0) {
          blocks.push(list);
        }
        continue;
      }
      // 表格
      if (i + 1 < end && trimmed.includes('|') && MarkdownParser.isTableDivider(lines[i + 1])) {
        const table = new BlockNode();
        table.type = 'table';
        table.headCells = MarkdownParser.splitRow(trimmed);
        table.aligns = MarkdownParser.parseAligns(lines[i + 1]);
        i += 2;
        while (i < end && lines[i].trim() !== '' && lines[i].includes('|')) {
          table.rows.push(MarkdownParser.splitRow(lines[i].trim()));
          i++;
        }
        blocks.push(table);
        continue;
      }
      // 段落（连续非空、非结构行）
      const para = new BlockNode();
      para.type = 'p';
      const paraLines: string[] = [trimmed];
      i++;
      while (i < end && lines[i].trim() !== '') {
        const l = lines[i].trim();
        if (l.startsWith('```') || l.startsWith('$$') || MarkdownParser.headingLevel(l) > 0
          || MarkdownParser.isHr(l) || l.startsWith('>') || MarkdownParser.listMarker(l) !== null) {
          break;
        }
        paraLines.push(l);
        i++;
      }
      // 合并软换行为空格（渲染时逐行处理更贴近源观感，保留 softbreak）
      for (let k = 0; k < paraLines.length; k++) {
        const inline = MarkdownParser.parseInlines(paraLines[k]);
        if (k > 0) {
          const br = new InlineNode();
          br.type = 'softbreak';
          inline.unshift(br);
        }
        for (const n of inline) {
          para.inlines.push(n);
        }
      }
      blocks.push(para);
    }
    return blocks;
  }

  private static headingLevel(s: string): number {
    let n = 0;
    while (n < 6 && s.startsWith('#', n)) {
      n++;
    }
    if (n > 0 && n < s.length && s.charAt(n) === ' ') {
      return n;
    }
    return 0;
  }

  private static isHr(s: string): boolean {
    if (s.length < 3) {
      return false;
    }
    const c = s.charAt(0);
    if (c !== '-' && c !== '*' && c !== '_') {
      return false;
    }
    for (const ch of s) {
      if (ch !== c && ch !== ' ') {
        return false;
      }
    }
    return true;
  }

  private static listMarker(line: string): ListMarker | null {
    const m = line.trim();
    let ordered = false;
    let num = 1;
    let markLen = 0;
    if (m.startsWith('- ') || m.startsWith('* ') || m.startsWith('+ ')) {
      markLen = 2;
    } else {
      const dot = m.indexOf('. ');
      if (dot > 0 && dot <= 4) {
        const digits = m.substring(0, dot);
        let allDigits = digits.length > 0;
        for (const ch of digits) {
          if (ch < '0' || ch > '9') {
            allDigits = false;
            break;
          }
        }
        if (allDigits) {
          ordered = true;
          num = parseInt(digits, 10);
          markLen = dot + 2;
        }
      }
    }
    if (markLen === 0) {
      return null;
    }
    const after = m.substring(markLen);
    let task = false;
    let taskDone = false;
    let content = after;
    if (after.startsWith('[ ] ') || after.startsWith('[x] ') || after.startsWith('[X] ')) {
      task = true;
      taskDone = after.charAt(1) !== ' ';
      content = after.substring(4);
    }
    const leading = line.length - line.trimStart().length;
    const contentStart = leading + markLen + (task ? 4 : 0);
    return new ListMarker(ordered, num, task, taskDone, contentStart, content);
  }

  private static isTableDivider(s: string): boolean {
    const t = s.trim();
    if (!t.includes('-') || !t.includes('|')) {
      return false;
    }
    for (const ch of t) {
      if (ch !== '-' && ch !== '|' && ch !== ':' && ch !== ' ') {
        return false;
      }
    }
    return true;
  }

  private static splitRow(s: string): InlineNode[][] {
    let t = s.trim();
    if (t.startsWith('|')) {
      t = t.substring(1);
    }
    if (t.endsWith('|')) {
      t = t.substring(0, t.length - 1);
    }
    const cells: InlineNode[][] = [];
    for (const cell of t.split('|')) {
      cells.push(MarkdownParser.parseInlines(cell.trim()));
    }
    return cells;
  }

  private static parseAligns(s: string): string[] {
    const out: string[] = [];
    let t = s.trim();
    if (t.startsWith('|')) {
      t = t.substring(1);
    }
    if (t.endsWith('|')) {
      t = t.substring(0, t.length - 1);
    }
    for (const cell of t.split('|')) {
      const c = cell.trim();
      const left = c.startsWith(':');
      const right = c.endsWith(':');
      if (left && right) {
        out.push('center');
      } else if (right) {
        out.push('right');
      } else {
        out.push('left');
      }
    }
    return out;
  }

  /** 行内解析：code span → math → strong/em/del → link/image */
  static parseInlines(s: string): InlineNode[] {
    const out: InlineNode[] = [];
    let i = 0;
    let plain = '';
    const flush = (): void => {
      if (plain !== '') {
        const n = new InlineNode();
        n.type = 'text';
        n.text = plain;
        out.push(n);
        plain = '';
      }
    };
    while (i < s.length) {
      const ch = s.charAt(i);
      // 行内代码
      if (ch === '`') {
        const close = s.indexOf('`', i + 1);
        if (close > i) {
          flush();
          const n = new InlineNode();
          n.type = 'code';
          n.text = s.substring(i + 1, close);
          out.push(n);
          i = close + 1;
          continue;
        }
      }
      // 行内公式 \(...\)（DeepSeek 实际输出格式）
      if (ch === '\\' && i + 1 < s.length && s.charAt(i + 1) === '(') {
        const closeParen = s.indexOf('\\)', i + 2);
        if (closeParen > i + 2) {
          flush();
          const n = new InlineNode();
          n.type = 'math';
          n.text = s.substring(i + 2, closeParen);
          out.push(n);
          i = closeParen + 2;
          continue;
        }
      }
      // 行内公式
      if (ch === '$' && i + 1 < s.length) {
        const close = s.indexOf('$', i + 1);
        if (close > i + 1) {
          flush();
          const n = new InlineNode();
          n.type = 'math';
          n.text = s.substring(i + 1, close);
          out.push(n);
          i = close + 1;
          continue;
        }
      }
      // 图片 ![alt](url)
      if (ch === '!' && i + 1 < s.length && s.charAt(i + 1) === '[') {
        const closeBracket = s.indexOf('](', i + 2);
        if (closeBracket > 0) {
          const closeParen = s.indexOf(')', closeBracket);
          if (closeParen > closeBracket) {
            flush();
            const n = new InlineNode();
            n.type = 'image';
            n.text = s.substring(i + 2, closeBracket);
            n.url = s.substring(closeBracket + 2, closeParen);
            out.push(n);
            i = closeParen + 1;
            continue;
          }
        }
      }
      // 链接 [text](url)
      if (ch === '[') {
        const closeBracket = s.indexOf('](', i + 1);
        if (closeBracket > 0) {
          const closeParen = s.indexOf(')', closeBracket);
          if (closeParen > closeBracket) {
            flush();
            const n = new InlineNode();
            n.type = 'link';
            n.url = s.substring(closeBracket + 2, closeParen);
            n.children = MarkdownParser.parseInlines(s.substring(i + 1, closeBracket));
            out.push(n);
            i = closeParen + 1;
            continue;
          }
        }
      }
      // 强调 **bold** / __bold__
      if ((ch === '*' && s.startsWith('**', i)) || (ch === '_' && s.startsWith('__', i))) {
        const marker = ch === '*' ? '**' : '__';
        const close = s.indexOf(marker, i + 2);
        if (close > 0) {
          flush();
          const n = new InlineNode();
          n.type = 'strong';
          n.children = MarkdownParser.parseInlines(s.substring(i + 2, close));
          out.push(n);
          i = close + 2;
          continue;
        }
      }
      // 斜体 *em* / _em_
      if (ch === '*' || (ch === '_' && (i === 0 || s.charAt(i - 1) === ' '))) {
        const close = s.indexOf(ch, i + 1);
        if (close > i + 1) {
          flush();
          const n = new InlineNode();
          n.type = 'em';
          n.children = MarkdownParser.parseInlines(s.substring(i + 1, close));
          out.push(n);
          i = close + 1;
          continue;
        }
      }
      // 删除线 ~~del~~
      if (ch === '~' && s.startsWith('~~', i)) {
        const close = s.indexOf('~~', i + 2);
        if (close > 0) {
          flush();
          const n = new InlineNode();
          n.type = 'del';
          n.children = MarkdownParser.parseInlines(s.substring(i + 2, close));
          out.push(n);
          i = close + 2;
          continue;
        }
      }
      // 转义
      if (ch === '\\' && i + 1 < s.length) {
        const next = s.charAt(i + 1);
        if ('`*_{}[]()#+-.!~$\\|'.includes(next)) {
          plain += next;
          i += 2;
          continue;
        }
      }
      plain += ch;
      i++;
    }
    flush();
    return out;
  }
}

class ListMarker {
  ordered: boolean;
  num: number;
  task: boolean;
  taskDone: boolean;
  contentStart: number;
  content: string;

  constructor(ordered: boolean, num: number, task: boolean, taskDone: boolean, contentStart: number, content: string) {
    this.ordered = ordered;
    this.num = num;
    this.task = task;
    this.taskDone = taskDone;
    this.contentStart = contentStart;
    this.content = content;
  }
}
