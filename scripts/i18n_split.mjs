// One-shot I18n domain split. Run: node scripts/i18n_split.mjs
import fs from 'node:fs';
import path from 'node:path';

const ROOT = path.resolve(import.meta.dirname, '..');
const I18N = path.join(ROOT, 'entry/src/main/ets/common/I18n.ets');
const OUT_DIR = path.join(ROOT, 'entry/src/main/ets/common/i18n');

const src = fs.readFileSync(I18N, 'utf8');
const lines = src.split('\n');

// ---- parse: two Record blocks (zh lines 8.., en ..) as ordered entries with raw lines
function parseBlock(startIdx) {
  const entries = [];
  let cur = null;
  for (let i = startIdx; i < lines.length; i++) {
    const l = lines[i];
    if (l.startsWith('};')) {
      break;
    }
    const m = l.match(/^  '([^']+)':\s?(.*)$/);
    if (m) {
      if (cur) {
        entries.push(cur);
      }
      cur = { key: m[1], value: m[2] };
    } else if (cur && l.trim() !== '') {
      cur.value += '\n' + l.trim();
    }
  }
  if (cur) {
    entries.push(cur);
  }
  return entries;
}
const zhStart = lines.findIndex((l) => l.startsWith('export const zh'));
const enStart = lines.findIndex((l) => l.startsWith('export const en'));
const zhEntries = parseBlock(zhStart + 1);
const enEntries = parseBlock(enStart + 1);
console.log(`zh ${zhEntries.length}, en ${enEntries.length}`);

// ---- classify
const RULES = [
  ['Legal', /^privacyPolicy|^privacyConsent|^agreement|^userAgreement/],
  ['Usage', /^usage|^peak/],
  ['Errors', /^reply|^commonNetwork|^unknownError|^requestFailed|^completionServerBusy/],
  ['Backup', /^history|^export|^backup|^deleteAll/],
  ['Sessions', /^session|^newChat|^untitledChat|^latestReminder|^deleteSession/],
  ['Common', /^(appName|about|version|portingFrom|cancel|confirm|delete|copied|search)$/],
  ['Settings', /^settings|^avatarMenu|^fontSize|^fontOpt|^notify|^liveView|^personalization|^persona|^model|^serviceAddress|^customModelHint|^dataManage/],
];
function domainOf(key) {
  for (const [d, re] of RULES) {
    if (re.test(key)) {
      return d;
    }
  }
  return 'Chat';
}
const DOMAINS = ['Common', 'Legal', 'Sessions', 'Chat', 'Errors', 'Settings', 'Backup', 'Usage'];
const bucket = {};
for (const d of DOMAINS) {
  bucket[d] = { zh: [], en: [] };
}
for (const e of zhEntries) {
  bucket[domainOf(e.key)].zh.push(e);
}
for (const e of enEntries) {
  bucket[domainOf(e.key)].en.push(e);
}
for (const d of DOMAINS) {
  console.log(`${d}: zh=${bucket[d].zh.length} en=${bucket[d].en.length}`);
}

// ---- emit domain files
fs.mkdirSync(OUT_DIR, { recursive: true });
for (const d of DOMAINS) {
  const body = (kind, arr) =>
    `export const ${kind}_${d.toUpperCase()}: Record<string, string> = {\n` +
    arr.map((e) => `  '${e.key}': ${e.value}`).join('\n') + '\n};\n';
  const out =
    `/** 词条分域：${d}（由 scripts/i18n_split.mjs 生成，勿手改本文件结构） */\n` +
    body('ZH', bucket[d].zh) + '\n' + body('EN', bucket[d].en);
  fs.writeFileSync(path.join(OUT_DIR, `I18n${d}.ets`), out);
}

// ---- rewrite I18n.ets
const imports = DOMAINS.map((d) =>
  `import { ZH_${d.toUpperCase()}, EN_${d.toUpperCase()} } from './i18n/I18n${d}';`).join('\n');
const zhRefs = DOMAINS.map((d) => `ZH_${d.toUpperCase()}`).join(', ');
const enRefs = DOMAINS.map((d) => `EN_${d.toUpperCase()}`).join(', ');
const newI18n =
`import { SettingsStore } from '../prefs/SettingsStore';
${imports}

/**
 * 双语词条：按域拆分在 common/i18n/，此处合并；键名与原项目 src/i18n 对齐。
 * translate() 在 build 中读取 SettingsStore.locale（@Trace），语言切换即时生效。
 */

function mergeDicts(parts: Record<string, string>[]): Record<string, string> {
  const out: Record<string, string> = {};
  for (const p of parts) {
    const ks: string[] = Object.keys(p);
    for (const k of ks) {
      out[k] = p[k];
    }
  }
  return out;
}

export const zh: Record<string, string> = mergeDicts([${zhRefs}]);
export const en: Record<string, string> = mergeDicts([${enRefs}]);

export class I18n {
  static translate(key: string, params?: Record<string, string>): string {
    const locale = SettingsStore.get().locale;
    const dict = locale === 'en-US' ? en : zh;
    let text: string = dict[key] ?? zh[key] ?? key;
    if (params) {
      const keys: string[] = Object.keys(params);
      for (const k of keys) {
        text = text.split(\`{\${k}}\`).join(params[k]);
      }
    }
    return text;
  }
}
`;
fs.writeFileSync(I18N, newI18n);
console.log('I18n.ets rewritten');
