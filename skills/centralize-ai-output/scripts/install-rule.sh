#!/bin/sh
# Installs the Centralize AI Output rule into the global instruction files of AI agents, so they write their outputs
# into the AI agent output folder unless the user names another location.
#
# Usage:
#   sh install-rule.sh [--target claude|codex|gemini]...          dry run. Print what would change
#   sh install-rule.sh --apply [--target claude|codex|gemini]...  write the rule
#   sh install-rule.sh --print                                    print the rule text
#
# Targets (default: each target whose config folder exists):
#   claude  ${CLAUDE_CONFIG_DIR:-~/.claude}/rules/Centralize-AI-Output.md, the whole file
#   codex   ${CODEX_HOME:-~/.codex}/AGENTS.md, a block between the centralize-ai-output start and end markers
#   gemini  ~/.gemini/GEMINI.md, the same block
# Cursor has no user rule file. Paste the text from --print into Cursor Settings > Rules > User Rules.
#
# The rule text is ../assets/Centralize-AI-Output.md, with {{SCRIPT}} replaced by the absolute path of
# ai-output-dir.sh in this folder.
# Before it changes an existing file, the script copies it to <file>.bak.<YYYYmmdd-HHMMSS>. Content outside the block
# is kept. A symbolic link stays a symbolic link, and the file that it points to is changed.
#
# Exit codes: 0 success, 1 a write failed or the markers in a file are broken, 2 bad usage.

set -u

me=install-rule.sh

die() { # exit code, message
  printf '%s: %s\n' "$me" "$2" >&2
  exit "$1"
}

HERE=$(cd -- "$(dirname -- "$0")" && pwd) || exit 1
TEMPLATE=$HERE/../assets/Centralize-AI-Output.md
START='<!-- centralize-ai-output:start -->'
END='<!-- centralize-ai-output:end -->'

usage="usage: sh $me [--apply] [--target claude|codex|gemini]... | sh $me --print"
mode=dry
targets=
while [ $# -gt 0 ]; do
  case $1 in
    --apply)
      [ "$mode" = dry ] || die 2 "$usage"
      mode=apply ;;
    --print)
      [ "$mode" = dry ] || die 2 "$usage"
      mode=print ;;
    --target)
      [ $# -ge 2 ] || die 2 "$usage"
      case $2 in
        claude | codex | gemini) targets="$targets $2" ;;
        *) die 2 "unknown target: $2. $usage" ;;
      esac
      shift ;;
    *)
      die 2 "$usage" ;;
  esac
  shift
done
if [ "$mode" = print ] && [ -n "$targets" ]; then die 2 "$usage"; fi

[ -f "$TEMPLATE" ] || die 1 "the rule template is missing: $TEMPLATE"
case ${HOME:-} in
  /*) ;;
  *) die 2 "HOME is not set to an absolute path" ;;
esac

script_path=$HERE/ai-output-dir.sh
escaped=$(printf '%s' "$script_path" | sed 's/[\\|&]/\\&/g')

if [ "$mode" = print ]; then
  sed "s|{{SCRIPT}}|$escaped|g" "$TEMPLATE"
  exit 0
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/install-rule.XXXXXX") || die 1 "cannot create a temporary folder"
trap 'rm -rf -- "$work"' EXIT
rule=$work/rule.md
sed "s|{{SCRIPT}}|$escaped|g" "$TEMPLATE" >"$rule" || die 1 "cannot read the rule template"
block=$work/block.md
{ printf '%s\n' "$START"; cat "$rule"; printf '%s\n' "$END"; } >"$block"

claude_dir=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
codex_dir=${CODEX_HOME:-$HOME/.codex}
gemini_dir=$HOME/.gemini

if [ -z "$targets" ]; then
  [ -d "$claude_dir" ] && targets="$targets claude"
  [ -d "$codex_dir" ] && targets="$targets codex"
  [ -d "$gemini_dir" ] && targets="$targets gemini"
  if [ -z "$targets" ]; then printf '%s\n' "No agent config folder found ($claude_dir, $codex_dir, $gemini_dir)."; fi
fi

# Writes the new content of a block file into $2: the block replaced, or appended after one empty line.
with_block() { # file, output
  if [ ! -f "$1" ] || [ ! -s "$1" ]; then
    cat "$block" >"$2"
    return 0
  fi
  n_start=$(grep -cxF -e "$START" "$1")
  n_end=$(grep -cxF -e "$END" "$1")
  if [ "$n_start" -eq 0 ] && [ "$n_end" -eq 0 ]; then
    cat "$1" >"$2"
    # Add the missing newline at the end of the file, then one empty line.
    if [ "$(tail -c 1 "$1" | wc -l)" -eq 0 ]; then printf '\n' >>"$2"; fi
    printf '\n' >>"$2"
    cat "$block" >>"$2"
    return 0
  fi
  if [ "$n_start" -ne 1 ] || [ "$n_end" -ne 1 ] ||
    [ "$(grep -nxF -e "$START" "$1" | cut -d: -f1)" -gt "$(grep -nxF -e "$END" "$1" | cut -d: -f1)" ]; then
    die 1 "$1 has broken centralize-ai-output markers. Fix them manually, then run this script again."
  fi
  awk -v s="$START" -v e="$END" '
    NR == FNR { b = b $0 "\n"; next }
    $0 == s { printf "%s", b; skip = 1; next }
    skip && $0 == e { skip = 0; next }
    !skip { print }
  ' "$block" "$1" >"$2"
}

# Writes $2 into the file $1, with a backup of an existing file.
write_file() { # file, new content
  if [ ! -e "$1" ] && [ ! -L "$1" ]; then
    mkdir -p -- "$(dirname -- "$1")" || die 1 "cannot create the folder of $1"
    cat "$2" >"$1" || die 1 "cannot write $1"
    printf 'created %s\n' "$1"
    return 0
  fi
  backup=$1.bak.$(date +%Y%m%d-%H%M%S)
  [ ! -e "$backup" ] || backup=$backup.$$
  cp -p -- "$1" "$backup" || die 1 "cannot back up $1"
  if [ -L "$1" ]; then
    cat "$2" >"$1" || die 1 "cannot write $1"
  else
    tmp=$(mktemp "$(dirname -- "$1")/.install-rule.XXXXXX") || die 1 "cannot write next to $1"
    # cp -p first, so the new file keeps the mode of the old one.
    if ! { cp -p -- "$1" "$tmp" && cat "$2" >"$tmp" && mv -- "$tmp" "$1"; }; then
      rm -f -- "$tmp"
      die 1 "cannot write $1"
    fi
  fi
  printf 'updated %s (backup: %s)\n' "$1" "$backup"
}

for t in $targets; do
  case $t in
    claude) dir=$claude_dir; file=$claude_dir/rules/Centralize-AI-Output.md ;;
    codex) dir=$codex_dir; file=$codex_dir/AGENTS.md ;;
    gemini) dir=$gemini_dir; file=$gemini_dir/GEMINI.md ;;
  esac
  if [ ! -d "$dir" ]; then
    printf 'skip %s (no folder %s)\n' "$t" "$dir"
    continue
  fi
  new=$work/$t.new
  if [ "$t" = claude ]; then cp -- "$rule" "$new"; else with_block "$file" "$new"; fi
  if [ ! -e "$file" ] && [ ! -L "$file" ]; then
    action=create
  elif cmp -s -- "$new" "$file"; then
    action=unchanged
  else
    action=update
  fi
  if [ "$mode" = dry ] || [ "$action" = unchanged ]; then
    printf '%s %s\n' "$action" "$file"
  else
    write_file "$file" "$new"
  fi
done

if [ "$mode" = dry ]; then
  printf '%s\n' 'dry run: nothing was changed. Run again with --apply to write.'
fi
printf '%s\n' "Cursor: paste the rule text into Cursor Settings > Rules > User Rules. Print it with: sh $HERE/$me --print"
