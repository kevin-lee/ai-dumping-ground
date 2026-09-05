#!/usr/bin/env node
// check.mjs - verify a built report before handing it over.
//
//   node check.mjs --work <workdir> --html <report.html>
//
// Prints PASS / WARN / FAIL lines and exits non-zero when anything FAILs.

import { readFileSync, existsSync, statSync, writeFileSync, readdirSync, mkdtempSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { execFileSync } from 'node:child_process';
import vm from 'node:vm';

function arg(name) { const i = process.argv.indexOf(name); return i !== -1 ? process.argv[i + 1] : undefined; }
const work = arg('--work'), htmlPath = arg('--html');
if (!work || !htmlPath) { process.stderr.write('usage: check.mjs --work <workdir> --html <report.html>\n'); process.exit(2); }

let fails = 0, warns = 0;
const pass = (m) => process.stdout.write(`PASS  ${m}\n`);
const warn = (m) => { warns++; process.stdout.write(`WARN  ${m}\n`); };
const fail = (m) => { fails++; process.stdout.write(`FAIL  ${m}\n`); };

if (!existsSync(htmlPath)) { fail(`${htmlPath} does not exist`); process.exit(1); }
const html = readFileSync(htmlPath, 'utf8');
const meta = JSON.parse(readFileSync(join(work, 'meta.json'), 'utf8'));
const manifestPath = join(work, 'content', 'manifest.json');
const manifest = existsSync(manifestPath) ? JSON.parse(readFileSync(manifestPath, 'utf8')) : {};
const fragDir = join(work, 'content');
const fragments = existsSync(fragDir) ? readdirSync(fragDir).filter((f) => f.endsWith('.html')).map((f) => [f, readFileSync(join(fragDir, f), 'utf8')]) : [];
const lang2 = manifest.lang2 || null;

// 1. size
const size = statSync(htmlPath).size;
if (size < 16 * 1024 * 1024) pass(`size ${(size / 1024).toFixed(0)} KB, under 16 MB`); else fail(`size ${(size / 1024 / 1024).toFixed(1)} MB exceeds 16 MB`);

// 2. exactly one script, syntax checked
const scripts = [...html.matchAll(/<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/g)];
if (scripts.length !== 1) fail(`${scripts.length} <script> blocks, expected exactly one`);
else {
  const dir = mkdtempSync(join(tmpdir(), 'pr-analysis-check-'));
  const js = join(dir, 'page.js');
  writeFileSync(js, scripts[0][1]);
  try { execFileSync(process.execPath, ['--check', js], { stdio: 'pipe' }); pass('script parses (node --check)'); }
  catch (e) { fail(`script syntax: ${String(e.stderr || e.message).trim().split('\n').slice(0, 3).join(' | ')}`); }
}

// 3. single file: only allowed external hosts
const allowedHosts = new Set(['fonts.googleapis.com', 'fonts.gstatic.com']);
try { allowedHosts.add(new URL(meta.repo.url).host); } catch (e) { /* ignore */ }
if (meta.ticket && meta.ticket.url) { try { allowedHosts.add(new URL(meta.ticket.url).host); } catch (e) { /* ignore */ } }
if (meta.jiraBase) { try { allowedHosts.add(new URL(meta.jiraBase).host); } catch (e) { /* ignore */ } }
if (manifest.ticket && manifest.ticket.url) { try { allowedHosts.add(new URL(manifest.ticket.url).host); } catch (e) { /* ignore */ } }
const extraSources = [meta.pr && meta.pr.body || ''];
const refsPath = join(work, 'references.txt');
if (existsSync(refsPath)) extraSources.push(readFileSync(refsPath, 'utf8'));
for (const src of extraSources) for (const m of src.matchAll(/https?:\/\/([^/\s"')>\]]+)/g)) allowedHosts.add(m[1]);
const badUrls = [];
for (const m of html.matchAll(/\b(?:src|href|cite)="(https?:\/\/[^"]+)"/g)) {
  let host; try { host = new URL(m[1]).host; } catch (e) { host = null; }
  if (!host || !allowedHosts.has(host)) badUrls.push(m[1]);
}
if (badUrls.length) fail(`external URLs outside the allowed hosts: ${[...new Set(badUrls)].slice(0, 8).join(', ')}`);
else pass(`external references limited to ${[...allowedHosts].join(', ')}`);
const scriptSrc = [...html.matchAll(/<script[^>]*\ssrc=/g)];
if (scriptSrc.length) fail('external <script src> found, the page must be self-contained'); else pass('no external scripts');

// 4. BLOCKS fidelity
let BLOCKS = null;
const bm = html.match(/const BLOCKS = ([\s\S]*?);\n\s*\/\/ Per-group masks/);
if (!bm) fail('cannot locate the BLOCKS literal');
else {
  try { BLOCKS = vm.runInNewContext('(' + bm[1] + ')'); } catch (e) { fail(`BLOCKS does not evaluate: ${e.message}`); }
}
if (BLOCKS) {
  let mismatches = [];
  for (const b of manifest.blocks || []) {
    const emb = BLOCKS[b.key];
    if (!emb) { mismatches.push(`${b.key}: missing`); continue; }
    const slice = (text, range) => {
      if (!range) return text;
      if (range[0] === 0 && range[1] === 0) return '';
      return text.split('\n').slice(range[0] - 1, range[1]).join('\n');
    };
    const bp = join(work, 'files', `${b.fileIndex}.before`), ap = join(work, 'files', `${b.fileIndex}.after`);
    const redact = (t) => (manifest.redact || []).reduce((s, r) => s.replace(new RegExp(r.pattern, r.flags || 'g'), r.replacement), t);
    const before = existsSync(bp) ? redact(readFileSync(bp, 'utf8')) : '';
    const after = existsSync(ap) ? redact(readFileSync(ap, 'utf8')) : '';
    const eb = slice(before, b.range && b.range.before), ea = slice(after, b.range && b.range.after);
    if (emb.before !== eb) mismatches.push(`${b.key}: before differs (${emb.before.length} vs ${eb.length} chars)`);
    if (emb.after !== ea) mismatches.push(`${b.key}: after differs (${emb.after.length} vs ${ea.length} chars)`);
  }
  if (mismatches.length) fail(`embedded text differs from git: ${mismatches.join('; ')}`);
  else pass(`${Object.keys(BLOCKS).length} block(s) embedded byte for byte from git show${(manifest.redact || []).length ? ` (after ${manifest.redact.length} declared redaction rule(s))` : ''}`);
}

// 5. keys and anchors
const ids = new Set([...html.matchAll(/\sid="([^"]+)"/g)].map((m) => m[1]));
const badKeys = [];
for (const m of html.matchAll(/data-(?:block|ident|lines)="([^"]+)"/g)) if (BLOCKS && !BLOCKS[m[1]]) badKeys.push(m[1]);
if (badKeys.length) fail(`data-block/ident keys without BLOCKS entry: ${[...new Set(badKeys)].join(', ')}`); else pass('every diff and badge key has an embedded block');
const badAnchors = [];
for (const m of html.matchAll(/<a href="#([^"]+)"/g)) if (!ids.has(m[1])) badAnchors.push(m[1]);
if (badAnchors.length) fail(`anchors without target: ${[...new Set(badAnchors)].join(', ')}`); else pass('every in-page anchor has a target');

// 6 and 7. languages
const countClass = (s, cls) => (s.match(new RegExp(`class="[^"]*\\b${cls}\\b[^"]*"`, 'g')) || []).length;
if (lang2) {
  const imbalance = [];
  for (const [name, frag] of fragments) {
    // Second-language summaries under verbatim quotes (class "summary l2") have no English twin by design
    const en = countClass(frag, 'en'), l2 = countClass(frag, 'l2') - (frag.match(/class="[^"]*\bsummary\b[^"]*\bl2\b[^"]*"|class="[^"]*\bl2\b[^"]*\bsummary\b[^"]*"/g) || []).length;
    if (en !== l2) imbalance.push(`${name} en=${en} l2=${l2}`);
  }
  if (imbalance.length) fail(`language pairs unbalanced: ${imbalance.join('; ')}`); else pass(`every fragment pairs .en with .l2 (${lang2})`);
} else {
  const l2 = countClass(html, 'l2');
  if (l2) fail(`English-only report contains ${l2} element(s) with class l2`); else pass('English only, no second-language elements');
}

// 8. prose hygiene on fragments (not code, pre, blockquote)
const stripQuoted = (s) => s.replace(/<pre[\s\S]*?<\/pre>/g, '').replace(/<blockquote[\s\S]*?<\/blockquote>/g, '').replace(/<code[\s\S]*?<\/code>/g, '').replace(/<svg[\s\S]*?<\/svg>/g, '').replace(/<[^>]+>/g, ' ');
const hygiene = [];
for (const [name, frag] of fragments) {
  const text = stripQuoted(frag);
  const em = (text.match(/—/g) || []).length;
  const semi = (text.match(/;/g) || []).length;
  if (em || semi) hygiene.push(`${name}: ${em} em-dash, ${semi} semicolon`);
}
if (hygiene.length) warn(`prose hygiene: ${hygiene.join('; ')}`); else pass('no em-dashes or semicolons in authored prose');

// 9. secrets and PII
const secretPatterns = [
  ['email address', /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g, (s) => !/noreply@/i.test(s)],
  ['AWS access key', /\bAKIA[0-9A-Z]{16}\b/g],
  ['GitHub token', /\bghp_[A-Za-z0-9]{36}\b|\bgithub_pat_[A-Za-z0-9_]{20,}\b/g],
  ['Slack token', /\bxox[abpr]-[A-Za-z0-9-]{10,}\b/g],
  ['private key', /-----BEGIN [A-Z ]*PRIVATE KEY/g],
  ['JWT', /\beyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}/g],
  ['credential assignment', /(password|passwd|secret|token)\s*[:=]\s*['"][^'"]{6,}['"]/gi]
];
let secretHit = false;
for (const [label, re, keep] of secretPatterns) {
  const hits = [...html.matchAll(re)].map((m) => m[0]).filter((s) => !keep || keep(s));
  if (hits.length) { secretHit = true; fail(`${label} found (${hits.length}): ${hits.slice(0, 3).map((h) => h.slice(0, 40)).join(', ')}`); }
}
if (!secretHit) pass('no email addresses, keys, tokens, or credential assignments');
const acct = [...html.matchAll(/(?<![\w.])\d{12}(?![\w.])/g)];
if (acct.length) warn(`${acct.length} twelve-digit number(s), possible cloud account IDs: ${[...new Set(acct.map((m) => m[0]))].slice(0, 5).join(', ')}`);
const bearer = [...html.matchAll(/Bearer [A-Za-z0-9._-]{20,}/g)];
if (bearer.length) warn(`${bearer.length} Bearer token-like string(s)`);

// 10. accessibility statics
const a11y = [];
if (!/<a class="skip-link" href="#main">/.test(html)) a11y.push('skip link missing');
if (!/<main id="main"/.test(html)) a11y.push('main#main missing');
if (!/id="announce"[^>]*aria-live=/.test(html)) a11y.push('#announce live region missing');
if (!/<html lang="/.test(html)) a11y.push('<html lang> missing');
if (!/<title>[^<]+<\/title>/.test(html)) a11y.push('<title> missing');
if (!/<dialog id="help"/.test(html)) a11y.push('dialog#help missing');
for (const m of html.matchAll(/<button\b([^>]*)>([\s\S]*?)<\/button>/g)) {
  const attrs = m[1], inner = m[2].replace(/<svg[\s\S]*?<\/svg>/g, '').replace(/<span class="tip"[\s\S]*?<\/span>\s*<\/span>|<span class="tip"[\s\S]*?<\/span>/g, '').replace(/<[^>]+>/g, '').trim();
  if (!/aria-label=/.test(attrs) && !inner) a11y.push(`button without text or aria-label: <button${attrs.slice(0, 60)}>`);
}
for (const m of html.matchAll(/<svg\b([^>]*)>/g)) {
  if (!/role="img"/.test(m[1]) && !/aria-hidden="true"/.test(m[1])) a11y.push(`svg without role="img" or aria-hidden: <svg${m[1].slice(0, 60)}>`);
}
for (const m of html.matchAll(/<img\b([^>]*)>/g)) if (!/\salt=/.test(m[1])) a11y.push('img without alt');
if (a11y.length) fail(`accessibility: ${[...new Set(a11y)].slice(0, 8).join('; ')}`); else pass('skip link, live region, labelled buttons, hidden decorative SVG, title, lang, help dialog');

// 11. acronym reminder
const proseText = fragments.map(([, f]) => stripQuoted(f)).join(' ') + ' ' + ((manifest.title || '') + ' ' + (manifest.statTiles || []).map((t) => t.en).join(' '));
const expanded = new Set([...html.replace(/<[^>]+>/g, ' ').matchAll(/\(([A-Z][A-Z0-9]{1,5})\)/g)].map((m) => m[1]));
const ignore = new Set(['PR', 'ID', 'OK', 'TODO', 'README', 'UTF']);
const unexpanded = new Set();
for (const m of proseText.matchAll(/(?<![\w-])([A-Z][A-Z0-9]{1,5})(?![\w-])/g)) {
  const t = m[1];
  if (/^\d+$/.test(t) || ignore.has(t) || expanded.has(t)) continue;
  unexpanded.add(t);
}
if (unexpanded.size) warn(`acronyms without a parenthesised expansion anywhere on the page: ${[...unexpanded].sort().join(', ')} (expand on first use, or ignore if they are identifiers)`);
else pass('every all-caps short form has an expansion, or none appear');

process.stdout.write(`\n${fails} FAIL, ${warns} WARN\n`);
process.exit(fails ? 1 : 0);
