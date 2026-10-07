# /// script
# requires-python = ">=3.12,<3.14"
# dependencies = [
#   "mlx-whisper>=0.4.3; sys_platform == 'darwin' and platform_machine == 'arm64'",
#   "faster-whisper>=1.2; sys_platform != 'darwin' or platform_machine != 'arm64'",
#   "huggingface_hub",
#   "numpy",
# ]
# ///
"""Word timings for captions and scene cues, in video time.

1. Whisper transcribes the narration locally with word timestamps (mlx-whisper large-v3-turbo on
   Apple Silicon, faster-whisper elsewhere). Nothing is uploaded.
2. With --script, the transcript is aligned to the script, so every caption word has the script's
   spelling and punctuation and no word is lost. Without it, Whisper's words are used as they are.
3. With --display, spoken forms are shown in their written form: "skills dot S H" becomes
   "skills.sh" in the captions (one caption word that spans the spoken words).
4. Whisper tends to start a word too early after a pause, so starts inside a pause move to its end.
5. Times are shifted by --offset, the video time where the narration starts (the mix lead-in).

Check that generated speech says the script (AUDIO MODE), listing every place where it differs:
  scripts/offline.sh uv run --script make_timings.py narration.wav --check --script narration.txt

Usage:
  uv run --script make_timings.py --setup          # once, with the network: downloads the Whisper model
  scripts/offline.sh uv run --script make_timings.py narration.wav timings.json --script narration.txt \
      [--display display.json] [--offset 2.0] [--language en|ko|...]

Writes timings.json ([{"w": word, "s": start, "e": end}, ...]) and timings.txt next to it: the
narration sentence by sentence with start and end times, for planning scenes.
display.json: [{"spoken": "skills dot S H", "written": "skills.sh"}, ...]
"""

import argparse
import difflib
import json
import platform
import re
import subprocess
import sys
import unicodedata
from pathlib import Path

MLX = platform.system() == "Darwin" and platform.machine() == "arm64"
MLX_MODEL = "mlx-community/whisper-large-v3-turbo"
FW_MODEL = "large-v3-turbo"


def norm(s: str) -> str:
    s = unicodedata.normalize("NFKC", s).lower()
    return "".join(ch for ch in s if unicodedata.category(ch)[0] in "LN")


def tail_punct(s: str) -> str:
    m = re.search(r"[^\w]*$", s)
    return m.group(0) if m else ""


def hangul_ratio(text: str) -> float:
    letters = [c for c in text if c.isalpha()]
    return sum("가" <= c <= "힣" for c in letters) / max(1, len(letters))


def bias_prompt(script: str) -> str:
    # Names and terms help Whisper spell them right; it only reads the start of a long prompt.
    seen, terms = set(), []
    for tok in re.findall(r"\S+", script):
        w = tok.strip(".,;:!?\"'()[]")
        if w and (w[0].isupper() or any(c.isdigit() for c in w) or "." in w) and w.lower() not in seen:
            seen.add(w.lower())
            terms.append(w)
    return ", ".join(terms[:60])


def transcribe(path: Path, language: str | None, prompt: str | None) -> list[dict]:
    if MLX:
        import mlx_whisper

        r = mlx_whisper.transcribe(str(path), path_or_hf_repo=MLX_MODEL, word_timestamps=True,
                                   language=language, initial_prompt=prompt or None)
        segs = [[{"w": w["word"].strip(), "s": float(w["start"]), "e": float(w["end"]), "p": float(w["probability"])}
                 for w in seg.get("words", []) if w["word"].strip()] for seg in r["segments"]]
    else:
        from faster_whisper import WhisperModel

        model = WhisperModel(FW_MODEL, device="auto", compute_type="auto")
        segments, _ = model.transcribe(str(path), word_timestamps=True, language=language, initial_prompt=prompt or None)
        segs = [[{"w": w.word.strip(), "s": float(w.start), "e": float(w.end), "p": float(w.probability)}
                 for w in (seg.words or []) if w.word.strip()] for seg in segments]
    # After the last word Whisper sometimes "hears" a stock phrase in the silence ("MBC 뉴스 스토리입니다.",
    # "Thanks for watching"): a last segment with almost no confidence, or with its words squeezed into a
    # tenth of a second. Nobody said them, so they go.
    segs = [s for s in segs if s]
    while segs and (sum(w["p"] for w in segs[-1]) / len(segs[-1]) < 0.1 or (segs[-1][-1]["e"] - segs[-1][0]["s"]) / len(segs[-1]) < 0.1):
        segs.pop()
    return [{k: w[k] for k in ("w", "s", "e")} for s in segs for w in s]


def script_tokens(text: str) -> list[str]:
    toks: list[str] = []
    for t in re.findall(r"\S+", text):
        if not norm(t) and toks:      # a lone dash or symbol joins the word before it
            toks[-1] += " " + t
        else:
            toks.append(t)
    return toks


def align(tokens: list[str], heard: list[dict]) -> tuple[list[dict], float]:
    a = [norm(t) for t in tokens]
    b = [norm(h["w"]) for h in heard]
    out: list[dict | None] = [None] * len(tokens)
    equal = 0
    for op, i1, i2, j1, j2 in difflib.SequenceMatcher(a=a, b=b, autojunk=False).get_opcodes():
        if op == "equal":
            for k in range(i2 - i1):
                out[i1 + k] = {"w": tokens[i1 + k], "s": heard[j1 + k]["s"], "e": heard[j1 + k]["e"]}
            equal += i2 - i1
        elif op == "replace":
            s, e = heard[j1]["s"], heard[j2 - 1]["e"]
            weights = [max(1, len(a[i])) for i in range(i1, i2)]
            total, acc = sum(weights), 0
            for k, i in enumerate(range(i1, i2)):
                ws = s + (e - s) * acc / total
                acc += weights[k]
                out[i] = {"w": tokens[i], "s": ws, "e": s + (e - s) * acc / total}
    # Script words Whisper did not hear share the gap between their neighbours.
    i = 0
    while i < len(out):
        if out[i] is not None:
            i += 1
            continue
        j = i
        while j < len(out) and out[j] is None:
            j += 1
        left = out[i - 1]["e"] if i > 0 else (out[j]["s"] if j < len(out) else 0.0)
        right = out[j]["s"] if j < len(out) else left + 0.3 * (j - i)
        step = max(0.0, right - left) / (j - i)
        for k in range(i, j):
            out[k] = {"w": tokens[k], "s": left + step * (k - i), "e": left + step * (k - i + 1)}
        i = j
    return out, equal / max(1, len(tokens))


def differences(tokens: list[str], heard: list[dict]) -> list[str]:
    """Where the transcript differs from the script, with the time of the first heard word."""
    a = [norm(t) for t in tokens]
    b = [norm(h["w"]) for h in heard]
    out = []
    for op, i1, i2, j1, j2 in difflib.SequenceMatcher(a=a, b=b, autojunk=False).get_opcodes():
        if op == "equal":
            continue
        at = heard[j1]["s"] if j1 < len(heard) else (heard[-1]["e"] if heard else 0.0)
        said = " ".join(tokens[i1:i2]) or "(nothing)"
        got = " ".join(h["w"] for h in heard[j1:j2]) or "(nothing)"
        out.append(f"{at:7.2f}s  script: {said}  |  heard: {got}")
    return out


def apply_display(words: list[dict], display: list[dict]) -> list[dict]:
    rules = sorted(([norm(x) for x in r["spoken"].split()], r["written"]) for r in display)
    rules.sort(key=lambda r: -len(r[0]))   # longest spoken form first
    out, i = [], 0
    while i < len(words):
        for spoken, written in rules:
            n = len(spoken)
            if n and [norm(w["w"]) for w in words[i: i + n]] == spoken:
                out.append({"w": written + tail_punct(words[i + n - 1]["w"]), "s": words[i]["s"], "e": words[i + n - 1]["e"]})
                i += n
                break
        else:
            out.append(words[i])
            i += 1
    return out


def pauses(path: Path) -> list[tuple[float, float]]:
    log = subprocess.run(
        ["ffmpeg", "-hide_banner", "-i", str(path), "-af", "silencedetect=noise=-40dB:d=0.1", "-f", "null", "-"],
        capture_output=True, text=True,
    ).stderr
    marks = [float(v) for v in re.findall(r"silence_(?:start|end): (-?[0-9.]+)", log)]
    return list(zip(marks[0::2], marks[1::2]))


def snap(words: list[dict], sil: list[tuple[float, float]]) -> None:
    for i, x in enumerate(words):
        for ss, se in sil:
            if ss - 0.08 <= x["s"] < se:
                x["s"] = se
                if i > 0 and words[i - 1]["e"] > ss:
                    words[i - 1]["e"] = ss
            if ss < x["e"] <= se + 0.3 and x["s"] < ss:
                x["e"] = ss
        x["e"] = max(x["e"], x["s"] + 0.02)


def sheet(words: list[dict]) -> str:
    lines, cur = [], []
    for w in words:
        cur.append(w)
        end = re.search(r"[.?!。！？][\"'”’)]*$", w["w"])
        long_comma = len(cur) >= 14 and re.search(r"[,;:][\"'”’)]*$", w["w"])
        if end or long_comma:
            lines.append(cur)
            cur = []
    if cur:
        lines.append(cur)
    head = f"# {len(words)} words, {words[0]['s']:.2f}-{words[-1]['e']:.2f} s in video time\n" if words else ""
    return head + "\n".join(f"[{c[0]['s']:7.2f} -{c[-1]['e']:7.2f}] " + " ".join(w["w"] for w in c) for c in lines) + "\n"


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("audio", type=Path, nargs="?")
    ap.add_argument("out", type=Path, nargs="?")
    ap.add_argument("--setup", action="store_true", help="download the Whisper model (network), then exit")
    ap.add_argument("--check", action="store_true", help="only report how well the audio matches --script; writes nothing")
    ap.add_argument("--script", type=Path)
    ap.add_argument("--display", type=Path)
    ap.add_argument("--offset", type=float, default=2.0)
    ap.add_argument("--language", help="en, ko, ... (default: from the script, else detected)")
    a = ap.parse_args()
    if a.setup:
        from huggingface_hub import snapshot_download

        if MLX:
            print(snapshot_download(MLX_MODEL))
        else:
            from faster_whisper import WhisperModel

            WhisperModel(FW_MODEL, device="auto", compute_type="auto")
            print(f"faster-whisper {FW_MODEL} is cached")
        return
    if not a.audio or not (a.out or a.check):
        sys.exit("audio and out are required (or --setup, or --check)")
    if a.check and not a.script:
        sys.exit("--check needs --script")

    text = a.script.read_text(encoding="utf-8") if a.script else ""
    language = a.language or (("ko" if hangul_ratio(text) > 0.3 else "en") if text else None)
    heard = transcribe(a.audio, language, bias_prompt(text) if text else None)
    if not heard:
        sys.exit("Whisper heard no words")
    if a.check:
        tokens = script_tokens(text)
        _, matched = align(tokens, heard)
        diffs = differences(tokens, heard)
        print(f"{a.audio.name}: {matched:.0%} of the script heard exactly as written, {len(diffs)} difference(s)")
        for d in diffs:
            print("  " + d)
        print("Differences in spelling only (numbers, hyphens, respelled names) are fine; wrong or missing words are not.")
        return
    if text:
        words, matched = align(script_tokens(text), heard)
        print(f"aligned {len(words)} script words to {len(heard)} heard words, {matched:.0%} matched exactly")
        if matched < 0.8:
            print("warning: under 80% of the script matched; is this the right script for this audio?")
    else:
        words = heard
    if a.display:
        words = apply_display(words, json.loads(a.display.read_text(encoding="utf-8")))
    snap(words, pauses(a.audio))
    res = [{"w": w["w"], "s": round(w["s"] + a.offset, 3), "e": round(w["e"] + a.offset, 3)} for w in words]
    a.out.parent.mkdir(parents=True, exist_ok=True)
    a.out.write_text(json.dumps(res, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    txt = a.out.with_suffix(".txt")
    txt.write_text(sheet(res), encoding="utf-8")
    print(f"{a.out} ({len(res)} words), {txt}")
    print(sheet(res))


if __name__ == "__main__":
    main()
