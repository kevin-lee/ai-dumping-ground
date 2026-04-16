---
name: setup-serena-mcp
description: Creates or updates .mcp.json in the current project directory to configure the serena MCP server for Claude Code. Invoke only when the user explicitly runs the `/setup-serena-mcp` slash command — do not trigger on general phrases like "set up serena" or "add an MCP server" unless that exact slash command is used.
---

# setup-serena-mcp

Configures the [serena](https://github.com/oraios/serena) MCP server for the current project
by writing (or updating) `.mcp.json` in the current working directory.

## Invocation mechanism

Use `uvx --from git+https://github.com/oraios/serena` so serena runs in an isolated,
auto-fetched environment. This means the user doesn't need to pre-install serena or keep
a global install in sync — `uvx` handles caching and resolution. The only prerequisite is
`uv` on PATH (install via `curl -LsSf https://astral.sh/uv/install.sh | sh` on Unix).

## Why these flags matter

serena runs correctly under Claude Code with both:

- `--context claude-code` — tunes serena's tool descriptions and reminders for Claude Code.
  The default context is generic and drops some Claude Code-specific behavior that the
  serena maintainers ship for this client.
- `--project <path>` — serena does not auto-detect the project root; without it, serena
  either refuses to start or operates on the wrong directory.

## Config to write

Wrap the launch in `sh -c` so `$PWD` expands to the project root at process-launch time
rather than hardcoding an absolute path. This keeps `.mcp.json` portable — it survives
the project being moved, renamed, or cloned to a different location, and it works for
every teammate who checks out the repo.

The serena entry to add:

```json
"serena": {
  "type": "stdio",
  "command": "sh",
  "args": [
    "-c",
    "uvx --from git+https://github.com/oraios/serena serena start-mcp-server --context claude-code --project \"$PWD\""
  ]
}
```

## Steps

1. Check whether `.mcp.json` already exists in the current directory.
   - If it exists: read and parse it. If the top-level shape is not
     `{"mcpServers": {...}}`, stop and ask the user before overwriting — a different
     shape likely means the file is managed by a tool you don't want to stomp on.
   - If not: start from `{"mcpServers": {}}`.

2. Set `mcpServers["serena"]` to the entry above. Preserve all other `mcpServers` entries.
   If a `serena` entry already exists, overwrite it and note the overwrite to the user.

3. Write the result back to `.mcp.json` with 2-space indentation and a trailing newline.

4. Tell the user:
   - Whether `.mcp.json` was created fresh or updated, and whether an existing `serena`
     entry was overwritten.
   - To restart their Claude Code session for the change to take effect.
   - That `uv` must be on PATH for serena to launch. If they don't have it:
     `curl -LsSf https://astral.sh/uv/install.sh | sh`.
   - That the first launch will be slow while `uvx` fetches and caches serena from git;
     subsequent launches are fast.

## Notes

- `$PWD` is evaluated when Claude Code launches the MCP server process, which inherits
  the working directory from the terminal. Launch `claude` from the project root so the
  path resolves correctly.
- This is a project-level config — it only affects sessions opened in this directory.
  Commit `.mcp.json` to the repo if you want teammates to share the setup.
- If there is also a global `serena` entry in `~/.claude.json` (e.g. from
  `claude mcp add --scope user serena ...`), the project-level entry takes precedence for
  sessions opened here, but the two configs can drift. If the user reports unexpected
  behavior, suggest: `claude mcp remove --scope user serena`.
- To pin a specific serena version instead of tracking `main`, change the `--from` target
  to `git+https://github.com/oraios/serena@<tag-or-sha>`.
