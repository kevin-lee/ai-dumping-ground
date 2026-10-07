# /// script
# requires-python = ">=3.12"
# dependencies = ["numpy"]
# ///
"""Prepare the narration for the video: cut the silence before the first word and after the last,
and with --trim-pauses also shorten the pauses between words, for a faster pace.

Silence is any run of 10 ms frames below the threshold lasting at least 150 ms. Leading silence is
removed and trailing silence is cut to a short tail. The pauses in between stay as recorded, unless
--trim-pauses shortens each one to a length that depends on how long it was, so commas stay short
and sentence breaks stay a little longer. Cuts are made in the middle of each pause with a short
fade, so there are no clicks.

The input can be any format ffmpeg reads (wav, mp3, m4a, flac and so on). The output is a
48 kHz mono 16-bit WAV plus a JSON map from source time to output time.

Usage:
  uv run --script trim_silence.py narration-af_heart-1.00x.wav narration.wav trim-map.json
  uv run --script trim_silence.py narration-af_heart-1.00x.wav --dry-run     # both lengths, writes nothing
Options:
  --trim-pauses              shorten the pauses too (by default they stay as recorded)
  --pause-scale 1.0          with --trim-pauses: multiply every target pause (0.8 tighter, 1.3 more relaxed)
  --threshold-db auto|<dB>   auto (default) picks it from the noise floor, -40 dB for clean TTS
  --dry-run                  only print the length with the pauses kept and with them trimmed, write
                             nothing (then dst and mapping may be omitted)
"""

import argparse
import json
import subprocess
import wave
from pathlib import Path

import numpy as np

SR = 48000
FRAME = 0.010
MIN_SILENCE = 0.15
FADE = 0.008
LEAD_PAD = 0.03
TAIL_PAD = 0.08


def target_pause(d: float, scale: float) -> float:
    if d < 0.30:
        return min(d, 0.12 * scale)
    if d < 0.45:
        return 0.18 * scale
    return 0.26 * scale


def decode(path: Path) -> np.ndarray:
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", str(path), "-f", "f32le", "-ac", "1", "-ar", str(SR), "-"],
        check=True, capture_output=True,
    ).stdout
    return np.frombuffer(raw, dtype="<f4").copy()


def write_wav(path: Path, samples: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((np.clip(samples, -1, 1) * 32767).astype("<i2").tobytes())


def frame_db(x: np.ndarray) -> np.ndarray:
    n = int(FRAME * SR)
    frames = x[: len(x) // n * n].reshape(-1, n)
    return 20 * np.log10(np.sqrt((frames ** 2).mean(axis=1)) + 1e-10)


def pick_threshold(db: np.ndarray) -> float:
    noise = float(np.percentile(db, 10))
    speech = float(np.percentile(db, 95))
    # Clean TTS has digital silence, so this lands on -40 dB. Noisy recordings get a higher threshold,
    # but always well under the speech level.
    return float(min(np.clip(noise + 10, -40, -28), speech - 20))


def silences(db: np.ndarray, threshold: float) -> list[tuple[float, float]]:
    quiet = db < threshold
    runs, start = [], None
    for i, q in enumerate(np.append(quiet, False)):
        if q and start is None:
            start = i
        elif not q and start is not None:
            if (i - start) * FRAME >= MIN_SILENCE:
                runs.append((start * FRAME, i * FRAME))
            start = None
    return runs


def plan(runs: list[tuple[float, float]], total: float, trim: bool, scale: float) -> list[tuple[float, float]]:
    """The parts of the source to keep: everything between the first and the last word, with each pause
    shortened when trim is set."""
    keep: list[tuple[float, float]] = []
    cursor = 0.0
    for s, e in runs:
        if s <= 0.0:
            cursor = max(0.0, e - LEAD_PAD)
            continue
        if e >= total - FRAME * 2:
            keep.append((cursor, min(total, s + TAIL_PAD)))
            cursor = total
            break
        if not trim:
            continue
        t = target_pause(e - s, scale)
        keep.append((cursor, s + t / 2))
        cursor = e - t / 2
    if cursor < total:
        keep.append((cursor, total))
    return keep


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("src", type=Path)
    ap.add_argument("dst", type=Path, nargs="?")
    ap.add_argument("mapping", type=Path, nargs="?")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--trim-pauses", action="store_true", help="shorten the pauses between words too")
    ap.add_argument("--threshold-db", default="auto")
    ap.add_argument("--pause-scale", type=float, default=1.0)
    a = ap.parse_args()

    x = decode(a.src)
    total = len(x) / SR
    db = frame_db(x)
    threshold = pick_threshold(db) if a.threshold_db == "auto" else float(a.threshold_db)
    runs = silences(db, threshold)
    inner = sum(1 for s, e in runs if s > 0.0 and e < total - FRAME * 2)
    if a.dry_run or not (a.dst and a.mapping):
        kept = sum(e - s for s, e in plan(runs, total, False, a.pause_scale))
        trimmed = sum(e - s for s, e in plan(runs, total, True, a.pause_scale))
        print(f"{a.src.name}: {total:.2f}s as recorded (dry run, nothing written)\n"
              f"  pauses kept (the default):  {kept:.2f}s, only the silence before the first word and after the last cut\n"
              f"  pauses trimmed:             {trimmed:.2f}s, {inner} pauses shortened to 0.12 to 0.26 s (x{a.pause_scale:g})")
        return
    keep = plan(runs, total, a.trim_pauses, a.pause_scale)

    fade = int(FADE * SR)
    ramp = np.linspace(0, 1, fade, dtype=np.float32)
    parts, segs, new_t = [], [], 0.0
    for s, e in keep:
        seg = x[int(s * SR): int(e * SR)].copy()
        if len(seg) > 2 * fade:
            seg[:fade] *= ramp
            seg[-fade:] *= ramp[::-1]
        parts.append(seg)
        segs.append({"src": [round(s, 4), round(e, 4)], "dst": [round(new_t, 4), round(new_t + len(seg) / SR, 4)]})
        new_t += len(seg) / SR
    y = np.concatenate(parts) if parts else x
    write_wav(a.dst, y)
    a.mapping.parent.mkdir(parents=True, exist_ok=True)
    a.mapping.write_text(json.dumps({
        "source": str(a.src),
        "source_seconds": round(total, 3),
        "output_seconds": round(len(y) / SR, 3),
        "pauses": "trimmed" if a.trim_pauses else "kept",
        "threshold_db": round(threshold, 1),
        "segments": segs,
    }, indent=2))
    what = f"{inner} pauses shortened" if a.trim_pauses else f"{inner} pauses kept as recorded"
    print(f"{a.src.name}: {total:.2f}s -> {len(y) / SR:.2f}s, {what}, threshold {threshold:.1f} dB")


if __name__ == "__main__":
    main()
