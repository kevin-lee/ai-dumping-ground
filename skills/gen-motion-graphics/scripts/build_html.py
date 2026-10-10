"""Assemble the standalone motion-graphics HTML from the engine template and the scene files.

Everything is inlined (fonts, word timings, mix data, audio), so the page needs no other file:

  python3 build_html.py --video build/video.json --mix build/mix.json --timings build/timings.json \
      --audio build/master.mp3 --scenes build/scenes --out output/<slug>.html

--scenes is a folder with scenes.html, scenes.css and scenes.js (see references/engine-api.md).
video.json holds the page settings; paths in it are relative to video.json:

  {
    "title": "AI Skills Intro",
    "lang": "en",
    "poster": 19.2,
    "fadeOut": 1.5,
    "captions": {"maxWords": 6, "maxChars": 42},
    "fonts": [
      {"family": "Inter", "file": "fonts/inter.woff2", "weight": "100 900", "role": "ui"},
      {"family": "JetBrains Mono", "file": "fonts/jetbrains-mono.woff2", "weight": "100 800", "role": ["mono"]}
    ]
  }

--audio-url NAME makes a page for a website instead: the audio is copied next to the page and only
fetched when Play is pressed, so the page itself stays small.
"""

import argparse
import base64
import json
import re
import shutil
import sys
from pathlib import Path

SKILL_DIR = Path(__file__).resolve().parent.parent
DEFAULT_TEMPLATE = SKILL_DIR / "assets" / "template.html"
FALLBACK = {
    "ui": 'ui-sans-serif, system-ui, -apple-system, "Segoe UI", sans-serif',
    "mono": "ui-monospace, Menlo, Consolas, monospace",
    "display": "var(--font-ui)",
}
# The template's Content Security Policy blocks every request the page makes. This check stops such references at
# build time, and it also catches what the policy cannot block: leaving the page for another address.
EXTERNAL = re.compile(
    r"""(<link\b|<meta\b|@import\b|\b(?:src|href)\s*=\s*["']?(?:https?:)?//|url\(\s*["']?(?:https?:)?//"""
    r"""|\blocation\s*(?:\.href\s*)?=(?!=)|\blocation\.(?:assign|replace)\s*\(|\bwindow\.open\s*\()""",
    re.I,
)


def b64(path: Path) -> str:
    return base64.b64encode(path.read_bytes()).decode("ascii")


def js_json(value) -> str:
    # "<" is escaped so no string inside the data can close the <script> element.
    return json.dumps(value, ensure_ascii=False, separators=(",", ":")).replace("<", "\\u003c")


def font_css(fonts: list[dict], base: Path) -> tuple[str, str]:
    faces, roles, families = [], {}, []
    for f in fonts:
        path = (base / f["file"]).resolve()
        if not path.exists():
            sys.exit(f"font file not found: {path}")
        fmt = {".woff2": "woff2", ".woff": "woff", ".ttf": "truetype", ".otf": "opentype"}[path.suffix.lower()]
        mime = {"woff2": "font/woff2", "woff": "font/woff", "truetype": "font/ttf", "opentype": "font/otf"}[fmt]
        faces.append(
            "@font-face {\n"
            f'  font-family: "{f["family"]}";\n'
            f'  src: url(data:{mime};base64,{b64(path)}) format("{fmt}");\n'
            f'  font-weight: {f.get("weight", "100 900")};\n'
            f'  font-style: {f.get("style", "normal")};\n'
            "  font-display: block;\n"
            "}"
        )
        if f["family"] not in families:
            families.append(f["family"])
        role = f.get("role", [])
        for r in [role] if isinstance(role, str) else role:
            if r in FALLBACK and r not in roles:
                roles[r] = f["family"]
    # A character missing from one embedded font comes from another before a system font: Inter has no ❯ or ▌
    # (the typing caret), JetBrains Mono no ✓ or ⏎. Each subset keeps the same characters, so the other one has it.
    stack = lambda first, r: ", ".join([f'"{first}"'] + [f'"{x}"' for x in families if x != first] + [FALLBACK[r]])
    variables = "\n".join(f"  --font-{r}: {stack(fam, r)};" for r, fam in roles.items())
    return "\n".join(faces), variables


def fill(template: str, values: dict[str, str]) -> str:
    # One pass, so text inside an inserted value is never mistaken for another placeholder.
    def swap(m: re.Match) -> str:
        key = m.group(1)
        return values[key] if key in values else m.group(0)

    filled = re.sub(r"__([A-Z][A-Z_]*[A-Z])__", swap, template)
    left = sorted(set(re.findall(r"__([A-Z][A-Z_]*[A-Z])__", template)) - set(values))
    if left:
        sys.exit(f"template placeholders without a value: {left}")
    return filled


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--video", type=Path, required=True, help="video.json with title, lang, poster, captions, fonts")
    ap.add_argument("--mix", type=Path, required=True, help="mix.json written by mix_audio.py")
    ap.add_argument("--timings", type=Path, required=True, help="timings.json written by make_timings.py")
    ap.add_argument("--audio", type=Path, required=True, help="mastered audio to embed (mp3)")
    ap.add_argument("--scenes", type=Path, required=True, help="folder with scenes.html, scenes.css, scenes.js")
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--template", type=Path, default=DEFAULT_TEMPLATE)
    ap.add_argument("--audio-url", help="reference the audio by this file name next to the page instead of inlining it")
    a = ap.parse_args()

    video = json.loads(a.video.read_text(encoding="utf-8"))
    mix = json.loads(a.mix.read_text(encoding="utf-8"))
    timings = json.loads(a.timings.read_text(encoding="utf-8"))
    scenes = {ext: (a.scenes / f"scenes.{ext}").read_text(encoding="utf-8") for ext in ("html", "css", "js")}
    if re.search(r"</script", scenes["js"], re.I):
        sys.exit("scenes.js contains '</script'; write it as '<\\/script' so the page does not break")
    for name, text in scenes.items():
        if m := EXTERNAL.search(text):
            sys.exit(f"scenes.{name} loads or opens something outside the page ({m.group(0)}); inline resources as data: URLs and never leave the page")

    config = {k: v for k, v in video.items() if k not in ("fonts",)}
    config["duration"] = video.get("duration", mix["duration"])
    for key in ("music", "narration"):
        if key in mix and mix[key] is not None:
            config[key] = mix[key]
    faces, font_vars = font_css(video.get("fonts", []), a.video.parent)

    if a.audio_url:
        src, preload = a.audio_url, "none"
    else:
        mime = {".mp3": "audio/mpeg", ".m4a": "audio/mp4", ".aac": "audio/aac", ".ogg": "audio/ogg", ".opus": "audio/ogg", ".wav": "audio/wav"}[a.audio.suffix.lower()]
        src, preload = f"data:{mime};base64,{b64(a.audio)}", "auto"

    html = fill(
        a.template.read_text(encoding="utf-8"),
        {
            "LANG": video.get("lang", "en"),
            "TITLE": video.get("title", "Motion graphics").replace("<", "&lt;"),
            "FONT_FACES": faces,
            "FONT_VARS": font_vars,
            "SCENES_CSS": scenes["css"],
            "SCENES_HTML": scenes["html"],
            "SCENES_JS": scenes["js"],
            "VIDEO": js_json(config),
            "TIMINGS": js_json(timings),
            "AUDIO_SRC": src,
            "AUDIO_PRELOAD": preload,
        },
    )
    a.out.parent.mkdir(parents=True, exist_ok=True)
    a.out.write_text(html, encoding="utf-8")
    print(f"{a.out} ({a.out.stat().st_size / 1e6:.2f} MB, {config['duration']:.2f} s, {len(timings)} words)")
    if a.audio_url:
        dst = a.out.parent / a.audio_url
        shutil.copyfile(a.audio, dst)
        print(f"{dst} ({dst.stat().st_size / 1e6:.2f} MB)")


if __name__ == "__main__":
    main()
