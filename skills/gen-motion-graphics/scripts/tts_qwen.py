# /// script
# requires-python = ">=3.12,<3.13"
# dependencies = [
#   "mlx-audio>=0.5.8; sys_platform == 'darwin' and platform_machine == 'arm64'",
#   "qwen-tts>=0.1.1; sys_platform != 'darwin' or platform_machine != 'arm64'",
#   "huggingface_hub",
#   "numpy",
#   "soundfile",
# ]
# ///
"""Narration audio with Qwen3-TTS (CustomVoice), entirely on this machine. Used for Korean narration,
and for languages Kokoro does not speak. Apple Silicon runs it with mlx-audio, other systems with qwen-tts.

Run generation through offline.sh so the text cannot leave the machine:
  scripts/offline.sh uv run --script scripts/tts_qwen.py --text narration.txt --speaker Sohee \
      --speeds 1,1.18,1.3 --out-dir sources/audio [--instruct warm] [--lexicon lexicon.json]
  -> sources/audio/narration-sohee-1.00x.wav, ...-1.18x.wav, ...-1.30x.wav

Voice samples (the first sentences of the script, or --sample-text) with an index.html to compare them,
for several speakers and/or styles:
  scripts/offline.sh uv run --script scripts/tts_qwen.py --text narration.txt --samples Sohee \
      --styles cheerful,warm,neutral --out-dir sources/audio/samples

One-time model download (needs the network; the text is not involved):
  uv run --script scripts/tts_qwen.py --setup [--model Qwen/Qwen3-TTS-12Hz-0.6B-CustomVoice]

Speakers: Sohee (Korean, female), Vivian, Serena (Chinese, female), Uncle_Fu, Dylan, Eric (Chinese, male),
Ryan, Aiden (English, male), Ono_Anna (Japanese, female). All of them can speak every supported language,
and the native speaker sounds best. The 1.7B model speaks in a bright, cheerful style by default; --instruct
takes a named style (STYLES below: cheerful, warm, neutral) or a description of the style, pace or emotion.
For Korean narration the cheerful style is written in Korean (LOCAL_STYLES), which the user picked over the
English wording. Style changes only the tone, never the words. The 0.6B model cannot follow a style: its delivery stays
neutral, which can sound curt.
Qwen3-TTS has no speed setting, so faster versions are time-stretched with pitch kept (rubberband R3 when
installed, otherwise ffmpeg atempo). The model samples randomly, so a word can come out wrong in one take and right in another: --seed makes a
take repeatable, and --chunk-seeds 2=13 redoes only chunk 2 with another seed (generation prints the chunks).
Chunks are evened out in loudness and the result peaks at -1 dBFS.
Known misreadings are respelled on every run (PRONUNCIATIONS below, e.g. Scala in Korean). lexicon.json adds
more respellings, overrides a built-in one, or switches it off with null: {"Git": {"say": "깃"}, "Scala": null}
"""

import argparse
import html
import json
import platform
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
import soundfile as sf

MLX = platform.system() == "Darwin" and platform.machine() == "arm64"
DEFAULT_MODEL = "Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice"
SPEAKERS = ["Sohee", "Vivian", "Serena", "Ono_Anna", "Ryan", "Aiden", "Uncle_Fu", "Dylan", "Eric"]
LANGS = {"ko": "Korean", "en": "English", "zh": "Chinese", "ja": "Japanese", "de": "German", "fr": "French",
         "ru": "Russian", "pt": "Portuguese", "es": "Spanish", "it": "Italian"}
STYLES = {
    "cheerful": "Speak in a bright, cheerful and friendly tone, like an upbeat YouTube host, "
                "with a smile in the voice and a lively pace.",
    "warm": "Speak in a warm, upbeat and confident tone, like a friendly tech presenter, smiling, "
            "with clear and lively delivery.",
    "neutral": "",
}
# Styles written in the narration's own language, used instead of the English ones above. For Korean the user
# picked the cheerful style written in Korean over the same style in English (2026-10-06).
LOCAL_STYLES = {
    "Korean": {"cheerful": "밝고 경쾌하고 친근한 목소리로, 미소를 띠며 활기차게 말해 주세요."},
}
DEFAULT_STYLE = "cheerful"
CHUNK_CHARS = {"Korean": 110, "Japanese": 110, "Chinese": 110}   # dense scripts: about 20 s of speech
DEFAULT_CHUNK = 260                                                # Latin scripts: about 15 s
GAP = 0.25

# Words the model reads unreliably, respelled before speaking, per narration language. They apply on every run,
# and lexicon.json can override them (null switches one off). Captions keep the original spelling.
# Scala is 스칼라 in Korean, with the "a" of "father", never 스케일라.
PRONUNCIATIONS = {
    "Korean": {"Scala": "스칼라"},
}


def setup(model: str) -> None:
    from huggingface_hub import snapshot_download

    print(f"downloading {model} (CustomVoice 1.7B is about 4.2 GB, 0.6B about 2.5 GB)")
    print(snapshot_download(model))


def local_path(model: str) -> str:
    if Path(model).exists():
        return model
    from huggingface_hub import snapshot_download

    try:
        return snapshot_download(model, local_files_only=True)
    except Exception:
        sys.exit(f"{model} is not downloaded yet. Run with --setup first (needs the network).")


def word_pattern(word: str) -> re.Pattern:
    """The word where it stands alone. A Latin letter or digit at an edge needs a non-Latin neighbour, while
    Hangul, kana and Han characters need none, because particles attach to names ("macOS와", "Linux에서").
    A plain \\w boundary would never match those."""
    latin = re.compile(r"[A-Za-z0-9]")
    pre = r"(?<![A-Za-z0-9])" if latin.match(word[0]) else ""
    post = r"(?![A-Za-z0-9])" if latin.match(word[-1]) else ""
    return re.compile(pre + re.escape(word) + post)


def detect_language(text: str) -> str:
    letters = [c for c in text if c.isalpha()]
    count = lambda lo, hi: sum(lo <= c <= hi for c in letters)
    if count("가", "힣") > 0.3 * len(letters):
        return "Korean"
    if count("぀", "ヿ") > 0.1 * len(letters):
        return "Japanese"
    if count("一", "鿿") > 0.3 * len(letters):
        return "Chinese"
    return "English"


def chunks(text: str, language: str) -> list[str]:
    """Whole sentences, a few at a time, never across a paragraph: long inputs make the model rush or drop
    the last words, and small chunks let one bad sentence be redone with another seed."""
    limit = CHUNK_CHARS.get(language, DEFAULT_CHUNK)
    out = []
    for para in re.split(r"\n\s*\n", text):
        cur = ""
        for s in (x for x in re.split(r"(?<=[.!?。！？])\s+", " ".join(para.split())) if x.strip()):
            if cur and len(cur) + len(s) + 1 > limit:
                out.append(cur)
                cur = s
            else:
                cur = f"{cur} {s}".strip()
        if cur:
            out.append(cur)
    return out


class Engine:
    def __init__(self, model: str, seed: int):
        self.seed = seed
        path = local_path(model)
        try:
            size = json.loads((Path(path) / "config.json").read_text()).get("tts_model_size", "")
        except (OSError, ValueError):
            size = ""
        self.styles = size != "0b6"   # the 0.6B models have no instruction control
        if MLX:
            from mlx_audio.tts.utils import load_model

            self.model = load_model(path)
            self.sr = self.model.sample_rate
        else:
            import torch
            from qwen_tts import Qwen3TTSModel

            device = "cuda:0" if torch.cuda.is_available() else "cpu"
            dtype = torch.bfloat16 if device != "cpu" else torch.float32
            self.model = Qwen3TTSModel.from_pretrained(path, device_map=device, dtype=dtype, attn_implementation="sdpa")
            self.sr = None

    def say(self, text: str, speaker: str, language: str, instruct: str | None, seed: int) -> tuple[np.ndarray, int]:
        if MLX:
            import mlx.core as mx

            mx.random.seed(seed)
            parts = self.model.generate_custom_voice(text=text, speaker=speaker, language=language, instruct=instruct,
                                                     temperature=0.9, top_p=1.0, repetition_penalty=1.05)
            audio = np.concatenate([np.array(r.audio, dtype=np.float32).reshape(-1) for r in parts])
            return audio, self.sr
        import torch

        torch.manual_seed(seed)
        wavs, sr = self.model.generate_custom_voice(text=text, speaker=speaker, language=language, instruct=instruct)
        return np.asarray(wavs[0], dtype=np.float32), sr


def speech_rms(x: np.ndarray, sr: int) -> float:
    """Loudness of the speech only, ignoring pauses (20 ms frames above -45 dBFS)."""
    n = int(0.02 * sr)
    f = x[: len(x) // n * n].reshape(-1, n)
    p = (f ** 2).mean(axis=1)
    active = p[p > 10 ** (-45 / 10)]
    return float(np.sqrt(active.mean())) if len(active) else 0.0


def normalize(x: np.ndarray, peak_db: float = -1.0) -> np.ndarray:
    return x * (10 ** (peak_db / 20) / (np.abs(x).max() + 1e-9))


def speak(engine: Engine, text: str, speaker: str, language: str, instruct: str | None,
          seeds: dict[int, int] | None = None, show: bool = False) -> tuple[np.ndarray, int]:
    pieces, sr = [], 24000
    for i, c in enumerate(chunks(text, language), 1):
        seed = (seeds or {}).get(i, engine.seed)
        if show:
            print(f"chunk {i} (seed {seed}): {c[:70]}{'...' if len(c) > 70 else ''}")
        audio, sr = engine.say(c, speaker, language, instruct, seed)
        pieces.append(audio)
    # The model's level drifts from take to take; even the chunks out on their speech loudness.
    levels = [speech_rms(p, sr) for p in pieces]
    target = float(np.median([v for v in levels if v > 0] or [1.0]))
    pieces = [p * (target / v) if v > 0 else p for p, v in zip(pieces, levels)]
    gap = np.zeros(int(GAP * sr), dtype=np.float32)
    out = [x for p in pieces for x in (p, gap)][:-1]
    return normalize(np.concatenate(out)), sr


def stretch(src: Path, dst: Path, speed: float) -> str:
    if shutil.which("rubberband"):
        subprocess.run(["rubberband", "-q", "-3", "-T", f"{speed}", str(src), str(dst)], check=True)
        return "rubberband R3"
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(src), "-af", f"atempo={speed}", str(dst)], check=True)
    return "ffmpeg atempo"


def report(path: Path, note: str) -> None:
    data, sr = sf.read(str(path), dtype="float32")
    peak = 20 * np.log10(np.abs(data).max() + 1e-9)
    print(f"{path} ({len(data) / sr:.1f}s, {note}, peak {peak:.1f} dBFS)")


def samples_page(out_dir: Path, names: list[tuple[str, str]], text: str) -> Path:
    rows = "\n".join(f'<div class="row"><b>{html.escape(label)}</b><audio controls preload="none" src="{html.escape(file)}"></audio></div>' for label, file in names)
    page = out_dir / "index.html"
    page.write_text(
        "<!doctype html><meta charset=utf-8><title>Voice samples</title>"
        "<style>body{font:16px system-ui;margin:32px;max-width:760px;color:#222}.row{display:flex;align-items:center;gap:16px;margin:10px 0}"
        "b{width:200px;font-family:ui-monospace,monospace}p{color:#555}</style>"
        f"<h1>Voice samples</h1><p>{html.escape(text)}</p>{rows}",
        encoding="utf-8",
    )
    return page


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--setup", action="store_true", help="download the model (network)")
    ap.add_argument("--model", default=DEFAULT_MODEL, help="HF repo id or local folder of a CustomVoice model")
    ap.add_argument("--text", type=Path)
    ap.add_argument("--speaker", default="Sohee")
    ap.add_argument("--language", help="Korean, English, ... or a code like ko (default: detected from the text)")
    ap.add_argument("--instruct", help='a named style (cheerful, warm, neutral) or a description of the style, pace or emotion (1.7B only); default: cheerful')
    ap.add_argument("--styles", help="with --samples: comma-separated styles to compare, e.g. cheerful,warm,neutral")
    ap.add_argument("--speeds", default="1")
    ap.add_argument("--out-dir", type=Path)
    ap.add_argument("--name", default="narration")
    ap.add_argument("--lexicon", type=Path)
    ap.add_argument("--samples", nargs="?", const="Sohee,Vivian,Serena,Ryan,Aiden", help="comma-separated speakers")
    ap.add_argument("--sample-text")
    ap.add_argument("--sentences", type=int, default=2)
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--chunk-seeds", default="", help="other seeds for some chunks, e.g. 2=13,4=21 (chunk numbers are printed)")
    ap.add_argument("--list-chunks", action="store_true", help="only print how the text is split into chunks")
    a = ap.parse_args()

    if a.setup:
        setup(a.model)
        return
    if not a.text or not (a.out_dir or a.list_chunks):
        sys.exit("--text and --out-dir are required")
    text = a.text.read_text(encoding="utf-8").strip()
    language = LANGS.get(a.language, a.language) if a.language else detect_language(text)
    respell = {w: {"say": v} for w, v in PRONUNCIATIONS.get(language, {}).items()}
    user = json.loads(a.lexicon.read_text(encoding="utf-8")) if a.lexicon else {}
    for word, fix in user.items():
        if fix is None:
            respell.pop(word, None)
        else:
            respell[word] = fix
    unused = []
    for word, fix in respell.items():
        if isinstance(fix, dict) and "say" in fix:
            pat = word_pattern(word)
            if not pat.search(text):
                if word in user:
                    unused.append(word)
                continue
            text = pat.sub(lambda m, say=fix["say"]: say, text)
    if unused:
        print(f"note: these lexicon entries do not occur in the text, so they change nothing: {unused}")
    if a.list_chunks:
        for i, c in enumerate(chunks(text, language), 1):
            print(f"chunk {i}: {c}")
        return
    seeds = {int(k): int(v) for k, v in (x.split("=") for x in a.chunk_seeds.split(",") if x.strip())}
    engine = Engine(a.model, a.seed)
    style = lambda v: LOCAL_STYLES.get(language, {}).get(v) or STYLES.get(v, v) or None   # a named style, or the description
    instruct = style(DEFAULT_STYLE if a.instruct is None else a.instruct)
    if not engine.styles:
        print("note: this 0.6B model cannot follow a style, so the delivery stays neutral. "
              "For a cheerful voice use the 1.7B model (--setup downloads it).")
        instruct = None
    a.instruct = instruct
    a.out_dir.mkdir(parents=True, exist_ok=True)

    if a.samples:
        speakers = [s.strip() for s in a.samples.split(",") if s.strip()]
        styles = [s.strip() for s in a.styles.split(",") if s.strip()] if a.styles and engine.styles else [None]
        sample = a.sample_text or " ".join(re.split(r"(?<=[.!?。！？])\s+", " ".join(text.split()))[: a.sentences])
        names = []
        for n in speakers:
            for st in styles:
                label = n if st is None else f"{n}, {st}"
                audio, sr = speak(engine, sample, n, language, a.instruct if st is None else style(st))
                path = a.out_dir / f"{re.sub(r'[^a-z0-9]+', '-', label.lower()).strip('-')}.wav"
                sf.write(str(path), audio, sr, subtype="PCM_16")
                report(path, f"speaker {n}, {language}, style {st or (instruct and 'default') or 'neutral'}")
                names.append((label, path.name))
        print(f"{samples_page(a.out_dir, names, sample)}  (open it to compare the voices)")
        return
    print(f"style: {instruct or 'neutral'}")

    audio, sr = speak(engine, text, a.speaker, language, a.instruct, seeds, show=True)
    with tempfile.TemporaryDirectory() as tmp:
        base = Path(tmp) / "base.wav"
        sf.write(str(base), audio, sr, subtype="PCM_16")
        for s in [float(x) for x in a.speeds.split(",") if x.strip()]:
            dst = a.out_dir / f"{a.name}-{a.speaker.lower()}-{s:.2f}x.wav"
            if abs(s - 1) < 1e-6:
                shutil.copyfile(base, dst)
                report(dst, f"speaker {a.speaker}, {language}, speed 1")
            else:
                how = stretch(base, dst, s)
                data, rate = sf.read(str(dst), dtype="float32")
                sf.write(str(dst), normalize(data), rate, subtype="PCM_16")   # stretching can raise the peaks
                report(dst, f"speaker {a.speaker}, {language}, speed {s:g} via {how}")


if __name__ == "__main__":
    main()
