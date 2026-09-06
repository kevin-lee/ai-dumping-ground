# Figures

Read this when a figure earns its place. A figure states something the surrounding text does not, and it always ends with a one-sentence caption. Four kinds exist, all styled by the template: inline SVG for topology and state machines, and three plain HTML idioms (a step flow, a before and after pair, a bar list) that cost fewer tokens to write and reflow on narrow screens. None of them carries `style=` attributes or hex colors. Tone comes from classes, so every figure follows the theme, the color vision deficiency (CVD) palette, and the palette switch.

## When a figure earns its place

Add one when the idea is one of these and prose would take a paragraph to say what a picture says at a glance:

- a flow across components or processes (who calls whom, in what order)
- a before and after topology (layers, modules, where a responsibility moved)
- a state machine
- an ordering or timing question (schedulers, ticks, retries, races)
- a data shape change (fields added, nested, split)
- a numeric comparison the PR reports

The guard: skip it for a straightforward PR, never add a decorative one, and a number that comes from the PR keeps its `<span class="src">(PR)</span>` label inside the figure.

## Where a figure may live

- `mechanism.html`: the page-wide picture.
- A group callout (`group-<key>.html`): inside the callout's second column, after the list and before or after the effect grid.
- A finding (`findings.html`): after the finding's paragraph, inside the second column.
- An extra section (`extra-<id>.html`): anywhere in the fragment.
- A block note (`block-<key>.html`): as a sibling of the `<p class="note">` lines, above the diff. Keep block-level figures rare.

## Step flow (HTML)

Boxes joined by arrows. Use it for a call chain, a pipeline, or a lifecycle.

```html
<div class="figure">
  <ol class="flow">
    <li class="accent"><span class="t">Terminal event</span><span class="d">PushEventSource</span></li>
    <li><span class="t">Inbox</span><span class="d">queued, not yet applied</span></li>
    <li class="ok"><span class="t">Loop tick</span><span class="d">applies, renders once</span></li>
  </ol>
  <p class="caption">One sentence tying the flow to the change.</p>
</div>
```

`.t` is the step name, `.d` the one-line detail. Tone classes on `li`: `ok`, `warn`, `alert`, `accent`. The list wraps on narrow screens.

## Before and after pair (HTML)

Two labeled columns. Use it when the shape of something changed.

```html
<div class="figure">
  <div class="pair">
    <div class="was"><div class="h">Before</div><p>One driver per platform, each with its own loop.</p></div>
    <div class="now"><div class="h">After</div><p>One shared loop, platform drivers only schedule.</p></div>
  </div>
  <p class="caption">One sentence on why the shape changed.</p>
</div>
```

`<pre>` and `<ul>` are allowed inside each half. The columns stack on narrow screens.

## Bar list (HTML)

Rows of label, bar, value. Use it for numbers the PR reports, never for numbers you did not measure or quote.

```html
<div class="figure">
  <div class="bars">
    <span class="k">p50</span><span class="bar" data-pct="40" aria-hidden="true"><span></span></span><span class="v">120 ms <span class="src">(PR)</span></span>
    <span class="k">p99</span><span class="bar alert" data-pct="100" aria-hidden="true"><span></span></span><span class="v">300 ms <span class="src">(PR)</span></span>
  </div>
  <p class="caption">One sentence naming the source and the comparison.</p>
</div>
```

`data-pct` is an integer from 0 to 100 (the check script rejects anything else). Tone classes on `.bar`: `ok`, `warn`, `alert`, `muted`. The label and the value carry the meaning for screen readers, the bar is decorative.

## Inline SVG

Reserve SVG for topology and state machines, where boxes and arrows must sit at positions. Skeleton:

```html
<div class="figure">
  <svg viewBox="0 0 880 300" width="100%" role="img" aria-labelledby="fig-title">
    <title id="fig-title">Before and after: where the cleanup layer sits</title>
    <!-- shapes, text, arrows -->
  </svg>
  <p class="caption">One sentence tying the figure to the change.</p>
</div>
```

Classes the template styles:

- Shapes: `.ly` (outline), `.ly-base`, `.ly-plain`, `.ly-soft`, `.ly-good`, `.ly-bad`.
- Tone fills: `.fill-ok`, `.fill-warn`, `.fill-alert`, `.fill-accent`, `.fill-muted`.
- Strokes: `.stroke-ok`, `.stroke-warn`, `.stroke-alert`, `.stroke-accent`, `.stroke-muted`, `.rule`, `.arrowline`, `.arrowhead`.
- Text: `.lbl` (uppercase label), `.mono`, `.tag` with `.good`, `.bad`, `.alert`, `.muted`, and `.small`.

Use a `viewBox` of `0 0 880 <height>` with `width="100%"`. No `style=`, no hex. Every `<title>` id must be unique on the page, so name it after the fragment (`fig-mechanism`, `fig-group-ubuntu`).

## Accessibility

- Every figure has a caption sentence.
- SVG carries `role="img"` and a `<title>` referenced by `aria-labelledby`.
- The HTML idioms need no ARIA beyond `aria-hidden` on `.bar`. The step flow is an ordered list, the pair is two labeled columns, the bar list reads as label then value.
- Tone classes are never the only signal. The text says it too.
