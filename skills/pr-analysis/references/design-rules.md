# Design rules

The template already carries the layout, typography scale, theme handling, and interaction. What you decide per report is the palette, the font pairing, and the words. These rules keep those decisions consistent so a reader who has seen one report knows how to read the next.

## Palette

Four inputs drive every colour on the page. The template derives ground, surfaces, lines, and soft tints from them with `color-mix()`, so you never hand-tune the rest.

| Input | Meaning |
|---|---|
| `accentLight` | Accent for links, controls, active states on the light theme. Needs at least 4.5:1 contrast on `paperLight`. |
| `accentDark` | The same role on the dark theme. A lighter, less saturated version of the light accent. |
| `paperLight` | The page ground in light mode. Off-white with a faint tint, never pure white, never a saturated colour. The page should feel like paper. |
| `paperDark` | The page ground in dark mode. Near-black with the same tint direction. |

### Named pastel set

Pick one at random when the user says "Pick a pastel for me". State which one you picked in the completion message.

| Name | accentLight | accentDark | paperLight | paperDark |
|---|---|---|---|---|
| lavender | `#6B5BB5` | `#B9AEF2` | `#FBFAF7` | `#16161D` |
| sage | `#4F7F5C` | `#9FD1AC` | `#F9FAF6` | `#141814` |
| sky | `#3B6FA8` | `#9CC3EE` | `#F7F9FB` | `#13171D` |
| peach | `#B85F3A` | `#F0AE8E` | `#FBF8F5` | `#1B1614` |
| sand | `#8A6D2F` | `#DCC08A` | `#FBF9F3` | `#191712` |
| rose | `#A64D6E` | `#EFA6BF` | `#FBF7F8` | `#1A1417` |

Random pick without thinking about it:

```
node -e 'const p=["lavender","sage","sky","peach","sand","rose"];console.log(p[Math.floor(Math.random()*p.length)])'
```

### From a colour brief

When the user describes what they want, translate the words:

- Colour words name the accent. Pick a mid-tone for light (`blue` `#2F6FB5`, `green` `#3E7F58`, `teal` `#0F766E`, `purple` `#5B3FA3`, `orange` `#B85F3A`, `red` `#A63A3A`, `pink` `#A64D6E`, `brown` `#7A5A3A`, `grey` `#5B6170`) and a lighter tint of the same hue for dark.
- Ground words name the paper. "Solarized light" is `#FDF6E3` with dark `#002B36`. "Cream" or "warm" is `#FBF7EE` with dark `#1B1712`. "Cool" or "blue-grey" is `#F5F7FA` with dark `#13161C`. "Paper" or "neutral" is `#FAFAF7` with dark `#161616`.
- Solarized light worked example: paper `#FDF6E3`, dark paper `#002B36`, accent `#268BD2` light and `#83C2F0` dark. Note that Solarized blue on Solarized paper is just under 4.5:1, so darken the light accent to `#1F6FB0` unless the user asked for the exact Solarized values.
- If the brief names a controls colour and a ground colour separately, that is exactly the accent and paper split.

Contrast check for a candidate pair (WCAG relative luminance):

```
node -e '
const L=h=>{const c=h.replace("#","").match(/../g).map(x=>parseInt(x,16)/255).map(v=>v<=.03928?v/12.92:((v+.055)/1.055)**2.4);return .2126*c[0]+.7152*c[1]+.0722*c[2]};
const [a,b]=process.argv.slice(1);const r=(Math.max(L(a),L(b))+.05)/(Math.min(L(a),L(b))+.05);console.log(r.toFixed(2))' "#1F6FB0" "#FDF6E3"
```

Aim for 4.5 or more for accent on paper in both themes.

## Fonts

Rotate between three pairings so consecutive reports do not look identical. Always declare the fallback stack, the page must read correctly offline.

| Display | Body | Mono |
|---|---|---|
| Archivo 500 600 700 | IBM Plex Sans 400 500 600 italic 400 | IBM Plex Mono 400 500 |
| Manrope 600 700 800 | Source Sans 3 400 500 600 italic 400 | JetBrains Mono 400 500 |
| Fraunces 600 700 | Public Sans 400 500 600 italic 400 | Fira Code 400 500 |

`fontsHref` for the second pairing, as an example:

```
https://fonts.googleapis.com/css2?family=Manrope:wght@600;700;800&family=Source+Sans+3:ital,wght@0,400;0,500;0,600;1,400&family=JetBrains+Mono:wght@400;500&display=swap
```

Font stacks to put in the manifest:

- display: `"Archivo", "Helvetica Neue", Arial, sans-serif` (swap the first name)
- body: `"IBM Plex Sans", "Segoe UI", Roboto, Helvetica, Arial, sans-serif`
- mono: `"IBM Plex Mono", ui-monospace, SFMono-Regular, Menlo, Consolas, monospace`

## Kinds and tones

Kinds are the two to four categories of change on this page (for example `fix`, `silence`, `hygiene`). Each maps to a semantic tone that already has light, dark, and CVD values in the template:

| Tone | Use for |
|---|---|
| `ok` | Improvements, reclaimed resources, things that now work |
| `warn` | Behaviour changes a reader should notice, trade-offs |
| `alert` | Failures that were possible before, risk, silent errors |
| `nodata` | Hygiene, renames, formatting, no behaviour change |
| `accent` | The page's main theme when none of the above fits |

Each kind also carries a glyph from `◆ ▲ ● ■ ✚ ✦ ⬟ ✱`. The glyph is shown before the chip label and in the table of contents, so the category survives without colour. Do not reuse a glyph for two kinds on one page.

## Fundamentals the template relies on

- Every colour comes from a token. Fragments never contain hex values or `style=` colours.
- Both themes are designed, not one. If you add an SVG, colour it with the `.figure` classes so it follows the theme and the CVD toggle.
- Running text stays near 65 characters wide. The `p` and `li` rules already cap width.
- Digits that line up use `font-variant-numeric: tabular-nums`, which the stat tiles and diff counts already have.
- Structure encodes meaning. Numbered lists only for real sequences. Section eyebrows only when they say something true.
- Wide content (tables, code, diagrams) sits inside a container with `overflow-x: auto`. Use `.table-scroll` around tables.
- The page must read at rest. No content hidden until scroll or hover.
