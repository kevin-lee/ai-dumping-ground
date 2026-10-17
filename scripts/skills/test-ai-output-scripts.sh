#!/bin/bash
# Runs ai-output-dir.sh and migrate-ai-output.sh against throwaway Git repositories and folders in a temporary folder and
# checks the results. It never touches your real AI agent output folder.
#
# Usage:
#   bash scripts/skills/test-ai-output-scripts.sh
#
# Environment variables:
#   SH_UNDER_TEST    shell used to run the scripts (default: /bin/sh)
#   KEEP_TEST_DIR=1  keep the work folder even when every check passes
#   NO_COLOR=1       no color, even in a terminal
#   FORCE_COLOR=1    color, even in a pipe or a file (NO_COLOR wins over it)

# shellcheck disable=SC2319 # each check receives the status of the condition written right before it
# shellcheck disable=SC2016 # the $HOME cases pass the literal text on purpose
set -u

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
S="$REPO/skills/riper-5/scripts"
SH_UNDER_TEST="${SH_UNDER_TEST:-/bin/sh}"

# Color only for a terminal. NO_COLOR turns it off, FORCE_COLOR turns it on for a pipe or a file.
use_color() { # file descriptor
  [ -z "${NO_COLOR:-}" ] && { [ -n "${FORCE_COLOR:-}" ] || [ -t "$1" ]; }
}
if use_color 1; then
  GREEN=$(printf '\033[32m'); RED=$(printf '\033[31m'); YELLOW=$(printf '\033[33m')
  BOLD=$(printf '\033[1m'); DIM=$(printf '\033[2m'); RESET=$(printf '\033[0m')
else
  GREEN=""; RED=""; YELLOW=""; BOLD=""; DIM=""; RESET=""
fi
if use_color 2; then
  ERR_RED=$(printf '\033[31m'); ERR_RESET=$(printf '\033[0m')
else
  ERR_RED=""; ERR_RESET=""
fi

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

WORK=$(mktemp -d "${TMPDIR:-/tmp}/test-ai-output-scripts.XXXXXX") || exit 1
# The physical path, so a symbolic link in the temporary folder (/var on macOS) does not change the expected paths.
WORK=$(cd -P "$WORK" && pwd)
H="$WORK/home"
mkdir -p "$H"
R="$H/.ai"
PASSES=0
FAILS=0
SKIPS=0

check() { # name, status
  if [ "$2" -eq 0 ]; then
    echo "${GREEN}PASS${RESET} $1"
    PASSES=$((PASSES + 1))
  else
    echo "${BOLD}${RED}FAIL${RESET} $1"
    FAILS=$((FAILS + 1))
    echo "${DIM}  --- rc: $(cat "$WORK/rc" 2>/dev/null) ---${RESET}"
    echo "${DIM}  --- out ---${RESET}"; cat "$WORK/out" 2>/dev/null
    echo "${DIM}  --- err ---${RESET}"; cat "$WORK/err" 2>/dev/null
  fi
}

skip() { # name, reason
  echo "${YELLOW}SKIP${RESET} $1 ($2)"
  SKIPS=$((SKIPS + 1))
}

# Runs a script in a folder: folder, [VAR=value ...], script name, [arguments ...].
run() {
  local dir="$1"; shift
  local envs=()
  while [[ "${1:-}" == *=* ]]; do envs+=("$1"); shift; done
  local script="$1"; shift
  (cd "$dir" && env -u AI_AGENT_OUTPUT_DIR HOME="$H" ${envs[@]+"${envs[@]}"} \
    "$SH_UNDER_TEST" "$S/$script" ${1+"$@"} >"$WORK/out" 2>"$WORK/err"; echo $? >"$WORK/rc")
}

out() { cat "$WORK/out"; }
rc() { cat "$WORK/rc"; }

g() { # folder, git arguments
  local dir="$1"; shift
  git -C "$dir" -c user.name=test -c user.email=test@example.invalid -c init.defaultBranch=main "$@" >/dev/null 2>&1
}

mkrepo() { # name, [origin URL]
  mkdir -p "$WORK/$1"
  g "$WORK/$1" init -q
  if [ -n "${2:-}" ]; then g "$WORK/$1" remote add origin "$2"; fi
}

commit() { # name
  g "$WORK/$1" commit -q --allow-empty -m init
}

snap() { # folder
  [ -e "$1" ] || { echo "missing"; return; }
  (cd "$1" && find . | LC_ALL=C sort | while IFS= read -r f; do
    if [ -f "$f" ]; then printf '%s %s\n' "$f" "$(cksum < "$f")"; else printf '%s\n' "$f"; fi
  done)
}

has_line() { # file, line
  grep -qxF -e "$2" "$1" 2>/dev/null
}

if ! command -v git >/dev/null 2>&1; then
  echo "${ERR_RED}error: git is required${ERR_RESET}" >&2
  exit 1
fi

echo "${DIM}Shell under test: $SH_UNDER_TEST${RESET}"
echo "${DIM}Work folder: $WORK${RESET}"

# 1. Copies
for f in ai-output-dir.sh migrate-ai-output.sh; do
  for s in pr-analysis gen-motion-graphics; do
    cmp -s "$REPO/skills/riper-5/scripts/$f" "$REPO/skills/$s/scripts/$f"
    check "copy: skills/$s/scripts/$f is identical to the riper-5 copy" $?
  done
  for s in riper-5 pr-analysis gen-motion-graphics; do
    [ -x "$REPO/skills/$s/scripts/$f" ]
    check "copy: skills/$s/scripts/$f is executable" $?
  done
done

# 2. Root
mkdir -p "$WORK/plain"
run "$WORK/plain" ai-output-dir.sh --root
[ "$(rc)" = 0 ] && [ "$(out)" = "$R" ]
check "root: unset gives \$HOME/.ai" $?

run "$WORK/plain" 'AI_AGENT_OUTPUT_DIR=~/x' ai-output-dir.sh --root
[ "$(out)" = "$H/x" ]
check "root: literal ~/x is expanded" $?

run "$WORK/plain" 'AI_AGENT_OUTPUT_DIR=~' ai-output-dir.sh --root
[ "$(out)" = "$H" ]
check "root: literal ~ is expanded" $?

run "$WORK/plain" 'AI_AGENT_OUTPUT_DIR=$HOME/x' ai-output-dir.sh --root
[ "$(out)" = "$H/x" ]
check "root: literal \$HOME/x is expanded" $?

run "$WORK/plain" 'AI_AGENT_OUTPUT_DIR=${HOME}/x' ai-output-dir.sh --root
[ "$(out)" = "$H/x" ]
check "root: literal \${HOME}/x is expanded" $?

run "$WORK/plain" 'AI_AGENT_OUTPUT_DIR=$HOME' ai-output-dir.sh --root
[ "$(out)" = "$H" ]
check "root: literal \$HOME is expanded" $?

run "$WORK/plain" "AI_AGENT_OUTPUT_DIR=$WORK/abs/x//" ai-output-dir.sh --root
[ "$(out)" = "$WORK/abs/x" ]
check "root: trailing slashes are removed" $?

run "$WORK/plain" 'AI_AGENT_OUTPUT_DIR=~/x' ai-output-dir.sh
[ "$(rc)" = 0 ] && [ -d "$H/x/local$WORK/plain" ] && [ ! -e "$WORK/plain/~" ]
check "root: ~/x creates the folder under \$HOME, not a ~ folder" $?

run "$WORK/plain" AI_AGENT_OUTPUT_DIR=x ai-output-dir.sh
[ "$(rc)" = 2 ] && [ -s "$WORK/err" ] && [ -z "$(out)" ] && [ ! -e "$WORK/plain/x" ]
check "root: a relative path exits 2 and creates nothing" $?

run "$WORK/plain" 'AI_AGENT_OUTPUT_DIR=~bob/x' ai-output-dir.sh
[ "$(rc)" = 2 ] && [ -s "$WORK/err" ] && [ ! -e "$WORK/plain/~bob" ]
check "root: ~user exits 2 and creates nothing" $?

run "$WORK/plain" ai-output-dir.sh --bad
[ "$(rc)" = 2 ]
check "usage: an unknown option exits 2" $?

# 3. Remote forms
expect_key() { # name, URL, expected key
  mkrepo "$1" "$2"
  run "$WORK/$1" ai-output-dir.sh --print-only
  [ "$(rc)" = 0 ] && [ "$(out)" = "$R/$3" ]
  check "remote: $2 gives $3" $?
}
expect_key r-scp 'git@github.com:Kevin-Lee/Repo.git' github.com/kevin-lee/repo
expect_key r-https 'https://github.com/o/r.git' github.com/o/r
expect_key r-ssh-port 'ssh://git@host.example:2222/o/r.git' host.example/o/r
expect_key r-nested 'https://gitlab.example/group/sub/r.git/' gitlab.example/group/sub/r
expect_key r-file 'file:///srv/r.git' "local$WORK/r-file"
expect_key r-abs '/srv/r.git' "local$WORK/r-abs"
expect_key r-rel '../r' "local$WORK/r-rel"

mkrepo r-cred 'https://user:secret-token@github.com/o/cred'
run "$WORK/r-cred" ai-output-dir.sh
[ "$(rc)" = 0 ] && [ "$(out)" = "$R/github.com/o/cred" ]
check "remote: credentials are removed from the key" $?
! grep -rq secret-token "$R" "$WORK/out" "$WORK/err" && [ -z "$(find "$R" -name '*secret*')" ]
check "remote: the token is in no folder name, no .project-info and no output" $?

# 4. Remote choice
mkrepo r-choice
g "$WORK/r-choice" remote add aaa https://a.example/x/aaa
g "$WORK/r-choice" remote add origin https://o.example/x/origin
run "$WORK/r-choice" ai-output-dir.sh --print-only
[ "$(out)" = "$R/o.example/x/origin" ]
check "remote choice: origin wins over aaa" $?

mkrepo r-noorigin
g "$WORK/r-noorigin" remote add beta https://b.example/x/beta
g "$WORK/r-noorigin" remote add alpha https://a.example/x/alpha
run "$WORK/r-noorigin" ai-output-dir.sh --print-only
[ "$(out)" = "$R/a.example/x/alpha" ]
check "remote choice: without origin, alpha wins over beta" $?

# 5. No remote
mkrepo norem
mkdir -p "$WORK/norem/sub/deep"
run "$WORK/norem" ai-output-dir.sh --print-only
[ "$(out)" = "$R/local$WORK/norem" ]
check "no remote: local/<repository root>" $?
run "$WORK/norem/sub/deep" ai-output-dir.sh --print-only
[ "$(out)" = "$R/local$WORK/norem" ]
check "no remote: the same folder from a subfolder" $?

# 6. Symbolic links
ln -s "$WORK/norem" "$WORK/link-norem"
run "$WORK/link-norem/sub" ai-output-dir.sh
[ "$(rc)" = 0 ] && [ "$(out)" = "$R/local$WORK/link-norem" ]
check "symlink: a repository opened through a symbolic link keeps the link path" $?
has_line "$R/local$WORK/link-norem/.project-info" "path=$WORK/link-norem" &&
  has_line "$R/local$WORK/link-norem/.project-info" "canonical=$WORK/norem"
check "symlink: .project-info has the link path and the canonical path" $?

ln -s "$WORK/plain" "$WORK/link-plain"
run "$WORK/link-plain" ai-output-dir.sh
[ "$(out)" = "$R/local$WORK/link-plain" ] &&
  has_line "$R/local$WORK/link-plain/.project-info" "canonical=$WORK/plain"
check "symlink: a non-Git folder keeps the link path" $?

# 7. Worktrees
mkrepo wtr https://github.com/o/wtr
commit wtr
g "$WORK/wtr" worktree add -q "$WORK/wtr-wt"
if [ -d "$WORK/wtr-wt" ]; then
  run "$WORK/wtr-wt" ai-output-dir.sh --print-only
  [ "$(out)" = "$R/github.com/o/wtr" ]
  check "worktree: a linked worktree with a remote uses the repository folder" $?
else
  skip "worktree: a linked worktree with a remote" "git worktree add failed"
fi

mkrepo wtn
commit wtn
ln -s "$WORK/wtn" "$WORK/link-wtn"
g "$WORK/wtn" worktree add -q "$WORK/wtn-wt"
if [ -d "$WORK/wtn-wt" ]; then
  run "$WORK/wtn-wt" ai-output-dir.sh --print-only
  [ "$(out)" = "$R/local$WORK/wtn" ]
  check "worktree: without a remote and without a prior run, local/<canonical main path>" $?
  run "$WORK/link-wtn" ai-output-dir.sh
  [ "$(out)" = "$R/local$WORK/link-wtn" ]
  check "worktree: the main worktree through a symbolic link keeps the link path" $?
  run "$WORK/wtn-wt" ai-output-dir.sh
  [ "$(out)" = "$R/local$WORK/link-wtn" ]
  check "worktree: without a remote, the linked worktree finds the main worktree folder" $?
else
  skip "worktree: linked worktrees without a remote" "git worktree add failed"
fi

# 8. Not Git
mkdir -p "$WORK/notgit"
run "$WORK/notgit" ai-output-dir.sh --print-only
[ "$(out)" = "$R/local$WORK/notgit" ]
check "not Git: local/<folder>" $?

# 9. .project-info
mkrepo info https://github.com/o/info
run "$WORK/info" ai-output-dir.sh
run "$WORK/info" ai-output-dir.sh
I="$R/github.com/o/info/.project-info"
[ -z "$(grep -v '^#' "$I" | LC_ALL=C sort | uniq -d)" ]
check ".project-info: a second run adds no duplicate line" $?
has_line "$I" kind=remote && has_line "$I" remote=github.com/o/info && has_line "$I" "path=$WORK/info" &&
  has_line "$I" "canonical=$WORK/info"
check ".project-info: kind, remote, path and canonical lines" $?

run "$WORK/info" "AI_AGENT_OUTPUT_DIR=$WORK/fresh-root" ai-output-dir.sh --print-only
[ "$(out)" = "$WORK/fresh-root/github.com/o/info" ] && [ ! -e "$WORK/fresh-root" ]
check "--print-only creates nothing" $?

# 10. Migration
mkrepo migempty https://github.com/o/migempty
run "$WORK/migempty" migrate-ai-output.sh --check plans "done"
[ "$(rc)" = 1 ] && [ -z "$(out)" ]
check "migrate: --check with nothing to move exits 1 and prints nothing" $?

mkrepo mig https://github.com/o/mig
D="$R/github.com/o/mig"
mkdir -p "$WORK/mig/.ai/plans/2026-10" "$WORK/mig/.ai/done/2026-09" "$WORK/mig/.ai/examples" "$D/done/2026-09" "$D/plans/2026-10"
echo a > "$WORK/mig/.ai/plans/2026-10/a.md"
echo same > "$WORK/mig/.ai/plans/2026-10/same.md"
echo same > "$D/plans/2026-10/same.md"
echo b-old > "$WORK/mig/.ai/done/2026-09/b.md"
echo b-new > "$D/done/2026-09/b.md"
echo e > "$WORK/mig/.ai/examples/e.html"
echo ds > "$WORK/mig/.ai/plans/.DS_Store"

run "$WORK/mig" migrate-ai-output.sh --check plans "done"
[ "$(rc)" = 0 ] && [ "$(out)" = "$WORK/mig/.ai/plans
$WORK/mig/.ai/done" ]
check "migrate: --check with files exits 0 and prints the folders" $?

before_src=$(snap "$WORK/mig"); before_dst=$(snap "$R")
run "$WORK/mig" migrate-ai-output.sh plans "done"
[ "$(rc)" = 0 ] && [ "$before_src" = "$(snap "$WORK/mig")" ] && [ "$before_dst" = "$(snap "$R")" ]
check "migrate: a dry run changes nothing" $?
grep -qxF "move $WORK/mig/.ai/plans/2026-10/a.md -> $D/plans/2026-10/a.md" "$WORK/out" &&
  grep -q "^same $WORK/mig/.ai/plans/2026-10/same.md " "$WORK/out" &&
  grep -q "^conflict $WORK/mig/.ai/done/2026-09/b.md " "$WORK/out"
check "migrate: a dry run reports move, same and conflict" $?

run "$WORK/mig" migrate-ai-output.sh --apply plans "done"
[ "$(rc)" = 3 ]
check "migrate: --apply with a conflict exits 3" $?
[ -f "$D/plans/2026-10/a.md" ] && [ ! -e "$WORK/mig/.ai/plans/2026-10/a.md" ]
check "migrate: --apply moves a file" $?
[ "$(cat "$WORK/mig/.ai/done/2026-09/b.md")" = b-old ] && [ "$(cat "$D/done/2026-09/b.md")" = b-new ]
check "migrate: a conflict stays in place and the destination is not overwritten" $?
[ -f "$WORK/mig/.ai/plans/2026-10/same.md" ]
check "migrate: an identical file stays in place" $?
[ -f "$D/.project-info" ]
check "migrate: --apply writes .project-info" $?
[ -f "$WORK/mig/.ai/examples/e.html" ] && [ -f "$WORK/mig/.ai/plans/.DS_Store" ] && [ -d "$WORK/mig/.ai" ]
check "migrate: other content, .DS_Store and the .ai folder are not touched" $?
grep -q '^Left in place:' "$WORK/out" && grep -qxF "$WORK/mig/.ai/done/2026-09/b.md" "$WORK/out"
check "migrate: --apply lists what is left in place" $?

mkrepo mig2 https://github.com/o/mig2
mkdir -p "$WORK/mig2/.ai/docs/pr/no-ticket"
echo r > "$WORK/mig2/.ai/docs/pr/no-ticket/pr-1-report.html"
run "$WORK/mig2" migrate-ai-output.sh --apply docs/pr
[ "$(rc)" = 0 ] && [ -f "$R/github.com/o/mig2/docs/pr/no-ticket/pr-1-report.html" ] && [ -d "$WORK/mig2/.ai/docs/pr/no-ticket" ]
check "migrate: --apply without conflicts exits 0 and keeps the empty folders" $?

mkdir -p "$WORK/vid/video/x/sources"
echo s > "$WORK/vid/video/x/sources/s.txt"
run "$WORK/vid" migrate-ai-output.sh --check --from "$WORK/vid" video
[ "$(rc)" = 0 ]
check "migrate: --check --from finds ./video outside Git" $?
run "$WORK/vid" migrate-ai-output.sh --apply --from "$WORK/vid" video
[ "$(rc)" = 0 ] && [ -f "$R/local$WORK/vid/video/x/sources/s.txt" ]
check "migrate: --apply --from moves ./video outside Git" $?

run "$WORK/mig2" migrate-ai-output.sh /x
[ "$(rc)" = 2 ]
check "migrate: an absolute item exits 2" $?
run "$WORK/mig2" migrate-ai-output.sh a/../b
[ "$(rc)" = 2 ]
check "migrate: an item with .. exits 2" $?
run "$WORK/mig2" migrate-ai-output.sh --check --apply plans
[ "$(rc)" = 2 ]
check "migrate: --check with --apply exits 2" $?
run "$WORK/mig2" migrate-ai-output.sh
[ "$(rc)" = 2 ]
check "migrate: no item exits 2" $?

echo
if [ "$FAILS" -eq 0 ]; then SUMMARY_COLOR="$GREEN"; else SUMMARY_COLOR="$RED"; fi
echo "${BOLD}${SUMMARY_COLOR}$PASSES passed, $FAILS failed, $SKIPS skipped${RESET}"
if [ "$FAILS" -eq 0 ] && [ "${KEEP_TEST_DIR:-}" != 1 ]; then
  rm -rf "$WORK"
else
  echo "${YELLOW}Work folder kept: $WORK${RESET}"
fi
[ "$FAILS" -eq 0 ]
