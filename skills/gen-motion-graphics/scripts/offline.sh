#!/bin/sh
# Run a command with all network access blocked, so narration text and audio cannot leave the machine.
#   scripts/offline.sh uv run --script scripts/tts_kokoro.py ...
# Models and packages must already be downloaded (each TTS script has a --setup step for that).
export HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 UV_OFFLINE=1 HF_HUB_DISABLE_TELEMETRY=1
case "$(uname -s)" in
  Darwin)
    exec sandbox-exec -p '(version 1)(allow default)(deny network*)' "$@" ;;
  Linux)
    if unshare -rn true 2>/dev/null; then exec unshare -rn "$@"; fi
    if command -v firejail >/dev/null 2>&1; then exec firejail --quiet --net=none "$@"; fi
    echo "offline.sh: cannot block the network here (no unprivileged unshare, no firejail)." >&2
    echo "offline.sh: ask the user before running without the block." >&2
    exit 2 ;;
  *)
    echo "offline.sh: unsupported system $(uname -s); ask the user before running without a network block." >&2
    exit 2 ;;
esac
