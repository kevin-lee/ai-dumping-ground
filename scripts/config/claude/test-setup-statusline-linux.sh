#!/bin/bash
# Runs test-setup-statusline.sh in Linux containers: Debian 12 (jq 1.6), Debian 13 (jq 1.7.1) and Alpine (BusyBox) by default.
#
# Usage:
#   bash scripts/config/claude/test-setup-statusline-linux.sh [image ...]
#
# Uses $CONTAINER_CLI if set, otherwise podman, otherwise docker. Needs network access to pull images and packages.

set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

if [ -n "${CONTAINER_CLI:-}" ]; then
  CLI="$CONTAINER_CLI"
elif command -v podman >/dev/null 2>&1; then
  CLI=podman
elif command -v docker >/dev/null 2>&1; then
  CLI=docker
else
  echo "error: podman or docker is required" >&2
  exit 1
fi

if [ "$#" -eq 0 ]; then
  set -- debian:bookworm-slim debian:trixie-slim alpine:latest
fi

# Runs as nobody so the unwritable-folder test is not skipped.
INNER='if command -v apt-get >/dev/null 2>&1; then
  apt-get update -qq && apt-get install -y -qq jq >/dev/null
else
  apk add --no-cache -q bash jq
fi
su -s /bin/bash nobody -c "bash /src/test-setup-statusline.sh"'

RESULTS=""
FAILED=0
for image in "$@"; do
  echo "=== $image ==="
  if "$CLI" run --rm -v "$HERE:/src:ro" "$image" sh -c "$INNER"; then
    RESULTS="${RESULTS}PASS $image
"
  else
    RESULTS="${RESULTS}FAIL $image
"
    FAILED=1
  fi
done

echo "---"
printf '%s' "$RESULTS"
exit "$FAILED"
