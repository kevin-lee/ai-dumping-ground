# /// script
# requires-python = ">=3.12"
# dependencies = ["numpy", "scipy"]
# ///
"""Compose an original lo-fi hip hop beat for the video, entirely in code: no samples, no downloads.

The track is written in video time, made for this narration: the drums drop exactly on --drop-at (the
first word by default, or the product reveal), --breaks take the drums out where the narration turns,
and it runs a bar past the mix's ending. Every sound is synthesized here (electric piano chords, bass,
kick, snare, hats, vinyl crackle, tape wobble), so the music is original: no license to check and
nothing for YouTube's Content ID to match.

Usage:
  uv run --script compose_music.py --narration sources/build/narration.wav --lead-in 2.0 \
      --out sources/music/original-beat.wav --analysis sources/music/music.json \
      [--drop-at 6.0] [--outro 4] [--bpm 92] [--key F] [--progression 0] [--breaks 30:36] \
      [--style upbeat|calm] [--seed 7]
Then mix it like a found track, with the drop where it already is:
  uv run --script mix_audio.py sources/build/narration.wav --music sources/music/original-beat.wav \
      --analysis sources/music/music.json --lead-in 2.0 --drop <drop-at> --drop-at <drop-at> --out-dir sources/build

music.json has the shape analyze_music.py writes, with exact values: the composer knows its own grid.
mix_audio.py also plays these drums (kick, clap, snare, hats, crash) as the generated beat on a found track.
Progressions (--progression): 0 I-vi-ii-V (bright), 1 IV-iii-vi-I (warm), 2 ii-V-I-vi (jazzy).
--seed changes the small variations (velocities, timing, drum fills, chord voicings): same seed, same track.
"""

import argparse
import json
import subprocess
import sys
import wave
from pathlib import Path

import numpy as np
from scipy.signal import butter, sosfilt

SR = 48000
NOTES = {"C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "F": 5, "F#": 6, "Gb": 6,
         "G": 7, "G#": 8, "Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11}
KEY_NAMES = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]
MAJ9, MIN9, MIN7, DOM9, SUS9 = [0, 4, 7, 11, 14], [0, 3, 7, 10, 14], [0, 3, 7, 10], [0, 4, 7, 10, 14], [0, 5, 7, 10, 14]
PROGRESSIONS = [
    [(0, MAJ9), (9, MIN9), (2, MIN9), (7, SUS9)],   # I - vi - ii - V: bright, classic
    [(5, MAJ9), (4, MIN7), (9, MIN9), (0, MAJ9)],   # IV - iii - vi - I: warm
    [(2, MIN9), (7, DOM9), (0, MAJ9), (9, MIN7)],   # ii - V - I - vi: jazzy
]


def hz(m: float) -> float:
    return 440.0 * 2 ** ((m - 69) / 12)


def sec(t: float) -> int:
    return int(round(t * SR))


def add(buf: np.ndarray, t: float, sig: np.ndarray, gain: float = 1.0) -> None:
    """Mix sig into buf starting at time t (seconds); parts outside the buffer are dropped."""
    s = sec(t)
    a, b = max(0, s), min(len(buf), s + len(sig))
    if b > a:
        buf[a:b] += gain * sig[a - s: b - s]


def lp(x: np.ndarray, f: float, order: int = 2) -> np.ndarray:
    return sosfilt(butter(order, min(f, SR / 2 - 100), "low", fs=SR, output="sos"), x)


def hp(x: np.ndarray, f: float, order: int = 2) -> np.ndarray:
    return sosfilt(butter(order, f, "high", fs=SR, output="sos"), x)


def bp(x: np.ndarray, lo: float, hi: float) -> np.ndarray:
    return sosfilt(butter(2, [lo, hi], "band", fs=SR, output="sos"), x)


def smoothstep(x):
    x = np.clip(x, 0, 1)
    return x * x * (3 - 2 * x)


# ---------- instruments ----------

def ep_note(f: float, dur: float, vel: float) -> np.ndarray:
    """Electric piano: an FM tine for the bell-like attack plus a soft body, held for dur, then released."""
    n = sec(dur + 0.5)
    t = np.arange(n) / SR
    index = 1.2 * np.exp(-t / 0.12) + 0.3
    tone = np.sin(2 * np.pi * f * t + index * np.sin(2 * np.pi * f * t))
    tone += 0.25 * np.sin(2 * np.pi * 2 * f * t) * np.exp(-t / 0.35)
    tone += 0.12 * np.sin(2 * np.pi * 3 * f * t) * np.exp(-t / 0.22)
    env = np.minimum(1, t / 0.004) * np.exp(-t / 1.6)
    env *= np.where(t < dur, 1.0, np.exp(-(t - dur) / 0.12))
    return vel * tone * env


def bass_note(f: float, dur: float, vel: float) -> np.ndarray:
    n = sec(dur + 0.2)
    t = np.arange(n) / SR
    tone = np.sin(2 * np.pi * f * t) + 0.25 * np.sin(4 * np.pi * f * t)
    env = np.minimum(1, t / 0.008) * np.exp(-t / 0.9) * np.where(t < dur, 1.0, np.exp(-(t - dur) / 0.06))
    return vel * np.tanh(1.6 * tone * env) / np.tanh(1.6)


def kick(vel: float, rng, decay: float = 0.26) -> np.ndarray:
    t = np.arange(sec(0.5)) / SR
    freq = 46 + 78 * np.exp(-t / 0.032)
    body = np.sin(2 * np.pi * np.cumsum(freq) / SR) * np.exp(-t / decay)
    click = hp(rng.standard_normal(len(t)), 2500) * np.exp(-t / 0.002) * 0.25
    return vel * np.tanh(1.8 * (body + click)) / np.tanh(1.8)


def snare(vel: float, rng) -> np.ndarray:
    t = np.arange(sec(0.4)) / SR
    tone = np.sin(2 * np.pi * 186 * t) * np.exp(-t / 0.05) * 0.55
    rattle = bp(rng.standard_normal(len(t)), 1400, 7000) * np.exp(-t / 0.13)
    return vel * (tone + 0.9 * rattle) * np.minimum(1, t / 0.0015)   # a soft attack keeps it out of the kick band


def clap(vel: float, rng) -> np.ndarray:
    """Hand clap: three quick bursts of band-passed noise and a short tail."""
    t = np.arange(sec(0.3)) / SR
    env = sum(np.where(t >= d, np.exp(-(t - d) / 0.0045), 0.0) for d in (0.0, 0.0095, 0.019))
    env = env + 0.55 * np.where(t >= 0.028, np.exp(-(t - 0.028) / 0.075), 0.0)
    return vel * 0.8 * bp(rng.standard_normal(len(t)), 900, 5500) * env


def hat(vel: float, rng, open_: bool = False) -> np.ndarray:
    t = np.arange(sec(0.35 if open_ else 0.09)) / SR
    noise = hp(rng.standard_normal(len(t)), 7500, 3)
    return vel * noise * np.exp(-t / (0.16 if open_ else 0.028))


def crash(vel: float, rng) -> np.ndarray:
    t = np.arange(sec(2.0)) / SR
    return vel * hp(rng.standard_normal(len(t)), 4500, 2) * np.exp(-t / 0.7)


def pluck(f: float, dur: float, vel: float, rng) -> np.ndarray:
    """Plucked string (Karplus-Strong): a filtered noise burst circulating in a one-period delay line."""
    period = max(2, int(round(SR / f)))
    n = sec(dur + 0.5)
    g = np.exp(-1 / (f * 0.9))                      # about a second of ring
    prev = lp(rng.standard_normal(period), 5000) * 0.9
    out = np.zeros(n)
    for pos in range(0, n, period):
        m = min(period, n - pos)
        out[pos:pos + m] = prev[:m]
        prev = 0.5 * (prev + np.roll(prev, -1)) * g
    t = np.arange(n) / SR
    return vel * out * np.where(t < dur, 1.0, np.exp(-(t - dur) / 0.07))


def crackle(n: int, rng) -> np.ndarray:
    """Vinyl: sparse clicks of random size plus a little hiss."""
    out = hp(rng.standard_normal(n), 3000) * 0.004
    count = int(n / SR * 9)
    pos = rng.integers(0, n, count)
    amp = rng.exponential(0.06, count) * rng.choice([-1, 1], count)
    clicks = np.zeros(n)
    np.add.at(clicks, pos, amp)
    return out + hp(lp(clicks, 6000), 1200)


def wobble(x: np.ndarray, t: np.ndarray) -> np.ndarray:
    """Tape wow and flutter: a slowly varying delay, a few cents of drifting pitch."""
    d = 0.004 + 0.0011 * np.sin(2 * np.pi * 0.55 * t) + 0.0003 * np.sin(2 * np.pi * 5.1 * t)
    return np.interp(t - d, t, x, left=0.0)


# ---------- arrangement ----------

def motif(rng) -> list[tuple[float, int]]:
    """A short two-bar phrase on the major pentatonic: (beat within the phrase, scale step) pairs."""
    starts = sorted(rng.choice([0.5, 1.0, 1.5, 2.75, 3.5, 4.5, 5.0, 6.25, 6.75], size=int(rng.integers(3, 6)), replace=False))
    step, out = int(rng.integers(3, 6)), []
    for b in starts:
        step = int(np.clip(step + rng.choice([-2, -1, 1, 2]), 0, 9))
        out.append((float(b), step))
    return out


def compose(length: float, drop: float, bpm: float, key: int, prog: list, breaks: list[tuple[float, float]],
            style: str, rng, outro_from: float | None = None) -> tuple[np.ndarray, np.ndarray, list[dict]]:
    T = 60.0 / bpm
    bar = 4 * T
    n = sec(length)
    t = np.arange(n) / SR
    ep, bass, drums, lead, kicks = np.zeros(n), np.zeros(n), np.zeros(n), np.zeros(n), []
    phrase_a = motif(rng)
    phrase_b = phrase_a[:-1] + [(phrase_a[-1][0], max(0, phrase_a[-1][1] - 2))]
    pent = [0, 2, 4, 7, 9]
    calm = style == "calm"
    k0 = int(np.floor(-drop / bar))           # first bar index (negative: the intro before the drop)
    k1 = int(np.ceil((length - drop) / bar))
    in_break = lambda s: any(a - 1e-6 <= s < b - 1e-6 for a, b in breaks)
    bars = []
    for k in range(k0, k1 + 1):
        s = drop + k * bar
        root, chord = prog[k % 4]
        intro = k < 0
        drums_on = not intro and not in_break(s)
        nxt_on = (k + 1) >= 0 and not in_break(s + bar)
        bars.append({"bar": k - k0, "start": round(s, 4), "drums": bool(drums_on)})
        # Chords: voice the chord tones between MIDI 59 and 80, root left to the bass.
        base = 48 + key + root
        voicing = sorted({59 + ((base + iv - 59) % 12) + (12 if iv >= 12 else 0) for iv in chord[1:]})
        voicing = [v for v in voicing if v <= 80][:4]
        hits = [(0.0, 3.9, 0.75)] if intro or calm else [(0.0, 2.4, 0.85), (2.5, 1.4, 0.62)]
        for b0, dur, vel in hits:
            for i, v in enumerate(voicing):
                strum = i * 0.011 + rng.uniform(0, 0.004)
                add(ep, s + b0 * T + strum, ep_note(hz(v), dur * T, vel * rng.uniform(0.9, 1.05)))
        # Bass from the drop on, also through breaks.
        if not intro:
            r = 36 + (key + root) % 12
            fifth = r + 7
            line = [(0.0, 1.8, r, 0.9), (2.5, 1.0, r, 0.75)] + ([] if calm else [(3.5, 0.42, fifth, 0.55)])
            for b0, dur, note, vel in line:
                add(bass, s + b0 * T, bass_note(hz(note), dur * T, vel))
        # A soft plucked melody: every other two-bar phrase under the narration, every phrase after it.
        if style == "upbeat" and k % 2 == 0 and not intro:
            after = outro_from is not None and s >= outro_from - bar
            if after or (k // 2) % 2 == 0:
                for b0, step in (phrase_a if (k // 2) % 2 == 0 else phrase_b):
                    note = 67 + key % 12 + pent[step % 5] + 12 * (step // 5)
                    while note > 82:
                        note -= 12
                    add(lead, s + b0 * T + rng.uniform(0, 0.01), pluck(hz(note), 0.9 * T, (0.55 if after else 0.32) * rng.uniform(0.85, 1.1), rng))
        if drums_on:
            pattern = [0.0, 2.25, 2.5] if k % 4 == 3 else [0.0, 1.75, 2.5]
            for b0 in pattern:
                tk = s + b0 * T
                kicks.append(tk)
                add(drums, tk, kick(0.95 if b0 == 0 else 0.8, rng))
            for b0 in (1.0, 3.0):
                add(drums, s + b0 * T + 0.012, snare(0.52 * rng.uniform(0.92, 1.05), rng))
            if k % 4 == 3 and not calm:
                add(drums, s + 3.75 * T + 0.01, snare(0.18, rng))
            swing = (0.58 - 0.5) * 2 * (T / 4)
            for i in range(16):
                if calm and i % 2:
                    continue
                if i % 2 and rng.random() < 0.18:
                    continue
                open_ = (i == 14 and k % 2 == 1)
                vel = (0.36 if i % 4 == 0 else 0.27 if i % 2 == 0 else 0.17) * rng.uniform(0.85, 1.15)
                add(drums, s + i * T / 4 + (swing if i % 2 else 0) + rng.uniform(-0.003, 0.003), hat(vel, rng, open_))
        # A fill and a crash where the drums come in.
        if not drums_on and nxt_on and (k + 1) >= 0:
            for j, b0 in enumerate((3.0, 3.25, 3.5, 3.75)):
                add(drums, s + b0 * T, snare(0.22 + 0.13 * j, rng))
        if drums_on and (k == 0 or in_break(s - bar)):
            add(drums, s, crash(0.2, rng))
    # Sidechain-style pump: chords and bass dip under each kick.
    pump = np.zeros(n)
    for tk in kicks:
        a = sec(tk)
        if 0 <= a < n:
            m = min(n - a, sec(0.4))
            pump[a:a + m] = np.maximum(pump[a:a + m], np.exp(-np.arange(m) / SR / 0.14))
    duck = 1 - 0.32 * pump
    ep_bus = wobble(hp(lp(ep, 7000), 200, 1) * duck, t)
    bass_bus = lp(bass, 900) * duck
    lead_bus = wobble(lp(lead, 6000), t)
    drum_bus = np.tanh(1.3 * lp(drums, 12000)) / np.tanh(1.3)
    # The intro opens up into the drop; breaks dip the filter.
    music = 0.6 * ep_bus + 0.42 * bass_bus + 0.5 * lead_bus
    music = music + 0.6 * bp(music, 1700, 4500)          # a little presence, like a real recording
    muffled = lp(music, 900, 2)
    w = smoothstep((t - (drop - bar)) / bar)
    for a, b in breaks:
        w = np.minimum(w, 1 - 0.55 * smoothstep((t - a) / 0.4) * (1 - smoothstep((t - b + 0.4) / 0.4)))
    music = muffled + (music - muffled) * w
    left = music + 0.85 * drum_bus
    right = music.copy() + 0.85 * drum_bus
    # Gentle stereo: the piano drifts left and right, the hiss and crackle sit in both.
    pan = 0.12 * np.sin(2 * np.pi * 0.11 * t)
    left += 0.6 * ep_bus * pan
    right -= 0.6 * ep_bus * pan
    vinyl = crackle(n, rng)
    out = np.stack([lp(left, 11000) + vinyl, lp(right, 11000) + vinyl * 0.9], axis=1)
    out *= 0.12 / (np.sqrt((out ** 2).mean()) + 1e-9)
    return out, drum_bus, bars


def narration_length(path: Path) -> float:
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(path)],
                         capture_output=True, text=True, check=True).stdout
    return float(out.strip())


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--narration", type=Path, help="the prepared narration (sources/build/narration.wav), to size the track like mix_audio.py does")
    ap.add_argument("--length", type=float, help="track length in seconds instead of --narration")
    ap.add_argument("--lead-in", type=float, default=2.0)
    ap.add_argument("--outro", type=float, default=4.0)
    ap.add_argument("--drop-at", type=float, help="video time where the drums come in (default: --lead-in)")
    ap.add_argument("--bpm", type=float, default=92.0)
    ap.add_argument("--key", default=None, help="C, Db, D, ... (default: picked by --seed)")
    ap.add_argument("--progression", type=int, default=None, help="0, 1 or 2 (default: picked by --seed)")
    ap.add_argument("--breaks", default="", help="video time ranges without drums, e.g. 30:36,48:51")
    ap.add_argument("--style", choices=["upbeat", "calm"], default="upbeat")
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--analysis", type=Path, required=True)
    a = ap.parse_args()

    rng = np.random.default_rng(a.seed)
    drop = a.drop_at if a.drop_at is not None else a.lead_in
    bar = 4 * 60.0 / a.bpm
    if a.length:
        length = a.length
    elif a.narration:
        end = a.lead_in + narration_length(a.narration)
        total = drop + np.ceil((end + a.outro - drop) / bar - 1e-6) * bar   # the same ending mix_audio.py computes
        length = float(total + bar)
    else:
        sys.exit("give --narration or --length")
    key = NOTES[a.key] if a.key else int(rng.choice([5, 3, 2, 8, 10]))       # F, Eb, D, Ab, Bb
    pi = a.progression if a.progression is not None else int(rng.integers(0, len(PROGRESSIONS)))
    breaks = []
    for part in [x for x in a.breaks.split(",") if x.strip()]:
        b0, b1 = (float(v) for v in part.split(":"))
        snap = lambda v: drop + round((v - drop) / bar) * bar               # breaks start and end on bar lines
        breaks.append((snap(b0), snap(b1)))
    outro_from = (a.lead_in + narration_length(a.narration)) if a.narration else None
    audio, drum_bus, bars = compose(length, drop, a.bpm, key, PROGRESSIONS[pi], breaks, a.style, rng, outro_from)

    a.out.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(a.out), "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((np.clip(audio, -1, 1) * 32767).astype("<i2").tobytes())

    # Analysis in analyze_music.py's shape, from the composer's own grid.
    T = 60.0 / a.bpm
    rms = lambda x: float(20 * np.log10(np.sqrt((x ** 2).mean()) + 1e-9)) if len(x) else -120.0
    kept = []
    for b in bars:
        s0, s1 = max(0, sec(b["start"])), min(len(audio), sec(b["start"] + 4 * T))
        if s1 - s0 < sec(T):
            continue
        b.update(rms_db=round(rms(audio[s0:s1].mean(axis=1)), 1), drums_db=round(rms(drum_bus[s0:s1]), 1))
        kept.append(b)
    for i, b in enumerate(kept):
        b["bar"] = i
    step = SR // 20
    m = len(drum_bus) // step
    env = np.sqrt((drum_bus[: m * step].reshape(m, step) ** 2).mean(axis=1))
    env = np.clip(np.convolve(env, np.ones(5) / 5, mode="same") / (np.percentile(env[env > 0], 90) + 1e-9 if (env > 0).any() else 1), 0, 1)
    downbeats = [round(drop + k * 4 * T, 4) for k in range(int(np.floor(-drop / (4 * T))), int(np.ceil((length - drop) / (4 * T))) + 1) if 0 <= drop + k * 4 * T < length]
    info = {
        "source": str(a.out), "composed": True, "seed": a.seed, "key": KEY_NAMES[key],
        "progression": pi, "style": a.style, "duration": round(length, 3), "bpm": a.bpm, "beat": round(T, 6),
        "grid_offset": round(drop % T, 4), "downbeat_phase": 0, "downbeats": downbeats,
        "first_drum_downbeat": round(drop, 4), "breaks": [[round(x, 3), round(y, 3)] for x, y in breaks],
        "bars": kept, "drums_rate": 20, "drums": [round(float(v), 3) for v in env],
    }
    a.analysis.parent.mkdir(parents=True, exist_ok=True)
    a.analysis.write_text(json.dumps(info, indent=1))
    print(f"{a.out} ({length:.2f}s, {a.bpm:g} BPM, key {info['key']}, progression {pi}, {a.style}, drums drop at {drop:.2f}s"
          + (f", breaks {info['breaks']}" if breaks else "") + ")")
    print(f"{a.analysis}: mix with --drop {drop:.4f} --drop-at {drop:.4f}")


if __name__ == "__main__":
    main()
