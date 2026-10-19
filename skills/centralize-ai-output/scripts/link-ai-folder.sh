#!/bin/sh
# Replaces a project's empty .ai folder with a symbolic link to the project's AI agent output folder, which
# ai-output-dir.sh in the same folder prints. Then any tool that writes into .ai writes into the output folder.
#
# Usage:
#   sh link-ai-folder.sh          dry run. Print what would be removed and linked. Change nothing
#   sh link-ai-folder.sh --apply  remove the empty folders and .DS_Store files in .ai, then create the link
#
# .ai is <repository root>/.ai in a Git repository, else ./.ai. The script links only when .ai is absent, or when it
# has nothing but folders and .DS_Store files. Move the other files first with migrate-ai-output.sh --all.
# It removes only .DS_Store files (one by one) and empty folders (rmdir), never anything else.
# A .ai/ pattern in a gitignore file does not match a symbolic link. Use .ai (no slash).
# File names that contain a newline are not supported.
#
# Exit codes: 0 success, 1 a step failed, 2 bad usage, 4 the state of .ai does not allow the link.
#             A failure of ai-output-dir.sh exits with its code.
#
# Maintainers: see docs/ai-output-folder-maintenance.md in the ai-dumping-ground repository.

set -u

me=link-ai-folder.sh

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

usage="usage: sh $me [--apply]"
mode=dry
case $# in
  0) ;;
  1)
    case $1 in
      --apply) mode=apply ;;
      *) die 2 "$usage" ;;
    esac ;;
  *) die 2 "$usage" ;;
esac

# The project root, with its symbolic links when $PWD is correct.
phys=$(pwd -P) || die 1 "cannot read the current folder"
logical=$phys
case ${PWD:-} in
  /*)
    if [ "$(phys_of "$PWD")" = "$phys" ]; then logical=$(strip_slashes "$PWD"); fi ;;
esac
top=$logical
in_git=false
if command -v git >/dev/null 2>&1 && [ "$(git rev-parse --is-inside-work-tree 2>/dev/null)" = true ]; then
  in_git=true
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
top_dir=$top
[ "$top" != / ] || top=
ai=$top/.ai

dest=$(sh "$HERE/ai-output-dir.sh" --print-only) || exit $?

gitignore_check() {
  $in_git || return 0
  if ! (cd -- "$top_dir" && git check-ignore -q .ai 2>/dev/null); then
    printf '%s\n' 'warning: .ai is not ignored by Git. A .ai/ pattern does not match a symbolic link. Use .ai (no slash) in a gitignore file.'
  fi
}

if [ -L "$ai" ]; then
  dest_phys=$(phys_of "$dest") || dest_phys=
  if [ -n "$dest_phys" ] && [ "$(phys_of "$ai")" = "$dest_phys" ]; then
    printf 'already linked: %s -> %s\n' "$ai" "$dest"
    gitignore_check
    exit 0
  fi
  die 4 "$ai is a symbolic link to $(readlink "$ai" 2>/dev/null), not to $dest. Not linked."
fi

if $in_git && [ -n "$(cd -- "$top_dir" && git ls-files -- .ai 2>/dev/null)" ]; then
  die 4 ".ai is tracked by Git. Not linked."
fi

if [ -e "$ai" ] && [ ! -d "$ai" ]; then
  die 4 "$ai is not a folder. Not linked."
fi

nl='
'
ds=
dirs=
if [ -d "$ai" ]; then
  others=$(find "$ai" ! -type d ! \( -type f -name .DS_Store \) 2>/dev/null | LC_ALL=C sort)
  if [ -n "$others" ]; then
    {
      printf '%s has files to move first. Run migrate-ai-output.sh --all, then run this script again.\n' "$ai"
      printf '%s\n' "$others" | head -n 20
    } >&2
    exit 4
  fi
  ds=$(find "$ai" -type f -name .DS_Store 2>/dev/null | LC_ALL=C sort)
  # -depth lists the contents of a folder before the folder, so each folder is empty when it is removed.
  dirs=$(find "$ai" -depth -type d 2>/dev/null)
fi

old_ifs=$IFS
set -f
if [ "$mode" = dry ]; then
  IFS=$nl
  for f in $ds; do printf 'remove %s\n' "$f"; done
  for d in $dirs; do printf 'rmdir %s\n' "$d"; done
  IFS=$old_ifs
  printf 'link %s -> %s\n' "$ai" "$dest"
  printf '%s\n' 'dry run: nothing was changed. Run again with --apply to link.'
  exit 0
fi

sh "$HERE/ai-output-dir.sh" >/dev/null || exit $?
IFS=$nl
for f in $ds; do
  rm -f -- "$f" || die 1 "cannot remove $f"
  printf 'removed %s\n' "$f"
done
for d in $dirs; do
  rmdir -- "$d" || die 1 "cannot remove the folder $d"
  printf 'removed %s\n' "$d"
done
IFS=$old_ifs
ln -s -- "$dest" "$ai" || die 1 "cannot create the link $ai -> $dest"
printf 'linked %s -> %s\n' "$ai" "$dest"
gitignore_check
exit 0
