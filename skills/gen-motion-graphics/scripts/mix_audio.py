# /// script
# requires-python = ">=3.12"
# dependencies = ["numpy", "scipy"]
# ///
"""Mix the narration with background music, master it, and describe the result for the page.

The music is edited on its beat grid (from analyze_music.py): a chosen drum downbeat (the drop) lands
on the first word, optional whole-bar cuts move sections around, the track loops whole bars when it
is too short, and the ending lands on a bar line with a low-pass sweep and fade. The music sits lower
while the narration plays and ducks a little more under each phrase.

A found track gets a generated beat on top (--beat light, the default): drums synthesized with
compose_music.py's instruments and locked to the track's grid to the millisecond. Hi-hats follow the
track's swing, claps double its snares, kicks add punch to its downbeats, and a fill and a crash mark
the drums coming in on the drop and after every breakdown. A composed track has its own drums and gets none.

Usage:
  uv run --script mix_audio.py narration.wav --music track.mp3 --analysis music.json --out-dir build/
  uv run --script mix_audio.py narration.wav --out-dir build/          # narration only

Options (times in seconds):
  --lead-in 2.0        video time of the first word (the music plays alone before it)
  --drop T             source time of the downbeat that lands on --drop-at (default: the analysed drop)
  --drop-at T          video time for that downbeat (default: --lead-in)
  --cut A:B            remove source time A..B, repeatable; use whole bars from the analysis table
  --outro 4.0          music after the last word, at least; the ending waits for the next bar line, so the
                       end card lasts 4 s plus up to one bar (2.8 s at 85 BPM, 2.2 s at 110)
  --fade 3.0           length of the closing sweep and fade
  --bed-db -7          music level under the narration, relative to the lead-in and outro
  --duck-db -6         extra dip while words are spoken
  --target-lufs -14    integrated loudness of the master (YouTube plays at about -14 LUFS)
  --beat light         generated beat on a found track: light (default), strong, or off
  --sfx sfx.json       sound effects to mix in, exported from the page with render_video.py --export-sfx
  --sfx-level light    light (default), medium or off

Writes to --out-dir: mix-raw.wav, master.wav (48 kHz stereo), master.mp3 (for the page) and mix.json:
  duration, narration {start, end}, music {bpm, downbeat, drumsRate, drums[], fadeOut, segments}, beat, sfx,
  loudness.
music.downbeat is the video time of beat 0. drums is 0..1 drum activity in video time, so the page can
pulse on the beat only where the drums really play.
"""

import argparse
import json
import re
import subprocess
import sys
import wave
from pathlib import Path

import numpy as np

SR = 48000
XFADE = 0.015
VOICE_RMS = 0.20
MUSIC_RMS = 0.12


def decode(path: Path, channels: int) -> np.ndarray:
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", str(path), "-f", "f32le", "-ac", str(channels), "-ar", str(SR), "-"],
        check=True, capture_output=True,
    ).stdout
    return np.frombuffer(raw, dtype="<f4").reshape(-1, channels).copy()


def write_wav(path: Path, x: np.ndarray, bits: int = 16) -> None:
    with wave.open(str(path), "wb") as w:
        w.setnchannels(x.shape[1])
        w.setsampwidth(bits // 8)
        w.setframerate(SR)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype("<i2").tobytes())


def sec(t: float) -> int:
    return int(round(t * SR))


def smoothstep(x: np.ndarray) -> np.ndarray:
    x = np.clip(x, 0, 1)
    return x * x * (3 - 2 * x)


def plan_segments(offset: float, total: float, track_end: float, cuts: list[tuple[float, float]],
                  loop: tuple[float, float]) -> list[tuple[float, float, float]]:
    """Walk the track from `offset`, skipping cuts and looping, until `total` seconds are covered.

    Returns (video_start, source_start, length) triples. A negative source start means silence.
    """
    segs, v, s = [], 0.0, offset
    if s < 0:
        segs.append((0.0, -1.0, -s))
        v, s = -s, 0.0
    guard = 0
    while v < total - 1e-6:
        guard += 1
        if guard > 1000:
            sys.exit("could not plan the music edit; check --cut and the loop range")
        cut = next(((a, b) for a, b in cuts if a <= s < b), None)
        if cut:
            s = cut[1]
            continue
        stop = min([a for a, _ in cuts if a > s] + [loop[1] if s < loop[1] else track_end, track_end])
        if stop - s < 1e-6:
            s = loop[0]
            continue
        n = min(stop - s, total - v)
        segs.append((v, s, n))
        v += n
        s += n
        if s >= loop[1] - 1e-6 or s >= track_end - 1e-6:
            s = loop[0]
    return segs


def render_music(m: np.ndarray, segs: list[tuple[float, float, float]], total: float) -> np.ndarray:
    out = np.zeros((sec(total), 2), dtype=np.float32)
    x = sec(XFADE)
    ramp = np.linspace(0, 1, x, dtype=np.float32)[:, None]
    for i, (v, s, n) in enumerate(segs):
        if s < 0:
            continue
        a, b = sec(v), sec(v + n)
        piece = m[sec(s): sec(s) + (b - a) + x]
        piece = np.pad(piece, ((0, max(0, b - a + x - len(piece))), (0, 0)))
        piece[:x] *= ramp                       # fades in over the previous segment's tail, never clicks
        if i + 1 < len(segs):                   # tail of x samples overlaps the next segment
            piece[b - a: b - a + x] *= ramp[::-1]
            end = min(len(out), b + x)
            out[a:end] += piece[: end - a]
        else:
            out[a:b] += piece[: b - a]
    return out


def envelope(voice: np.ndarray) -> np.ndarray:
    """Speech activity from 0 to 1 with a fast attack and a slow release."""
    hop = sec(0.01)
    frames = voice[: len(voice) // hop * hop].reshape(-1, hop)
    db = 20 * np.log10(np.sqrt((frames ** 2).mean(axis=1)) + 1e-9)
    active = np.clip((db + 45) / 20, 0, 1)
    out = np.zeros_like(active)
    level = 0.0
    for i, v in enumerate(active):
        level += (v - level) * (0.5 if v > level else 0.035)
        out[i] = level
    env = np.repeat(out, hop)
    return np.pad(env, (0, max(0, len(voice) - len(env))))[: len(voice)]


def end_sweep(m: np.ndarray, start: float) -> np.ndarray:
    """One-pole low-pass that closes from 18 kHz to 300 Hz over the ending."""
    s = sec(start)
    tail = m[s:].copy()
    k = np.linspace(0, 1, len(tail))
    alpha = 1 - np.exp(-2 * np.pi * (18000 * (300 / 18000) ** k) / SR)
    y = np.zeros(2, dtype=np.float64)
    for i in range(len(tail)):
        y += alpha[i] * (tail[i] - y)
        tail[i] = y
    out = m.copy()
    out[s:] = tail
    return out


# ---------- a generated beat on top of a found track ----------

# Each part of the beat is levelled against the track's own energy in that part's band, measured while the beat
# plays (dB). Claps and kicks are sparse, so their hits come out about 9 dB above these averages.
BEAT_PARTS = {"kick": ("kick",), "clap": ("clap", "snare"), "hat": ("hat", "crash")}
BEAT_BANDS = {"kick": (40, 120), "clap": (2000, 6000), "hat": (6000, 16000)}
BEAT_DB = {"light": {"kick": -10.0, "clap": -9.0, "hat": -12.0}, "strong": {"kick": -6.0, "clap": -6.0, "hat": -9.0}}


def attack_curve(x: np.ndarray) -> np.ndarray:
    """Attack strength every millisecond: the rise of a 2 ms loudness envelope above 1 kHz, in log terms."""
    from scipy.signal import butter, sosfiltfilt

    high = sosfiltfilt(butter(2, 1000, "high", fs=SR, output="sos"), x)
    e = np.sqrt(np.convolve(high ** 2, np.ones(96) / 96, mode="same")[::48])
    le = np.log(e + 1e-5)
    return np.maximum(0, np.diff(le, prepend=le[0]))


def composer():
    """compose_music.py from this folder, for its instruments, without leaving bytecode next to the scripts."""
    sys.dont_write_bytecode = True
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import compose_music

    return compose_music


def beat_layer(an: dict, segs: list[tuple[float, float, float]], drop_at: float, total: float, mode: str) -> list:
    """Drums in video time on the edited track's grid: [(time, instrument, velocity), ...]."""
    rng = np.random.default_rng(5)
    T, t0 = an["beat"], an["grid_offset"]
    bar = 4 * T
    kicks, snares = an["kick_beats"], an["snare_beats"]
    sw = an.get("swing") or {}
    e8, e16, ea = sw.get("eighth") or 0.5, sw.get("sixteenth"), sw.get("a")
    late = float(an.get("snare_offset") or 0.0)

    def src(v: float) -> float | None:
        for vs, ss, n in segs:
            if vs - 1e-9 <= v < vs + n:
                return ss + (v - vs) if ss >= 0 else None
        return None

    def hit(flags: list[int], v: float) -> bool:
        s = src(v)
        i = int(round((s - t0) / T)) if s is not None else -1
        return 0 <= i < len(flags) and bool(flags[i])

    def drums(v: float) -> bool:
        s = src(v)
        return s is not None and any(b["drums"] for b in an["bars"] if b["start"] - 1e-6 <= s < b["start"] + bar - 1e-6)

    k0, k1 = int(np.floor(-drop_at / bar)), int(np.ceil((total - drop_at) / bar))
    on = {k: drums(drop_at + (k + 0.125) * bar) and drums(drop_at + (k + 0.625) * bar) for k in range(k0 - 1, k1 + 2)}
    hats = [(0.0, 0.34), (e8, 0.26)] + ([(e16, 0.15), (ea, 0.15)] if e16 is not None and ea is not None else [])
    events = []
    for k in range(k0, k1 + 1):
        s = drop_at + k * bar
        if not on[k]:
            if on[k + 1] and s + 3 * T > 0:            # a fill into the drums coming (back) in
                events += [(s + b * T + late, "snare", 0.2 + 0.12 * j) for j, b in enumerate((3.0, 3.25, 3.5, 3.75))]
            continue
        entry = not on[k - 1]
        if entry and s > 0:
            events.append((s, "crash", 0.2))
        for p in range(4):
            v = s + p * T
            if p == 0 and (entry or hit(kicks, v)):
                events.append((v, "kick", 0.85))
            elif mode == "strong" and p == 2 and hit(kicks, v):
                events.append((v, "kick", 0.7))
            if p in (1, 3) and hit(snares, v):
                events.append((v + late, "clap", 0.7))
                if mode == "strong":
                    events.append((v + late, "snare", 0.32))
            for q, vel in hats:
                if q not in (0.0, e8) and rng.random() < 0.2:
                    continue
                events.append((v + q * T, "hat", vel * rng.uniform(0.85, 1.15)))
    return [e for e in events if 0 <= e[0] < total]


def render_beat(events: list, total: float, mode: str) -> dict[str, np.ndarray]:
    """The beat's parts (kick, clap, hat), each a mono signal in video time."""
    cm = composer()
    rng = np.random.default_rng(5)
    parts = {}
    for part, kinds in BEAT_PARTS.items():
        bus = np.zeros(sec(total))
        for t, kind, vel in events:
            if kind in kinds:
                snd = {"kick": lambda: cm.kick(vel, rng, decay=0.16 if mode == "light" else 0.22), "clap": lambda: cm.clap(vel, rng),
                       "snare": lambda: cm.snare(vel, rng), "hat": lambda: cm.hat(vel, rng), "crash": lambda: cm.crash(vel, rng)}[kind]()
                cm.add(bus, t, snd)
        bus = np.tanh(1.3 * cm.lp(bus, 12000)) / np.tanh(1.3)
        parts[part] = cm.hp(bus, 60) if mode == "light" and part == "kick" else bus
    return parts


def level_beat(parts: dict[str, np.ndarray], music: np.ndarray, sel: slice, mode: str) -> tuple[np.ndarray, dict]:
    """Sum the parts, each at BEAT_DB against the track's energy in its band."""
    from scipy.signal import butter, sosfiltfilt

    out, gains = np.zeros_like(music), {}
    for part, x in parts.items():
        sos = butter(4, BEAT_BANDS[part], "band", fs=SR, output="sos")
        mine = float(np.sqrt((sosfiltfilt(sos, x[sel]) ** 2).mean()))
        if mine < 1e-9:
            continue
        theirs = float(np.sqrt((sosfiltfilt(sos, music[sel]) ** 2).mean()))
        g = 10 ** (BEAT_DB[mode][part] / 20) * theirs / mine
        out += g * x
        gains[part] = BEAT_DB[mode][part]
    return out, gains


def lock(music: np.ndarray, events: list, total: float, mode: str, start: float, end: float) -> tuple[dict[str, np.ndarray], dict]:
    """Lock the beat to the track's own hits. First the whole beat shifts onto the track's attacks (the best
    cross-correlation within 40 ms), then every kick and clap moves onto the attack of the hit it doubles,
    when there is a clear one within 12 ms, because many tracks are played a little off the grid.
    Returns the rendered parts of the beat and a summary in milliseconds."""
    a = attack_curve(music)
    b = attack_curve(sum(render_beat(events, total, mode).values()))
    r0 = max(40, int(start * 1000))
    r1 = max(r0 + 1, min(min(len(a), len(b)) - 41, int(end * 1000)))
    lags = np.arange(-40, 41)
    sc = np.array([float(np.dot(a[r0:r1], b[r0 - L: r1 - L])) for L in lags])
    j = int(np.argmax(sc))
    shift = float(lags[j])
    if 0 < j < len(lags) - 1:
        y0, y1, y2 = sc[j - 1: j + 2]
        shift += 0.5 * (y0 - y2) / (y0 - 2 * y1 + y2 + 1e-12)

    def peak(ms: float, reach: int) -> tuple[float, float]:
        c = int(round(ms))
        lo, hi = max(0, c - reach), min(len(a), c + reach + 1)
        if hi <= lo:
            return ms, 0.0
        k = lo + int(np.argmax(a[lo:hi]))
        if 0 < k < len(a) - 1:                 # parabolic refinement between milliseconds
            y0, y1, y2 = a[k - 1: k + 2]
            return k + 0.5 * (y0 - y2) / (y0 - 2 * y1 + y2 + 1e-12), float(y1)
        return float(k), float(a[k])

    doubled = [i for i, (t, kind, _) in enumerate(events) if kind in ("kick", "clap") and start <= t <= end]
    found = {i: peak(events[i][0] * 1000 + shift, 12) for i in doubled}
    strong = np.median([v for _, v in found.values()]) if found else 0.0
    moved, fixes = list(events), []
    for i, (ms, v) in found.items():
        t, kind, vel = events[i]
        if v >= 0.5 * strong:
            fixes.append(ms - (t * 1000 + shift))
            moved[i] = (ms / 1000, kind, vel)
        else:
            moved[i] = (t + shift / 1000, kind, vel)
    moved = [(t + shift / 1000, k, v) if i not in found else (t, k, v) for i, (t, k, v) in enumerate(moved)]
    hats = [peak(t * 1000, 12)[0] - t * 1000 for t, kind, _ in moved if kind == "hat" and start <= t <= end]
    fx = np.abs(fixes) if fixes else np.zeros(1)
    return render_beat(moved, total, mode), {
        "shift_ms": round(shift, 2), "snapped": len(fixes), "doubled": len(doubled),
        "snap_ms": {"median": round(float(np.median(fx)), 2), "max": round(float(fx.max()), 2)},
        "hat_ms": round(float(np.median(np.abs(hats))), 2) if hats else None,
    }


# ---------- sound effects, all synthesized here ----------

SFX_DB = {"whoosh": -24, "swipe": -27, "pop": -27, "tick": -35, "type": -35, "impact": -17, "riser": -26, "ding": -25}
SFX_LEVEL = {"light": 0.0, "medium": 4.0}


def moving_band(n: int, center, width: float, rng) -> np.ndarray:
    """Noise through a band whose centre moves over time (center: seconds -> Hz), by short-time FFT."""
    nfft, hop = 1024, 256
    x = rng.standard_normal(n + nfft)
    win = np.hanning(nfft)
    f = np.maximum(np.fft.rfftfreq(nfft, 1 / SR), 1.0)
    out, norm = np.zeros(len(x)), np.zeros(len(x))
    for a in range(0, len(x) - nfft, hop):
        mask = np.exp(-0.5 * (np.log2(f / center(a / SR)) / width) ** 2)
        out[a:a + nfft] += np.fft.irfft(np.fft.rfft(x[a:a + nfft] * win) * mask) * win
        norm[a:a + nfft] += win ** 2
    y = (out / np.maximum(norm, 1e-6))[:n]
    return y / (np.abs(y).max() + 1e-9)


def stereo(mono: np.ndarray, pan_from: float = 0.0, pan_to: float | None = None) -> np.ndarray:
    pan = np.linspace(pan_from, pan_from if pan_to is None else pan_to, len(mono))   # -1 left .. 1 right
    th = (pan + 1) * np.pi / 4
    return np.stack([mono * np.cos(th), mono * np.sin(th)], axis=1) * np.sqrt(2)


def sfx_sound(kind: str, dur: float | None, rng) -> tuple[np.ndarray, float]:
    """(stereo sound, offset of its landing point from its start)."""
    if kind in ("whoosh", "swipe"):
        d = 0.55 if kind == "whoosh" else 0.3
        n = int(d * SR)
        lo, hi = (350, 3200) if kind == "whoosh" else (800, 5000)
        center = lambda t: lo * (hi / lo) ** min(1, t / (0.7 * d)) if t < 0.7 * d else hi * (0.4 ** ((t - 0.7 * d) / (0.3 * d)))
        u = np.arange(n) / n
        env = np.where(u < 0.7, smoothstep(u / 0.7) ** 1.5, np.exp(-(u - 0.7) / 0.08))
        side = rng.choice([-1, 1])
        return stereo(moving_band(n, center, 0.45, rng) * env, -0.6 * side, 0.6 * side), 0.7 * d
    if kind == "riser":
        d = dur or 1.0
        n = int(d * SR)
        u = np.arange(n) / n
        return stereo(moving_band(n, lambda t: 300 * (5000 / 300) ** min(1, t / d), 0.35, rng) * u ** 2), d
    if kind == "pop":
        t = np.arange(int(0.12 * SR)) / SR
        f = 420 + 480 * np.exp(-t / 0.025)
        y = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.minimum(1, t / 0.002) * np.exp(-t / 0.045)
        return stereo(y, rng.uniform(-0.2, 0.2)), 0.0
    if kind in ("tick", "type"):
        def one() -> np.ndarray:
            t = np.arange(int(0.02 * SR)) / SR
            click = rng.standard_normal(len(t)) * np.exp(-t / 0.0015)
            ping = np.sin(2 * np.pi * rng.uniform(2600, 3400) * t) * np.exp(-t / 0.004)
            return (0.7 * click + 0.5 * ping) * rng.uniform(0.7, 1.05)
        if kind == "tick":
            return stereo(one(), rng.uniform(-0.3, 0.3)), 0.0
        d = dur or 0.8
        y = np.zeros(int((d + 0.05) * SR))
        at = 0.0
        while at < d:
            s0 = int(at * SR)
            k = one()
            y[s0:s0 + len(k)] += k[: len(y) - s0]
            at += rng.uniform(0.055, 0.095)
        return stereo(y, rng.uniform(-0.2, 0.2)), 0.0
    if kind == "impact":
        t = np.arange(int(1.4 * SR)) / SR
        f = 38 + 32 * np.exp(-t / 0.12)
        sub = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.minimum(1, t / 0.003) * np.exp(-t / 0.35)
        noise = rng.standard_normal(len(t))
        thump = np.convolve(noise, np.ones(120) / 120, mode="same") * np.exp(-t / 0.08) * 3
        tail = np.convolve(noise, np.ones(12) / 12, mode="same") * np.exp(-t / 0.5) * 0.18
        bright = np.diff(noise, prepend=0) * np.exp(-t / 0.05) * 0.12
        return stereo(np.tanh(1.4 * (sub + thump + tail + bright)) / np.tanh(1.4)), 0.0
    if kind == "ding":
        t = np.arange(int(1.0 * SR)) / SR
        def bell(f0: float) -> np.ndarray:
            return sum(a * np.sin(2 * np.pi * f0 * r * t) * np.exp(-t / dcy) for r, a, dcy in ((1, 1, 0.6), (2.76, 0.35, 0.3), (5.4, 0.15, 0.15)))
        y = bell(1318.5) * np.minimum(1, t / 0.002)
        late = int(0.09 * SR)
        y[late:] += bell(1661.2)[: len(y) - late] * 0.9
        return stereo(y / (np.abs(y).max() + 1e-9), 0.15), 0.0
    raise ValueError(f"unknown sound effect kind {kind!r}")


def sfx_bus(events: list[dict], total: float, level: str) -> np.ndarray:
    out = np.zeros((sec(total), 2), dtype=np.float32)
    rng = np.random.default_rng(11)
    for e in events:
        snd, land = sfx_sound(e["kind"], e.get("dur"), rng)
        gain = 10 ** ((SFX_DB[e["kind"]] + SFX_LEVEL[level]) / 20) * float(e.get("gain", 1))
        start = sec(float(e["t"]) - land)
        a, b = max(0, start), min(len(out), start + len(snd))
        if b > a:
            out[a:b] += (snd[a - start: b - start] / (np.abs(snd).max() + 1e-9) * gain).astype(np.float32)
    return out


def loudness(path: Path) -> tuple[float, float]:
    log = subprocess.run(
        ["ffmpeg", "-hide_banner", "-nostats", "-i", str(path), "-af", "ebur128=peak=true", "-f", "null", "-"],
        capture_output=True, text=True,
    ).stderr
    i = float(re.findall(r"I:\s+(-?[\d.]+) LUFS", log)[-1])
    tp = float(re.findall(r"Peak:\s+(-?[\d.]+|-inf) dBFS", log)[-1])
    return i, tp


def master(raw: Path, dst: Path, target: float) -> tuple[float, float]:
    measured, _ = loudness(raw)
    gain = target - measured
    for _ in range(3):
        subprocess.run(
            ["ffmpeg", "-v", "error", "-y", "-i", str(raw), "-af",
             f"volume={gain:.2f}dB,alimiter=limit=-1.5dB:attack=5:release=60:level=disabled",
             "-ar", str(SR), "-c:a", "pcm_s16le", str(dst)],
            check=True,
        )
        i, tp = loudness(dst)
        if abs(i - target) <= 0.3:
            break
        gain += target - i   # the limiter took some level away; push a little more
    return i, tp


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("narration", type=Path)
    ap.add_argument("--music", type=Path)
    ap.add_argument("--analysis", type=Path)
    ap.add_argument("--out-dir", type=Path, required=True)
    ap.add_argument("--lead-in", type=float, default=2.0)
    ap.add_argument("--drop", type=float)
    ap.add_argument("--drop-at", type=float)
    ap.add_argument("--cut", action="append", default=[])
    ap.add_argument("--outro", type=float, default=4.0)
    ap.add_argument("--fade", type=float, default=3.0)
    ap.add_argument("--bed-db", type=float, default=-7.0)
    ap.add_argument("--duck-db", type=float, default=-6.0)
    ap.add_argument("--target-lufs", type=float, default=-14.0)
    ap.add_argument("--mp3-kbps", type=int, default=192)
    ap.add_argument("--beat", choices=["light", "strong", "off"], default="light", help="generated beat on top of a found track")
    ap.add_argument("--sfx", type=Path, help="sound effects exported by render_video.py --export-sfx")
    ap.add_argument("--sfx-level", choices=["light", "medium", "off"], default="light")
    a = ap.parse_args()
    a.out_dir.mkdir(parents=True, exist_ok=True)

    voice = decode(a.narration, 1)[:, 0]
    narr_start = a.lead_in
    narr_end = narr_start + len(voice) / SR
    info: dict = {"narration": {"start": round(narr_start, 3), "end": round(narr_end, 3)}, "music": None}

    if a.music:
        if not a.analysis:
            sys.exit("--music needs --analysis (run analyze_music.py first)")
        an = json.loads(a.analysis.read_text())
        T = an["beat"]
        bar = 4 * T
        drop = a.drop if a.drop is not None else an["first_drum_downbeat"]
        drop_at = a.drop_at if a.drop_at is not None else a.lead_in
        cuts = sorted(tuple(map(float, c.split(":"))) for c in a.cut)
        for c0, c1 in cuts:
            beats = (c1 - c0) / T
            if abs(beats - round(beats)) > 0.05:
                print(f"warning: cut {c0}:{c1} is {beats:.2f} beats; whole beats keep the grid (and the visuals) in time")
        # Ending: outro after the last word, rounded up to a bar line of the video beat grid.
        total = narr_end + a.outro
        total = float(drop_at + np.ceil((total - drop_at) / bar - 1e-6) * bar)
        drum_bars = [b for b in an["bars"] if b["drums"]]
        loop_from = drop
        loop_to = (drum_bars[-1]["start"] + bar) if drum_bars else an["duration"]
        loop_to = float(loop_from + max(1, np.floor((min(loop_to, an["duration"]) - loop_from) / bar)) * bar)
        segs = plan_segments(drop - drop_at, total, an["duration"], cuts, (loop_from, loop_to))
        m = render_music(decode(a.music, 2), segs, total)
        fade_from = total - a.fade
        info["beat"] = {"mode": "off"}
        if a.beat != "off" and an.get("composed"):
            info["beat"]["reason"] = "a composed track has its own drums"
        elif a.beat != "off":
            jitter = an.get("grid_jitter_ms")
            if "kick_beats" not in an:
                info["beat"]["reason"] = "music.json comes from an older analyze_music.py; run it again"
            elif jitter is None or jitter > 8:
                info["beat"]["reason"] = "the track's own beat is not steady enough to lock a generated beat to"
            else:
                events = beat_layer(an, segs, drop_at, total, a.beat)
                first = min((t for t, _, _ in events), default=fade_from)
                parts, fit = lock(m.mean(axis=1), events, total, a.beat, max(first, drop_at), fade_from)
                layer, levels = level_beat(parts, m.mean(axis=1), slice(sec(max(first, 0)), sec(fade_from)), a.beat)
                m = m + layer[:, None].astype(np.float32)
                counts = {k: sum(1 for e in events if e[1] == k) for k in ("kick", "clap", "snare", "hat", "crash")}
                info["beat"] = {"mode": a.beat, "level_db": levels, "counts": counts, **fit}
        m = end_sweep(m, fade_from)
        m *= MUSIC_RMS / (np.sqrt((m[sec(max(0, drop_at)):sec(fade_from)] ** 2).mean()) + 1e-9)

        # Drum activity in video time, mapped through the edit.
        rate = an["drums_rate"]
        src_env = np.array(an["drums"])
        vt = np.arange(int(total * rate) + 1) / rate
        drums = np.zeros_like(vt)
        for v, s, n in segs:
            if s < 0:
                continue
            sel = (vt >= v) & (vt < v + n)
            idx = np.clip(((vt[sel] - v + s) * rate).round().astype(int), 0, len(src_env) - 1)
            drums[sel] = src_env[idx]
        drums *= 1 - smoothstep((vt - fade_from) / max(a.fade, 1e-3))
        info["music"] = {
            "source": str(a.music),
            "bpm": round(60 / T, 3),
            "downbeat": round(drop_at, 4),
            "drumsRate": rate,
            "drums": [round(float(d), 3) for d in drums],
            "fadeOut": [round(fade_from, 3), round(total, 3)],
            "segments": [{"video": [round(v, 3), round(v + n, 3)], "source": [round(s, 3), round(s + n, 3)] if s >= 0 else None} for v, s, n in segs],
        }
    else:
        total = narr_end + max(1.0, min(a.outro, 2.0))
        m = np.zeros((sec(total), 2), dtype=np.float32)

    n = sec(total)
    v = np.zeros(n, dtype=np.float32)
    v[sec(narr_start): sec(narr_start) + len(voice)] = voice[: n - sec(narr_start)]
    v *= VOICE_RMS / (np.sqrt((voice ** 2).mean()) + 1e-9)
    t = np.arange(n) / SR
    into = smoothstep((t - (narr_start - 0.25)) / 0.5)
    leave = smoothstep((t - (narr_end + 0.05)) / 0.6)
    gain = 10 ** ((a.bed_db * into * (1 - leave) + a.duck_db * envelope(v)[:n]) / 20)
    fade_from = total - a.fade
    gain *= 1 - smoothstep((t - fade_from) / max(a.fade, 1e-3))
    mix = m[:n] * gain[:, None] + v[:, None]
    sfx_count = 0
    if a.sfx and a.sfx_level != "off":
        events = json.loads(a.sfx.read_text())["events"]
        mix = mix + sfx_bus(events, total, a.sfx_level)[:n]
        sfx_count = len(events)
    mix /= max(1.0, np.abs(mix).max() / 0.98)

    raw, wav, mp3 = a.out_dir / "mix-raw.wav", a.out_dir / "master.wav", a.out_dir / "master.mp3"
    write_wav(raw, mix)
    integrated, peak = master(raw, wav, a.target_lufs)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(wav), "-c:a", "libmp3lame", "-b:a", f"{a.mp3_kbps}k", str(mp3)], check=True)

    beat = info.pop("beat", {"mode": "off"})
    info = {"duration": round(total, 3), **info, "beat": beat, "sfx": {"count": sfx_count, "level": a.sfx_level if sfx_count else "off"},
            "loudness": {"integrated_lufs": integrated, "true_peak_dbfs": peak}}
    (a.out_dir / "mix.json").write_text(json.dumps(info, indent=1))
    msg = f"{wav} ({total:.2f}s, narration {narr_start:.2f}-{narr_end:.2f}s, {integrated:.1f} LUFS, peak {peak:.1f} dBFS)"
    if beat["mode"] != "off":
        c = beat["counts"]
        msg += (f"\nbeat ({beat['mode']}): {c['kick']} kicks, {c['clap']} claps, {c['snare']} snares, {c['hat']} hi-hats, {c['crash']} crashes,"
                f" shifted {beat['shift_ms']:+.1f} ms onto the track; {beat['snapped']} of {beat['doubled']} kicks and claps moved onto"
                f" the track's own hits (by {beat['snap_ms']['median']:.1f} ms, at most {beat['snap_ms']['max']:.1f})"
                + (f"; hi-hats sit {beat['hat_ms']:.1f} ms from the track's attacks" if beat["hat_ms"] is not None else ""))
    elif beat.get("reason"):
        msg += f"\nbeat: left out, because {beat['reason']}"
    if sfx_count:
        msg += f"\nsound effects: {sfx_count} ({a.sfx_level})"
    if info["music"]:
        msg += f"\nmusic: {info['music']['bpm']} BPM, beat 0 at {info['music']['downbeat']}s, fade {info['music']['fadeOut'][0]}-{total:.2f}s"
        for s in info["music"]["segments"]:
            msg += f"\n  video {s['video'][0]:7.2f}-{s['video'][1]:7.2f}s  <- source {s['source'] if s['source'] else 'silence'}"
    print(msg)


if __name__ == "__main__":
    main()
