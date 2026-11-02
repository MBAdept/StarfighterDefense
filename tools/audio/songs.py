"""
songs.py – the soundtrack of Starfighter Defense, composed in code.

The main motif (rising fifth, stepwise answer):  1 – 5 | 6 5 4 3 4 | 3 7 ...
appears in the title theme (D minor, heroic), both combat tracks (E minor / F minor),
the docking theme (D major, relaxed), the game-over theme (D minor, slow) and – twisted into
tritones – in the enemy-system theme.

usage: /opt/tools/audiovenv/bin/python songs.py [title map combat_space combat_planet docking gameover enemy]
"""
from __future__ import annotations

import os
import sys
import time

import numpy as np

import instruments as ins
from musiclib import (Song, arp_track, bass_track, chords_track, diatonic, drum_pattern, fill, mel, nm,
                      parse_chord, scale_pcs, voice_chord, write_song)
from synthlib import ns

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "audio", "music")
DEBUG = os.path.join(os.path.dirname(__file__), "renders")


def merged(chords):
    """[(start_index, length, symbol)] merging equal consecutive symbols"""
    out = []
    for i, c in enumerate(chords):
        if out and out[-1][2] == c:
            out[-1][1] += 1
        else:
            out.append([i, 1, c])
    return out


def chords_merged(s, track, per_bar, start_bar=0, low=55, high=77, n_voices=4, vel=0.7, legato=1.0):
    prev = None
    for i, length, sym in merged(per_bar):
        v = voice_chord(sym, prev, low, high, n_voices)
        prev = v
        for m in v:
            s.note(track, s.bar(start_bar + i), length * s.bpb * legato, m, vel)


def bass_merged(s, track, per_bar, start_bar=0, octave=2, vel=0.8):
    for i, length, sym in merged(per_bar):
        _, _, bpc = parse_chord(sym)
        root = 12 * (octave + 1) + bpc
        if bpc >= 8:
            root -= 12
        s.note(track, s.bar(start_bar + i), length * s.bpb, root, vel)


def harmony_line(s, track, start_beat, melody, steps, scale, vel=0.7, transpose=0):
    for off, d, m, acc in mel(melody, transpose):
        if m is None:
            continue
        s.note(track, start_beat + off, d, diatonic(m, steps, scale), vel)


def tom_fill(s, start_beat, beats=1.0, tones=(190, 150, 120, 95), track="tom", v0=0.6, v1=1.0, step=0.25):
    n = int(beats / step)
    for k in range(n):
        tone = tones[min(len(tones) - 1, k * len(tones) // n)]
        s.hit(track, start_beat + k * step, "tom", v0 + (v1 - v0) * k / max(1, n - 1), tone=tone,
              pan=(-0.4 + 0.8 * k / max(1, n - 1)))


def snare_roll(s, track, start_beat, beats, kind="snare", v0=0.15, v1=1.0):
    # 16ths in the first half, 32nds in the second half
    half = beats / 2
    n1 = int(half / 0.25)
    n2 = int(half / 0.125)
    for k in range(n1):
        s.hit(track, start_beat + k * 0.25, kind, v0 + (v1 - v0) * 0.5 * k / n1)
    for k in range(n2):
        s.hit(track, start_beat + half + k * 0.125, kind, v0 + (v1 - v0) * (0.5 + 0.5 * k / n2))


# =============================================================================================
# 1) TITLE THEME – D minor, 96 BPM, 40 bars (100 s)
# =============================================================================================
THEME_A_DMIN = ("D4:1 A4:3 | Bb4:.5 A4:.5 G4:1 F4:1 G4:1 | F4:1 C5:3 | D5:.5 C5:.5 Bb4:1 A4:1 G4:1 | "
                "D4:1 A4:1 D5:2 | F5:2 D5:1 Bb4:1 | C5:1.5 Bb4:.5 A4:1 G4:1 | A4:4")


def title_theme():
    s = Song("title_theme", bpm=96, bars=40, tail=9.0, seed=11, delay_beats=0.75, delay_fb=0.35)
    intro = ["Dm", "Dm", "Bb", "C"]
    A = ["Dm", "Bb", "F", "C", "Dm", "Bb", "Gm", "A"]
    B = ["F", "C", "Dm", "Bb", "F", "C", "Bb", "A"]
    C = ["Gm", "Bb", "C", "Dm", "Gm", "Bb", "C", "A"]
    outro = ["Dm", "Bb", "C", "A"]
    prog = intro + A + B + C + A + outro
    assert len(prog) == 40
    dmin = scale_pcs("D", "minor")

    s.add("pad", "synth", voice=ins.v_supersaw_pad, gain_db=-12, sends={"hall": 0.3}, sidechain=0.3, hp=180)
    s.add("strings", "fluid", program=48, gain_db=-10, sends={"hall": 0.35}, humanize=0.012, hp=110)
    s.add("celli", "fluid", program=42, gain_db=-10, sends={"hall": 0.3}, humanize=0.01, channel=1, hp=45)
    s.add("choir", "fluid", program=52, gain_db=-12, sends={"hall": 0.45}, channel=2, hp=160)
    s.add("horn", "fluid", program=60, gain_db=-7, sends={"hall": 0.35}, humanize=0.008, channel=3, hp=90)
    s.add("brass", "synth", voice=ins.v_brass, gain_db=-6, sends={"hall": 0.25, "delay": 0.06}, hp=120)
    s.add("brass2", "synth", voice=ins.v_brass, gain_db=-12, sends={"hall": 0.3}, pan_=-0.25, hp=150)
    s.add("lead", "synth", voice=ins.v_lead, gain_db=-6, sends={"hall": 0.22, "delay": 0.22}, hp=150)
    s.add("bells", "synth", voice=ins.v_bell, gain_db=-19, sends={"hall": 0.35, "delay": 0.25}, hp=300)
    s.add("arp", "synth", voice=ins.v_pluck, gain_db=-16, sends={"delay": 0.3, "hall": 0.12}, sidechain=0.35,
          voice_kw={"decay": 0.15}, hp=200)
    s.add("bass", "synth", voice=ins.v_bass, gain_db=-10, sidechain=0.45, hp=35)
    s.add("sub", "synth", voice=ins.v_sub, gain_db=-17, sidechain=0.3)
    s.add("kick", "drum", gain_db=-6)
    s.add("snare", "drum", gain_db=-10, sends={"gated": 0.45, "plate": 0.06})
    s.add("hat", "drum", gain_db=-19)
    s.add("crash", "drum", gain_db=-17, sends={"hall": 0.2})
    s.add("tom", "drum", gain_db=-11, sends={"hall": 0.25})
    s.add("taiko", "drum", gain_db=-7, sends={"hall": 0.35})
    s.add("timp", "drum", gain_db=-10, sends={"hall": 0.4})
    s.add("fx", "audio", gain_db=-13, sends={"hall": 0.2})

    # section dynamics (before mastering)
    s.master_env = [(0, -5), (s.bar(4), -3), (s.bar(12), -1.5), (s.bar(20), -2.5), (s.bar(27.5), -0.5),
                    (s.bar(28), 0), (s.bar(36), -1.5), (s.bar(37), -4), (s.bar(40), -5)]
    # harmony beds
    chords_track(s, "pad", prog, 0, low=50, high=74, n_voices=4, vel=0.7, legato=1.0)
    s.automate("pad", [(0, -7), (s.bar(4), 0), (s.bar(36), 0), (s.bar(40), -4)])
    chords_track(s, "strings", prog[4:36], 4, low=55, high=76, n_voices=4, vel=0.62, legato=1.0)
    chords_track(s, "choir", prog[20:36], 20, low=57, high=74, n_voices=3, vel=0.7)
    s.melody("celli", 0, "D3:1 A3:3 | D3:4 | Bb2:4 | C3:4", vel=0.72)
    # bridge ostinato in the celli (8ths root/fifth)
    for i, sym in enumerate(C):
        r, _, bpc = parse_chord(sym)
        root = 48 + bpc if bpc < 5 else 36 + bpc
        for k in range(8):
            s.note("celli", s.bar(20 + i) + k * 0.5, 0.42, root + (7 if k % 4 == 2 else 0), 0.75 if k % 2 == 0 else 0.6)

    # melodies
    s.melody("horn", s.bar(4), THEME_A_DMIN, vel=0.8)
    s.melody("brass", s.bar(4), THEME_A_DMIN, vel=0.78)
    s.melody("lead", s.bar(12), "A4:1 C5:1 F5:2 | E5:1.5 D5:.5 C5:2 | D5:1 F5:1 A5:1 G5:.5 F5:.5 | G5:2 F5:1 D5:1 | "
                                "C5:1 F5:1 A5:2 | G5:1.5 F5:.5 E5:2 | D5:1 F5:1 Bb5:1 A5:.5 G5:.5 | A5:2 G5:1 E5:1", vel=0.82)
    bridge = "G4:1 D5:3 | F5:.5 D5:.5 C5:1 Bb4:2 | C5:1 G5:3 | F5:.5 E5:.5 D5:1 A4:2 | Bb4:1 G5:3 | " \
             "A5:.5 G5:.5 F5:1 D5:2 | E5:1 C6:3 | C#6:2 A5:2"
    s.melody("strings", s.bar(20), bridge, vel=0.72, transpose=-12)
    s.melody("horn", s.bar(24), "Bb4:1 G5:3 | A5:.5 G5:.5 F5:1 D5:2 | E5:1 C6:3 | C#6:2 A5:2", vel=0.75, transpose=-12)
    # climax: brass an octave up + diatonic third below, horns at written pitch
    s.melody("brass", s.bar(28), THEME_A_DMIN, vel=0.9, transpose=12)
    harmony_line(s, "brass2", s.bar(28), THEME_A_DMIN, -2, dmin, vel=0.75, transpose=12)
    s.melody("horn", s.bar(28), THEME_A_DMIN, vel=0.88)
    s.melody("horn", s.bar(36), "D4:1 A4:3 | Bb4:.5 A4:.5 G4:1 F4:2 | E4:1 G4:3 | A4:2 E4:2", vel=0.55)

    # arps / bells
    arp_track(s, "arp", prog[2:], 2, rate=4, pattern="updown", low=57, octaves=2, vel=0.55, gate=0.55)
    s.automate("arp", [(0, -10), (s.bar(4), -2), (s.bar(12), 0), (s.bar(36), -3), (s.bar(40), -8)])
    arp_track(s, "bells", B, 12, rate=2, pattern="updown", low=74, octaves=1, vel=0.5, gate=0.9)
    arp_track(s, "bells", A, 28, rate=2, pattern="updown", low=74, octaves=1, vel=0.5, gate=0.9)

    # bass
    bass_track(s, "bass", intro, 0, style="whole", octave=2, vel=0.75)
    bass_track(s, "bass", A, 4, style="half", octave=2, vel=0.8)
    bass_track(s, "bass", B, 12, style="eighths_oct", octave=2, vel=0.82)
    bass_track(s, "bass", C, 20, style="eighths", octave=2, vel=0.8)
    bass_track(s, "bass", A, 28, style="eighths_oct", octave=2, vel=0.88)
    bass_track(s, "bass", outro, 36, style="whole", octave=2, vel=0.7)
    bass_track(s, "sub", B + C + A, 12, style="whole", octave=1, vel=0.8)

    # drums
    fill(s, "timp", "timpani", s.bar(2), 32, 0.25, 0.12, 0.95, tone=73.4)
    s.clip("fx", s.bar(4), ins.fx_impact(s.rng, 1.0))
    s.hit("crash", s.bar(4), "crash", 0.9)
    drum_pattern(s, "taiko", "taiko", "X.....o.X...o.o.", 4, 8)
    drum_pattern(s, "hat", "hat", "o.g.o.g.o.g.o.g.", 4, 8)
    tom_fill(s, s.bar(7) + 3, 1.0)
    tom_fill(s, s.bar(11) + 2, 2.0, step=0.25)
    # B – synthwave drive
    drum_pattern(s, "kick", "kick", "X......xX.......", 12, 8)
    drum_pattern(s, "snare", "snare", "....X.......X...", 12, 8)
    drum_pattern(s, "hat", "hat", "xoxoxoxoxoxoxoxo", 12, 8)
    for b in (12, 16):
        s.hit("crash", s.bar(b), "crash", 0.85)
    tom_fill(s, s.bar(19) + 3, 1.0)
    # C – tribal build
    drum_pattern(s, "kick", "kick", "X.......X.......", 20, 8)
    drum_pattern(s, "tom", "tom", "x.ox.ox.x.ox.ox.", 20, 6, tone=85)
    drum_pattern(s, "taiko", "taiko", "X.......X.......", 20, 6)
    snare_roll(s, "snare", s.bar(26), 8, v0=0.15, v1=1.0)
    s.clip("fx", s.bar(26), ins.fx_riser(s.bt(8), s.rng))
    # A' – climax
    s.clip("fx", s.bar(28), ins.fx_impact(s.rng, 1.2))
    drum_pattern(s, "kick", "kick", "X...x...X...x...", 28, 8)
    drum_pattern(s, "snare", "snare", "....X.......X...", 28, 8)
    drum_pattern(s, "hat", "hat", "xoxoxoxoxoxoxoxo", 28, 8)
    drum_pattern(s, "taiko", "taiko", "X.......X.....o.", 28, 8)
    for b in (28, 32):
        s.hit("crash", s.bar(b), "crash", 1.0)
    tom_fill(s, s.bar(35) + 2, 2.0)
    # outro
    s.hit("taiko", s.bar(36), "taiko", 0.7)
    s.hit("taiko", s.bar(38), "taiko", 0.5)
    fill(s, "timp", "timpani", s.bar(39), 16, 0.25, 0.08, 0.35, tone=55.0)
    return s


# =============================================================================================
# 2) MAP THEME – A minor, 80 BPM, 30 bars (90 s)
# =============================================================================================
def map_theme():
    s = Song("map_theme", bpm=80, bars=30, tail=12.0, seed=21, delay_beats=1.5, delay_fb=0.45, target_lufs=-15.0)
    per_bar = ["Am9", "Am9", "Fmaj7#11", "Fmaj7#11", "Dm9", "Dm9", "Esus4", "E",
               "Am9", "Am9", "Cmaj7", "Cmaj7", "Fmaj7", "Fmaj7", "G6", "E",
               "Dm9", "Dm9", "Am9", "Am9", "Bbmaj7", "Bbmaj7", "Esus4", "E",
               "Am9", "Am9", "Fmaj7", "Fmaj7", "Esus4", "E"]
    assert len(per_bar) == 30
    s.add("pad", "synth", voice=ins.v_warm_pad, gain_db=-10, sends={"space": 0.35}, hp=210)
    s.eq_lowmid, s.eq_presence, s.eq_air = -4.0, 2.0, 4.0
    s.master_env = [(0, -3), (s.bar(8), -1.5), (s.bar(16), 0), (s.bar(24), -1), (s.bar(30), -2.5)]
    s.add("strings", "fluid", program=49, gain_db=-13, sends={"hall": 0.45}, humanize=0.015, hp=110)
    s.add("glass", "synth", voice=ins.v_bell, gain_db=-12, sends={"delay": 0.45, "space": 0.35},
          voice_kw={"ratio": 2.0, "index": 1.2, "decay": 0.9}, hp=350)
    s.add("pulse", "synth", voice=ins.v_pluck, gain_db=-15, sidechain=0.25, sends={"hall": 0.1},
          voice_kw={"shape": "tri", "decay": 0.09, "peak": 1400, "base": 120, "q": 0.9})
    s.add("sub", "synth", voice=ins.v_sub, gain_db=-15)
    s.add("sonar", "synth", voice=ins.v_bell, gain_db=-13, sends={"space": 0.7},
          voice_kw={"ratio": 1.0, "index": 0.6, "decay": 2.2}, hp=500)
    s.add("horn", "fluid", program=60, gain_db=-10, sends={"hall": 0.6}, humanize=0.01, hp=90)
    s.add("kick", "drum", gain_db=-13)
    s.add("hat", "drum", gain_db=-22, sends={"hall": 0.2})
    s.add("shaker", "drum", gain_db=-21, sends={"hall": 0.2})

    chords_merged(s, "pad", per_bar, 0, low=55, high=79, n_voices=5, vel=0.7)
    chords_merged(s, "strings", per_bar[16:], 16, low=55, high=76, n_voices=4, vel=0.5)
    bass_merged(s, "sub", per_bar, 0, octave=1, vel=0.85)
    # slow glassy arpeggio from bar 4, sparse 8ths
    arp_track(s, "glass", per_bar[4:], 4, rate=2, pattern="skip", low=69, octaves=1, vel=0.42, gate=0.9,
              skip=lambda k: k in (3, 7))
    # tension pulse bars 8-23
    bass_track(s, "pulse", per_bar[8:24], 8, style="eighths", octave=2, vel=0.7, gate=0.6)
    # sonar pings
    for b in range(0, 30, 4):
        s.note("sonar", s.bar(b) + 0.5, 1.0, nm("E6"), 0.7)
    # distant horn motif bars 16-23
    s.melody("horn", s.bar(16), "D4:1 A4:3 | G4:.5 F4:.5 E4:1 D4:2 | E4:1 B4:3 | A4:.5 G4:.5 E4:1 C4:2 | "
                                "F4:1 C5:3 | Bb4:.5 A4:.5 F4:1 D4:2 | E4:2 A4:2 | G#4:4", vel=0.6)
    drum_pattern(s, "kick", "kick", "x...............", 8, 20, tone=44, punch=0.5)
    drum_pattern(s, "hat", "hat", "..o...o...o...o.", 8, 20)
    drum_pattern(s, "shaker", "shaker", "gogogogogogogogo", 12, 16)
    return s


# =============================================================================================
# 3) COMBAT (SPACE) – E minor, 136 BPM, 60 bars (~106 s)
# =============================================================================================
THEME_EMIN = ("E4:1 B4:3 | C5:.5 B4:.5 A4:1 G4:1 A4:1 | G4:1 D5:3 | E5:.5 D5:.5 C5:1 B4:1 A4:1 | "
              "E4:1 B4:1 E5:2 | G5:2 E5:1 C5:1 | D5:1.5 C5:.5 B4:1 A4:1 | B4:4")
B_EMIN = ("G5:2 E5:1 C5:1 | D5:1.5 E5:.5 F#5:2 | G5:1 B5:1 A5:1 G5:1 | F#5:2 E5:2 | C5:1 E5:1 A5:2 | "
          "G5:1.5 E5:.5 C5:2 | D5:1 F#5:1 A5:1 D6:1 | B5:2 D#5:2")


def _groove(s, start, bars, kick="X...x...X...x...", snare="....X.......X...", hat="xoxoxoxoxoxoxoxo",
            ohat="..o...o...o...o.", snare_kind="clap"):
    drum_pattern(s, "kick", "kick", kick, start, bars)
    drum_pattern(s, "snare", snare_kind, snare, start, bars)
    drum_pattern(s, "hat", "hat", hat, start, bars)
    if ohat:
        drum_pattern(s, "ohat", "hat", ohat, start, bars, open_=True)


def combat_space():
    s = Song("combat_space", bpm=136, bars=60, tail=7.0, seed=31, delay_beats=0.75, delay_fb=0.33)
    intro = ["Em"] * 4
    A = ["Em", "C", "G", "D", "Em", "C", "Am", "B"] * 2
    B = ["C", "D", "Em", "Em", "Am", "C", "D", "B"] * 2
    brk = ["Am", "Bm", "C", "B7", "Am", "Bm", "C", "B"]
    A2 = ["Em", "C", "G", "D", "Em", "C", "Am", "B", "Em", "C", "D", "B"]
    turn = ["Em", "C", "D", "B"]
    prog = intro + A + B + brk + A2 + turn
    assert len(prog) == 60
    emin = scale_pcs("E", "minor")

    s.add("pad", "synth", voice=ins.v_supersaw_pad, gain_db=-14, sends={"hall": 0.25}, sidechain=0.55,
          voice_kw={"attack": 0.08, "release": 0.6, "cutoff": 3200}, hp=200)
    s.add("strings", "fluid", program=48, gain_db=-12, sends={"hall": 0.3}, humanize=0.008, hp=120)
    s.add("choir", "fluid", program=52, gain_db=-14, sends={"hall": 0.4}, channel=1, hp=160)
    s.add("brass", "synth", voice=ins.v_brass, gain_db=-6, sends={"hall": 0.2, "delay": 0.08}, hp=120)
    s.add("brass2", "synth", voice=ins.v_brass, gain_db=-12, sends={"hall": 0.25}, pan_=0.3, hp=150)
    s.add("lead", "synth", voice=ins.v_lead, gain_db=-7, sends={"hall": 0.18, "delay": 0.25}, hp=150)
    s.add("arp", "synth", voice=ins.v_pluck, gain_db=-16, sends={"delay": 0.25, "hall": 0.1}, sidechain=0.4,
          voice_kw={"decay": 0.11, "peak": 4800}, hp=220)
    s.add("bass", "synth", voice=ins.v_bass, gain_db=-11, sidechain=0.5, voice_kw={"decay": 0.09, "peak": 2000}, hp=35)
    s.add("sub", "synth", voice=ins.v_sub, gain_db=-22, sidechain=0.6)
    s.add("kick", "drum", gain_db=-7, hp=30)
    s.add("snare", "drum", gain_db=-9, sends={"gated": 0.35, "plate": 0.05})
    s.add("hat", "drum", gain_db=-18)
    s.add("ohat", "drum", gain_db=-24)
    s.add("crash", "drum", gain_db=-17, sends={"hall": 0.15})
    s.add("tom", "drum", gain_db=-11, sends={"hall": 0.2})
    s.add("taiko", "drum", gain_db=-11, sends={"hall": 0.3}, hp=40)
    s.add("fx", "audio", gain_db=-14, sends={"hall": 0.2})

    s.master_env = [(0, -4), (s.bar(4), -1.5), (s.bar(20), -1), (s.bar(36), -3), (s.bar(43.5), -1.5),
                    (s.bar(44), 0), (s.bar(56), -1), (s.bar(60), -1.5)]
    chords_track(s, "pad", prog, 0, low=52, high=74, n_voices=4, vel=0.65)
    s.automate("pad", [(0, -6), (s.bar(4), 0)])
    chords_track(s, "strings", B + brk + A2, 20, low=55, high=76, n_voices=4, vel=0.6)
    chords_track(s, "choir", B[8:] + brk + A2, 28, low=57, high=74, n_voices=3, vel=0.65)
    # break: string ostinato
    for i, sym in enumerate(brk):
        r, _, bpc = parse_chord(sym)
        root = 45 + ((bpc - 9) % 12)
        for k in range(8):
            s.note("strings", s.bar(36 + i) + k * 0.5, 0.35, root + (12 if k % 2 else 0), 0.72 if k % 2 == 0 else 0.6)

    # themes
    s.melody("brass", s.bar(4), THEME_EMIN, vel=0.82)
    s.melody("brass", s.bar(12), THEME_EMIN, vel=0.86, transpose=12)
    harmony_line(s, "brass2", s.bar(12), THEME_EMIN, -2, emin, vel=0.7, transpose=12)
    s.melody("lead", s.bar(20), B_EMIN, vel=0.84)
    s.melody("lead", s.bar(28), B_EMIN, vel=0.88)
    harmony_line(s, "brass2", s.bar(28), B_EMIN, -2, emin, vel=0.6, transpose=-12)
    s.melody("brass", s.bar(44), THEME_EMIN, vel=0.92, transpose=12)
    harmony_line(s, "brass2", s.bar(44), THEME_EMIN, -2, emin, vel=0.75, transpose=12)
    s.melody("brass", s.bar(52), "E5:1 B5:3 | C6:.5 B5:.5 A5:1 G5:2 | F#5:1 A5:1 D6:2 | D#6:4", vel=0.95)
    s.melody("strings", s.bar(52), "E5:1 B5:3 | C6:.5 B5:.5 A5:1 G5:2 | F#5:1 A5:1 D6:2 | D#6:4", vel=0.8,
             transpose=-12)

    # arps
    arp_track(s, "arp", intro[2:] + A + B, 2, rate=4, pattern="updown", low=64, octaves=2, vel=0.55, gate=0.5)
    arp_track(s, "arp", A2 + turn, 44, rate=4, pattern="updown", low=64, octaves=2, vel=0.6, gate=0.5)
    s.automate("arp", [(0, -9), (s.bar(4), 0)])

    # bass
    bass_track(s, "bass", intro + A + B, 0, style="sixteenths", octave=2, vel=0.8)
    bass_track(s, "bass", brk, 36, style="eighths", octave=2, vel=0.82)
    bass_track(s, "bass", A2 + turn, 44, style="sixteenths", octave=2, vel=0.85)
    bass_track(s, "sub", A + B + brk + A2 + turn, 4, style="half", octave=1, vel=0.75)
    s.automate("bass", [(0, -4), (s.bar(4), 0)])

    # drums
    drum_pattern(s, "kick", "kick", "X...x...X...x...", 0, 4)
    drum_pattern(s, "hat", "hat", "o.o.o.o.o.o.o.o.", 0, 4)
    s.clip("fx", s.bar(2), ins.fx_riser(s.bt(8), s.rng))
    snare_roll(s, "snare", s.bar(3), 4, kind="snare", v0=0.2, v1=0.95)
    for start, n in ((4, 16), (20, 16)):
        _groove(s, start, n)
    drum_pattern(s, "taiko", "taiko", "X...............", 20, 16)
    for b in (4, 12, 20, 28):
        s.hit("crash", s.bar(b), "crash", 0.9)
    for b in (4, 20, 44):
        s.clip("fx", s.bar(b), ins.fx_impact(s.rng, 0.9))
    tom_fill(s, s.bar(11) + 2, 2.0)
    tom_fill(s, s.bar(19) + 3, 1.0)
    tom_fill(s, s.bar(27) + 3, 1.0)
    s.clip("fx", s.bar(34), ins.fx_riser(s.bt(8), s.rng))
    tom_fill(s, s.bar(35) + 2, 2.0)
    # break: half-time
    drum_pattern(s, "kick", "kick", "X.........X.....", 36, 8)
    drum_pattern(s, "snare", "snare", "........X.......", 36, 6)
    drum_pattern(s, "hat", "hat", "x.o.x.o.x.o.x.o.", 36, 8)
    drum_pattern(s, "tom", "tom", "x..x..x...x..x..", 36, 6, tone=90)
    drum_pattern(s, "taiko", "taiko", "X.......X.......", 36, 8)
    snare_roll(s, "snare", s.bar(42), 8, kind="snare", v0=0.15, v1=1.0)
    s.clip("fx", s.bar(42), ins.fx_riser(s.bt(8), s.rng))
    # A2 + turnaround
    _groove(s, 44, 16)
    drum_pattern(s, "taiko", "taiko", "X.......X.......", 44, 12)
    for b in (44, 48, 52, 56):
        s.hit("crash", s.bar(b), "crash", 1.0 if b == 44 else 0.85)
    tom_fill(s, s.bar(51) + 3, 1.0)
    tom_fill(s, s.bar(55) + 2, 2.0)
    tom_fill(s, s.bar(59) + 2, 2.0, v0=0.5, v1=0.9)
    return s


# =============================================================================================
# 4) COMBAT (PLANET) – F minor, 142 BPM, 64 bars (~108 s) – darker, more urgent
# =============================================================================================
THEME_FMIN = ("F4:1 C5:3 | Db5:.5 C5:.5 Bb4:1 Ab4:1 Bb4:1 | Ab4:1 Eb5:3 | F5:.5 Eb5:.5 Db5:1 C5:1 Bb4:1 | "
              "F4:1 C5:1 F5:2 | Ab5:2 F5:1 Db5:1 | Eb5:1.5 Db5:.5 C5:1 Bb4:1 | C5:4")
B_FMIN = ("Ab5:.5 F5:.5 Db5:.5 F5:.5 Ab5:1 Bb5:1 | G5:.5 Eb5:.5 Bb4:.5 Eb5:.5 G5:2 | Ab5:1 C6:1 Bb5:.5 Ab5:.5 G5:1 | "
          "F5:4 | Bb5:1 Ab5:.5 F5:.5 Db5:2 | Ab5:1 F5:.5 Db5:.5 Ab4:2 | G5:1 Bb5:1 Eb6:2 | E5:2 G5:2")


def combat_planet():
    s = Song("combat_planet", bpm=142, bars=64, tail=7.0, seed=41, delay_beats=0.75, delay_fb=0.3)
    intro = ["Fm"] * 4
    A = ["Fm", "Db", "Ab", "Eb", "Fm", "Db", "Bbm", "C"] * 2
    B = ["Db", "Eb", "Fm", "Fm", "Bbm", "Db", "Eb", "C"] * 2
    brk = ["Fm", "Gb", "Fm", "Gb", "Db", "Eb", "C", "C"]
    A2 = ["Fm", "Db", "Ab", "Eb", "Fm", "Db", "Bbm", "C"] * 2
    turn = ["Fm", "Db", "Eb", "C"]
    prog = intro + A + B + brk + A2 + turn
    assert len(prog) == 64
    fmin = scale_pcs("F", "minor")

    s.add("pad", "synth", voice=ins.v_supersaw_pad, gain_db=-15, sends={"hall": 0.25}, sidechain=0.55,
          voice_kw={"attack": 0.06, "release": 0.5, "cutoff": 1900}, hp=200)
    s.add("strings", "fluid", program=44, gain_db=-13, sends={"hall": 0.3}, humanize=0.006, hp=110)  # tremolo strings
    s.add("choir", "fluid", program=52, gain_db=-14, sends={"hall": 0.4}, channel=1, hp=160)
    s.add("brass", "synth", voice=ins.v_brass, gain_db=-7, sends={"hall": 0.2, "delay": 0.06},
          voice_kw={"bright": 0.85}, hp=120)
    s.add("brass2", "synth", voice=ins.v_brass, gain_db=-12, sends={"hall": 0.25}, pan_=-0.3, hp=150)
    s.add("stabs", "fluid", program=61, gain_db=-11, sends={"hall": 0.3}, channel=2, hp=120)  # brass section
    s.add("lead", "synth", voice=ins.v_lead, gain_db=-8, sends={"hall": 0.15, "delay": 0.22},
          voice_kw={"bright": 0.8}, hp=150)
    s.add("arp", "synth", voice=ins.v_pluck, gain_db=-17, sends={"delay": 0.22, "hall": 0.1}, sidechain=0.4,
          voice_kw={"decay": 0.1, "peak": 3800, "shape": "square"}, hp=220)
    s.add("bass", "synth", voice=ins.v_bass, gain_db=-12, sidechain=0.5, voice_kw={"decay": 0.08, "peak": 1700}, hp=35)
    s.add("reese", "synth", voice=ins.v_reese, gain_db=-13, sidechain=0.45, hp=38)
    s.add("kick", "drum", gain_db=-7, hp=30)
    s.add("snare", "drum", gain_db=-8, sends={"gated": 0.3, "plate": 0.05})
    s.add("hat", "drum", gain_db=-19)
    s.add("ohat", "drum", gain_db=-25)
    s.add("crash", "drum", gain_db=-17, sends={"hall": 0.15})
    s.add("tom", "drum", gain_db=-10, sends={"hall": 0.2})
    s.add("taiko", "drum", gain_db=-10, sends={"hall": 0.35}, hp=40)
    s.add("fx", "audio", gain_db=-14, sends={"hall": 0.2})

    s.master_env = [(0, -4), (s.bar(4), -1.5), (s.bar(20), -1), (s.bar(36), -2.5), (s.bar(43.5), -1.5),
                    (s.bar(44), 0), (s.bar(60), -1), (s.bar(64), -1.5)]
    chords_track(s, "pad", prog, 0, low=51, high=72, n_voices=4, vel=0.65)
    chords_track(s, "strings", B + brk + A2, 20, low=53, high=74, n_voices=4, vel=0.62)
    chords_track(s, "choir", brk + A2[8:], 36, low=55, high=72, n_voices=3, vel=0.7)
    # dissonant brass stabs in the break (Gb over F pedal)
    for i, sym in enumerate(brk):
        v = voice_chord(sym, None, 55, 72, 4)
        for off in (0, 1.5, 3):
            for m in v:
                s.note("stabs", s.bar(36 + i) + off, 0.4, m, 0.85 if off == 0 else 0.7)
    # themes
    s.melody("brass", s.bar(4), THEME_FMIN, vel=0.82)
    s.melody("brass", s.bar(12), THEME_FMIN, vel=0.86, transpose=12)
    harmony_line(s, "brass2", s.bar(12), THEME_FMIN, -2, fmin, vel=0.7, transpose=12)
    s.melody("lead", s.bar(20), B_FMIN, vel=0.84)
    s.melody("lead", s.bar(28), B_FMIN, vel=0.88)
    harmony_line(s, "brass2", s.bar(28), B_FMIN, -2, fmin, vel=0.6, transpose=-12)
    s.melody("brass", s.bar(44), THEME_FMIN, vel=0.92, transpose=12)
    harmony_line(s, "brass2", s.bar(44), THEME_FMIN, -2, fmin, vel=0.75, transpose=12)
    s.melody("brass", s.bar(52), THEME_FMIN, vel=0.95, transpose=12)
    s.melody("strings", s.bar(52), THEME_FMIN, vel=0.8)
    harmony_line(s, "brass2", s.bar(52), THEME_FMIN, -2, fmin, vel=0.75, transpose=12)

    arp_track(s, "arp", intro[2:] + A, 2, rate=4, pattern="skip", low=60, octaves=2, vel=0.55, gate=0.5)
    arp_track(s, "arp", A2 + turn, 44, rate=4, pattern="skip", low=60, octaves=2, vel=0.6, gate=0.5)
    bass_track(s, "bass", intro + A, 0, style="sixteenths", octave=2, vel=0.82)
    bass_track(s, "reese", B, 20, style="gallop", octave=2, vel=0.85)
    bass_track(s, "reese", brk, 36, style="whole", octave=2, vel=0.9)
    bass_track(s, "bass", A2 + turn, 44, style="sixteenths", octave=2, vel=0.86)
    s.automate("bass", [(0, -4), (s.bar(4), 0)])

    drum_pattern(s, "kick", "kick", "X.......X.......", 0, 4)
    drum_pattern(s, "taiko", "taiko", "X.....X...X.....", 0, 4)
    s.clip("fx", s.bar(2), ins.fx_riser(s.bt(8), s.rng))
    snare_roll(s, "snare", s.bar(3), 4, v0=0.2, v1=0.95)
    _groove(s, 4, 16, kick="X...x...X...x.x.", snare_kind="snare")
    _groove(s, 20, 16, kick="X..xx...X..xx...", snare_kind="snare", ohat="..x...x...x...x.")
    drum_pattern(s, "taiko", "taiko", "X.....X.........", 20, 16)
    for b in (4, 12, 20, 28):
        s.hit("crash", s.bar(b), "crash", 0.9)
    for b in (4, 20, 44):
        s.clip("fx", s.bar(b), ins.fx_impact(s.rng, 1.0))
    tom_fill(s, s.bar(11) + 2, 2.0, tones=(170, 140, 110, 85))
    tom_fill(s, s.bar(19) + 3, 1.0, tones=(170, 140, 110, 85))
    tom_fill(s, s.bar(27) + 3, 1.0, tones=(170, 140, 110, 85))
    s.clip("fx", s.bar(34), ins.fx_riser(s.bt(8), s.rng))
    tom_fill(s, s.bar(35) + 2, 2.0, tones=(170, 140, 110, 85))
    # break: taiko war drums
    drum_pattern(s, "taiko", "taiko", "X..X..X.X..X.X..", 36, 8)
    drum_pattern(s, "kick", "kick", "X.........X.....", 36, 8)
    drum_pattern(s, "snare", "snare", "........X.......", 36, 6)
    drum_pattern(s, "tom", "tom", "..x...x...x..x.x", 36, 6, tone=80)
    snare_roll(s, "snare", s.bar(42), 8, v0=0.15, v1=1.0)
    s.clip("fx", s.bar(42), ins.fx_riser(s.bt(8), s.rng))
    _groove(s, 44, 20, kick="X...x...X...x.x.", snare_kind="snare")
    drum_pattern(s, "taiko", "taiko", "X.......X.......", 44, 16)
    for b in (44, 48, 52, 56, 60):
        s.hit("crash", s.bar(b), "crash", 0.9)
    tom_fill(s, s.bar(51) + 3, 1.0, tones=(170, 140, 110, 85))
    tom_fill(s, s.bar(59) + 2, 2.0, tones=(170, 140, 110, 85))
    tom_fill(s, s.bar(63) + 2, 2.0, tones=(170, 140, 110, 85), v0=0.5, v1=0.9)
    return s


# =============================================================================================
# 5) DOCKING THEME – D major, 84 BPM, 20 bars (~57 s) – warm, safe harbour
# =============================================================================================
def docking_theme():
    s = Song("docking_theme", bpm=84, bars=20, tail=9.0, seed=51, delay_beats=0.75, delay_fb=0.35, target_lufs=-15.0)
    prog = ["Dmaj7", "Bm7", "Gmaj7", "A6", "Dmaj7", "F#m7", "Gmaj7", "Asus4",
            "Bm7", "Gmaj7", "Dmaj7/F#", "Gmaj7", "Em7", "F#m7", "Gmaj7", "A7sus4",
            "Dmaj7", "Bm7", "Gmaj7", "Asus4"]
    assert len(prog) == 20
    s.add("ep", "synth", voice=ins.v_epiano, gain_db=-10, sends={"plate": 0.25}, hp=160)
    s.eq_lowmid, s.eq_presence, s.eq_air = -4.0, 2.0, 3.5
    s.master_env = [(0, -2.5), (s.bar(4), -0.5), (s.bar(12), 0), (s.bar(20), -1.5)]
    s.add("pad", "synth", voice=ins.v_warm_pad, gain_db=-15, sends={"hall": 0.3}, voice_kw={"cutoff": 1900}, hp=220)
    s.add("strings", "fluid", program=49, gain_db=-15, sends={"hall": 0.4}, humanize=0.015, hp=120)
    s.add("bells", "synth", voice=ins.v_bell, gain_db=-7, sends={"hall": 0.3, "delay": 0.2},
          voice_kw={"ratio": 2.0, "index": 1.4, "decay": 1.1}, hp=300)
    s.add("bass", "synth", voice=ins.v_bass, gain_db=-12, voice_kw={"peak": 700, "drive": 1.05, "decay": 0.25}, hp=35)
    s.add("kick", "drum", gain_db=-12)
    s.add("rim", "drum", gain_db=-17, sends={"plate": 0.2})
    s.add("shaker", "drum", gain_db=-19)
    s.add("hat", "drum", gain_db=-21)

    chords_track(s, "ep", prog, 0, low=59, high=79, n_voices=4, vel=0.6,
                 rhythm=[(0, 1.4), (1.5, 0.9), (2.5, 1.4)])
    chords_track(s, "pad", prog, 0, low=50, high=72, n_voices=4, vel=0.6)
    chords_track(s, "strings", prog[8:], 8, low=57, high=76, n_voices=3, vel=0.45)
    s.melody("bells", s.bar(4), "D5:1 A5:3 | A5:.5 F#5:.5 E5:1 C#5:2 | D5:1 B5:3 | A5:.5 G5:.5 E5:1 D5:2 | "
                                "F#5:1 D6:3 | C#6:.5 B5:.5 A5:1 F#5:2 | A5:2 F#5:1 E5:1 | D5:4", vel=0.75)
    s.melody("bells", s.bar(12), "B5:1 G5:1 E5:2 | C#6:1 A5:1 F#5:2 | D6:1 B5:1 F#5:1 G5:1 | A5:4 | "
                                 "F#5:1 A5:1 D6:2 | D6:.5 C#6:.5 B5:1 F#5:2 | G5:1 B5:1 D6:1 F#6:1 | E6:4", vel=0.7)
    for i, sym in enumerate(prog):
        _, _, bpc = parse_chord(sym)
        root = 36 + bpc if bpc < 8 else 24 + bpc
        b0 = s.bar(i)
        s.note("bass", b0, 1.4, root, 0.75)
        s.note("bass", b0 + 1.5, 0.45, root + 12, 0.55)
        s.note("bass", b0 + 2.5, 1.2, root + 7, 0.65)
    drum_pattern(s, "kick", "kick", "x.......x.x.....", 2, 18, tone=50, punch=0.6)
    drum_pattern(s, "rim", "rim", "....x.......x...", 4, 16)
    drum_pattern(s, "shaker", "shaker", "goxogoxogoxogoxo", 4, 16)
    drum_pattern(s, "hat", "hat", "..o...o...o...o.", 8, 12)
    return s


# =============================================================================================
# 6) GAME OVER – D minor, 60 BPM, 9 bars + tail (~42 s), ends cleanly (no loop)
# =============================================================================================
def gameover_theme():
    s = Song("gameover_theme", bpm=60, bars=9, tail=7.0, seed=61, loop=False, target_lufs=-16.0)
    prog = ["Dm", "Bb", "Gm", "A", "Dm", "Bb", "Gm6", "Asus4", "Dm"]
    s.add("strings", "fluid", program=49, gain_db=-8, sends={"hall": 0.45}, humanize=0.012, hp=70)
    s.master_env = [(0, -2), (s.bar(4), 0), (s.bar(8), -1)]
    s.eq_lowmid, s.eq_presence, s.eq_air = -3.0, 1.5, 3.0
    s.add("horn", "fluid", program=60, gain_db=-6, sends={"hall": 0.45}, humanize=0.01, channel=1, hp=80)
    s.add("piano", "fluid", program=0, gain_db=-12, sends={"hall": 0.4}, channel=2)
    s.add("pad", "synth", voice=ins.v_warm_pad, gain_db=-13, sends={"space": 0.35},
          voice_kw={"cutoff": 900, "release": 4.0}, hp=100)
    s.add("sub", "synth", voice=ins.v_sub, gain_db=-14)
    s.add("timp", "drum", gain_db=-12, sends={"hall": 0.4})

    chords_track(s, "strings", prog[:7], 0, low=50, high=72, n_voices=4, vel=0.55)
    # bar 7: Asus4 -> A, bar 8: final Dm(add9) held
    for m in voice_chord("Asus4", None, 52, 72, 4):
        s.note("strings", s.bar(7), 2.0, m, 0.5)
    for m in voice_chord("A", None, 52, 72, 4):
        s.note("strings", s.bar(7) + 2, 2.0, m, 0.5)
    for m in (nm("D3"), nm("A3"), nm("D4"), nm("E4"), nm("F4"), nm("A4")):
        s.note("strings", s.bar(8), 6.0, m, 0.45)
    chords_track(s, "pad", prog, 0, low=48, high=70, n_voices=4, vel=0.6)
    s.melody("horn", 0, "D4:2 A4:2 | Bb4:1 A4:1 F4:2 | G4:1.5 A4:.5 Bb4:1 D5:1 | C#5:3 A4:1 | D5:2 A4:2 | "
                        "G4:1 F4:1 D4:2 | E4:2 G4:1 F4:1 | E4:2 C#4:2 | D4:6", vel=0.68)
    for i, sym in enumerate(prog):
        _, _, bpc = parse_chord(sym)
        root = 36 + bpc if bpc < 8 else 24 + bpc
        s.note("piano", s.bar(i), 3.5, root, 0.5)
        s.note("piano", s.bar(i) + 2, 1.5, root + 12, 0.32)
        s.note("sub", s.bar(i), 4.0, root - 12, 0.7)
    # a few high piano tears
    for b, n in ((1, "D6"), (3, "E6"), (5, "D6"), (7, "C#6")):
        s.note("piano", s.bar(b) + 3, 1.0, nm(n), 0.3)
    fill(s, "timp", "timpani", s.bar(7) + 2, 8, 0.25, 0.1, 0.35, tone=55.0)
    s.hit("timp", s.bar(8), "timpani", 0.45, tone=73.4)
    return s


# =============================================================================================
# 7) ENEMY SYSTEM – C phrygian / tritones, 70 BPM, 14 bars (48 s) – alien, dark
# =============================================================================================
def enemy_system_theme():
    s = Song("enemy_system_theme", bpm=70, bars=14, tail=12.0, seed=71, delay_beats=1.0, delay_fb=0.5,
             target_lufs=-15.0)
    per_bar = ["Cm", "Cm", "Db/C", "Db/C", "Cm", "Cm", "Gb/C", "Gb/C", "Abm/C", "Abm/C", "Gbmaj7/C",
               "Gbmaj7/C", "Cm", "Db/C"]
    s.add("drone", "synth", voice=ins.v_drone, gain_db=-12, sends={"space": 0.3}, hp=40)
    s.eq_lowmid, s.eq_presence, s.eq_air = -3.0, 2.0, 3.0
    s.add("sub", "synth", voice=ins.v_sub, gain_db=-16)
    s.add("glass", "synth", voice=ins.v_glass, gain_db=-9, sends={"space": 0.5, "delay": 0.25}, hp=200)
    s.add("choir", "fluid", program=53, gain_db=-13, sends={"space": 0.5}, hp=150)
    s.add("horn", "fluid", program=60, gain_db=-12, sends={"space": 0.55}, channel=1)
    s.add("trem", "fluid", program=44, gain_db=-17, sends={"hall": 0.4}, channel=2)
    s.add("metal", "drum", gain_db=-10, sends={"space": 0.5, "delay": 0.3})
    s.add("kick", "drum", gain_db=-10, sends={"hall": 0.3})
    s.add("fx", "audio", gain_db=-16, sends={"space": 0.4})

    s.note("drone", 0, s.total_beats - 1, nm("C2"), 0.9)
    s.note("drone", 0, s.total_beats - 1, nm("G2"), 0.5)
    for b in range(0, 14, 2):
        s.note("sub", s.bar(b), 8, nm("C1"), 0.8)
    chords_merged(s, "glass", per_bar, 0, low=60, high=82, n_voices=4, vel=0.6)
    chords_merged(s, "choir", per_bar[4:], 4, low=55, high=74, n_voices=3, vel=0.55)
    s.melody("horn", s.bar(6), "C4:1 F#4:3 | G4:.5 F#4:.5 Eb4:1 C4:2 | Db4:1 G4:3 | Ab4:.5 G4:.5 F4:1 Db4:2", vel=0.6)
    for b in range(4, 14):
        s.note("trem", s.bar(b), 4, nm("C3") + (1 if b % 4 >= 2 else 0), 0.5)
    # irregular metallic hits (deterministic "random")
    rr = np.random.default_rng(7)
    beats = sorted(set(np.round(rr.uniform(4, s.total_beats - 2, 18) * 2) / 2))
    for bt in beats:
        s.hit("metal", bt, "metal", float(rr.uniform(0.35, 0.9)), pan=float(rr.uniform(-0.7, 0.7)),
              variant=int(rr.integers(0, 6)))
    drum_pattern(s, "kick", "kick", "X..x............", 2, 12, tone=38, punch=0.35, decay=0.6)
    for b in (4, 8, 12):
        s.clip("fx", s.bar(b) - s.bpb, ins.fx_reverse_swell(s.bt(s.bpb), s.rng))
    return s


SONGS = {"title": title_theme, "map": map_theme, "combat_space": combat_space, "combat_planet": combat_planet,
         "docking": docking_theme, "gameover": gameover_theme, "enemy": enemy_system_theme}


def main(which):
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(DEBUG, exist_ok=True)
    for key in which or SONGS:
        t0 = time.time()
        song = SONGS[key]()
        path = os.path.join(OUT, song.name + ".ogg")
        out, stems = write_song(song, path, os.path.join(DEBUG, song.name + ".wav"))
        from synthlib import lufs, true_peak, loop_seam
        info = f"{song.name:22s} {out.shape[0] / 44100:6.1f}s  LUFS={lufs(out):6.1f}  TP={true_peak(out):5.1f}"
        if song.loop:
            ls = loop_seam(out)
            info += f"  seam_jump={ls['jump']:.4f} typ={ls['typ_step']:.4f}"
        print(info, f"({time.time() - t0:.0f}s)", flush=True)
        if os.environ.get("STEMS"):
            from synthlib import mono
            rep = []
            for nme, b in stems.items():
                mm = mono(b)
                w = 4410
                k = mm.shape[0] // w
                r = np.sqrt(np.mean(mm[:k * w].reshape(k, w) ** 2, axis=1))
                act = r[r > r.max() * 0.01]
                rep.append((nme, 20 * np.log10(np.percentile(act, 90) + 1e-9)))
            print("   stems:", "  ".join(f"{a}={b:.0f}" for a, b in sorted(rep, key=lambda z: -z[1])))


if __name__ == "__main__":
    main(sys.argv[1:])
