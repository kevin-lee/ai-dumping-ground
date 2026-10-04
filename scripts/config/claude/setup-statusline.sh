#!/bin/bash
# Installs statusline-command.sh into the Claude Code config folder ($CLAUDE_CONFIG_DIR or ~/.claude) and sets "statusLine" in its settings.json.
#
# Usage:
#   bash scripts/config/claude/setup-statusline.sh
#   curl -fsSL https://raw.githubusercontent.com/kevin-lee/ai-dumping-ground/main/scripts/config/claude/setup-statusline.sh | bash

set -euo pipefail

SCRIPT_NAME="statusline-command.sh"
SOURCE_URL="https://raw.githubusercontent.com/kevin-lee/ai-dumping-ground/main/scripts/config/claude/statusline-command.sh"
# shellcheck disable=SC2016 # $cmd is a jq variable, not a shell one
UPDATE_FILTER='.statusLine = ((.statusLine // {}) + {type: "command", command: $cmd})'
# shellcheck disable=SC2016 # $cmd is a jq variable, not a shell one
MATCH_FILTER='.statusLine.type == "command" and .statusLine.command == $cmd'

CONFIG_DIR=""
STATUSLINE_COMMAND=""
TMP_DIR=""
PENDING_TMP=""

die() {
  printf 'error: %s\n' "$1" >&2
  exit 1
}

info() {
  printf '%s\n' "$1"
}

cleanup() {
  if [ -n "$PENDING_TMP" ]; then rm -f "$PENDING_TMP"; fi
  if [ -n "$TMP_DIR" ]; then rm -rf "$TMP_DIR"; fi
}

# Follows symlinks without `readlink -f`, which older macOS does not have.
resolve_link() {
  local path="$1" hops=0 target
  while [ -L "$path" ]; do
    hops=$((hops + 1))
    if [ "$hops" -gt 40 ]; then
      die "$1 has too many levels of symlinks. Nothing was changed."
    fi
    target=$(readlink "$path")
    case "$target" in
      /*) path="$target" ;;
      *) path="$(dirname "$path")/$target" ;;
    esac
  done
  printf '%s\n' "$path"
}

resolve_config() {
  if [ -z "${HOME:-}" ]; then die "HOME is not set."; fi
  local home_claude="${HOME%/}/.claude"
  local dir="${CLAUDE_CONFIG_DIR:-}"

  if [ -z "$dir" ]; then
    CONFIG_DIR="$home_claude"
    STATUSLINE_COMMAND="bash ~/.claude/$SCRIPT_NAME"
    return
  fi

  case "$dir" in
    /*) ;;
    *) die "CLAUDE_CONFIG_DIR must be an absolute path: $dir" ;;
  esac
  while [ "$dir" != "/" ] && [ "${dir%/}" != "$dir" ]; do
    dir="${dir%/}"
  done

  CONFIG_DIR="$dir"
  if [ "$dir" = "$home_claude" ]; then
    STATUSLINE_COMMAND="bash ~/.claude/$SCRIPT_NAME"
  else
    # Kept literal so Claude Code's shell expands it when it runs the status line.
    STATUSLINE_COMMAND="bash \"\$CLAUDE_CONFIG_DIR/$SCRIPT_NAME\""
  fi
}

check_target() {
  local path="$1" resolved="$2"
  if [ -L "$path" ] && [ ! -e "$resolved" ]; then
    die "$path is a symlink to $resolved, which does not exist. Nothing was changed."
  fi
  if [ -e "$resolved" ] && [ ! -f "$resolved" ]; then
    die "$resolved is not a regular file. Nothing was changed."
  fi
}

# Prints missing, blank or object. Dies if the file is not what settings.json must be.
settings_state() {
  local file="$1" err
  if [ ! -e "$file" ]; then
    printf 'missing\n'
    return
  fi
  if [ -z "$(LC_ALL=C tr -d ' \t\r\n' < "$file")" ]; then
    printf 'blank\n'
    return
  fi
  if ! err=$(jq -s . "$file" 2>&1 >/dev/null); then
    die "$file is not valid JSON. Nothing was changed.
$err"
  fi
  if ! jq -e -s 'length == 1 and (.[0] | type == "object")' "$file" >/dev/null 2>&1; then
    die "$file must contain a single JSON object. Nothing was changed."
  fi
  if ! jq -e '.statusLine == null or (.statusLine | type == "object")' "$file" >/dev/null 2>&1; then
    die "\"statusLine\" in $file is not an object. Fix or remove it, then run this script again. Nothing was changed."
  fi
  printf 'object\n'
}

# Prints the path of the statusline-command.sh to install, downloading it when this script is not run from a file.
fetch_source() {
  local self="${BASH_SOURCE[0]:-}" local_source downloaded
  if [ -n "$self" ] && [ -f "$self" ]; then
    local_source="$(dirname "$self")/$SCRIPT_NAME"
    if [ -f "$local_source" ]; then
      printf '%s\n' "$local_source"
      return
    fi
  fi

  if ! command -v curl >/dev/null 2>&1; then
    die "curl is required to download $SCRIPT_NAME"
  fi
  downloaded="$TMP_DIR/$SCRIPT_NAME"
  if ! curl -fsSL "$SOURCE_URL" -o "$downloaded"; then
    die "failed to download $SOURCE_URL. Nothing was changed."
  fi
  if [ ! -s "$downloaded" ]; then
    die "downloaded file is not a shell script: $SOURCE_URL. Nothing was changed."
  fi
  case "$(head -n 1 "$downloaded")" in
    '#!'*) ;;
    *) die "downloaded file is not a shell script: $SOURCE_URL. Nothing was changed." ;;
  esac
  printf '%s\n' "$downloaded"
}

# Replaces the target in one rename, so Claude Code never reads a half-written file.
install_file() {
  local content="$1" target="$2" new_mode="$3"
  PENDING_TMP=$(mktemp "$(dirname "$target")/.$(basename "$target").XXXXXX")
  if [ -e "$target" ]; then
    cp -p "$target" "$PENDING_TMP"
  else
    chmod "$new_mode" "$PENDING_TMP"
  fi
  cat "$content" > "$PENDING_TMP"
  mv -f "$PENDING_TMP" "$target"
  PENDING_TMP=""
}

main() {
  if ! command -v jq >/dev/null 2>&1; then
    die "jq is required but was not found. Install jq and run this script again."
  fi

  resolve_config
  TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/setup-statusline.XXXXXX")
  trap cleanup EXIT

  local settings_path settings_resolved state settings_new settings_update=1
  settings_path="$CONFIG_DIR/settings.json"
  settings_resolved=$(resolve_link "$settings_path")
  check_target "$settings_path" "$settings_resolved"
  state=$(settings_state "$settings_resolved")
  settings_new="$TMP_DIR/settings.json"
  if [ "$state" = "object" ]; then
    jq --arg cmd "$STATUSLINE_COMMAND" "$UPDATE_FILTER" "$settings_resolved" > "$settings_new"
  else
    jq -n --arg cmd "$STATUSLINE_COMMAND" "{} | $UPDATE_FILTER" > "$settings_new"
  fi
  if ! jq -e 'type == "object"' "$settings_new" >/dev/null 2>&1; then
    die "failed to build the new $settings_path. Nothing was changed."
  fi
  if [ "$state" = "object" ] && jq -e --arg cmd "$STATUSLINE_COMMAND" "$MATCH_FILTER" "$settings_resolved" >/dev/null 2>&1; then
    settings_update=0
  fi

  local source_script target_path target_resolved script_update=1
  source_script=$(fetch_source)
  target_path="$CONFIG_DIR/$SCRIPT_NAME"
  target_resolved=$(resolve_link "$target_path")
  check_target "$target_path" "$target_resolved"
  if [ -f "$target_resolved" ] && cmp -s "$source_script" "$target_resolved"; then
    script_update=0
  fi

  if [ "$script_update" -eq 0 ] && [ "$settings_update" -eq 0 ]; then
    info "No difference found. $target_path and the statusLine in $settings_path are already up to date. Installation skipped."
    exit 0
  fi

  local ts script_backup settings_backup
  ts=$(date +%Y%m%d-%H%M%S)
  script_backup="$CONFIG_DIR/$SCRIPT_NAME.bak.$ts"
  settings_backup="$CONFIG_DIR/settings.json.bak.$ts"
  if [ "$script_update" -eq 1 ] && [ -e "$target_resolved" ] && { [ -e "$script_backup" ] || [ -L "$script_backup" ]; }; then
    die "backup file already exists: $script_backup. Nothing was changed."
  fi
  if [ "$settings_update" -eq 1 ] && [ -e "$settings_resolved" ] && { [ -e "$settings_backup" ] || [ -L "$settings_backup" ]; }; then
    die "backup file already exists: $settings_backup. Nothing was changed."
  fi

  if [ ! -d "$CONFIG_DIR" ]; then
    mkdir -p "$CONFIG_DIR"
    info "Created $CONFIG_DIR"
  fi

  # Script first: if the settings step then fails, no command points to a missing file.
  if [ "$script_update" -eq 1 ]; then
    if [ -e "$target_resolved" ]; then
      cp -p "$target_resolved" "$script_backup"
      info "Backed up $target_path to $script_backup"
    fi
    install_file "$source_script" "$target_resolved" 644
    info "Installed $target_path"
  else
    info "$target_path is already up to date"
  fi

  if [ "$settings_update" -eq 1 ]; then
    if [ -e "$settings_resolved" ]; then
      cp -p "$settings_resolved" "$settings_backup"
      info "Backed up $settings_path to $settings_backup"
    fi
    install_file "$settings_new" "$settings_resolved" 600
    info "Set statusLine.command to $STATUSLINE_COMMAND in $settings_path"
  else
    info "statusLine in $settings_path is already up to date"
  fi

  info "Done. If Claude Code is running and the status line does not appear, restart Claude Code."
}

main "$@"
