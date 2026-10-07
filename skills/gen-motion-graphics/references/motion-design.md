# Motion design

How to make the video dynamic and engaging rather than a narrated slideshow. The defaults here come from an intro the user approved: dark pastel, kinetic, every visual on its word, every cut on the beat. Follow the user's own visual preferences when they have any.

## Principles

1. **Show what is said, when it is said.** Every important noun or verb gets a visual beat on its word. Items in a spoken list appear one by one, each on its own word. Use `cue()` for all of it.
2. **Show, do not caption.** The captions already carry the words. The picture shows the thing itself: a terminal typing the command, cards for the options, a diagram of the flow, logos, numbers counting up. On-screen text is short labels and headlines, about seven words at most besides the captions.
3. **Lock to the music.** Cut scenes on beats near the narration's turns (`cutAt`). Pulse hero elements on the beat (`pulse(t)`). Land the big reveal on a strong downbeat with `ring` and `flash`.
4. **Never freeze.** Something must move in every frame. The background drifts by itself. Give scenes a slow push (scale 1 to 1.03 across the scene) and let resting elements breathe or float a few pixels. Something new appears at least every 1.5 s, and much more often while words are spoken (see "Density" below).
5. **One idea per scene, one focal point.** Clear hierarchy: one big thing, a few supporting things.
6. **Continuity beats cuts.** Carry objects across scenes with a `layer`. In the approved intro, the six agent tiles lined up, scattered on "messy", orbited the logo, collapsed into it, and came back for the end card. The logo itself shrank into the corner as a heads-up display (HUD) badge. Recurring objects make it feel designed.
7. **Contrast tension and release.** A problem gets tension: rose tint, shake, tangled lines, glitch-split text. The solution resolves it: clean layout, smooth curves, green ticks, a calm palette.
8. **Sound marks the moments.** Light sound effects make motion feel physical: a whoosh on a cut, a pop when a card lands on its word, ticks while a command types, a riser into the reveal and an impact on it, a ding when something succeeds. Put one on each meaningful moment and leave the rest to the music. A sound on every element turns into noise. Declare them in `scenes.js` with the same cues as the visuals (`sfx(C.pick, "pop")`), so sound and picture stay in step.
9. **Energy curve.** Fast hook, big reveal, steady informative body with chapters, one more reveal for the strongest point, then a calm end card while the music plays out.

## Density

The user approved this amount of motion: a 28.5 s intro with 5 scenes and 66 visual moments, each on a word or a beat (about one every 0.4 s). `render_video.py --check` measured it at 99 element entrances (3.5 per second), and it never went more than 1.25 s without something new. Make that the default, unless the user asks for calmer:

- Every noun, verb and list item the narration names gets its own entrance on its word: an icon, a chip, a card, a typed line, a counter.
- Between spoken visuals, small beats keep it alive: a highlight, a check landing, a ring on the beat, an element moving to a new place.
- `--check` prints the entrances per second and the longest stretch with nothing new. Under about 2 per second, or a stretch over 2 s, means the storyboard needs more beats there.

## Structure of a 60 to 90 s intro

| Part | Time | What |
|---|---|---|
| Cold open | lead-in, about 2 s | Name typed in a prompt, or a logo sting, over the music alone |
| Hook | 6 to 12 s | The problem or the promise. Concrete, a little tension |
| Reveal | 3 to 5 s | Name and logo, ring and flash on the drop or a downbeat, tagline typed |
| Chapters | 5 to 9 s each | One feature each, with a chapter HUD ("01 install"), a show-don't-tell visual and a cut between |
| Climax | 5 to 8 s | The differentiator, with the second-biggest visual moment |
| Get it | 4 to 6 s | Install command typed, platforms, link |
| End card | outro, 4 to 6 s | Logo, tagline, where to find it. The music closes |

An explainer swaps the chapters for steps, and a 30 s promo keeps the hook, the reveal, two points and the end card.

## Layout and type

- Safe area x 120 to 1800, y 90 to 870. The captions own the bottom, the HUD the top-right corner.
- Sizes at 1080p: headline 80 to 150 px, subhead 36 to 48, body 26 to 34, labels 22 to 26. Nothing under 22 px.
- Use one UI family and a monospace family for code. Display weights are 700 to 800 and body 500 to 600. Tight negative letter-spacing works on big headlines.
- Colour: a dark base, three accents, and meaning colours (green for success, rose for problems, sun for warnings). Keep accents for what matters.
- Do not use emoji. They fall back to system fonts and look different everywhere. Draw icons as inline SVG.

## Timing numbers

- Entrances 0.35 to 0.6 s with overshoot (`pop`). Exits 0.25 to 0.35 s (`out`). Stagger 0.05 to 0.12 s.
- Readable text stays at least 1.5 s. Typing speed is 25 to 45 characters per second.
- Scenes last 4 to 7 s. Something new every 0.3 to 1 s, never more than 1.5 s without it.
- Flashes: at most three per video, strength 0.4 or less. Never strobe.

## Pattern catalog

Every snippet uses only the engine API (`references/engine-api.md`). `C` holds cues.

**Kinetic headline, word by word on speech:**
```html
<div class="a headline" id="h1" style="left:960px;top:200px"><span class="w ac">AI</span> <span class="w">coding</span> <span class="w">agents</span></div>
```
```js
const ws = [...$("h1").children], at = ["AI", "coding", "agents"].map(w => cue(w, C.start));
ws.forEach((el, i) => S(el, pop(t, at[i], .45, 50, .6), false));
```

**Staggered cards, each on its spoken name:**
```js
NAMES.forEach((n, i) => { const at = cue(n, C.list);
  S($("card" + i), { ...pop(t, at, .55, 90, .6), r: (1 - eOut(P(t, at, .55))) * (i % 2 ? 8 : -8) }); });
```

**Typed command in a terminal:**
```html
<div class="a term" id="tm" style="left:960px;top:430px;width:1200px;height:300px">
  <div class="bar"><i></i><i></i><i></i><span>~/project</span></div><div class="body" id="tmb"></div></div>
```
```js
S($("tm"), pop(t, C.run - .3, .45, 40, .92));
H($("tmb"), typed([[["❯ ", "dim"], ["toolbox ", ""], ["install", "ac"]], [["✓ ready", "gr"]]], t, C.run, .9, C.next));
```

**Output lines streaming in, with statuses:**
```js
ROWS.forEach((r, i) => { const at = C.check + .5 + i * .25, done = t >= at + .6;
  H($("row" + i), done ? `<span class="gr">✓</span> ${esc(r)}` : `<span class="dim">… ${esc(r)}</span>`);
  S($("row" + i), { o: P(t, at, .15) }, false); });
```

**Flow diagram with dashes and dots travelling along the paths** (paths in an `<svg class="full">`):
```js
[...$("flows").querySelectorAll("path")].forEach((p, k) => {
  p.style.opacity = P(t, C.flow + k * .15, .3); p.style.strokeDashoffset = (-t * 60).toFixed(1);
  const L = p._len ?? (p._len = p.getTotalLength()), u = ((t * .8) + k * .3) % 1, pt = p.getPointAtLength(L * u);
  const dot = $("dot" + k); dot.setAttribute("cx", pt.x); dot.setAttribute("cy", pt.y); dot.style.opacity = Math.sin(Math.PI * u);
});
```

**Line drawing** (`<path pathLength="1" ...>`):
```js
drawPath($("link" + i), eOut(P(t, C.connect + i * .05, .5)));
```

**Items flying along an arc from A to B (copy, sync, send):**
```js
const u = eInOut(P(t, C.copy + k * .16, .55));
S($("fly" + k), { x: lerp(0, 800, u), y: -170 * Math.sin(Math.PI * u), r: 6 * bump(u), s: 1 + .08 * bump(u), o: u > 0 && u < 1 ? 1 : 0 });
```

**Orbit, then collapse into a logo:**
```js
const a = (i * 60 - 90 + (t - C.meet) * 9) * Math.PI / 180, orbit = { x: 960 + 640 * Math.cos(a), y: 450 + 300 * Math.sin(a), s: .5 };
const into = eIn(P(t, C.collapse + i * .03, .4));
S($("tile" + i), { ...mix(orbit, { x: 960, y: 450, s: .1 }, into), o: 1 - into });
```

**Logo reveal on the beat:**
```js
const at = snapBeat(C.meet, 1); const u = P(t, at, .6);
S($("logo"), { s: (.4 + .6 * eBack(u)) * (1 + .02 * pulse(t)), o: clamp(u * 3) });
// at top level: ring(at, 960, 450); flash(at, .22);
```

**Problem moment: shake, tint, glitch split:**
```js
const amp = 18 * eIn(P(t, C.messy - .3, .6)), j = shake(t, amp, 3);
S($("msg"), { ...j, s: 1.6 - .6 * eOut(P(t, C.messy, .35)), o: P(t, C.messy, .1) });
$("msg").style.textShadow = `${-6 - amp * .8}px 0 rgba(255,80,120,.85), ${6 + amp * .8}px 0 rgba(80,200,255,.85)`;
$("tint").style.opacity = (.9 * P(t, C.messy - .3, .6)).toFixed(3);
```

**Strike-through and stamp:**
```js
S($("strike1"), { sx: eOut(P(t, C.noJvm, .3)), sy: 1 }, false);   // .strike: transform-origin 0 50%
const st = P(t, C.notRequired, .3); S($("stamp"), { o: clamp(st * 4), s: 1.7 - .7 * eBack(st), r: -8 });
```

**Number counting up:**
```js
H($("stat"), countUp(t, C.stars, 1.2, 0, 12000).replace(/\B(?=(\d{3})+(?!\d))/g, ","));
```

**Camera push across a scene and a gentle float at rest:**
```js
const S3 = { from: C.install - .2, to: C.search - .2 };
scene("s3", { ...S3, draw: t => {
  S($("s3wrap"), { s: 1 + .03 * P(t, S3.from, S3.to - S3.from) });   // wrap the scene content in one .a div
  S($("badge"), { y: 6 * Math.sin(t * 1.6) });
}});
```

**Element travelling into the HUD corner and back for the end card:**
```js
const HUD = { x: 150, y: 58, s: .25 }, CENTER = { x: 960, y: 450, s: 1 };
const p = t < C.end ? mix(CENTER, HUD, eInOut(P(t, C.firstChapter, .6))) : mix(HUD, CENTER, eInOut(P(t, C.end, .6)));
S($("logo"), p);
```

## Looks

Override the tokens in `scenes.css`. "Dark pastel" is the engine default.

```css
/* Light and clean */
:root { --ink:#f6f4ef; --stage-bg:#f6f4ef; --panel:#ffffff; --panel2:#f0ede6; --line:#ddd7cc; --fg:#1d1b26; --dim:#6d6a7c;
  --peach:#f2783c; --lav:#6b54e8; --mint:#0fa37f; --sun:#e2a400; --rose:#e2475f; --green:#22a35a; --sky:#2f7ee8;
  --blob-a:rgba(242,120,60,.16); --blob-b:rgba(107,84,232,.14); --blob-c:rgba(15,163,127,.10);
  --grid-dot:rgba(0,0,0,.08); --grain:.025; --vignette:rgba(0,0,0,.10); --cap-bg:rgba(255,255,255,.85); --cap-hi-fg:#fff; }

/* Bold and colourful */
:root { --ink:#120a2a; --stage-bg:#120a2a; --panel:#24124f; --panel2:#1b0e3d; --line:#4b2c99; --fg:#fff8f0; --dim:#b9a8e8;
  --peach:#ff8a3d; --lav:#c77dff; --mint:#3ef0c0; --sun:#ffe14d; --rose:#ff4d8d; --green:#5df28a; --sky:#4dc3ff;
  --accent:var(--sun); --blob-a:rgba(255,77,141,.45); --blob-b:rgba(77,195,255,.40); --blob-c:rgba(255,225,77,.25); --grain:.04; }
```

## Avoid

- Invented facts on screen: a made-up install command, URL, version or number. Illustrations (example file names, sample data) are fine when they read as examples and are listed in the report.
- Slides of bullet points, or the narration repeated as on-screen text.
- Motion that is not tied to a word, a beat or a transition. Random wiggles read as noise.
- Many things moving at once. Animate the focal element and let the rest settle.
- Text under 22 px, light text on a busy background, important things in the caption area.
- Heavy `filter: blur()` on many elements at once (it slows rendering). Use it for exits only.
- Stock-photo or clip-art looks. Simple geometric shapes, terminals, cards, diagrams and type carry this style.
