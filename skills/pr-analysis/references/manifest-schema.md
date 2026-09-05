# Manifest and fragments

The build reads `<workdir>/content/manifest.json` and the fragment files next to it, joins them with `meta.json` and the embedded file versions, and writes one HTML file. You author the manifest and the fragments. You never edit the output.

## manifest.json

```jsonc
{
  "title": "ABC-123 Payment retries",            // <ticket or repo> <short subject>, page name, not a caption
  "langMode": "single",                          // "single" (English only, or hidden bilingual) or "both"
  "lang2": null,                                 // BCP 47 code such as "ko", or null for English only
  "palette": {
    "name": "sage",                               // a named pastel from assets/palettes.json. For a custom brief omit name and give accentLight, accentDark, paperLight, paperDark instead, never both
    "fontDisplay": "\"Manrope\", \"Helvetica Neue\", Arial, sans-serif",
    "fontBody": "\"Source Sans 3\", \"Segoe UI\", Roboto, Helvetica, Arial, sans-serif",
    "fontMono": "\"JetBrains Mono\", ui-monospace, SFMono-Regular, Menlo, Consolas, monospace",
    "fontsHref": "https://fonts.googleapis.com/css2?family=Manrope:wght@600;700;800&family=Source+Sans+3:ital,wght@0,400;0,500;0,600;1,400&family=JetBrains+Mono:wght@400;500&display=swap"
  },
  "ticket": { "label": "ABC-123", "url": "https://your-domain.atlassian.net/browse/ABC-123" },  // url may be null
  "kinds": {
    "fix":     { "en": "Fix",     "l2": null, "tone": "ok",     "glyph": "◆" },
    "silence": { "en": "Silence", "l2": null, "tone": "warn",   "glyph": "▲" },
    "hygiene": { "en": "Hygiene", "l2": null, "tone": "nodata", "glyph": "●" }
  },
  "groups": [
    {
      "key": "ubuntu", "en": "Ubuntu", "l2": null,
      "calloutFragment": "group-ubuntu.html",   // or null
      "mask": [                                  // or null. Applied before comparing files in a group
        { "pattern": "^ENV JAVA_FULL_VERSION .*$", "flags": "gm", "replacement": "ENV JAVA_FULL_VERSION <VERSION>" }
      ]
    }
  ],
  "blocks": [
    {
      "key": "jre21",                 // used in ids: b-jre21, data-block, data-ident
      "fileIndex": 3,                 // index into meta.files
      "group": "ubuntu",              // or null
      "rep": true,                    // one representative per group, or false
      "kinds": ["fix", "hygiene"],
      "en": "Fold cleanups into the install layer",     // one line, imperative
      "l2": null,
      "notesFragment": "block-jre21.html",              // or null
      "range": null                   // or { "before": [17, 40], "after": [19, 44] } 1-based inclusive line numbers
    }
  ],
  "sections": {
    "mechanism": false,               // true when mechanism.html exists
    "fromPr": false,                  // true when from-pr.html exists
    "extra": [                        // zero or more, rendered between verification and follow-up
      { "id": "scripts", "en": "Does scripts/ need updating?", "l2": null, "fragment": "extra-scripts.html" }
    ]
  },
  "statTiles": [
    { "n": "7", "tone": "grey", "en": "files changed", "l2": null }   // tone: grey | ok | warn | bad
  ],
  "redact": [                         // optional. Applied to embedded file text by the build, and by the check before comparing with git
    { "pattern": "\\b\\d{12}\\.dkr\\.ecr", "flags": "g", "replacement": "[REDACTED].dkr.ecr" }
  ],
  "labels": {                         // every field optional
    "wsEn": "Ignore whitespace-only changes",
    "wsL2": null,
    "wsTag": "ws",
    "diffHeadEn": null,               // default "<baseRef> (<baseShort>) → PR #<N> (<headShort>)"
    "diffHeadL2": null
  }
}
```

Rules the build enforces:

- Every `blocks[].key` is unique and matches `^[a-z0-9-]+$`.
- Every `fileIndex` exists in `meta.files`. Binary files cannot be blocks.
- Every `kinds[]` entry exists in `kinds`. Every `group` exists in `groups`.
- Every fragment named in the manifest exists. Required fragments always exist.
- `langMode: "single"` with `lang2: null` fails if any fragment contains `class="l2"`.
- `range` line numbers are 1-based and inclusive. `before` may be `[0, 0]` for an added file, `after` may be `[0, 0]` for a deleted file.
- `palette.name` must be a key of `assets/palettes.json` and cannot be combined with the four colour values. Without `name`, all four colour values are required.

## Fragments

All fragments live in `<workdir>/content/`. Required: `header-lede.html`, `findings.html`, `changes-intro.html`, `verification.html`, `followup.html`, `footer.html`. Optional: `mechanism.html`, `from-pr.html`, `group-<key>.html`, `block-<key>.html`, `extra-<id>.html`.

Fragments are HTML snippets, not documents. No `<html>`, `<head>`, `<style>`, `<script>`, no `style=` attributes, no hex colours. Use only the idioms below, the CSS for them already exists.

### Two language idioms

Block-level text uses sibling elements:

```html
<p class="en">The key fetch could fail without failing the build.</p>
<p class="l2">키 가져오기가 빌드를 실패시키지 않고 실패할 수 있었습니다.</p>
```

Headings, chips, labels, and table cells use nested spans:

```html
<h3><span class="en">Three cleanups ran in the wrong layer</span><span class="l2">정리 세 개가 잘못된 레이어에서 실행됐습니다</span></h3>
```

English-only pages use neither class on text. Just write the element.

### header-lede.html

One or two `<p class="lede">` paragraphs (with `en`/`l2` when bilingual). What changes, why, how the page is organised. The `h1` comes from the manifest `title`, so do not repeat it here.

### findings.html

Two to five cards:

```html
<div class="finding">
  <div class="bar fix" aria-hidden="true"></div>
  <div>
    <span class="kind fix" data-glyph="◆">Fix</span>
    <h3>The Adoptium key fetch could fail without failing the build</h3>
    <p>A pipeline reports the last command's exit status, so a failed <code>curl</code> left a 0-byte key and <code>set -e</code> saw success. The PR writes the file with <code>-o</code> instead.</p>
  </div>
</div>
```

The kind class and `data-glyph` must match the manifest. The build validates them.

### mechanism.html (optional)

A `.section-head` is generated. Provide the figure:

```html
<div class="figure">
  <svg viewBox="0 0 880 300" width="100%" role="img" aria-labelledby="fig-title">
    <title id="fig-title">Before and after: where the cleanup layer sits</title>
    <!-- use classes .ly .ly-base .ly-plain .ly-soft .ly-good .ly-bad, text.lbl text.mono text.tag -->
  </svg>
  <p class="caption">One sentence tying the figure to the change.</p>
</div>
```

### changes-intro.html

One `<p class="sub">` naming what the diffs compare. The build already prints base and head in each diff header, so keep this to how the blocks are organised.

### group-<key>.html (optional, one per group that needs a Why)

```html
<div class="callout" role="note">
  <div class="bar" aria-hidden="true"></div>
  <div>
    <h3>Why these four files change</h3>
    <ul>
      <li><strong>One RUN for install and cleanup.</strong> Reason in one sentence.</li>
    </ul>
    <div class="effect" role="table" aria-label="Before and after for this group">
      <div class="h"></div><div class="h">Before</div><div class="h">After</div>
      <div class="k" data-label="layers writing packages">layers writing packages</div>
      <div class="v was">install, temurin, purge (whiteout)</div>
      <div class="v now">one layer</div>
    </div>
  </div>
</div>
```

Rows are triples: `.k` then two `.v`. Use `.v.was` and `.v.now` for changed rows, `<span class="same">unchanged</span>` inside plain `.v` for unchanged rows, `<span class="src">(PR)</span>` after a value that comes from the PR.

### block-<key>.html (optional)

One or more `<p class="note">` lines shown above the diff. Use it for "representative for this group", a redaction notice, or a skipped binary. New and deleted files are labelled by the build.

### from-pr.html (optional)

```html
<div class="quote">
  <div class="bar" aria-hidden="true"></div>
  <div class="q-body">
    <div class="label">Quoted from the PR description, not reproduced here</div>
    <blockquote cite="https://github.com/owner/repo/pull/123">
      <p>Verbatim paragraph.</p>
      <pre>verbatim code block</pre>
    </blockquote>
    <p class="summary l2"><span class="tag">요약</span> Second-language summary when bilingual.</p>
  </div>
</div>
```

### verification.html

```html
<div class="checks">
  <div class="check-row">
    <div class="ic pass" aria-label="passed">✓</div>
    <div>
      <div class="t">ENV lines are untouched</div>
      <p>What was checked and how, in one or two sentences.</p>
      <pre>git --no-pager diff 1d75197 fdbfa95 | grep -E '^[+-]ENV '</pre>
    </div>
  </div>
  <div class="check-row">
    <div class="ic skip" aria-label="not run">–</div>
    <div>
      <div class="t">Image build and size measurement</div>
      <p>Not run here. Figures are quoted from the PR.</p>
    </div>
  </div>
</div>
```

### extra-<id>.html (optional)

Any of the idioms above. The build adds the section heading from the manifest. Close with a `.callout` verdict when the section answers a question.

### followup.html

```html
<div class="lists">
  <div>
    <div class="tagline">From the PR</div>
    <ul><li>…</li></ul>
  </div>
  <div>
    <div class="tagline">Noticed while checking, not caused by this PR</div>
    <ul><li>…</li></ul>
  </div>
</div>
```

### footer.html

One `<p>` per language: source of truth (base and head shas, PR link), what was not reproduced, where the page lives.
