# ai-dumping-ground

Use [ai-skills](https://github.com/kevin-lee/ai-skills) to install the skills in this repository.

```
aiskills install kevin-lee/ai-dumping-ground
```

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
