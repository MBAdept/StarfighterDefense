"""
synthlib.py – small, self-contained DSP/synthesis toolkit used to generate every
sound effect and music track of "Starfighter Defense".

Everything here is original code: band-limited oscillators (PolyBLEP), a TPT
state-variable filter with per-sample cutoff, envelopes, noise colours, modal
resonators, a synthetic convolution reverb (no recorded impulse responses),
chorus / ping-pong delay, saturation, loudness measurement (BS.1770 via
pyloudnorm) and file writers (16-bit WAV, Ogg Vorbis via ffmpeg).

Run with /opt/tools/audiovenv/bin/python (numpy, scipy, numba, pedalboard,
soundfile, pyloudnorm).
"""
from __future__ import annotations

import functools
import os
import subprocess
import tempfile

import numpy as np
import scipy.signal as sps
import soundfile as sf
from numba import njit

SR = 44100
TAU = 2.0 * np.pi
RNG = np.random.default_rng(1986)


# --------------------------------------------------------------------------------------------
# basic helpers
# --------------------------------------------------------------------------------------------
def ns(sec: float) -> int:
    """seconds -> number of samples"""
    return max(0, int(round(sec * SR)))


def tarr(n: int) -> np.ndarray:
    return np.arange(n, dtype=np.float64) / SR


def db(x: float) -> float:
    return float(10.0 ** (x / 20.0))


def to_db(x: float) -> float:
    return 20.0 * np.log10(max(float(x), 1e-12))


def arr(x, n: int) -> np.ndarray:
    """broadcast scalar or array to float64 array of length n"""
    if np.isscalar(x):
        return np.full(n, float(x), dtype=np.float64)
    a = np.asarray(x, dtype=np.float64)
    if a.shape[0] == n:
        return a
    if a.shape[0] > n:
        return a[:n]
    out = np.empty(n)
    out[: a.shape[0]] = a
    out[a.shape[0]:] = a[-1] if a.shape[0] else 0.0
    return out


def midi_to_hz(m: float) -> float:
    return 440.0 * 2.0 ** ((m - 69.0) / 12.0)


def cents(c: float) -> float:
    return 2.0 ** (c / 1200.0)


def pad_to(x: np.ndarray, n: int) -> np.ndarray:
    if x.shape[0] >= n:
        return x[:n]
    shape = (n,) + x.shape[1:]
    out = np.zeros(shape)
    out[: x.shape[0]] = x
    return out


def mix_into(dst: np.ndarray, src: np.ndarray, start: int, gain: float = 1.0):
    """add src into dst at sample offset start (handles bounds, mono->stereo)"""
    if start >= dst.shape[0] or src.shape[0] == 0:
        return
    if start < 0:
        src = src[-start:]
        start = 0
    end = min(dst.shape[0], start + src.shape[0])
    seg = src[: end - start]
    if dst.ndim == 2 and seg.ndim == 1:
        dst[start:end] += gain * seg[:, None]
    else:
        dst[start:end] += gain * seg


def stereo(x: np.ndarray) -> np.ndarray:
    if x.ndim == 2:
        return x
    return np.stack([x, x], axis=1)


def mono(x: np.ndarray) -> np.ndarray:
    if x.ndim == 1:
        return x
    return x.mean(axis=1)


def pan(x: np.ndarray, p: float) -> np.ndarray:
    """constant-power pan, p in [-1, 1]; mono or stereo in -> stereo out"""
    a = (p + 1.0) * 0.25 * np.pi
    gl, gr = np.cos(a) * np.sqrt(2.0), np.sin(a) * np.sqrt(2.0)
    if x.ndim == 1:
        return np.stack([x * gl, x * gr], axis=1)
    out = x.copy()
    out[:, 0] *= gl
    out[:, 1] *= gr
    return out


def pan_dynamic(x: np.ndarray, p: np.ndarray) -> np.ndarray:
    """pan with per-sample position array (mono in)"""
    x = mono(x)
    p = arr(p, x.shape[0])
    a = (p + 1.0) * 0.25 * np.pi
    return np.stack([x * np.cos(a) * np.sqrt(2.0), x * np.sin(a) * np.sqrt(2.0)], axis=1)


def fade(x: np.ndarray, fin: float = 0.002, fout: float = 0.01) -> np.ndarray:
    x = x.copy()
    n_in, n_out = ns(fin), ns(fout)
    if n_in > 0:
        ramp = np.sin(np.linspace(0, np.pi / 2, n_in)) ** 2
        x[:n_in] *= ramp if x.ndim == 1 else ramp[:, None]
    if n_out > 0:
        ramp = np.cos(np.linspace(0, np.pi / 2, n_out)) ** 2
        x[-n_out:] *= ramp if x.ndim == 1 else ramp[:, None]
    return x


def normalize(x: np.ndarray, peak_db: float = -1.0) -> np.ndarray:
    m = np.max(np.abs(x))
    if m < 1e-12:
        return x
    return x * (db(peak_db) / m)


def remove_dc(x: np.ndarray, hz: float = 15.0) -> np.ndarray:
    sos = sps.butter(2, hz, "highpass", fs=SR, output="sos")
    return sps.sosfilt(sos, x, axis=0)


# --------------------------------------------------------------------------------------------
# oscillators
# --------------------------------------------------------------------------------------------
@njit(cache=True)
def _blep(t, dt):
    if t < dt:
        t = t / dt
        return t + t - t * t - 1.0
    elif t > 1.0 - dt:
        t = (t - 1.0) / dt
        return t * t + t + t + 1.0
    return 0.0


@njit(cache=True)
def _saw(freq, phase0):
    n = freq.shape[0]
    out = np.empty(n)
    ph = phase0
    for i in range(n):
        dt = freq[i] / 44100.0
        if dt < 1e-9:
            dt = 1e-9
        if dt > 0.45:
            dt = 0.45
        out[i] = 2.0 * ph - 1.0 - _blep(ph, dt)
        ph += dt
        while ph >= 1.0:
            ph -= 1.0
    return out


@njit(cache=True)
def _square(freq, pw, phase0):
    n = freq.shape[0]
    out = np.empty(n)
    ph = phase0
    for i in range(n):
        dt = freq[i] / 44100.0
        if dt < 1e-9:
            dt = 1e-9
        if dt > 0.45:
            dt = 0.45
        w = pw[i]
        v = 1.0 if ph < w else -1.0
        v += _blep(ph, dt)
        p2 = ph + 1.0 - w
        while p2 >= 1.0:
            p2 -= 1.0
        v -= _blep(p2, dt)
        out[i] = v
        ph += dt
        while ph >= 1.0:
            ph -= 1.0
    return out


@njit(cache=True)
def _leaky_integrate(x, freq):
    # turns a band-limited square into a band-limited triangle
    n = x.shape[0]
    out = np.empty(n)
    acc = 0.0
    for i in range(n):
        dt = freq[i] / 44100.0
        acc = acc + 4.0 * dt * x[i]
        acc *= 0.9995
        out[i] = acc
    return out


def phase(freq, n: int, phase0: float = 0.0) -> np.ndarray:
    """running phase in radians for (possibly time-varying) frequency"""
    f = arr(freq, n)
    return TAU * (np.cumsum(f) / SR) + phase0 - TAU * f[0] / SR


def sine(freq, n: int, phase0: float = 0.0) -> np.ndarray:
    return np.sin(phase(freq, n, phase0))


def saw(freq, n: int, phase0: float | None = None) -> np.ndarray:
    if phase0 is None:
        phase0 = RNG.random()
    return _saw(arr(freq, n), phase0)


def square(freq, n: int, pw=0.5, phase0: float | None = None) -> np.ndarray:
    if phase0 is None:
        phase0 = RNG.random()
    return _square(arr(freq, n), arr(pw, n), phase0)


def triangle(freq, n: int, phase0: float | None = None) -> np.ndarray:
    """triangle (naive – its harmonics fall off with 1/n^2, aliasing is negligible here)"""
    if phase0 is None:
        phase0 = RNG.random()
    p = (phase(freq, n) / TAU + phase0) % 1.0
    return 2.0 * np.abs(2.0 * p - 1.0) - 1.0


def supersaw(freq, n: int, voices: int = 7, detune_cents: float = 18.0, stereo_out: bool = True,
             spread: float = 0.9) -> np.ndarray:
    """JP-8000 style detuned saw stack, returns stereo (n,2) when stereo_out"""
    f = arr(freq, n)
    out = np.zeros((n, 2)) if stereo_out else np.zeros(n)
    for v in range(voices):
        d = 0.0 if voices == 1 else (v / (voices - 1) * 2.0 - 1.0)
        det = cents(d * detune_cents + RNG.uniform(-1.5, 1.5))
        s = _saw(f * det, RNG.random())
        g = 1.0 if v == voices // 2 else 0.75
        if stereo_out:
            out += pan(s * g, d * spread)
        else:
            out += s * g
    return out / np.sqrt(voices)


def fm(freq, n: int, ratio: float, index, fb: float = 0.0, phase0: float = 0.0) -> np.ndarray:
    """2-operator FM (phase modulation). index may be an envelope array."""
    f = arr(freq, n)
    mod = np.sin(phase(f * ratio, n))
    if fb:
        mod = np.sin(phase(f * ratio, n) + fb * mod)
    return np.sin(phase(f, n, phase0) + arr(index, n) * mod)


# --------------------------------------------------------------------------------------------
# noise
# --------------------------------------------------------------------------------------------
def white(n: int, rng=None) -> np.ndarray:
    rng = rng or RNG
    return rng.standard_normal(n)


def pink(n: int, rng=None) -> np.ndarray:
    """Paul Kellet's refined pink noise filter (via IIR approximation)"""
    w = white(n, rng)
    b = [0.049922035, -0.095993537, 0.050612699, -0.004408786]
    a = [1, -2.494956002, 2.017265875, -0.522189400]
    p = sps.lfilter(b, a, w)
    return p / (np.std(p) + 1e-12)


def brown(n: int, rng=None) -> np.ndarray:
    w = white(n, rng)
    b = sps.lfilter([1.0], [1.0, -0.995], w)
    b = remove_dc(b, 10.0)
    return b / (np.std(b) + 1e-12)


def crackle(n: int, density: float, rng=None, decay_ms: float = 1.5) -> np.ndarray:
    """sparse random impulses (density = impulses per second) with tiny decays"""
    rng = rng or RNG
    x = np.zeros(n)
    count = int(density * n / SR)
    if count <= 0:
        return x
    pos = rng.integers(0, n, count)
    x[pos] = rng.uniform(-1, 1, count) * rng.uniform(0.3, 1.0, count) ** 2
    k = np.exp(-np.arange(ns(decay_ms / 1000.0 * 6) + 1) / max(1, ns(decay_ms / 1000.0)))
    return sps.oaconvolve(x, k)[:n]


# --------------------------------------------------------------------------------------------
# envelopes
# --------------------------------------------------------------------------------------------
def env_points(points, n: int | None = None, curve: str = "lin") -> np.ndarray:
    """points: [(t_sec, value), ...]; returns envelope sampled at SR. curve 'lin' or 'exp'"""
    ts = np.array([p[0] for p in points], dtype=np.float64)
    vs = np.array([p[1] for p in points], dtype=np.float64)
    total = ns(ts[-1]) + 1 if n is None else n
    t = tarr(total)
    if curve == "exp":
        lv = np.log(np.maximum(vs, 1e-5))
        return np.exp(np.interp(t, ts, lv))
    return np.interp(t, ts, vs)


def adsr(dur: float, a: float, d: float, s: float, r: float, n_total: int | None = None,
         curve: float = 4.0) -> np.ndarray:
    """gate length dur (seconds); returns envelope of length dur + r (or n_total).
    curve > 0 makes decay/release exponential-ish."""
    n_gate = max(1, ns(dur))
    n_rel = ns(r)
    n = n_total if n_total is not None else n_gate + n_rel
    e = np.zeros(n)
    na, nd = max(1, ns(a)), max(1, ns(d))
    i = np.arange(n_gate)
    att = np.clip(i / na, 0, 1)
    att = 1.0 - (1.0 - att) ** 2  # slightly convex attack
    dec_t = np.clip((i - na) / nd, 0, 1)
    # make the decay reach exactly s at its end
    dec = s + (1 - s) * (np.exp(-curve * dec_t) - np.exp(-curve) * dec_t)
    g = np.where(i < na, att, dec)
    m = min(n, n_gate)
    e[:m] = g[:m]
    level = g[m - 1] if m > 0 else 0.0
    if n > n_gate and n_rel > 0:
        k = np.arange(min(n - n_gate, n_rel))
        rt = k / max(1, n_rel)
        e[n_gate:n_gate + k.shape[0]] = level * (np.exp(-curve * rt) - np.exp(-curve) * rt)
    return e


def exp_decay(n: int, tau: float, attack: float = 0.0) -> np.ndarray:
    t = tarr(n)
    e = np.exp(-t / max(tau, 1e-5))
    if attack > 0:
        e *= np.clip(t / attack, 0, 1)
    return e


def lfo(n: int, rate: float, phase0: float = 0.0, shape: str = "sine") -> np.ndarray:
    t = tarr(n)
    if shape == "sine":
        return np.sin(TAU * rate * t + phase0)
    if shape == "tri":
        p = (rate * t + phase0 / TAU) % 1.0
        return 4 * np.abs(p - 0.5) - 1
    if shape == "square":
        return np.sign(np.sin(TAU * rate * t + phase0))
    raise ValueError(shape)


# --------------------------------------------------------------------------------------------
# filters
# --------------------------------------------------------------------------------------------
@njit(cache=True)
def _svf(x, cutoff, q, mode):
    n = x.shape[0]
    out = np.empty(n)
    ic1 = 0.0
    ic2 = 0.0
    for i in range(n):
        fc = cutoff[i]
        if fc < 10.0:
            fc = 10.0
        if fc > 20000.0:
            fc = 20000.0
        g = np.tan(np.pi * fc / 44100.0)
        k = 1.0 / q[i]
        a1 = 1.0 / (1.0 + g * (g + k))
        a2 = g * a1
        a3 = g * a2
        v3 = x[i] - ic2
        v1 = a1 * ic1 + a2 * v3
        v2 = ic2 + a2 * ic1 + a3 * v3
        ic1 = 2.0 * v1 - ic1
        ic2 = 2.0 * v2 - ic2
        if mode == 0:
            out[i] = v2
        elif mode == 1:
            out[i] = v1
        elif mode == 2:
            out[i] = x[i] - k * v1 - v2
        else:
            out[i] = x[i] - k * v1  # notch
    return out


_MODES = {"lp": 0, "bp": 1, "hp": 2, "notch": 3}


def svf(x: np.ndarray, cutoff, q=0.707, mode: str = "lp") -> np.ndarray:
    """time-varying TPT state variable filter (12 dB/oct). Works on mono or stereo."""
    if x.ndim == 2:
        return np.stack([svf(x[:, c], cutoff, q, mode) for c in range(x.shape[1])], axis=1)
    n = x.shape[0]
    return _svf(x.astype(np.float64), arr(cutoff, n), arr(q, n), _MODES[mode])


def lp24(x, cutoff, q=0.707):
    """24 dB/oct lowpass: two cascaded SVFs (resonance on the second stage)"""
    return svf(svf(x, cutoff, 0.6, "lp"), cutoff, q, "lp")


def biquad(x: np.ndarray, kind: str, f0: float, q: float = 0.707, gain_db: float = 0.0) -> np.ndarray:
    """static RBJ biquad: lp, hp, bp, peak, lowshelf, highshelf"""
    A = 10 ** (gain_db / 40)
    w0 = TAU * min(f0, 0.49 * SR) / SR
    alpha = np.sin(w0) / (2 * q)
    cw = np.cos(w0)
    if kind == "lp":
        b = [(1 - cw) / 2, 1 - cw, (1 - cw) / 2]
        a = [1 + alpha, -2 * cw, 1 - alpha]
    elif kind == "hp":
        b = [(1 + cw) / 2, -(1 + cw), (1 + cw) / 2]
        a = [1 + alpha, -2 * cw, 1 - alpha]
    elif kind == "bp":
        b = [alpha, 0, -alpha]
        a = [1 + alpha, -2 * cw, 1 - alpha]
    elif kind == "peak":
        b = [1 + alpha * A, -2 * cw, 1 - alpha * A]
        a = [1 + alpha / A, -2 * cw, 1 - alpha / A]
    elif kind == "lowshelf":
        sq = 2 * np.sqrt(A) * alpha
        b = [A * ((A + 1) - (A - 1) * cw + sq), 2 * A * ((A - 1) - (A + 1) * cw), A * ((A + 1) - (A - 1) * cw - sq)]
        a = [(A + 1) + (A - 1) * cw + sq, -2 * ((A - 1) + (A + 1) * cw), (A + 1) + (A - 1) * cw - sq]
    elif kind == "highshelf":
        sq = 2 * np.sqrt(A) * alpha
        b = [A * ((A + 1) + (A - 1) * cw + sq), -2 * A * ((A - 1) + (A + 1) * cw), A * ((A + 1) + (A - 1) * cw - sq)]
        a = [(A + 1) - (A - 1) * cw + sq, 2 * ((A - 1) - (A + 1) * cw), (A + 1) - (A - 1) * cw - sq]
    else:
        raise ValueError(kind)
    b = np.array(b) / a[0]
    a = np.array(a) / a[0]
    return sps.lfilter(b, a, x, axis=0)


def butter(x: np.ndarray, kind: str, f, order: int = 4) -> np.ndarray:
    sos = sps.butter(order, f, {"lp": "lowpass", "hp": "highpass", "bp": "bandpass", "bs": "bandstop"}[kind],
                     fs=SR, output="sos")
    return sps.sosfilt(sos, x, axis=0)


def onepole_lp(x: np.ndarray, fc: float) -> np.ndarray:
    a = np.exp(-TAU * fc / SR)
    return sps.lfilter([1 - a], [1, -a], x, axis=0)


def resonator_bank(x: np.ndarray, freqs, decays, gains) -> np.ndarray:
    """parallel two-pole resonators (modal synthesis). decays: T60-ish seconds per mode"""
    out = np.zeros_like(x, dtype=np.float64)
    for f, d, g in zip(freqs, decays, gains):
        if f >= 0.48 * SR:
            continue
        r = np.exp(-6.91 / (d * SR))
        w = TAU * f / SR
        b = [1 - r]
        a = [1, -2 * r * np.cos(w), r * r]
        out += g * sps.lfilter(b, a, x, axis=0)
    return out


def modal(freqs, decays, gains, n: int, rng=None, phases=True) -> np.ndarray:
    """sum of exponentially decaying sines (metallic / bell / clang)"""
    t = tarr(n)
    rng = rng or RNG
    out = np.zeros(n)
    for f, d, g in zip(freqs, decays, gains):
        ph = rng.random() * TAU if phases else 0.0
        out += g * np.sin(TAU * f * t + ph) * np.exp(-6.91 * t / d)
    return out


# --------------------------------------------------------------------------------------------
# nonlinear / dynamics
# --------------------------------------------------------------------------------------------
def saturate(x: np.ndarray, drive: float = 2.0, asym: float = 0.0) -> np.ndarray:
    y = np.tanh(drive * (x + asym)) - np.tanh(drive * asym)
    return y / np.tanh(drive)


def fold(x: np.ndarray, amount: float = 1.5) -> np.ndarray:
    return np.sin(x * amount * np.pi / 2)


def bitcrush(x: np.ndarray, bits: float = 8, down: int = 1) -> np.ndarray:
    q = 2 ** (bits - 1)
    y = np.round(x * q) / q
    if down > 1:
        y = np.repeat(y[::down], down, axis=0)[: x.shape[0]]
    return y


def sidechain_env(n: int, hits_sec, depth: float = 0.6, attack: float = 0.004, release: float = 0.18) -> np.ndarray:
    """gain envelope ducking after each hit time (seconds)"""
    g = np.ones(n)
    t = tarr(n)
    for h in hits_sec:
        s = ns(h)
        if s >= n:
            continue
        seg = t[s:] - h
        duck = np.where(seg < attack, seg / attack, np.exp(-(seg - attack) / release))
        g[s:] = np.minimum(g[s:], 1.0 - depth * duck)
    # smooth
    return onepole_lp(g, 200.0)


def compress(x: np.ndarray, threshold_db=-18, ratio=3.0, attack_ms=10, release_ms=120) -> np.ndarray:
    import pedalboard as pb
    board = pb.Pedalboard([pb.Compressor(threshold_db=threshold_db, ratio=ratio, attack_ms=attack_ms,
                                         release_ms=release_ms)])
    y = board(np.ascontiguousarray(x.T if x.ndim == 2 else x[None, :], dtype=np.float32), SR)
    return y.T.astype(np.float64) if x.ndim == 2 else y[0].astype(np.float64)


def limit(x: np.ndarray, threshold_db=-1.0, release_ms=80) -> np.ndarray:
    import pedalboard as pb
    board = pb.Pedalboard([pb.Limiter(threshold_db=threshold_db, release_ms=release_ms)])
    y = board(np.ascontiguousarray(x.T if x.ndim == 2 else x[None, :], dtype=np.float32), SR)
    return y.T.astype(np.float64) if x.ndim == 2 else y[0].astype(np.float64)


def pb_process(x: np.ndarray, plugins) -> np.ndarray:
    import pedalboard as pb
    board = pb.Pedalboard(plugins)
    y = board(np.ascontiguousarray(x.T if x.ndim == 2 else x[None, :], dtype=np.float32), SR)
    return y.T.astype(np.float64) if x.ndim == 2 else y[0].astype(np.float64)


# --------------------------------------------------------------------------------------------
# modulation effects
# --------------------------------------------------------------------------------------------
@njit(cache=True)
def _mod_delay(x, delay_samples):
    n = x.shape[0]
    out = np.zeros(n)
    for i in range(n):
        d = delay_samples[i]
        pos = i - d
        if pos < 0.0:
            continue
        i0 = int(pos)
        frac = pos - i0
        a = x[i0]
        b = x[i0 + 1] if i0 + 1 < n else 0.0
        out[i] = a + (b - a) * frac
    return out


def chorus(x: np.ndarray, rate: float = 0.6, depth_ms: float = 3.0, base_ms: float = 12.0, mix: float = 0.5,
           voices: int = 2) -> np.ndarray:
    """stereo chorus; mono/stereo in, stereo out"""
    xs = stereo(x)
    n = xs.shape[0]
    out = np.zeros((n, 2))
    for c in range(2):
        wet = np.zeros(n)
        for v in range(voices):
            ph = (c * 0.5 + v / voices) * TAU
            d = (base_ms + depth_ms * (0.5 + 0.5 * np.sin(TAU * rate * (1 + 0.13 * v) * tarr(n) + ph))) * SR / 1000
            wet += _mod_delay(xs[:, c].astype(np.float64), d)
        out[:, c] = xs[:, c] * (1 - mix) + wet / voices * mix * 1.2
    return out


@njit(cache=True)
def _pingpong(xl, xr, d, fb, damp):
    n = xl.shape[0]
    bl = np.zeros(n + d)
    br = np.zeros(n + d)
    outl = np.zeros(n)
    outr = np.zeros(n)
    lpl = 0.0
    lpr = 0.0
    for i in range(n):
        yl = bl[i]
        yr = br[i]
        lpl = lpl + damp * (yl - lpl)
        lpr = lpr + damp * (yr - lpr)
        outl[i] = yl
        outr[i] = yr
        # cross feedback: L echo feeds R line and vice versa
        bl[i + d] += xl[i] + lpr * fb
        br[i + d] += lpl * fb
    return outl, outr


def pingpong_delay(x: np.ndarray, delay_s: float, feedback: float = 0.45, damp_hz: float = 4500.0,
                   tail_s: float = 0.0) -> np.ndarray:
    """returns ONLY the wet signal (stereo). Input mono/stereo."""
    xs = stereo(x)
    if tail_s > 0:
        xs = pad_to(xs, xs.shape[0] + ns(tail_s))
    xm = xs.mean(axis=1).astype(np.float64)
    d = max(1, ns(delay_s))
    damp = 1 - np.exp(-TAU * damp_hz / SR)
    l, r = _pingpong(xm, np.zeros_like(xm), d, feedback, damp)
    return np.stack([l, r], axis=1)


def widen(x: np.ndarray, amount: float = 1.3) -> np.ndarray:
    """M/S width; amount 1 = unchanged"""
    xs = stereo(x)
    m = (xs[:, 0] + xs[:, 1]) * 0.5
    s = (xs[:, 0] - xs[:, 1]) * 0.5 * amount
    return np.stack([m + s, m - s], axis=1)


def haas(x: np.ndarray, ms: float = 12.0, side: int = 1) -> np.ndarray:
    x = mono(x)
    d = ns(ms / 1000)
    delayed = np.concatenate([np.zeros(d), x[:-d] if d else x])
    return np.stack([x, delayed], axis=1) if side > 0 else np.stack([delayed, x], axis=1)


# --------------------------------------------------------------------------------------------
# reverb – synthetic stereo impulse responses + FFT convolution
# --------------------------------------------------------------------------------------------
_REVERB_PRESETS = {
    #           rt60   predelay  hf_ratio  lf_ratio  er_gain  density_ms  length_fac
    "small":   (0.35,  0.003,    0.55,     1.0,      0.6,     12,         1.4),
    "room":    (0.75,  0.006,    0.5,      1.1,      0.45,    20,         1.4),
    "plate":   (1.7,   0.004,    0.75,     0.9,      0.15,    6,          1.3),
    "hall":    (2.6,   0.022,    0.55,     1.2,      0.3,     35,         1.35),
    "bighall": (4.2,   0.030,    0.5,      1.25,     0.25,    45,         1.3),
    "space":   (6.5,   0.045,    0.4,      1.3,      0.15,    60,         1.25),
    "gated":   (0.9,   0.002,    0.8,      1.0,      0.3,     8,          1.0),
}


@functools.lru_cache(maxsize=None)
def make_ir(preset: str, seed: int = 7) -> np.ndarray:
    rt60, pre, hf, lf, er_gain, dens, lfac = _REVERB_PRESETS[preset]
    rng = np.random.default_rng(seed)
    n = ns(rt60 * lfac + pre + 0.05)
    t = tarr(n)
    ir = np.zeros((n, 2))
    bands = [(20, 250, rt60 * lf), (250, 1200, rt60), (1200, 4500, rt60 * (0.5 + 0.5 * hf)),
             (4500, 9000, rt60 * hf), (9000, 19000, rt60 * hf * 0.6)]
    for c in range(2):
        noise = rng.standard_normal(n)
        tail = np.zeros(n)
        for lo, hi, rt in bands:
            sos = sps.butter(3, [lo, hi], "bandpass", fs=SR, output="sos")
            tail += sps.sosfilt(sos, noise) * np.exp(-6.91 * t / rt)
        # diffuse build-up (echo density grows over the first ~dens ms)
        build = 1 - np.exp(-t / (dens / 1000.0))
        tail *= build
        ir[:, c] = tail
        # early reflections
        n_er = 14
        er_t = np.sort(rng.uniform(0.004, 0.012 + dens / 1000 * 2.5, n_er))
        for k, et in enumerate(er_t):
            idx = ns(et)
            if idx < n:
                ir[idx, c] += er_gain * rng.uniform(0.4, 1.0) * (1 if rng.random() > 0.3 else -1) * (1 - k / n_er) * 3
    # predelay
    p = ns(pre)
    ir = np.concatenate([np.zeros((p, 2)), ir])[:n]
    # gentle fade at end
    f = ns(0.08)
    ir[-f:] *= np.linspace(1, 0, f)[:, None]
    if preset == "gated":
        g = np.ones(n)
        cut = ns(0.22)
        g[cut:] = np.exp(-tarr(n - cut) / 0.012)
        ir *= g[:, None]
    # normalise energy so wet level is predictable
    ir /= np.sqrt(np.sum(ir ** 2) / 2)
    ir *= 0.5
    return ir


def reverb(x: np.ndarray, preset: str = "hall", wet: float = 0.3, dry: float = 1.0, tail: bool = True,
           predelay_extra: float = 0.0, lowcut: float = 180.0, highcut: float = 12000.0) -> np.ndarray:
    """convolution reverb with synthetic IR; returns stereo (len + tail if tail)"""
    ir = make_ir(preset)
    xs = stereo(x).astype(np.float64)
    send = xs
    if lowcut:
        send = butter(send, "hp", lowcut, 2)
    if highcut:
        send = butter(send, "lp", highcut, 2)
    if predelay_extra > 0:
        send = np.concatenate([np.zeros((ns(predelay_extra), 2)), send])
    wl = sps.oaconvolve(send[:, 0], ir[:, 0])
    wr = sps.oaconvolve(send[:, 1], ir[:, 1])
    # a little cross-feed for a more natural image
    w = np.stack([wl * 0.9 + wr * 0.1, wr * 0.9 + wl * 0.1], axis=1)
    n_out = w.shape[0] if tail else xs.shape[0]
    out = np.zeros((n_out, 2))
    out[: xs.shape[0]] += dry * xs[:n_out]
    out += wet * w[:n_out]
    return out


def trim_tail(x: np.ndarray, thresh_db: float = -70.0, min_len: float = 0.05, fade_s: float = 0.03) -> np.ndarray:
    """cut trailing silence and apply short fade"""
    a = np.abs(mono(x)) if x.ndim == 2 else np.abs(x)
    th = db(thresh_db) * max(a.max(), 1e-9)
    idx = np.where(a > th)[0]
    end = idx[-1] + 1 if idx.size else ns(min_len)
    end = max(end, ns(min_len))
    y = x[:end]
    return fade(y, 0.0, min(fade_s, end / SR * 0.5))


# --------------------------------------------------------------------------------------------
# loudness / analysis
# --------------------------------------------------------------------------------------------
def lufs(x: np.ndarray) -> float:
    import pyloudnorm as pyln
    meter = pyln.Meter(SR)
    xs = stereo(x) if x.ndim == 2 else x
    if xs.shape[0] < ns(0.45):
        xs = pad_to(xs, ns(0.45))
    try:
        return float(meter.integrated_loudness(xs))
    except Exception:
        return float("nan")


def short_term_max(x: np.ndarray, win: float = 0.4) -> float:
    """max momentary-ish RMS level (dBFS) – better loudness indicator for short sfx"""
    m = mono(x) if x.ndim == 2 else x
    w = max(1, ns(win))
    if m.shape[0] <= w:
        return to_db(np.sqrt(np.mean(m ** 2)) + 1e-12)
    c = np.cumsum(np.concatenate([[0], m ** 2]))
    rms = np.sqrt((c[w:] - c[:-w]) / w)
    return to_db(rms.max())


def true_peak(x: np.ndarray) -> float:
    up = sps.resample_poly(x, 4, 1, axis=0)
    return to_db(np.max(np.abs(up)))


def loop_seam(x: np.ndarray) -> dict:
    """compare the wrap point: sample jump and local derivative continuity"""
    xs = stereo(x)
    jump = np.max(np.abs(xs[0] - xs[-1]))
    d_end = xs[-1] - xs[-2]
    d_start = xs[1] - xs[0]
    typical = np.median(np.abs(np.diff(xs, axis=0))) + 1e-9
    win = ns(0.05)
    e_end = np.sqrt(np.mean(xs[-win:] ** 2))
    e_start = np.sqrt(np.mean(xs[:win] ** 2))
    return {"jump": float(jump), "typ_step": float(typical), "jump_ratio": float(jump / typical),
            "slope_diff": float(np.max(np.abs(d_end - d_start))),
            "rms_end_db": to_db(e_end), "rms_start_db": to_db(e_start)}


def make_loop(x: np.ndarray, loop_len: int, xfade_s: float = 0.25) -> np.ndarray:
    """turn a rendering of at least loop_len + xfade samples into a seamless loop of loop_len
    samples: the material after loop_len is equal-power cross-faded into the beginning."""
    xf = ns(xfade_s)
    need = loop_len + xf
    x = pad_to(x, need)
    out = x[:loop_len].copy()
    tail = x[loop_len:loop_len + xf]
    w = np.linspace(0, 1, xf)
    fi = np.sin(w * np.pi / 2)  # fade-in for original head
    fo = np.cos(w * np.pi / 2)  # fade-out for the tail continuation
    if out.ndim == 2:
        fi, fo = fi[:, None], fo[:, None]
    out[:xf] = out[:xf] * fi + tail * fo
    return out


def fold_tail(x: np.ndarray, loop_len: int) -> np.ndarray:
    """musical loops: everything after loop_len (release + reverb tails) is ADDED onto the
    start, exactly as it would sound when the loop repeats."""
    out = pad_to(x, max(loop_len, 1)).copy()[:loop_len]
    rest = x[loop_len:]
    k = 0
    while rest.shape[0] > 0:
        seg = rest[:loop_len]
        out[: seg.shape[0]] += seg
        rest = rest[loop_len:]
        k += 1
    return out


# --------------------------------------------------------------------------------------------
# writers
# --------------------------------------------------------------------------------------------
def write_wav(path: str, x: np.ndarray, peak_db: float | None = None, dither: bool = True):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    y = x.astype(np.float64)
    if peak_db is not None:
        y = normalize(y, peak_db)
    if dither:
        lsb = 1.0 / 32768.0
        y = y + (RNG.random(y.shape) - RNG.random(y.shape)) * lsb
    y = np.clip(y, -1.0, 32767 / 32768)
    sf.write(path, y, SR, subtype="PCM_16")


def write_ogg(path: str, x: np.ndarray, quality: int = 6):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with tempfile.TemporaryDirectory() as td:
        tmp = os.path.join(td, "tmp.wav")
        sf.write(tmp, np.clip(x, -1, 1).astype(np.float32), SR, subtype="FLOAT")
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp, "-c:a", "libvorbis", "-q:a", str(quality),
                        path], check=True)


def spectrogram_png(path: str, x: np.ndarray, title: str = ""):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    m = mono(x)
    f, t, S = sps.spectrogram(m, SR, nperseg=1024, noverlap=768)
    fig, ax = plt.subplots(2, 1, figsize=(10, 6), gridspec_kw={"height_ratios": [1, 3]})
    ax[0].plot(np.arange(m.shape[0]) / SR, m, lw=0.4)
    ax[0].set_xlim(0, m.shape[0] / SR)
    ax[0].set_title(title)
    ax[1].pcolormesh(t, f, 10 * np.log10(S + 1e-12), shading="auto", vmin=-120, vmax=-20, cmap="magma")
    ax[1].set_yscale("symlog", linthresh=200)
    ax[1].set_ylim(30, 20000)
    fig.tight_layout()
    fig.savefig(path, dpi=80)
    plt.close(fig)
