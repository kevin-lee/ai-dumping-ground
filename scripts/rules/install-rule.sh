#!/bin/sh
# Installs a rule from the rules/ folder of the ai-dumping-ground repository (default: Clear-Writing) for AI agents.
#
# Usage:
#   sh install-rule.sh --agent <agent>... [--rule <name>] [--project <dir>]           dry run. Print what would change
#   sh install-rule.sh --apply --agent <agent>... [--rule <name>] [--project <dir>]   write the rule
#   sh install-rule.sh --print [--rule <name>]                                        print the rule text
#
# Agents:
#   claude       ${CLAUDE_CONFIG_DIR:-~/.claude}/rules/<name>.md, the whole file, with the rule between markers
#   codex        ${CODEX_HOME:-~/.codex}/AGENTS.md, a marked block. When AGENTS.override.md exists in that folder,
#                the block goes there, because Codex then reads it instead of AGENTS.md. Alias: chatgpt
#   antigravity  ~/.gemini/GEMINI.md, a marked block. Gemini CLI reads this file too. Alias: gemini
#   windsurf     ~/.devin/rules/<name>.md (Devin Desktop, the new name of Windsurf), the whole file with
#                "trigger: always_on" front matter, and ~/.codeium/windsurf/memories/global_rules.md (old Windsurf),
#                a marked block. Each one only when its folder exists. The old Windsurf reads only the first 6,000
#                characters of global_rules.md, so the script does not change that file when the result is longer
#                ("too-long"). Alias: devin
#   cursor       Cursor has no global rule file. The script tells you to paste the text from --print into
#                Cursor Settings > Rules > User Rules
#   agents       AGENTS.md in the project folder, a marked block. Codex, Cursor, Windsurf, Antigravity and other agents
#                read it. There is no standard global AGENTS.md
#   all          claude, codex, antigravity, windsurf and cursor. Not agents, because it changes a project
#
# --rule <name>    the rule file rules/<name>.md. Default: Clear-Writing
# --force          replace a whole rule file (claude, devin) that has the same name but that this script did not write
# --project <dir>  the project folder for agents. Default: the root of the Git repository of the current folder, or
#                  the current folder outside Git
#
# In a clone, the script reads the rule from ../../rules/<name>.md. Outside a clone, for example with
# "curl ... | sh -s -- <options>", it downloads the rule from $RULE_BASE_URL/<name>.md with curl. Default RULE_BASE_URL:
# https://raw.githubusercontent.com/kevin-lee/ai-dumping-ground/main/rules
#
# A global agent whose config folder does not exist is skipped.
#
# Actions:
#   create     the file does not exist
#   add        the file exists and has no block
#   outdated   the installed rule is different from the rule that this script writes. A dry run shows a diff
#   unchanged  the installed rule is up to date
#   too-long   (old Windsurf only) the file would be longer than 6,000 characters. Nothing is changed
#   conflict   (claude, devin) a file with the same name exists, but it has no markers of the rule and it is not a
#              copy of the rule. Nothing is changed, and the exit code is 1. --force replaces it
#   force      the same as conflict, but --force is given. The file is replaced after a backup
#
# Before it changes an existing file, the script copies it to <file>.bak.<YYYYmmdd-HHMMSS>. Content outside the block
# is kept. A symbolic link stays a symbolic link, and the file that it points to is changed.
#
# Exit codes: 0 success, 1 a read or write failed, the markers in a file are broken, or a conflict, 2 bad usage.

set -u

me=install-rule.sh

die() { # exit code, message
  printf '%s: %s\n' "$me" "$2" >&2
  exit "$1"
}

usage="usage: sh $me [--apply] [--force] --agent claude|codex|chatgpt|antigravity|gemini|windsurf|devin|cursor|agents|all... [--rule <name>] [--project <dir>] | sh $me --print [--rule <name>]"
mode=dry
force=false
agents=
rule_name=Clear-Writing
project=
while [ $# -gt 0 ]; do
  case $1 in
    --apply)
      [ "$mode" = dry ] || die 2 "$usage"
      mode=apply ;;
    --print)
      [ "$mode" = dry ] || die 2 "$usage"
      mode=print ;;
    --force)
      force=true ;;
    --agent)
      [ $# -ge 2 ] || die 2 "$usage"
      case $2 in
        claude | codex | antigravity | windsurf | cursor | agents) a=$2 ;;
        chatgpt) a=codex ;;
        gemini) a=antigravity ;;
        devin) a=windsurf ;;
        all) a='claude codex antigravity windsurf cursor' ;;
        *) die 2 "unknown agent: $2. $usage" ;;
      esac
      for x in $a; do
        case " $agents " in
          *" $x "*) ;;
          *) agents="$agents $x" ;;
        esac
      done
      shift ;;
    --rule)
      [ $# -ge 2 ] || die 2 "$usage"
      rule_name=$2
      shift ;;
    --project)
      [ $# -ge 2 ] || die 2 "$usage"
      project=$2
      shift ;;
    *)
      die 2 "$usage" ;;
  esac
  shift
done

case $rule_name in
  '' | .* | *[!A-Za-z0-9._-]*) die 2 "bad rule name: $rule_name. Use the file name in rules/ without .md" ;;
esac
if [ "$mode" = print ]; then
  [ -z "$agents" ] && [ -z "$project" ] || die 2 "$usage"
else
  [ -n "$agents" ] || die 2 "choose at least one agent. $usage"
fi
case ${HOME:-} in
  /*) ;;
  *) die 2 "HOME is not set to an absolute path" ;;
esac

work=$(mktemp -d "${TMPDIR:-/tmp}/install-rule.XXXXXX") || die 1 "cannot create a temporary folder"
trap 'rm -rf -- "$work"' EXIT

# The rule text: the file in the clone, or a download.
HERE=$(cd -- "$(dirname -- "$0")" 2>/dev/null && pwd) || HERE=
local_rule=$HERE/../../rules/$rule_name.md
rule=$work/rule.md
if [ -n "$HERE" ] && [ -f "$HERE/$me" ] && [ -d "$HERE/../../rules" ]; then
  local_rule=$(cd -- "$HERE/../../rules" && pwd)/$rule_name.md
  [ -f "$local_rule" ] || die 1 "no rule $rule_name.md in $(dirname -- "$local_rule")"
  cp -- "$local_rule" "$rule" || die 1 "cannot read $local_rule"
  source_text=$local_rule
else
  base=${RULE_BASE_URL:-https://raw.githubusercontent.com/kevin-lee/ai-dumping-ground/main/rules}
  command -v curl >/dev/null 2>&1 || die 1 "the rule is not next to this script, and curl is not installed to download it"
  curl -fsSL -- "$base/$rule_name.md" >"$rule" || die 1 "cannot download $base/$rule_name.md"
  source_text=$base/$rule_name.md
fi
[ -s "$rule" ] || die 1 "the rule is empty: $source_text"
# Add the missing newline at the end of the rule.
if [ "$(tail -c 1 "$rule" | wc -l)" -eq 0 ]; then printf '\n' >>"$rule"; fi

if [ "$mode" = print ]; then
  cat "$rule"
  exit 0
fi

START="<!-- rule:$rule_name:start -->"
END="<!-- rule:$rule_name:end -->"

block=$work/rule.block
{ printf '%s\n' "$START"; cat "$rule"; printf '%s\n' "$END"; } >"$block"

# The rule with front matter for Devin Desktop. The description is the first "# " heading.
devin_rule=$work/rule.devin
title=$(sed -n 's/^# *//p' "$rule" | head -n 1)
[ -n "$title" ] || title=$rule_name
devin_front=$work/rule.front
{
  printf '%s\n' '---' 'trigger: always_on'
  printf 'description: %s\n' "$(printf '%s' "$title" | sed 's/["\\]/\\&/g; s/.*/"&"/')"
  printf '%s\n' '---' ''
} >"$devin_front"
cat "$devin_front" "$block" >"$devin_rule"
# The same rule without markers, to recognize a copy that was made by hand.
devin_plain=$work/rule.devin-plain
cat "$devin_front" "$rule" >"$devin_plain"

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

# Writes the new content of a block file into $2: the block replaced, or appended after one empty line.
with_block() { # file, output
  if [ ! -f "$1" ] || [ ! -s "$1" ]; then
    cat "$block" >"$2"
    return 0
  fi
  if [ "$(markers "$1")" = none ]; then
    cat "$1" >"$2"
    if [ "$(tail -c 1 "$1" | wc -l)" -eq 0 ]; then printf '\n' >>"$2"; fi
    printf '\n' >>"$2"
    cat "$block" >>"$2"
    return 0
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

failed=false
WINDSURF_LIMIT=6000

# Installs the rule into one file. kind is "file" (the whole file is the content) or "block".
# For kind file, the script changes an existing file only when it is its own: the file has the markers of the rule,
# or it is the rule without markers (a copy made by hand). Another file with the same name is a conflict, and only
# --force replaces it.
install_to() { # label, config folder, file, kind, [content for kind file, the same content without markers]
  i_label=$1
  i_dir=$2
  i_file=$3
  if [ ! -d "$i_dir" ]; then
    printf 'skip %s (no folder %s)\n' "$i_label" "$i_dir"
    return 0
  fi
  i_new=$work/new
  if [ "$4" = file ]; then
    cp -- "$5" "$i_new"
    i_state=none
    if [ -e "$i_file" ] || [ -L "$i_file" ]; then
      i_state=ok
      if ! cmp -s -- "$i_new" "$i_file" && [ "$(markers "$i_file")" != ok ] && ! cmp -s -- "$6" "$i_file"; then
        if ! $force; then
          printf 'conflict %s (%s): a different file with this name exists. Nothing was changed.\n' "$i_file" "$i_label"
          printf '  Rename or remove it, or run again with --force to replace it (the script backs it up first).\n'
          failed=true
          return 0
        fi
        printf 'force %s (%s): replaces a different file with this name.\n' "$i_file" "$i_label"
      fi
    fi
  else
    i_state=$(markers "$i_file")
    if [ "$i_state" = broken ]; then
      printf '%s: %s has broken %s markers. Fix them manually, then run this script again.\n' "$me" "$i_file" "$rule_name" >&2
      failed=true
      return 0
    fi
    with_block "$i_file" "$i_new"
  fi

  # The old Windsurf ignores the text after the first 6,000 characters of global_rules.md. A rule that is cut off
  # is worse than no rule, so the script does not write it.
  if [ "$i_label" = windsurf ]; then
    i_chars=$(wc -m <"$i_new" | tr -d ' ')
    if [ "$i_chars" -gt "$WINDSURF_LIMIT" ]; then
      printf 'too-long %s (windsurf): it would have %s characters, and Windsurf reads only the first %s.\n' "$i_file" "$i_chars" "$WINDSURF_LIMIT"
      printf '  Nothing was changed. Use Devin Desktop (~/.devin/rules/) or a workspace rule in .windsurf/rules/.\n'
      return 0
    fi
  fi

  if [ ! -e "$i_file" ] && [ ! -L "$i_file" ]; then
    i_action=create
  elif [ "$i_state" = none ]; then
    i_action=add
  elif cmp -s -- "$i_new" "$i_file"; then
    i_action=unchanged
  else
    i_action=outdated
  fi
  if [ "$mode" = dry ] || [ "$i_action" = unchanged ]; then
    printf '%s %s (%s)\n' "$i_action" "$i_file" "$i_label"
    if [ "$mode" = dry ] && [ "$i_action" = outdated ]; then
      diff -u -- "$i_file" "$i_new" | sed -e '1s/^--- .*/--- installed/' -e '2s/^+++ .*/+++ new/'
    fi
  else
    write_file "$i_file" "$i_new"
  fi
}

claude_dir=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
codex_dir=${CODEX_HOME:-$HOME/.codex}

printf 'rule: %s\n' "$source_text"
for a in $agents; do
  case $a in
    claude) install_to claude "$claude_dir" "$claude_dir/rules/$rule_name.md" file "$block" "$rule" ;;
    codex)
      # Codex reads AGENTS.override.md instead of AGENTS.md when it exists.
      codex_file=$codex_dir/AGENTS.md
      if [ -e "$codex_dir/AGENTS.override.md" ] || [ -L "$codex_dir/AGENTS.override.md" ]; then
        codex_file=$codex_dir/AGENTS.override.md
      fi
      install_to codex "$codex_dir" "$codex_file" block ;;
    antigravity) install_to antigravity "$HOME/.gemini" "$HOME/.gemini/GEMINI.md" block ;;
    windsurf)
      if [ ! -d "$HOME/.devin" ] && [ ! -d "$HOME/.codeium/windsurf" ]; then
        printf 'skip windsurf (no folder %s or %s)\n' "$HOME/.devin" "$HOME/.codeium/windsurf"
      else
        [ -d "$HOME/.devin" ] && install_to devin "$HOME/.devin" "$HOME/.devin/rules/$rule_name.md" file "$devin_rule" "$devin_plain"
        [ -d "$HOME/.codeium/windsurf" ] && install_to windsurf "$HOME/.codeium/windsurf" "$HOME/.codeium/windsurf/memories/global_rules.md" block
      fi ;;
    cursor)
      printf 'cursor: Cursor has no global rule file. Paste the rule text into Cursor Settings > Rules > User Rules.\n'
      if [ -n "$HERE" ] && [ -f "$HERE/$me" ]; then
        printf '  Print it with: sh %s/%s --print --rule %s\n' "$HERE" "$me" "$rule_name"
      else
        printf '  Print it with: curl -fsSL %s\n' "$source_text"
      fi ;;
    agents)
      if [ -z "$project" ]; then
        project=$(git rev-parse --show-toplevel 2>/dev/null) || project=$PWD
      fi
      [ -d "$project" ] || die 2 "the project folder does not exist: $project"
      project=$(cd -- "$project" && pwd) || die 1 "cannot open $project"
      install_to agents "$project" "$project/AGENTS.md" block ;;
  esac
done

if [ "$mode" = dry ]; then
  printf '%s\n' 'dry run: nothing was changed. Run again with --apply to write.'
fi
if $failed; then exit 1; fi
exit 0
