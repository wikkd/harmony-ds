import { Fonts } from '../../common/Fonts';
/**
 * 数学公式渲染（LaTeX 常用子集）：
 * - 符号映射（希腊字母/运算符/关系符/箭头/集合）→ Unicode
 * - ^{}/_{} 上下标 → Unicode 上下标字符（跨分片稳定、无特殊排版依赖）
 * - \frac 行内 (a)/(b)；\sqrt → √(x)；未识别命令保持原文（优雅降级）
 */

export class MathSpan {
  text: string = '';
}

const SUPER_MAP: Record<string, string> = {
  '0': '⁰', '1': '¹', '2': '²', '3': '³', '4': '⁴', '5': '⁵', '6': '⁶', '7': '⁷', '8': '⁸', '9': '⁹',
  '+': '⁺', '-': '⁻', '=': '⁼', '(': '⁽', ')': '⁾', 'n': 'ⁿ', 'i': 'ⁱ', ' ': ' ',
};
const SUB_MAP: Record<string, string> = {
  '0': '₀', '1': '₁', '2': '₂', '3': '₃', '4': '₄', '5': '₅', '6': '₆', '7': '₇', '8': '₈', '9': '₉',
  '+': '₊', '-': '₋', '=': '₌', '(': '₍', ')': '₎', 'a': 'ₐ', 'e': 'ₑ', 'o': 'ₒ', 'x': 'ₓ',
  'h': 'ₕ', 'k': 'ₖ', 'l': 'ₗ', 'm': 'ₘ', 'n': 'ₙ', 'p': 'ₚ', 's': 'ₛ', 't': 'ₜ', ' ': ' ',
};

function scriptText(raw: string, map: Record<string, string>, caret: string): string {
  let out = '';
  for (const ch of raw) {
    const mapped = map[ch];
    if (mapped !== undefined) {
      out += mapped;
    } else {
      out += `${caret}${ch}`;
    }
  }
  return out;
}

export class MathConverter {
  private static symbols: Record<string, string> = {
    'alpha': 'α', 'beta': 'β', 'gamma': 'γ', 'delta': 'δ', 'epsilon': 'ε', 'varepsilon': 'ε',
    'zeta': 'ζ', 'eta': 'η', 'theta': 'θ', 'iota': 'ι', 'kappa': 'κ', 'lambda': 'λ',
    'mu': 'μ', 'nu': 'ν', 'xi': 'ξ', 'pi': 'π', 'rho': 'ρ', 'sigma': 'σ', 'tau': 'τ',
    'upsilon': 'υ', 'phi': 'φ', 'varphi': 'φ', 'chi': 'χ', 'psi': 'ψ', 'omega': 'ω',
    'Gamma': 'Γ', 'Delta': 'Δ', 'Theta': 'Θ', 'Lambda': 'Λ', 'Xi': 'Ξ', 'Pi': 'Π',
    'Sigma': 'Σ', 'Phi': 'Φ', 'Psi': 'Ψ', 'Omega': 'Ω',
    'times': '×', 'cdot': '·', 'div': '÷', 'pm': '±', 'mp': '∓',
    'leq': '≤', 'le': '≤', 'geq': '≥', 'ge': '≥', 'neq': '≠', 'ne': '≠', 'approx': '≈', 'equiv': '≡',
    'sim': '∼', 'propto': '∝',
    'infty': '∞', 'partial': '∂', 'nabla': '∇',
    'sum': '∑', 'prod': '∏', 'int': '∫', 'iint': '∬', 'iiint': '∭',
    'rightarrow': '→', 'to': '→', 'leftarrow': '←', 'gets': '←',
    'leftrightarrow': '↔', 'Rightarrow': '⇒', 'implies': '⇒', 'Leftarrow': '⇐',
    'Leftrightarrow': '⇔', 'iff': '⇔', 'mapsto': '↦',
    'uparrow': '↑', 'downarrow': '↓', 'updownarrow': '↕', 'Uparrow': '⇑', 'Downarrow': '⇓',
    'in': '∈', 'notin': '∉', 'ni': '∋', 'subset': '⊂', 'subseteq': '⊆',
    'supset': '⊃', 'supseteq': '⊇', 'cup': '∪', 'cap': '∩', 'emptyset': '∅', 'varnothing': '∅',
    'forall': '∀', 'exists': '∃', 'nexists': '∄', 'neg': '¬', 'land': '∧', 'lor': '∨',
    'oplus': '⊕', 'otimes': '⊗', 'perp': '⊥', 'parallel': '∥', 'angle': '∠',
    'degree': '°', 'prime': '′', 'ell': 'ℓ', 'Re': 'ℜ', 'Im': 'ℑ', 'aleph': 'ℵ',
    'langle': '⟨', 'rangle': '⟩', 'lfloor': '⌊', 'rfloor': '⌋', 'lceil': '⌈', 'rceil': '⌉',
    'ldots': '…', 'cdots': '⋯', 'vdots': '⋮', 'ddots': '⋱', 'dots': '…',
  };

  static convert(latex: string): MathSpan[] {
    const out: MathSpan[] = [];
    MathConverter.walk(latex, 0, out);
    if (out.length === 0) {
      const s = new MathSpan();
      s.text = latex;
      out.push(s);
    }
    return out;
  }

  private static walk(latex: string, start: number, out: MathSpan[]): number {
    // 用栈式实现替代闭包递归
    let plain = '';
    let i = start;
    const flush = (): void => {
      if (plain !== '') {
        const s = new MathSpan();
        s.text = plain;
        out.push(s);
        plain = '';
      }
    };
    while (i < latex.length) {
      const ch = latex.charAt(i);
      if (ch === '^' || ch === '_') {
        flush();
        const group = MathConverter.readGroup(latex, i + 1);
        const s = new MathSpan();
        s.text = scriptText(group.text, ch === '^' ? SUPER_MAP : SUB_MAP, ch === '^' ? '^' : '_');
        out.push(s);
        i = group.next;
        continue;
      }
      if (ch === '\\') {
        let j = i + 1;
        while (j < latex.length && /[a-zA-Z]/.test(latex.charAt(j))) {
          j++;
        }
        const name = latex.substring(i + 1, j);
        if (name === 'frac' || name === 'dfrac' || name === 'tfrac') {
          const num = MathConverter.readGroup(latex, j);
          const den = MathConverter.readGroup(latex, num.next);
          flush();
          const s = new MathSpan();
          s.text = `(${num.text})/(${den.text})`;
          out.push(s);
          i = den.next;
          continue;
        }
        if (name === 'sqrt') {
          const arg = MathConverter.readGroup(latex, j);
          flush();
          const s = new MathSpan();
          s.text = `√(${arg.text})`;
          out.push(s);
          i = arg.next;
          continue;
        }
        if (name === 'text' || name === 'mathrm' || name === 'operatorname') {
          const arg = MathConverter.readGroup(latex, j);
          flush();
          const s = new MathSpan();
          s.text = arg.text;
          out.push(s);
          i = arg.next;
          continue;
        }
        if (name === 'left' || name === 'right') {
          i = j;
          if (i < latex.length && latex.charAt(i) !== '.') {
            plain += latex.charAt(i);
          }
          i++;
          continue;
        }
        if (name === ' ' || name === 'quad' || name === 'qquad' || name === ','
          || name === ';' || name === ':' || name === '!') {
          flush();
          const s = new MathSpan();
          s.text = name === ' ' || name === ',' || name === ';' || name === ':' ? ' ' : '  ';
          out.push(s);
          i = j;
          continue;
        }
        const sym = MathConverter.symbols[name];
        if (sym !== undefined) {
          flush();
          const s = new MathSpan();
          s.text = sym;
          out.push(s);
          i = j;
          continue;
        }
        plain += latex.substring(i, j);
        i = j;
        continue;
      }
      if (ch === '{' || ch === '}') {
        i++;
        continue;
      }
      plain += ch;
      i++;
    }
    flush();
    return i;
  }

  private static readGroup(s: string, start: number): GroupResult {
    if (start >= s.length) {
      return new GroupResult('', start);
    }
    if (s.charAt(start) === '{') {
      let depth = 1;
      let j = start + 1;
      while (j < s.length && depth > 0) {
        if (s.charAt(j) === '{') {
          depth++;
        } else if (s.charAt(j) === '}') {
          depth--;
          if (depth === 0) {
            break;
          }
        }
        j++;
      }
      return new GroupResult(s.substring(start + 1, j), j + 1);
    }
    if (s.charAt(start) === '\\') {
      let j = start + 1;
      while (j < s.length && /[a-zA-Z]/.test(s.charAt(j))) {
        j++;
      }
      return new GroupResult(s.substring(start, j), j);
    }
    return new GroupResult(s.charAt(start), start + 1);
  }
}

class GroupResult {
  text: string;
  next: number;

  constructor(text: string, next: number) {
    this.text = text;
    this.next = next;
  }
}

/** 块级公式视图 */
@ComponentV2
export struct MathBlock {
  @Param latex: string = '';

  build() {
    Text() {
      ForEach(MathConverter.convert(this.latex), (s: MathSpan, i: number) => {
        Span(s.text)
      }, (s: MathSpan, i: number) => `m${i}`)
    }
    .fontSize(Fonts.body1())
    .fontColor($r('app.color.text_primary'))
    .fontFamily('serif')
    .width('100%')
    .textAlign(TextAlign.Center)
    .padding(8)
  }
}

/** 行内公式 */
@ComponentV2
export struct MathInline {
  @Param latex: string = '';

  build() {
    Text() {
      ForEach(MathConverter.convert(this.latex), (s: MathSpan, i: number) => {
        Span(s.text)
      }, (s: MathSpan, i: number) => `mi${i}`)
    }
    .fontSize(Fonts.body1())
    .fontColor($r('app.color.text_primary'))
    .fontFamily('serif')
  }
}
