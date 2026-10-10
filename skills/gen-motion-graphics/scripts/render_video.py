# /// script
# requires-python = ">=3.12"
# dependencies = ["playwright>=1.55"]
# ///
"""Render the standalone motion-graphics HTML to video, frame by frame, with Google Chrome.

The page exposes window.renderAt(t), so every frame is drawn at an exact time and the result does not
depend on machine speed. The timeline is split across parallel browser workers, each encoding its
own H.264 segment; the segments are joined without re-encoding and the audio is added.

Check (seconds, no screenshots): runs renderAt over the whole timeline and reports script errors,
text that overflows its box, and visible elements that collide with the captions or the frame edge.
It also measures the motion: how many elements enter per second, and the longest stretch in which
nothing new appears (no element entering, no text changing, no cut, ring or flash). And it lists text that
looks like a key, password or token, on screen, in the captions or anywhere in the page source (then it
exits with 1).
  uv run --script render_video.py page.html --check
Stills for review (auto = the middle of every scene plus just after every cut), with contact sheets of
four stills each (sheet-01.png, ...), so a review needs a quarter of the image views:
  uv run --script render_video.py page.html --stills auto --out-dir stills/ [--debug]
  uv run --script render_video.py page.html --stills 3,16.5,40 --out-dir stills/
Video:
  uv run --script render_video.py page.html --audio master.wav --out video.mp4
Preview of one part: add --from 20 --to 30.
Sound effects the scenes declare (sfx(), plus the automatic ones for cuts, flashes and rings), for mix_audio.py --sfx:
  uv run --script render_video.py page.html --export-sfx sfx.json
Options: --fps 60, --scale 1 (2 renders 3840x2160), --workers N, --crf 17, --maxrate 24 (Mbit/s cap,
         80 at 4K, 0 = none), --no-captions, --format png|jpeg (jpeg is faster and slightly softer)
"""

import argparse
import base64
import json
import multiprocessing as mp
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

from playwright.sync_api import sync_playwright

W, H = 1920, 1080

LINT_JS = r"""
(t) => {
  renderAt(t);
  const out = [];
  const stage = document.getElementById('stage');
  const capEl = document.querySelector('#cap .chunk[style*="visible"]');
  const cap = capEl ? capEl.getBoundingClientRect() : null;
  const effOpacity = el => {
    let o = 1;
    for (let e = el; e && e !== stage; e = e.parentElement) {
      const cs = getComputedStyle(e);
      if (cs.display === 'none' || cs.visibility === 'hidden') return 0;
      o *= parseFloat(cs.opacity);
    }
    return o;
  };
  const els = document.querySelectorAll('#scenes *');
  for (const el of els) {
    const own = [...el.childNodes].some(n => n.nodeType === 3 && n.textContent.trim());
    if (!own) continue;
    const r = el.getBoundingClientRect();
    if (r.width < 2 || r.height < 2) continue;
    if (effOpacity(el) < 0.9) continue;
    const label = (el.id ? '#' + el.id : el.tagName.toLowerCase() + (el.className && typeof el.className === 'string' ? '.' + el.className.split(' ')[0] : '')) + ' "' + el.textContent.trim().slice(0, 40) + '"';
    if (el.scrollWidth > el.clientWidth + 2 && getComputedStyle(el).overflow !== 'visible') out.push(['overflow', label]);
    if (r.left < 24 || r.right > 1896 || r.top < 16 || r.bottom > 1064) out.push(['edge', label]);
    if (cap && r.bottom > cap.top - 8 && r.top < cap.bottom && r.right > cap.left && r.left < cap.right) out.push(['captions', label]);
  }
  return out;
}
"""

# What is on screen at t, for the motion measure: [key, parent key, own text] of every visible element.
# Keys are paths from the nearest id, so an element re-created by innerHTML keeps its key.
SEEN_JS = r"""
(t) => {
  renderAt(t);
  const stage = document.getElementById('stage'), root = document.getElementById('scenes');
  const key = el => { const parts = []; for (let e = el; e && e !== root; e = e.parentElement) {
      if (e.id) { parts.push('#' + e.id); break; }
      parts.push(e.tagName + ':' + [...e.parentElement.children].indexOf(e)); }
    return parts.reverse().join('/'); };
  const out = [];
  for (const el of root.querySelectorAll('*')) {
    let o = 1;
    for (let e = el; e && e !== stage && o > 0; e = e.parentElement) {
      const cs = getComputedStyle(e);
      o = cs.display === 'none' || cs.visibility === 'hidden' ? 0 : o * parseFloat(cs.opacity);
    }
    if (o < 0.5) continue;
    const r = el.getBoundingClientRect();
    if (r.width < 4 || r.height < 4 || r.right < 0 || r.left > 1920 || r.bottom < 0 || r.top > 1080) continue;
    const own = [...el.childNodes].filter(n => n.nodeType === 3).map(n => n.textContent).join('').trim();
    out.push([key(el), el.parentElement === root ? '' : key(el.parentElement), own]);
  }
  return out;
}
"""

# The text a viewer can read at t: visible scene text, with inline runs joined so a token split across coloured
# spans stays whole, and the caption phrase on screen (all of it, its dimmed words too).
TEXT_JS = r"""
(t) => {
  renderAt(t);
  const stage = document.getElementById('stage'), op = new Map();
  const eff = el => {
    if (!el || el === stage) return 1;
    if (!op.has(el)) {
      const cs = getComputedStyle(el);
      op.set(el, cs.display === 'none' || cs.visibility === 'hidden' ? 0 : parseFloat(cs.opacity) * eff(el.parentElement));
    }
    return op.get(el);
  };
  const block = el => { while (el && getComputedStyle(el).display.startsWith('inline')) el = el.parentElement; return el; };
  let out = '', last = null;
  const walk = document.createTreeWalker(document.getElementById('scenes'), NodeFilter.SHOW_TEXT);
  for (let n = walk.nextNode(); n; n = walk.nextNode()) {
    if (!n.textContent.trim() || eff(n.parentElement) < .5) continue;
    const b = block(n.parentElement);
    out += (b === last ? '' : '\n') + n.textContent;
    last = b;
  }
  const cap = document.querySelector('#cap .chunk[style*="visible"]');
  return out + (cap ? '\n' + cap.textContent : '');
}
"""

# Text that looks like a key, password or token: well-known formats, and a long value after a word such as "password:".
SECRETS = [(name, re.compile(rx)) for name, rx in [
    ("private key", r"-----BEGIN [A-Z ]*PRIVATE KEY-----"),
    ("AWS access key", r"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b"),
    ("GitHub token", r"\b(?:gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{40,})"),
    ("Slack token", r"\bxox[abposr]-[A-Za-z0-9-]{10,}"),
    ("Slack webhook", r"hooks\.slack\.com/services/[A-Za-z0-9/]{20,}"),
    ("Google API key", r"\bAIza[0-9A-Za-z_-]{35}"),
    ("Atlassian API token", r"\bATATT[A-Za-z0-9_=-]{20,}"),
    ("API key", r"\bsk-(?=[A-Za-z0-9_-]*\d)[A-Za-z0-9_-]{32,}"),
    ("Stripe key", r"\b[rs]k_(?:live|test)_[0-9A-Za-z]{16,}"),
    ("npm token", r"\bnpm_[A-Za-z0-9]{36}\b"),
    ("JSON Web Token", r"\beyJ[A-Za-z0-9_-]{8,}\.eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}"),
    ("password in a URL", r"://[^/\s:@]+:([^/\s@]+)@"),
    ("credential", r"(?i)(?<![a-z])(?:password|passwd|pwd|secret|token|api[_-]?key|access[_-]?key|client[_-]?secret)"
                   r"[\"']?\s*[:=]\s*[\"']?([A-Za-z0-9._~+/=-]{12,})"),
    ("bearer token", r"(?i)\bbearer\s+([A-Za-z0-9._~+/=-]{16,})"),
]]
# A placeholder, an example or a variable, not a real value.
FAKE = re.compile(r"(?i)example|placeholder|redacted|dummy|your[-_]|xxxx|\*\*\*|0000|1234|abcd|\.env\b|environ|getenv|secrets\.")


def secrets(text: str) -> set[str]:
    """Text that looks like a key, password or token, described without printing it in full."""
    found, spans = set(), []
    for name, rx in SECRETS:
        for m in rx.finditer(text):
            g = m.lastindex or 0
            v = m.group(g)
            if any(a < m.end(g) and m.start(g) < b for a, b in spans):
                continue  # already reported in a more exact format above
            if name == "private key" or (len(set(v)) >= 8 and not FAKE.search(v)):
                spans.append(m.span(g))
                found.add(f'{name} "{v[:4] if len(v) >= 20 else v[:2]}…" ({len(v)} characters)')
    return found


def launch(p, scale: float):
    args = ["--force-color-profile=srgb", "--hide-scrollbars", "--disable-lcd-text"]
    try:
        browser = p.chromium.launch(channel="chrome", args=args)
    except Exception:
        browser = p.chromium.launch(args=args)  # bundled Chromium: `uv run --with playwright playwright install chromium`
    return browser, browser.new_page(viewport={"width": W, "height": H}, device_scale_factor=scale)


def open_page(p, html: Path, captions: bool, scale: float = 1, debug: bool = False):
    browser, page = launch(p, scale)
    errors: list[str] = []
    page.on("pageerror", lambda e: errors.append(str(e)))
    page.on("console", lambda m: errors.append(m.text) if m.type == "error" else None)
    page.set_default_timeout(120000)
    query = "?capture" + ("" if captions else "&captions=0") + ("&debug" if debug else "")
    page.goto(html.resolve().as_uri() + query)
    page.wait_for_function("typeof window.renderAt === 'function'", timeout=30000)
    page.evaluate("document.fonts.ready")
    if errors:
        browser.close()
        sys.exit("page errors:\n  " + "\n  ".join(errors))
    return browser, page, errors


def shot(cdp, fmt: str) -> bytes:
    params = {"format": fmt, "optimizeForSpeed": True, "captureBeyondViewport": False, "fromSurface": True}
    if fmt == "jpeg":
        params["quality"] = 95
    return base64.b64decode(cdp.send("Page.captureScreenshot", params)["data"])


def check(html: Path, step: float) -> None:
    with sync_playwright() as p:
        browser, page, errors = open_page(p, html, True)
        dur = page.evaluate("VIDEO.duration")
        scenes = page.evaluate("SCENE_LIST")
        marks = sorted(page.evaluate("[...CUT_LIST, ...RINGS.map(r => r[0]), ...FLASHES.map(f => f[0])]"))
        fade_out = float(page.evaluate("VIDEO.fadeOut ?? 1.5"))
        hits: dict[tuple[str, str], list[float]] = {}
        problems: dict[str, list[float]] = {}
        t, n = 0.0, 0
        shown: dict[str, str] = {}
        entrances, fresh = 0, []                 # fresh: (time, whether something new appeared since the last frame)
        texts: dict[str, list[float]] = {}       # what a viewer can read, with the times it is on screen
        while t <= dur:
            before = len(errors)
            try:
                for kind, label in page.evaluate(LINT_JS, t):
                    hits.setdefault((kind, label), []).append(round(t, 2))
                now = {k: (parent, text) for k, parent, text in page.evaluate(SEEN_JS, t)}
                entered = {k for k in now if k not in shown}
                entrances += sum(1 for k in entered if now[k][0] not in entered) if n else 0
                changed = any(text and k in shown and shown[k] != text for k, (_, text) in now.items())
                marked = any(t - step < m <= t for m in marks)
                fresh.append((t, bool(n) and (bool(entered) or changed or marked)))
                shown = {k: text for k, (_, text) in now.items()}
                texts.setdefault(page.evaluate(TEXT_JS, t), []).append(round(t, 2))
            except Exception as e:  # a script error at this time
                errors.append(str(e).splitlines()[0])
            for e in errors[before:]:
                problems.setdefault(e, []).append(round(t, 2))
            t += step
            n += 1
        browser.close()
    print(f"checked {n} frames over {dur:.2f}s, {len(scenes)} scenes")
    # Motion: the longest stretch without anything new, from the start to the closing fade-out.
    end = dur - fade_out
    points = [0.0] + [x for x, new in fresh if new and x < end] + [end]
    if len(points) >= 3:
        quiet, at = max((b - a, a) for a, b in zip(points, points[1:]))
        print(f"motion: {entrances} elements enter ({entrances / dur:.1f} per second); the longest stretch with nothing new "
              f"is {quiet:.2f}s, from {at:.2f}s")
        if quiet > 2.0:
            print(f"  note: nothing new on screen for {quiet:.2f}s from {at:.2f}s; the intro the user approved never went "
                  "past about 1.5s")
    order = sorted(scenes, key=lambda s: s["from"])
    for a, b in [(x["to"], y["from"]) for x, y in zip(order, order[1:]) if y["from"] - x["to"] > 0.5]:
        print(f"  note: no scene between {a:.2f}s and {b:.2f}s (only layers and the background show)")
    for e, ts in problems.items():
        print(f"  ERROR {e}  ({len(ts)}x, first at {ts[0]:.2f}s, last at {ts[-1]:.2f}s)")
    for (kind, label), ts in sorted(hits.items(), key=lambda kv: kv[1][0]):
        span = ts[-1] - ts[0] + step
        if kind != "overflow" and span < 0.6:   # brief contact while moving in or out is fine
            continue
        print(f"  {kind:8s} {label} at {ts[0]:.2f}-{ts[-1]:.2f}s")
    # Secrets on screen, in the captions, or anywhere in the page source (comments in scenes.js ship in the page too).
    # The page source is read without its base64 fonts and audio.
    found: dict[str, list[float]] = {}
    for text, ts in texts.items():
        for s in secrets(text):
            found.setdefault(s, []).extend(ts)
    for s in secrets(re.sub(r"data:[^,\s\"')]*;base64,[A-Za-z0-9+/=]+", "data:", html.read_text(encoding="utf-8"))):
        found.setdefault(s, [])
    for label, ts in sorted(found.items(), key=lambda kv: min(kv[1], default=1e9)):
        where = f"on screen at {min(ts):.2f}-{max(ts):.2f}s" if ts else "in the page source only, not on screen"
        print(f"  secret   {label} {where}")
    if problems or found:
        sys.exit(1)


def export_sfx(html: Path, out: Path) -> None:
    with sync_playwright() as p:
        browser, page, _ = open_page(p, html, True)
        events = page.evaluate("window.SFX_LIST || []")
        dur = page.evaluate("VIDEO.duration")
        browser.close()
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps({"duration": dur, "events": events}, indent=1))
    kinds: dict[str, int] = {}
    for e in events:
        kinds[e["kind"]] = kinds.get(e["kind"], 0) + 1
    print(f"{out}: {len(events)} sound effects ({', '.join(f'{v} {k}' for k, v in sorted(kinds.items())) or 'none'})")


def stills(html: Path, spec: str, out_dir: Path, captions: bool, scale: float, debug: bool) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    with sync_playwright() as p:
        browser, page, _ = open_page(p, html, captions, scale, debug)
        if spec == "auto":
            scenes = page.evaluate("SCENE_LIST")
            cuts = page.evaluate("CUT_LIST")
            times = sorted({round((s["from"] + s["to"]) / 2, 2) for s in scenes} | {round(c + 0.45, 2) for c in cuts})
        else:
            times = [float(x) for x in spec.split(",")]
        cdp = page.context.new_cdp_session(page)
        paths = []
        for t in times:
            page.evaluate(f"renderAt({t})")
            path = out_dir / f"t{t:07.2f}.png"
            path.write_bytes(shot(cdp, "png"))
            paths.append(path)
            print(path)
        browser.close()
    for sheet in sheets(paths, out_dir):
        print(sheet)


def sheets(paths: list[Path], out_dir: Path) -> list[Path]:
    """Contact sheets: four stills per image, 2 by 2 at half size, in time order."""
    for old in out_dir.glob("sheet-*.png"):
        old.unlink()
    out = []
    for n, i in enumerate(range(0, len(paths), 4), 1):
        group = paths[i:i + 4]
        args = [x for pth in group for x in ("-i", str(pth))]
        filt = [f"[{k}:v]scale={W // 2}:{H // 2}[v{k}]" for k in range(len(group))]
        filt += [f"color=c=black:s={W // 2}x{H // 2}:d=1[v{k}]" for k in range(len(group), 4)]
        filt.append("[v0][v1][v2][v3]xstack=inputs=4:layout=0_0|w0_0|0_h0|w0_h0[out]")
        dst = out_dir / f"sheet-{n:02d}.png"
        subprocess.run(["ffmpeg", "-v", "error", "-y", *args, "-filter_complex", ";".join(filt), "-map", "[out]",
                        "-frames:v", "1", str(dst)], check=True)
        out.append(dst)
    return out


def worker(k: int, html: str, start: int, end: int, fps: int, captions: bool, scale: float, fmt: str,
           seg: str, crf: int, preset: str, maxrate: float, done, failed) -> None:
    try:
        enc = subprocess.Popen(
            ["ffmpeg", "-v", "error", "-y", "-f", "image2pipe", "-framerate", str(fps), "-c:v", fmt if fmt == "png" else "mjpeg", "-i", "-",
             "-vf", "scale=out_color_matrix=bt709:out_range=tv,format=yuv420p,setparams=color_primaries=bt709:color_trc=bt709:colorspace=bt709:range=tv",
             "-c:v", "libx264", "-preset", preset, "-crf", str(crf), "-profile:v", "high", "-g", str(fps * 2),
             *(["-maxrate", f"{maxrate:g}M", "-bufsize", f"{2 * maxrate:g}M"] if maxrate > 0 else []),
             "-r", str(fps), seg],
            stdin=subprocess.PIPE,
        )
        with sync_playwright() as p:
            browser, page, _ = open_page(p, Path(html), captions, scale)
            cdp = page.context.new_cdp_session(page)
            for i in range(start, end):
                page.evaluate(f"renderAt({i / fps})")
                enc.stdin.write(shot(cdp, fmt))
                with done.get_lock():
                    done.value += 1
            browser.close()
        enc.stdin.close()
        if enc.wait() != 0:
            raise RuntimeError(f"ffmpeg failed for segment {k}")
    except Exception as e:  # report and let the parent stop
        print(f"worker {k}: {e}", file=sys.stderr, flush=True)
        failed.value = 1


def video(html: Path, audio: Path, out: Path, fps: int, captions: bool, scale: float, workers: int, fmt: str, crf: int, preset: str,
          maxrate: float, t_from: float = 0.0, t_to: float | None = None) -> None:
    with sync_playwright() as p:
        browser, page, _ = open_page(p, html, captions)
        dur = page.evaluate("VIDEO.duration")
        browser.close()
    first = int(round(t_from * fps))
    last = int(round(min(dur, t_to if t_to is not None else dur) * fps))
    frames = last - first
    if frames <= 0:
        sys.exit("nothing to render: check --from and --to")
    workers = max(1, min(workers, frames // (fps * 2) or 1))
    tmp = Path(tempfile.mkdtemp(prefix="gen-motion-graphics-render-"))
    bounds = [first + round(frames * k / workers) for k in range(workers + 1)]
    ctx = mp.get_context("spawn")
    done, failed = ctx.Value("i", 0), ctx.Value("i", 0)
    procs = []
    for k in range(workers):
        seg = tmp / f"seg{k:02d}.mp4"
        procs.append(ctx.Process(target=worker, args=(k, str(html.resolve()), bounds[k], bounds[k + 1], fps, captions, scale, fmt, str(seg), crf, preset, maxrate, done, failed)))
    start = time.time()
    for pr in procs:
        pr.start()
    last = 0.0
    while any(pr.is_alive() for pr in procs):
        time.sleep(0.5)
        if failed.value:
            for pr in procs:
                pr.terminate()
            shutil.rmtree(tmp, ignore_errors=True)
            sys.exit("rendering failed")
        now = time.time()
        if now - last >= 10:
            last = now
            d, el = done.value, now - start
            eta = el / d * (frames - d) if d else 0
            print(f"frame {d}/{frames} ({d / frames:.0%}), {el:.0f}s elapsed, about {eta:.0f}s left, {workers} workers", flush=True)
    if failed.value or any(pr.exitcode for pr in procs):
        shutil.rmtree(tmp, ignore_errors=True)
        sys.exit("rendering failed")
    listing = tmp / "segments.txt"
    listing.write_text("".join(f"file '{tmp / f'seg{k:02d}.mp4'}'\n" for k in range(workers)))
    subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-f", "concat", "-safe", "0", "-i", str(listing),
         "-ss", f"{first / fps:.6f}", "-t", f"{frames / fps:.6f}", "-i", str(audio),
         "-map", "0:v:0", "-map", "1:a:0", "-c:v", "copy", "-c:a", "aac", "-b:a", "384k", "-ar", "48000",
         "-color_primaries", "bt709", "-color_trc", "bt709", "-colorspace", "bt709", "-color_range", "tv",
         "-af", "apad", "-t", f"{frames / fps:.6f}", "-movflags", "+faststart", str(out)],
        check=True,
    )
    shutil.rmtree(tmp, ignore_errors=True)
    print(f"{out} done: {frames} frames in {time.time() - start:.0f}s with {workers} workers ({frames / (time.time() - start):.1f} fps)")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("html", type=Path)
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--step", type=float, default=0.25, help="seconds between checked frames")
    ap.add_argument("--stills")
    ap.add_argument("--export-sfx", type=Path, help="write the page's sound-effect events to this JSON file")
    ap.add_argument("--out-dir", type=Path)
    ap.add_argument("--audio", type=Path)
    ap.add_argument("--out", type=Path)
    ap.add_argument("--fps", type=int, default=60)
    ap.add_argument("--scale", type=float, default=1)
    ap.add_argument("--workers", type=int, default=max(1, min(8, (os.cpu_count() or 2) // 2)))
    ap.add_argument("--format", choices=["png", "jpeg"], default="png")
    ap.add_argument("--crf", type=int, default=17)
    ap.add_argument("--preset", default="slow")
    ap.add_argument("--maxrate", type=float, help="video bitrate cap in Mbit/s (default 24 at 1080p, 80 at 4K; 0 = no cap)")
    ap.add_argument("--from", dest="t_from", type=float, default=0.0, help="video: start time, for a preview of one part")
    ap.add_argument("--to", dest="t_to", type=float, help="video: end time")
    ap.add_argument("--no-captions", action="store_true")
    ap.add_argument("--debug", action="store_true", help="stills only: print the time, scene and word in the corner")
    a = ap.parse_args()
    if a.export_sfx:
        export_sfx(a.html, a.export_sfx)
    elif a.check:
        check(a.html, a.step)
    elif a.stills:
        if not a.out_dir:
            sys.exit("--stills needs --out-dir")
        stills(a.html, a.stills, a.out_dir, not a.no_captions, a.scale, a.debug)
    else:
        if not (a.audio and a.out):
            sys.exit("video needs --audio and --out")
        a.out.parent.mkdir(parents=True, exist_ok=True)
        maxrate = a.maxrate if a.maxrate is not None else (80.0 if a.scale >= 2 else 24.0)
        video(a.html, a.audio, a.out, a.fps, not a.no_captions, a.scale, a.workers, a.format, a.crf, a.preset, maxrate, a.t_from, a.t_to)


if __name__ == "__main__":
    main()
