#!/bin/sh
# Installs the Centralize AI Output rule into the global instruction files of AI agents, so they write their outputs
# into the AI agent output folder unless the user names another location.
#
# Usage:
#   sh install-rule.sh [--target claude|codex|gemini]...          dry run. Print what would change
#   sh install-rule.sh --apply [--target claude|codex|gemini]...  write the rule
#   sh install-rule.sh --check [--target claude|codex|gemini]...  print only the installed rules that are outdated
#   sh install-rule.sh --print                                    print the rule text
#
# Targets (default: each target whose config folder exists):
#   claude  ${CLAUDE_CONFIG_DIR:-~/.claude}/rules/Centralize-AI-Output.md, the whole file
#   codex   ${CODEX_HOME:-~/.codex}/AGENTS.md, a block between the centralize-ai-output start and end markers
#   gemini  ~/.gemini/GEMINI.md, the same block
# Cursor has no user rule file. Paste the text from --print into Cursor Settings > Rules > User Rules.
#
# The rule text is ../assets/Centralize-AI-Output.md, with {{SCRIPT}} replaced by the absolute path of ai-output-dir.sh.
# For each target, it is the copy in <config folder>/skills/centralize-ai-output/scripts/ when that file exists, else
# the copy in this folder. --print uses the copy in this folder.
#
# Actions of a dry run and --apply:
#   create     the file does not exist
#   add        the file exists and has no block (codex, gemini)
#   outdated   the installed rule is different from the rule that this script writes. A dry run shows a diff
#   unchanged  the installed rule is up to date
# --check prints "outdated <file>" or "broken <file>" (broken markers) for each installed rule that needs an update,
# and nothing else. A target without an installed rule is not listed. ai-output-dir.sh uses it.
#
# Before it changes an existing file, the script copies it to <file>.bak.<YYYYmmdd-HHMMSS>. Content outside the block
# is kept. A symbolic link stays a symbolic link, and the file that it points to is changed.
#
# Exit codes: 0 success, 1 a write failed or the markers in a file are broken, 2 bad usage,
#   3 (--check only) at least one installed rule is outdated or has broken markers.
#
# Maintainers: see docs/ai-output-folder-maintenance.md in the ai-dumping-ground repository.

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

usage="usage: sh $me [--apply | --check] [--target claude|codex|gemini]... | sh $me --print"
mode=dry
targets=
while [ $# -gt 0 ]; do
  case $1 in
    --apply)
      [ "$mode" = dry ] || die 2 "$usage"
      mode=apply ;;
    --check)
      [ "$mode" = dry ] || die 2 "$usage"
      mode=check ;;
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

# Writes the rule text with the script path into the output file, or to stdout without an output file.
render() { # script path, [output file]
  r_e=$(printf '%s' "$1" | sed 's/[\\|&]/\\&/g')
  if [ $# -ge 2 ]; then
    sed "s|{{SCRIPT}}|$r_e|g" "$TEMPLATE" >"$2"
  else
    sed "s|{{SCRIPT}}|$r_e|g" "$TEMPLATE"
  fi
}

if [ "$mode" = print ]; then
  render "$HERE/ai-output-dir.sh"
  exit 0
fi

# Prints the path of ai-output-dir.sh that the rule of an agent runs: its own copy when it exists, else this copy.
script_for() { # agent config folder
  s_f=$1/skills/centralize-ai-output/scripts/ai-output-dir.sh
  if [ -f "$s_f" ]; then printf '%s\n' "$s_f"; else printf '%s\n' "$HERE/ai-output-dir.sh"; fi
}

work=$(mktemp -d "${TMPDIR:-/tmp}/install-rule.XXXXXX") || die 1 "cannot create a temporary folder"
trap 'rm -rf -- "$work"' EXIT

claude_dir=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
codex_dir=${CODEX_HOME:-$HOME/.codex}
gemini_dir=$HOME/.gemini

if [ -z "$targets" ]; then
  [ -d "$claude_dir" ] && targets="$targets claude"
  [ -d "$codex_dir" ] && targets="$targets codex"
  [ -d "$gemini_dir" ] && targets="$targets gemini"
  if [ -z "$targets" ] && [ "$mode" != check ]; then
    printf '%s\n' "No agent config folder found ($claude_dir, $codex_dir, $gemini_dir)."
  fi
fi

# Prints the state of the markers in a file: none, ok or broken.
markers() { # file
  if [ ! -f "$1" ]; then
    printf '%s\n' none
    return 0
  fi
  m_s=$(grep -cxF -e "$START" "$1")
  m_e=$(grep -cxF -e "$END" "$1")
  if [ "$m_s" -eq 0 ] && [ "$m_e" -eq 0 ]; then
    printf '%s\n' none
  elif [ "$m_s" -ne 1 ] || [ "$m_e" -ne 1 ] ||
    [ "$(grep -nxF -e "$START" "$1" | cut -d: -f1)" -gt "$(grep -nxF -e "$END" "$1" | cut -d: -f1)" ]; then
    printf '%s\n' broken
  else
    printf '%s\n' ok
  fi
}

# Writes the new content of a block file into $3: the block replaced, or appended after one empty line.
with_block() { # block, file, output
  if [ ! -f "$2" ] || [ ! -s "$2" ]; then
    cat "$1" >"$3"
    return 0
  fi
  case $(markers "$2") in
    none)
      cat "$2" >"$3"
      # Add the missing newline at the end of the file, then one empty line.
      if [ "$(tail -c 1 "$2" | wc -l)" -eq 0 ]; then printf '\n' >>"$3"; fi
      printf '\n' >>"$3"
      cat "$1" >>"$3"
      return 0 ;;
    broken)
      die 1 "$2 has broken centralize-ai-output markers. Fix them manually, then run this script again." ;;
  esac
  awk -v s="$START" -v e="$END" '
    NR == FNR { b = b $0 "\n"; next }
    $0 == s { printf "%s", b; skip = 1; next }
    skip && $0 == e { skip = 0; next }
    !skip { print }
  ' "$1" "$2" >"$3"
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

found=false
for t in $targets; do
  case $t in
    claude) dir=$claude_dir; file=$claude_dir/rules/Centralize-AI-Output.md ;;
    codex) dir=$codex_dir; file=$codex_dir/AGENTS.md ;;
    gemini) dir=$gemini_dir; file=$gemini_dir/GEMINI.md ;;
  esac
  if [ ! -d "$dir" ]; then
    [ "$mode" = check ] || printf 'skip %s (no folder %s)\n' "$t" "$dir"
    continue
  fi
  script=$(script_for "$dir")
  rule=$work/$t.rule
  render "$script" "$rule" || die 1 "cannot read the rule template"
  new=$work/$t.new
  if [ "$t" = claude ]; then
    state=none
    { [ -e "$file" ] || [ -L "$file" ]; } && state=ok
    cp -- "$rule" "$new"
  else
    state=$(markers "$file")
    block=$work/$t.block
    { printf '%s\n' "$START"; cat "$rule"; printf '%s\n' "$END"; } >"$block"
    if [ "$state" != broken ]; then with_block "$block" "$file" "$new"; fi
  fi

  if [ "$mode" = check ]; then
    if [ "$state" = broken ]; then
      printf 'broken %s\n' "$file"
      found=true
    elif [ "$state" = ok ] && ! cmp -s -- "$new" "$file"; then
      printf 'outdated %s\n' "$file"
      found=true
    fi
    continue
  fi

  # Dry run and --apply: broken markers stop here, as before.
  if [ "$state" = broken ]; then with_block "$block" "$file" "$new"; fi
  if [ ! -e "$file" ] && [ ! -L "$file" ]; then
    action=create
  elif [ "$state" = none ]; then
    action=add
  elif cmp -s -- "$new" "$file"; then
    action=unchanged
  else
    action=outdated
  fi
  if [ "$mode" = dry ] || [ "$action" = unchanged ]; then
    printf '%s %s\n' "$action" "$file"
    if [ "$mode" = dry ]; then
      printf '  script: %s\n' "$script"
      if [ "$action" = outdated ]; then
        diff -u -- "$file" "$new" | sed -e '1s/^--- .*/--- installed/' -e '2s/^+++ .*/+++ new/'
      fi
    fi
  else
    write_file "$file" "$new"
  fi
done

if [ "$mode" = check ]; then
  if $found; then exit 3; fi
  exit 0
fi
if [ "$mode" = dry ]; then
  printf '%s\n' 'dry run: nothing was changed. Run again with --apply to write.'
fi
printf '%s\n' "Cursor: paste the rule text into Cursor Settings > Rules > User Rules. Print it with: sh $HERE/$me --print"
