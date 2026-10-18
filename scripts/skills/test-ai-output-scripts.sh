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
C="$REPO/skills/centralize-ai-output/scripts"
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

# Runs a centralize-ai-output script: the same arguments as run.
runc() {
  local saved="$S"
  S="$C"
  run "$@"
  S="$saved"
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

lkey() { # absolute path. Prints the expected local key: local/<name>-<hash>
  local n="${1##*/}" c
  while [[ "$n" == .* ]]; do n="${n#.}"; done
  [ -n "$n" ] || n=root
  c=$(printf '%s' "$1" | cksum)
  printf 'local/%s-%08x\n' "$n" "${c%% *}"
}

if ! command -v git >/dev/null 2>&1; then
  echo "${ERR_RED}error: git is required${ERR_RESET}" >&2
  exit 1
fi

echo "${DIM}Shell under test: $SH_UNDER_TEST${RESET}"
echo "${DIM}Work folder: $WORK${RESET}"

# 1. Copies
for f in ai-output-dir.sh migrate-ai-output.sh; do
  for s in pr-analysis gen-motion-graphics centralize-ai-output; do
    cmp -s "$REPO/skills/riper-5/scripts/$f" "$REPO/skills/$s/scripts/$f"
    check "copy: skills/$s/scripts/$f is identical to the riper-5 copy" $?
  done
  for s in riper-5 pr-analysis gen-motion-graphics centralize-ai-output; do
    [ -x "$REPO/skills/$s/scripts/$f" ]
    check "copy: skills/$s/scripts/$f is executable" $?
  done
done

for f in link-ai-folder.sh install-rule.sh; do
  [ -x "$C/$f" ]
  check "copy: skills/centralize-ai-output/scripts/$f is executable" $?
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
[ "$(rc)" = 0 ] && [ -d "$H/x/$(lkey "$WORK/plain")" ] && [ ! -e "$WORK/plain/~" ]
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
expect_key r-file 'file:///srv/r.git' "$(lkey "$WORK/r-file")"
expect_key r-abs '/srv/r.git' "$(lkey "$WORK/r-abs")"
expect_key r-rel '../r' "$(lkey "$WORK/r-rel")"

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
[ "$(out)" = "$R/$(lkey "$WORK/norem")" ]
check "no remote: local/<name>-<hash> of the repository root" $?
run "$WORK/norem/sub/deep" ai-output-dir.sh --print-only
[ "$(out)" = "$R/$(lkey "$WORK/norem")" ]
check "no remote: the same folder from a subfolder" $?

# 6. Symbolic links
ln -s "$WORK/norem" "$WORK/link-norem"
run "$WORK/link-norem/sub" ai-output-dir.sh
[ "$(rc)" = 0 ] && [ "$(out)" = "$R/$(lkey "$WORK/link-norem")" ]
check "symlink: a repository opened through a symbolic link keeps the link path" $?
has_line "$R/$(lkey "$WORK/link-norem")/.project-info" "path=$WORK/link-norem" &&
  has_line "$R/$(lkey "$WORK/link-norem")/.project-info" "canonical=$WORK/norem"
check "symlink: .project-info has the link path and the canonical path" $?

ln -s "$WORK/plain" "$WORK/link-plain"
run "$WORK/link-plain" ai-output-dir.sh
[ "$(out)" = "$R/$(lkey "$WORK/link-plain")" ] &&
  has_line "$R/$(lkey "$WORK/link-plain")/.project-info" "canonical=$WORK/plain"
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
  [ "$(out)" = "$R/$(lkey "$WORK/wtn")" ]
  check "worktree: without a remote and without a prior run, local/<name>-<hash> of the canonical main path" $?
  run "$WORK/link-wtn" ai-output-dir.sh
  [ "$(out)" = "$R/$(lkey "$WORK/link-wtn")" ]
  check "worktree: the main worktree through a symbolic link keeps the link path" $?
  run "$WORK/wtn-wt" ai-output-dir.sh
  [ "$(out)" = "$R/$(lkey "$WORK/link-wtn")" ]
  check "worktree: without a remote, the linked worktree finds the main worktree folder" $?
  [[ "$(out)" != *wtn-wt* ]]
  check "worktree: a linked worktree does not get its own folder" $?
else
  skip "worktree: linked worktrees without a remote" "git worktree add failed"
fi

# 8. Not Git
mkdir -p "$WORK/notgit"
run "$WORK/notgit" ai-output-dir.sh --print-only
[ "$(out)" = "$R/$(lkey "$WORK/notgit")" ]
check "not Git: local/<name>-<hash> of the folder" $?

[ "$(lkey /Users/me/work/notes)" = local/notes-995faa70 ]
check "local key: /Users/me/work/notes gives local/notes-995faa70" $?

mkdir -p "$WORK/deep/a/b/c/proj"
run "$WORK/deep/a/b/c/proj" ai-output-dir.sh --print-only
[ "$(out)" = "$R/$(lkey "$WORK/deep/a/b/c/proj")" ] && [[ "$(out)" != "$R/local/"*/* ]]
check "not Git: a deep path gives one folder level under local/" $?

mkdir -p "$WORK/p1/same" "$WORK/p2/same"
run "$WORK/p1/same" ai-output-dir.sh --print-only
SAME1=$(out)
run "$WORK/p2/same" ai-output-dir.sh --print-only
SAME2=$(out)
[[ "$SAME1" == "$R/local/same-"* ]] && [[ "$SAME2" == "$R/local/same-"* ]] && [ "$SAME1" != "$SAME2" ]
check "not Git: two folders with the same name get different folders" $?

mkdir -p "$WORK/.dotproj"
run "$WORK/.dotproj" ai-output-dir.sh --print-only
[ "$(out)" = "$R/$(lkey "$WORK/.dotproj")" ] && [[ "$(out)" == "$R/local/dotproj-"* ]]
check "not Git: leading dots are removed from the name" $?

if [ "$(git -C / rev-parse --is-inside-work-tree 2>/dev/null)" != true ]; then
  run / ai-output-dir.sh --print-only
  [ "$(out)" = "$R/local/root-661ae946" ]
  check "not Git: / gives local/root-<hash>" $?
else
  skip "not Git: / gives local/root-<hash>" "/ is inside a Git work tree"
fi

mkdir -p "$WORK/badbin" "$WORK/notgit2"
printf '#!/bin/sh\nexit 1\n' > "$WORK/badbin/cksum"
chmod +x "$WORK/badbin/cksum"
run "$WORK/notgit2" "PATH=$WORK/badbin:$PATH" ai-output-dir.sh
[ "$(rc)" = 1 ] && [ -s "$WORK/err" ] && [ -z "$(out)" ] && [ ! -e "$R/.project-info" ]
check "not Git: a failed cksum exits 1 and writes nothing" $?

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
[ "$(rc)" = 0 ] && [ -f "$R/$(lkey "$WORK/vid")/video/x/sources/s.txt" ]
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

# 11. Migration of everything
mkrepo all https://github.com/o/all
DA="$R/github.com/o/all"
mkdir -p "$WORK/all/.ai/plans/2026-10" "$WORK/all/.ai/examples"
echo p > "$WORK/all/.ai/plans/2026-10/p.md"
echo x > "$WORK/all/.ai/examples/x.html"
echo n > "$WORK/all/.ai/notes.md"
echo ds > "$WORK/all/.ai/.DS_Store"
run "$WORK/all" migrate-ai-output.sh --check --all
[ "$(rc)" = 0 ] && [ "$(out)" = "$WORK/all/.ai/examples
$WORK/all/.ai/notes.md
$WORK/all/.ai/plans" ]
check "migrate --all: --check lists every entry, the top-level file too" $?
before_src=$(snap "$WORK/all"); before_dst=$(snap "$R")
run "$WORK/all" migrate-ai-output.sh --all
[ "$(rc)" = 0 ] && [ "$before_src" = "$(snap "$WORK/all")" ] && [ "$before_dst" = "$(snap "$R")" ] &&
  grep -qxF "move $WORK/all/.ai/notes.md -> $DA/notes.md" "$WORK/out"
check "migrate --all: a dry run changes nothing and lists the top-level file" $?
run "$WORK/all" migrate-ai-output.sh --apply --all
[ "$(rc)" = 0 ] && [ -f "$DA/plans/2026-10/p.md" ] && [ -f "$DA/examples/x.html" ] && [ -f "$DA/notes.md" ] &&
  [ ! -e "$WORK/all/.ai/notes.md" ]
check "migrate --all: --apply moves every entry" $?
[ -f "$WORK/all/.ai/.DS_Store" ] && [ -d "$WORK/all/.ai/plans/2026-10" ] && [ ! -e "$DA/.DS_Store" ]
check "migrate --all: .DS_Store and the empty folders stay" $?
run "$WORK/all" migrate-ai-output.sh --all plans
[ "$(rc)" = 2 ]
check "migrate --all: --all with an item exits 2" $?
mkrepo all-none https://github.com/o/all-none
run "$WORK/all-none" migrate-ai-output.sh --check --all
[ "$(rc)" = 1 ] && [ -z "$(out)" ]
check "migrate --all: --check without .ai exits 1" $?
run "$WORK/all-none" migrate-ai-output.sh --apply --all
[ "$(rc)" = 0 ] && grep -q '^nothing to migrate: ' "$WORK/out" && [ ! -e "$R/github.com/o/all-none" ]
check "migrate --all: --apply without .ai has nothing to migrate and creates nothing" $?

# 12. Link
runc "$WORK/all" link-ai-folder.sh
[ "$(rc)" = 0 ] && grep -qxF "remove $WORK/all/.ai/.DS_Store" "$WORK/out" &&
  grep -qxF "rmdir $WORK/all/.ai/plans/2026-10" "$WORK/out" && grep -qxF "link $WORK/all/.ai -> $DA" "$WORK/out" &&
  [ -d "$WORK/all/.ai" ] && [ ! -L "$WORK/all/.ai" ]
check "link: a dry run lists the .DS_Store files and the empty folders, and changes nothing" $?
runc "$WORK/all" link-ai-folder.sh --apply
[ "$(rc)" = 0 ] && [ -L "$WORK/all/.ai" ] && [ "$(readlink "$WORK/all/.ai")" = "$DA" ] && [ -f "$DA/notes.md" ]
check "link: --apply removes them and links .ai to the output folder" $?
runc "$WORK/all" link-ai-folder.sh
[ "$(rc)" = 0 ] && grep -qxF "already linked: $WORK/all/.ai -> $DA" "$WORK/out"
check "link: a second run reports already linked" $?
run "$WORK/all" migrate-ai-output.sh --check --all
[ "$(rc)" = 1 ]
check "migrate: --check on a linked .ai exits 1" $?
run "$WORK/all" migrate-ai-output.sh --all
[ "$(rc)" = 0 ] && grep -q 'is already linked to' "$WORK/out"
check "migrate: a dry run on a linked .ai has nothing to migrate" $?

mkrepo lfiles https://github.com/o/lfiles
mkdir -p "$WORK/lfiles/.ai/plans"
echo k > "$WORK/lfiles/.ai/plans/keep.md"
runc "$WORK/lfiles" link-ai-folder.sh --apply
[ "$(rc)" = 4 ] && [ -f "$WORK/lfiles/.ai/plans/keep.md" ] && [ ! -L "$WORK/lfiles/.ai" ] && grep -q keep.md "$WORK/err"
check "link: files in .ai exit 4 and nothing changes" $?

mkrepo labsent https://github.com/o/labsent
runc "$WORK/labsent" link-ai-folder.sh --apply
[ "$(rc)" = 0 ] && [ "$(readlink "$WORK/labsent/.ai")" = "$R/github.com/o/labsent" ] && [ -d "$R/github.com/o/labsent" ]
check "link: without .ai, --apply creates the link" $?

mkrepo ltracked https://github.com/o/ltracked
mkdir -p "$WORK/ltracked/.ai"
: > "$WORK/ltracked/.ai/.DS_Store"
g "$WORK/ltracked" add -f .ai/.DS_Store
runc "$WORK/ltracked" link-ai-folder.sh --apply
[ "$(rc)" = 4 ] && [ ! -L "$WORK/ltracked/.ai" ]
check "link: a .ai tracked by Git exits 4" $?

mkrepo lother https://github.com/o/lother
mkdir -p "$WORK/elsewhere"
ln -s "$WORK/elsewhere" "$WORK/lother/.ai"
runc "$WORK/lother" link-ai-folder.sh --apply
[ "$(rc)" = 4 ] && [ "$(readlink "$WORK/lother/.ai")" = "$WORK/elsewhere" ]
check "link: a link to another place exits 4 and stays" $?

mkrepo lslash https://github.com/o/lslash
printf '.ai/\n' > "$WORK/lslash/.gitignore"
runc "$WORK/lslash" link-ai-folder.sh --apply
[ "$(rc)" = 0 ] && grep -q '^warning: .ai is not ignored by Git' "$WORK/out"
check "link: a .ai/ gitignore pattern gives the warning" $?
mkrepo lnoslash https://github.com/o/lnoslash
printf '.ai\n' > "$WORK/lnoslash/.gitignore"
runc "$WORK/lnoslash" link-ai-folder.sh --apply
[ "$(rc)" = 0 ] && ! grep -q '^warning:' "$WORK/out"
check "link: a .ai gitignore pattern gives no warning" $?

# 13. Install the rule
IH="$WORK/rule-home"
mkdir -p "$IH/claude" "$IH/codex"
printf 'old line 1\nold line 2' > "$IH/codex/AGENTS.md"
RULE_ENV=(HOME="$IH" CLAUDE_CONFIG_DIR="$IH/claude" CODEX_HOME="$IH/codex")
runc "$WORK/plain" "${RULE_ENV[@]}" install-rule.sh --print
grep -qF "sh $C/ai-output-dir.sh" "$WORK/out" && ! grep -qF '{{SCRIPT}}' "$WORK/out"
check "rule: --print has the absolute script path and no placeholder" $?
before=$(snap "$IH")
runc "$WORK/plain" "${RULE_ENV[@]}" install-rule.sh
[ "$(rc)" = 0 ] && [ "$before" = "$(snap "$IH")" ] &&
  grep -qxF "create $IH/claude/rules/Centralize-AI-Output.md" "$WORK/out" &&
  grep -qxF "update $IH/codex/AGENTS.md" "$WORK/out" && ! grep -q 'gemini' "$WORK/out" &&
  grep -q '^Cursor: ' "$WORK/out"
check "rule: a dry run lists the targets with a folder, skips gemini, and changes nothing" $?
runc "$WORK/plain" "${RULE_ENV[@]}" install-rule.sh --target gemini
grep -qxF "skip gemini (no folder $IH/.gemini)" "$WORK/out"
check "rule: a named target without its folder is skipped" $?
runc "$WORK/plain" "${RULE_ENV[@]}" install-rule.sh --apply
[ "$(rc)" = 0 ] && grep -qxF '# Centralize AI Output' "$IH/claude/rules/Centralize-AI-Output.md" &&
  [ "$(head -n 2 "$IH/codex/AGENTS.md")" = "old line 1
old line 2" ] && [ "$(grep -cxF '<!-- centralize-ai-output:start -->' "$IH/codex/AGENTS.md")" = 1 ] &&
  [ "$(find "$IH/codex" -name 'AGENTS.md.bak.*' | wc -l | tr -d ' ')" = 1 ]
check "rule: --apply writes the rule file and adds one block, and keeps the old lines with a backup" $?
runc "$WORK/plain" "${RULE_ENV[@]}" install-rule.sh --apply
[ "$(rc)" = 0 ] && grep -qxF "unchanged $IH/codex/AGENTS.md" "$WORK/out" &&
  grep -qxF "unchanged $IH/claude/rules/Centralize-AI-Output.md" "$WORK/out" &&
  [ "$(find "$IH" -name '*.bak.*' | wc -l | tr -d ' ')" = 1 ]
check "rule: a second --apply changes nothing and makes no backup" $?
sed 's/^# Centralize AI Output$/# Old title/' "$IH/codex/AGENTS.md" > "$WORK/agents.tmp" && cat "$WORK/agents.tmp" > "$IH/codex/AGENTS.md"
printf 'last line\n' >> "$IH/codex/AGENTS.md"
runc "$WORK/plain" "${RULE_ENV[@]}" install-rule.sh --apply --target codex
[ "$(rc)" = 0 ] && [ "$(grep -cxF '<!-- centralize-ai-output:start -->' "$IH/codex/AGENTS.md")" = 1 ] &&
  ! grep -qxF '# Old title' "$IH/codex/AGENTS.md" && grep -qxF 'last line' "$IH/codex/AGENTS.md" &&
  [ "$(find "$IH/codex" -name 'AGENTS.md.bak.*' | wc -l | tr -d ' ')" -ge 2 ]
check "rule: a changed block is replaced, the content after it stays, and a backup is made" $?
mkdir -p "$IH/real" "$IH/codex2"
printf 'linked file\n' > "$IH/real/AGENTS.md"
ln -s "$IH/real/AGENTS.md" "$IH/codex2/AGENTS.md"
runc "$WORK/plain" HOME="$IH" CODEX_HOME="$IH/codex2" install-rule.sh --apply --target codex
[ "$(rc)" = 0 ] && [ -L "$IH/codex2/AGENTS.md" ] && grep -qxF '<!-- centralize-ai-output:end -->' "$IH/real/AGENTS.md"
check "rule: a symbolic link AGENTS.md stays a link, and its file gets the block" $?
mkdir -p "$IH/codex3"
printf 'x\n<!-- centralize-ai-output:start -->\nno end\n' > "$IH/codex3/AGENTS.md"
cp "$IH/codex3/AGENTS.md" "$WORK/broken.md"
runc "$WORK/plain" HOME="$IH" CODEX_HOME="$IH/codex3" install-rule.sh --apply --target codex
[ "$(rc)" = 1 ] && cmp -s "$WORK/broken.md" "$IH/codex3/AGENTS.md"
check "rule: broken markers exit 1 and change nothing" $?
runc "$WORK/plain" "${RULE_ENV[@]}" install-rule.sh --target cursor
[ "$(rc)" = 2 ]
check "rule: --target cursor exits 2" $?

# 14. Output choices
cmp -s "$S/ai-output-choices.sh" "$REPO/skills/pr-analysis/scripts/ai-output-choices.sh"
check "choices: skills/pr-analysis/scripts/ai-output-choices.sh is identical to the riper-5 copy" $?
[ -x "$S/ai-output-choices.sh" ] && [ -x "$REPO/skills/pr-analysis/scripts/ai-output-choices.sh" ]
check "choices: both copies are executable" $?

kv() { # key. Prints its value from the last output.
  sed -n "s/^$1=//p" "$WORK/out"
}

mkrepo ch https://github.com/o/ch
CH="$R/github.com/o/ch"
before=$(snap "$H")
run "$WORK/ch" ai-output-choices.sh
[ "$(rc)" = 0 ] && [ "$(kv central)" = "$CH" ] && [ "$(kv central_exists)" = no ] &&
  [ "$(kv project)" = "$WORK/ch/.ai" ] && [ "$(kv project_exists)" = no ] && [ "$(kv ask)" = yes ] &&
  [ "$(kv recommended)" = central ] && [ "$(kv order)" = "central project other" ]
check "choices: neither exists gives central (Recommended), project, other" $?
[ "$before" = "$(snap "$H")" ] && [ ! -e "$WORK/ch/.ai" ]
check "choices: the script creates nothing" $?

mkdir -p "$WORK/ch/.ai"
run "$WORK/ch" ai-output-choices.sh
[ "$(kv project_exists)" = yes ] && [ "$(kv recommended)" = project ] && [ "$(kv order)" = "project central other" ]
check "choices: only .ai exists gives project (Recommended), central, other" $?

mkdir -p "$CH"
run "$WORK/ch" ai-output-choices.sh
[ "$(kv central_exists)" = yes ] && [ "$(kv project_exists)" = yes ] && [ "$(kv recommended)" = none ] &&
  [ "$(kv order)" = "central project other" ] && [ "$(kv ask)" = yes ]
check "choices: both exist gives central, project, other with no recommendation" $?

mkrepo ch2 https://github.com/o/ch2
mkdir -p "$R/github.com/o/ch2"
run "$WORK/ch2" ai-output-choices.sh
[ "$(kv central_exists)" = yes ] && [ "$(kv project_exists)" = no ] && [ "$(kv recommended)" = central ] &&
  [ "$(kv order)" = "central project other" ]
check "choices: only the central folder exists gives central (Recommended), project, other" $?

ln -s "$R/github.com/o/ch2" "$WORK/ch2/.ai"
run "$WORK/ch2" ai-output-choices.sh
[ "$(kv ask)" = no ] && [ "$(kv use)" = "$R/github.com/o/ch2" ] && [ "$(kv project_exists)" = yes ]
check "choices: .ai linked to the central folder gives ask=no and use=<central>" $?

run "$WORK/ch" 'AI_AGENT_OUTPUT_DIR=~/custom' ai-output-choices.sh
[ "$(kv central)" = "$H/custom/github.com/o/ch" ]
check "choices: AI_AGENT_OUTPUT_DIR=~/custom moves the central folder under \$HOME/custom" $?

run "$WORK/ch" AI_AGENT_OUTPUT_DIR=relative ai-output-choices.sh
[ "$(rc)" = 0 ] && [ -z "$(kv central)" ] && [ -n "$(kv central_error)" ] && [ "$(kv order)" = "project other" ] &&
  [ "$(kv recommended)" = project ]
check "choices: a bad AI_AGENT_OUTPUT_DIR gives central_error and no central option, exit 0" $?

mkdir -p "$WORK/ch/sub/deep"
run "$WORK/ch/sub/deep" ai-output-choices.sh
[ "$(kv project)" = "$WORK/ch/.ai" ]
check "choices: from a subfolder, project is .ai in the repository root" $?

[ "$(kv migrate)" = "sh $S/migrate-ai-output.sh --all" ]
check "choices: migrate is the dry run with the absolute script path" $?

run "$WORK/ch" ai-output-choices.sh --x
[ "$(rc)" = 2 ]
check "choices: an argument exits 2" $?

echo
if [ "$FAILS" -eq 0 ]; then SUMMARY_COLOR="$GREEN"; else SUMMARY_COLOR="$RED"; fi
echo "${BOLD}${SUMMARY_COLOR}$PASSES passed, $FAILS failed, $SKIPS skipped${RESET}"
if [ "$FAILS" -eq 0 ] && [ "${KEEP_TEST_DIR:-}" != 1 ]; then
  rm -rf "$WORK"
else
  echo "${YELLOW}Work folder kept: $WORK${RESET}"
fi
[ "$FAILS" -eq 0 ]
