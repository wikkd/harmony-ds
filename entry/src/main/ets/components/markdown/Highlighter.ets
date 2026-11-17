/**
 * 轻量语法高亮：关键字/字符串/注释/数字/标点 分段着色。
 * 覆盖 ArkTS/TS/JS/Python/Java/C/C++/JSON/HTML 常见结构；未识别语言按纯文本。
 * 配色取自官方深浅色语义（token 类别 → 资源色）。
 */

export class CodeSpan {
  text: string = '';
  kind: string = 'plain'; // plain | keyword | string | comment | number | punct | func | type
}

export class Highlighter {
  private static readonly KEYWORDS: Set<string> = new Set([
    'abstract', 'as', 'async', 'await', 'break', 'case', 'catch', 'class', 'const', 'constructor',
    'continue', 'debugger', 'declare', 'default', 'delete', 'do', 'else', 'enum', 'export',
    'extends', 'false', 'finally', 'for', 'from', 'function', 'get', 'if', 'implements', 'import',
    'in', 'instanceof', 'interface', 'is', 'let', 'namespace', 'new', 'null', 'number', 'of',
    'private', 'protected', 'public', 'readonly', 'return', 'set', 'static', 'string', 'super',
    'switch', 'this', 'throw', 'true', 'try', 'type', 'typeof', 'undefined', 'var', 'void',
    'while', 'yield', 'def', 'elif', 'except', 'lambda', 'pass', 'raise', 'with', 'and', 'or',
    'not', 'None', 'True', 'False', 'self', 'print', 'struct', 'union', 'template', 'typename',
    'public:', 'private:', 'using', 'include', 'int', 'float', 'double', 'char', 'bool', 'long',
    'short', 'unsigned', 'signed', 'final', 'abstract', 'package', 'extends', 'synchronized',
  ]);

  /** 高亮一段代码：逐段切分 */
  static highlight(code: string, lang: string): CodeSpan[] {
    const out: CodeSpan[] = [];
    const l = lang.toLowerCase();
    const hashComment = ['py', 'python', 'sh', 'bash', 'yaml', 'yml', 'toml', 'ini'].includes(l);
    const sqlLike = ['sql'].includes(l);
    let i = 0;
    let plain = '';
    const flush = (): void => {
      if (plain !== '') {
        Highlighter.pushPlain(out, plain);
        plain = '';
      }
    };
    while (i < code.length) {
      const ch = code.charAt(i);
      const two = i + 1 < code.length ? code.substring(i, i + 2) : '';
      // 行注释
      if ((ch === '#' && hashComment) || two === '//' || (sqlLike && two === '--')) {
        const nl = code.indexOf('\n', i);
        const end = nl === -1 ? code.length : nl;
        flush();
        const span = new CodeSpan();
        span.text = code.substring(i, end);
        span.kind = 'comment';
        out.push(span);
        i = end;
        continue;
      }
      // 块注释 /* */ （C 系）
      if (two === '/*') {
        const close = code.indexOf('*/', i + 2);
        const end = close === -1 ? code.length : close + 2;
        flush();
        const span = new CodeSpan();
        span.text = code.substring(i, end);
        span.kind = 'comment';
        out.push(span);
        i = end;
        continue;
      }
      // 三引号字符串（Python）
      if (code.startsWith('"""', i) || code.startsWith("'''", i)) {
        const q = code.substring(i, i + 3);
        const close = code.indexOf(q, i + 3);
        const end = close === -1 ? code.length : close + 3;
        flush();
        const span = new CodeSpan();
        span.text = code.substring(i, end);
        span.kind = 'string';
        out.push(span);
        i = end;
        continue;
      }
      // 字符串
      if (ch === '"' || ch === "'" || ch === '`') {
        let j = i + 1;
        while (j < code.length) {
          if (code.charAt(j) === '\\') {
            j += 2;
            continue;
          }
          if (code.charAt(j) === ch) {
            j++;
            break;
          }
          j++;
        }
        flush();
        const span = new CodeSpan();
        span.text = code.substring(i, Math.min(j, code.length));
        span.kind = 'string';
        out.push(span);
        i = j;
        continue;
      }
      // 数字
      if (ch >= '0' && ch <= '9') {
        let j = i;
        while (j < code.length && /[0-9a-fA-FxX._]/.test(code.charAt(j))) {
          j++;
        }
        flush();
        const span = new CodeSpan();
        span.text = code.substring(i, j);
        span.kind = 'number';
        out.push(span);
        i = j;
        continue;
      }
      // 标识符/关键字
      if (/[A-Za-z_$]/.test(ch)) {
        let j = i;
        while (j < code.length && /[A-Za-z0-9_$]/.test(code.charAt(j))) {
          j++;
        }
        const word = code.substring(i, j);
        // 函数名（后随 '('）
        let k = j;
        while (k < code.length && code.charAt(k) === ' ') {
          k++;
        }
        const isCall = k < code.length && code.charAt(k) === '(';
        flush();
        const span = new CodeSpan();
        span.text = word;
        if (Highlighter.KEYWORDS.has(word)) {
          span.kind = 'keyword';
        } else if (isCall) {
          span.kind = 'func';
        } else if (word.charAt(0) >= 'A' && word.charAt(0) <= 'Z') {
          span.kind = 'type';
        } else {
          span.kind = 'plain';
        }
        out.push(span);
        i = j;
        continue;
      }
      // 标点
      if ('{}[]()<>=+-*/%!&|;:,.'.includes(ch)) {
        flush();
        const span = new CodeSpan();
        span.text = ch;
        span.kind = 'punct';
        out.push(span);
        i++;
        continue;
      }
      plain += ch;
      i++;
    }
    flush();
    return out;
  }

  private static pushPlain(out: CodeSpan[], text: string): void {
    // 纯文本按空白保留
    const span = new CodeSpan();
    span.text = text;
    span.kind = 'plain';
    out.push(span);
  }
}
