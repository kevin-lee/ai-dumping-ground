# /// script
# requires-python = ">=3.10,<3.14"
# dependencies = ["kokoro-onnx>=0.6.1", "numpy"]
# ///
"""Narration audio with Kokoro (Kokoro-82M v1.0 through kokoro-onnx), entirely on this machine.

Run generation through offline.sh so the text cannot leave the machine:
  scripts/offline.sh uv run --script scripts/tts_kokoro.py --text narration.txt --voice af_heart \
      --speeds 1,1.18,1.3 --out-dir sources/audio [--lexicon lexicon.json]
  -> sources/audio/narration-af_heart-1.00x.wav, ...-1.18x.wav, ...-1.30x.wav
Speeds work like playback speeds: the 1.18x file is 1.18 times shorter than the 1x file, pauses included.
Kokoro's own speed setting is not proportional, so it is calibrated for each speed. Files peak at -1 dBFS.

Voice samples to choose from (the first sentences of the script, or --sample-text), with an index.html
to play them side by side:
  scripts/offline.sh uv run --script scripts/tts_kokoro.py --text narration.txt \
      --samples af_heart,af_bella,am_michael,bf_emma --out-dir sources/audio/samples

Check how words will be pronounced before generating (espeak-ng phonemes, IPA):
  scripts/offline.sh uv run --script scripts/tts_kokoro.py --phonemes "Scala, Kubernetes, nginx"

One-time download of the model files (needs the network; the text is not involved):
  uv run --script scripts/tts_kokoro.py --setup

Known mispronunciations are fixed on every run (PRONUNCIATIONS below, e.g. Scala). lexicon.json adds more,
keys are words as written in the narration:
  {"nginx": {"say": "engine x"}, "Vite": {"say": "veet"}}
"ipa" replaces espeak's phonemes for that word, "say" replaces the word before phonemizing. An entry for a
built-in word overrides it, and null switches it off: {"Scala": null}.
"""

import argparse
import hashlib
import html
import json
import re
import sys
import urllib.request
import wave
from pathlib import Path

import numpy as np

MODEL_DIR = Path.home() / ".cache" / "kokoro-onnx"
RELEASE = "https://api.github.com/repos/thewh1teagle/kokoro-onnx/releases/tags/model-files-v1.1"
FILES = ["kokoro-v1.0.onnx", "voices-v1.0.bin"]
LANG = {"a": "en-us", "b": "en-gb", "e": "es", "f": "fr-fr", "h": "hi", "i": "it", "j": "ja", "p": "pt-br", "z": "cmn"}
DEFAULT_SAMPLES = ["af_heart", "af_bella", "af_nicole", "af_sarah", "am_michael", "am_fenrir", "am_puck", "bf_emma", "bm_george"]

# Words espeak-ng gets wrong in English, with the phonemes to use instead. They apply on every run with an
# English voice, and lexicon.json can override them. Scala is said like the "a" in "father", not like "scale".
PRONUNCIATIONS = {
    "Scala": "skˈɑːlə",
}


def setup() -> None:
    MODEL_DIR.mkdir(parents=True, exist_ok=True)
    req = urllib.request.Request(RELEASE, headers={"User-Agent": "gen-motion-graphics"})
    assets = {a["name"]: a for a in json.loads(urllib.request.urlopen(req, timeout=60).read())["assets"]}
    for name in FILES:
        dst, asset = MODEL_DIR / name, assets[name]
        want = (asset.get("digest") or "").removeprefix("sha256:")
        if dst.exists() and (not want or hashlib.sha256(dst.read_bytes()).hexdigest() == want):
            print(f"{dst} is already there" + (" (SHA-256 verified)" if want else ""))
            continue
        print(f"downloading {name} ({asset['size'] / 1e6:.0f} MB)")
        data = urllib.request.urlopen(asset["browser_download_url"], timeout=600).read()
        if want and hashlib.sha256(data).hexdigest() != want:
            sys.exit(f"{name}: SHA-256 does not match the release, not saved")
        dst.write_bytes(data)
        print(f"{dst} saved{' (SHA-256 verified)' if want else ''}")


def load():
    from kokoro_onnx import Kokoro

    missing = [f for f in FILES if not (MODEL_DIR / f).exists()]
    if missing:
        sys.exit(f"model files missing in {MODEL_DIR}: {missing}. Run with --setup first (needs the network).")
    return Kokoro(str(MODEL_DIR / FILES[0]), str(MODEL_DIR / FILES[1]))


def word_pattern(word: str) -> re.Pattern:
    """The word where it stands alone. A Latin letter or digit at an edge needs a non-Latin neighbour, while
    Hangul, kana and Han characters need none, because particles attach to names ("macOS와", "Linux에서").
    A plain \\w boundary would never match those."""
    latin = re.compile(r"[A-Za-z0-9]")
    pre = r"(?<![A-Za-z0-9])" if latin.match(word[0]) else ""
    post = r"(?![A-Za-z0-9])" if latin.match(word[-1]) else ""
    return re.compile(pre + re.escape(word) + post)


def read_text(path: Path) -> str:
    # Paragraph breaks only make the file readable; the narration is spoken as one stream.
    return " ".join(path.read_text(encoding="utf-8").split())


def build_lexicon(path: Path | None, lang: str) -> tuple[dict, set[str]]:
    """The built-in PRONUNCIATIONS (English voices) plus lexicon.json, whose entries win.
    Returns the lexicon and the user's words."""
    lexicon = {word: {"ipa": ipa} for word, ipa in PRONUNCIATIONS.items()} if lang.startswith("en") else {}
    user = json.loads(path.read_text(encoding="utf-8")) if path else {}
    for word, fix in user.items():
        if fix is None:
            lexicon.pop(word, None)
        else:
            lexicon[word] = fix
    return lexicon, {w for w, fix in user.items() if fix is not None}


def to_phonemes(kokoro, text: str, lang: str, lexicon: dict) -> str:
    for word, fix in lexicon.items():
        if isinstance(fix, dict) and "say" in fix:
            text = word_pattern(word).sub(lambda m: fix["say"], text)
    phonemes = kokoro.tokenizer.phonemize(text, lang)
    for word, fix in lexicon.items():
        ipa = fix.get("ipa") if isinstance(fix, dict) else fix
        if not ipa or not word_pattern(word).search(text):
            continue
        wrong = kokoro.tokenizer.phonemize(word, lang).strip()
        # In a sentence espeak may stress the word less, so look for those forms too.
        forms = [f for f in dict.fromkeys([wrong, wrong.replace("ˈ", "ˌ"), wrong.replace("ˈ", "")]) if f and f in phonemes]
        if not forms and ipa not in phonemes:
            sys.exit(f'cannot find the phonemes of "{word}" ({wrong}) in the text to replace them')
        for f in forms:
            phonemes = phonemes.replace(f, ipa)
    return phonemes


def write_wav(path: Path, samples: np.ndarray, sr: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes((np.clip(samples, -1.0, 1.0) * 32767).astype("<i2").tobytes())


def synth(kokoro, phonemes: str, voice: str, speed: float, factor: float = 1.0) -> tuple[np.ndarray, int]:
    lang = LANG.get(voice[0], "en-us")
    # Pauses shrink with the playback factor, like speeding up a recording would.
    return kokoro.create(phonemes, voice=voice, speed=speed, lang=lang, is_phonemes=True,
                         sentence_pause=0.25 / factor, clause_pause=0.1 / factor)


def at_factor(kokoro, phonemes: str, voice: str, factor: float, ref_secs: float) -> tuple[np.ndarray, int, str]:
    """Speech that is `factor` times shorter than the 1x take, like a playback speed.

    Kokoro's own speed setting is not proportional (1.18 shortens a take by only about 10 %) and its response
    jumps between settings 1.30 and 1.35. So the setting is used inside its smooth range, 0.7 to 1.3, calibrated
    to the length, and whatever is left is a small time-stretch with the pitch kept.
    Measured: length factor ~ 1 + 0.75 x (setting - 1).
    """
    lo, hi = 0.7, 1.3
    setting = min(hi, max(lo, 1 + (factor - 1) / 0.75))
    samples, sr = synth(kokoro, phonemes, voice, setting, factor)
    got = ref_secs / (len(samples) / sr)
    if abs(got - factor) / factor > 0.01 and lo < setting < hi:
        setting = min(hi, max(lo, setting * factor / got))
        samples, sr = synth(kokoro, phonemes, voice, setting, factor)
        got = ref_secs / (len(samples) / sr)
    how = f"Kokoro speed setting {setting:.3f}"
    if abs(got - factor) / factor > 0.005:
        samples = stretch(samples, sr, factor / got)
        how += f" + {factor / got:.3f}x time-stretch"
    return samples, sr, how


def stretch(samples: np.ndarray, sr: int, tempo: float) -> np.ndarray:
    """Pitch-preserving tempo change: rubberband's R3 engine when installed, otherwise ffmpeg atempo."""
    import shutil
    import subprocess
    import tempfile

    with tempfile.TemporaryDirectory() as tmp:
        src, dst = Path(tmp) / "in.wav", Path(tmp) / "out.wav"
        write_wav(src, samples, sr)
        if shutil.which("rubberband"):
            subprocess.run(["rubberband", "-q", "-3", "-T", f"{tempo}", str(src), str(dst)], check=True)
        else:
            subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(src), "-af", f"atempo={tempo}", str(dst)], check=True)
        with wave.open(str(dst), "rb") as w:
            return np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype(np.float32) / 32768.0


def normalize(samples: np.ndarray) -> np.ndarray:
    # Kokoro speaks quietly (about -25 LUFS); peaks at -1 dBFS make the files comfortable to listen to.
    return samples * (10 ** (-1 / 20) / (np.abs(samples).max() + 1e-9))


def speak(kokoro, text: str, voice: str, speed: float, lexicon: dict, out: Path, ref_secs: float | None = None,
          native: bool = False) -> float:
    phonemes = to_phonemes(kokoro, text, LANG.get(voice[0], "en-us"), lexicon)
    if abs(speed - 1) < 1e-6 or native or ref_secs is None:
        samples, sr = synth(kokoro, phonemes, voice, speed)
        how = f"speed {speed:g}"
    else:
        samples, sr, made = at_factor(kokoro, phonemes, voice, speed, ref_secs)
        how = f"{ref_secs / (len(samples) / sr):.3f}x shorter than 1x ({made})"
    write_wav(out, normalize(samples), sr)
    secs = len(samples) / sr
    print(f"{out} ({secs:.1f}s, voice {voice}, {how}, peaks at -1 dBFS)")
    return secs


def first_sentences(text: str, n: int) -> str:
    parts = re.split(r"(?<=[.!?])\s+", text)
    return " ".join(parts[:n])


def samples_page(out_dir: Path, voices: list[str], text: str) -> Path:
    rows = "\n".join(
        f'<div class="row"><b>{html.escape(v)}</b><audio controls preload="none" src="{html.escape(v)}.wav"></audio></div>' for v in voices
    )
    page = out_dir / "index.html"
    page.write_text(
        "<!doctype html><meta charset=utf-8><title>Voice samples</title>"
        "<style>body{font:16px system-ui;margin:32px;max-width:760px;color:#222}.row{display:flex;align-items:center;gap:16px;margin:10px 0}"
        "b{width:130px;font-family:ui-monospace,monospace}p{color:#555}</style>"
        f"<h1>Voice samples</h1><p>{html.escape(text)}</p>{rows}",
        encoding="utf-8",
    )
    return page


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--setup", action="store_true", help="download the model files (network)")
    ap.add_argument("--list-voices", action="store_true")
    ap.add_argument("--phonemes", help="comma-separated words or phrases to show as phonemes")
    ap.add_argument("--text", type=Path, help="narration text file")
    ap.add_argument("--voice", default="af_heart")
    ap.add_argument("--speeds", default="1", help="comma-separated playback speeds, e.g. 1,1.18,1.3: 1.18 is 1.18x shorter than 1x")
    ap.add_argument("--native-speed", action="store_true", help="pass the speeds to Kokoro as they are (not proportional)")
    ap.add_argument("--out-dir", type=Path)
    ap.add_argument("--name", default="narration", help="file name prefix")
    ap.add_argument("--lexicon", type=Path)
    ap.add_argument("--samples", nargs="?", const=",".join(DEFAULT_SAMPLES), help="comma-separated voices for samples")
    ap.add_argument("--sample-text", help="text for the samples (default: the first sentences of --text)")
    ap.add_argument("--sentences", type=int, default=2, help="sentences per sample")
    a = ap.parse_args()

    if a.setup:
        setup()
        return
    kokoro = load()
    if a.list_voices:
        print(" ".join(sorted(kokoro.get_voices())))
        return
    lexicon, user_words = build_lexicon(a.lexicon, LANG.get(a.voice[0], "en-us"))
    if a.phonemes:
        lang = LANG.get(a.voice[0], "en-us")
        for w in [x.strip() for x in a.phonemes.split(",") if x.strip()]:
            raw = kokoro.tokenizer.phonemize(w, lang).strip()
            fixed = to_phonemes(kokoro, w, lang, lexicon).strip()
            print(f"{w}: {raw}" + (f"   -> spoken as {fixed} (fixed by the lexicon)" if fixed != raw else ""))
        return
    if not (a.text and a.out_dir):
        sys.exit("--text and --out-dir are required")
    text = read_text(a.text)
    unused = [w for w in user_words if not word_pattern(w).search(text)]
    if unused:
        print(f"note: these lexicon entries do not occur in the text, so they change nothing: {unused}")
    if a.samples:
        voices = [v.strip() for v in a.samples.split(",") if v.strip()]
        unknown = sorted(set(voices) - set(kokoro.get_voices()))
        if unknown:
            sys.exit(f"unknown voices: {unknown}; see --list-voices")
        sample = a.sample_text or first_sentences(text, a.sentences)
        for v in voices:
            speak(kokoro, sample, v, float(a.speeds.split(",")[0]), lexicon, a.out_dir / f"{v}.wav")
        print(f"{samples_page(a.out_dir, voices, sample)}  (open it to compare the voices)")
        return
    if a.voice not in kokoro.get_voices():
        sys.exit(f"unknown voice {a.voice}; see --list-voices")
    speeds = [float(x) for x in a.speeds.split(",") if x.strip()]
    if any(not 0.5 <= s <= 2.0 for s in speeds):
        sys.exit("speeds must be between 0.5 and 2.0")
    ref = None
    if any(abs(s - 1) > 1e-6 for s in speeds) and not a.native_speed:
        # The 1x take is the reference length for the faster or slower ones.
        lang = LANG.get(a.voice[0], "en-us")
        base, sr = synth(kokoro, to_phonemes(kokoro, text, lang, lexicon), a.voice, 1.0)
        ref = len(base) / sr
    for s in speeds:
        speak(kokoro, text, a.voice, s, lexicon, a.out_dir / f"{a.name}-{a.voice}-{s:.2f}x.wav", ref, a.native_speed)


if __name__ == "__main__":
    main()
