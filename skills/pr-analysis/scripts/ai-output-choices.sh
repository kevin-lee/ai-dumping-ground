#!/bin/sh
# Prints the choices for where to store AI agent outputs of the current project, so the agent only asks the question:
# the central folder that ai-output-dir.sh in the same folder prints (it honors AI_AGENT_OUTPUT_DIR), and .ai in the
# project root (the Git repository root, else the current folder). It changes nothing.
#
# Usage:
#   sh ai-output-choices.sh
#
# Output, one key=value per line, in this order:
#   central=<path>            the central folder, empty when ai-output-dir.sh fails
#   central_exists=yes|no
#   central_error=<message>   only when ai-output-dir.sh fails
#   project=<path>            .ai in the project root
#   project_exists=yes|no     yes for a folder, or a symbolic link to a folder
#   ask=yes|no                no when .ai is a symbolic link to the central folder
#   use=<path>                only with ask=no
#   recommended=central|project|none
#   order=<words>             the option order, from central, project and other
#   migrate=<command>         the dry run that moves everything in .ai to the central folder
#
# Exit codes: 0 success (also when ai-output-dir.sh fails), 2 bad usage.
#
# This file is identical in every skill that has it. Change all copies together.
# Maintainers: see docs/ai-output-folder-maintenance.md in the ai-dumping-ground repository.

set -u

me=ai-output-choices.sh

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

# The project root, with its symbolic links when $PWD is correct.
phys=$(pwd -P) || exit 1
logical=$phys
case ${PWD:-} in
  /*)
    if [ "$(phys_of "$PWD")" = "$phys" ]; then logical=$(strip_slashes "$PWD"); fi ;;
esac
top=$logical
if command -v git >/dev/null 2>&1 && [ "$(git rev-parse --is-inside-work-tree 2>/dev/null)" = true ]; then
  top_phys=$(phys_of "$(git rev-parse --show-toplevel)")
  prefix=$(git rev-parse --show-prefix)
  prefix=${prefix%/}
  if [ -n "$prefix" ]; then
    case $logical in
      */"$prefix") top=${logical%/"$prefix"} ;;
      *) top=$top_phys ;;
    esac
  fi
  [ "$(phys_of "$top")" = "$top_phys" ] || top=$top_phys
fi
[ "$top" != / ] || top=
project=$top/.ai

central_error=
if ! central=$(sh "$HERE/ai-output-dir.sh" --print-only 2>&1); then
  central_error=$(printf '%s\n' "$central" | sed 's/^ai-output-dir.sh: //' | head -n 1)
  [ -n "$central_error" ] || central_error="ai-output-dir.sh failed"
  central=
fi

central_exists=no
if [ -n "$central" ] && [ -d "$central" ]; then central_exists=yes; fi
project_exists=no
if [ -d "$project" ]; then project_exists=yes; fi

ask=yes
if [ -n "$central" ] && [ -L "$project" ] && [ "$central_exists" = yes ] &&
  [ "$(phys_of "$project")" = "$(phys_of "$central")" ]; then
  ask=no
fi

if [ -z "$central" ]; then
  order="project other"
  if [ "$project_exists" = yes ]; then recommended=project; else recommended=none; fi
elif [ "$central_exists" = yes ] && [ "$project_exists" = yes ]; then
  order="central project other"
  recommended=none
elif [ "$project_exists" = yes ]; then
  order="project central other"
  recommended=project
else
  order="central project other"
  recommended=central
fi

printf 'central=%s\n' "$central"
printf 'central_exists=%s\n' "$central_exists"
if [ -n "$central_error" ]; then printf 'central_error=%s\n' "$central_error"; fi
printf 'project=%s\n' "$project"
printf 'project_exists=%s\n' "$project_exists"
printf 'ask=%s\n' "$ask"
if [ "$ask" = no ]; then printf 'use=%s\n' "$central"; fi
printf 'recommended=%s\n' "$recommended"
printf 'order=%s\n' "$order"
printf 'migrate=sh %s/migrate-ai-output.sh --all\n' "$HERE"
