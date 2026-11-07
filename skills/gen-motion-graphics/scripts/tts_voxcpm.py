# /// script
# requires-python = ">=3.12,<3.13"
# dependencies = [
#   "mlx-audio>=0.6.4; sys_platform == 'darwin' and platform_machine == 'arm64'",
#   "voxcpm>=2.0.3; sys_platform != 'darwin' or platform_machine != 'arm64'",
#   "huggingface_hub",
#   "numpy",
#   "soundfile",
# ]
# ///
"""Narration audio with VoxCPM2, entirely on this machine. The other choice for Korean narration, next to
tts_qwen.py. Apple Silicon runs it with mlx-audio, other systems with the voxcpm package. Output is 48 kHz mono.

VoxCPM2 has no preset speakers. The voice comes from one of two places:
  - a description (voice design): --design female (the default), --design male, or your own description
  - a reference clip (voice cloning): --ref-audio voice.wav, best with its exact transcript in --ref-text

Run generation through offline.sh so the text cannot leave the machine:
  scripts/offline.sh uv run --script scripts/tts_voxcpm.py --text narration.txt --design female \
      --speeds 1,1.18 --out-dir sources/audio [--lexicon lexicon.json]
  -> sources/audio/narration-voxcpm-female-1.00x.wav, ...-1.18x.wav

Voice samples (the first sentences of the script, or --sample-text) with an index.html to compare them:
  scripts/offline.sh uv run --script scripts/tts_voxcpm.py --text narration.txt --samples female,male \
      --out-dir sources/audio/samples [--ref-audio voice.wav --ref-text "..."]

One-time model download (needs the network; the text is not involved):
  uv run --script scripts/tts_voxcpm.py --setup

The text is spoken in chunks of whole sentences, never across a paragraph (the same chunks as tts_qwen.py).
A designed voice is different on every call, so only chunk 1 is spoken from the description. Every later chunk
clones chunk 1 (its audio and its text), so the voice stays the same through the narration. The seed of chunk 1
therefore chooses the voice: --seed gives another voice, and --chunk-seeds 1=13 does too. --chunk-seeds 3=13
redoes only chunk 3, in the same voice. The model samples randomly, so a word can be wrong in one take and right
in another. Chunks are evened out in loudness and the result peaks at -1 dBFS.
VoxCPM2 has no speed setting, so faster versions are time-stretched with pitch kept (rubberband R3 when
installed, otherwise ffmpeg atempo).
Known misreadings (PRONUNCIATIONS in tts_qwen.py, e.g. Scala in Korean) and lexicon.json "say" entries are
respelled before speaking, the same way as in tts_qwen.py.
"""

import argparse
import platform
import re
import shutil
import sys
import tempfile
from pathlib import Path

import numpy as np
import soundfile as sf

sys.path.insert(0, str(Path(__file__).resolve().parent))
from tts_qwen import (GAP, LANGS, chunks, detect_language, normalize, report, require_offline,  # noqa: E402
                      respell_text, samples_page, speech_rms, stretch)

MLX = platform.system() == "Darwin" and platform.machine() == "arm64"
DEFAULT_MODEL = "mlx-community/VoxCPM2-bf16" if MLX else "openbmb/VoxCPM2"
# {who} is filled from the narration language, e.g. "Korean woman". The female design is the one the user rated
# 4 of 5 for Korean in the 2026-11-07 comparison. The male design has not been rated yet.
DESIGNS = {
    "female": "A young {who} woman with a bright, warm and friendly voice, like a cheerful tech YouTuber, "
              "clear and lively.",
    "male": "A {who} man in his thirties with a warm, calm and confident voice, like a friendly tech presenter, "
            "with clear delivery.",
}
DEFAULT_DESIGN = "female"
NATIONALITY = {"Korean": "Korean", "English": "American", "Japanese": "Japanese", "Chinese": "Chinese"}
CFG = 2.0
STEPS = 10


def setup(model: str) -> None:
    from huggingface_hub import snapshot_download

    print(f"downloading {model} (about 5 GB)")
    print(snapshot_download(model))


def local_path(model: str) -> str:
    if Path(model).exists():
        return model
    from huggingface_hub import snapshot_download

    try:
        return snapshot_download(model, local_files_only=True)
    except Exception:
        sys.exit(f"{model} is not downloaded yet. Run with --setup first (needs the network).")


def design_text(name: str, language: str) -> str:
    """A named design filled in for the language, or the user's own description as it is."""
    who = NATIONALITY.get(language, "")
    return re.sub(r"\s+", " ", DESIGNS[name].format(who=who)) if name in DESIGNS else name


class Engine:
    def __init__(self, model: str):
        path = local_path(model)
        if MLX:
            from mlx_audio.tts.utils import load_model

            self.model = load_model(path)
            self.sr = self.model.sample_rate
        else:
            from voxcpm import VoxCPM

            self.model = VoxCPM.from_pretrained(path, load_denoiser=False)
            self.sr = self.model.tts_model.sample_rate

    def say(self, text: str, seed: int, instruct: str | None = None, ref: Path | None = None,
            prompt: tuple[Path, str] | None = None) -> np.ndarray:
        """One take. instruct: a voice description or a style. ref: a clip to clone. prompt: a clip and its
        exact transcript, which the take continues from (the closest copy of the voice)."""
        if MLX:
            import mlx.core as mx

            mx.random.seed(seed)
            kw = dict(instruct=instruct or None, cfg_value=CFG, inference_timesteps=STEPS)
            if ref:
                kw["ref_audio"] = str(ref)
            if prompt:
                kw["prompt_audio"], kw["prompt_text"] = str(prompt[0]), prompt[1]
            parts = [np.asarray(r.audio.astype(mx.float32)).reshape(-1) for r in self.model.generate(text=text, **kw)]
            return np.concatenate(parts)
        wav = self.model.generate(
            text=f"({instruct}){text}" if instruct else text,
            reference_wav_path=str(ref) if ref else None,
            prompt_wav_path=str(prompt[0]) if prompt else None,
            prompt_text=prompt[1] if prompt else None,
            cfg_value=CFG, inference_timesteps=STEPS, seed=seed,
        )
        return np.asarray(wav, dtype=np.float32).reshape(-1)


def speak(engine: Engine, text: str, language: str, seed: int, design: str | None, ref: Path | None,
          ref_text: str | None, style: str | None, seeds: dict[int, int] | None = None,
          show: bool = False) -> tuple[np.ndarray, int]:
    """Design mode: chunk 1 from the description, later chunks continue from chunk 1. Clone mode: every chunk
    clones the reference (and continues from it when its transcript is known)."""
    sr = engine.sr
    pieces = []
    with tempfile.TemporaryDirectory() as tmp:
        anchor = None
        for i, c in enumerate(chunks(text, language), 1):
            s = (seeds or {}).get(i, seed)
            if show:
                print(f"chunk {i} (seed {s}): {c[:70]}{'...' if len(c) > 70 else ''}")
            if ref:
                audio = engine.say(c, s, instruct=style, ref=ref, prompt=(ref, ref_text) if ref_text else None)
            elif anchor is None:
                audio = engine.say(c, s, instruct=design)
                anchor = (Path(tmp) / "chunk1.wav", c)
                sf.write(str(anchor[0]), normalize(audio), sr, subtype="PCM_16")
            else:
                audio = engine.say(c, s, ref=anchor[0], prompt=anchor)
            pieces.append(audio)
    levels = [speech_rms(p, sr) for p in pieces]
    target = float(np.median([v for v in levels if v > 0] or [1.0]))
    pieces = [p * (target / v) if v > 0 else p for p, v in zip(pieces, levels)]
    gap = np.zeros(int(GAP * sr), dtype=np.float32)
    out = [x for p in pieces for x in (p, gap)][:-1]
    return normalize(np.concatenate(out)), sr


def slug(label: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", label.lower()).strip("-")[:40] or "voice"


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--setup", action="store_true", help="download the model (network)")
    ap.add_argument("--model", default=DEFAULT_MODEL, help="HF repo id or local folder of a VoxCPM2 model")
    ap.add_argument("--text", type=Path)
    ap.add_argument("--language", help="Korean, English, ... or a code like ko (default: detected from the text)")
    ap.add_argument("--design", help=f"a named voice ({', '.join(DESIGNS)}) or a description; default: {DEFAULT_DESIGN}")
    ap.add_argument("--ref-audio", type=Path, help="a clip of the voice to clone (5 to 15 s of clean speech)")
    ap.add_argument("--ref-text", help="the exact transcript of --ref-audio, or a file with it (better cloning)")
    ap.add_argument("--style", help="with --ref-audio: a style for the cloned voice, e.g. 'cheerful, slightly faster'")
    ap.add_argument("--voice-name", help="the voice part of the file name (default: the design name, or 'clone')")
    ap.add_argument("--speeds", default="1")
    ap.add_argument("--out-dir", type=Path)
    ap.add_argument("--name", default="narration")
    ap.add_argument("--lexicon", type=Path)
    ap.add_argument("--samples", nargs="?", const=",".join(DESIGNS),
                    help="comma-separated designs to compare; with --ref-audio a clone sample is added")
    ap.add_argument("--sample-text")
    ap.add_argument("--sentences", type=int, default=2)
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--chunk-seeds", default="", help="other seeds for some chunks, e.g. 2=13,4=21 (chunk 1 sets a designed voice)")
    ap.add_argument("--list-chunks", action="store_true", help="only print how the text is split into chunks")
    a = ap.parse_args()

    if a.setup:
        setup(a.model)
        return
    require_offline()
    if not a.text or not (a.out_dir or a.list_chunks):
        sys.exit("--text and --out-dir are required")
    if a.ref_audio and a.design:
        sys.exit("use --design or --ref-audio, not both")
    if a.ref_audio and not a.ref_audio.exists():
        sys.exit(f"{a.ref_audio} does not exist")
    ref_text = a.ref_text
    if ref_text and Path(ref_text).is_file():
        ref_text = Path(ref_text).read_text(encoding="utf-8").strip()
    text = a.text.read_text(encoding="utf-8").strip()
    language = LANGS.get(a.language, a.language) if a.language else detect_language(text)
    text = respell_text(text, language, a.lexicon)
    if a.list_chunks:
        for i, c in enumerate(chunks(text, language), 1):
            print(f"chunk {i}: {c}")
        return
    seeds = {int(k): int(v) for k, v in (x.split("=") for x in a.chunk_seeds.split(",") if x.strip())}
    engine = Engine(a.model)
    a.out_dir.mkdir(parents=True, exist_ok=True)

    if a.samples:
        sample = a.sample_text or " ".join(re.split(r"(?<=[.!?。！？])\s+", " ".join(text.split()))[: a.sentences])
        sample = respell_text(sample, language, a.lexicon) if a.sample_text else sample
        voices = [(d.strip(), design_text(d.strip(), language), None) for d in a.samples.split(",") if d.strip()]
        if a.ref_audio:
            voices.append(("clone", None, a.ref_audio))
        names = []
        for label, design, ref in voices:
            audio, sr = speak(engine, sample, language, a.seed, design, ref, ref_text, a.style)
            path = a.out_dir / f"voxcpm-{slug(label)}.wav"
            sf.write(str(path), audio, sr, subtype="PCM_16")
            report(path, f"VoxCPM2 {label}, {language}")
            names.append((f"VoxCPM2 {label}", path.name))
        print(f"{samples_page(a.out_dir, names, sample)}  (open it to compare the voices)")
        return

    design = None if a.ref_audio else design_text(a.design or DEFAULT_DESIGN, language)
    voice = a.voice_name or ("clone" if a.ref_audio else slug(a.design or DEFAULT_DESIGN))
    print(f"voice: {'clone of ' + str(a.ref_audio) if a.ref_audio else design}")
    audio, sr = speak(engine, text, language, a.seed, design, a.ref_audio, ref_text, a.style, seeds, show=True)
    with tempfile.TemporaryDirectory() as tmp:
        base = Path(tmp) / "base.wav"
        sf.write(str(base), audio, sr, subtype="PCM_16")
        for s in [float(x) for x in a.speeds.split(",") if x.strip()]:
            dst = a.out_dir / f"{a.name}-voxcpm-{voice}-{s:.2f}x.wav"
            if abs(s - 1) < 1e-6:
                shutil.copyfile(base, dst)
                report(dst, f"VoxCPM2 {voice}, {language}, speed 1")
            else:
                how = stretch(base, dst, s)
                data, rate = sf.read(str(dst), dtype="float32")
                sf.write(str(dst), normalize(data), rate, subtype="PCM_16")   # stretching can raise the peaks
                report(dst, f"VoxCPM2 {voice}, {language}, speed {s:g} via {how}")


if __name__ == "__main__":
    main()
