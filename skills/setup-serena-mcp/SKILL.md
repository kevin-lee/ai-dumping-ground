---
name: setup-serena-mcp
description: Configures the serena MCP server for the current project so it works identically in the Claude Code CLI and in "Code" inside the Claude Desktop app. Writes a committed self-locating wrapper script plus a machine-local .mcp.json. Invoke only when the user explicitly runs the `/setup-serena-mcp` slash command — do not trigger on general phrases like "set up serena" or "add an MCP server" unless that exact slash command is used.
---

# setup-serena-mcp

Configures the [serena](https://github.com/oraios/serena) MCP server for the current project so the
**same setup works in both**:

- the **Claude Code CLI** (`claude` in a terminal), and
- **"Code" inside the Claude Desktop app** (embedded Claude Code — same engine as the CLI).

This does **not** target the Claude Desktop app's *plain chat* (that reads a separate global
`claude_desktop_config.json` and has no project concept). This skill is only about Claude Code's
project-level `.mcp.json`.

## Invocation mechanism

Use `uvx --from git+https://github.com/oraios/serena` so serena runs in an isolated, auto-fetched
environment — no pre-install or global-sync needed. The only prerequisite is `uv` on PATH
(`curl -LsSf https://astral.sh/uv/install.sh | sh` on Unix).

## Why a wrapper script instead of `$PWD`

serena needs the absolute project path (`--project`); it does not auto-detect the root. The obvious
approach — `sh -c 'uvx ... --project "$PWD"'` — is **not reliable**, because of a confirmed open bug
([claude-code#75266](https://github.com/anthropics/claude-code/issues/75266)):

- When Claude Code runs **embedded in the Claude Desktop app**, it launches stdio MCP servers with
  `cwd = $HOME` instead of the project root. So `$PWD` (and any relative `command` path) resolves to
  the home directory, and serena opens the wrong project. The CLI is unaffected, but we want one
  config that works in both.
- `${CLAUDE_PROJECT_DIR}` does **not** help in the `command`/`args` position: Claude Code does not
  populate it in the server-launch environment there (`claude mcp list` reports
  `Missing environment variables: CLAUDE_PROJECT_DIR`). Verified against Claude Code 2.1.x.

The robust fix is a **self-locating wrapper script** committed inside the project. The wrapper
derives the project root from **its own on-disk location**, independent of the launcher's cwd — so
it computes the correct `--project` in both the CLI and the embedded app. Only the path to the
wrapper must be cwd-independent, so `.mcp.json` points at it by **absolute path** (see portability
note).

## Which serena context

Use `--context claude-code` for both surfaces — "Code" in the Desktop app *is* Claude Code, so the
same context applies. It tunes serena's tool descriptions and reminders for this client.

## Files this skill manages

1. `<project>/.claude/serena-mcp.sh` — committed, portable, self-locating wrapper.
2. `<project>/.mcp.json` — machine-local (absolute path inside), **gitignored**, regenerated per
   machine by re-running this skill.
3. `<project>/.gitignore` — ensure `.mcp.json` is ignored.

### Wrapper script: `.claude/serena-mcp.sh`

POSIX `sh`, no `readlink -f` (BSD `readlink` on older macOS lacks `-f`); uses `pwd -P`:

```sh
#!/bin/sh
# Self-locate the project root from this script's own path, independent of cwd.
# .claude/serena-mcp.sh  ->  project root is one level up from .claude/
scriptdir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
root=$(CDPATH= cd -- "$scriptdir/.." && pwd -P)
exec uvx --from git+https://github.com/oraios/serena serena start-mcp-server \
  --context claude-code --project "$root"
```

### `.mcp.json` entry (absolute `command`)

The skill fills in the real absolute path to the wrapper at run time:

```json
"serena": {
  "type": "stdio",
  "command": "/absolute/path/to/project/.claude/serena-mcp.sh"
}
```

## Steps

1. Determine the absolute path of the current project root (the directory `.mcp.json` will live in).

2. Write `.claude/serena-mcp.sh` with the wrapper above. Create `.claude/` if needed. `chmod +x` it.

3. Read/parse `.mcp.json` if it exists. If the top-level shape is not `{"mcpServers": {...}}`, stop
   and ask before overwriting (a different shape likely means the file is tool-managed). Otherwise
   start from `{"mcpServers": {}}`. Set `mcpServers["serena"]` to the entry above with the
   **absolute** wrapper path. Preserve other entries; overwrite an existing `serena` entry and note
   it. Write back with 2-space indentation and a trailing newline.

4. Ensure `.mcp.json` is gitignored: if `<project>/.gitignore` doesn't already ignore it, append a
   `.mcp.json` line. (The wrapper under `.claude/` stays committed — it's portable.)

5. Tell the user:
   - That `.claude/serena-mcp.sh` (portable, commit it) and `.mcp.json` (machine-local, gitignored)
     were written, and that teammates/other machines re-run this skill once to generate their own
     `.mcp.json`.
   - To restart their Claude Code session (CLI) or reopen the "Code" panel in Desktop.
   - That `uv` must be on PATH; if missing: `curl -LsSf https://astral.sh/uv/install.sh | sh`.
   - That the first launch is slow while `uvx` fetches and caches serena from git; later launches
     are fast.
   - That this works in both the CLI and "Code" in the Desktop app, but **not** Desktop plain chat.

## Notes

- Why absolute path in `.mcp.json` (and hence gitignored): the wrapper path must not depend on cwd,
  or bug #75266 breaks the embedded app. Absolute is the only cwd-independent way to *find* the
  wrapper; the wrapper itself is portable and committed. Re-running this skill regenerates
  `.mcp.json` cheaply.
- Because the embedded app launches with a minimal environment, if `uv`/`uvx` isn't found, add its
  directory to `PATH` via an `env` block on the `.mcp.json` entry, or hardcode the absolute `uvx`
  path inside the wrapper (find it with `which uvx`).
- To pin a serena version instead of tracking `main`, change the `--from` target in the wrapper to
  `git+https://github.com/oraios/serena@<tag-or-sha>`.
- If a global `serena` entry exists in `~/.claude.json`, the project entry takes precedence for
  sessions here but the two can drift. If behavior is unexpected: `claude mcp remove --scope user serena`.
