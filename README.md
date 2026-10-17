# ai-dumping-ground

Use [ai-skills](https://github.com/kevin-lee/ai-skills) to install the skills in this repository.

```
aiskills install kevin-lee/ai-dumping-ground
```

## Skill output folder

`riper-5`, `pr-analysis` and `gen-motion-graphics` write their outputs to one central folder, `${AI_AGENT_OUTPUT_DIR:-~/.ai}/<project>/`, not into the project. Thus the outputs of all projects are in one location, and they cannot be committed by accident.

`<project>` identifies the project:

- In a Git repository with a remote: `<host>/<owner>/<repo>` from the `origin` remote, or from the first remote by name when there is no `origin`. The user, the credentials, the port and the `.git` suffix are removed, and the key is in lowercase. All clones and worktrees of one repository share one folder. For example, `git@github.com:kevin-lee/ai-dumping-ground.git` gives `~/.ai/github.com/kevin-lee/ai-dumping-ground/`.
- In a Git repository with no remote or with a local-path remote, and outside Git: `local/<absolute path>`. For example, `/Users/me/work/notes` gives `~/.ai/local/Users/me/work/notes/`.
- A path with a symbolic link keeps the symbolic link, as `$PWD` shows it.

Layout:

```
~/.ai/<project>/
├── .project-info   kind, remote, and every path that used this folder
├── plans/          riper-5 plans
├── done/           riper-5 plans after review
├── docs/pr/        pr-analysis reports
└── video/          gen-motion-graphics videos
```

`AI_AGENT_OUTPUT_DIR` changes the root. An absolute path works, and so do `~`, `~/x`, `$HOME/x` and `${HOME}/x`, also when a settings file does not expand them. A relative path or `~user/x` is an error. Each skill has `scripts/ai-output-dir.sh`, which prints the folder for the current project. `--root` prints only the root.

### Migration from the old `.ai/` folder

Before this change, the skills wrote to `.ai/` in each project. When a skill finds old outputs there, it offers to move them. You can also run the migration yourself from the project folder, with `<skill>` as the installed skill folder:

```
sh <skill>/scripts/migrate-ai-output.sh plans done            # riper-5, dry run
sh <skill>/scripts/migrate-ai-output.sh docs/pr               # pr-analysis, dry run
sh <skill>/scripts/migrate-ai-output.sh video                 # gen-motion-graphics, dry run
sh <skill>/scripts/migrate-ai-output.sh --from "$PWD" video   # gen-motion-graphics, old ./video outside Git
```

Without an option, the script only shows what it would do. Add `--apply` to move the files. It never deletes and never overwrites a file. A file whose destination exists stays in place and is reported. Other content, for example `.ai/examples`, is not touched. At the end it lists what is left, so you can decide what to do with it.

### Tests

[test-ai-output-scripts.sh](scripts/skills/test-ai-output-scripts.sh) runs `ai-output-dir.sh` and `migrate-ai-output.sh` against throwaway Git repositories and folders in a temporary folder and checks the results. It also checks that the copies in the three skills are identical. It never touches your real output folder. It needs `bash` and `git`, and no network access.

```
bash scripts/skills/test-ai-output-scripts.sh
```

Each check prints `PASS`, `FAIL` or `SKIP`, and the script exits with 1 if any check fails. Set `KEEP_TEST_DIR=1` to keep the temporary folder for inspection, or `SH_UNDER_TEST` to run the scripts with a different shell (default: `/bin/sh`). The output is in color when it goes to a terminal. Set `NO_COLOR=1` to turn the color off, or `FORCE_COLOR=1` to keep it in a pipe.

[test-ai-output-scripts-linux.sh](scripts/skills/test-ai-output-scripts-linux.sh) runs the same tests on Linux in Debian 12, Debian 13 and Alpine containers, using Podman or Docker:

```
bash scripts/skills/test-ai-output-scripts-linux.sh
```

To test other images, pass their names. This needs network access to pull the images and install `git` in them.

## Scripts

### Claude Code status line

[setup-statusline.sh](scripts/config/claude/setup-statusline.sh) installs [statusline-command.sh](scripts/config/claude/statusline-command.sh) as the Claude Code status line. The status line shows the model and effort level, the current folder and git branch, context window usage, the time left on the prompt cache, the session cost and the session duration.

Requirements: `bash` and `jq` on macOS or Linux. Running it from GitHub also needs `curl`.

Run it from GitHub:

```
curl -fsSL https://raw.githubusercontent.com/kevin-lee/ai-dumping-ground/main/scripts/config/claude/setup-statusline.sh | bash
```

Or from a clone of this repository:

```
bash scripts/config/claude/setup-statusline.sh
```

The script uses the Claude Code config folder, which is `$CLAUDE_CONFIG_DIR` if it is set, otherwise `~/.claude`. To install into a different folder, set it for the script:

```
curl -fsSL https://raw.githubusercontent.com/kevin-lee/ai-dumping-ground/main/scripts/config/claude/setup-statusline.sh | CLAUDE_CONFIG_DIR=/path/to/claude-config bash
```

What it does:

- Copies `statusline-command.sh` into the config folder.
- Sets `statusLine.type` to `command` and `statusLine.command` in the config folder's `settings.json`. The command is `bash ~/.claude/statusline-command.sh`, or `bash "$CLAUDE_CONFIG_DIR/statusline-command.sh"` when `CLAUDE_CONFIG_DIR` points to another folder.
- Keeps every other setting, including other `statusLine` fields such as `padding` and `refreshInterval`.
- Before changing an existing file, saves a copy next to it as `<file name>.bak.<YYYYmmdd-HHMMSS>` and prints its path.
- Creates the config folder and `settings.json` if they don't exist.
- Changes nothing if both files are already up to date.
- Stops without changing anything if `settings.json` is not valid JSON, is not a single JSON object, or has a `statusLine` that is not an object.
- If `settings.json` is a symlink, keeps the symlink and updates the file it points to.

If Claude Code is running and the status line does not appear, restart Claude Code.

#### Tests

[test-setup-statusline.sh](scripts/config/claude/test-setup-statusline.sh) runs `setup-statusline.sh` against throwaway config folders in a temporary folder and checks the results. It never touches your real Claude Code config. It needs `bash` and `jq`, and no network access.

```
bash scripts/config/claude/test-setup-statusline.sh
```

Each check prints `PASS`, `FAIL` or `SKIP`, and the script exits with 1 if any check fails. Set `KEEP_TEST_DIR=1` to keep the temporary folder for inspection, or `BASH_UNDER_TEST` to run the installer with a different `bash` (default: `/bin/bash`).

[test-setup-statusline-linux.sh](scripts/config/claude/test-setup-statusline-linux.sh) runs the same tests on Linux in Debian 12, Debian 13 and Alpine containers, using Podman or Docker:

```
bash scripts/config/claude/test-setup-statusline-linux.sh
```

To test other images, pass their names, for example `bash scripts/config/claude/test-setup-statusline-linux.sh debian:bookworm-slim`. This needs network access to pull the images and install `jq` in them.
