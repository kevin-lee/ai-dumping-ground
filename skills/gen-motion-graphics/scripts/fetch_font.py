# /// script
# requires-python = ">=3.12"
# dependencies = ["fonttools>=4.60", "brotli"]
# ///
"""Download an open-licensed font family from Google Fonts' GitHub repository and subset it to the
characters the video uses, as small woff2 files ready to embed in the standalone page.

Usage:
  uv run --script fetch_font.py "JetBrains Mono" build/fonts --text build/scenes build/timings.json
  uv run --script fetch_font.py "Noto Sans KR" build/fonts --text build/scenes build/timings.json --role ui

--text takes files or folders; every character in them is kept, plus printable ASCII and common
symbols, so dynamic text (numbers, arrows, ticks) still renders. Re-run it after editing the scenes.
Prints the "fonts" entries to paste into video.json. Downloads are cached in
~/.cache/gen-motion-graphics/fonts. Family names are the ones shown on fonts.google.com.
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont

CACHE = Path.home() / ".cache" / "gen-motion-graphics" / "fonts"
API = "https://api.github.com/repos/google/fonts/contents/{lic}/{slug}"
EXTRA = "–—…‘’“”•·→←↑↓↗✓✔✗✕❯›‹«»▌█▲▼●○◉◯■□★☆♪⌘⏎€£¥©®™°±×÷≈≠≤≥"
TEXT_EXT = {".html", ".css", ".js", ".json", ".txt", ".md", ".srt", ".vtt"}


def fetch(url: str) -> bytes:
    headers = {"User-Agent": "gen-motion-graphics", "Accept": "application/vnd.github+json"}
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    if token and "api.github.com" in url:
        headers["Authorization"] = f"Bearer {token}"
    with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=60) as r:
        return r.read()


def list_dir(lic: str, slug: str) -> list[dict] | None:
    """Directory listing from the GitHub API: through an authenticated gh when available (5000 requests an
    hour), otherwise anonymously (60 an hour, shared by everything on this machine)."""
    path = f"repos/google/fonts/contents/{lic}/{slug}"
    if shutil.which("gh"):
        r = subprocess.run(["gh", "api", path], capture_output=True, text=True)
        if r.returncode == 0:
            return json.loads(r.stdout)
        if "Not Found" in r.stdout + r.stderr:
            return None
    try:
        return json.loads(fetch(API.format(lic=lic, slug=slug)))
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None
        if e.code == 403:
            sys.exit("GitHub's anonymous rate limit is used up. Run `gh auth login`, set GITHUB_TOKEN, or try again in an hour.")
        raise


def cached(family: str) -> list[dict]:
    """Files of this family downloaded earlier, so a re-run needs no network."""
    stem = re.sub(r"[^A-Za-z0-9]", "", family)
    hits = sorted(p for p in CACHE.glob(f"{stem}*") if p.suffix.lower() in (".ttf", ".otf") and "italic" not in p.name.lower()
                  and re.match(rf"{re.escape(stem)}(\[|-|\.)", p.name))
    return [{"name": p.name, "download_url": None} for p in hits]


def family_files(family: str) -> list[dict]:
    local = cached(family)
    if any("[" in f["name"] for f in local):
        return local
    slug = re.sub(r"[^a-z0-9]", "", family.lower())
    for lic in ("ofl", "apache", "ufl"):
        items = list_dir(lic, slug)
        if not items:
            continue
        fonts = [i for i in items if i["name"].lower().endswith((".ttf", ".otf")) and "italic" not in i["name"].lower()]
        if fonts:
            return fonts
    if local:
        return local
    sys.exit(f'"{family}" was not found in github.com/google/fonts (tried ofl/, apache/, ufl/{slug})')


def chars(paths: list[Path]) -> str:
    seen = set(chr(c) for c in range(0x20, 0x7F)) | set(EXTRA)
    for p in paths:
        files = [f for f in p.rglob("*") if f.suffix.lower() in TEXT_EXT] if p.is_dir() else [p]
        for f in files:
            text = f.read_text(encoding="utf-8", errors="ignore")
            seen |= set(text)
            seen |= {chr(int(h, 16)) for h in re.findall(r"\\u([0-9a-fA-F]{4})", text)}
    return "".join(sorted(c for c in seen if c.isprintable()))


def weight_of(font: TTFont) -> str:
    if "fvar" in font:
        for ax in font["fvar"].axes:
            if ax.axisTag == "wght":
                return f"{int(ax.minValue)} {int(ax.maxValue)}"
    return str(font["OS/2"].usWeightClass)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("family")
    ap.add_argument("out_dir", type=Path)
    ap.add_argument("--text", type=Path, nargs="+", required=True)
    ap.add_argument("--role", default=None, help="ui, mono or display (default: mono for mono families, else ui)")
    ap.add_argument("--weights", default="400,500,600,700,800", help="static families only: weights to keep")
    a = ap.parse_args()

    files = family_files(a.family)
    variable = [f for f in files if "[" in f["name"]]
    if variable:
        chosen = variable[:1]
    else:
        want = {int(w) for w in a.weights.split(",")}
        chosen = []
        for f in files:
            path = CACHE / f["name"]
            if not path.exists():
                CACHE.mkdir(parents=True, exist_ok=True)
                path.write_bytes(fetch(f["download_url"]))
            if TTFont(path, lazy=True)["OS/2"].usWeightClass in want:
                chosen.append(f)
    if not chosen:
        sys.exit(f"no usable font files for {a.family}")

    text = chars(a.text)
    a.out_dir.mkdir(parents=True, exist_ok=True)
    role = a.role or ("mono" if "mono" in a.family.lower() or "code" in a.family.lower() else "ui")
    entries = []
    for f in chosen:
        src = CACHE / f["name"]
        if not src.exists():
            CACHE.mkdir(parents=True, exist_ok=True)
            src.write_bytes(fetch(f["download_url"]))
        font = TTFont(src)
        weight = weight_of(font)
        opts = subset.Options()
        opts.flavor = "woff2"
        opts.layout_features = ["*"]
        opts.name_IDs = ["*"]
        opts.notdef_outline = True
        sub = subset.Subsetter(opts)
        sub.populate(text=text)
        sub.subset(font)
        stem = re.sub(r"[^A-Za-z0-9]+", "-", Path(f["name"]).stem).strip("-")
        dst = a.out_dir / f"{stem}-subset.woff2"
        font.flavor = "woff2"
        font.save(dst)
        missing = [c for c in text if ord(c) > 0x7F and ord(c) not in TTFont(src).getBestCmap()]
        print(f"{dst} ({dst.stat().st_size / 1024:.0f} KB, weight {weight}, {len(text)} characters)")
        if missing:
            print(f"  not in this font: {''.join(missing[:80])} (the page takes them from the video's other embedded font when it has them, else from a system font)")
        entries.append({"family": a.family, "file": str(dst), "weight": weight, "role": role})
    print("video.json fonts entries (make file paths relative to video.json):")
    print(json.dumps(entries, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
