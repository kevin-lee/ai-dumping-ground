---
name: pr-analysis
description: Create an interactive, single-file HTML report that explains what a pull request changes and why, block by block with live syntax-colored diffs that show changed lines with expandable context, findings, verification, follow-ups, a theme toggle, a text size control, a color palette switch, and a color vision deficiency palette. Use this whenever the user invokes /pr-analysis, asks for a PR report, PR explainer, PR walkthrough, PR summary page, "explain this PR as a page", "HTML report for PR 123", "help my team understand this PR", or wants a shareable document about a pull request, even if they do not say "report" or "HTML". Do not use it to post review comments on GitHub, that is what code-review does.
---

# pr-analysis

Build one self-contained HTML page that lets someone who did not write a pull request understand it: what changed, why it had to change that way, what was verified, and what is left. The page carries the diffs themselves, computed in the browser from the embedded before and after text, so it stays truthful and works offline.

The engine (layout, diff viewer, theme, accessibility) is a bundled template. Node scripts gather the data, assemble the page, and check it. Your work is the analysis and the words: findings, grouping, headings, verification, follow-ups, palette. You never write the HTML page by hand.

## 0. Parse the arguments

The text after `/pr-analysis` is the argument string (the harness substitutes it into this skill as `$ARGUMENTS`). It may contain, in any order:

- `--help` or `help`: print `references/help.md` verbatim (the fenced block, without the fence) and stop. Make no other tool call.
- A PR identifier: a bare integer (`123`), `#123`, or a PR URL.
- `bilingual=<Language>` optionally followed by `show` or `hide`. The language is the token after `=` up to the next space. The mode is `both` when the words after the language contain `show` or `both`, otherwise `hidden`. So `bilingual=Korean` alone and `bilingual=Korean hide` are hidden, `bilingual=Korean show` is both, and the older `show both` and `hidden with the param` resolve by the same rule. Map the language name to a code with the table in `references/writing-rules.md`. Unknown name: use the lowercased name as the code and say so at the end.

Without `bilingual=` the report is English only. Examples: `/pr-analysis 70`, `/pr-analysis 70 bilingual=Korean show`, `/pr-analysis #70 bilingual=Korean hide`, `/pr-analysis #70 bilingual=Korean` (hidden, same as `hide`).

## 1. Intake, before anything else

Call `AskUserQuestion` exactly once, before reading any file or running any command. The user asked for this order so no analysis tokens are spent before they have confirmed the inputs. Ask up to four questions:

1. **PR** (only when no PR identifier was given): options "PR of the current branch" (resolved with `gh pr view` and no number) and "Most recently updated open PR in this repository" (`gh pr list --limit 1 --json number`). The user can type a number or URL as Other.
2. **Issue**: options "Detect from the PR" (branch name, title, and body are scanned for `ABC-123` or `#123`, falling back to `no-ticket`) and "None". Other accepts `ABC-123`, `123`, `#123`, or `issue-123`.
3. **Color**: option "Pick a pastel for me" (a random palette from `references/design-rules.md`). Other accepts a brief such as "blue controls on a mild solarized-light yellow ground".
4. **References**: option "None". Other accepts file paths, URLs, repository paths, and notes. These are read during analysis and any question they raise gets its own section.

Do not ask about language or output location. Both are decided by the arguments and the rules below.

## 2. Gather

Run from the repository root:

```
node <skill>/scripts/gather.mjs --pr <N> --out <workdir>
```

`<skill>` is this skill's directory. `<workdir>` is `<scratchpad>/pr-analysis/pr-<N>/` when the session has a scratchpad directory, otherwise `$TMPDIR/pr-analysis/<repo>-pr-<N>/`. The script fetches the PR's base and head, computes the merge-base (the same point GitHub compares against, never `HEAD~1`), writes every changed file at both commits, the patch, the commit messages, and `meta.json`. It records authors by login only. If it prints a WARNING about local state, keep it for the completion message. The local working tree is never the source of the report.

Write the references answer to `<workdir>/references.txt` so the check script can allow links to those hosts.

## 3. Resolve the issue ID and output path

- Detected or typed Jira style key (`ABC-123`): folder `ABC-123`, upper-cased. Link to `<jiraBase>/browse/<KEY>` when `meta.jiraBase` or a `/browse/` URL in the references gives a base, otherwise unlinked.
- Digits, `#N`, or `issue-N`: folder `issue-N`, linked to `<repoUrl>/issues/N`.
- Nothing: folder `no-ticket`.
- Anything else typed: keep it after replacing characters outside `[A-Za-z0-9._-]` with `-`.

Output path, always: `.ai/docs/pr/<folder>/pr-<N>-report.html` relative to the repository root. Say the resolved path before continuing.

## 4. Read the change

Read `<workdir>/diff.patch`, then each changed file's before and after (`files/<i>.before`, `files/<i>.after`), then the PR body in `meta.json` and the commit messages in `commits/`. Read enough surrounding code in the repository to explain why each change was made, not only what changed. Read the user's references: local files with Read, URLs with WebFetch when available, repositories by path. Do not read files unrelated to the change.

Before embedding anything, scan the changed files for credentials. `references/writing-rules.md` says how to redact.

## 5. Design the content

Follow `references/content-spec.md`. Decide, in this order: the kinds (two to four categories with a tone and a glyph), the findings, the grouping of files into blocks and groups, which optional sections earn their place (mechanism figure, quoted PR figures, extra sections for reference questions) and whether any finding, group, or block earns a figure (read `references/figures.md` only when one does), the verification rows, the follow-ups, and the stat tiles. Then pick the palette (a name from `assets/palettes.json` for a pastel, or four values from a color brief) and the font pairing per `references/design-rules.md`.

## 6. Write the manifest and fragments

Write `<workdir>/content/manifest.json` and the fragment files described in `references/manifest-schema.md`. Every visible string follows `references/writing-rules.md` and `references/accessibility.md`. In bilingual mode every English element has a second-language twin. In English-only mode no element carries `class="l2"`.

## 7. Build

```
node <skill>/scripts/build.mjs --work <workdir> --template <skill>/assets/template.html --out <output path>
```

The build validates the manifest, escapes and embeds the file text, generates the table of contents, blocks, and commits section, and fills the template. It fails loudly on a missing fragment, an unknown kind, or an anchor without a target.

The build reads `assets/palettes.json` next to the template and embeds the named palettes in the page for the palette switch. The output never references that file.

The build also downloads the Prism grammars the PR's file types need into `~/.cache/pr-analysis` on first use, verifies them against pinned checksums, and inlines them. When the download fails it prints a WARNING and builds without syntax colors. Keep that warning for the completion message. Never add the library to the skill.

## 8. Check

```
node <skill>/scripts/check.mjs --work <workdir> --html <output path>
```

Fix every FAIL by editing the manifest or fragments and rebuilding. Read every WARN and decide: expand an acronym, remove a semicolon, or leave it when it is a quoted string or an identifier, and say why in the completion message. Never edit the output HTML directly.

## 9. Look once

If `open` or a headless Chrome is available, render the page once and glance at it: header, one diff block, the theme toggle. One pass of fixes through the fragments, rebuild, then stop. Do not loop on screenshots. When headless Chrome does not exit in a sandbox, pass `--host-resolver-rules="MAP * ~NOTFOUND"` so the font stylesheet fails fast, and avoid `#fragment` URLs, which render blank in headless mode.

## 10. Finish

Report, in this order:

- The absolute output path, a markdown link to it with a relative path (opens in the editor), and a `file://` link (opens in the browser). For hidden bilingual mode add the same `file://` link with `?lang=<code>`.
- One sentence on what the page contains (blocks, groups, findings, extra sections).
- Which palette (name, or custom from the brief) and font pairing you used.
- Any warnings: local state from gather, an unknown language code, redactions, syntax colors off and why, WARN lines left standing and why.

Nothing is committed, pushed, or published.

## What not to do

- Do not publish to Claude Artifacts, Codex Sites, Gemini Canvas or any external service unless explicitly requested. The deliverable is the local HTML file.
- Do not edit the generated HTML by hand. The manifest and fragments are the source, the build is the only writer.
- Do not hard code organisation hosts, repository names, or ticket systems. Everything comes from `meta.json`, the manifest, or the user's references.
- Do not write email addresses, full names, or anything that looks like a credential into the page.
- Do not assume `HEAD~1`, the local branch, or the working tree is the PR. The PR is base merge-base to head, as gathered.
- Do not present figures from the PR description as measured. Quote them and label them.
- Do not load design skills at runtime. `references/design-rules.md` carries what matters here.
- Do not vendor the highlighter into the skill folder or the repository. The build fetches it into the cache.
