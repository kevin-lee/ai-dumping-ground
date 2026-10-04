#!/bin/bash
# Runs setup-statusline.sh against throwaway config folders and checks the results. It never touches the real Claude Code config.
#
# Usage:
#   bash scripts/config/claude/test-setup-statusline.sh
#
# Environment variables:
#   BASH_UNDER_TEST  bash used to run the installer (default: /bin/bash)
#   KEEP_TEST_DIR=1  keep the work folder even when every check passes

# shellcheck disable=SC2319 # each check receives the status of the condition written right before it
set -u

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
INSTALLER="$HERE/setup-statusline.sh"
SOURCE="$HERE/statusline-command.sh"
BASH_UNDER_TEST="${BASH_UNDER_TEST:-/bin/bash}"
SOURCE_URL="https://raw.githubusercontent.com/kevin-lee/ai-dumping-ground/main/scripts/config/claude/statusline-command.sh"

DEFAULT_CMD="bash ~/.claude/statusline-command.sh"
ENV_CMD="bash \"\$CLAUDE_CONFIG_DIR/statusline-command.sh\""
DEFAULT_SETTINGS='{"statusLine":{"type":"command","command":"bash ~/.claude/statusline-command.sh"}}'

WORK=$(mktemp -d "${TMPDIR:-/tmp}/test-setup-statusline.XXXXXX") || exit 1
PASSES=0
FAILS=0
SKIPS=0
# The case folder whose out and err are printed when a check fails.
CASE=""

check() { # name, status
  if [ "$2" -eq 0 ]; then
    echo "PASS $1"
    PASSES=$((PASSES + 1))
  else
    echo "FAIL $1"
    FAILS=$((FAILS + 1))
    if [ -n "$CASE" ]; then
      echo "  --- out ---"; cat "$CASE/out" 2>/dev/null
      echo "  --- err ---"; cat "$CASE/err" 2>/dev/null
    fi
  fi
}

skip() { # name, reason
  echo "SKIP $1 ($2)"
  SKIPS=$((SKIPS + 1))
}

new_case() {
  local c="$WORK/$1"
  mkdir -p "$c/home" "$c/tmp" "$c/bin"
  printf '%s\n' "$c"
}

# Extra VAR=value arguments come after the defaults, so a case can replace PATH completely.
run() {
  local c="$1"; shift
  (cd "$c" && env -u CLAUDE_CONFIG_DIR HOME="$c/home" TMPDIR="$c/tmp" PATH="$c/bin:$PATH" ${1+"$@"} \
    "$BASH_UNDER_TEST" "$INSTALLER" >"$c/out" 2>"$c/err"; echo $? >"$c/rc")
}

# Pipes the installer into bash, as `curl ... | bash` does.
run_remote() {
  local c="$1"; shift
  (cd "$c" && cat "$INSTALLER" | env -u CLAUDE_CONFIG_DIR HOME="$c/home" TMPDIR="$c/tmp" PATH="$c/bin:$PATH" ${1+"$@"} \
    "$BASH_UNDER_TEST" >"$c/out" 2>"$c/err"; echo $? >"$c/rc")
}

rc() { cat "$1/rc"; }

# shellcheck disable=SC2012 # ls -ld on one path, only the permission column is used
snap() {
  (cd "$1" && find . | LC_ALL=C sort | while IFS= read -r f; do
    if [ -L "$f" ]; then
      printf '%s -> %s\n' "$f" "$(readlink "$f")"
    elif [ -f "$f" ]; then
      printf '%s %s %s\n' "$f" "$(cksum < "$f")" "$(ls -ld "$f" | cut -c1-10)"
    else
      printf '%s %s\n' "$f" "$(ls -ld "$f" | cut -c1-10)"
    fi
  done)
}

mode_is() { [ -n "$(find "$1" -prune -perm "$2" 2>/dev/null)" ]; }

no_backups() { [ -z "$(find "$1" -name '*.bak.*')" ]; }

only_entry() { # folder, the one name it must contain
  [ "$(find "$1" -mindepth 1)" = "$1/$2" ]
}

fake_cmd() { # case, name, shell body
  printf '#!/bin/sh\n%s\n' "$3" > "$1/bin/$2"
  chmod 755 "$1/bin/$2"
}

fake_curl() { # case, ok|fail|html
  local c="$1" action body
  case "$2" in
    ok) action="cp '$SOURCE' \"\$out\"" ;;
    html) action="echo '<html>Not Found</html>' > \"\$out\"" ;;
    *) action="echo 'curl: (22) The requested URL returned error: 404' >&2; exit 22" ;;
  esac
  body=$(cat <<EOF
printf '%s\n' "\$*" > '$c/curl-args'
out=""
while [ \$# -gt 0 ]; do
  if [ "\$1" = "-o" ]; then out="\$2"; fi
  shift
done
$action
EOF
)
  fake_cmd "$c" curl "$body"
}

# Checksums of the real config files, to prove they are never touched.
fingerprint() {
  local d f
  for d in "$HOME/.claude" ${CLAUDE_CONFIG_DIR:+"$CLAUDE_CONFIG_DIR"}; do
    for f in settings.json statusline-command.sh; do
      if [ -e "$d/$f" ]; then
        printf '%s %s\n' "$d/$f" "$(cksum < "$d/$f")"
      else
        printf '%s missing\n' "$d/$f"
      fi
    done
  done
}

echo "OS:   $(uname -s)"
echo "bash: $("$BASH_UNDER_TEST" --version | head -n 1)"
echo "jq:   $(jq --version 2>&1)"
echo "uid:  $(id -u)"
echo "---"

REAL_BEFORE=$(fingerprint)

# T1 fresh HOME
CASE=$(new_case t1); H="$CASE/home/.claude"
run "$CASE"
[ "$(rc "$CASE")" = 0 ] && [ -d "$H" ] && cmp -s "$SOURCE" "$H/statusline-command.sh" \
  && mode_is "$H/statusline-command.sh" 644 && mode_is "$H/settings.json" 600 \
  && [ "$(jq -c . "$H/settings.json")" = "$DEFAULT_SETTINGS" ] && no_backups "$H"
check "T1 fresh install" $?

# T2 rerun of T1
before=$(snap "$CASE/home")
run "$CASE"
[ "$(rc "$CASE")" = 0 ] && grep -q "No difference found" "$CASE/out" && [ "$(snap "$CASE/home")" = "$before" ] && no_backups "$H"
check "T2 rerun skips" $?

# T3 other keys, extra statusLine fields and mode 644 are kept
CASE=$(new_case t3); H="$CASE/home/.claude"; mkdir -p "$H"; cp "$SOURCE" "$H/statusline-command.sh"
echo '{"theme":"dark","statusLine":{"padding":2,"type":"command","command":"bash /abs/.claude/statusline-command.sh","refreshInterval":5},"env":{"A":"1"},"zzz":[1,2]}' \
  | jq . > "$H/settings.json"
chmod 644 "$H/settings.json"; cp "$H/settings.json" "$CASE/original.json"
run "$CASE"
baks=$(find "$H" -name 'settings.json.bak.*')
[ "$(rc "$CASE")" = 0 ] && [ "$(printf '%s\n' "$baks" | grep -c .)" = 1 ] && cmp -s "$baks" "$CASE/original.json" \
  && [ "$(jq -c 'del(.statusLine.command)' "$H/settings.json")" = "$(jq -c 'del(.statusLine.command)' "$CASE/original.json")" ] \
  && [ "$(jq -r '.statusLine.command' "$H/settings.json")" = "$DEFAULT_CMD" ] \
  && [ "$(jq -c '[keys_unsorted, (.statusLine | keys_unsorted)]' "$H/settings.json")" = "$(jq -c '[keys_unsorted, (.statusLine | keys_unsorted)]' "$CASE/original.json")" ] \
  && mode_is "$H/settings.json" 644 && [ -z "$(find "$H" -name 'statusline-command.sh.bak.*')" ]
check "T3 merge keeps other keys, order and mode" $?

# T4 only the script differs
CASE=$(new_case t4); H="$CASE/home/.claude"; mkdir -p "$H"
{ cat "$SOURCE"; echo "# local change"; } > "$H/statusline-command.sh"; cp "$H/statusline-command.sh" "$CASE/modified.sh"
printf '%s\n' "$DEFAULT_SETTINGS" > "$H/settings.json"; settings_before=$(cksum < "$H/settings.json")
run "$CASE"
b=$(find "$H" -name 'statusline-command.sh.bak.*')
[ "$(rc "$CASE")" = 0 ] && [ -n "$b" ] && cmp -s "$b" "$CASE/modified.sh" && cmp -s "$SOURCE" "$H/statusline-command.sh" \
  && [ "$(cksum < "$H/settings.json")" = "$settings_before" ] && [ -z "$(find "$H" -name 'settings.json.bak.*')" ]
check "T4 only script updated" $?

# T5 settings.json is a relative symlink
CASE=$(new_case t5); H="$CASE/home/.claude"; mkdir -p "$H" "$CASE/dotfiles"
echo '{"theme":"light"}' > "$CASE/dotfiles/settings.json"; ln -s ../../dotfiles/settings.json "$H/settings.json"
run "$CASE"
b=$(find "$H" -name 'settings.json.bak.*')
[ "$(rc "$CASE")" = 0 ] && [ -L "$H/settings.json" ] && [ "$(readlink "$H/settings.json")" = "../../dotfiles/settings.json" ] \
  && [ "$(jq -c . "$CASE/dotfiles/settings.json")" = '{"theme":"light","statusLine":{"type":"command","command":"bash ~/.claude/statusline-command.sh"}}' ] \
  && [ -n "$b" ] && [ ! -L "$b" ] && [ -f "$b" ] && [ "$(jq -c . "$b")" = '{"theme":"light"}' ] \
  && only_entry "$CASE/dotfiles" settings.json
check "T5 settings symlink kept, written through" $?

# T6 dangling settings.json symlink
CASE=$(new_case t6); H="$CASE/home/.claude"; mkdir -p "$H"; ln -s ../nowhere.json "$H/settings.json"
before=$(snap "$CASE/home")
run "$CASE"
[ "$(rc "$CASE")" = 1 ] && [ "$(snap "$CASE/home")" = "$before" ] && grep -q "which does not exist" "$CASE/err"
check "T6 dangling symlink stops" $?

# T7 empty and T7b whitespace-only settings.json
for kind in empty ws; do
  CASE=$(new_case "t7-$kind"); H="$CASE/home/.claude"; mkdir -p "$H"
  if [ "$kind" = empty ]; then : > "$H/settings.json"; else printf '  \n\t\n' > "$H/settings.json"; fi
  cp "$H/settings.json" "$CASE/original.json"; chmod 640 "$H/settings.json"
  run "$CASE"
  b=$(find "$H" -name 'settings.json.bak.*')
  [ "$(rc "$CASE")" = 0 ] && [ "$(jq -c . "$H/settings.json")" = "$DEFAULT_SETTINGS" ] && [ -n "$b" ] && cmp -s "$b" "$CASE/original.json" \
    && mode_is "$H/settings.json" 640
  check "T7 $kind settings treated as {}" $?
done

# T8, T9, T9b, T10 content that settings.json must not have
for spec in 'T8|{"a":1,}|is not valid JSON' 'T9|[]|must contain a single JSON object' \
  'T9b|{}{}|must contain a single JSON object' 'T10|{"statusLine":"x"}|is not an object'; do
  name=${spec%%|*}; rest=${spec#*|}; content=${rest%%|*}; msg=${rest#*|}
  CASE=$(new_case "$name"); H="$CASE/home/.claude"; mkdir -p "$H"; printf '%s\n' "$content" > "$H/settings.json"
  before=$(snap "$CASE/home")
  run "$CASE"
  [ "$(rc "$CASE")" = 1 ] && [ "$(snap "$CASE/home")" = "$before" ] && grep -q "$msg" "$CASE/err" \
    && grep -q -F "$H/settings.json" "$CASE/err" && [ ! -e "$H/statusline-command.sh" ]
  check "$name '$content' stops, nothing changed" $?
done

# T11 "statusLine": null
CASE=$(new_case t11); H="$CASE/home/.claude"; mkdir -p "$H"; echo '{"statusLine":null}' > "$H/settings.json"
run "$CASE"
[ "$(rc "$CASE")" = 0 ] && [ "$(jq -c . "$H/settings.json")" = "$DEFAULT_SETTINGS" ]
check "T11 null statusLine replaced" $?

# T12 CLAUDE_CONFIG_DIR with a space, and the written command renders a status line
CASE=$(new_case t12); D="$CASE/custom dir"
run "$CASE" CLAUDE_CONFIG_DIR="$D"
cmd=$(jq -r '.statusLine.command' "$D/settings.json" 2>/dev/null)
echo '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"/tmp/x"},"cost":{"total_cost_usd":0.12,"total_duration_ms":65000},"context_window":{"used_percentage":42,"total_input_tokens":1000,"total_output_tokens":200,"context_window_size":200000},"effort":{"level":"high"}}' \
  > "$CASE/sample.json"
line=""
if [ "$cmd" = "$ENV_CMD" ]; then
  line=$(cd "$CASE" && HOME="$CASE/home" CLAUDE_CONFIG_DIR="$D" sh -c "$cmd" < "$CASE/sample.json" 2>&1)
fi
[ "$(rc "$CASE")" = 0 ] && cmp -s "$SOURCE" "$D/statusline-command.sh" && [ "$cmd" = "$ENV_CMD" ] \
  && mode_is "$D/settings.json" 600 && [ ! -e "$CASE/home/.claude" ] && printf '%s\n' "$line" | grep -q "Opus"
check "T12 CLAUDE_CONFIG_DIR with a space uses literal \$CLAUDE_CONFIG_DIR and renders" $?

# T13 CLAUDE_CONFIG_DIR equal to ~/.claude with a trailing slash
CASE=$(new_case t13)
run "$CASE" CLAUDE_CONFIG_DIR="$CASE/home/.claude/"
[ "$(rc "$CASE")" = 0 ] && [ "$(jq -r '.statusLine.command' "$CASE/home/.claude/settings.json")" = "$DEFAULT_CMD" ]
check "T13 CLAUDE_CONFIG_DIR=\$HOME/.claude/ uses the ~ form" $?

# T14 CLAUDE_CONFIG_DIR with a literal ~
CASE=$(new_case t14)
run "$CASE" CLAUDE_CONFIG_DIR='~/alt'
[ "$(rc "$CASE")" = 1 ] && grep -q "must be an absolute path" "$CASE/err" && [ ! -e "$CASE/~" ] \
  && [ -z "$(find "$CASE/home" -mindepth 1)" ]
check "T14 relative CLAUDE_CONFIG_DIR stops" $?

# T15 remote mode with a fake curl
CASE=$(new_case t15); H="$CASE/home/.claude"; fake_curl "$CASE" ok
run_remote "$CASE"
[ "$(rc "$CASE")" = 0 ] && cmp -s "$SOURCE" "$H/statusline-command.sh" \
  && [ "$(jq -c . "$H/settings.json")" = "$DEFAULT_SETTINGS" ] && grep -q -F "$SOURCE_URL" "$CASE/curl-args"
check "T15 remote mode installs the downloaded script" $?

# T15b download fails
CASE=$(new_case t15b); fake_curl "$CASE" fail
before=$(snap "$CASE/home")
run_remote "$CASE"
[ "$(rc "$CASE")" = 1 ] && grep -q "failed to download" "$CASE/err" && [ "$(snap "$CASE/home")" = "$before" ]
check "T15b remote download failure changes nothing" $?

# T15c download is not a shell script
CASE=$(new_case t15c); fake_curl "$CASE" html
before=$(snap "$CASE/home")
run_remote "$CASE"
[ "$(rc "$CASE")" = 1 ] && grep -q "not a shell script" "$CASE/err" && [ "$(snap "$CASE/home")" = "$before" ]
check "T15c remote non-script download changes nothing" $?

# T17 statusline-command.sh is a relative symlink
CASE=$(new_case t17); H="$CASE/home/.claude"; mkdir -p "$H" "$CASE/dotfiles"
{ cat "$SOURCE"; echo "# local change"; } > "$CASE/dotfiles/statusline-command.sh"
cp "$CASE/dotfiles/statusline-command.sh" "$CASE/old.sh"
ln -s ../../dotfiles/statusline-command.sh "$H/statusline-command.sh"
printf '%s\n' "$DEFAULT_SETTINGS" > "$H/settings.json"
run "$CASE"
b=$(find "$H" -name 'statusline-command.sh.bak.*')
[ "$(rc "$CASE")" = 0 ] && [ -L "$H/statusline-command.sh" ] \
  && [ "$(readlink "$H/statusline-command.sh")" = "../../dotfiles/statusline-command.sh" ] \
  && cmp -s "$SOURCE" "$CASE/dotfiles/statusline-command.sh" && [ -n "$b" ] && [ ! -L "$b" ] && [ -f "$b" ] \
  && cmp -s "$b" "$CASE/old.sh" && only_entry "$CASE/dotfiles" statusline-command.sh
check "T17 script symlink kept, written through" $?

# T18 settings.json is a symlink to itself
CASE=$(new_case t18); H="$CASE/home/.claude"; mkdir -p "$H"; ln -s settings.json "$H/settings.json"
before=$(snap "$CASE/home")
run "$CASE"
[ "$(rc "$CASE")" = 1 ] && grep -q "too many levels of symlinks" "$CASE/err" && [ "$(snap "$CASE/home")" = "$before" ]
check "T18 symlink loop stops" $?

# T19 settings.json is a folder
CASE=$(new_case t19); H="$CASE/home/.claude"; mkdir -p "$H/settings.json"
before=$(snap "$CASE/home")
run "$CASE"
[ "$(rc "$CASE")" = 1 ] && grep -q "is not a regular file" "$CASE/err" && [ "$(snap "$CASE/home")" = "$before" ]
check "T19 folder instead of settings.json stops" $?

# T20 the backup name is already taken
CASE=$(new_case t20); H="$CASE/home/.claude"; mkdir -p "$H"
fake_cmd "$CASE" date 'echo 20000101-000000'
echo '{"theme":"dark"}' > "$H/settings.json"; echo 'old backup' > "$H/settings.json.bak.20000101-000000"
before=$(snap "$CASE/home")
run "$CASE"
[ "$(rc "$CASE")" = 1 ] && grep -q "backup file already exists" "$CASE/err" && [ "$(snap "$CASE/home")" = "$before" ] \
  && [ ! -e "$H/statusline-command.sh" ]
check "T20 taken backup name stops before any write" $?

# T21 jq missing
CASE=$(new_case t21); mkdir -p "$CASE/nobin"
run "$CASE" PATH="$CASE/nobin"
[ "$(rc "$CASE")" = 1 ] && grep -q "jq is required" "$CASE/err" && [ ! -e "$CASE/home/.claude" ]
check "T21 missing jq stops" $?

# T22 curl missing in remote mode
CASE=$(new_case t22)
for tool in jq mktemp dirname basename tr rm cat head cmp date mkdir cp mv chmod readlink; do
  ln -s "$(command -v "$tool")" "$CASE/bin/$tool"
done
before=$(snap "$CASE/home")
run_remote "$CASE" PATH="$CASE/bin"
[ "$(rc "$CASE")" = 1 ] && grep -q "curl is required" "$CASE/err" && [ "$(snap "$CASE/home")" = "$before" ]
check "T22 missing curl in remote mode stops" $?

# T23 config folder that cannot be written to
if [ "$(id -u)" = 0 ]; then
  skip "T23 unwritable config folder" "root ignores folder permissions"
else
  CASE=$(new_case t23); H="$CASE/home/.claude"; mkdir -p "$H"; echo '{"theme":"dark"}' > "$H/settings.json"
  chmod 555 "$H"
  before=$(snap "$CASE/home")
  run "$CASE"
  after=$(snap "$CASE/home")
  chmod 755 "$H"
  [ "$(rc "$CASE")" != 0 ] && [ "$after" = "$before" ]
  check "T23 unwritable config folder changes nothing" $?
fi

# T24 the final rename fails
CASE=$(new_case t24); H="$CASE/home/.claude"; mkdir -p "$H"; cp "$SOURCE" "$H/statusline-command.sh"
echo '{"theme":"dark"}' > "$H/settings.json"; cp "$H/settings.json" "$CASE/original.json"
fake_cmd "$CASE" mv 'exit 1'
run "$CASE"
baks=$(find "$H" -name 'settings.json.bak.*')
[ "$(rc "$CASE")" != 0 ] && cmp -s "$H/settings.json" "$CASE/original.json" \
  && [ "$(printf '%s\n' "$baks" | grep -c .)" = 1 ] && cmp -s "$baks" "$CASE/original.json" \
  && [ -z "$(find "$H" -name '.settings.json.*')" ]
check "T24 failed rename keeps the original and leaves no temp file" $?

CASE=""

leftover=""
for d in "$WORK"/*/tmp; do
  if [ -n "$(find "$d" -mindepth 1)" ]; then leftover="$leftover $d"; fi
done
[ -z "$leftover" ]
check "no installer temp folders left behind" $?

[ -z "$(find "$WORK" \( -name '.settings.json.*' -o -name '.statusline-command.sh.*' \))" ]
check "no temp files left next to targets" $?

# T16 real config unchanged
[ "$(fingerprint)" = "$REAL_BEFORE" ]
check "T16 real config unchanged" $?

echo "---"
echo "PASS: $PASSES  FAIL: $FAILS  SKIP: $SKIPS"
if [ "$FAILS" -eq 0 ] && [ "${KEEP_TEST_DIR:-}" != 1 ]; then
  rm -rf "$WORK"
else
  echo "Test files kept in $WORK"
fi
if [ "$FAILS" -gt 0 ]; then exit 1; fi
