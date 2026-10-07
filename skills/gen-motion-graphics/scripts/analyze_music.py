# /// script
# requires-python = ">=3.12"
# dependencies = ["librosa>=1.0", "numpy"]
# ///
"""Analyse a music track for beat-synced editing.

Measures the tempo and a constant beat grid, estimates which beat starts each bar, and measures
how loud the drums are in every bar, so you can pick where the drums drop in, where the breaks
are, and which bars can be cut or looped. Writes music.json for mix_audio.py and prints a table.

It also measures what mix_audio.py needs to lay a generated beat on top of the track: the grid to
about a millisecond (fitted to the attacks on the beats), how steady the track's own beat is, which
beats have a kick or a snare, how late the snare sits, and where the hi-hats fall (the swing).

Usage: uv run --script analyze_music.py track.mp3 music.json

music.json:
  bpm, beat (seconds per beat), grid_offset (time of beat 0), downbeat_phase (0..3),
  downbeats (bar start times), first_drum_downbeat (the drop), bars (per-bar levels),
  drums_rate + drums (0..1 drum activity sampled drums_rate times per second, source time),
  grid_jitter_ms (how far the attacks on the beats stray from the grid), kick_beats and snare_beats (0 or 1 per
  beat of the grid), snare_offset (seconds after the beat), swing (where the hi-hats fall, as
  fractions of a beat: eighth, sixteenth and a, the last two null without sixteenth notes).
All times are seconds in the source file. Downbeats are an estimate: kick-heavy beats are taken as
beat 1. Treat them as a starting point and look at the bar table.
"""

import argparse
import json
import sys
from pathlib import Path

import librosa
import numpy as np

SR = 22050
HOP = 128
DRUMS_RATE = 20
FINE_HOP = 22                 # about a millisecond
FINE = FINE_HOP / SR


def fold_bpm(bpm: float) -> float:
    while bpm > 140:
        bpm /= 2
    while bpm < 70:
        bpm *= 2
    return bpm


def band_onsets(y: np.ndarray, fmin: float, fmax: float) -> np.ndarray:
    S = np.abs(librosa.stft(y, n_fft=2048, hop_length=HOP))
    freqs = librosa.fft_frequencies(sr=SR, n_fft=2048)
    band = S[(freqs >= fmin) & (freqs < fmax)]
    flux = np.maximum(0, np.diff(np.log1p(band), axis=1)).sum(axis=0)
    return np.concatenate([[0], flux])


def fine_onsets(x: np.ndarray) -> np.ndarray:
    """Attack strength about every millisecond: the rise of a 2 ms loudness envelope, in log terms."""
    e = np.sqrt(np.convolve(x ** 2, np.ones(44) / 44, mode="same")[::FINE_HOP])
    le = np.log(e + 1e-4)
    return np.convolve(np.maximum(0, np.diff(le, prepend=le[0])), np.ones(3) / 3, mode="same")


def attack_near(d: np.ndarray, t: float, lo: float, hi: float) -> tuple[float, float] | None:
    """Time and strength of the strongest attack between t + lo and t + hi."""
    a, b = max(0, int((t + lo) / FINE)), min(len(d), int((t + hi) / FINE) + 1)
    if b - a < 3:
        return None
    i = a + int(np.argmax(d[a:b]))
    return i * FINE, float(d[i])


def refine_grid(d: np.ndarray, t0: float, T: float, beats: list[int]) -> tuple[float, float, float | None, int]:
    """Fit t = t0 + i * T to the attacks on these beats (weighted least squares, outliers out).
    Returns the new t0 and T, the remaining scatter in milliseconds, and the number of beats used."""
    pts = [(i, *r) for i in beats if (r := attack_near(d, t0 + i * T, -0.025, 0.025))]
    if len(pts) < 8:
        return t0, T, None, len(pts)
    i_, t_, w_ = (np.array(v, dtype=float) for v in zip(*pts))
    keep = np.ones(len(i_), dtype=bool)
    for _ in range(3):
        A = np.stack([np.ones(int(keep.sum())), i_[keep]], axis=1)
        sw = np.sqrt(w_[keep])
        c0, c1 = np.linalg.lstsq(A * sw[:, None], t_[keep] * sw, rcond=None)[0]
        r = t_ - (c0 + c1 * i_)
        keep = np.abs(r) < max(0.006, 2.5 * float(np.std(r[keep])))
    return float(c0), float(c1), float(np.std(r[keep]) * 1000), int(keep.sum())


def swing(d: np.ndarray, t0: float, T: float, beats: list[int]) -> dict:
    """Where the hi-hats fall within a beat: high-frequency attacks folded over the beat."""
    B = 240
    fold = np.zeros(B)
    for i in beats:
        idx = np.clip(np.round((t0 + (i + np.arange(B) / B) * T) / FINE).astype(int), 0, len(d) - 2)
        fold += np.maximum.reduce([d[np.clip(idx + k, 0, len(d) - 1)] for k in (-1, 0, 1)])
    fold = np.convolve(fold / max(1, len(beats)), np.ones(5) / 5, mode="same")
    base = float(np.median(fold))

    def peak(lo: float, hi: float) -> tuple[float, float]:
        a, b = int(lo * B), int(hi * B)
        j = a + int(np.argmax(fold[a:b]))
        if 0 < j < B - 1:                     # parabolic refinement between bins
            y0, y1, y2 = fold[j - 1: j + 2]
            j = j + 0.5 * (y0 - y2) / (y0 - 2 * y1 + y2 + 1e-12)
        return j / B, float(fold[int(round(j)) % B]) - base

    p8, s8 = peak(0.42, 0.70)
    p16, s16 = peak(0.17, 0.40)
    pa, sa = peak(0.67, 0.93)
    sixteenths = s8 > 0 and s16 > 0.35 * s8 and sa > 0.35 * s8
    return {"eighth": round(p8, 3), "sixteenth": round(p16, 3) if sixteenths else None, "a": round(pa, 3) if sixteenths else None}


def comb_grid(env: np.ndarray, duration: float, bpm_hint: float) -> tuple[float, float]:
    """Constant grid t_k = t0 + k * T that collects the most drum onset energy.

    Searches T within 4 % of the hint in 0.2 ms steps and t0 in 4 ms steps. Beat trackers can be off
    by a few BPM on swung lo-fi drums, which drifts by a second over a minute; this does not.
    """
    fr = HOP / SR
    peak = np.maximum.reduce([np.roll(env, s) for s in (-1, 0, 1)])
    T0 = 60.0 / bpm_hint
    best = (-1.0, T0, 0.0)
    for T in np.arange(T0 * 0.96, T0 * 1.04, 0.0002):
        t0s = np.arange(0, T, 0.004)
        k = np.arange(int((duration - T) / T))
        idx = np.clip(np.round((t0s[:, None] + k[None, :] * T) / fr).astype(int), 0, len(env) - 1)
        sc = peak[idx].sum(axis=1)
        i = int(np.argmax(sc))
        if sc[i] > best[0]:
            best = (float(sc[i]), float(T), float(t0s[i]))
    return best[2], best[1]


def main(src: Path, dst: Path) -> None:
    y, _ = librosa.load(str(src), sr=SR, mono=True)
    duration = len(y) / SR
    tempo, beat_frames = librosa.beat.beat_track(y=y, sr=SR, hop_length=512, start_bpm=90, units="frames")
    tempo = float(np.atleast_1d(tempo)[0])
    if len(beat_frames) < 8:
        sys.exit("too few beats found; is this track rhythmic?")

    # Percussive part for drum activity, kick and snare bands for the grid and the downbeat estimate.
    perc = librosa.effects.percussive(y, margin=3.0)
    kick = band_onsets(perc, 30, 150)
    snare = band_onsets(perc, 1500, 6000)
    frame_t = librosa.frames_to_time(np.arange(len(kick)), sr=SR, hop_length=HOP)
    t0, T = comb_grid(kick / (kick.max() + 1e-9) + 0.5 * snare / (snare.max() + 1e-9), duration, fold_bpm(tempo))
    bpm = 60 / T
    grid = np.arange(t0, duration, T)

    def at(env: np.ndarray, times: np.ndarray) -> np.ndarray:
        idx = np.clip(np.searchsorted(frame_t, times), 0, len(env) - 1)
        win = [env[max(0, i - 2): i + 3].max() for i in idx]
        return np.array(win)

    def rms_db(sig: np.ndarray, a: float, b: float) -> float:
        seg = sig[int(a * SR): int(b * SR)]
        return float(20 * np.log10(np.sqrt((seg ** 2).mean()) + 1e-9)) if len(seg) else -120.0

    # The drop: the first beat that has a kick or snare hit on it and from which the drums keep playing for
    # at least 3 of the next 4 beats. Energy alone is not enough: a fill or a pickup late in the beat before
    # would put the drop one beat early.
    beat_db = np.array([rms_db(perc, g, g + T) for g in grid])
    on = beat_db > np.percentile(beat_db, 75) - 9
    k_at, s_at = at(kick, grid), at(snare, grid)
    ref_k = np.percentile(k_at[on], 90) if on.any() else k_at.max()
    ref_s = np.percentile(s_at[on], 90) if on.any() else s_at.max()
    kick_hit = k_at > 0.35 * ref_k
    hit = kick_hit | (s_at > 0.35 * ref_s)
    # A drop lands with a kick. A snare fill just before it has no kick, so it does not count.
    drop_beat = next((i for i in range(len(on) - 3) if kick_hit[i] and on[i] and on[i: i + 4].sum() >= 3), None)
    if drop_beat is None:
        drop_beat = next((i for i in range(len(on) - 3) if hit[i] and on[i] and on[i: i + 4].sum() >= 3), None)
    # A fill that bleeds into the kick band can still pass; the real downbeat right after it hits much harder.
    if drop_beat is not None:
        ahead = [j for j in (drop_beat + 1, drop_beat + 2) if j < len(k_at) and k_at[j] >= 1.5 * k_at[drop_beat]]
        if ahead:
            drop_beat = max(ahead, key=lambda j: k_at[j])

    # The grid to about a millisecond, for a generated beat on top: the comb search is good to a few
    # milliseconds, enough for the visuals, but two drums that far apart would flam. The fit uses the
    # high-frequency attacks on the beats (hi-hats and the click of the kick): a kick's low end rises too
    # slowly to time. Snares often lag behind the grid on purpose, so they are measured on their own band.
    from scipy.signal import butter, sosfiltfilt
    snare_hit = s_at > 0.35 * ref_s
    d_high = fine_onsets(sosfiltfilt(butter(4, 5000, "high", fs=SR, output="sos"), perc))
    t0, T, jitter, fitted = refine_grid(d_high, t0, T, [i for i in range(len(grid)) if on[i]])
    bpm = 60 / T
    grid = t0 + np.arange(len(grid)) * T
    d_mid = fine_onsets(sosfiltfilt(butter(4, [1000, 5000], "band", fs=SR, output="sos"), perc))
    lags = [r[0] - (t0 + i * T) for i in range(len(grid)) if snare_hit[i] and not kick_hit[i] and on[i]
            if (r := attack_near(d_mid, t0 + i * T, -0.02, 0.045))]
    snare_offset = float(np.median(lags)) if len(lags) >= 6 else 0.0
    hats = swing(d_high, t0, T, [i for i in range(len(grid) - 1) if on[i]])

    # Bar phase: drums nearly always enter on beat 1, so the drop decides. The kick and snare pattern (kick on
    # 1 and 3, snare on 2 and 4) is only a fallback for tracks without a clear drop: half-time grooves put the
    # snare on 3 and would shift the bars by a beat.
    scores = []
    for p in range(4):
        one, three = k_at[p::4], k_at[(p + 2) % 4::4]
        two, four = s_at[(p + 1) % 4::4], s_at[(p + 3) % 4::4]
        n = min(len(one), len(three), len(two), len(four))
        scores.append(float(one[:n].mean() + 0.5 * three[:n].mean() + 0.5 * (two[:n].mean() + four[:n].mean())))
    phase = drop_beat % 4 if drop_beat is not None else int(np.argmax(scores))
    downbeats = grid[phase::4]

    bars = []
    for i, a in enumerate(downbeats):
        b = min(duration, a + 4 * T)
        bars.append({"bar": i, "start": round(float(a), 3), "rms_db": round(rms_db(y, a, b), 1), "drums_db": round(rms_db(perc, a, b), 1)})
    loud = np.array([x["drums_db"] for x in bars])
    ref = float(np.percentile(loud, 75)) if len(loud) else -20.0
    for x in bars:
        x["drums"] = x["drums_db"] > ref - 9
    first = float(grid[drop_beat]) if drop_beat is not None else next((x["start"] for x in bars if x["drums"]), float(downbeats[0]))

    # Drum activity envelope: percussive RMS in 50 ms steps, smoothed, 0..1 against the loud bars.
    step = SR // DRUMS_RATE
    n = len(perc) // step
    env = np.sqrt((perc[: n * step].reshape(n, step) ** 2).mean(axis=1))
    env = np.convolve(env, np.ones(5) / 5, mode="same")
    top = np.percentile(env, 90) + 1e-9
    drums = np.clip(env / top, 0, 1)

    out = {
        "source": str(src),
        "duration": round(duration, 3),
        "bpm": round(bpm, 3),
        "beat": round(T, 5),
        "grid_offset": round(t0, 4),
        "downbeat_phase": phase,
        "downbeats": [round(float(d), 4) for d in downbeats],
        "first_drum_downbeat": round(first, 4),
        "bars": bars,
        "drums_rate": DRUMS_RATE,
        "drums": [round(float(v), 3) for v in drums],
        "grid_jitter_ms": round(jitter, 2) if jitter is not None else None,
        "kick_beats": [int(bool(x)) for x in kick_hit],
        "snare_beats": [int(bool(x)) for x in snare_hit],
        "snare_offset": round(snare_offset, 4),
        "swing": hats,
    }
    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_text(json.dumps(out, indent=1))

    print(f"{src.name}: {duration:.1f}s, {bpm:.2f} BPM (librosa said {tempo:.1f}), beat {T:.4f}s, bar {4 * T:.3f}s")
    print(f"first drum downbeat (drop): {first:.3f}s   downbeat phase {phase} (scores {', '.join(f'{s:.1f}' for s in scores)})")
    if jitter is None:
        print(f"beat layer: too few clear beats ({fitted}) to fit the grid precisely; mix_audio.py will leave the generated beat out")
    else:
        steady = "steady, so a generated beat can be laid on top" if jitter <= 8 else "not steady, so mix_audio.py will leave the generated beat out"
        print(f"grid fitted to {fitted} beats: their attacks stray {jitter:.1f} ms from it ({steady})")
    shuffle = "straight" if abs(hats["eighth"] - 0.5) < 0.03 else f"swung, at {hats['eighth']:.2f} of a beat"
    sixteen = f", sixteenths at {hats['sixteenth']:.3f} and {hats['a']:.3f}" if hats["sixteenth"] else ", no sixteenths"
    print(f"snare {snare_offset * 1000:+.0f} ms from the beat; hi-hat eighths {shuffle}{sixteen}")
    print(" bar   start   level  drums")
    for x in bars:
        print(f"{x['bar']:4d} {x['start']:7.2f}s {x['rms_db']:6.1f} {x['drums_db']:6.1f}  {'drums' if x['drums'] else '-- no drums --'}")
    print(f"wrote {dst}")


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("track", type=Path, help="the music file (any format ffmpeg or librosa reads)")
    ap.add_argument("out", type=Path, help="music.json to write")
    a = ap.parse_args()
    main(a.track, a.out)
