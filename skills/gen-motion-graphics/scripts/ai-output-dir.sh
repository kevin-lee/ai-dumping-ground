#!/bin/sh
# Prints the AI agent output folder of the current project. Without an option, it also creates the folder and records
# the project in the folder's .project-info file.
#
# Usage:
#   sh ai-output-dir.sh               resolve the folder, create it, update .project-info and print the folder
#   sh ai-output-dir.sh --print-only  resolve the folder and print it. Change nothing
#   sh ai-output-dir.sh --root        print the root folder only. Change nothing
#
# The folder is <root>/<project key>.
#   root  $AI_AGENT_OUTPUT_DIR, or ~/.ai when it is not set. A literal ~, $HOME or ${HOME} at the start is expanded here,
#         because settings files do not expand it. A ~user path or a relative path is an error.
#   key   <host>/<path> of the Git remote (origin, else the first remote by name), without the user, the credentials,
#         the port and the .git suffix, in lowercase.
#         local/<name>-<hash> when there is no remote, when the remote is a local path, or outside a Git repository.
#         <name> is the last part of the absolute path without leading dots (root for /), and <hash> is the cksum CRC of
#         the absolute path as 8 lowercase hexadecimal digits. All worktrees of one repository share one folder.
#         The path keeps symbolic links as $PWD shows them. If the agent starts its shell in the resolved path, $PWD has
#         no symbolic link to keep, and the resolved path is used.
#         A linked worktree without a remote uses the folder whose .project-info has canonical=<main worktree path>.
#
# Exit codes: 0 success, 1 the folder or .project-info cannot be written, 2 bad usage, HOME or AI_AGENT_OUTPUT_DIR.
#
# This file is identical in every skill that has it. Change all copies together.

set -u

me=ai-output-dir.sh

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

local_key() { # absolute path. Prints local/<name>-<hash>.
  l_n=${1##*/}
  while :; do
    case $l_n in
      .*) l_n=${l_n#.} ;;
      *) break ;;
    esac
  done
  [ -n "$l_n" ] || l_n=root
  l_c=$(printf '%s' "$1" | cksum) || return 1
  l_c=${l_c%% *}
  printf 'local/%s-%08x\n' "$l_n" "$l_c"
}

normalize_remote() { # remote URL. Prints <host>/<path>, or nothing for a local path.
  n_u=$1
  case $n_u in
    '' | file:* | /* | ./* | ../* | '~'* | [A-Za-z]:\\* | [A-Za-z]:/*)
      return 0 ;;
    *://*)
      n_u=${n_u#*://}
      n_hostpart=${n_u%%/*}
      case $n_u in
        */*) n_path=${n_u#*/} ;;
        *) n_path= ;;
      esac
      n_hostpart=${n_hostpart##*@}
      case $n_hostpart in
        '['*) n_host=${n_hostpart%%]*}] ;;
        *) n_host=${n_hostpart%%:*} ;;
      esac ;;
    *:*)
      n_before=${n_u%%:*}
      # A "/" before the first ":" means a local path, not host:path.
      case $n_before in
        */*) return 0 ;;
      esac
      n_path=${n_u#*:}
      n_host=${n_before##*@} ;;
    *)
      return 0 ;;
  esac
  while :; do
    case $n_path in
      /* | '~'*) n_path=${n_path#?} ;;
      *) break ;;
    esac
  done
  while [ "${n_path%/}" != "$n_path" ]; do n_path=${n_path%/}; done
  n_path=${n_path%.git}
  while [ "${n_path%/}" != "$n_path" ]; do n_path=${n_path%/}; done
  n_host=$(printf '%s' "$n_host" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9._-' '-')
  n_path=$(printf '%s' "$n_path" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9._/-' '-' | tr -s '/')
  if [ -z "$n_host" ] || [ -z "$n_path" ]; then return 0; fi
  case $n_host in
    . | ..) return 0 ;;
  esac
  case /$n_path/ in
    */./* | */../*) return 0 ;;
  esac
  printf '%s/%s\n' "$n_host" "$n_path"
}

usage="usage: sh $me [--print-only | --root]"
mode=create
case $# in
  0) ;;
  1)
    case $1 in
      --print-only) mode=print ;;
      --root) mode=root ;;
      *) die 2 "$usage" ;;
    esac ;;
  *) die 2 "$usage" ;;
esac

# The root.
case ${HOME:-} in
  /*) ;;
  *) die 2 "HOME is not set to an absolute path" ;;
esac
v=${AI_AGENT_OUTPUT_DIR:-}
[ -n "$v" ] || v=$HOME/.ai
# The patterns match the literal text ~, $HOME and ${HOME}, which settings files leave unexpanded.
# shellcheck disable=SC2016,SC2088
case $v in
  '~' | '$HOME' | '${HOME}') root=$HOME ;;
  '~/'*) root=$HOME/${v#'~/'} ;;
  '$HOME/'*) root=$HOME/${v#'$HOME/'} ;;
  '${HOME}/'*) root=$HOME/${v#'${HOME}/'} ;;
  '~'*) die 2 "AI_AGENT_OUTPUT_DIR: ~user paths are not supported: $v" ;;
  *) root=$v ;;
esac
case $root in
  /*) ;;
  *) die 2 "AI_AGENT_OUTPUT_DIR must be an absolute path, ~ or start with ~/ or \$HOME/: $v" ;;
esac
root=$(strip_slashes "$root")
if [ "$mode" = root ]; then
  printf '%s\n' "$root"
  exit 0
fi
base=$root
[ "$root" != / ] || base=

# The current folder, with its symbolic links when $PWD is correct.
phys=$(pwd -P) || die 1 "cannot read the current folder"
logical=$phys
case ${PWD:-} in
  /*)
    if [ "$(phys_of "$PWD")" = "$phys" ]; then logical=$(strip_slashes "$PWD"); fi ;;
esac

in_git=false
if command -v git >/dev/null 2>&1 && [ "$(git rev-parse --is-inside-work-tree 2>/dev/null)" = true ]; then
  in_git=true
fi

if $in_git; then
  top_phys=$(phys_of "$(git rev-parse --show-toplevel)") || die 1 "cannot find the Git repository root"
  prefix=$(git rev-parse --show-prefix)
  prefix=${prefix%/}
  if [ -z "$prefix" ]; then
    top_logical=$logical
  else
    case $logical in
      */"$prefix") top_logical=${logical%/"$prefix"} ;;
      *) top_logical=$top_phys ;;
    esac
  fi
  # A symbolic link inside the repository can make the logical root wrong.
  [ "$(phys_of "$top_logical")" = "$top_phys" ] || top_logical=$top_phys

  common=$(phys_of "$(git rev-parse --git-common-dir)")
  gitdir=$(phys_of "$(git rev-parse --git-dir)")
  linked=false
  [ "$gitdir" = "$common" ] || linked=true
  if ! $linked; then
    main_canonical=$top_phys
  else
    case $common in
      */.git) main_canonical=${common%/.git} ;;
      *) main_canonical=$common ;;
    esac
  fi

  remotes=$(git remote 2>/dev/null)
  remote=
  if [ -n "$remotes" ]; then
    if printf '%s\n' "$remotes" | grep -qxF -e origin; then
      remote=origin
    else
      remote=$(printf '%s\n' "$remotes" | LC_ALL=C sort | head -n 1)
    fi
  fi
  rkey=
  if [ -n "$remote" ]; then
    url=$(git remote get-url "$remote" 2>/dev/null) || url=
    rkey=$(normalize_remote "$url")
  fi

  path_line=$top_logical
  canonical_line=$main_canonical
  if [ -n "$rkey" ]; then
    kind=remote
    out=$base/$rkey
  elif ! $linked; then
    kind=local
    lkey=$(local_key "$top_logical") || die 1 "cannot calculate the local key of $top_logical"
    out=$base/$lkey
  else
    kind=local
    lkey=$(local_key "$main_canonical") || die 1 "cannot calculate the local key of $main_canonical"
    out=$base/$lkey
    if [ -d "$base/local" ]; then
      found=$(find "$base/local" -name .project-info -type f 2>/dev/null | LC_ALL=C sort | while IFS= read -r f; do
        if grep -qxF -e "canonical=$main_canonical" "$f" 2>/dev/null; then
          printf '%s\n' "${f%/.project-info}"
          break
        fi
      done)
      [ -z "$found" ] || out=$found
    fi
  fi
else
  kind=local
  lkey=$(local_key "$logical") || die 1 "cannot calculate the local key of $logical"
  out=$base/$lkey
  path_line=$logical
  canonical_line=$phys
fi

if [ "$mode" = print ]; then
  printf '%s\n' "$out"
  exit 0
fi

mkdir -p -- "$out" 2>/dev/null || die 1 "cannot create $out. If the agent runs in a sandbox, allow writes to $root."
info=$out/.project-info
if [ ! -f "$info" ]; then
  printf '%s\n' '# Written by ai-output-dir.sh. One key=value per line. path and canonical lines list every location that used this folder.' \
    >"$info" 2>/dev/null || die 1 "cannot write $info. If the agent runs in a sandbox, allow writes to $root."
fi

add_line() { # line. Adds it to .project-info unless the file has it already.
  grep -qxF -e "$1" "$info" 2>/dev/null && return 0
  printf '%s\n' "$1" >>"$info" 2>/dev/null || die 1 "cannot write $info. If the agent runs in a sandbox, allow writes to $root."
}

add_line "kind=$kind"
if [ "$kind" = remote ]; then add_line "remote=$rkey"; fi
add_line "path=$path_line"
add_line "canonical=$canonical_line"

printf '%s\n' "$out"
