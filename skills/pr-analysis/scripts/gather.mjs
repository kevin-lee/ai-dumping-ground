#!/usr/bin/env node
// gather.mjs - collect everything the report needs about one pull request.
//
//   node gather.mjs --pr <number | #number | PR URL> --out <workdir>
//
// Runs from inside the repository the PR belongs to. Uses gh for metadata and git for
// file contents at the PR's merge-base and head commits. Never touches the working tree.
// Writes into <workdir>:
//   meta.json          everything below, plus ticket detection and local state
//   diff.patch         git diff -M <mergeBase> <head>
//   diffstat.txt       git diff --stat
//   files/<i>.before   file content at the merge-base (empty for added files)
//   files/<i>.after    file content at the head commit (empty for deleted files)
//   commits/<sha7>.txt full commit message of each commit in the PR
//
// No email addresses are stored. Authors are recorded by login only.

import { execFileSync } from 'node:child_process';
import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

function arg(name, fallback) {
  const i = process.argv.indexOf(name);
  return i !== -1 && process.argv[i + 1] !== undefined ? process.argv[i + 1] : fallback;
}

function fail(msg) {
  process.stderr.write(`gather: ${msg}\n`);
  process.exit(1);
}

function run(cmd, args, opts = {}) {
  return execFileSync(cmd, args, { encoding: 'utf8', maxBuffer: 256 * 1024 * 1024, stdio: ['ignore', 'pipe', 'pipe'], ...opts });
}
function runBuffer(cmd, args) {
  return execFileSync(cmd, args, { maxBuffer: 256 * 1024 * 1024, stdio: ['ignore', 'pipe', 'pipe'] });
}
function tryRun(cmd, args) {
  try { return run(cmd, args).trim(); } catch (e) { return null; }
}

const prArg = arg('--pr');
const out = arg('--out');
if (!prArg || !out) fail('usage: gather.mjs --pr <number|#number|url> --out <workdir>');

// PR number from a bare number, #number, or a PR URL
const prMatch = String(prArg).match(/(?:pull\/)?#?(\d+)\s*$/);
if (!prMatch) fail(`cannot read a PR number from "${prArg}"`);
const prNumber = Number(prMatch[1]);

// Repository
if (tryRun('git', ['rev-parse', '--is-inside-work-tree']) !== 'true') fail('run this inside a git repository');
const repoRoot = run('git', ['rev-parse', '--show-toplevel']).trim();
process.chdir(repoRoot);

let repo;
try {
  repo = JSON.parse(run('gh', ['repo', 'view', '--json', 'nameWithOwner,url,defaultBranchRef']));
} catch (e) {
  fail('gh repo view failed. Is gh installed and authenticated (gh auth status), and does this repository have a GitHub remote?');
}
const repoUrl = repo.url.replace(/\/$/, '');
const [owner, name] = repo.nameWithOwner.split('/');
const host = new URL(repoUrl).origin;

// Which remote points at this repository
let remote = 'origin';
const remotes = tryRun('git', ['remote', '-v']) || '';
for (const line of remotes.split('\n')) {
  const m = line.match(/^(\S+)\s+(\S+)\s+\(fetch\)/);
  if (m && m[2].toLowerCase().includes(repo.nameWithOwner.toLowerCase())) { remote = m[1]; break; }
}

// Pull request
let pr;
try {
  pr = JSON.parse(run('gh', ['pr', 'view', String(prNumber), '--json',
    'number,title,url,state,isDraft,baseRefName,headRefName,headRefOid,baseRefOid,author,body,createdAt,mergedAt,mergeCommit,files,commits,labels,headRepository,headRepositoryOwner']));
} catch (e) {
  fail(`gh pr view ${prNumber} failed: ${String(e.stderr || e.message).trim()}`);
}

// Fetch base and head so both commits are available locally
tryRun('git', ['fetch', '--no-tags', '--quiet', remote, pr.baseRefName]);
let headFetched = tryRun('git', ['fetch', '--no-tags', '--quiet', remote, `pull/${prNumber}/head:refs/pr-analysis/${prNumber}`]) !== null;
if (!headFetched) headFetched = tryRun('git', ['fetch', '--no-tags', '--quiet', remote, pr.headRefOid]) !== null;
if (tryRun('git', ['cat-file', '-e', `${pr.headRefOid}^{commit}`]) === null) fail(`head commit ${pr.headRefOid} is not available after fetching`);

// The "before" commit is the merge-base, the same point GitHub compares against
let mergeBase = tryRun('git', ['merge-base', pr.baseRefOid, pr.headRefOid]);
if (!mergeBase) mergeBase = tryRun('git', ['merge-base', `${remote}/${pr.baseRefName}`, pr.headRefOid]);
if (!mergeBase) fail('cannot compute the merge-base between the base branch and the PR head');

// Changed files
mkdirSync(join(out, 'files'), { recursive: true });
mkdirSync(join(out, 'commits'), { recursive: true });

const numstat = new Map();
for (const line of run('git', ['diff', '--numstat', '-M', mergeBase, pr.headRefOid]).split('\n')) {
  if (!line.trim()) continue;
  const [a, d, p] = line.split('\t');
  const path = p.includes(' => ') ? p.replace(/^.*\{?([^{}]*) => ([^{}]*)\}?.*$/, (s, x, y) => s.includes('{') ? s.replace(/\{[^}]*\}/, y) : y) : p;
  numstat.set(path, a === '-' && d === '-');
}

const files = [];
let index = 0;
for (const line of run('git', ['diff', '--name-status', '-M', mergeBase, pr.headRefOid]).split('\n')) {
  if (!line.trim()) continue;
  const parts = line.split('\t');
  const status = parts[0][0];
  const oldPath = status === 'R' || status === 'C' ? parts[1] : (status === 'A' ? null : parts[1]);
  const path = status === 'R' || status === 'C' ? parts[2] : parts[1];
  const binary = numstat.get(path) === true;
  const entry = { index, path, oldPath: status === 'A' ? null : oldPath, status, binary };
  if (!binary) {
    let before = Buffer.alloc(0), after = Buffer.alloc(0);
    if (status !== 'A') { try { before = runBuffer('git', ['show', `${mergeBase}:${oldPath}`]); } catch (e) { before = Buffer.alloc(0); } }
    if (status !== 'D') { try { after = runBuffer('git', ['show', `${pr.headRefOid}:${path}`]); } catch (e) { after = Buffer.alloc(0); } }
    writeFileSync(join(out, 'files', `${index}.before`), before);
    writeFileSync(join(out, 'files', `${index}.after`), after);
    entry.beforeLines = before.length ? before.toString('utf8').split('\n').length : 0;
    entry.afterLines = after.length ? after.toString('utf8').split('\n').length : 0;
  }
  files.push(entry);
  index++;
}

writeFileSync(join(out, 'diff.patch'), run('git', ['diff', '-M', mergeBase, pr.headRefOid]));
writeFileSync(join(out, 'diffstat.txt'), run('git', ['diff', '--stat', '-M', mergeBase, pr.headRefOid]));

// Commits, by login only
const commits = (pr.commits || []).map((c) => {
  const sha7 = c.oid.slice(0, 7);
  let message = tryRun('git', ['log', '-1', '--format=%B', c.oid]);
  if (message === null) message = [c.messageHeadline, c.messageBody].filter(Boolean).join('\n\n');
  writeFileSync(join(out, 'commits', `${sha7}.txt`), message + '\n');
  return {
    oid: c.oid,
    sha7,
    headline: c.messageHeadline,
    authors: (c.authors || []).map((a) => a.login).filter(Boolean),
    url: `${repoUrl}/commit/${c.oid}`
  };
});

// Ticket detection: Jira style key first, then a GitHub issue reference
const body = pr.body || '';
const haystacks = [pr.headRefName, pr.title, body];
let ticket = { kind: null, id: null, url: null };
for (const h of haystacks) {
  const m = h && h.match(/\b[A-Z][A-Z0-9]{1,9}-\d+\b/);
  if (m) { ticket = { kind: 'jira', id: m[0], url: null }; break; }
}
if (!ticket.kind) {
  for (const h of haystacks) {
    const m = h && (h.match(/(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?)\s+#(\d+)/i) || h.match(/(?:#|issues\/)(\d+)\b/));
    if (m) { ticket = { kind: 'github', id: `issue-${m[1]}`, url: `${repoUrl}/issues/${m[1]}` }; break; }
  }
}
let jiraBase = null;
const jb = body.match(/(https?:\/\/[a-z0-9.-]+\.atlassian\.net)/i) || body.match(/(https?:\/\/[^/\s"')]+)\/browse\/[A-Z][A-Z0-9]+-\d+/);
if (jb) jiraBase = jb[1];
if (ticket.kind === 'jira' && jiraBase) ticket.url = `${jiraBase}/browse/${ticket.id}`;

// Local state: is the checkout the PR branch with unpushed or uncommitted work?
const currentBranch = tryRun('git', ['branch', '--show-current']) || '';
const localHead = tryRun('git', ['rev-parse', 'HEAD']) || '';
const dirty = (tryRun('git', ['status', '--porcelain']) || '') !== '';
const localState = { currentBranch, headEqualsPr: localHead === pr.headRefOid, dirty, warning: null };
if (currentBranch === pr.headRefName && (!localState.headEqualsPr || dirty)) {
  localState.warning = `The checked-out branch ${currentBranch} has ${dirty ? 'uncommitted changes' : ''}${dirty && !localState.headEqualsPr ? ' and ' : ''}${!localState.headEqualsPr ? 'commits that differ from the PR head' : ''}. The report reflects the pushed PR at ${pr.headRefOid.slice(0, 7)}, not the local tree.`;
}

const today = new Date();
const analysedOn = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-${String(today.getDate()).padStart(2, '0')}`;

const meta = {
  repo: { owner, name, nameWithOwner: repo.nameWithOwner, url: repoUrl, host, defaultBranch: repo.defaultBranchRef && repo.defaultBranchRef.name, remote },
  pr: {
    number: pr.number, title: pr.title, url: pr.url, state: pr.state, isDraft: pr.isDraft,
    baseRefName: pr.baseRefName, headRefName: pr.headRefName,
    baseRefOid: pr.baseRefOid, headRefOid: pr.headRefOid,
    author: pr.author && pr.author.login ? pr.author.login : null,
    authorUrl: pr.author && pr.author.login ? `${host}/${pr.author.login}` : null,
    body, createdAt: pr.createdAt, mergedAt: pr.mergedAt,
    mergeCommit: pr.mergeCommit && pr.mergeCommit.oid ? pr.mergeCommit.oid : null,
    labels: (pr.labels || []).map((l) => l.name),
    headRepository: pr.headRepositoryOwner && pr.headRepository ? `${pr.headRepositoryOwner.login}/${pr.headRepository.name}` : null,
    ghFiles: (pr.files || []).map((f) => ({ path: f.path, additions: f.additions, deletions: f.deletions }))
  },
  mergeBase, headSha: pr.headRefOid, baseShort: mergeBase.slice(0, 7), headShort: pr.headRefOid.slice(0, 7),
  baseUrl: `${repoUrl}/commit/${mergeBase}`, headUrl: `${repoUrl}/commit/${pr.headRefOid}`,
  files, commits, ticket, jiraBase, localState, analysedOn
};

writeFileSync(join(out, 'meta.json'), JSON.stringify(meta, null, 2) + '\n');
process.stdout.write(`gather: PR #${pr.number} "${pr.title}"\n`);
process.stdout.write(`gather: ${files.length} changed file(s), ${commits.length} commit(s), base ${meta.baseShort} (merge-base of ${pr.baseRefName}) → head ${meta.headShort}\n`);
process.stdout.write(`gather: ticket ${ticket.kind ? `${ticket.id}${ticket.url ? ' ' + ticket.url : ' (no link found)'}` : 'none detected'}\n`);
if (localState.warning) process.stdout.write(`gather: WARNING ${localState.warning}\n`);
process.stdout.write(`gather: wrote ${join(out, 'meta.json')}\n`);
