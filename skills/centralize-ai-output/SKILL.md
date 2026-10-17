---
name: centralize-ai-output
description: Move everything in a project's .ai/ folder into the central AI agent output folder (${AI_AGENT_OUTPUT_DIR:-~/.ai}/<project>), replace .ai with a symbolic link to it, and install a global rule so AI agents write their outputs there unless the user names another location. Use when the user runs /centralize-ai-output, asks where the AI outputs of a project are, asks to move or migrate the .ai/ folder, or asks agents to keep their outputs out of the project.
---

# centralize-ai-output

AI agents write plans, reports, notes, videos and other outputs. This skill keeps them out of the project, in one central folder with one folder for each project, and makes agents use that folder by default.

`<skill>` below means this skill's directory. The scripts are in `<skill>/scripts/`. They are POSIX `sh` scripts. Run them from the project folder.

## Rules

- The folder is `${AI_AGENT_OUTPUT_DIR:-~/.ai}/<project>`. `sh <skill>/scripts/ai-output-dir.sh` prints it. Do not calculate it yourself.
- `<project>` is `<host>/<owner>/<repo>` of the Git remote (`origin`, else the first remote by name), without the user, the credentials, the port and `.git`, in lowercase. All clones and worktrees of one repository share one folder. Without a remote, or outside Git, it is `local/<absolute path>`, and the path keeps symbolic links.
- `AI_AGENT_OUTPUT_DIR` can be an absolute path, `~`, or a path that starts with `~/`, `$HOME/` or `${HOME}/`.
- Each project folder has a hidden `.project-info` file with the remote and every path that used the folder.
- Every step starts with a dry run. Run a step with `--apply` only after the user explicitly agrees to that step. Never delete or overwrite a file, except what the `link` step lists and the user accepts.
- If a script exits with an error, show its message and stop. If a sandbox blocks a write, tell the user to allow writes to the root folder (`sh <skill>/scripts/ai-output-dir.sh --root` prints it) or to the agent config folder.

## Arguments

The text after `/centralize-ai-output` selects the step:

| Argument | Step |
|---|---|
| none or `status` | status, then offer the next steps |
| `migrate` | migrate |
| `link` | link |
| `install-rule` | install-rule |
| `help`, `--help`, `-h` | Reply with the text in `references/help.md`, as it is, and stop |

## status

Run these and report the results in short form:

1. `sh <skill>/scripts/ai-output-dir.sh --print-only`: the output folder.
2. `sh <skill>/scripts/migrate-ai-output.sh --check --all`: the entries of `.ai/` that still have files.
3. `sh <skill>/scripts/link-ai-folder.sh`: the link state.
4. `sh <skill>/scripts/install-rule.sh`: the rule state of each agent.

Then offer the steps that are not done yet, in this order: migrate, link, install-rule. Ask the user which to run, with a choice prompt if the agent has one.

## migrate

1. Run `sh <skill>/scripts/migrate-ai-output.sh --all` (dry run) and show the result. It moves every entry of `.ai/`, files at the top level included. `.DS_Store` files stay.
2. Ask the user. Only after an explicit yes, run it with `--apply`.
3. Report what moved, what is the same, the conflicts and what is left. A conflict means that a different file with the same name exists in the output folder. Both files stay. Let the user decide what to do with them.

## link

The link makes `.ai` a symbolic link to the output folder, so any agent or tool that writes `.ai/...` writes into the output folder.

1. Run `sh <skill>/scripts/link-ai-folder.sh` (dry run). If it exits with 4, explain why (files are still in `.ai`, `.ai` is tracked by Git, or `.ai` links to a different place) and stop.
2. Show what it removes. This is the only step that removes anything: `.DS_Store` files and empty folders in `.ai`. Ask each time. Only after an explicit yes, run it with `--apply`.
3. If it prints the gitignore warning, explain it: a `.ai/` pattern matches only a folder, not a symbolic link, so `.ai` shows as untracked. The fix is `.ai` (no slash) in the project's `.gitignore` or in the global gitignore file. Do not change any gitignore file unless the user asks.

## install-rule

The rule tells agents to write their outputs into the output folder unless the user names another location.

1. Run `sh <skill>/scripts/install-rule.sh` (dry run). It lists `create`, `update` or `unchanged` for each agent whose config folder exists:
   - Claude: `~/.claude/rules/Centralize-AI-Output.md` (or under `$CLAUDE_CONFIG_DIR`)
   - Codex: a marked block in `~/.codex/AGENTS.md` (or under `$CODEX_HOME`)
   - Gemini: a marked block in `~/.gemini/GEMINI.md`
2. Ask the user. Only after an explicit yes, run it with `--apply`. Use `--target claude`, `--target codex` or `--target gemini` when the user wants only some of them. Each changed file gets a backup, `<file>.bak.<YYYYmmdd-HHMMSS>`.
3. Cursor has no user rule file. Show the text from `sh <skill>/scripts/install-rule.sh --print`, and tell the user to paste it into Cursor Settings > Rules > User Rules.
4. The rule takes effect in new sessions.
