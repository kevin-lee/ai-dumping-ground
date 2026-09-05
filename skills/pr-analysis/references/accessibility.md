# Accessibility checklist

The template satisfies the items marked (template). The items marked (fragments) are yours to keep when you write content. The check script verifies the static ones.

## Template

- Skip link as the first focusable element, landing on `main#main` (template).
- One polite live region `#announce` that reports view, width, wrap, whitespace, theme, CVD, sidebar, text size, and expand or collapse changes (template).
- Every icon button has visible or `aria-label` text, and its tooltip is also shown on keyboard focus (template).
- Segmented controls are `role="group"` with `aria-labelledby`, each button carries `aria-pressed` (template).
- The floating table of contents is a `role="dialog"` that receives focus on open, traps Tab while open, closes on Escape, and returns focus to its button (template).
- Keyboard shortcuts are listed in `dialog#help`, opened with `?`, and never fire while typing in an input (template).
- `prefers-reduced-motion` disables transitions and smooth scrolling (template).
- `forced-colors: active` keeps borders on blocks, chips, controls, and search hits (template).
- Diff rows carry `+` or `−` in the sign cell and a visually hidden "added" or "removed" word for screen readers (template).
- Colour is never the only signal: kind chips and TOC dots show a glyph, status pips show a glyph, stat tiles carry a label (template).
- Second-language elements get `lang="<code>"` from the build so screen readers switch voice (template).
- The text size panel is a non-modal `role="dialog"` inside the sticky top bar, opened from a labelled button that carries `aria-expanded` and `aria-controls`. Focus moves to the slider on open and back to the button on close, Escape closes it only while focus is inside, it never traps Tab, and the slider exposes its value in pixels through `aria-valuetext` (template).
- A block with text on one side only says "New file", "Deleted file", "Inserted lines", or "Removed lines" in the diff head in both views, and the side by side view shows a 46px hatched stub for the absent side instead of an empty pane (template).

## Fragments

- Headings stay in order. Sections start at `h2`, blocks and cards use `h3`, never skip a level inside a fragment.
- Link text says where the link goes. Never "here", "this", or a bare URL as text unless the URL is the point.
- Tables get a `<caption>` or an `aria-label` that says what the table compares.
- Inline SVG gets `role="img"` and a `<title>` with an `id` referenced by `aria-labelledby`. Decorative SVG gets `aria-hidden="true"`.
- A `<pre>` block is introduced by a sentence that says what it shows, so a listener knows what the code is before hearing it.
- Never rely on colour words alone ("the red rows"). Name the thing ("the removed lines").
- Do not add `tabindex`, `role`, or ARIA attributes in fragments unless this checklist asks for them. The template already wires the interactive parts.
- Keep the kind chip on every finding and block so the category is announced.
