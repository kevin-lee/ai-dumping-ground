#!/usr/bin/env bash
# Tests that `render_video.py --check` of the gen-motion-graphics skill reports the CSS class name "file".
# Slack shows a page that uses it as a binary file, not as HTML (issue #56).
#
# It builds two small pages with build_html.py in a temporary folder and runs --check on each:
#   - a page with class="a card file", ".file { ... }" and classList.add("file") must fail
#   - a page with class="cfg", ".profile", ".file-list", the id "values-file", a comment with ".file"
#     and the word "file" in a caption must pass
#
# Needs python3, uv and Google Chrome (or Playwright's Chromium). --check opens the page with ?capture,
# so it never loads the audio.
#
#   bash scripts/skills/test-gen-motion-graphics-check.sh

set -u

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
S="$ROOT/skills/gen-motion-graphics/scripts"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILED=0

pass() { printf 'PASS %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; FAILED=1; }

common() { # $1: folder
  mkdir -p "$1/scenes"
  printf '{"title": "check test", "lang": "en", "fadeOut": 0.5}\n' > "$1/video.json"
  printf '{"duration": 3}\n' > "$1/mix.json"
  printf '[{"w": "Open", "s": 0.3, "e": 0.6}, {"w": "the", "s": 0.6, "e": 0.7}, {"w": "file", "s": 0.7, "e": 1.1}]\n' > "$1/timings.json"
  printf 'not real audio' > "$1/master.mp3"
}

build_and_check() { # $1: folder; prints the --check output, returns its exit status
  python3 "$S/build_html.py" --video "$1/video.json" --mix "$1/mix.json" --timings "$1/timings.json" \
    --audio "$1/master.mp3" --scenes "$1/scenes" --out "$1/page.html" > /dev/null || return 99
  uv run --quiet --script "$S/render_video.py" "$1/page.html" --check 2>&1
}

# A page that uses the class "file" in the markup, in the CSS and in a script.
BAD="$TMP/bad"
common "$BAD"
cat > "$BAD/scenes/scenes.html" <<'EOF'
<section class="scene" id="s2">
  <div class="a card file" id="s2a" style="left:600px;top:400px"><div class="fh">values-hydra.yaml</div></div>
  <div class="a card file" id="s2b" style="left:1300px;top:400px"><div class="fh">values-kratos.yaml</div></div>
</section>
EOF
cat > "$BAD/scenes/scenes.css" <<'EOF'
.file { width: 560px; padding: 24px 28px; }
.file .fh { font-family: var(--font-mono); }
EOF
cat > "$BAD/scenes/scenes.js" <<'EOF'
scene("s2", { from: 0, to: DUR, init: () => $("s2a").classList.add("file"), draw: t => {
  S($("s2a"), pop(t, cue("Open"), .4, 20, .8));
  S($("s2b"), pop(t, cue("file"), .4, 20, .8));
}});
EOF
out="$(build_and_check "$BAD")"; status=$?
printf '%s\n' "--- --check on the page that uses \"file\" (exit $status)" "$out"
[ "$status" -eq 1 ] && pass "a page that uses the class \"file\" fails --check" || fail "a page that uses the class \"file\" fails --check (exit $status)"
n="$(printf '%s\n' "$out" | grep -c 'error: line [0-9]*: CSS class "file" makes Slack treat the page as binary')"
[ "$n" -eq 5 ] && pass "--check reports 5 lines: 2 class attributes, 2 CSS rules, 1 classList.add" || fail "--check reports 5 lines (got $n)"

# A page with similar names and the word "file" in normal text, which must not be reported.
GOOD="$TMP/good"
common "$GOOD"
cat > "$GOOD/scenes/scenes.html" <<'EOF'
<section class="scene" id="s2">
  <!-- a card for each file -->
  <div class="a card cfg" id="values-file" style="left:600px;top:400px"><div class="fh">values-hydra.yaml</div></div>
  <div class="a card profile" id="s2b" style="left:1300px;top:400px"><ul class="file-list"><li>a file</li></ul></div>
</section>
EOF
cat > "$GOOD/scenes/scenes.css" <<'EOF'
/* a .file card is called .cfg */
.cfg { width: 560px; padding: 24px 28px; }
.cfg .fh { font-family: var(--font-mono); }
.profile { width: 400px; }
.file-list { margin: 0; }
EOF
cat > "$GOOD/scenes/scenes.js" <<'EOF'
// the card shows one file
scene("s2", { from: 0, to: DUR, draw: t => {
  S($("values-file"), pop(t, cue("Open"), .4, 20, .8));
  S($("s2b"), pop(t, cue("file"), .4, 20, .8));
}});
EOF
out="$(build_and_check "$GOOD")"; status=$?
printf '%s\n' "--- --check on the page that does not use \"file\" (exit $status)" "$out"
[ "$status" -eq 0 ] && pass "a page with cfg, profile, file-list and the word \"file\" passes --check" || fail "a page with cfg, profile, file-list and the word \"file\" passes --check (exit $status)"
printf '%s\n' "$out" | grep -q 'CSS class "file"' && fail "--check reports nothing about the class \"file\"" || pass "--check reports nothing about the class \"file\""

exit "$FAILED"
