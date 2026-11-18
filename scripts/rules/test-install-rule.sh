#!/bin/bash
# Runs install-rule.sh against throwaway home and project folders and checks the results. It never touches the real
# agent config folders. It needs bash, git and curl (for file:// downloads), and no network access.
#
# Usage:
#   bash scripts/rules/test-install-rule.sh
#
# Environment variables:
#   SH_UNDER_TEST    shell used to run the installer (default: /bin/sh)
#   KEEP_TEST_DIR=1  keep the work folder even when every check passes
#   NO_COLOR=1       no color. FORCE_COLOR=1 keeps the color in a pipe

# shellcheck disable=SC2319 # each check receives the status of the condition written right before it
set -u

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
INSTALLER="$HERE/install-rule.sh"
RULES="$(cd "$HERE/../../rules" && pwd)"
RULE="$RULES/Clear-Writing.md"
SH_UNDER_TEST="${SH_UNDER_TEST:-/bin/sh}"
START='<!-- rule:Clear-Writing:start -->'
END='<!-- rule:Clear-Writing:end -->'

if { [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; } || [ -n "${FORCE_COLOR:-}" ]; then
  GREEN=$'\033[32m'; RED=$'\033[31m'; YELLOW=$'\033[33m'; RESET=$'\033[0m'
else
  GREEN=; RED=; YELLOW=; RESET=
fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/test-install-rule.XXXXXX") || exit 1
PASSES=0
FAILS=0
SKIPS=0
# The case folder whose out and err are printed when a check fails.
CASE=""

check() { # name, status
  if [ "$2" -eq 0 ]; then
    echo "${GREEN}PASS${RESET} $1"
    PASSES=$((PASSES + 1))
  else
    echo "${RED}FAIL${RESET} $1"
    FAILS=$((FAILS + 1))
    if [ -n "$CASE" ]; then
      echo "  --- out ---"; cat "$CASE/out" 2>/dev/null
      echo "  --- err ---"; cat "$CASE/err" 2>/dev/null
    fi
  fi
}

skip() { # name, reason
  echo "${YELLOW}SKIP${RESET} $1 ($2)"
  SKIPS=$((SKIPS + 1))
}

new_case() {
  local c="$WORK/$1"
  mkdir -p "$c/home" "$c/tmp" "$c/project"
  printf '%s\n' "$c"
}

# Runs the installer with the arguments, in the project folder of the case.
run() {
  local c="$1"; shift
  (cd "$c/project" && env -u CLAUDE_CONFIG_DIR -u CODEX_HOME -u RULE_BASE_URL HOME="$c/home" TMPDIR="$c/tmp" \
    "$SH_UNDER_TEST" "$INSTALLER" "$@" >"$c/out" 2>"$c/err"; echo $? >"$c/rc")
}

# Runs the installer with environment variables first: run_env <case> VAR=value... -- <arguments>.
run_env() {
  local c="$1"; shift
  local vars=()
  while [ $# -gt 0 ] && [ "$1" != -- ]; do vars+=("$1"); shift; done
  shift
  (cd "$c/project" && env -u CLAUDE_CONFIG_DIR -u CODEX_HOME -u RULE_BASE_URL HOME="$c/home" TMPDIR="$c/tmp" \
    "${vars[@]}" "$SH_UNDER_TEST" "$INSTALLER" "$@" >"$c/out" 2>"$c/err"; echo $? >"$c/rc")
}

# Pipes the installer into the shell, as `curl ... | sh -s -- <arguments>` does. The rule comes from RULE_BASE_URL.
run_remote() {
  local c="$1" base="$2"; shift 2
  (cd "$c/project" && env -u CLAUDE_CONFIG_DIR -u CODEX_HOME HOME="$c/home" TMPDIR="$c/tmp" RULE_BASE_URL="$base" \
    "$SH_UNDER_TEST" -s -- "$@" <"$INSTALLER" >"$c/out" 2>"$c/err"; echo $? >"$c/rc")
}

rc() { cat "$1/rc"; }

snap() {
  (cd "$1" && find . | LC_ALL=C sort | while IFS= read -r f; do
    if [ -L "$f" ]; then
      printf '%s -> %s\n' "$f" "$(readlink "$f")"
    elif [ -f "$f" ]; then
      printf '%s %s\n' "$f" "$(cksum <"$f")"
    else
      printf '%s\n' "$f"
    fi
  done)
}

backups() { # folder
  find "$1" -name '*.bak.*' | wc -l | tr -d ' '
}

# The block that the installer writes for the default rule.
expected_block() {
  printf '%s\n' "$START"
  cat "$RULE"
  printf '%s\n' "$END"
}

# --- usage ---

CASE=$(new_case usage)
run "$CASE"
check "no agent: exit 2" "$([ "$(rc "$CASE")" = 2 ]; echo $?)"
run "$CASE" --agent vim
check "unknown agent: exit 2" "$([ "$(rc "$CASE")" = 2 ]; echo $?)"
run "$CASE" --agent claude --rule ../x
check "rule name with a slash: exit 2" "$([ "$(rc "$CASE")" = 2 ]; echo $?)"
run "$CASE" --agent claude --rule .hidden
check "rule name with a leading dot: exit 2" "$([ "$(rc "$CASE")" = 2 ]; echo $?)"
run "$CASE" --print --agent claude
check "--print with --agent: exit 2" "$([ "$(rc "$CASE")" = 2 ]; echo $?)"
run "$CASE" --apply --print
check "--apply with --print: exit 2" "$([ "$(rc "$CASE")" = 2 ]; echo $?)"
run "$CASE" --agent claude --rule No-Such-Rule
check "missing rule in a clone: exit 1" "$([ "$(rc "$CASE")" = 1 ]; echo $?)"

# --- --print ---

CASE=$(new_case print)
run "$CASE" --print
check "--print: exit 0" "$([ "$(rc "$CASE")" = 0 ]; echo $?)"
check "--print: prints the rule" "$(cmp -s "$CASE/out" "$RULE"; echo $?)"

# --- dry run ---

CASE=$(new_case dry)
mkdir -p "$CASE/home/.claude" "$CASE/home/.codex" "$CASE/home/.gemini" "$CASE/home/.devin"
before=$(snap "$CASE/home")
run "$CASE" --agent all --agent agents
check "dry run: exit 0" "$([ "$(rc "$CASE")" = 0 ]; echo $?)"
check "dry run: changes nothing in home" "$([ "$before" = "$(snap "$CASE/home")" ]; echo $?)"
check "dry run: no project AGENTS.md" "$([ ! -e "$CASE/project/AGENTS.md" ]; echo $?)"
check "dry run: says create for claude" "$(grep -q "^create $CASE/home/.claude/rules/Clear-Writing.md (claude)$" "$CASE/out"; echo $?)"
check "dry run: says dry run" "$(grep -q '^dry run: nothing was changed' "$CASE/out"; echo $?)"

# --- claude ---

CASE=$(new_case claude)
mkdir -p "$CASE/home/.claude"
run "$CASE" --apply --agent claude
check "claude: exit 0" "$([ "$(rc "$CASE")" = 0 ]; echo $?)"
check "claude: writes the rule file" "$(cmp -s "$CASE/home/.claude/rules/Clear-Writing.md" <(expected_block); echo $?)"
run "$CASE" --apply --agent claude
check "claude: second run says unchanged" "$(grep -q '^unchanged ' "$CASE/out"; echo $?)"
check "claude: second run makes no backup" "$([ "$(backups "$CASE/home")" = 0 ]; echo $?)"
printf 'my edit\n' >>"$CASE/home/.claude/rules/Clear-Writing.md"
run "$CASE" --agent claude
check "claude: dry run says outdated" "$(grep -q '^outdated ' "$CASE/out"; echo $?)"
check "claude: dry run shows a diff" "$(grep -q '^-my edit$' "$CASE/out"; echo $?)"
run "$CASE" --apply --agent claude
check "claude: outdated file is replaced" "$(cmp -s "$CASE/home/.claude/rules/Clear-Writing.md" <(expected_block); echo $?)"
check "claude: outdated file is backed up" "$([ "$(backups "$CASE/home")" = 1 ]; echo $?)"

CASE=$(new_case claude-config-dir)
mkdir -p "$CASE/other"
run_env "$CASE" CLAUDE_CONFIG_DIR="$CASE/other" -- --apply --agent claude
check "claude: uses CLAUDE_CONFIG_DIR" "$(cmp -s "$CASE/other/rules/Clear-Writing.md" <(expected_block); echo $?)"

CASE=$(new_case claude-conflict)
mkdir -p "$CASE/home/.claude/rules"
printf '# My own rule\n' >"$CASE/home/.claude/rules/Clear-Writing.md"
before=$(snap "$CASE/home")
run "$CASE" --apply --agent claude
check "claude: a different file with the same name, exit 1" "$([ "$(rc "$CASE")" = 1 ]; echo $?)"
check "claude: a different file with the same name, says conflict" "$(grep -q '^conflict ' "$CASE/out"; echo $?)"
check "claude: a different file with the same name, file unchanged" "$([ "$before" = "$(snap "$CASE/home")" ]; echo $?)"
run "$CASE" --agent claude
check "claude: a different file with the same name, dry run says conflict" "$(grep -q '^conflict ' "$CASE/out"; echo $?)"
run "$CASE" --apply --force --agent claude
check "claude: --force, exit 0" "$([ "$(rc "$CASE")" = 0 ]; echo $?)"
check "claude: --force replaces the file" "$(cmp -s "$CASE/home/.claude/rules/Clear-Writing.md" <(expected_block); echo $?)"
check "claude: --force backs up the old file" "$(cat "$CASE/home/.claude/rules/Clear-Writing.md.bak."* | grep -qx '# My own rule'; echo $?)"

CASE=$(new_case claude-hand-copy)
mkdir -p "$CASE/home/.claude/rules"
cp "$RULE" "$CASE/home/.claude/rules/Clear-Writing.md"
run "$CASE" --apply --agent claude
check "claude: a copy of the rule without markers is updated" "$(cmp -s "$CASE/home/.claude/rules/Clear-Writing.md" <(expected_block); echo $?)"

CASE=$(new_case claude-missing)
run "$CASE" --apply --agent claude
check "claude: no config folder, skip" "$(grep -q '^skip claude ' "$CASE/out"; echo $?)"
check "claude: no config folder, nothing created" "$([ ! -e "$CASE/home/.claude" ]; echo $?)"

# --- codex (block) ---

CASE=$(new_case codex)
mkdir -p "$CASE/home/.codex"
printf 'line 1\nline 2' >"$CASE/home/.codex/AGENTS.md"
run "$CASE" --apply --agent chatgpt
check "codex: alias chatgpt, exit 0" "$([ "$(rc "$CASE")" = 0 ]; echo $?)"
{ printf 'line 1\nline 2\n\n'; expected_block; } >"$CASE/expected"
check "codex: keeps the content and adds the block after an empty line" "$(cmp -s "$CASE/home/.codex/AGENTS.md" "$CASE/expected"; echo $?)"
check "codex: backs up the file" "$([ "$(backups "$CASE/home")" = 1 ]; echo $?)"
# Change the rule inside the block and add content after it.
sed -i.tmp 's/^# Clear Writing$/# Old Title/' "$CASE/home/.codex/AGENTS.md" && rm -f "$CASE/home/.codex/AGENTS.md.tmp"
printf 'after\n' >>"$CASE/home/.codex/AGENTS.md"
run "$CASE" --agent codex
check "codex: dry run says outdated" "$(grep -q "^outdated $CASE/home/.codex/AGENTS.md (codex)$" "$CASE/out"; echo $?)"
run "$CASE" --apply --agent codex
{ printf 'line 1\nline 2\n\n'; expected_block; printf 'after\n'; } >"$CASE/expected"
check "codex: replaces only the block" "$(cmp -s "$CASE/home/.codex/AGENTS.md" "$CASE/expected"; echo $?)"

CASE=$(new_case codex-home)
mkdir -p "$CASE/codex"
run_env "$CASE" CODEX_HOME="$CASE/codex" -- --apply --agent codex
expected_block >"$CASE/expected"
check "codex: uses CODEX_HOME, new file is the block" "$(cmp -s "$CASE/codex/AGENTS.md" "$CASE/expected"; echo $?)"

CASE=$(new_case codex-override)
mkdir -p "$CASE/home/.codex"
printf 'main\n' >"$CASE/home/.codex/AGENTS.md"
printf 'override\n' >"$CASE/home/.codex/AGENTS.override.md"
run "$CASE" --apply --agent codex
{ printf 'override\n\n'; expected_block; } >"$CASE/expected"
check "codex: AGENTS.override.md gets the block" "$(cmp -s "$CASE/home/.codex/AGENTS.override.md" "$CASE/expected"; echo $?)"
check "codex: AGENTS.md is unchanged when AGENTS.override.md exists" "$([ "$(cat "$CASE/home/.codex/AGENTS.md")" = main ]; echo $?)"

CASE=$(new_case codex-broken)
mkdir -p "$CASE/home/.codex"
printf '%s\nx\n' "$START" >"$CASE/home/.codex/AGENTS.md"
before=$(snap "$CASE/home")
run "$CASE" --apply --agent codex
check "codex: broken markers, exit 1" "$([ "$(rc "$CASE")" = 1 ]; echo $?)"
check "codex: broken markers, file unchanged" "$([ "$before" = "$(snap "$CASE/home")" ]; echo $?)"

CASE=$(new_case codex-symlink)
mkdir -p "$CASE/home/.codex" "$CASE/dotfiles"
printf 'mine\n' >"$CASE/dotfiles/AGENTS.md"
ln -s "$CASE/dotfiles/AGENTS.md" "$CASE/home/.codex/AGENTS.md"
run "$CASE" --apply --agent codex
check "codex: symbolic link stays a link" "$([ -L "$CASE/home/.codex/AGENTS.md" ]; echo $?)"
check "codex: the link target gets the block" "$(grep -qxF "$START" "$CASE/dotfiles/AGENTS.md"; echo $?)"

# --- antigravity ---

CASE=$(new_case antigravity)
mkdir -p "$CASE/home/.gemini"
run "$CASE" --apply --agent gemini
expected_block >"$CASE/expected"
check "antigravity: alias gemini writes ~/.gemini/GEMINI.md" "$(cmp -s "$CASE/home/.gemini/GEMINI.md" "$CASE/expected"; echo $?)"

# --- windsurf ---

CASE=$(new_case devin)
mkdir -p "$CASE/home/.devin"
run "$CASE" --apply --agent windsurf
f="$CASE/home/.devin/rules/Clear-Writing.md"
check "devin: writes ~/.devin/rules/Clear-Writing.md" "$([ -f "$f" ]; echo $?)"
check "devin: front matter has trigger always_on" "$([ "$(sed -n '1,3p' "$f")" = $'---\ntrigger: always_on\ndescription: "Clear Writing"' ]; echo $?)"
check "devin: the rule follows the front matter" "$(tail -n +6 "$f" | cmp -s - <(expected_block); echo $?)"
check "devin: no old Windsurf folder, nothing created" "$([ ! -e "$CASE/home/.codeium" ]; echo $?)"

CASE=$(new_case devin-conflict)
mkdir -p "$CASE/home/.devin/rules"
printf -- '---\ntrigger: manual\n---\n\nmine\n' >"$CASE/home/.devin/rules/Clear-Writing.md"
before=$(snap "$CASE/home")
run "$CASE" --apply --agent devin
check "devin: a different file with the same name, says conflict" "$(grep -q '^conflict ' "$CASE/out"; echo $?)"
check "devin: a different file with the same name, file unchanged" "$([ "$before" = "$(snap "$CASE/home")" ]; echo $?)"

CASE=$(new_case windsurf-too-long)
mkdir -p "$CASE/home/.codeium/windsurf/memories"
printf 'mine\n' >"$CASE/home/.codeium/windsurf/memories/global_rules.md"
before=$(snap "$CASE/home")
run "$CASE" --apply --agent devin
check "windsurf: too long, exit 0" "$([ "$(rc "$CASE")" = 0 ]; echo $?)"
check "windsurf: too long, says too-long" "$(grep -q '^too-long ' "$CASE/out"; echo $?)"
check "windsurf: too long, file unchanged" "$([ "$before" = "$(snap "$CASE/home")" ]; echo $?)"

CASE=$(new_case windsurf-short)
mkdir -p "$CASE/home/.codeium/windsurf/memories" "$CASE/rules"
printf '# Short\n\n- Be short.\n' >"$CASE/rules/Short.md"
if command -v curl >/dev/null 2>&1; then
  run_remote "$CASE" "file://$CASE/rules" --apply --agent windsurf --rule Short
  check "windsurf: short rule, adds the block" "$(grep -qxF '<!-- rule:Short:start -->' "$CASE/home/.codeium/windsurf/memories/global_rules.md"; echo $?)"
else
  skip "windsurf: short rule, adds the block" "no curl"
fi

CASE=$(new_case windsurf-missing)
run "$CASE" --apply --agent windsurf
check "windsurf: no folders, skip" "$(grep -q '^skip windsurf ' "$CASE/out"; echo $?)"

# --- cursor ---

CASE=$(new_case cursor)
mkdir -p "$CASE/home/.cursor"
before=$(snap "$CASE/home")
run "$CASE" --apply --agent cursor
check "cursor: exit 0" "$([ "$(rc "$CASE")" = 0 ]; echo $?)"
check "cursor: tells the user to paste the rule" "$(grep -q 'User Rules' "$CASE/out"; echo $?)"
check "cursor: changes nothing" "$([ "$before" = "$(snap "$CASE/home")" ]; echo $?)"

# --- agents (project AGENTS.md) ---

CASE=$(new_case agents-git)
git -C "$CASE/project" init -q
mkdir -p "$CASE/project/sub/dir"
(cd "$CASE/project/sub/dir" && env -u CLAUDE_CONFIG_DIR -u CODEX_HOME HOME="$CASE/home" TMPDIR="$CASE/tmp" \
  "$SH_UNDER_TEST" "$INSTALLER" --apply --agent agents >"$CASE/out" 2>"$CASE/err"; echo $? >"$CASE/rc")
expected_block >"$CASE/expected"
check "agents: default is the Git root" "$(cmp -s "$CASE/project/AGENTS.md" "$CASE/expected"; echo $?)"
check "agents: nothing in the subfolder" "$([ ! -e "$CASE/project/sub/dir/AGENTS.md" ]; echo $?)"

CASE=$(new_case agents-project)
mkdir -p "$CASE/other"
run "$CASE" --apply --agent agents --project "$CASE/other"
check "agents: --project writes there" "$(cmp -s "$CASE/other/AGENTS.md" <(expected_block); echo $?)"
run "$CASE" --apply --agent agents --project "$CASE/none"
check "agents: missing --project folder, exit 2" "$([ "$(rc "$CASE")" = 2 ]; echo $?)"

CASE=$(new_case all-no-project)
mkdir -p "$CASE/home/.claude"
run "$CASE" --apply --agent all
check "all: does not write the project AGENTS.md" "$([ ! -e "$CASE/project/AGENTS.md" ]; echo $?)"

# --- remote (curl | sh) ---

if command -v curl >/dev/null 2>&1; then
  CASE=$(new_case remote)
  mkdir -p "$CASE/home/.claude"
  run_remote "$CASE" "file://$RULES" --apply --agent claude
  check "remote: exit 0" "$([ "$(rc "$CASE")" = 0 ]; echo $?)"
  check "remote: downloads the rule" "$(cmp -s "$CASE/home/.claude/rules/Clear-Writing.md" <(expected_block); echo $?)"
  check "remote: says where the rule came from" "$(grep -qF "rule: file://$RULES/Clear-Writing.md" "$CASE/out"; echo $?)"
  run_remote "$CASE" "file://$CASE/nothing" --apply --agent claude
  check "remote: failed download, exit 1" "$([ "$(rc "$CASE")" = 1 ]; echo $?)"
else
  skip "remote" "no curl"
fi

CASE=""
echo
echo "passed: $PASSES, failed: $FAILS, skipped: $SKIPS"
if [ "$FAILS" -gt 0 ] || [ -n "${KEEP_TEST_DIR:-}" ]; then
  echo "test folder: $WORK"
else
  rm -rf -- "$WORK"
fi
[ "$FAILS" -eq 0 ]
