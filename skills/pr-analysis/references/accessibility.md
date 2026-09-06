# Accessibility checklist

The template satisfies the items marked (template). The items marked (fragments) are yours to keep when you write content. The check script verifies the static ones.

## Template

- Skip link as the first focusable element, landing on `main#main` (template).
- One polite live region `#announce` that reports view, width, wrap, whitespace, show whole file, syntax colors, revealed lines, theme, CVD, palette, sidebar, text size, and expand or collapse changes (template).
- Every icon button has visible or `aria-label` text, and its tooltip is also shown on keyboard focus (template).
- Segmented controls are `role="group"` with `aria-labelledby`, each button carries `aria-pressed` (template).
- The floating table of contents is a `role="dialog"` that receives focus on open, traps Tab while open, closes on Escape, and returns focus to its button (template).
- Keyboard shortcuts are listed in `dialog#help`, opened with `?`, and never fire while typing in an input (template).
- `prefers-reduced-motion` disables transitions and smooth scrolling (template).
- `forced-colors: active` keeps borders on blocks, chips, controls, and search hits (template).
- Diff rows carry `+` or `−` in the sign cell and a visually hidden "added" or "removed" word for screen readers (template).
- Color is never the only signal: kind chips and TOC dots show a glyph, status pips show a glyph, stat tiles carry a label (template).
- Second-language elements get `lang="<code>"` from the build so screen readers switch voice (template).
- The text size panel is a non-modal `role="dialog"` inside the sticky top bar, opened from a labeled button that carries `aria-expanded` and `aria-controls`. Focus moves to the slider on open and back to the button on close, Escape closes it only while focus is inside, it never traps Tab, and the slider exposes its value in pixels through `aria-valuetext` (template).
- The color palette panel is a non-modal `role="dialog"` inside the sticky top bar, opened from a labeled button that carries `aria-expanded` and `aria-controls`. Its swatches are buttons with visible names and `aria-pressed`, the color dot is decorative, focus moves to the pressed swatch on open and back to the button on close, Escape closes it only while focus is inside, it never traps Tab, and the chosen palette is announced through the live region (template).
- A block with text on one side only says "New file", "Deleted file", "Inserted lines", or "Removed lines" in the diff head in both views, and the side by side view shows a 46px hatched stub for the absent side instead of an empty pane (template).
- Hidden context sits behind an expander row whose buttons are real buttons with visible text, an `aria-label` that names the line they start from, and focus that stays on the equivalent button after the block re-renders, or moves to the diff container when the gap is gone. The number of revealed lines is announced (template).
- The show whole file and syntax colors toggles are labeled checkboxes in the sidebar and `aria-pressed` icon buttons in the compact strip, with the same persistence and announcement as the other toggles (template).

## Fragments

- Headings stay in order. Sections start at `h2`, blocks and cards use `h3`, never skip a level inside a fragment.
- Link text says where the link goes. Never "here", "this", or a bare URL as text unless the URL is the point.
- Tables get a `<caption>` or an `aria-label` that says what the table compares.
- Inline SVG gets `role="img"` and a `<title>` with an `id` referenced by `aria-labelledby`. Decorative SVG gets `aria-hidden="true"`.
- A `<pre>` block is introduced by a sentence that says what it shows, so a listener knows what the code is before hearing it.
- Never rely on color words alone ("the red rows"). Name the thing ("the removed lines").
- Do not add `tabindex`, `role`, or ARIA attributes in fragments unless this checklist asks for them. The template already wires the interactive parts.
- Keep the kind chip on every finding and block so the category is announced.
- The step flow is an ordered list, the before and after pair is two labeled columns, and the bar list carries its meaning in the label and value text, the bar itself is `aria-hidden`. Tone classes are never the only signal.
- Every figure has a caption sentence.
