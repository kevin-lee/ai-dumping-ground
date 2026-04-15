---
name: init-metals-mcp
description: Creates or updates .mcp.json in the current Scala project directory to configure metals-mcp. Use this skill when the user wants to add metals-mcp to a project, says "init metals-mcp", "add metals-mcp config", "set up metals-mcp for this project", "configure metals-mcp here", or is in a Scala project and asks to wire up any metals MCP integration.
---

# init-metals-mcp

Configures metals-mcp for the current Scala project by writing (or updating) `.mcp.json`
in the current working directory.

## Why these two args are both required

metals-mcp will fail at startup without them:

- `--workspace <path>` — metals-mcp does not auto-detect the project directory
- `--transport stdio` — the default transport is HTTP (Undertow); Claude Code expects stdio
  and times out after 30s waiting for a stdio handshake that never comes

## Config to write

Use `sh -c` so `$PWD` expands to the project root at process-launch time, rather than
hardcoding an absolute path. This keeps the config portable — it works even if the project
is moved, renamed, or cloned to a different location.

The metals-mcp entry to add:

```json
"metals-mcp": {
  "type": "stdio",
  "command": "sh",
  "args": ["-c", "metals-mcp --workspace \"$PWD\" --transport stdio"]
}
```

## Steps

1. Check whether `.mcp.json` already exists in the current directory.
   - If it exists: read and parse it.
   - If not: start from `{"mcpServers": {}}`.

2. Set `mcpServers["metals-mcp"]` to the entry above. Preserve all other `mcpServers` entries.

3. Write the result back to `.mcp.json` with 2-space indentation.

4. Tell the user:
   - Whether `.mcp.json` was created fresh or updated
   - To restart their Claude Code session for the change to take effect

## Notes

- `$PWD` is evaluated when Claude Code launches the MCP server process, which inherits
  the working directory from the terminal. Always launch `claude` from the project root.
- This is a project-level config — it only affects sessions opened in this directory.
- If there is also a global metals-mcp entry in `~/.claude.json` with no `--workspace`,
  it will conflict (that entry fails with `--workspace is required`). Suggest the user
  remove it: `claude mcp remove --scope user metals-mcp`.
- Requires metals-mcp v1.6.7+ (`cs install metals-mcp` via Coursier) and Java on PATH.
