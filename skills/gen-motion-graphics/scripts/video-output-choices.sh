#!/bin/sh
# Prints the choices for where gen-motion-graphics stores its video folders, so the agent only asks the question:
# video in the current folder, and video in the central folder that ai-output-dir.sh in the same folder prints (it
# honors AI_AGENT_OUTPUT_DIR). It changes nothing.
#
# Usage:
#   sh video-output-choices.sh
#
# Output, one key=value per line, in this order:
#   current=<path>            video in the current folder (also in a Git repository)
#   current_exists=yes|no     yes for a folder, or a symbolic link to a folder
#   central=<path>            video in the central folder, empty when ai-output-dir.sh fails
#   central_exists=yes|no
#   central_error=<message>   only when ai-output-dir.sh fails
#   recommended=current|central|none
#   order=<words>             the option order, from current, central and other
#
# Exit codes: 0 success (also when ai-output-dir.sh fails), 2 bad usage.
#
# The recommendation rule is the same as in ai-output-choices.sh, with current for project. Change both scripts
# together. The tests compare them.
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
here=$(pwd -P) || exit 1
case ${PWD:-} in
  /*)
    if [ "$(phys_of "$PWD")" = "$here" ]; then here=$(strip_slashes "$PWD"); fi ;;
esac
[ "$here" != / ] || here=
current=$here/video

central_error=
if central=$(sh "$HERE/ai-output-dir.sh" --print-only 2>&1); then
  central=$central/video
else
  central_error=$(printf '%s\n' "$central" | sed 's/^ai-output-dir.sh: //' | head -n 1)
  [ -n "$central_error" ] || central_error="ai-output-dir.sh failed"
  central=
fi

current_exists=no
if [ -d "$current" ]; then current_exists=yes; fi
central_exists=no
if [ -n "$central" ] && [ -d "$central" ]; then central_exists=yes; fi

if [ -z "$central" ]; then
  order="current other"
  if [ "$current_exists" = yes ]; then recommended=current; else recommended=none; fi
elif [ "$central_exists" = yes ] && [ "$current_exists" = no ]; then
  order="central current other"
  recommended=central
else
  order="current central other"
  recommended=current
fi

printf 'current=%s\n' "$current"
printf 'current_exists=%s\n' "$current_exists"
printf 'central=%s\n' "$central"
printf 'central_exists=%s\n' "$central_exists"
if [ -n "$central_error" ]; then printf 'central_error=%s\n' "$central_error"; fi
printf 'recommended=%s\n' "$recommended"
printf 'order=%s\n' "$order"
