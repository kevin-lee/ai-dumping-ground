#!/usr/bin/env node
// build.mjs - assemble the single-file report from the template, meta.json, the manifest, and fragments.
//
//   node build.mjs --work <workdir> --template <template.html> --out <report.html>
//
// The build is the only thing that writes the report. Fix content in the fragments or the manifest
// and rebuild, never edit the output by hand.

import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'node:fs';
import { join, dirname } from 'node:path';

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
    startAfter: b.range && b.range.after[0] > 0 ? b.range.after[0] : 1
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
const palette = manifest.palette || {};
for (const k of ['accentLight', 'accentDark', 'paperLight', 'paperDark', 'fontDisplay', 'fontBody', 'fontMono', 'fontsHref']) {
  if (!palette[k]) fail(`manifest.palette.${k} is required`);
}
if (!/^https:\/\/fonts\.googleapis\.com\//.test(palette.fontsHref)) fail('palette.fontsHref must be a fonts.googleapis.com URL');

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
  wsLabelJs: jsStr(wsLabelEn)
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
process.stdout.write(`build: wrote ${outPath} (${(Buffer.byteLength(html) / 1024).toFixed(0)} KB, ${blocks.length} block(s), ${groups.length} group(s))\n`);
