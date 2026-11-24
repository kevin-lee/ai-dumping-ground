# /// script
# requires-python = ">=3.12"
# dependencies = []
# ///
"""Hold each completed scene on screen: make the pause before the first word of every scene at least
--gap seconds long, so viewers see the finished picture before the transition starts.

The script adds silence to the narration in the middle of the pause before each given word, shifts
the word timings by the same amounts, and writes timings.txt again, so Whisper does not run again.
A pause that is already long enough stays as it is, so running the script again with the same
times changes nothing. Run it after make_timings.py and before the music and the mix.

The times are the video times of the first word of each scene after the first, as timings.txt
prints them. Each one must be within 0.15 s of the start of a word that follows a pause of at
least 0.1 s, so the silence never cuts into the speech.

Usage:
  uv run --script add_holds.py sources/build/narration.wav sources/build/timings.json \
      --at 9.84,16.20,23.05 [--gap 1.2] [--offset 2.0]
Options:
  --gap 1.2      the shortest pause before a scene's first word, in seconds
  --offset 2.0   the video time of the first word, the same as make_timings.py --offset
  --dry-run      only print what would change, write nothing

It rewrites narration.wav, timings.json and timings.txt in place. To move or remove a scene change
later, run trim_silence.py and make_timings.py again, then this script with the new times.
"""

import argparse
import json
import math
import sys
import wave
from array import array
from pathlib import Path

sys.dont_write_bytecode = True   # keep __pycache__ out of the skill folder
sys.path.insert(0, str(Path(__file__).resolve().parent))
from make_timings import sheet  # noqa: E402

MATCH = 0.15     # how far a given time may be from the start of a word
QUIET = 0.02     # the window around the insert point that must be silent
MIN_ADD = 0.02   # do not add less than this
MIN_PAUSE = 0.1  # a scene must start after a pause at least this long


def rms_db(samples: array) -> float:
    if not samples:
        return -120.0
    return 20 * math.log10(math.sqrt(sum(s * s for s in samples) / len(samples)) / 32768 + 1e-10)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("audio", type=Path)
    ap.add_argument("timings", type=Path)
    ap.add_argument("--at", required=True, help="comma-separated video times of the first word of each scene")
    ap.add_argument("--gap", type=float, default=1.2)
    ap.add_argument("--offset", type=float, default=2.0)
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    words = json.loads(a.timings.read_text(encoding="utf-8"))
    with wave.open(str(a.audio), "rb") as w:
        params = w.getparams()
        frames = w.readframes(params.nframes)
    if params.sampwidth != 2 or params.nchannels != 1:
        sys.exit(f"{a.audio}: expected 16-bit mono (the output of trim_silence.py)")
    sr = params.framerate
    pcm = array("h")
    pcm.frombytes(frames)

    starts: list[int] = []
    for raw in a.at.split(","):
        t = float(raw)
        i = min(range(len(words)), key=lambda k: abs(words[k]["s"] - t))
        if abs(words[i]["s"] - t) > MATCH:
            near = ", ".join(f'{words[k]["s"]:.2f} "{words[k]["w"]}"' for k in sorted(
                range(len(words)), key=lambda k: abs(words[k]["s"] - t))[:3])
            sys.exit(f"no word starts at {t:.2f}s (nearest: {near})")
        if i == 0:
            print(f"  skip {t:.2f}s: the first word already follows the lead-in")
            continue
        starts.append(i)

    inserts: list[tuple[int, int]] = []   # (sample position in the original audio, samples to add)
    shift = [0.0] * len(words)
    for i in sorted(set(starts)):
        prev, cur = words[i - 1], words[i]
        gap = cur["s"] - prev["e"]
        if gap < MIN_PAUSE:
            sys.exit(f'{cur["s"]:.2f}s "{cur["w"]}" follows "{prev["w"]}" with no pause ({gap:.2f}s), so a hold there '
                     "would cut into the speech. Start the scene on the first word after a pause.")
        add = a.gap - gap
        if add < MIN_ADD:
            print(f'  keep {cur["s"]:7.2f}s "{cur["w"]}": the pause is already {gap:.2f}s')
            continue
        pos = round(((prev["e"] + cur["s"]) / 2 - a.offset) * sr)
        q = round(QUIET * sr)
        level = rms_db(pcm[max(0, pos - q): pos + q])
        if level > -40:
            print(f'  warning: the audio at {cur["s"]:.2f}s is not silent ({level:.0f} dB); the added silence may click')
        inserts.append((pos, round(add * sr)))
        for k in range(i, len(words)):
            shift[k] += add
        print(f'  hold {cur["s"]:7.2f}s "{cur["w"]}": pause {gap:.2f}s -> {a.gap:.2f}s (+{add:.2f}s)')

    total = sum(n for _, n in inserts) / sr
    print(f"{len(inserts)} holds added, {total:.2f}s in all; the narration is now {(len(pcm) / sr + total):.2f}s")
    if a.dry_run or not inserts:
        return

    out = array("h")
    cursor = 0
    for pos, n in inserts:
        out.extend(pcm[cursor:pos])
        out.extend(array("h", bytes(2 * n)))
        cursor = pos
    out.extend(pcm[cursor:])
    with wave.open(str(a.audio), "wb") as w:
        w.setparams(params)
        w.writeframes(out.tobytes())

    res = [{"w": w["w"], "s": round(w["s"] + d, 3), "e": round(w["e"] + d, 3)} for w, d in zip(words, shift)]
    a.timings.write_text(json.dumps(res, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    txt = a.timings.with_suffix(".txt")
    txt.write_text(sheet(res), encoding="utf-8")
    print(f"{a.audio}, {a.timings}, {txt}")
    print(sheet(res))


if __name__ == "__main__":
    main()
