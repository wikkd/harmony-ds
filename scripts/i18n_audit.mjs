// One-shot i18n dead-key audit + rewrite. Run: node scripts/i18n_audit.mjs
import fs from 'node:fs';
import path from 'node:path';

const ROOT = path.resolve(import.meta.dirname, '..');
const I18N = path.join(ROOT, 'entry/src/main/ets/common/I18n.ets');
const SRC = path.join(ROOT, 'entry/src');

const src = fs.readFileSync(I18N, 'utf8');
const lines = src.split('\n');

// 1. parse entries: line starts with two-space + quote
const entryStart = /^  '([^']+)':/;
const entries = []; // {key, start}
lines.forEach((l, i) => {
  const m = l.match(entryStart);
  if (m) {
    entries.push({ key: m[1], start: i });
  }
});

// 2. collect all other .ets sources
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
const others = walk(SRC, []).filter((p) => path.resolve(p) !== path.resolve(I18N));
const corpus = others.map((p) => [p, fs.readFileSync(p, 'utf8')]);

// 3. find dead keys: quoted literal never appears outside I18n.ets
const dead = [];
for (const e of entries) {
  const needle = `'${e.key}'`;
  const used = corpus.some(([, text]) => text.includes(needle));
  if (!used) {
    dead.push(e.key);
  }
}
const deadSet = new Set(dead);
console.log(`total unique keys: ${new Set(entries.map((e) => e.key)).size}`);
console.log(`dead keys: ${dead.length}`);

// 4. rewrite: drop lines of dead entries (start line + continuations until next entry/map close)
const drop = new Set();
for (let i = 0; i < entries.length; i++) {
  if (!deadSet.has(entries[i].key)) {
    continue;
  }
  const end = i + 1 < entries.length ? entries[i + 1].start : lines.length;
  for (let j = entries[i].start; j < end; j++) {
    if (lines[j].startsWith('};')) {
      break;
    }
    drop.add(j);
  }
}
const out = lines.filter((_, i) => !drop.has(i)).join('\n');
fs.writeFileSync(I18N, out);
console.log(`removed lines: ${drop.size}`);
for (const k of dead) {
  console.log(`  - ${k}`);
}
