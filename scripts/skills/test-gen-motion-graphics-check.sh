#!/usr/bin/env bash
# Tests that gen-motion-graphics pages are safe to upload to Slack (issue #56).
#
# Slack shows an uploaded page as a binary file when a line starts with "." and certain names (".file", ".text",
# ".globl", ".type", ".byte" in the upload tests), at column 0 or after tabs, in CSS, comments and text alike.
#
#   - build_html.py puts one space before every line that starts with optional tabs, "." and a letter,
#     so a built page has no such line, and render_video.py --check passes.
#   - A page with such a line (a page built without the space) fails --check, with one error per line.
#   - The class name "file" in the middle of a line (class="a card file") is not a problem.
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
TAB="$(printf '\t')"
DOT_LINE="^${TAB}*\\.[A-Za-z_]"   # a line that starts with optional tabs, "." and a letter

pass() { printf 'PASS %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; FAILED=1; }
check() { uv run --quiet --script "$S/render_video.py" "$1" --check 2>&1; }

D="$TMP/page"
mkdir -p "$D/scenes"
printf '{"title": "check test", "lang": "en", "fadeOut": 0.5}\n' > "$D/video.json"
printf '{"duration": 3}\n' > "$D/mix.json"
printf '[{"w": "Open", "s": 0.3, "e": 0.6}, {"w": "the", "s": 0.6, "e": 0.7}, {"w": "file", "s": 0.7, "e": 1.1}]\n' > "$D/timings.json"
printf 'not real audio' > "$D/master.mp3"

# Every trigger that the upload tests found: in CSS, a CSS comment, page text and a JS comment, at column 0 and
# after a tab, and as a prefix. Plus the class name "file" in the middle of a line, which is safe.
cat > "$D/scenes/scenes.html" <<EOF
<section class="scene" id="s2">
  <div class="a card file" id="s2a" style="left:600px;top:400px"><div class="fh">values-hydra.yaml</div></div>
  <div class="a card files" id="s2b" style="left:1300px;top:400px">values-kratos.yaml</div>
  <p class="a" id="s2c" style="left:960px;top:650px">
.file
  </p>
</section>
EOF
cat > "$D/scenes/scenes.css" <<EOF
.file { width: 560px; padding: 24px 28px; }
.file .fh { font-family: var(--font-mono); }
${TAB}.text { color: inherit; }
.files { margin: 0; }
/*
.type
*/
EOF
cat > "$D/scenes/scenes.js" <<EOF
/*
${TAB}.globl
*/
scene("s2", { from: 0, to: DUR, draw: t => {
  S(\$("s2a"), pop(t, cue("Open"), .4, 20, .8));
  S(\$("s2b"), pop(t, cue("file"), .4, 20, .8));
}});
EOF

if ! python3 "$S/build_html.py" --video "$D/video.json" --mix "$D/mix.json" --timings "$D/timings.json" \
  --audio "$D/master.mp3" --scenes "$D/scenes" --out "$D/page.html" > "$D/build.txt"; then
  fail "build_html.py builds the page"
  exit 1
fi
cat "$D/build.txt"

n="$(grep -c "$DOT_LINE" "$D/page.html")"
if [ "$n" -eq 0 ]; then pass "the built page has no line that starts with \".\" and a letter"; else fail "the built page has no line that starts with \".\" and a letter (got $n)"; fi
n="$(grep -c -e '^ \.file {' -e "^ ${TAB}\\.text {" -e '^ \.files {' -e '^ \.type$' -e "^ ${TAB}\\.globl$" -e '^ \.file$' "$D/page.html")"
if [ "$n" -eq 6 ]; then pass "the 6 scene lines are still there, with one space in front"; else fail "the 6 scene lines are still there, with one space in front (got $n)"; fi
if grep -q 'class="a card file"' "$D/page.html"; then pass "the class name \"file\" does not change"; else fail "the class name \"file\" does not change"; fi

out="$(check "$D/page.html")"; status=$?
printf '%s\n' "--- --check on the built page (exit $status)" "$out"
if [ "$status" -eq 0 ]; then pass "the built page passes --check"; else fail "the built page passes --check (exit $status)"; fi

# The same page without the space before 2 of the lines, as a page built without this fix would be.
sed -e 's/^ \(\.file {\)/\1/' -e "s/^ \\(${TAB}\\.text {\\)/\\1/" "$D/page.html" > "$D/old.html"
out="$(check "$D/old.html")"; status=$?
printf '%s\n' "--- --check on the page without the space (exit $status)" "$out"
if [ "$status" -eq 1 ]; then pass "a page with a line that starts with \".\" fails --check"; else fail "a page with a line that starts with \".\" fails --check (exit $status)"; fi
n="$(printf '%s\n' "$out" | grep -c -e 'error: line [0-9]*: "\.file {.*" starts with "\." and a letter' -e 'error: line [0-9]*: "\.text {.*" starts with "\." and a letter')"
if [ "$n" -eq 2 ]; then pass "--check reports the 2 lines, .file and a tab then .text"; else fail "--check reports the 2 lines, .file and a tab then .text (got $n)"; fi

exit "$FAILED"
