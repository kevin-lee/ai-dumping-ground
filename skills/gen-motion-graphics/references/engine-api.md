# Engine API

`assets/template.html` is the engine: the 1920x1080 stage, background, captions, chapter heads-up display (HUD), transitions, player, and the `renderAt(t)` frame function the renderer calls. You write three files in `sources/build/scenes/`, and `build_html.py` puts them into the template together with fonts, timings, mix data and audio.

| File | Holds |
|---|---|
| `scenes.html` | Markup inside the stage, between the background and the overlays: one `<section class="scene" id="...">` per scene, then any elements that layers animate (later in the file draws on top) |
| `scenes.css` | Styles for that markup. May override the `:root` tokens (palette, fonts, grain, caption colours) |
| `scenes.js` | Registers scenes, layers and overlays with the functions below. It runs after the engine and before boot. Never write `</script>` in it |

The page has a Content Security Policy that blocks every request to another address. Draw icons and logos as inline SVG, or put images in as `data:` URLs. `build_html.py` refuses a scene file that loads something from another address or leaves the page, and `render_video.py --check` reports a request the policy blocked as an ERROR.

## The one rule: every frame is a pure function of time

The renderer jumps to arbitrary times, in parallel processes, and the player seeks. So `draw(t)` must set everything that depends on time from `t` alone:

- Do not use `Date.now()`, `performance.now()`, `Math.random()`, `setTimeout`, `requestAnimationFrame`, CSS `transition` or `@keyframes`, or video and GIF elements. Use `rand(n)` for deterministic randomness.
- Do not accumulate state between frames (no `x += 1` per frame). Compute the value for `t`.
- Start every element invisible through its pose (`o: 0` before its entrance), not by toggling classes.

## Coordinates

- The stage is 1920x1080 CSS pixels and scales to fit the window (and to 3840x2160 for a 4K render), so design at 1080p.
- `.a` is an anchor: `left` and `top` place the element's centre, and `S()` moves it from there. A scene `<section>` covers the whole stage, so positions inside it are stage coordinates: `<div class="a headline" id="s1t" style="left:960px;top:300px">`.
- **Safe area:** keep important content inside x 120 to 1800 and y 90 to 870. The bottom 200 px belongs to the captions and the top-right corner to the chapter HUD. `render_video.py --check` reports text that collides with the captions or the frame edge.

## Time comes from the narration

Never hard-code a second for something tied to speech. Look up the word instead, so the scenes still fit when the narration is regenerated:

| Function | Returns |
|---|---|
| `cue("phrase", after = 0)` | Start time of the first occurrence of the word sequence at or after `after`. Case and punctuation are ignored, apostrophes too ("script's" matches `cue("scripts")`). Throws when not found |
| `cueEnd("phrase", after = 0)` | End time of that occurrence's last word |
| `wordsIn(a, b)` | Timing entries `{w, s, e}` that start in `[a, b)` |
| `TIMINGS`, `NARR_START`, `NARR_END`, `DUR` | All words, first word start, last word end, video length |

Look cues up once at the top of `scenes.js`, using distinctive phrases. For repeated words, pass `after`, usually an earlier cue:

```js
const C = {
  hook: cue("Every team"),
  meet: cue("Meet Toolbox"),
  repo: cue("Point it at"),
  pick: cue("pick a script"),
  os: cue("macOS and Linux"),
};
C.homebrew = cue("Homebrew", C.os);
```

Words in captions are shown in their written form (from `display.json`), so cue them that way: `cue("skills.sh")`.

Timing habits that read well:

- An element appears on its word, or 0.05 to 0.15 s before it.
- A scene starts just before the first word of its idea. `cutAt(cue("..."))` gives the time: a beat at most 0.4 s before the word, else a half beat, else 0.2 s before it. Plain `snapBeat` can land in the middle of the previous sentence.
- A scene ends at the next scene's start. The engine blur-zooms it out over its last 0.28 s.

## Music

Values come from `mix.json`, and they are all zero or no-ops when the video has no music.

| Name | Meaning |
|---|---|
| `BPM`, `BEAT` | Tempo and seconds per beat |
| `beat(k)` | Video time of beat k (k = 0 is the drop, 4 beats to a bar) |
| `snapBeat(t, dir = 0)` | Nearest beat to t (dir 1: the next one, -1: the previous one) |
| `cutAt(w)` | Time for a cut into a scene whose first word starts at w (see the timing habits above). Without music, w − 0.2 |
| `pulse(t)` | 0 to 1 kick on every beat, stronger on beat 1, only where the drums play |
| `drums(t)` | 0 to 1 how much the drums are playing |

The background already pulses. Use `1 + .03 * pulse(t)` on a hero element or a glow, not on body text.

## Registering things

```js
scene(id, { from, to, draw(t) { ... }, init() { ... }, exit: "zoom" | "fade" | "none" });
layer(draw, { init });        // runs every frame of the video; it controls its own visibility
cut(t);                       // two colour bands sweep across the stage, centred on t
ring(t, x = 960, y = 540);    // expanding ring, for reveals
flash(t, a = .2);             // white flash, keep a <= .4 and use few
chapter(t, "01", "install");  // corner HUD label from t on
chaptersEnd(t);               // HUD fades out at t
sfx(t, kind, { gain, dur });  // a sound effect that lands at t (see below)
```

**Sound effects.** `sfx()` registers a sound that lands at t. The engine also adds a whoosh for every `cut()`, an impact for every `flash()` and a pop for every `ring()` without a flash. Set `"sfx": {"auto": false}` in `video.json` to switch those off. `render_video.py --export-sfx` lists them all for `mix_audio.py --sfx`, which synthesizes and mixes them.

| kind | lands | use it for |
|---|---|---|
| `whoosh` | peaks at t | scene changes (automatic on cuts) |
| `swipe` | peaks at t | a card or panel sliding in |
| `pop` | at t | an element popping in on its word |
| `tick` | at t | a single click, a checkbox |
| `type` | ticks from t over `dur` | text being typed (match `typed()`'s start and duration) |
| `riser` | rises into t over `dur` | the build-up before a reveal |
| `impact` | at t | the reveal (automatic on flashes) |
| `ding` | at t | success, a finished step |

`gain` scales one sound (default 1). Keep them light: one sound on each meaningful moment, not on every element.

A scene is shown only for `from <= t < to`, and `draw` runs only then. Scenes may overlap. The later one in the file draws on top. `init` runs once at boot: build repeated markup there with template strings. Measure text and paths lazily inside `draw` (fonts are loaded by then) and cache the results on the element.

## Pose and content helpers

| Helper | Does |
|---|---|
| `S(el, {x, y, s, sx, sy, r, o, b}, center = true)` | Sets translate (px), scale, rotation (deg), opacity and blur (px). Pass `center = false` for elements that are not `.a` anchors, such as spans inside a line of text |
| `H(el, html)` | Sets `innerHTML` only when it changed |
| `pop(t, at, d = .5, dy = 36, s0 = .8)` | Entrance pose: fade, rise and overshoot scale |
| `out(t, at, d = .3, dy = -30)` | Exit pose |
| `both(a, b)` | Combines an entrance and an exit pose |
| `typed(segs, t, at, dur, caretUntil)` | HTML of coloured text typed from `at` over `dur` s. segs = lines of `[text, cssClass]` |
| `typeSegs(segs, n, t, caret)`, `segLen(segs)`, `caret(t)` | Lower-level typing helpers |
| `drawPath(pathEl, u)` | Draws an SVG path that has `pathLength="1"`, u from 0 to 1 |
| `countUp(t, at, d, a, b, decimals = 0)` | Number counting from a to b |
| `shake(t, amp, seed)` | `{x, y}` jitter for impact moments |
| `P(t, a, d)` | Progress of t through `[a, a + d]`, clamped to 0..1 |
| `eOut`, `eIn`, `eInOut`, `eBack`, `eElastic`, `bump(u)` | Easing. `bump` is 0 → 1 → 0 |
| `lerp`, `clamp`, `mix(poseA, poseB, u)`, `rand(n)`, `$(id)`, `esc(s)` | Basics. `$` throws on a missing id, which `--check` reports |

## Kit classes and tokens

Classes in the template: `.headline`, `.kicker`, `.bigmsg`, `.chip`, `.pill`, `.card`, `.stamp`, `.term` (a terminal window: `.bar` with three `<i>` and a `<span>` title, then `.body`), `.car` (caret), `.flow` (dashed SVG path), `.inl` and `.w` (inline-block spans for word-by-word animation), `.mono`, `.display`. Colour classes: `.dim .pe .lv .mi .su .ro .gr .sk .ac`.

Tokens you can override in `scenes.css`:

```css
:root {
  --ink: #0c0e1a; --panel: #151a31; --panel2: #10132a; --line: #2a3052; --fg: #f4f1ea; --dim: #8f96b8;
  --peach: #ffb38a; --lav: #b8a1ff; --mint: #7ee0c3; --sun: #ffd36e; --rose: #ff7a90; --green: #6fdc8c; --sky: #86adff;
  --accent: var(--peach); --accent2: var(--lav); --accent3: var(--mint);
  --stage-bg: var(--ink); --blob-a: rgba(255,179,138,.30); --blob-b: rgba(184,161,255,.30); --blob-c: rgba(126,224,195,.16);
  --grid-dot: rgba(255,255,255,.10); --grain: .05; --vignette: rgba(0,0,0,.55); --flash: #fff7ee;
  --cap-bg: rgba(8,10,20,.62); --cap-fg: var(--fg); --cap-hi: var(--accent); --cap-hi-fg: var(--ink);
}
```

Fonts come from `video.json` and set `--font-ui`, `--font-mono` and `--font-display`. The body uses `--font-ui`, while `.term`, `.mono` and `code` use `--font-mono`.

## video.json

```json
{
  "title": "Toolbox Intro",
  "lang": "en",
  "poster": 9.5,
  "fadeOut": 1.5,
  "captions": {"maxWords": 6, "maxChars": 42, "enabled": true},
  "fonts": [
    {"family": "Inter", "file": "fonts/Inter-opsz-wght-subset.woff2", "weight": "100 900", "role": "ui"},
    {"family": "JetBrains Mono", "file": "fonts/JetBrainsMono-wght-subset.woff2", "weight": "100 800", "role": "mono"}
  ]
}
```

`poster` is the frame shown before Play (pick a striking one). `duration`, `music` and `narration` come from `mix.json`. Paths are relative to `video.json`. A role may be a list (`["ui", "mono"]`).

## A complete small example

This shows the API on three scenes. It is not a finished video: it leaves the last sentence and the end card uncovered, has no layer carried across scenes, and has far fewer events than `motion-design.md` asks for. A demo built from it once looked sparse to the user. Use it to learn the calls, never as a template for the amount of motion.

`scenes.html`:

```html
<section class="scene" id="hook">
  <div class="a bigmsg" id="hookMsg" style="left:960px;top:470px"><span class="inl">a folder of scripts</span><br><span class="inl ac" id="hookNo">nobody can find</span></div>
</section>
<section class="scene" id="meet">
  <div class="a kicker" id="meetK" style="left:960px;top:330px">meet</div>
  <div class="a headline" id="meetT" style="left:960px;top:450px;font-size:140px">Toolbox</div>
  <div class="a" id="meetSub" style="left:960px;top:590px;font-size:40px"></div>
</section>
<section class="scene" id="steps">
  <div id="stepCards"></div>
</section>
```

`scenes.js`:

```js
const C = { hook: cue("Every team"), nobody: cue("nobody else"), meet: cue("Meet Toolbox"), one: cue("one command"),
            point: cue("Point it at"), type: cue("Type a few"), pick: cue("pick a script"), runs: cue("it runs"), os: cue("It works on") };
const STEPS = [["Point it at a repo", C.point], ["Type a few letters", C.type], ["Pick a script", C.pick], ["It runs", C.runs]];

scene("hook", { from: 0, to: C.meet - .2, draw: t => {
  const [l1, l2] = $("hookMsg").children;
  S(l1, pop(t, C.hook, .5, 40, .7), false);
  S($("hookNo"), { ...pop(t, C.nobody, .45, 30, .6), ...shake(t, 8 * bump(P(t, C.nobody + .3, .4))) }, false);
}});

scene("meet", { from: C.meet - .2, to: C.point - .2, draw: t => {
  S($("meetK"), pop(t, C.meet, .4, 20, .8));
  S($("meetT"), { ...pop(t, C.meet + .25, .6, 0, .4), s: pop(t, C.meet + .25, .6, 0, .4).s * (1 + .03 * pulse(t)) });
  H($("meetSub"), typed([[["one command, ", "dim"], ["a searchable menu", "ac"]]], t, C.one, .8, C.point - .5));
}});

scene("steps", { from: C.point - .2, to: C.os - .2,
  init: () => { $("stepCards").innerHTML = STEPS.map(([txt], i) =>
    `<div class="a card" id="st${i}" style="left:${330 + i * 420}px;top:520px;width:360px;text-align:center;font-size:34px;font-weight:700">
       <div class="ac" style="font-size:64px">${i + 1}</div>${esc(txt)}</div>`).join(""); },
  draw: t => STEPS.forEach(([, at], i) => S($("st" + i), { ...pop(t, at, .5, 60, .7), r: (1 - eOut(P(t, at, .5))) * (i % 2 ? 6 : -6) })),
});

cut(C.meet - .2); ring(C.meet + .25, 960, 450); flash(C.meet + .25, .2);
cut(C.point - .2); chapter(C.point - .2, "01", "how it works"); chaptersEnd(C.os - .2);
```
