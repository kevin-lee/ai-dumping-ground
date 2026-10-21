# AI output folder: notes for maintainers

This document is for AI agents and people who change the skills that use the central AI agent output folder. It records the issues, the considerations and the decisions, so that a later change does not break them again. Read it before you change a script or the rule.

## Files

Four skills write into `${AI_AGENT_OUTPUT_DIR:-~/.ai}/<project key>`:

| Skill | Scripts |
|---|---|
| `riper-5` | `ai-output-dir.sh`, `ai-output-choices.sh`, `migrate-ai-output.sh` |
| `pr-analysis` | `ai-output-dir.sh`, `ai-output-choices.sh`, `migrate-ai-output.sh` |
| `gen-motion-graphics` | `ai-output-dir.sh`, `migrate-ai-output.sh`, `video-output-choices.sh` |
| `centralize-ai-output` | `ai-output-dir.sh`, `migrate-ai-output.sh`, `link-ai-folder.sh`, `install-rule.sh`, and the rule text in `assets/Centralize-AI-Output.md` |

- Each copy of `ai-output-dir.sh`, `migrate-ai-output.sh` and `ai-output-choices.sh` must be identical in every skill that has it. A skill is installed alone, so each skill needs its own copy. The tests compare the copies.
- `video-output-choices.sh` is only in `gen-motion-graphics`. Its options are `video` in the current folder and `video` in the central folder, but its recommendation and order follow the same rule as `ai-output-choices.sh`, with `current` for `project`. The tests run both scripts in the same states and compare the results.
- `install-rule.sh` copies the rule into `~/.claude/rules/Centralize-AI-Output.md` (or under `$CLAUDE_CONFIG_DIR`) and into a marked block in `~/.codex/AGENTS.md` (or under `$CODEX_HOME`) and `~/.gemini/GEMINI.md`. Cursor has no user rule file, so the user pastes the text from `--print`.
- `AGENTS.md` at the repository root lists the files that make an agent read this document. When you add, rename or remove a file in the table above, or a test script, update that list too.

## Invariants

- POSIX `sh` only. The scripts must work with macOS `/bin/sh`, `bash`, `dash` (Debian) and BusyBox (Alpine).
- A script that changes something starts with a dry run. It changes something only with `--apply`, and the skill runs `--apply` only after the user explicitly agrees.
- Before a script changes an existing file, it makes a backup, `<file>.bak.<YYYYmmdd-HHMMSS>`. No script deletes a file of the user. `link-ai-folder.sh` removes only `.DS_Store` files and empty folders, and only after the user agrees.
- `shellcheck` gives no findings.
- `bash scripts/skills/test-ai-output-scripts.sh` passes on macOS with `/bin/sh`, `bash` and `dash`. `bash scripts/skills/test-ai-output-scripts-linux.sh` passes in Debian 12, Debian 13 and Alpine.
- An agent never calculates the folder itself. It runs `ai-output-dir.sh` and uses the printed path.

## Problem: an installed rule does not change with the skill

Facts found during issue #47:

- `install-rule.sh` copies the rule one time. `aiskills update` replaces the files in the skill folder, but the installed rule is outside the skill folder. `aiskills` has no post-update hook. So an installed rule stays as it was.
- The first rule had a fallback: "if the script does not exist, the folder is ..." with the key format. When the key changed from `local/<absolute path>` to `local/<name>-<hash>`, every old rule had a wrong fallback.
- The old rule runs the script first. A skill update replaces the script, so an old rule still gave the correct folder while the script existed. The wrong fallback had an effect only when the script was missing. Then the agent calculated a wrong folder, and nobody saw it.
- The Codex and Gemini blocks pointed to the Claude copy of the script (`~/.claude/skills/...`), also when Codex had its own copy. When the Claude copy was missing, Codex used the fallback.

## Decisions

1. **The rule has no key format.** It only tells the agent to run `ai-output-dir.sh` and use the printed path. If the script does not exist or fails, the agent does not calculate the folder, does not write into the project, tells the user, and asks where to write. Reason: a change of the key format then changes only the scripts and the documents, and a skill update installs them. A visible stop is better than a wrong folder that nobody sees.
2. **The script that the rule runs reports an outdated rule.** In default mode, `ai-output-dir.sh` runs `install-rule.sh --check` when `install-rule.sh` is in the same folder. That is true only in `centralize-ai-output`, so the four copies stay identical and the other skills do nothing. For each `outdated <file>` or `broken <file>` line, it prints `note for the AI agent: ...` on stderr. Stdout stays one path line, and the exit code does not change. It never writes the rule. `AI_AGENT_OUTPUT_RULE_CHECK=0` turns it off. Reason: every installed rule runs this script in every session, and `aiskills update` replaces it. So this is the only path that reaches a user who updates the skill and never runs `/centralize-ai-output`. Old rules call the Claude copy of the script, so the check reaches them too.
3. **Each agent's rule runs that agent's own copy of the script.** `install-rule.sh` uses `<config folder>/skills/centralize-ai-output/scripts/ai-output-dir.sh` when that file exists, else the copy that runs the installer. The dry run prints it as `script:`. Reason: an agent must not depend on the install of a different agent. Also, a run of the installer from a repository checkout then writes the installed path, so `outdated` means a real difference.
4. **The installer and the skill show the state clearly.** The actions are `create`, `add`, `outdated` and `unchanged`. A dry run shows a `diff -u` for each outdated rule, so the user sees the change before agreeing. `/centralize-ai-output` reports it in `status` and runs `--check` before `migrate`, `link` and `install-rule`.
5. **The project folder is the default.** `ai-output-choices.sh` and `video-output-choices.sh` recommend the project folder (`.ai`, or `video` in the current folder for `gen-motion-graphics`) and show it first. They recommend the central folder only when it is the only one that exists, and with no recommendation only when the central folder cannot be found and the project folder does not exist. Reason (issue #52): the central folder is a choice that the user makes on purpose, with `/centralize-ai-output` (after `link`, the skills do not ask) or with a choice in the question. A central folder that exists alone shows that the user chose it before.

"Outdated" means any difference between the installed rule and the rule that `install-rule.sh` writes now. This includes a different script path and a hand edit. A hand edit is lost on update, but the backup keeps it.

## Rejected options

- **A version marker in the rule** (for example `<!-- rule-version=2 -->`). A maintainer can forget to increase it, and then the check says "up to date" when it is not. `cmp` finds every difference and cannot be forgotten.
- **A symbolic link from `~/.claude/rules` to the asset.** It works only for Claude, the `{{SCRIPT}}` placeholder cannot be replaced in a link, and a reinstall of the skill can break the link.
- **A rule that only points to the asset** ("read `<skill>/assets/...`"). Agents follow an instruction to read another file less reliably than text that is loaded into the context, and each session needs one more read.
- **`@` imports in memory files.** Codex has no import. The `{{SCRIPT}}` path must be in a file, and a file that the installer writes into the skill folder makes `aiskills` see a local edit and stop updates of that skill.
- **An automatic rule update by a script.** It writes outside the project without the consent of the user.

## Limits

- A user who never updates the skill gets no message. The installer (`aiskills`) controls that.
- A Cursor rule is pasted by hand, so no script can check it.
- The note works only when the agent passes stderr on to the user. The new rule tells it to. An old rule does not, but the note speaks to the agent directly.
- A user who edits the rule on purpose sees the note in every session. `AI_AGENT_OUTPUT_RULE_CHECK=0` turns it off.

## How to change things

- **The rule text:** change only `assets/Centralize-AI-Output.md`. Do not add the key format or any other detail that the scripts own. Run the tests. After `aiskills update`, users get the note in their next session and can run `/centralize-ai-output install-rule`.
- **The project key format:** change all four copies of `ai-output-dir.sh` together, and `ai-output-choices.sh` if it is affected. Update the `centralize-ai-output` SKILL.md and `references/help.md`, the SKILL.md and `references/help.md` of the other skills that describe the key (`riper-5`, `pr-analysis`, `gen-motion-graphics`), README.md and the tests. Do not change the rule.
- **The `--check` output or the note:** `ai-output-dir.sh` reads the `outdated <file>` and `broken <file>` lines of `install-rule.sh --check`, and exit code 3. Change both scripts together, and copy `ai-output-dir.sh` to all four skills.
- **The recommendation rule:** change `ai-output-choices.sh` in `riper-5` and `pr-analysis` and `video-output-choices.sh` in `gen-motion-graphics` together. Update `skills/pr-analysis/references/help.md`, `skills/gen-motion-graphics/references/help.md`, README.md, decision 5 and the tests.
- **A new agent target:** add it to `install-rule.sh` (the folder, the file, whole file or block), to `script_for` if its skills folder is different, and to the tests and documents.
