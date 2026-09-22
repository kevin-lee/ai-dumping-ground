#!/usr/bin/env node
// build.mjs - assemble the single-file report from the template, meta.json, the manifest, and fragments.
//
//   node build.mjs --work <workdir> --template <template.html> --out <report.html>
//
// The build is the only thing that writes the report. Fix content in the fragments or the manifest
// and rebuild, never edit the output by hand.

import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'node:fs';
import { join, dirname, basename } from 'node:path';
import { homedir } from 'node:os';
import { createHash } from 'node:crypto';

function arg(name) {
  const i = process.argv.indexOf(name);
  return i !== -1 ? process.argv[i + 1] : undefined;
}
function fail(msg) { process.stderr.write(`build: ${msg}\n`); process.exit(1); }

const work = arg('--work'), templatePath = arg('--template'), outPath = arg('--out');
if (!work || !templatePath || !outPath) fail('usage: build.mjs --work <workdir> --template <template.html> --out <report.html>');

const meta = JSON.parse(readFileSync(join(work, 'meta.json'), 'utf8'));
const manifestPath = join(work, 'content', 'manifest.json');
if (!existsSync(manifestPath)) fail(`missing ${manifestPath}`);
const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));
let template = readFileSync(templatePath, 'utf8');

// Named palettes for the switch, read next to the template at build time. The output never references this file.
const palettesPath = join(dirname(templatePath), 'palettes.json');
if (!existsSync(palettesPath)) fail(`missing ${palettesPath}`);
let NAMED;
try { NAMED = JSON.parse(readFileSync(palettesPath, 'utf8')); } catch (e) { fail(`cannot parse ${palettesPath}: ${e.message}`); }
const COLOR_KEYS = ['accentLight', 'accentDark', 'paperLight', 'paperDark'];
if (!NAMED || typeof NAMED !== 'object' || Array.isArray(NAMED) || !Object.keys(NAMED).length) fail(`${palettesPath} must be an object with at least one palette`);
for (const [n, p] of Object.entries(NAMED)) {
  if (!/^[a-z][a-z0-9-]*$/.test(n) || n === 'default') fail(`palettes.json key "${n}" must match ^[a-z][a-z0-9-]*$ and cannot be "default"`);
  for (const k of COLOR_KEYS) if (!p || !/^#[0-9A-Fa-f]{6}$/.test(p[k] || '')) fail(`palettes.json "${n}".${k} must be a #RRGGBB color`);
}

// Themes for the switch: the four inputs plus a full token list for light and dark, read next to the template at build time.
const themesPath = join(dirname(templatePath), 'themes.json');
if (!existsSync(themesPath)) fail(`missing ${themesPath}`);
let THEMES;
try { THEMES = JSON.parse(readFileSync(themesPath, 'utf8')); } catch (e) { fail(`cannot parse ${themesPath}: ${e.message}`); }
if (!THEMES || typeof THEMES !== 'object' || Array.isArray(THEMES)) fail(`${themesPath} must be an object`);
const THEME_TOKENS = ['ink', 'ink-2', 'muted', 'accent-ink', 'ground', 'surface', 'surface-2', 'code-bg', 'ok', 'ok-soft', 'warn', 'warn-soft', 'alert', 'alert-soft', 'nodata', 'nodata-soft', 'add-bg', 'add-ink', 'add-mark', 'del-bg', 'del-ink', 'del-mark', 'hit-ink', 'sy-comment', 'sy-keyword', 'sy-string', 'sy-number', 'sy-name'];
for (const [n, t] of Object.entries(THEMES)) {
  if (!/^[a-z][a-z0-9-]*$/.test(n) || n === 'default') fail(`themes.json key "${n}" must match ^[a-z][a-z0-9-]*$ and cannot be "default"`);
  if (NAMED[n]) fail(`themes.json key "${n}" is also in palettes.json`);
  if (!t || typeof t.label !== 'string' || !t.label.trim()) fail(`themes.json "${n}".label must be a non-empty string`);
  for (const k of COLOR_KEYS) if (!/^#[0-9A-Fa-f]{6}$/.test(t[k] || '')) fail(`themes.json "${n}".${k} must be a #RRGGBB color`);
  for (const mode of ['light', 'dark']) {
    const tokens = t[mode];
    if (!tokens || typeof tokens !== 'object' || Array.isArray(tokens)) fail(`themes.json "${n}".${mode} must be an object`);
    const missing = THEME_TOKENS.filter((k) => !(k in tokens));
    if (missing.length) fail(`themes.json "${n}".${mode} is missing ${missing.join(', ')}`);
    const unknown = Object.keys(tokens).filter((k) => !THEME_TOKENS.includes(k));
    if (unknown.length) fail(`themes.json "${n}".${mode} has unknown ${unknown.join(', ')}`);
    for (const k of THEME_TOKENS) if (!/^#[0-9A-Fa-f]{6}$/.test(tokens[k])) fail(`themes.json "${n}".${mode}.${k} must be a #RRGGBB color`);
  }
}

// ---------- Vendor: syntax highlighting ----------
// Prism is downloaded once per machine into the cache, verified against pinned checksums, and inlined into the page.
// The skill never carries the library. Without network and cache the report builds without syntax colors.
const PRISM_VERSION = '1.30.0';
const VENDOR_BASES = process.env.PR_ANALYSIS_VENDOR_BASE
  ? [process.env.PR_ANALYSIS_VENDOR_BASE.replace(/\/?$/, '/')]
  : [`https://cdn.jsdelivr.net/npm/prismjs@${PRISM_VERSION}/`, `https://unpkg.com/prismjs@${PRISM_VERSION}/`];
const CACHE_DIR = process.env.PR_ANALYSIS_CACHE || join(homedir(), '.cache', 'pr-analysis');
const vendorDir = join(CACHE_DIR, 'vendor', `prismjs@${PRISM_VERSION}`);
// Every file is components/prism-<id>.min.js from the prismjs npm package. requires are Prism's own (from components.json).
const grammar = (sha256, requires) => ({ sha256, requires: requires || [] });
const PRISM = {
  core: grammar('6caad316dd991f24f8004e0b9c19c055cb5829ff65e973fbee406f96d81b8e7e'),
  clike: grammar('c76ba4e240932bdc75546be30e550f5ba5e13815ff71511c76e9e27ac3072444'),
  c: grammar('9e05cf21207bff46afbf80cb8f43bb58bc4a4a87b68f28bc0470342f69345209', ['clike']),
  cpp: grammar('12077d9ea67882c149066e94843a6ede9036994b3724bfc45b31d97619328e14', ['c']),
  csharp: grammar('f4eca14394e584a4a3a747fe6dc0a93ddbc657880f7dbac3f8d119ccb206107e', ['clike']),
  javascript: grammar('0345ea83e12b7b974e953c79a64dea35a40308309449db70b82020fb688ac321', ['clike']),
  typescript: grammar('852f5513bb9ca9db247f86ecfce74acc91c541749d34929157240518fef8152a', ['javascript']),
  jsx: grammar('0c8b80e4d98f6813ef95fd0e7ae2862cc0804ec305e0ad1f99c0a4bb7c28f865', ['markup', 'javascript']),
  tsx: grammar('752c15ed4ff1d03e042b407b332892e1097d5f5e348861e2e26db20d71b349bf', ['jsx', 'typescript']),
  java: grammar('4c2dc81dfc9efa51e38a7573938065288c63c64850f01a32f8a7b20a3e24c5a7', ['clike']),
  kotlin: grammar('68c1ddff0d10147c006688289c310ccbfb5283c8687b4bcb9bf7bc9bbdf9f41c', ['clike']),
  scala: grammar('2b73d569dc4cd469bce912291cd285819e8798f20c7ca56b16b40e6ffc737a24', ['java']),
  groovy: grammar('23797a1e79b83c0216c7ca025671b1d8575305b13ce22b64aa3d2a96b4a3b5ef', ['clike']),
  bash: grammar('6260814110e5182f2956e3bd257429548d9dbf2a9b66a63719b26cf9fac966a7'),
  sql: grammar('3fc5f8ce69950ec73adc972f061df42aaea78faa4864709134ea2adc083f3a33'),
  json: grammar('956d86baa5ae7ec4106758f354ac2d140bdcd7fc103dece02f73ed12b8d663e4'),
  yaml: grammar('719c8e8b8c344dc9de510c729f65ba840b1502a0a8e7e25e2ad19ee715f65c02'),
  toml: grammar('bc71428fec2670d59cda5ad3359615c91892f914f526cf6bfe316fc2ad55aff2'),
  ini: grammar('cf1b61f4a67f0101005c5133e22113e2f3a74f1c7917034e084df688f1735381'),
  properties: grammar('3272abb494806e743c8be4ee9220362c9c06a7282320198ca0bbd365cd8be147'),
  markdown: grammar('9f1166a087d9a9ffb3a833f2bccbe00920b55b41ade02a0b3054b7ab5fbc70ea', ['markup']),
  markup: grammar('879fc9d256c352d980e053857fa707330853b8bfb67ce284ea661a24dec5756e'),
  css: grammar('8c9760dba7f26ea842016919544dd9b73a78a36d5b07a1e9842c333ed18ab6ae'),
  scss: grammar('149a0fb3381c07a609cd671fd14958d1737c6ec1682deafd0b6d2018df9e5c91', ['css']),
  python: grammar('ed4385685bcf2d4935c8dbbab4bde16603da1329e092d2bf36c3dadd67e9a85c'),
  go: grammar('1225b4afb593126d4082da5fd2b131aede39831c2b2a62d6b07ea025acd2bf3f', ['clike']),
  rust: grammar('8ca261bb964333c717703059de8ff81e80a75d52c637913ef6f982da1ee82acb'),
  ruby: grammar('2511dcef4c4c79f8be63fcdcd56af9be91406a5ed192065da3713ab45bdb97b2', ['clike']),
  swift: grammar('69c8a062618949fbc7b69989ab7fb2b7bc111b28ea329e53713c7a2885614b20'),
  lua: grammar('f6ca280a77564667cc1006e59e31e338b01eee0ef840ae02a9bd5a0fc5ea4553'),
  makefile: grammar('4c1c05235779d4bff287b9ffc71dfb7dc10157c1a89bc49e0de2adb59d3635ee'),
  docker: grammar('a6cc0faa5977a40652f62798a692a5ae171e0380480df3ed056e117597ec52dd'),
  diff: grammar('f16816fb2242a84c6ff6715a48c6d0a3e469e3250912cb9f1b755ca537d02f48'),
  graphql: grammar('04519bfa04631ce1f85533803a510d594763c2b9ab5c13d209cfeb3b300ef355'),
  protobuf: grammar('7d1620ec30c379b432c631efa55acc14ddafda724aa4f19cb1993306ccd9b35f', ['clike']),
  hcl: grammar('6c8bc9ea13f7ad08648eb2ffdda99d5ed674844220b2b4757aeb19d06fc78b18')
};
for (const [id, entry] of Object.entries(PRISM)) entry.file = `components/prism-${id}.min.js`;
const LANG_BY_EXT = {};
for (const [id, exts] of Object.entries({
  scala: 'scala sbt sc', kotlin: 'kt kts', java: 'java', groovy: 'groovy gradle', javascript: 'js mjs cjs', jsx: 'jsx',
  typescript: 'ts mts cts', tsx: 'tsx', bash: 'sh bash zsh', sql: 'sql', json: 'json webmanifest', yaml: 'yml yaml', toml: 'toml',
  ini: 'ini cfg', properties: 'properties', markdown: 'md markdown', markup: 'html htm xml svg xhtml', css: 'css', scss: 'scss',
  python: 'py', go: 'go', rust: 'rs', ruby: 'rb', swift: 'swift', lua: 'lua', makefile: 'mk', diff: 'diff patch', graphql: 'graphql gql',
  protobuf: 'proto', hcl: 'tf hcl', c: 'c h', cpp: 'cpp cc cxx hpp hh', csharp: 'cs'
})) for (const e of exts.split(' ')) LANG_BY_EXT[e] = id;
const langByName = (name) => /^Dockerfile(\.|$)/.test(name) ? 'docker' : (name === 'Makefile' || name === 'GNUmakefile' ? 'makefile' : null);
function langFor(path) {
  const name = basename(path);
  const byName = langByName(name);
  if (byName) return byName;
  const dot = name.lastIndexOf('.');
  if (dot === -1) return null;
  return LANG_BY_EXT[name.slice(dot + 1).toLowerCase()] || null;
}
const noHighlight = process.argv.includes('--no-highlight');

const escHtml = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const jsStr = (s) => JSON.stringify(String(s));

// ---------- Manifest validation ----------
const errors = [];
const kinds = manifest.kinds || {};
const groups = manifest.groups || [];
const blocks = manifest.blocks || [];
const lang2 = manifest.lang2 || null;
const langMode = manifest.langMode === 'both' ? 'both' : 'single';
if (langMode === 'both' && !lang2) errors.push('langMode "both" needs lang2');
const tones = new Set(['ok', 'warn', 'alert', 'nodata', 'accent']);
for (const [k, v] of Object.entries(kinds)) {
  if (!/^[a-z0-9-]+$/.test(k)) errors.push(`kind key "${k}" must match ^[a-z0-9-]+$`);
  if (!tones.has(v.tone)) errors.push(`kind "${k}" has unknown tone "${v.tone}"`);
  if (!v.glyph) errors.push(`kind "${k}" needs a glyph`);
  if (!v.en) errors.push(`kind "${k}" needs an en label`);
}
const groupKeys = new Set(groups.map((g) => g.key));
const seenKeys = new Set();
for (const b of blocks) {
  if (!/^[a-z0-9-]+$/.test(b.key || '')) errors.push(`block key "${b.key}" must match ^[a-z0-9-]+$`);
  if (seenKeys.has(b.key)) errors.push(`duplicate block key "${b.key}"`);
  seenKeys.add(b.key);
  const f = meta.files[b.fileIndex];
  if (!f) errors.push(`block "${b.key}" points at fileIndex ${b.fileIndex} which does not exist`);
  else if (f.binary) errors.push(`block "${b.key}" points at binary file ${f.path}`);
  if (b.group && !groupKeys.has(b.group)) errors.push(`block "${b.key}" names unknown group "${b.group}"`);
  for (const k of b.kinds || []) if (!kinds[k]) errors.push(`block "${b.key}" names unknown kind "${k}"`);
  if (!b.en) errors.push(`block "${b.key}" needs an en heading`);
}
for (const g of groups) {
  const reps = blocks.filter((b) => b.group === g.key && b.rep);
  if (reps.length > 1) errors.push(`group "${g.key}" has ${reps.length} representatives, at most one is allowed`);
}
const required = ['header-lede.html', 'findings.html', 'changes-intro.html', 'verification.html', 'followup.html', 'footer.html'];
const fragDir = join(work, 'content');
function fragment(name, optional) {
  if (!name) return '';
  const p = join(fragDir, name);
  if (!existsSync(p)) { if (optional) return ''; errors.push(`missing fragment ${name}`); return ''; }
  return readFileSync(p, 'utf8').trim();
}
for (const r of required) if (!existsSync(join(fragDir, r))) errors.push(`missing required fragment ${r}`);
if (errors.length) fail('\n  ' + errors.join('\n  '));

// ---------- Fragment post-processing ----------
const glyphOf = (k) => kinds[k] ? kinds[k].glyph : '';
function decorate(html) {
  if (!html) return html;
  // data-glyph on kind chips and finding bars that lack it
  html = html.replace(/<(span|div)([^>]*?)class="((?:kind|bar)(?:\s+[^"]*)?)"([^>]*)>/g, (m, tag, pre, cls, post) => {
    if (/data-glyph=/.test(pre + post)) return m;
    const key = cls.split(/\s+/).find((c) => kinds[c]);
    if (!key) return m;
    return `<${tag}${pre}class="${cls}"${post} data-glyph="${escHtml(glyphOf(key))}">`;
  });
  // lang attribute on second-language elements
  if (lang2) {
    html = html.replace(/<([a-z][a-z0-9]*)([^>]*?)class="([^"]*\bl2\b[^"]*)"([^>]*)>/g, (m, tag, pre, cls, post) => {
      if (/\slang=/.test(pre + post)) return m;
      return `<${tag}${pre}class="${cls}"${post} lang="${escHtml(lang2)}">`;
    });
  }
  return html;
}
function l2Present(html) { return /class="[^"]*\bl2\b[^"]*"/.test(html); }

const frags = {};
for (const r of required) frags[r] = decorate(fragment(r));
const optionalNames = [];
if (manifest.sections && manifest.sections.mechanism) optionalNames.push('mechanism.html');
if (manifest.sections && manifest.sections.fromPr) optionalNames.push('from-pr.html');
for (const g of groups) if (g.calloutFragment) optionalNames.push(g.calloutFragment);
for (const b of blocks) if (b.notesFragment) optionalNames.push(b.notesFragment);
for (const x of (manifest.sections && manifest.sections.extra) || []) optionalNames.push(x.fragment);
for (const n of optionalNames) frags[n] = decorate(fragment(n, false));
if (errors.length) fail('\n  ' + errors.join('\n  '));
if (!lang2) {
  for (const [n, h] of Object.entries(frags)) if (l2Present(h)) errors.push(`fragment ${n} contains class="l2" but the report is English only`);
  if (errors.length) fail('\n  ' + errors.join('\n  '));
}

// ---------- Bilingual helpers ----------
function pair(en, l2, inline) {
  if (!lang2 || !l2) return escHtml(en);
  return `<span class="en">${escHtml(en)}</span><span class="l2" lang="${escHtml(lang2)}">${escHtml(l2)}</span>`;
}

// ---------- Identity ----------
const pr = meta.pr;
const ticketLabel = meta.ticketLabelOverride || (manifest.ticket && manifest.ticket.label) || (meta.ticket && meta.ticket.id) || '';
const ticketUrl = (manifest.ticket && manifest.ticket.url) || (meta.ticket && meta.ticket.url) || '';
const railTitle = ticketLabel || `PR #${pr.number}`;
const ticketHtml = ticketLabel
  ? (ticketUrl ? `<a href="${escHtml(ticketUrl)}">${escHtml(ticketLabel)}</a>` : `<span>${escHtml(ticketLabel)}</span>`) + '\n        <span aria-hidden="true">·</span>'
  : '';
const storagePrefix = `pr-analysis.${meta.repo.nameWithOwner}#${pr.number}.`;

// ---------- Kinds CSS ----------
const kindsCss = Object.entries(kinds).map(([k, v]) => {
  const soft = v.tone === 'accent' ? 'var(--accent-soft)' : `var(--${v.tone}-soft)`;
  const main = v.tone === 'accent' ? 'var(--accent)' : `var(--${v.tone})`;
  return `  .kind.${k} { background: ${soft}; color: ${main}; }\n  .kind-dot.${k} { color: ${main}; }\n  .finding .bar.${k} { background: ${main}; }`;
}).join('\n');

// ---------- Vendor resolution: which grammars this PR needs, from the cache or a mirror ----------
const wanted = new Set();
for (const b of blocks) { const l = langFor(meta.files[b.fileIndex].path); if (l) wanted.add(l); }
const needed = ['core'];
const addNeeded = (id) => { if (needed.includes(id)) return; for (const r of PRISM[id].requires) addNeeded(r); needed.push(id); };
for (const id of wanted) addNeeded(id);
let hl = !noHighlight && wanted.size > 0;
let hlReason = noHighlight ? '--no-highlight' : (wanted.size ? '' : 'no file type with a grammar');
const sha256 = (text) => createHash('sha256').update(text).digest('hex');
async function loadVendor(id) {
  const entry = PRISM[id];
  const cachePath = join(vendorDir, basename(entry.file));
  if (existsSync(cachePath)) {
    const text = readFileSync(cachePath, 'utf8');
    if (sha256(text) === entry.sha256) return { text, source: 'cached' };
  }
  const reasons = [];
  for (const base of VENDOR_BASES) {
    const url = base + entry.file;
    try {
      const res = await fetch(url, { signal: AbortSignal.timeout(20000) });
      if (!res.ok) { reasons.push(`${url}: HTTP ${res.status}`); continue; }
      const text = await res.text();
      if (sha256(text) !== entry.sha256) { reasons.push(`${url}: hash mismatch`); continue; }
      mkdirSync(vendorDir, { recursive: true });
      writeFileSync(cachePath, text);
      return { text, source: 'downloaded' };
    } catch (e) {
      reasons.push(`${url}: ${e.name === 'TimeoutError' ? 'timeout' : ((e.cause && e.cause.message) || e.message)}`);
    }
  }
  throw new Error(`${id}: ${reasons.join(', ')}`);
}
const vendorTexts = [];
let downloaded = 0, cached = 0;
if (hl) {
  try {
    for (const id of needed) {
      const r = await loadVendor(id);
      vendorTexts.push(r.text);
      if (r.source === 'downloaded') downloaded++; else cached++;
    }
  } catch (e) {
    hl = false;
    hlReason = e.message;
    process.stderr.write(`build: WARNING syntax highlighting skipped: ${hlReason}. The page builds without syntax colors.\n`);
  }
}
const langIds = needed.filter((id) => id !== 'core');
const vendorJs = hl
  ? [
    'window.Prism = { manual: true, disableWorkerMessageHandler: true };',
    `/* pr-analysis vendor: prism ${PRISM_VERSION}, languages: ${langIds.join(',')} */`,
    `/* Prism ${PRISM_VERSION} (MIT) https://prismjs.com  Copyright (c) 2012 Lea Verou */`,
    ...vendorTexts.map((t) => t + '\n;')
  ].join('\n')
  : `/* syntax colors off: ${hlReason.replace(/\*\//g, '* /')} */`;
const hlFlag = hl ? 'on' : 'off';

// ---------- Blocks and groups ----------
function sliceLines(text, range) {
  if (!range) return text;
  const [s, e] = range;
  if (s === 0 && e === 0) return '';
  const lines = text.split('\n');
  return lines.slice(s - 1, e).join('\n');
}
// Optional redaction rules, applied to embedded text only. check.mjs applies the same rules before comparing with git.
const redactRules = Array.isArray(manifest.redact) ? manifest.redact : [];
for (const r of redactRules) if (!r.pattern || typeof r.replacement !== 'string') fail('each redact rule needs pattern and replacement');
function redact(text) {
  let out = text;
  for (const r of redactRules) out = out.replace(new RegExp(r.pattern, r.flags || 'g'), r.replacement);
  return out;
}
function readFile(idx, side) {
  const p = join(work, 'files', `${idx}.${side}`);
  return existsSync(p) ? redact(readFileSync(p, 'utf8')) : '';
}
const statusWord = { A: 'Added', M: 'Modified', D: 'Deleted', R: 'Renamed', C: 'Copied', T: 'Type changed' };
const BLOCKS = {};
const blockHtml = new Map();
for (const b of blocks) {
  const f = meta.files[b.fileIndex];
  const beforeFull = readFile(b.fileIndex, 'before');
  const afterFull = readFile(b.fileIndex, 'after');
  const before = b.range ? sliceLines(beforeFull, b.range.before) : beforeFull;
  const after = b.range ? sliceLines(afterFull, b.range.after) : afterFull;
  BLOCKS[b.key] = {
    file: f.path, group: b.group || null, rep: !!b.rep, status: f.status,
    before, after,
    startBefore: b.range && b.range.before[0] > 0 ? b.range.before[0] : 1,
    startAfter: b.range && b.range.after[0] > 0 ? b.range.after[0] : 1,
    lang: hl ? langFor(f.path) : null
  };
  const fileUrl = f.status === 'D' ? `${meta.repo.url}/blob/${meta.mergeBase}/${f.oldPath || f.path}` : `${meta.repo.url}/blob/${meta.headSha}/${f.path}`;
  const chips = (b.kinds || []).map((k) => `<span class="kind ${k}" data-glyph="${escHtml(kinds[k].glyph)}">${pair(kinds[k].en, kinds[k].l2)}</span>`).join('\n            ');
  const rangeNote = b.range ? `<span class="status filestat">lines ${b.range.before[0]}–${b.range.before[1]} → ${b.range.after[0]}–${b.range.after[1]}</span>` : '';
  const notes = b.notesFragment ? frags[b.notesFragment] : '';
  blockHtml.set(b.key, `      <details class="block" id="b-${b.key}" open>
        <summary>
          <div class="name">
            <span class="module"><a href="${escHtml(fileUrl)}">${escHtml(f.path)}</a>${f.oldPath && f.oldPath !== f.path ? ` <span class="arrow">(was ${escHtml(f.oldPath)})</span>` : ''}</span>
            <h3>${pair(b.en, b.l2)}</h3>
          </div>
          <svg class="chev" viewBox="0 0 20 20" aria-hidden="true"><path d="M7 4l6 6-6 6" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>
          <div class="meta">
            ${chips}
            <span class="status filestat">${statusWord[f.status] || f.status}</span>
            ${rangeNote}
            <span class="status lines" data-lines="${b.key}"></span>
            <span class="ident pending" data-ident="${b.key}"></span>
          </div>
        </summary>
        <div class="body">
${notes ? notes.split('\n').map((l) => '          ' + l).join('\n') + '\n' : ''}          <div class="diff" data-block="${b.key}"></div>
        </div>
      </details>`);
}

const emittedGroups = new Set();
const changesParts = [];
const tocParts = [];
const dot = (k) => `<span class="kind-dot ${k}" data-glyph="${escHtml(kinds[k].glyph)}" title="${escHtml(kinds[k].en)}"></span>`;
// Short labels for the table of contents: the file's base name when unique, the full path otherwise,
// plus the after-side line range when a file is split into several blocks.
const baseName = (p) => p.split('/').pop();
const baseCounts = new Map();
for (const b of blocks) { const n = baseName(meta.files[b.fileIndex].path); baseCounts.set(n, (baseCounts.get(n) || 0) + 1); }
const blocksPerFile = new Map();
for (const b of blocks) blocksPerFile.set(b.fileIndex, (blocksPerFile.get(b.fileIndex) || 0) + 1);
const tocLabel = (b) => {
  const path = meta.files[b.fileIndex].path;
  const bn = baseName(path);
  const sameBase = [...new Set(blocks.filter((x) => baseName(meta.files[x.fileIndex].path) === bn).map((x) => x.fileIndex))].length > 1;
  let label = sameBase ? path : bn;
  if (b.range && blocksPerFile.get(b.fileIndex) > 1) label += ` L${b.range.after[0]}-${b.range.after[1]}`;
  return label;
};
const groupCount = (members) => {
  const paths = [...new Set(members.map((m) => meta.files[m.fileIndex].path))];
  if (paths.length === 1 && members.length > 1) return `${members.length} blocks`;
  return `${paths.length} file${paths.length === 1 ? '' : 's'}`;
};
// The member files, linked to their blocks, listed under the heading rather than inside it
const groupFiles = (members) => members.map((m) => `<li><a href="#b-${m.key}" title="${escHtml(meta.files[m.fileIndex].path)}">${escHtml(tocLabel(m))}</a></li>`).join('\n          ');
for (const b of blocks) {
  if (b.group && !emittedGroups.has(b.group)) {
    emittedGroups.add(b.group);
    const g = groups.find((x) => x.key === b.group);
    const members = blocks.filter((x) => x.group === g.key);
    changesParts.push(`      <div class="group-intro">
        <h3 class="group-head" id="g-${g.key}">
          <span>${pair(g.en, g.l2)}</span>
          <span class="count">${groupCount(members)}</span>
        </h3>
        <ul class="group-files" aria-label="Files in this group">
          ${groupFiles(members)}
        </ul>
      </div>`);
    if (g.calloutFragment) changesParts.push(frags[g.calloutFragment].split('\n').map((l) => '      ' + l).join('\n'));
    tocParts.push(`      <a href="#g-${g.key}" class="sub group"><span>${pair(g.en, g.l2)}</span></a>`);
    for (const m of members) {
      changesParts.push(blockHtml.get(m.key));
      tocParts.push(`      <a href="#b-${m.key}" class="sub file"><span class="dots">${(m.kinds || []).map(dot).join('')}</span><span>${escHtml(tocLabel(m))}</span></a>`);
    }
  } else if (!b.group) {
    changesParts.push(blockHtml.get(b.key));
    tocParts.push(`      <a href="#b-${b.key}" class="sub file"><span class="dots">${(b.kinds || []).map(dot).join('')}</span><span>${escHtml(tocLabel(b))}</span></a>`);
  }
}

// ---------- TOC ----------
const extras = (manifest.sections && manifest.sections.extra) || [];
const toc = [];
toc.push(`      <a href="#findings"><span>Findings</span></a>`);
if (manifest.sections && manifest.sections.mechanism) toc.push(`      <a href="#mechanism"><span>Mechanism</span></a>`);
toc.push(`      <a href="#changes"><span>Changes</span></a>`);
toc.push(...tocParts);
if (manifest.sections && manifest.sections.fromPr) toc.push(`      <a href="#from-pr"><span>Quoted from the PR</span></a>`);
toc.push(`      <a href="#verification"><span>Verification</span></a>`);
for (const x of extras) toc.push(`      <a href="#${escHtml(x.id)}"><span>${pair(x.en, x.l2)}</span></a>`);
toc.push(`      <a href="#followup"><span>Follow-up</span></a>`);
toc.push(`      <a href="#commits"><span>Commits</span></a>`);

// ---------- Sections ----------
function section(id, heading, body, extraClass) {
  return `    <section id="${escHtml(id)}"${extraClass ? ` class="${extraClass}"` : ''}>
      <div class="section-head">
        <h2>${heading}</h2>
      </div>
${body.split('\n').map((l) => '      ' + l).join('\n')}
    </section>`;
}
const mechanism = manifest.sections && manifest.sections.mechanism ? section('mechanism', 'Mechanism', frags['mechanism.html']) : '';
const fromPr = manifest.sections && manifest.sections.fromPr ? section('from-pr', 'Quoted from the PR', frags['from-pr.html']) : '';
const extraSections = extras.map((x) => {
  if (!/^[a-z][a-z0-9-]*$/.test(x.id)) fail(`extra section id "${x.id}" must match ^[a-z][a-z0-9-]*$`);
  return section(x.id, pair(x.en, x.l2), frags[x.fragment]);
}).join('\n\n');

const statTiles = (manifest.statTiles || []).map((t) => {
  const tone = ['grey', 'ok', 'warn', 'bad'].includes(t.tone) ? t.tone : 'grey';
  const label = lang2 && t.l2 ? `<span class="l en">${escHtml(t.en)}</span><span class="l l2" lang="${escHtml(lang2)}">${escHtml(t.l2)}</span>` : `<span class="l">${escHtml(t.en)}</span>`;
  return `        <div class="stat" role="listitem">
          <span class="n ${tone}">${escHtml(t.n)}</span>
          ${label}
        </div>`;
}).join('\n');

// Commits: table plus collapsible full messages
const commitRows = meta.commits.map((c) => `        <tr>
          <td class="sha"><a href="${escHtml(c.url)}">${escHtml(c.sha7)}</a></td>
          <td>${escHtml(c.headline)}</td>
          <td class="who">${c.authors.map((a) => `<a href="${escHtml(meta.repo.host)}/${escHtml(a)}">@${escHtml(a)}</a>`).join(', ') || '<span class="same">unknown</span>'}</td>
        </tr>`).join('\n');
const commitMsgs = meta.commits.map((c, i) => {
  const p = join(work, 'commits', `${c.sha7}.txt`);
  const msg = existsSync(p) ? readFileSync(p, 'utf8').replace(/\n+$/, '') : c.headline;
  const [subject, ...rest] = msg.split('\n');
  const body = rest.join('\n').replace(/^\n+/, '');
  return `        <details class="commit"${meta.commits.length === 1 ? ' open' : ''}>
          <summary><code>${escHtml(c.sha7)}</code> ${escHtml(subject)}</summary>
          <button type="button" class="copy" data-copy-target="commit-text-${escHtml(c.sha7)}">Copy</button>
          <pre id="commit-text-${escHtml(c.sha7)}"><span class="subject">${escHtml(subject)}</span>${body ? '\n\n' + escHtml(body) : ''}</pre>
        </details>`;
}).join('\n');
const commits = `      <div class="table-scroll">
      <table class="commits-table">
        <caption class="sr-only">Commits in this pull request</caption>
        <thead><tr><th scope="col">Commit</th><th scope="col">Subject</th><th scope="col">Author</th></tr></thead>
        <tbody>
${commitRows}
        </tbody>
      </table>
      </div>
      <div class="commit-msgs">
${commitMsgs}
      </div>`;

// Diff head label and whitespace labels
const labels = manifest.labels || {};
const baseLink = `<a href="${escHtml(meta.baseUrl)}">${escHtml(pr.baseRefName)} (${escHtml(meta.baseShort)})</a>`;
const headLink = `<a href="${escHtml(meta.headUrl)}">PR #${pr.number} (${escHtml(meta.headShort)})</a>`;
let diffHead = labels.diffHeadEn ? escHtml(labels.diffHeadEn) : `${baseLink} → ${headLink}`;
if (lang2 && labels.diffHeadL2) diffHead = `<span class="en">${diffHead}</span><span class="l2" lang="${escHtml(lang2)}">${escHtml(labels.diffHeadL2)}</span>`;
const wsLabelEn = labels.wsEn || 'Ignore whitespace-only changes';
const wsLabelL2 = lang2 && labels.wsL2 ? `<span class="l2" lang="${escHtml(lang2)}">${escHtml(labels.wsL2)}</span>` : '';
const wsTag = labels.wsTag || 'ws';

// ---------- Palette and dark token duplication ----------
const defines = {};
template = template.replace(/\/\*@define (\w+)\n([\s\S]*?)@end\*\/\n?/g, (m, name, body) => { defines[name] = body.replace(/\n$/, ''); return ''; });
const palette = { ...(manifest.palette || {}) };
if (palette.name) {
  const source = NAMED[palette.name] || THEMES[palette.name];
  if (!source) fail(`manifest.palette.name "${palette.name}" is not in palettes.json or themes.json (${[...Object.keys(NAMED), ...Object.keys(THEMES)].join(', ')})`);
  if (COLOR_KEYS.some((k) => k in palette)) fail('manifest.palette.name cannot be combined with accentLight, accentDark, paperLight, paperDark');
  for (const k of COLOR_KEYS) palette[k] = source[k];
}
for (const k of ['accentLight', 'accentDark', 'paperLight', 'paperDark', 'fontDisplay', 'fontBody', 'fontMono', 'fontsHref']) {
  if (!palette[k]) fail(`manifest.palette.${k} is required`);
}
if (!/^https:\/\/fonts\.googleapis\.com\//.test(palette.fontsHref)) fail('palette.fontsHref must be a fonts.googleapis.com URL');

// The report's own palette is the default. A named pastel with the same four values is labeled as the default instead of listed twice.
// A theme is the default only when the manifest names it: a brief with the same four values asked for less than the full theme.
const norm = (h) => String(h).toUpperCase();
const defaultName = palette.name && THEMES[palette.name]
  ? palette.name
  : (Object.keys(NAMED).find((n) => COLOR_KEYS.every((k) => norm(NAMED[n][k]) === norm(palette[k]))) || null);
const cap = (s) => s.charAt(0).toUpperCase() + s.slice(1);
const swatchRule = (n, p) => `  .swatch[data-palette-btn="${n}"] { --sw-accent-light: ${p.accentLight}; --sw-accent-dark: ${p.accentDark}; --sw-paper-light: ${p.paperLight}; --sw-paper-dark: ${p.paperDark}; }`;
const namedOthers = Object.keys(NAMED).filter((n) => n !== defaultName);
const themeOthers = Object.keys(THEMES).filter((n) => n !== defaultName);
const defaultIsTheme = !!(defaultName && THEMES[defaultName]);
const decl = (o) => Object.entries(o).map(([k, v]) => `--${k}: ${v};`).join(' ');
// The default theme applies while no data-palette is set, so it is right before the script runs.
// Light (0,2,0) beats the base :root, dark (0,3,0) beats the base dark blocks, and the later CVD blocks beat both.
const themeCss = (n) => {
  const t = THEMES[n];
  const isDefault = n === defaultName;
  const light = isDefault ? ':root:not([data-palette])' : `:root[data-palette="${n}"]`;
  const dark = isDefault ? ':root[data-theme="dark"]:not([data-palette])' : `:root[data-theme="dark"][data-palette="${n}"]`;
  return [
    `  /* theme ${n} light */`,
    `  ${light} { --accent-light: ${t.accentLight}; --accent-dark: ${t.accentDark}; --paper-light: ${t.paperLight}; --paper-dark: ${t.paperDark}; ${decl(t.light)} }`,
    `  /* theme ${n} dark */`,
    `  @media (prefers-color-scheme: dark) { ${light}:not([data-theme="light"]) { ${decl(t.dark)} } }`,
    `  ${dark} { ${decl(t.dark)} }`
  ];
};
const paletteCss = [
  '  /* Named palettes and themes for the switch. The report\'s own palette is the default. A pastel sets the four inputs, a theme also sets its own tokens for light and dark. */',
  ...namedOthers.map((n) => `  :root[data-palette="${n}"] { --accent-light: ${NAMED[n].accentLight}; --accent-dark: ${NAMED[n].accentDark}; --paper-light: ${NAMED[n].paperLight}; --paper-dark: ${NAMED[n].paperDark}; }`),
  ...Object.keys(THEMES).flatMap(themeCss),
  swatchRule('default', palette),
  ...themeOthers.map((n) => swatchRule(n, THEMES[n])),
  ...namedOthers.map((n) => swatchRule(n, NAMED[n]))
].join('\n');
const defaultLabel = defaultIsTheme ? `${THEMES[defaultName].label} (default)` : (defaultName ? `${cap(defaultName)} (default)` : 'Default');
const paletteOptions = [
  ['default', defaultLabel, true],
  ...themeOthers.map((n) => [n, THEMES[n].label, true]),
  ...namedOthers.map((n) => [n, cap(n), false])
]
  .map(([n, label, full]) => `            <button type="button" class="swatch${full ? ' full' : ''}" data-palette-btn="${n}" aria-pressed="${n === 'default'}"><span class="dot" aria-hidden="true"></span><span class="sw-name">${escHtml(label)}</span></button>`)
  .join('\n');

// ---------- Substitution ----------
const values = {
  title: escHtml(manifest.title || `${railTitle} PR #${pr.number}`),
  lang2: lang2 || '',
  langMode,
  storagePrefix,
  railTitle: escHtml(railTitle),
  ticketHtml,
  ticketLabel: escHtml(ticketLabel),
  ticketUrl: escHtml(ticketUrl),
  prNumber: String(pr.number),
  prUrl: escHtml(pr.url),
  prTitle: escHtml(pr.title),
  repoName: escHtml(meta.repo.nameWithOwner),
  repoUrl: escHtml(meta.repo.url),
  authorLogin: escHtml(pr.author || 'unknown'),
  authorUrl: escHtml(pr.authorUrl || meta.repo.url),
  branch: escHtml(pr.headRefName),
  baseRef: escHtml(pr.baseRefName),
  baseShort: escHtml(meta.baseShort),
  baseUrl: escHtml(meta.baseUrl),
  headShort: escHtml(meta.headShort),
  headUrl: escHtml(meta.headUrl),
  analysedOn: escHtml(meta.analysedOn),
  fontsHref: escHtml(palette.fontsHref),
  fontDisplay: palette.fontDisplay,
  fontBody: palette.fontBody,
  fontMono: palette.fontMono,
  accentLight: palette.accentLight,
  accentDark: palette.accentDark,
  paperLight: palette.paperLight,
  paperDark: palette.paperDark,
  paletteCss,
  paletteOptions,
  darkTokens: defines.darkTokens || '',
  cvdLightTokens: defines.cvdLightTokens || '',
  cvdDarkTokens: defines.cvdDarkTokens || '',
  tocHtml: toc.join('\n'),
  headerLede: frags['header-lede.html'].split('\n').map((l) => '      ' + l).join('\n'),
  statTiles,
  findings: frags['findings.html'].split('\n').map((l) => '        ' + l).join('\n'),
  mechanism,
  changesIntro: frags['changes-intro.html'].split('\n').map((l) => '        ' + l).join('\n'),
  changesBody: changesParts.join('\n\n'),
  fromPr,
  verification: frags['verification.html'].split('\n').map((l) => '      ' + l).join('\n'),
  extraSections,
  followup: frags['followup.html'].split('\n').map((l) => '      ' + l).join('\n'),
  commits,
  footer: frags['footer.html'].split('\n').map((l) => '      ' + l).join('\n'),
  blocksJs: JSON.stringify(BLOCKS),
  maskJs: JSON.stringify(Object.fromEntries(groups.filter((g) => g.mask && g.mask.length).map((g) => [g.key, g.mask]))),
  kindsCss,
  diffHeadLabel: jsStr(diffHead),
  wsLabelEn: escHtml(wsLabelEn),
  wsLabelL2,
  wsTag: escHtml(wsTag),
  wsTagJs: jsStr(wsTag),
  wsLabelJs: jsStr(wsLabelEn),
  vendorJs,
  hlFlag
};

let html = template.replace(/\{\{(\w+)\}\}/g, (m, name) => {
  if (!(name in values)) { errors.push(`template placeholder {{${name}} has no value`); return m; }
  return values[name];
});
if (errors.length) fail('\n  ' + errors.join('\n  '));
const leftover = html.match(/\{\{\w+\}\}/g);
if (leftover) fail(`unfilled placeholders: ${[...new Set(leftover)].join(', ')}`);

// TOC targets must exist
const ids = new Set([...html.matchAll(/\sid="([^"]+)"/g)].map((m) => m[1]));
for (const m of html.matchAll(/<a href="#([^"]+)"/g)) if (!ids.has(m[1])) errors.push(`link target #${m[1]} does not exist`);
if (errors.length) fail('\n  ' + errors.join('\n  '));

mkdirSync(dirname(outPath), { recursive: true });
writeFileSync(outPath, html);
process.stdout.write(hl
  ? `build: syntax colors: prism ${PRISM_VERSION}, ${langIds.length} file(s) (${langIds.join(',')}), ${downloaded} downloaded, ${cached} cached\n`
  : `build: syntax colors: off (${hlReason})\n`);
process.stdout.write(`build: wrote ${outPath} (${(Buffer.byteLength(html) / 1024).toFixed(0)} KB, ${blocks.length} block(s), ${groups.length} group(s), palette ${defaultName || 'custom'})\n`);
