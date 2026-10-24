#!/bin/sh
# Prints the choices for where gen-motion-graphics stores its video folders, so the agent only asks the question:
# video in the current folder, .ai/video in the project root (the Git repository root, else the current folder), and
# video in the central folder that ai-output-dir.sh in the same folder prints (it honors AI_AGENT_OUTPUT_DIR). It
# changes nothing.
#
# Usage:
#   sh video-output-choices.sh
#
# Output, one key=value per line, in this order:
#   current=<path>            video in the current folder (also in a Git repository)
#   current_exists=yes|no     yes for a folder, or a symbolic link to a folder
#   project=<path>            .ai/video in the project root, empty when .ai is a symbolic link to the central folder
#   project_exists=yes|no
#   central=<path>            video in the central folder, empty when ai-output-dir.sh fails
#   central_exists=yes|no
#   central_error=<message>   only when ai-output-dir.sh fails
#   recommended=current|project|central|none
#   order=<words>             the option order, from current, project, central and other
#
# Exit codes: 0 success (also when ai-output-dir.sh fails), 2 bad usage.
#
# The recommended option is the first of current, project and central whose folder exists, else current, or none when
# the central folder cannot be found. It is shown first, and the others follow in that order. This rule is different
# from ai-output-choices.sh (see decision 5).
# Maintainers: see docs/ai-output-folder-maintenance.md in the ai-dumping-ground repository.

set -u

me=video-output-choices.sh

strip_slashes() { # path. Prints it without trailing slashes. "/" stays "/".
  s_p=$1
  while [ "${#s_p}" -gt 1 ] && [ "${s_p%/}" != "$s_p" ]; do s_p=${s_p%/}; done
  printf '%s\n' "$s_p"
}

phys_of() { # folder. Prints its path with every symbolic link resolved.
  (cd -P -- "$1" 2>/dev/null && pwd -P)
}

if [ $# -gt 0 ]; then
  printf '%s: usage: sh %s\n' "$me" "$me" >&2
  exit 2
fi

HERE=$(cd -- "$(dirname -- "$0")" && pwd) || exit 1

# The current folder, with its symbolic links when $PWD is correct.
phys=$(pwd -P) || exit 1
here=$phys
case ${PWD:-} in
  /*)
    if [ "$(phys_of "$PWD")" = "$phys" ]; then here=$(strip_slashes "$PWD"); fi ;;
esac

# The project root, with its symbolic links when $PWD is correct.
top=$here
if command -v git >/dev/null 2>&1 && [ "$(git rev-parse --is-inside-work-tree 2>/dev/null)" = true ]; then
  top_phys=$(phys_of "$(git rev-parse --show-toplevel)")
  prefix=$(git rev-parse --show-prefix)
  prefix=${prefix%/}
  if [ -n "$prefix" ]; then
    case $here in
      */"$prefix") top=${here%/"$prefix"} ;;
      *) top=$top_phys ;;
    esac
  fi
  [ "$(phys_of "$top")" = "$top_phys" ] || top=$top_phys
fi

[ "$here" != / ] || here=
[ "$top" != / ] || top=
current=$here/video
project=$top/.ai/video

central_error=
if central_root=$(sh "$HERE/ai-output-dir.sh" --print-only 2>&1); then
  central=$central_root/video
else
  central_error=$(printf '%s\n' "$central_root" | sed 's/^ai-output-dir.sh: //' | head -n 1)
  [ -n "$central_error" ] || central_error="ai-output-dir.sh failed"
  central_root=
  central=
fi

# .ai linked to the central folder makes .ai/video the same folder as central.
if [ -n "$central_root" ] && [ -L "$top/.ai" ] && [ -d "$central_root" ] &&
  [ "$(phys_of "$top/.ai")" = "$(phys_of "$central_root")" ]; then
  project=
fi

current_exists=no
if [ -d "$current" ]; then current_exists=yes; fi
project_exists=no
if [ -n "$project" ] && [ -d "$project" ]; then project_exists=yes; fi
central_exists=no
if [ -n "$central" ] && [ -d "$central" ]; then central_exists=yes; fi

if [ "$current_exists" = yes ]; then
  recommended=current
elif [ "$project_exists" = yes ]; then
  recommended=project
elif [ "$central_exists" = yes ]; then
  recommended=central
elif [ -z "$central" ]; then
  recommended=none
else
  recommended=current
fi

order=
if [ "$recommended" != none ]; then order=$recommended; fi
for option in current project central; do
  [ "$option" != "$recommended" ] || continue
  case $option in
    project) [ -n "$project" ] || continue ;;
    central) [ -n "$central" ] || continue ;;
  esac
  order="${order:+$order }$option"
done
order="$order other"

printf 'current=%s\n' "$current"
printf 'current_exists=%s\n' "$current_exists"
printf 'project=%s\n' "$project"
printf 'project_exists=%s\n' "$project_exists"
printf 'central=%s\n' "$central"
printf 'central_exists=%s\n' "$central_exists"
if [ -n "$central_error" ]; then printf 'central_error=%s\n' "$central_error"; fi
printf 'recommended=%s\n' "$recommended"
printf 'order=%s\n' "$order"
