"""
instruments.py – synthesizer voices and drum kit for the music of Starfighter Defense.

Every voice is a function  voice(freq_hz, dur_s, vel, rng, **kw) -> np.ndarray
returning mono (n,) or stereo (n,2) audio INCLUDING its release tail.
Drums: drum(vel, rng, **kw) -> np.ndarray.
"""
from __future__ import annotations

import functools

import numpy as np

from synthlib import (SR, adsr, brown, butter, cents, crackle, db, env_points, exp_decay, fm, lfo, lp24,
                      modal, ns, onepole_lp, pan, pink, saturate, saw, sine, square, supersaw, svf, tarr,
                      triangle, white, resonator_bank, mix_into)


# ---------------------------------------------------------------------------------------------
# tonal voices
# ---------------------------------------------------------------------------------------------
def v_brass(f, dur, vel, rng, bright=1.0, release=0.3, attack=0.035):
    """80s synth brass: detuned saws, filter envelope swell, delayed vibrato"""
    n = ns(dur + release)
    t = tarr(n)
    o = saw(f, n) + saw(f * cents(5), n) + 0.6 * saw(f * cents(-6), n) + 0.25 * square(f / 2, n, 0.5)
    fenv = adsr(dur, attack * 1.3, 0.4, 0.5, release, n)
    vib = 1 + 0.0045 * np.clip((t - 0.3) / 0.4, 0, 1) * np.sin(2 * np.pi * 5.2 * t)
    cut = (f * 1.5 + (f * 7.5 * bright * (0.55 + 0.45 * vel) + 900) * fenv) * vib
    o = lp24(o, np.minimum(cut, 16000), 1.0)
    amp = adsr(dur, attack, 0.3, 0.82, release, n)
    return saturate(o * amp * 0.32 * (0.4 + 0.6 * vel), 1.25)


def v_supersaw_pad(f, dur, vel, rng, cutoff=2600, attack=0.45, release=1.4, voices=7, detune=16):
    n = ns(dur + release)
    t = tarr(n)
    o = supersaw(f, n, voices, detune, True, 0.95)
    cut = cutoff * (0.75 + 0.25 * np.sin(2 * np.pi * 0.13 * t + rng.random() * 6))
    o = svf(o, cut, 0.8, "lp")
    amp = adsr(dur, attack, 0.6, 0.85, release, n, curve=3)
    return o * amp[:, None] * 0.22 * (0.5 + 0.5 * vel)


def v_warm_pad(f, dur, vel, rng, cutoff=1300, attack=0.9, release=2.2):
    n = ns(dur + release)
    t = tarr(n)
    l = saw(f * cents(-7), n) + 0.7 * triangle(f, n) + 0.4 * saw(f * cents(4), n)
    r = saw(f * cents(7), n) + 0.7 * triangle(f * cents(-2), n) + 0.4 * saw(f * cents(-4), n)
    cut = cutoff * (0.8 + 0.2 * np.sin(2 * np.pi * 0.09 * t + rng.random() * 6))
    o = np.stack([svf(l, cut, 0.75, "lp"), svf(r, cut * 1.03, 0.75, "lp")], axis=1)
    amp = adsr(dur, attack, 1.0, 0.9, release, n, curve=2.5)
    return o * amp[:, None] * 0.2 * (0.5 + 0.5 * vel)


def v_strings(f, dur, vel, rng, attack=0.28, release=0.9, bright=1.0):
    """string-machine / synth strings ensemble"""
    n = ns(dur + release)
    t = tarr(n)
    vib = 1 + 0.003 * np.sin(2 * np.pi * (5.0 + rng.random()) * t + rng.random() * 6)
    out = np.zeros((n, 2))
    for k, (d, p) in enumerate([(-9, -0.7), (-3, -0.25), (3, 0.25), (9, 0.7), (0, 0.0)]):
        out += pan(saw(f * cents(d) * vib, n), p)
    out = svf(out, 2600 * bright + f, 0.7, "lp")
    out = butter(out, "hp", max(80, f * 0.5), 2)
    amp = adsr(dur, attack, 0.5, 0.92, release, n, curve=2)
    return out * amp[:, None] * 0.13 * (0.45 + 0.55 * vel)


def v_pluck(f, dur, vel, rng, decay=0.2, peak=5200, base=250, q=1.3, shape="saw", release=0.12):
    n = ns(dur + release + decay)
    t = tarr(n)
    if shape == "saw":
        o = saw(f, n) + 0.5 * saw(f * cents(7), n)
    elif shape == "square":
        o = square(f, n, 0.35) + 0.4 * saw(f * cents(-5), n)
    else:
        o = triangle(f, n) + 0.3 * square(f, n, 0.5)
    fenv = np.exp(-t / decay)
    o = lp24(o, base + f * 0.8 + peak * (0.4 + 0.6 * vel) * fenv, q)
    amp = adsr(dur, 0.002, decay * 1.6, 0.25, release, n, curve=4)
    return o * amp * 0.3 * (0.35 + 0.65 * vel)


def v_bass(f, dur, vel, rng, decay=0.13, peak=2400, drive=1.6, release=0.05):
    n = ns(dur + release)
    t = tarr(n)
    o = saw(f, n) + 0.55 * square(f * cents(-4), n, 0.5)
    o = lp24(o, 120 + f + peak * (0.4 + 0.6 * vel) * np.exp(-t / decay), 1.25)
    sub = sine(f / 2 if f > 70 else f, n) * 0.0 + sine(f, n) * 0.55
    amp = adsr(dur, 0.002, 0.15, 0.85, release, n, curve=3)
    return saturate((o * 0.6 + sub) * amp * 0.5 * (0.5 + 0.5 * vel), drive)


def v_reese(f, dur, vel, rng, cutoff=700, release=0.08, drive=2.2):
    n = ns(dur + release)
    t = tarr(n)
    o = saw(f * cents(-11), n) + saw(f * cents(11), n) + 0.5 * saw(f * 2 * cents(3), n)
    cut = cutoff * (1 + 0.3 * np.sin(2 * np.pi * 0.7 * t + rng.random() * 6))
    o = lp24(o, cut, 1.3)
    sub = sine(f, n) * 0.8
    amp = adsr(dur, 0.004, 0.2, 0.9, release, n)
    return saturate((o * 0.45 + sub) * amp * 0.45 * (0.5 + 0.5 * vel), drive)


def v_sub(f, dur, vel, rng, release=0.15):
    n = ns(dur + release)
    o = sine(f, n) + 0.12 * sine(2 * f, n)
    return o * adsr(dur, 0.01, 0.1, 1.0, release, n) * 0.45 * vel


def v_bell(f, dur, vel, rng, ratio=3.5, index=2.6, decay=1.2):
    n = ns(max(dur, decay * 2.2))
    t = tarr(n)
    o = fm(f, n, ratio, index * (0.5 + 0.5 * vel) * np.exp(-t / (decay * 0.35)) + 0.2)
    o += 0.25 * fm(f * 2.001, n, 1.0, 0.8 * np.exp(-t / 0.2))
    return o * exp_decay(n, decay, attack=0.001) * 0.22 * vel


def v_glass(f, dur, vel, rng, release=1.5):
    """glassy FM pad (enemy system)"""
    n = ns(dur + release)
    t = tarr(n)
    idx = 1.2 + 0.8 * np.sin(2 * np.pi * 0.21 * t + rng.random() * 6)
    o = fm(f, n, 1.4142, idx) * 0.7 + fm(f * cents(9), n, 3.0, idx * 0.5) * 0.4
    amp = adsr(dur, 0.6, 0.8, 0.8, release, n, curve=2)
    return pan(o * amp * 0.16 * vel, rng.uniform(-0.6, 0.6))


def v_epiano(f, dur, vel, rng, release=0.4):
    n = ns(dur + release + 0.3)
    t = tarr(n)
    tine = fm(f, n, 1.0, (1.4 + 1.2 * vel) * np.exp(-t / 0.5) + 0.15)
    bark = fm(f, n, 14.0, 0.7 * vel * np.exp(-t / 0.025)) * 0.2
    body = sine(f, n) * 0.3
    env = np.exp(-t / (1.6 + 200.0 / f))
    gate = adsr(dur, 0.001, 0.01, 1.0, release, n)
    o = (tine + bark + body) * env * gate
    # gentle tremolo / stereo autopan like a suitcase EP
    trem = 0.5 + 0.5 * np.sin(2 * np.pi * 4.5 * t)
    return np.stack([o * (0.6 + 0.4 * trem), o * (0.6 + 0.4 * (1 - trem))], axis=1) * 0.22 * (0.4 + 0.6 * vel)


def v_lead(f, dur, vel, rng, release=0.18, bright=1.0):
    n = ns(dur + release)
    t = tarr(n)
    vib = 1 + 0.006 * np.clip((t - 0.18) / 0.25, 0, 1) * np.sin(2 * np.pi * 5.6 * t)
    o = saw(f * vib, n) * 0.6 + square(f * vib * cents(-7), n, 0.42) * 0.5 + saw(f * 2 * vib * cents(4), n) * 0.12
    fenv = adsr(dur, 0.01, 0.25, 0.6, release, n)
    o = lp24(o, f * 2 + (3200 * bright + f * 2) * fenv, 1.4)
    amp = adsr(dur, 0.008, 0.2, 0.85, release, n)
    return saturate(o * amp * 0.28 * (0.5 + 0.5 * vel), 1.5)


def v_choir(f, dur, vel, rng, vowel="ah", attack=0.5, release=1.2):
    """formant-filtered saw ensemble ("aah")"""
    n = ns(dur + release)
    t = tarr(n)
    formants = {"ah": [(730, 1.0, 9), (1090, 0.5, 10), (2440, 0.25, 12)],
                "oo": [(300, 1.0, 8), (870, 0.35, 10), (2240, 0.1, 12)],
                "eh": [(530, 1.0, 9), (1840, 0.45, 11), (2480, 0.3, 12)]}[vowel]
    out = np.zeros((n, 2))
    for k, (d, p) in enumerate([(-8, -0.6), (-2, -0.2), (3, 0.25), (8, 0.6)]):
        vib = 1 + 0.004 * np.sin(2 * np.pi * (5 + rng.random()) * t + rng.random() * 6)
        src = saw(f * cents(d + rng.uniform(-2, 2)) * vib, n)
        v = np.zeros(n)
        for fc, g, q in formants:
            v += g * svf(src, fc, q, "bp")
        out += pan(v, p)
    amp = adsr(dur, attack, 0.8, 0.9, release, n, curve=2)
    return out * amp[:, None] * 0.3 * (0.45 + 0.55 * vel)


def v_drone(f, dur, vel, rng, release=2.0):
    n = ns(dur + release)
    t = tarr(n)
    o = saw(f, n) + saw(f * cents(6), n) + 0.5 * square(f * 0.5, n, 0.3)
    o = lp24(o, 250 + 200 * (0.5 + 0.5 * np.sin(2 * np.pi * 0.07 * t)), 1.6)
    amp = adsr(dur, 1.5, 1.0, 0.9, release, n, curve=2)
    return pan(o * amp * 0.25 * vel, 0)


# ---------------------------------------------------------------------------------------------
# drums (cached variants for speed; small random variation between variants)
# ---------------------------------------------------------------------------------------------
_DRUM_CACHE = {}


def drum(name, vel, rng, variant=None, **kw):
    v = variant if variant is not None else int(rng.integers(0, 4))
    key = (name, v, tuple(sorted(kw.items())))
    if key not in _DRUM_CACHE:
        import zlib
        r = np.random.default_rng(zlib.crc32(repr(key).encode()))
        _DRUM_CACHE[key] = DRUMS[name](r, **kw)
    return _DRUM_CACHE[key] * vel


def d_kick(rng, tone=48, punch=1.0, decay=0.42, click=1.0):
    n = ns(decay * 1.6)
    t = tarr(n)
    f = tone + (170 * punch) * np.exp(-t / 0.035) + 40 * np.exp(-t / 0.006)
    body = sine(f, n) * exp_decay(n, decay * 0.55, attack=0.0008)
    clk = svf(white(n, rng), 3500, 0.8, "bp") * exp_decay(n, 0.0025) * 0.5 * click
    o = saturate(body * 1.25 + clk, 1.5)
    return o * 0.9


def d_snare(rng, tone=185, snap=1.0, decay=0.19):
    n = ns(decay * 2.2)
    t = tarr(n)
    tonal = (sine(tone * (1 + 0.25 * np.exp(-t / 0.01)), n) + 0.6 * sine(tone * 1.78, n)) * exp_decay(n, 0.065)
    nz = svf(white(n, rng), 5200, 0.6, "bp") * exp_decay(n, decay * 0.55, attack=0.0005) * snap
    nz += svf(white(n, rng), 9000, 0.7, "hp") * exp_decay(n, 0.05) * 0.4
    return saturate(tonal * 0.7 + nz * 0.9, 1.3) * 0.7


def d_clap(rng, decay=0.22):
    n = ns(0.5)
    t = tarr(n)
    env = np.zeros(n)
    for k, o in enumerate([0.0, 0.011, 0.023, 0.034]):
        s = ns(o)
        env[s:] += exp_decay(n - s, 0.008 if k < 3 else decay * 0.4) * (0.9 if k < 3 else 1.0)
    o = svf(white(n, rng), 1400, 1.4, "bp") * env + svf(white(n, rng), 3200, 1.0, "bp") * env * 0.5
    return o * 0.75


def d_hat(rng, open_=False, decay=None):
    d = decay if decay is not None else (0.32 if open_ else 0.045)
    n = ns(d * 3 + 0.02)
    t = tarr(n)
    metal = np.zeros(n)
    for f in (205.3, 304.4, 369.6, 522.7, 540.0, 800.0):
        metal += square(f * 2.0, n, 0.5)
    o = svf(metal, 9000, 0.9, "hp") * 0.25 + svf(white(n, rng), 8500, 0.7, "hp") * 0.6
    o = svf(o, 11000, 0.7, "bp") * 0.5 + o * 0.5
    return o * exp_decay(n, d, attack=0.0005) * 0.5


def d_crash(rng, decay=2.2):
    n = ns(decay * 1.7)
    t = tarr(n)
    out = np.zeros((n, 2))
    for c in range(2):
        metal = np.zeros(n)
        for f in rng.uniform(300, 1200, 8):
            metal += square(f, n, 0.5)
        o = svf(metal, 6000, 0.6, "hp") * 0.15 + svf(white(n, rng), 5000, 0.5, "hp") * 0.7
        o = o * (exp_decay(n, decay * 0.42, attack=0.001) * 0.85 + exp_decay(n, 0.05) * 0.4)
        out[:, c] = o
    return out * 0.5


def d_tom(rng, tone=110, decay=0.35):
    n = ns(decay * 1.8)
    t = tarr(n)
    f = tone * (1 + 0.6 * np.exp(-t / 0.03))
    o = sine(f, n) * exp_decay(n, decay * 0.5) + 0.25 * sine(f * 1.6, n) * exp_decay(n, decay * 0.25)
    o += svf(white(n, rng), 1200, 0.8, "bp") * exp_decay(n, 0.012) * 0.4
    return saturate(o, 1.3) * 0.8


def d_taiko(rng, tone=58, decay=0.9):
    n = ns(decay * 1.8)
    t = tarr(n)
    f = tone * (1 + 0.35 * np.exp(-t / 0.04))
    o = sine(f, n) * exp_decay(n, decay * 0.45, attack=0.001) + 0.4 * sine(f * 2.3, n) * exp_decay(n, 0.12)
    skin = svf(white(n, rng), 600, 0.7, "lp") * exp_decay(n, 0.02) * 0.8
    o += skin
    return saturate(o * 1.2, 1.4) * 0.85


def d_timpani(rng, tone=73.4, decay=1.4):
    n = ns(decay * 1.6)
    t = tarr(n)
    f = tone * (1 + 0.05 * np.exp(-t / 0.05))
    o = (sine(f, n) + 0.5 * sine(f * 1.504, n) * exp_decay(n, decay * 0.4) + 0.25 * sine(f * 1.742, n) *
         exp_decay(n, decay * 0.3)) * exp_decay(n, decay * 0.5, attack=0.002)
    o += svf(white(n, rng), 300, 0.7, "lp") * exp_decay(n, 0.025) * 0.6
    return o * 0.7


def d_shaker(rng, decay=0.06):
    n = ns(decay * 2.5)
    o = svf(white(n, rng), 6500, 1.2, "bp") * env_points([(0, 0), (0.008, 1), (decay * 2.5, 0)], n) ** 2
    return o * 0.4


def d_rim(rng):
    n = ns(0.08)
    t = tarr(n)
    o = sine(1700, n) * exp_decay(n, 0.008) + svf(white(n, rng), 3000, 2, "bp") * exp_decay(n, 0.006)
    return o * 0.5


def d_metal(rng, base=None, decay=1.2):
    """inharmonic metallic hit (enemy system)"""
    base = base or rng.uniform(180, 420)
    n = ns(decay * 1.5)
    ratios = [1.0, 1.593, 2.135, 2.653, 3.156, 4.07]
    o = modal([base * r for r in ratios], [decay * (1 - 0.12 * k) for k in range(6)],
              [1, 0.7, 0.55, 0.4, 0.3, 0.2], n, rng)
    o += svf(white(n, rng), 3000, 0.7, "hp") * exp_decay(n, 0.004)
    return o * 0.35


DRUMS = {"kick": d_kick, "snare": d_snare, "clap": d_clap, "hat": d_hat, "crash": d_crash, "tom": d_tom,
         "taiko": d_taiko, "timpani": d_timpani, "shaker": d_shaker, "rim": d_rim, "metal": d_metal}


# ---------------------------------------------------------------------------------------------
# FX
# ---------------------------------------------------------------------------------------------
def fx_riser(dur, rng, f0=200, f1=6000):
    n = ns(dur)
    t = tarr(n)
    k = t / dur
    nz = np.stack([svf(white(n, rng), f0 * (f1 / f0) ** k, 1.6, "bp"),
                   svf(white(n, rng), f0 * (f1 / f0) ** k * 1.05, 1.6, "bp")], axis=1)
    tone = saw(80 * (16) ** k, n) * 0.15
    tone = svf(tone, 400 + 6000 * k, 1.0, "lp")
    o = nz * (k ** 2)[:, None] * 0.5 + pan(tone * k ** 2, 0)
    return o


def fx_impact(rng, size=1.0):
    n = ns(3.0 * size)
    t = tarr(n)
    sub = sine(28 + 70 * np.exp(-t / 0.06), n) * exp_decay(n, 0.6 * size)
    burst = lp24(white(n, rng), 200 + 3000 * np.exp(-t / 0.05), 0.8) * exp_decay(n, 0.25 * size)
    o = saturate(sub * 1.1 + burst * 0.5, 1.4)
    return pan(o, 0) * 0.8


def fx_reverse_swell(dur, rng, f=None):
    n = ns(dur)
    t = tarr(n)
    k = t / dur
    o = np.stack([svf(white(n, rng), 3000 + 4000 * k, 0.8, "bp"), svf(white(n, rng), 3200 + 4000 * k, 0.8, "bp")],
                 axis=1)
    return o * (k ** 3)[:, None] * 0.4
