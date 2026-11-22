// i18n dead-key audit + rewrite across the split domain files (common/i18n/I18n*.ets).
// Run: node scripts/i18n_audit.mjs
import fs from 'node:fs';
import path from 'node:path';

const ROOT = path.resolve(import.meta.dirname, '..');
const I18N_DIR = path.join(ROOT, 'entry/src/main/ets/common/i18n');
const I18N = path.join(ROOT, 'entry/src/main/ets/common/I18n.ets');
const SRC = path.join(ROOT, 'entry/src');

// 1. dictionary files are the entry sources (split since i18n_split.mjs ran)
const dictFiles = fs.readdirSync(I18N_DIR)
  .filter((n) => n.endsWith('.ets'))
  .map((n) => path.join(I18N_DIR, n));
const entryStart = /^  '([^']+)':/;
const fileEntries = []; // { file, lines, entries: [{ key, start }] }
for (const f of dictFiles) {
  const lines = fs.readFileSync(f, 'utf8').split('\n');
  const entries = [];
  lines.forEach((l, i) => {
    const m = l.match(entryStart);
    if (m) {
      entries.push({ key: m[1], start: i });
    }
  });
  fileEntries.push({ file: f, lines, entries });
}

// 2. usage corpus: all .ets except the dictionaries and the merge hub I18n.ets
const dictSet = new Set([...dictFiles, I18N].map((p) => path.resolve(p)));
function walk(dir, out) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) {
      walk(p, out);
    } else if (e.name.endsWith('.ets')) {
      out.push(p);
    }
  }
  return out;
}
const others = walk(SRC, []).filter((p) => !dictSet.has(path.resolve(p)));
const corpus = others.map((p) => fs.readFileSync(p, 'utf8'));

// 3. dead keys: quoted literal never appears outside the dictionaries.
// Dynamic keys (built via template literals in LegalDocPage) are allowlisted.
const DYNAMIC_PREFIXES = [
  'privacyPolicySection',
  'agreementSection',
  'aiInfoSection',
  'reportSection',
];
const isDynamic = (k) => DYNAMIC_PREFIXES.some((p) => k.startsWith(p));
const uniqueKeys = new Set();
for (const fe of fileEntries) {
  for (const e of fe.entries) {
    uniqueKeys.add(e.key);
  }
}
const dead = [];
for (const k of uniqueKeys) {
  if (isDynamic(k)) {
    continue;
  }
  const needle = `'${k}'`;
  if (!corpus.some((text) => text.includes(needle))) {
    dead.push(k);
  }
}
console.log(`total unique keys: ${uniqueKeys.size}`);
console.log(`dead keys: ${dead.length}`);
for (const k of dead) {
  console.log(`  - ${k}`);
}

// 4. rewrite: drop dead entry lines (entry start until next entry or map close)
const deadSet = new Set(dead);
let removed = 0;
for (const fe of fileEntries) {
  const drop = new Set();
  for (let i = 0; i < fe.entries.length; i++) {
    if (!deadSet.has(fe.entries[i].key)) {
      continue;
    }
    const end = i + 1 < fe.entries.length ? fe.entries[i + 1].start : fe.lines.length;
    for (let j = fe.entries[i].start; j < end; j++) {
      if (fe.lines[j].startsWith('};')) {
        break;
      }
      drop.add(j);
    }
  }
  if (drop.size === 0) {
    continue;
  }
  fs.writeFileSync(fe.file, fe.lines.filter((_, i) => !drop.has(i)).join('\n'));
  console.log(`${path.basename(fe.file)}: removed ${drop.size} lines`);
  removed += drop.size;
}
console.log(`removed lines: ${removed}`);
