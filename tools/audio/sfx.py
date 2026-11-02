"""
sfx.py – generates every sound effect of Starfighter Defense into assets/audio/sfx/.

All sounds are synthesised from scratch (oscillators, noise, filters, modal resonators,
synthetic reverb).  Each sound is built from layers (transient + body + tail).
Loudness hierarchy is applied at the end via short-term RMS targets with a -1 dBFS peak ceiling.

usage:  /opt/tools/audiovenv/bin/python sfx.py [name ...]
"""
from __future__ import annotations

import os
import sys

import numpy as np
import scipy.signal as sps

from synthlib import (SR, adsr, arr, brown, butter, chorus, crackle, db, env_points, exp_decay, fade, fm,
                      lfo, limit, loop_seam, lp24, make_ir, mix_into, mono, normalize, ns, onepole_lp, pad_to,
                      pan, pan_dynamic, pink, remove_dc, resonator_bank, reverb, saturate, saw, short_term_max,
                      sine, square, supersaw, svf, tarr, to_db, triangle, trim_tail, white, widen, write_wav,
                      modal, bitcrush, true_peak, midi_to_hz)

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "audio", "sfx")

# target short-term (400 ms) RMS level per sound in dBFS -> loudness hierarchy
# (peak ceiling -1 dBFS is always enforced on top)
TARGETS = {}
REGISTRY = {}


def sfx(name, target_rms, stereo_out=False, loop=False):
    def deco(fn):
        REGISTRY[name] = (fn, target_rms, stereo_out, loop)
        return fn
    return deco


def rng_for(name):
    return np.random.default_rng(abs(hash(name)) % (2 ** 32) if False else sum(map(ord, name)) * 7919)


def rev_mono(x, preset="room", wet=0.2, dry=1.0):
    """mono reverb: convolve with left IR channel only"""
    ir = make_ir(preset)[:, 0]
    w = sps.oaconvolve(butter(x, "hp", 150, 2), ir)
    out = np.zeros(w.shape[0])
    out[: x.shape[0]] += dry * x
    out += wet * w
    return out


def L(*parts):
    """sum layers of different lengths"""
    n = max(p.shape[0] for p in parts)
    if any(p.ndim == 2 for p in parts):
        out = np.zeros((n, 2))
    else:
        out = np.zeros(n)
    for p in parts:
        mix_into(out, p, 0)
    return out


def at(x, offset_s, total=None):
    """delay a layer by offset seconds"""
    o = ns(offset_s)
    shape = (x.shape[0] + o,) + x.shape[1:]
    out = np.zeros(shape)
    out[o:] = x
    return out


def periodic_noise(period_s, reps, rng, kind="white", channels=1):
    """noise that repeats exactly every period -> perfectly loopable after filtering"""
    n = ns(period_s)
    if channels == 1:
        base = {"white": white, "pink": pink, "brown": brown}[kind](n, rng)
        return np.tile(base, reps)
    return np.stack([np.tile({"white": white, "pink": pink, "brown": brown}[kind](n, rng), reps)
                     for _ in range(channels)], axis=1)


def middle_period(x, period_s, reps=3):
    n = ns(period_s)
    k = reps // 2
    return x[k * n:(k + 1) * n]


# =============================================================================================
# WEAPONS
# =============================================================================================
def _laser(rng, f0, f1, dur, fm_ratio, fm_idx, noise_amt, tone_mix, sweep_tau):
    n = ns(dur)
    t = tarr(n)
    k = np.exp(-t / sweep_tau)
    f = f1 + (f0 - f1) * k
    body = 0.55 * square(f, n, 0.5 - 0.3 * k) + 0.45 * saw(f * 1.004, n)
    body = svf(body, f * 3.0 + 2500 * k, 1.6, "lp")
    zap = fm(f, n, fm_ratio, fm_idx * k + 0.4)
    amp = exp_decay(n, dur * 0.32, attack=0.0015)
    nz = svf(white(n, rng), 7000 * k + 900, 0.9, "bp") * exp_decay(n, 0.025)
    click = svf(white(n, rng), 4000, 0.7, "hp") * exp_decay(n, 0.002)
    x = (tone_mix * body + (1 - tone_mix) * zap) * amp + noise_amt * nz + 0.35 * click
    # sub "punch" so it feels like a weapon, not a toy
    punch = sine(160 * (1 + 2 * np.exp(-t / 0.01)), n) * exp_decay(n, 0.025) * 0.35
    x = saturate(x + punch, 1.6)
    x = rev_mono(x, "small", 0.18)
    return x


@sfx("laser_1", -15)
def laser_1(rng):
    return _laser(rng, 2300, 260, 0.30, 2.01, 3.0, 0.25, 0.6, 0.045)


@sfx("laser_2", -15)
def laser_2(rng):
    return _laser(rng, 2700, 330, 0.27, 1.5, 4.0, 0.2, 0.5, 0.038)


@sfx("laser_3", -15)
def laser_3(rng):
    return _laser(rng, 1900, 210, 0.34, 3.02, 2.5, 0.35, 0.65, 0.055)


@sfx("ion_fire", -11)
def ion_fire(rng):
    n = ns(1.35)
    t = tarr(n)
    sub = sine(36 + 110 * np.exp(-t / 0.05), n) * exp_decay(n, 0.32, attack=0.002)
    f_body = 98 * (1 + 1.8 * np.exp(-t / 0.07))
    body = supersaw(f_body, n, 5, 22, stereo_out=False)
    body = lp24(body, 140 + 4200 * np.exp(-t / 0.11), 1.4) * exp_decay(n, 0.42, attack=0.003)
    # electric sizzle: band-passed noise, chopped by fast random gating
    gate = np.clip(onepole_lp(np.abs(white(n, rng)) > 1.2, 300) * 3, 0, 1)
    sizzle = svf(white(n, rng), 5200 + 2500 * np.exp(-t / 0.25), 1.8, "bp") * (0.35 + 0.65 * gate)
    sizzle *= exp_decay(n, 0.45, attack=0.01)
    zing = fm(420 + 3000 * np.exp(-t / 0.13), n, 1.5, 2.2 * np.exp(-t / 0.18)) * exp_decay(n, 0.22)
    # charge "suck" right before the blast (very short pre-swell inside first 30 ms)
    crack = svf(white(n, rng), 2500, 0.6, "hp") * exp_decay(n, 0.006)
    x = 1.0 * sub + 0.75 * body + 0.22 * sizzle + 0.32 * zing + 0.4 * crack
    x = saturate(x * 1.2, 2.2)
    return rev_mono(x, "room", 0.28)


@sfx("ion_ready", -24)
def ion_ready(rng):
    def ping(f, dur):
        n = ns(dur)
        t = tarr(n)
        return fm(f, n, 2.0, 1.6 * np.exp(-t / 0.04)) * exp_decay(n, 0.09, attack=0.001)
    x = L(ping(1318.5, 0.25), at(ping(1975.5, 0.3), 0.07))
    return rev_mono(x, "plate", 0.2)


@sfx("shield_hit", -14)
def shield_hit(rng):
    n = ns(0.7)
    t = tarr(n)
    crack = svf(white(n, rng), 3200, 0.7, "hp") * exp_decay(n, 0.008)
    bell = fm(612, n, 1.414, 3.2 * np.exp(-t / 0.14) + 0.3) * exp_decay(n, 0.24)
    bell2 = fm(941, n, 2.76, 2.0 * np.exp(-t / 0.09)) * exp_decay(n, 0.16)
    buzz = square(94, n, 0.3) * svf(white(n, rng), 2100, 0.5, "bp") * exp_decay(n, 0.11)
    zap = sine(280 + 2400 * np.exp(-t / 0.045), n) * exp_decay(n, 0.07)
    x = 0.8 * crack + 0.55 * bell + 0.3 * bell2 + 0.45 * buzz + 0.4 * zap
    x = saturate(x, 1.4)
    return rev_mono(x, "plate", 0.25)


@sfx("shield_break", -14)
def shield_break(rng):
    n = ns(0.95)
    t = tarr(n)
    # glass shatter: many short inharmonic partials with staggered onsets
    shatter = np.zeros(n)
    for i in range(38):
        f = rng.uniform(1800, 9500)
        on = rng.uniform(0, 0.18) ** 1.6
        d = rng.uniform(0.04, 0.22)
        m = ns(d * 2.5)
        part = np.sin(2 * np.pi * f * tarr(m) + rng.random() * 6) * np.exp(-6.9 * tarr(m) / d)
        mix_into(shatter, part * rng.uniform(0.2, 1.0), ns(on))
    shatter += svf(white(n, rng), 6000, 0.8, "hp") * exp_decay(n, 0.05) * 1.5
    # power-down whine
    f = 1500 * (180 / 1500) ** np.clip(t / 0.7, 0, 1)
    whine = (sine(f * (1 + 0.02 * lfo(n, 9 + 20 * t.mean())), n) * 0.7 + 0.3 * saw(f, n)) * \
        env_points([(0, 0), (0.01, 1), (0.6, 0.4), (0.95, 0)], n)
    whine = svf(whine, 3000, 0.7, "lp")
    crackles = svf(crackle(n, 300, rng), 4000, 0.7, "hp") * exp_decay(n, 0.3) * 3
    x = 0.55 * shatter + 0.5 * whine + 0.4 * crackles
    return rev_mono(x, "plate", 0.3)


@sfx("laser_deflect", -19)
def laser_deflect(rng):
    n = ns(0.35)
    t = tarr(n)
    f = 2650 - 420 * (1 - np.exp(-t / 0.08))
    ping = fm(f, n, 1.53, 1.2 * np.exp(-t / 0.05)) * exp_decay(n, 0.09, attack=0.0008)
    partials = modal([3910, 5620, 7410], [0.12, 0.08, 0.05], [0.4, 0.25, 0.15], n, rng)
    click = svf(white(n, rng), 5000, 0.7, "hp") * exp_decay(n, 0.0015)
    x = ping + partials + 0.5 * click
    return rev_mono(x, "small", 0.25)


# =============================================================================================
# EXPLOSIONS
# =============================================================================================
def _turbulence(n, rng, rate=18.0, amount=0.35):
    m = onepole_lp(white(n, rng), rate)
    m /= (np.std(m) + 1e-9)
    return 1.0 + amount * np.tanh(m)


def _blast(rng, dur, size=1.0, sub_f=(95, 34), bright=1.0):
    n = ns(dur)
    t = tarr(n)
    crack = svf(white(n, rng), 1200, 0.6, "hp") * exp_decay(n, 0.004 * size)
    nz = pink(n, rng) * 0.6 + white(n, rng) * 0.4
    cutoff = 220 + 5200 * bright * np.exp(-t / (0.09 * size)) + 900 * np.exp(-t / (0.5 * size))
    body = lp24(nz, cutoff, 0.9) * exp_decay(n, 0.28 * size, attack=0.002) * _turbulence(n, rng)
    sub = sine(sub_f[1] + (sub_f[0] - sub_f[1]) * np.exp(-t / (0.07 * size)), n) * exp_decay(n, 0.3 * size,
                                                                                             attack=0.002)
    rumble = svf(brown(n, rng), 170, 0.7, "lp") * exp_decay(n, 0.65 * size, attack=0.03) * _turbulence(n, rng, 6, 0.5)
    crk = svf(crackle(n, 70 * size, rng), 3500, 0.6, "hp") * exp_decay(n, 0.45 * size) * 5
    x = 0.55 * crack + 1.0 * body + 0.9 * sub + 0.7 * rumble + 0.35 * crk
    return saturate(x * 1.1, 1.8)


def macro(n, points):
    """overall loudness contour in dB: [(t, dB), ...] (exponential interpolation)"""
    return env_points([(t, db(v)) for t, v in points], n, "exp")


def _explosion_small(rng, bright):
    x = _blast(rng, 1.6, 0.8, (110, 38), bright)
    x = rev_mono(x, "room", 0.22)
    n = x.shape[0]
    x *= macro(n, [(0, 0), (0.12, -2), (0.45, -9), (0.9, -18), (1.4, -30), (n / SR, -60)])
    return x


@sfx("explosion_small_1", -12)
def explosion_small_1(rng):
    return _explosion_small(rng, 1.0)


@sfx("explosion_small_2", -12)
def explosion_small_2(rng):
    return _explosion_small(rng, 0.8)


@sfx("explosion_small_3", -12)
def explosion_small_3(rng):
    return _explosion_small(rng, 1.2)


def _debris(rng, n, count=10, spread=1.2):
    out = np.zeros(n)
    for i in range(count):
        on = rng.uniform(0.05, spread)
        m = ns(rng.uniform(0.25, 0.7))
        freqs = rng.uniform(250, 2600, 4)
        part = modal(freqs, rng.uniform(0.08, 0.35, 4), rng.uniform(0.2, 1.0, 4), m, rng)
        mix_into(out, part * rng.uniform(0.15, 0.6) * np.exp(-on), ns(on))
    return out


def _explosion_large(rng, offsets):
    n = ns(3.3)
    x = np.zeros(n)
    for i, (o, s, g) in enumerate(offsets):
        b = _blast(rng, 3.0 - o, s, (88 - 10 * i, 27), 1.0 - 0.2 * i)
        b *= macro(b.shape[0], [(0, 0), (0.15, -3), (0.6, -12), (1.5, -24), (b.shape[0] / SR, -50)])
        mix_into(x, b * g, ns(o))
    x += 0.3 * _debris(rng, n, 9, 1.4)
    tail = svf(brown(n, rng), 110, 0.7, "lp") * env_points([(0, 0), (0.25, 1), (3.3, 0)], n) ** 2 * 0.5
    x += tail
    x = saturate(x, 1.3)
    x = rev_mono(x, "hall", 0.26)
    m = x.shape[0]
    x *= macro(m, [(0, 0), (0.3, -2), (0.8, -8), (1.6, -16), (2.5, -26), (3.2, -40), (m / SR, -70)])
    return x


@sfx("explosion_large_1", -10)
def explosion_large_1(rng):
    return _explosion_large(rng, [(0.0, 1.3, 1.0), (0.17, 1.0, 0.55), (0.42, 1.1, 0.4)])


@sfx("explosion_large_2", -10)
def explosion_large_2(rng):
    return _explosion_large(rng, [(0.0, 1.4, 1.0), (0.26, 1.1, 0.5), (0.55, 0.9, 0.38), (0.8, 1.0, 0.28)])


@sfx("explosion_huge", -9, stereo_out=True)
def explosion_huge(rng):
    n = ns(5.8)
    t = tarr(n)
    x = np.zeros((n, 2))
    blasts = [(0.0, 1.9, 1.0, 0.0), (0.24, 1.3, 0.55, -0.55), (0.52, 1.4, 0.45, 0.6), (0.9, 1.5, 0.36, -0.3),
              (1.35, 1.7, 0.3, 0.35)]
    for o, s, g, p in blasts:
        b = _blast(rng, 5.6 - o, s, (72, 22), 0.95)
        b *= macro(b.shape[0], [(0, 0), (0.3, -2), (1.2, -9), (3.0, -20), (b.shape[0] / SR, -45)])
        mix_into(x, pan(b * g, p), ns(o))
    sub = sine(20 + 58 * np.exp(-t / 0.35), n) * exp_decay(n, 1.1, attack=0.004)
    x += stereo_sub(sub * 0.9)
    for c in range(2):
        r = svf(brown(n, rng), 130, 0.7, "lp") * env_points([(0, 0), (0.35, 1), (1.8, 0.55), (5.8, 0)], n) ** 1.6
        r *= _turbulence(n, rng, 3, 0.6)
        x[:, c] += 1.1 * r
    x += pan(_debris(rng, n, 16, 2.6) * 0.35, 0.25) + pan(_debris(rng, n, 12, 2.6) * 0.3, -0.4)
    x = saturate(x, 1.25)
    x = reverb(x, "bighall", wet=0.3)
    m = x.shape[0]
    x *= macro(m, [(0, 0), (0.4, -1), (1.2, -5), (2.2, -12), (3.4, -20), (4.6, -29), (5.5, -42), (m / SR, -70)])[:, None]
    return widen(x, 1.25)


def stereo_sub(x):
    return np.stack([x, x], axis=1)


# =============================================================================================
# PLAYER DAMAGE
# =============================================================================================
@sfx("player_hit_light", -15)
def player_hit_light(rng):
    n = ns(0.42)
    t = tarr(n)
    chop = (square(43, n, 0.4) > 0).astype(float) * 0.6 + 0.4
    static = svf(white(n, rng), 3500, 0.9, "bp") * chop * exp_decay(n, 0.09, attack=0.001)
    thump = sine(58 + 110 * np.exp(-t / 0.02), n) * exp_decay(n, 0.07)
    zap = sine(750 + 2600 * np.exp(-t / 0.03), n) * exp_decay(n, 0.05) * 0.5
    x = 0.8 * static + 0.9 * thump + 0.4 * zap
    return rev_mono(saturate(x, 1.6), "small", 0.2)


@sfx("player_hit_heavy", -10)
def player_hit_heavy(rng):
    n = ns(1.3)
    t = tarr(n)
    impact = lp24(white(n, rng), 300 + 3800 * np.exp(-t / 0.05), 0.8) * exp_decay(n, 0.22, attack=0.001)
    thump = sine(34 + 120 * np.exp(-t / 0.04), n) * exp_decay(n, 0.28)
    # metal stress groan: inharmonic modes slowly bending downward
    groan = np.zeros(n)
    bend = 1 - 0.06 * (1 - np.exp(-t / 0.5))
    for f, d, g in [(173, 0.9, 1.0), (412, 0.7, 0.6), (689, 0.5, 0.45), (1023, 0.4, 0.3), (1490, 0.3, 0.2)]:
        groan += g * np.sin(2 * np.pi * np.cumsum(f * bend) / SR) * np.exp(-6.9 * t / d)
    groan *= 0.4 * (1 + 0.3 * lfo(n, 7.3))
    sparks = svf(crackle(n, 220, rng), 3200, 0.6, "hp") * exp_decay(n, 0.55) * 6
    hiss = svf(white(n, rng), 6000, 0.7, "hp") * exp_decay(n, 0.4, attack=0.05) * 0.15
    x = 1.0 * impact + 1.0 * thump + groan + 0.45 * sparks + hiss
    x = saturate(x * 1.3, 2.0)
    return trim_tail(rev_mono(x, "room", 0.3), -60)


# =============================================================================================
# ENEMY WEAPONS
# =============================================================================================
@sfx("enemy_shot_fighter", -17)
def enemy_shot_fighter(rng):
    n = ns(0.32)
    t = tarr(n)
    f = np.where(t < 0.03, 520 + (1450 - 520) * (t / 0.03), 300 + 1150 * np.exp(-(t - 0.03) / 0.07))
    tone = square(f, n, 0.32) * 0.6 + saw(f * 0.5, n) * 0.4
    ring = tone * (0.6 + 0.4 * sine(71, n))
    x = svf(ring, 1700 + 1500 * np.exp(-t / 0.05), 1.4, "bp") * 1.6
    x *= exp_decay(n, 0.085, attack=0.002)
    hiss = svf(white(n, rng), 3000, 1.0, "bp") * exp_decay(n, 0.03) * 0.4
    return rev_mono(saturate(x + hiss, 2.2), "small", 0.2)


@sfx("enemy_shot_destroyer", -13)
def enemy_shot_destroyer(rng):
    n = ns(1.1)
    t = tarr(n)
    ch_end = 0.32
    # charge: rising tone with accelerating tremolo
    fc = 190 * (900 / 190) ** np.clip(t / ch_end, 0, 1)
    trem = 0.5 + 0.5 * np.sin(2 * np.pi * np.cumsum(18 + 40 * np.clip(t / ch_end, 0, 1)) / SR)
    charge = (sine(fc, n) * 0.6 + saw(fc, n) * 0.25) * trem * np.clip(t / ch_end, 0, 1) ** 2 * (t < ch_end)
    charge = svf(charge, 2500, 0.8, "lp")
    m = n - ns(ch_end)
    tt = tarr(m)
    boom = sine(42 + 120 * np.exp(-tt / 0.03), m) * exp_decay(m, 0.2)
    body = lp24(supersaw(130 * (1 + np.exp(-tt / 0.05)), m, 5, 30, False), 200 + 3200 * np.exp(-tt / 0.09), 1.3)
    body *= exp_decay(m, 0.3, attack=0.002)
    plasma = svf(white(m, rng), 4200, 2.0, "bp") * exp_decay(m, 0.35) * 0.5
    launch = 0.9 * boom + 0.8 * body + plasma
    x = np.zeros(n)
    x += charge * 0.7
    mix_into(x, launch, ns(ch_end))
    return trim_tail(rev_mono(saturate(x, 1.8), "room", 0.25), -60)


@sfx("flagship_charge_loop", -12, loop=True)
def flagship_charge_loop(rng):
    P, R = 2.0, 3
    n = ns(P * R)
    t = tarr(n)
    drone = saw(55.0, n, 0.0) + saw(55.5, n, 0.3) + 0.6 * saw(110.0, n, 0.6)
    drone = lp24(drone, 380 + 120 * np.sin(2 * np.pi * 0.5 * t), 1.8)
    pulse = 0.55 + 0.45 * (0.5 + 0.5 * np.sin(2 * np.pi * 4.0 * t)) ** 2
    hum = (np.sin(2 * np.pi * 220 * t + 0.4 * np.sin(2 * np.pi * 6 * t)) +
           0.6 * np.sin(2 * np.pi * 330 * t + 0.3 * np.sin(2 * np.pi * 6 * t + 1)))
    sub = np.sin(2 * np.pi * 27.5 * t) * 0.8
    nz = periodic_noise(P, R, rng)
    crackles = svf(nz, 3800, 2.5, "bp") * (0.5 + 0.5 * np.sin(2 * np.pi * 8 * t) ** 8)
    x = 0.6 * drone * pulse + 0.18 * hum * pulse + 0.5 * sub + 0.12 * crackles
    x = saturate(x, 1.6)
    # reverb on periodic signal, then cut out the steady-state middle period
    x = mono(reverb(x, "room", 0.2, tail=False))
    return middle_period(x, P, R)


@sfx("flagship_fire", -9, stereo_out=True)
def flagship_fire(rng):
    n = ns(2.7)
    t = tarr(n)
    scream = fm(1000 + 3200 * np.exp(-t / 0.18), n, 1.01, 3 * np.exp(-t / 0.3)) * exp_decay(n, 0.35, attack=0.004)
    roar = np.zeros(n)
    for f in (55, 82.4, 110, 164.8):
        roar += supersaw(f * (1 + 0.15 * np.exp(-t / 0.2)), n, 5, 35, False)
    roar = lp24(roar, 250 + 6000 * np.exp(-t / 0.35), 1.2) * env_points([(0, 0), (0.01, 1), (1.2, 0.6), (2.7, 0)], n)
    roar = saturate(roar * 0.5, 3.0)
    sub = sine(24 + 60 * np.exp(-t / 0.15), n) * exp_decay(n, 0.9, attack=0.003)
    whoosh = svf(pink(n, rng), 300 + 5000 * np.exp(-t / 0.25), 1.5, "bp") * exp_decay(n, 0.7, attack=0.01)
    x = 0.4 * scream + 0.8 * roar + 1.0 * sub + 0.6 * whoosh
    xs = np.stack([x, x], axis=1)
    xs = chorus(xs, 0.3, 4, 14, 0.35)
    xs = reverb(xs, "bighall", 0.3)
    m = xs.shape[0]
    xs *= macro(m, [(0, 0), (0.5, -1), (1.1, -6), (1.9, -14), (2.6, -26), (3.0, -40), (m / SR, -70)])[:, None]
    return widen(xs, 1.3)


@sfx("near_miss", -15, stereo_out=True)
def near_miss(rng):
    n = ns(0.85)
    t = tarr(n)
    tp = 0.3  # closest approach
    shape = np.exp(-((t - tp) / 0.12) ** 2)
    shape = np.where(t > tp, np.exp(-(t - tp) / 0.18), shape)
    fc = 600 + 2600 / (1 + np.exp((t - tp) / 0.05))
    whoosh = svf(white(n, rng), fc, 1.3, "bp") * shape
    zing = sine(1250 + 600 / (1 + np.exp((t - tp) / 0.03)), n) * shape * 0.25
    x = whoosh + zing
    p = np.tanh((t - tp) / 0.1) * 0.85
    xs = pan_dynamic(x, p)
    return trim_tail(reverb(xs, "room", 0.2), -60)


@sfx("incoming", -17)
def incoming(rng):
    def beep(f):
        n = ns(0.075)
        b = (square(f, n, 0.5) * 0.35 + sine(f, n) * 0.65)
        return svf(b, 5000, 0.7, "lp") * adsr(0.065, 0.003, 0.02, 0.8, 0.01, n)
    x = L(beep(1568), at(beep(1568), 0.12), at(beep(2093), 0.24))
    return rev_mono(x, "small", 0.18)


# =============================================================================================
# ALERTS
# =============================================================================================
@sfx("alarm_station", -14, loop=True)
def alarm_station(rng):
    P, R = 2.0, 3
    n = ns(P * R)
    x = np.zeros(n)
    whoop_len = 0.78
    m = ns(whoop_len)
    tt = tarr(m)
    f = 410 * (790 / 410) ** (tt / whoop_len) ** 0.8
    tone = square(f, m, 0.42, 0.0) * 0.5 + saw(f, m, 0.0) * 0.5
    tone = svf(tone, 1250, 1.8, "bp") * 1.8 + svf(tone, 3000, 0.7, "lp") * 0.4
    env = adsr(whoop_len - 0.06, 0.02, 0.1, 0.9, 0.05, m)
    whoop = saturate(tone * env, 2.0)
    for k in range(R * 2):
        mix_into(x, whoop, ns(k * 1.0))
    x = mono(reverb(x, "room", 0.22, tail=False))
    return middle_period(x, P, R)


@sfx("warning_low_energy", -16)
def warning_low_energy(rng):
    def beep(f, d):
        n = ns(d + 0.05)
        b = triangle(f, n) * 0.7 + square(f, n, 0.5) * 0.3
        return svf(b, 3500, 0.8, "lp") * adsr(d, 0.004, 0.03, 0.85, 0.04, n)
    x = L(beep(988, 0.13), at(beep(784, 0.16), 0.22))
    return trim_tail(rev_mono(x, "small", 0.2), -60)


@sfx("wave_incoming", -14)
def wave_incoming(rng):
    def stab(chord, d):
        n = ns(d + 0.3)
        tt = tarr(n)
        out = np.zeros(n)
        for m in chord:
            f = midi_to_hz(m)
            o = saw(f, n) + saw(f * 1.006, n)
            o = lp24(o, 400 + 4000 * np.exp(-tt / 0.08), 1.2)
            out += o * adsr(d, 0.006, 0.15, 0.6, 0.25, n)
        return out / len(chord)
    t1 = stab([52, 55, 59, 64], 0.16)
    t2 = stab([53, 56, 60, 65], 0.5)
    n = ns(1.1)
    hit = sine(40 + 90 * np.exp(-tarr(n) / 0.04), n) * exp_decay(n, 0.25)
    sw = svf(white(n), 400 + 3000 * np.exp(-tarr(n) / 0.2), 1.3, "bp") * exp_decay(n, 0.2, attack=0.02) * 0.3
    x = L(t1, at(t2, 0.22), at(hit * 0.8, 0.22), at(sw, 0.2))
    return trim_tail(rev_mono(saturate(x, 1.5), "hall", 0.25), -60)


# =============================================================================================
# HYPERJUMP / WARP
# =============================================================================================
@sfx("hyperjump", -11, stereo_out=True)
def hyperjump(rng):
    n = ns(2.6)
    t = tarr(n)
    tc = 1.9
    k = np.clip(t / tc, 0, 1)
    f = 75 * (1500 / 75) ** (k ** 1.3)
    trem_rate = 4 + 32 * k ** 2
    trem = 0.65 + 0.35 * np.sin(2 * np.pi * np.cumsum(trem_rate) / SR)
    charge = (sine(f, n) * 0.5 + saw(f, n) * 0.35 + saw(f * 1.5, n) * 0.15)
    charge = lp24(charge, 300 + 7000 * k ** 2, 1.2) * trem * (k ** 1.5) * (t < tc + 0.03)
    charge = fade(charge, 0, 0.0)
    swell = svf(white(n, rng), 400 + 7500 * k ** 2, 1.4, "bp") * k ** 2.5 * (t < tc + 0.02) * 0.8
    m = n - ns(tc)
    tt = tarr(m)
    woosh = svf(pink(m, rng), 200 + 9000 * np.exp(-tt / 0.12), 1.0, "bp") * exp_decay(m, 0.25, attack=0.003) * 1.6
    boom = sine(30 + 90 * np.exp(-tt / 0.05), m) * exp_decay(m, 0.35)
    zap = fm(3500 * np.exp(-tt / 0.08) + 300, m, 0.5, 2 * np.exp(-tt / 0.05)) * exp_decay(m, 0.06)
    x = np.zeros(n)
    x += charge * 0.9 + swell
    mix_into(x, woosh + boom + 0.4 * zap, ns(tc))
    xs = chorus(x, 0.5, 3, 10, 0.35)
    xs = reverb(xs, "hall", 0.25)
    return trim_tail(widen(xs, 1.4), -60)


@sfx("hyperjump_arrive", -12, stereo_out=True)
def hyperjump_arrive(rng):
    n = ns(1.6)
    t = tarr(n)
    boom = sine(28 + 70 * np.exp(-t / 0.08), n) * exp_decay(n, 0.5, attack=0.002)
    burst = lp24(white(n, rng), 200 + 2400 * np.exp(-t / 0.06), 0.8) * exp_decay(n, 0.2, attack=0.001)
    shimmer = np.stack([svf(white(n, rng), 7000, 3.0, "bp"), svf(white(n, rng), 7600, 3.0, "bp")], axis=1)
    shimmer *= (exp_decay(n, 0.6, attack=0.03) * 0.35)[:, None]
    tone = fm(220 * (1 + 0.5 * np.exp(-t / 0.1)), n, 2.0, 1.5 * np.exp(-t / 0.4)) * exp_decay(n, 0.5) * 0.25
    x = stereo_sub(boom + 0.7 * burst + tone) + shimmer
    x = reverb(x, "hall", 0.35)
    return trim_tail(widen(x, 1.3), -60)


@sfx("warp_in", -14)
def warp_in(rng):
    n = ns(1.05)
    t = tarr(n)
    tr = 0.33
    k = np.clip(t / tr, 0, 1)
    rip = svf(white(n, rng), 500 + 6000 * k ** 2, 2.0, "bp") * k ** 3 * (t < tr) * 1.4
    m = n - ns(tr)
    tt = tarr(m)
    zap = sine(300 + 3200 * np.exp(-tt / 0.03), m) * exp_decay(m, 0.06)
    tail = svf(saw(150 + 450 * np.exp(-tt / 0.12), m) + saw(152 + 455 * np.exp(-tt / 0.12), m), 1800, 1.4, "lp")
    tail *= exp_decay(m, 0.25)
    x = rip.copy()
    mix_into(x, 0.8 * zap + 0.5 * tail, ns(tr))
    x = mono(chorus(x, 1.3, 4, 6, 0.5))
    return trim_tail(rev_mono(saturate(x, 1.5), "room", 0.25), -60)


# =============================================================================================
# DOCKING / STATION
# =============================================================================================
@sfx("dock_slide", -16)
def dock_slide(rng):
    n = ns(3.1)
    t = tarr(n)
    env = env_points([(0, 0), (0.5, 1), (2.4, 0.9), (3.1, 0)], n)
    hum = (sine(55 * (1 + 0.05 * t / 3), n) * 0.7 + svf(saw(110 * (1 + 0.05 * t / 3), n), 320, 0.8, "lp") * 0.5)
    servo = sine(420 + 220 * np.clip(t / 2.5, 0, 1) + 6 * lfo(n, 7), n) * 0.18
    servo += sine(2 * (420 + 220 * np.clip(t / 2.5, 0, 1)), n) * 0.05
    hiss = svf(white(n, rng), 3500, 0.7, "hp") * env_points([(0, 0), (1.0, 0.3), (2.8, 0.15), (3.1, 0)], n) * 0.25
    rumble = svf(brown(n, rng), 110, 0.7, "lp") * 0.6
    clicks = svf(crackle(n, 6, rng, 3), 1500, 2, "bp") * 4
    x = (hum + servo + rumble) * env + hiss + clicks * env
    return trim_tail(rev_mono(x, "room", 0.25), -60)


@sfx("dock_clamp", -13)
def dock_clamp(rng):
    n = ns(1.1)

    def clunk(scale):
        m = ns(0.6)
        tt = tarr(m)
        exc = white(m, rng) * exp_decay(m, 0.003)
        metal = resonator_bank(exc, [142 * scale, 311 * scale, 523 * scale, 868 * scale, 1342 * scale, 2210 * scale],
                               [0.35, 0.3, 0.22, 0.18, 0.12, 0.08], [1.0, 0.8, 0.6, 0.45, 0.3, 0.2]) * 18
        thump = sine(50 + 60 * np.exp(-tt / 0.02), m) * exp_decay(m, 0.08)
        click = svf(white(m, rng), 3000, 0.7, "hp") * exp_decay(m, 0.002)
        return metal + thump + 0.5 * click
    m = ns(0.75)
    hiss = svf(white(m, rng), 2600, 0.6, "hp") * exp_decay(m, 0.28, attack=0.02) * 0.16
    x = L(clunk(1.0), at(clunk(1.12) * 0.8, 0.17), at(hiss, 0.3))
    return trim_tail(rev_mono(saturate(x, 1.4), "room", 0.3), -60)


@sfx("refuel_tick", -21)
def refuel_tick(rng):
    n = ns(0.15)
    t = tarr(n)
    f = 1320 * (1 + 0.04 * np.exp(-t / 0.01))
    x = sine(f, n) * 0.8 + sine(2 * f, n) * 0.2
    x *= exp_decay(n, 0.035, attack=0.001)
    x += svf(white(n, rng), 5000, 0.7, "hp") * exp_decay(n, 0.0015) * 0.3
    return rev_mono(x, "small", 0.15)


def _epiano(f, dur, vel=1.0, n_tail=0.8):
    n = ns(dur + n_tail)
    t = tarr(n)
    tine = fm(f, n, 1.0, (1.8 * vel) * np.exp(-t / 0.4) + 0.2)
    bell = fm(f * 1.0, n, 14.0, 0.6 * np.exp(-t / 0.03)) * 0.25
    env = adsr(dur, 0.002, 1.2, 0.0, 0.3, n, curve=3) * 0.6 + exp_decay(n, 1.4) * 0.4
    env *= np.clip(1 - np.maximum(0, t - dur) / max(n_tail, 1e-3), 0, 1)
    return (tine + bell) * env


@sfx("refuel_complete", -16)
def refuel_complete(rng):
    notes = [72, 76, 79, 84]
    x = np.zeros(ns(1.4))
    for i, m in enumerate(notes):
        mix_into(x, _epiano(midi_to_hz(m), 0.6 - i * 0.05, 0.9), ns(i * 0.075))
    pad_n = ns(1.2)
    pad = np.zeros(pad_n)
    for m in (60, 64, 67):
        pad += svf(saw(midi_to_hz(m), pad_n) + saw(midi_to_hz(m) * 1.005, pad_n), 1800, 0.7, "lp")
    pad *= env_points([(0, 0), (0.25, 0.25), (0.8, 0.2), (1.2, 0)], pad_n)
    mix_into(x, pad * 0.5, ns(0.2))
    return trim_tail(rev_mono(x, "plate", 0.35), -60)


# =============================================================================================
# PLANET
# =============================================================================================
@sfx("city_destroyed", -12)
def city_destroyed(rng):
    n = ns(3.2)
    t = tarr(n)
    blast = _blast(rng, 3.2, 1.6, (70, 26), 0.6)
    blast = butter(blast, "lp", 1300, 4)  # distance: muffled
    rumble = svf(brown(n, rng), 140, 0.7, "lp") * env_points([(0, 0), (0.4, 1), (1.2, 0.8), (3.2, 0)], n) ** 1.3
    rumble *= _turbulence(n, rng, 4, 0.6)
    debris = svf(crackle(n, 45, rng, 4), 1800, 0.7, "lp") * env_points([(0, 0), (0.3, 1), (3.0, 0)], n) * 4
    groan = np.zeros(n)
    bend = 1 - 0.1 * np.clip(t / 2.5, 0, 1)
    for f, g in [(96, 1.0), (151, 0.6), (233, 0.4)]:
        groan += g * np.sin(2 * np.pi * np.cumsum(f * bend) / SR)
    groan *= env_points([(0, 0), (0.6, 0), (1.0, 0.25), (2.5, 0.1), (3.2, 0)], n)
    x = 0.9 * blast + 0.8 * rumble + 0.4 * debris + 0.25 * groan
    x = rev_mono(saturate(x, 1.3), "hall", 0.35)
    m = x.shape[0]
    return x * macro(m, [(0, 0), (0.35, -1), (1.0, -6), (2.0, -13), (3.0, -22), (3.5, -32), (m / SR, -70)])


@sfx("bombard_loop", -14, loop=True)
def bombard_loop(rng):
    P, R = 2.0, 3
    n = ns(P * R)
    t = tarr(n)
    drone = saw(73.5, n, 0.0) + saw(74.0, n, 0.5) + 0.5 * square(147.0, n, 0.3, 0.2)
    drone = lp24(drone, 520, 1.6)
    pulse = 0.6 + 0.4 * np.sin(2 * np.pi * 6.0 * t) ** 2
    nz = periodic_noise(P, R, rng)
    crack = svf(nz, 3000, 1.2, "bp") * (0.4 + 0.6 * (0.5 + 0.5 * np.sin(2 * np.pi * 12 * t)) ** 4)
    whine = np.sin(2 * np.pi * 880 * t + 3 * np.sin(2 * np.pi * 6 * t)) * 0.08
    sub = np.sin(2 * np.pi * 36.5 * t) * 0.5
    x = 0.55 * drone * pulse + 0.3 * crack + whine + sub
    x = saturate(x, 1.8)
    x = mono(reverb(x, "room", 0.2, tail=False))
    return middle_period(x, P, R)


# =============================================================================================
# UI
# =============================================================================================
def _blip(f, d, bright=1.0):
    n = ns(d + 0.02)
    t = tarr(n)
    x = fm(f, n, 2.0, bright * np.exp(-t / 0.02)) * adsr(d, 0.001, d * 0.5, 0.5, 0.015, n)
    return x


@sfx("ui_move", -24)
def ui_move(rng):
    n = ns(0.07)
    t = tarr(n)
    x = sine(1900 * (1 + 0.1 * np.exp(-t / 0.005)), n) * exp_decay(n, 0.018, attack=0.0005)
    x += svf(white(n, rng), 4500, 0.7, "hp") * exp_decay(n, 0.0012) * 0.3
    return x


@sfx("ui_select", -21)
def ui_select(rng):
    x = L(_blip(1046.5, 0.055), at(_blip(1568, 0.11, 1.4), 0.06))
    return trim_tail(rev_mono(x, "small", 0.2), -60)


@sfx("ui_back", -22)
def ui_back(rng):
    x = L(_blip(1568, 0.05), at(_blip(1046.5, 0.09, 0.8), 0.055))
    return trim_tail(rev_mono(x, "small", 0.2), -60)


@sfx("ui_error", -20)
def ui_error(rng):
    def buzz():
        n = ns(0.11)
        b = square(158, n, 0.5) + square(166, n, 0.4)
        return svf(b, 1100, 0.8, "lp") * adsr(0.09, 0.003, 0.02, 0.9, 0.015, n)
    x = L(buzz(), at(buzz(), 0.15))
    return trim_tail(rev_mono(x, "small", 0.12), -60)


@sfx("ui_type", -25)
def ui_type(rng):
    n = ns(0.05)
    x = svf(white(n, rng), 2200, 0.8, "hp") * exp_decay(n, 0.004, attack=0.0003)
    x += sine(2400, n) * exp_decay(n, 0.008) * 0.4
    return x


@sfx("map_open", -18)
def map_open(rng):
    n = ns(0.5)
    t = tarr(n)
    sweep = svf(white(n, rng), 300 * (6000 / 300) ** np.clip(t / 0.35, 0, 1), 2.0, "bp") * \
        env_points([(0, 0), (0.05, 1), (0.35, 0.7), (0.5, 0)], n) * 0.5
    chirps = np.zeros(n)
    for i, f in enumerate([660, 990, 1320, 1980]):
        m = ns(0.05)
        c = square(f, m, 0.5) * exp_decay(m, 0.02)
        mix_into(chirps, bitcrush(c, 6, 2) * 0.35, ns(0.03 + i * 0.035))
    x = sweep + chirps
    return trim_tail(rev_mono(x, "plate", 0.2), -60)


@sfx("map_close", -19)
def map_close(rng):
    n = ns(0.45)
    t = tarr(n)
    sweep = svf(white(n, rng), 5500 * (300 / 5500) ** np.clip(t / 0.3, 0, 1), 2.0, "bp") * \
        env_points([(0, 0), (0.02, 1), (0.3, 0.5), (0.45, 0)], n) * 0.5
    chirps = np.zeros(n)
    for i, f in enumerate([1980, 1320, 990, 660]):
        m = ns(0.05)
        c = square(f, m, 0.5) * exp_decay(m, 0.02)
        mix_into(chirps, bitcrush(c, 6, 2) * 0.3, ns(0.01 + i * 0.03))
    x = sweep + chirps
    return trim_tail(rev_mono(x, "plate", 0.2), -60)


@sfx("target_lock", -26)
def target_lock(rng):
    def tick():
        n = ns(0.03)
        return sine(3100, n) * exp_decay(n, 0.006, attack=0.0004)
    return L(tick(), at(tick() * 0.8, 0.045))


# =============================================================================================
# JINGLES
# =============================================================================================
def _brass(f, dur, vel=1.0, bright=1.0):
    n = ns(dur + 0.35)
    t = tarr(n)
    o = saw(f, n) + saw(f * 1.0035, n) + 0.5 * saw(f * 0.9965, n) + 0.3 * square(f / 2, n, 0.5)
    fenv = adsr(dur, 0.04, 0.35, 0.45, 0.3, n)
    cut = f * 1.3 + (f * 7 * bright + 900) * fenv
    vib = 1 + 0.004 * np.clip((t - 0.25) / 0.3, 0, 1) * np.sin(2 * np.pi * 5.3 * t)
    o = lp24(o, cut * vib, 1.1)
    return saturate(o * adsr(dur, 0.03, 0.25, 0.85, 0.3, n) * vel * 0.4, 1.3)


def _bell(f, dur):
    n = ns(dur)
    t = tarr(n)
    return fm(f, n, 3.5, 3.0 * np.exp(-t / 0.25) + 0.3) * exp_decay(n, dur * 0.35, attack=0.001)


def _timp_roll(f, dur, n_hits=14):
    n = ns(dur + 0.8)
    out = np.zeros(n)
    for i in range(n_hits):
        m = ns(0.9)
        tt = tarr(m)
        hit = (sine(f * (1 + 0.04 * np.exp(-tt / 0.05)), m) + 0.4 * sine(f * 1.5, m)) * exp_decay(m, 0.5)
        hit += svf(white(m), 400, 0.7, "lp") * exp_decay(m, 0.03)
        mix_into(out, hit * (0.3 + 0.7 * (i / n_hits)), ns(i * dur / n_hits))
    return out


@sfx("squadron_destroyed", -14, stereo_out=True)
def squadron_destroyed(rng):
    # motif fragment (rising fifth) resolving to a bright D major chord
    x = np.zeros(ns(2.8))
    mix_into(x, _brass(midi_to_hz(62), 0.13), 0)
    mix_into(x, _brass(midi_to_hz(69), 0.32), ns(0.15))
    for m in (62, 66, 69, 74):
        mix_into(x, _brass(midi_to_hz(m), 1.3, 0.8), ns(0.5))
    for i, m in enumerate((81, 86, 90)):
        mix_into(x, _bell(midi_to_hz(m), 1.4) * 0.25, ns(0.5 + i * 0.09))
    n = ns(0.6)
    hit = sine(45 + 70 * np.exp(-tarr(n) / 0.04), n) * exp_decay(n, 0.2)
    mix_into(x, hit * 0.6, ns(0.5))
    xs = chorus(x, 0.4, 2.5, 12, 0.3)
    xs = reverb(xs, "hall", 0.3)
    return trim_tail(xs, -60)


@sfx("planet_saved", -13, stereo_out=True)
def planet_saved(rng):
    x = np.zeros(ns(3.6))
    # D – A (motif) then bVI – bVII – I victory cadence
    mix_into(x, _brass(midi_to_hz(62), 0.2), 0)
    mix_into(x, _brass(midi_to_hz(69), 0.5), ns(0.22))
    chords = [((58, 62, 65, 70), 0.8, 0.28), ((60, 64, 67, 72), 1.1, 0.28), ((62, 66, 69, 74, 78), 1.4, 1.7)]
    for notes, start, d in chords:
        for m in notes:
            mix_into(x, _brass(midi_to_hz(m), d, 0.7), ns(start))
    # choir-ish pad on the final chord
    pn = ns(2.2)
    pad = np.zeros(pn)
    tt = tarr(pn)
    for m in (50, 57, 62, 66, 69):
        f = midi_to_hz(m)
        v = saw(f, pn) + saw(f * 1.004, pn) + saw(f * 0.996, pn)
        pad += svf(v, 900 + 300 * np.sin(2 * np.pi * 0.7 * tt), 1.5, "bp")
    pad *= env_points([(0, 0), (0.3, 0.3), (1.6, 0.25), (2.2, 0)], pn)
    mix_into(x, pad * 0.5, ns(1.4))
    for i, m in enumerate((86, 90, 93, 98)):
        mix_into(x, _bell(midi_to_hz(m), 1.6) * 0.22, ns(1.4 + i * 0.08))
    mix_into(x, _timp_roll(midi_to_hz(38), 0.55, 10) * 0.5, ns(0.8))
    n = ns(0.8)
    hit = sine(40 + 70 * np.exp(-tarr(n) / 0.05), n) * exp_decay(n, 0.3)
    mix_into(x, hit * 0.7, ns(1.4))
    xs = chorus(x, 0.4, 2.5, 12, 0.3)
    xs = reverb(xs, "hall", 0.35)
    return trim_tail(xs, -60)


# =============================================================================================
# AMBIENCE
# =============================================================================================
@sfx("engine_loop", -24, stereo_out=True, loop=True)
def engine_loop(rng):
    P, R = 4.0, 3
    n = ns(P * R)
    t = tarr(n)
    hum = (np.sin(2 * np.pi * 41.0 * t) + 0.8 * np.sin(2 * np.pi * 41.25 * t + 1.0) +
           0.35 * np.sin(2 * np.pi * 82.0 * t + 0.3) + 0.18 * np.sin(2 * np.pi * 123.0 * t + 2.0) +
           0.08 * np.sin(2 * np.pi * 246.0 * t + 0.7))
    hum *= 0.85 + 0.15 * np.sin(2 * np.pi * 0.25 * t)
    nz = periodic_noise(P, R, rng, "pink", channels=2)
    air = svf(nz, 260 + 40 * np.sin(2 * np.pi * 0.5 * t), 0.7, "lp") * 0.5
    elec = svf(periodic_noise(P, R, rng, "white", channels=2), 5200, 2.0, "bp") * 0.03
    whine = np.sin(2 * np.pi * 1840.0 * t + 0.6 * np.sin(2 * np.pi * 0.5 * t)) * 0.012
    x = air + elec
    x[:, 0] += 0.5 * hum + whine
    x[:, 1] += 0.5 * hum * 0.97 + whine * 0.8
    return middle_period(x, P, R)



# maximum file durations (spec durations + a little room for the natural tail); a smooth fade
# is applied at the cut. Loops are never cut.
MAXDUR = {
    "laser_1": 0.42, "laser_2": 0.4, "laser_3": 0.45, "ion_fire": 1.45, "ion_ready": 0.5, "shield_hit": 0.8,
    "shield_break": 1.05, "laser_deflect": 0.45, "explosion_small_1": 1.55, "explosion_small_2": 1.5,
    "explosion_small_3": 1.55, "explosion_large_1": 3.1, "explosion_large_2": 3.2, "explosion_huge": 5.6,
    "player_hit_light": 0.55, "player_hit_heavy": 1.4, "enemy_shot_fighter": 0.42, "enemy_shot_destroyer": 1.25,
    "flagship_fire": 3.0, "near_miss": 0.9, "incoming": 0.6, "warning_low_energy": 0.8, "hyperjump": 2.8,
    "hyperjump_arrive": 1.8, "warp_in": 1.15, "dock_slide": 3.3, "dock_clamp": 1.15, "refuel_tick": 0.2,
    "refuel_complete": 1.5, "city_destroyed": 3.5, "ui_move": 0.08, "ui_select": 0.3, "ui_back": 0.25,
    "ui_error": 0.38, "ui_type": 0.05, "map_open": 0.65, "map_close": 0.6, "wave_incoming": 1.35,
    "squadron_destroyed": 2.9, "planet_saved": 3.6, "target_lock": 0.1,
}


# UI / tiny sounds must never be peaky: lower peak ceilings (dBFS)
PEAK_MAX = {"ui_move": -9.0, "ui_select": -8.0, "ui_back": -9.0, "ui_error": -8.0, "ui_type": -10.0,
            "target_lock": -12.0, "refuel_tick": -7.0, "ion_ready": -10.0}


def cap(name, x):
    md = MAXDUR.get(name)
    if md is None:
        return x
    n = ns(md)
    if x.shape[0] <= n:
        return x
    x = x[:n].copy()
    fl = min(ns(0.18), int(n * 0.3))
    ramp = np.cos(np.linspace(0, np.pi / 2, fl)) ** 2
    x[-fl:] *= ramp if x.ndim == 1 else ramp[:, None]
    return x


# =============================================================================================
def finish(name, x, target_rms, loop):
    x = np.asarray(x, dtype=np.float64)
    if not loop:
        x = remove_dc(x, 12.0)
        # remove leading near-silence (attack must be immediate)
        a = np.abs(mono(x)) if x.ndim == 2 else np.abs(x)
        th = db(-50) * a.max()
        first = int(np.argmax(a > th))
        x = x[max(0, first - 8):]
        x = cap(name, x)
        x = fade(x, 0.0005, 0.01)
    else:
        x = x - np.mean(x, axis=0)
    cur = short_term_max(x)
    gain = db(target_rms - cur)
    x = x * gain
    peak = np.max(np.abs(x))
    ceiling = db(PEAK_MAX.get(name, -1.0))
    if peak > ceiling:
        if loop:
            x *= ceiling / peak  # never limit loops (would break periodicity at seam)
        else:
            # soft limiting for transient-heavy sounds, then hard scale
            x = limit(x, -1.2, 60)
            p2 = np.max(np.abs(x))
            if p2 > ceiling:
                x *= ceiling / p2
    return x


def main(names):
    os.makedirs(OUT, exist_ok=True)
    report = []
    for name, (fn, target, st, loop) in REGISTRY.items():
        if names and name not in names:
            continue
        rng = rng_for(name)
        x = fn(rng)
        if not st and x.ndim == 2:
            x = mono(x)
        if st and x.ndim == 1:
            x = np.stack([x, x], axis=1)
        x = finish(name, x, target, loop)
        path = os.path.join(OUT, name + ".wav")
        write_wav(path, x, None, dither=not loop)
        info = dict(name=name, dur=x.shape[0] / SR, ch=1 if x.ndim == 1 else 2, peak=to_db(np.max(np.abs(x))),
                    rms=short_term_max(x), loop=loop)
        if loop:
            info.update(loop_seam(x))
        report.append(info)
        print(f"{name:24s} {info['dur']:5.2f}s ch={info['ch']} peak={info['peak']:6.1f} st_rms={info['rms']:6.1f}"
              + (f"  LOOP jump_ratio={info['jump_ratio']:.2f}" if loop else ""))
    return report


if __name__ == "__main__":
    main(sys.argv[1:])
