#!/bin/bash
# Runs test-ai-output-scripts.sh in Linux containers: Debian 12 and Debian 13 (dash as /bin/sh) and Alpine (BusyBox) by default.
#
# Usage:
#   bash scripts/skills/test-ai-output-scripts-linux.sh [image ...]
#
# Uses $CONTAINER_CLI if set, otherwise podman, otherwise docker. Needs network access to pull images and packages.
#
# Environment variables:
#   NO_COLOR=1     no color, even in a terminal
#   FORCE_COLOR=1  color, even in a pipe or a file (NO_COLOR wins over it)
#
# Maintainers: see docs/ai-output-folder-maintenance.md.

set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)

# Color only for a terminal. NO_COLOR turns it off, FORCE_COLOR turns it on for a pipe or a file.
use_color() { # file descriptor
  [ -z "${NO_COLOR:-}" ] && { [ -n "${FORCE_COLOR:-}" ] || [ -t "$1" ]; }
}
if use_color 1; then
  GREEN=$(printf '\033[32m'); RED=$(printf '\033[31m'); CYAN=$(printf '\033[36m')
  BOLD=$(printf '\033[1m'); DIM=$(printf '\033[2m'); RESET=$(printf '\033[0m')
  # The container has no terminal, so the test inside it needs FORCE_COLOR.
  COLOR_ENV=(-e FORCE_COLOR=1)
else
  GREEN=""; RED=""; CYAN=""; BOLD=""; DIM=""; RESET=""
  COLOR_ENV=(-e NO_COLOR=1)
fi
if use_color 2; then
  ERR_RED=$(printf '\033[31m'); ERR_RESET=$(printf '\033[0m')
else
  ERR_RED=""; ERR_RESET=""
fi

if [ -n "${CONTAINER_CLI:-}" ]; then
  CLI="$CONTAINER_CLI"
elif command -v podman >/dev/null 2>&1; then
  CLI=podman
elif command -v docker >/dev/null 2>&1; then
  CLI=docker
else
  echo "${ERR_RED}error: podman or docker is required${ERR_RESET}" >&2
  exit 1
fi

if [ "$#" -eq 0 ]; then
  set -- debian:bookworm-slim debian:trixie-slim alpine:latest
fi

# The repository root is mounted, because the test compares the script copies in the three skills.
INNER='if command -v apt-get >/dev/null 2>&1; then
  apt-get update -qq && apt-get install -y -qq git >/dev/null
else
  apk add --no-cache -q bash git
fi
SH_UNDER_TEST=/bin/sh bash /src/scripts/skills/test-ai-output-scripts.sh'

RESULTS=""
FAILED=0
for image in "$@"; do
  echo "${BOLD}${CYAN}=== $image ===${RESET}"
  if "$CLI" run --rm "${COLOR_ENV[@]}" -v "$REPO:/src:ro" "$image" sh -c "$INNER"; then
    RESULTS="${RESULTS}${GREEN}PASS${RESET} $image
"
  else
    RESULTS="${RESULTS}${BOLD}${RED}FAIL${RESET} $image
"
    FAILED=1
  fi
done

echo "${DIM}---${RESET}"
printf '%s' "$RESULTS"
exit "$FAILED"
