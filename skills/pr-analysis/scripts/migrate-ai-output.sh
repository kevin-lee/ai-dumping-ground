#!/bin/sh
# Moves old AI agent outputs from a project's .ai/ folder into the project's AI agent output folder, which
# ai-output-dir.sh in the same folder prints.
#
# Usage:
#   sh migrate-ai-output.sh [--check | --apply] [--from <legacy folder>] <item>...
#
#   <item>        a subfolder of the legacy folder, for example plans, done, docs/pr or video
#   --from <dir>  the legacy folder. Default: <repository root>/.ai in a Git repository, else ./.ai
#   no option     dry run. Print what would move and change nothing
#   --check       print each item folder that has files to move. Change nothing
#   --apply       move the files
#
# The script never deletes a file or a folder, and never overwrites a file. A file whose destination exists stays in
# place: "same" when the two files are identical, "conflict" when they are different. .DS_Store files are ignored.
# Content outside the given items, for example .ai/examples, is never touched.
# File names that contain a newline are not supported.
#
# Exit codes: 0 success (with --check: there are files to move), 1 nothing to move (--check only) or a move failed,
#             2 bad usage, 3 --apply left conflicts in place. A failure of ai-output-dir.sh exits with its code.
#
# This file is identical in every skill that has it. Change all copies together.

set -u

me=migrate-ai-output.sh

die() { # exit code, message
  printf '%s: %s\n' "$me" "$2" >&2
  exit "$1"
}

strip_slashes() { # path. Prints it without trailing slashes. "/" stays "/".
  s_p=$1
  while [ "${#s_p}" -gt 1 ] && [ "${s_p%/}" != "$s_p" ]; do s_p=${s_p%/}; done
  printf '%s\n' "$s_p"
}

phys_of() { # folder. Prints its path with every symbolic link resolved.
  (cd -P -- "$1" 2>/dev/null && pwd -P)
}

HERE=$(cd -- "$(dirname -- "$0")" && pwd) || exit 1

usage="usage: sh $me [--check | --apply] [--from <legacy folder>] <item>..."
mode=dry
from=
from_given=false
items=
nl='
'
while [ $# -gt 0 ]; do
  case $1 in
    --check | --apply)
      [ "$mode" = dry ] || die 2 "--check and --apply cannot be used together. $usage"
      mode=${1#--} ;;
    --from)
      [ $# -ge 2 ] || die 2 "$usage"
      from=$2
      from_given=true
      shift ;;
    -*)
      die 2 "$usage" ;;
    *)
      case $1 in
        '' | /*) die 2 "an item must be a relative path: $1" ;;
        *"$nl"*) die 2 "an item must not contain a newline" ;;
      esac
      case /$1/ in
        */../* | */./*) die 2 "an item must not have a . or .. segment: $1" ;;
      esac
      items=$items$(strip_slashes "$1")$nl ;;
  esac
  shift
done
[ -n "$items" ] || die 2 "$usage"

if $from_given; then
  [ -d "$from" ] || die 2 "--from is not a folder: $from"
  from=$(strip_slashes "$from")
else
  phys=$(pwd -P) || die 1 "cannot read the current folder"
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
  from=$top/.ai
fi

dest=$(sh "$HERE/ai-output-dir.sh" --print-only) || exit $?
dest_phys=$(phys_of "$dest") || dest_phys=

old_ifs=$IFS
set -f
IFS=$nl
for item in $items; do
  src=$from/$item
  src_phys=$(phys_of "$src") || src_phys=
  for d in "$dest" "$dest_phys"; do
    [ -n "$d" ] || continue
    for s in "$src" "$src_phys"; do
      [ -n "$s" ] || continue
      case $d/ in
        "$s"/*) die 2 "the destination $dest is inside the legacy folder $src" ;;
      esac
    done
  done
done
IFS=$old_ifs

list_files() { # folder
  find "$1" \( -type f -o -type l \) ! -name .DS_Store 2>/dev/null | LC_ALL=C sort
}

if [ "$mode" = check ]; then
  any=false
  IFS=$nl
  for item in $items; do
    src=$from/$item
    if [ -d "$src" ] && [ ! -L "$src" ] && [ -n "$(list_files "$src")" ]; then
      printf '%s\n' "$src"
      any=true
    fi
  done
  IFS=$old_ifs
  if $any; then exit 0; fi
  exit 1
fi

if [ "$mode" = apply ]; then
  sh "$HERE/ai-output-dir.sh" >/dev/null || exit $?
fi

moves=0
sames=0
conflicts=0
failures=0
IFS=$nl
for item in $items; do
  src=$from/$item
  [ -d "$src" ] || continue
  if [ -L "$src" ]; then
    printf 'skip %s (symbolic link)\n' "$src"
    continue
  fi
  files=$(list_files "$src")
  for f in $files; do
    rel=${f#"$src"/}
    dst=$dest/$item/$rel
    if [ -e "$dst" ] || [ -L "$dst" ]; then
      if [ -f "$f" ] && [ -f "$dst" ] && cmp -s "$f" "$dst"; then
        printf 'same %s (identical file exists: %s)\n' "$f" "$dst"
        sames=$((sames + 1))
      else
        printf 'conflict %s (different file exists: %s)\n' "$f" "$dst"
        conflicts=$((conflicts + 1))
      fi
    elif [ "$mode" = dry ]; then
      printf 'move %s -> %s\n' "$f" "$dst"
      moves=$((moves + 1))
    elif mkdir -p -- "${dst%/*}" && [ ! -e "$dst" ] && [ ! -L "$dst" ] && mv -- "$f" "$dst"; then
      printf 'moved %s -> %s\n' "$f" "$dst"
      moves=$((moves + 1))
    else
      printf 'failed %s -> %s\n' "$f" "$dst"
      failures=$((failures + 1))
    fi
  done
done
IFS=$old_ifs

if [ "$mode" = dry ]; then
  printf 'dry run: %d to move, %d identical, %d conflicts. Nothing was changed. Run again with --apply to move.\n' \
    "$moves" "$sames" "$conflicts"
  exit 0
fi

printf 'apply: %d moved, %d identical left in place, %d conflicts left in place.\n' "$moves" "$sames" "$conflicts"
if [ "$failures" -gt 0 ]; then printf '%d files failed to move.\n' "$failures"; fi
left=
IFS=$nl
for item in $items; do
  src=$from/$item
  if [ -e "$src" ] || [ -L "$src" ]; then left=$left$(find "$src" 2>/dev/null | LC_ALL=C sort)$nl; fi
done
IFS=$old_ifs
if [ -n "$left" ]; then
  printf 'Left in place:\n%s' "$left"
else
  printf 'Left in place: nothing\n'
fi
printf '%s\n' 'This script never deletes files or folders. Remove what is left manually if you do not need it.'
if [ "$failures" -gt 0 ]; then exit 1; fi
if [ "$conflicts" -gt 0 ]; then exit 3; fi
exit 0
