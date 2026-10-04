#!/bin/bash
input=$(cat)

MODEL=$(echo "$input" | jq -r '.model.display_name')
EFFORT=$(echo "$input" | jq -r '.effort.level // empty')
DIR=$(echo "$input" | jq -r '.workspace.current_dir')
COST=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
PCT=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
IN_TOK=$(echo "$input" | jq -r '.context_window.total_input_tokens // 0')
OUT_TOK=$(echo "$input" | jq -r '.context_window.total_output_tokens // 0')
CTX_SIZE=$(echo "$input" | jq -r '.context_window.context_window_size // 0')
USED_TOK=$((IN_TOK + OUT_TOK))
DURATION_MS=$(echo "$input" | jq -r '.cost.total_duration_ms // 0')
TRANSCRIPT=$(echo "$input" | jq -r '.transcript_path // empty')

# Prompt cache: "<last API call epoch> <ttl seconds>" from the transcript.
# TTL is 1h if the most recent cache write used the 1h tier, otherwise 5m.
CACHE_TS=""; CACHE_TTL=""
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
  read -r CACHE_TS CACHE_TTL < <(tail -n 400 "$TRANSCRIPT" 2>/dev/null | jq -rRs '
    [ split("\n")[] | fromjson? | select(.type == "assistant" and .message.usage != null and (.isSidechain | not)) ] as $a
    | if ($a | length) == 0 then empty else
        ([ $a[] | .message.usage.cache_creation // {}
           | select((.ephemeral_1h_input_tokens // 0) + (.ephemeral_5m_input_tokens // 0) > 0) ] | last) as $cc
        | (if ($cc.ephemeral_1h_input_tokens // 0) > 0 then 3600 else 300 end) as $ttl
        | "\($a[-1].timestamp | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601) \($ttl)"
      end')
fi

# Format a token count compactly: 16700 -> 16.7k, 200000 -> 200k, 1000000 -> 1M
fmt_tokens() {
  awk -v n="$1" 'BEGIN {
    if (n >= 1000000)      { v = n / 1000000; s = "M" }
    else if (n >= 1000)    { v = n / 1000;    s = "k" }
    else                   { printf "%d", n; exit }
    if (v == int(v)) printf "%d%s", v, s; else printf "%.1f%s", v, s
  }'
}
USED_FMT=$(fmt_tokens "$USED_TOK")
TOTAL_FMT=$(fmt_tokens "$CTX_SIZE")

CYAN='\033[36m'; GREEN='\033[32m'; YELLOW='\033[33m'; RED='\033[31m'; RESET='\033[0m'
COLOR_MODEL='\033[38;5;75m'    # steel blue
COLOR_EFFORT='\033[38;5;214m'  # amber/orange
COLOR_TOKENS='\033[38;5;245m'  # gray

# Pick bar color based on context usage
if [ "$PCT" -ge 90 ]; then BAR_COLOR="$RED"
elif [ "$PCT" -ge 70 ]; then BAR_COLOR="$YELLOW"
else BAR_COLOR="$GREEN"; fi

FILLED=$((PCT / 10)); EMPTY=$((10 - FILLED))
printf -v FILL "%${FILLED}s"; printf -v PAD "%${EMPTY}s"
BAR="${FILL// /█}${PAD// /░}"

MINS=$((DURATION_MS / 60000)); SECS=$(((DURATION_MS % 60000) / 1000))

BRANCH=""
git rev-parse --git-dir > /dev/null 2>&1 && BRANCH=" | 🌿 $(git branch --show-current 2>/dev/null)"

CACHE=""
if [ -n "$CACHE_TS" ] && [ -n "$CACHE_TTL" ]; then
  REMAIN=$((CACHE_TS + CACHE_TTL - $(date +%s)))
  if [ "$CACHE_TTL" -ge 3600 ]; then TIER="1h"; else TIER="5m"; fi
  if [ "$REMAIN" -le 0 ]; then
    CACHE=" | 💾 ${RED}cache expired${RESET} ${COLOR_TOKENS}(${TIER})${RESET}"
  else
    if [ $((REMAIN * 5)) -le "$CACHE_TTL" ]; then CACHE_COLOR="$YELLOW"; else CACHE_COLOR="$GREEN"; fi
    CACHE=" | 💾 ${CACHE_COLOR}cache $((REMAIN / 60))m $((REMAIN % 60))s${RESET} ${COLOR_TOKENS}(${TIER})${RESET}"
  fi
fi

COST_FMT=$(printf '$%.2f' "$COST")
echo -e "${COLOR_MODEL}[$MODEL${RESET} ${COLOR_EFFORT}$EFFORT${COLOR_MODEL}]${RESET} | 📁 ${DIR##*/}$BRANCH | ${BAR_COLOR}${BAR}${RESET} ${PCT}% ${COLOR_TOKENS}(${USED_FMT}/${TOTAL_FMT})${RESET}${CACHE} | ${YELLOW}${COST_FMT}${RESET} | ⏱️ ${MINS}m ${SECS}s"
