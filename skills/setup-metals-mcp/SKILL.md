---
name: setup-metals-mcp
description: Configures metals-mcp for the current Scala project so it works identically in the Claude Code CLI and in "Code" inside the Claude Desktop app. Writes a committed self-locating wrapper script plus a machine-local .mcp.json. Use when the user wants to add metals-mcp to a project, says "setup metals-mcp", "add metals-mcp config", "configure metals-mcp here", or is in a Scala project and asks to wire up any metals MCP integration.
---

# setup-metals-mcp

Configures metals-mcp for the current Scala project so the **same setup works in both**:

- the **Claude Code CLI** (`claude` in a terminal), and
- **"Code" inside the Claude Desktop app** (embedded Claude Code — same engine as the CLI).

This does **not** target the Claude Desktop app's *plain chat* (that reads a separate global
`claude_desktop_config.json` and has no project concept). This skill is only about Claude Code's
project-level `.mcp.json`.

## Why a wrapper script instead of `$PWD`

metals-mcp needs the absolute workspace path (`--workspace`); it does not auto-detect the project.
The obvious approach — `sh -c 'metals-mcp --workspace "$PWD" ...'` — is **not reliable**, because
of a confirmed open bug ([claude-code#75266](https://github.com/anthropics/claude-code/issues/75266)):

- When Claude Code runs **embedded in the Claude Desktop app**, it launches stdio MCP servers with
  `cwd = $HOME` instead of the project root. So `$PWD` (and any relative `command` path) resolves to
  the home directory, and metals opens the wrong workspace. The CLI is unaffected, but we want one
  config that works in both.
- `${CLAUDE_PROJECT_DIR}` does **not** help in the `command`/`args` position: Claude Code does not
  populate it in the server-launch environment there. `claude mcp list` reports
  `Missing environment variables: CLAUDE_PROJECT_DIR` if you try. (Verified against Claude Code
  2.1.x.)

The robust fix is a **self-locating wrapper script** committed inside the project. The wrapper
derives the project root from **its own on-disk location**, which is independent of the launcher's
cwd — so it computes the correct `--workspace` in both the CLI and the embedded app. The only piece
that must be cwd-independent is the path to the wrapper itself, so `.mcp.json` points at it by
**absolute path** (see the portability note below).

## Files this skill manages

1. `<project>/.claude/metals-mcp.sh` — committed, portable, self-locating wrapper.
2. `<project>/.mcp.json` — machine-local (absolute path inside), **gitignored**, regenerated per
   machine by re-running this skill.
3. `<project>/.gitignore` — ensure `.mcp.json` is ignored.

### Wrapper script: `.claude/metals-mcp.sh`

POSIX `sh`, no `readlink -f` (BSD `readlink` on older macOS lacks `-f`); uses `pwd -P` to resolve
the script's directory:

```sh
#!/bin/sh
# Self-locate the project root from this script's own path, independent of cwd.
# .claude/metals-mcp.sh  ->  project root is one level up from .claude/
scriptdir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
root=$(CDPATH= cd -- "$scriptdir/.." && pwd -P)
exec metals-mcp --workspace "$root" --transport stdio
```

`--transport stdio` is still required: metals-mcp defaults to HTTP (Undertow) and Claude Code
expects stdio (it times out after 30s otherwise).

### `.mcp.json` entry (absolute `command`)

The skill fills in the real absolute path to the wrapper at run time:

```json
"metals-mcp": {
  "type": "stdio",
  "command": "/absolute/path/to/project/.claude/metals-mcp.sh"
}
```

## Steps

1. Determine the absolute path of the current project root (the directory `.mcp.json` will live in).

2. Write `.claude/metals-mcp.sh` with the wrapper above. Create `.claude/` if needed. `chmod +x` it.

3. Read/parse `.mcp.json` if it exists (start from `{"mcpServers": {}}` otherwise). Set
   `mcpServers["metals-mcp"]` to the entry above with the **absolute** wrapper path filled in.
   Preserve all other `mcpServers` entries; overwrite an existing `metals-mcp` entry and note it.
   Write back with 2-space indentation and a trailing newline.

4. Ensure `.mcp.json` is gitignored: if `<project>/.gitignore` doesn't already ignore it, append a
   `.mcp.json` line. (The wrapper under `.claude/` stays committed — it's portable.)

5. Tell the user:
   - That `.claude/metals-mcp.sh` (portable, commit it) and `.mcp.json` (machine-local, gitignored)
     were written, and that teammates/other machines re-run this skill once to generate their own
     `.mcp.json`.
   - To restart their Claude Code session (CLI) or reopen the "Code" panel in Desktop for the
     change to take effect.
   - That this works in both the CLI and "Code" in the Desktop app, but **not** Desktop plain chat.

## Notes

- Requires metals-mcp v1.6.7+ (`cs install metals-mcp` via Coursier) and Java on PATH. Because the
  embedded app launches with a minimal environment, if metals-mcp can't find `java`, add
  `JAVA_HOME`/`PATH` via an `env` block on the `.mcp.json` entry, or set them inside the wrapper.
- Why absolute path in `.mcp.json` (and hence gitignored): the path to the wrapper must not depend
  on cwd, or bug #75266 breaks the embedded app. An absolute path is the only cwd-independent way to
  *find* the wrapper; the wrapper itself is portable and committed. The `.mcp.json` is cheap to
  regenerate — just re-run this skill.
- If a global metals-mcp entry exists in `~/.claude.json` with no `--workspace`, it conflicts (fails
  with `--workspace is required`). Suggest: `claude mcp remove --scope user metals-mcp`.
