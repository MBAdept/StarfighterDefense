"""
musiclib.py – tiny code-based "DAW" used to compose and render the soundtrack.

* music theory helpers (note names, chord symbols, voice leading, diatonic harmonisation)
* Song: tracks of notes / drum hits / audio clips on a beat grid
* track types: 'synth' (python voices), 'drum', 'fluid' (FluidR3_GM via fluidsynth CLI), 'audio'
* mixing: per-stem level normalisation + gain/pan, sends to synthetic reverbs and a ping-pong
  delay, kick-keyed sidechain ducking
* mastering: glue compression, limiter, loudness normalisation to -14 LUFS, true-peak <= -1 dBTP
* seamless loops: render with tail, fold the tail onto the loop start, master the tiled loop and cut
  the steady-state middle copy
"""
from __future__ import annotations

import os
import subprocess
import tempfile

import mido
import numpy as np
import soundfile as sf

from synthlib import (SR, butter, compress, db, fold_tail, limit, lufs, mix_into, mono, ns, pad_to, pan,
                      pingpong_delay, reverb, stereo, to_db, true_peak, midi_to_hz)
import instruments as ins

SF2 = "/usr/share/sounds/sf2/FluidR3_GM.sf2"

# ---------------------------------------------------------------------------------------------
# theory
# ---------------------------------------------------------------------------------------------
_NB = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def nm(name: str) -> int:
    """'C#4' -> 61, 'Bb2' -> 46"""
    letter = name[0].upper()
    i, acc = 1, 0
    while i < len(name) and name[i] in "#b":
        acc += 1 if name[i] == "#" else -1
        i += 1
    return 12 * (int(name[i:]) + 1) + _NB[letter] + acc


def pc(name: str) -> int:
    letter = name[0].upper()
    acc = sum(1 if c == "#" else -1 for c in name[1:3] if c in "#b")
    return (_NB[letter] + acc) % 12


_QUAL = {
    "": [0, 4, 7], "m": [0, 3, 7], "5": [0, 7], "7": [0, 4, 7, 10], "m7": [0, 3, 7, 10], "maj7": [0, 4, 7, 11],
    "m9": [0, 3, 7, 10, 14], "maj9": [0, 4, 7, 11, 14], "add9": [0, 4, 7, 14], "madd9": [0, 3, 7, 14],
    "sus2": [0, 2, 7], "sus4": [0, 5, 7], "7sus4": [0, 5, 7, 10], "dim": [0, 3, 6], "aug": [0, 4, 8],
    "6": [0, 4, 7, 9], "m6": [0, 3, 7, 9], "9": [0, 4, 7, 10, 14], "maj7#11": [0, 4, 7, 11, 18],
    "m7b5": [0, 3, 6, 10], "mmaj7": [0, 3, 7, 11], "m11": [0, 3, 7, 10, 14, 17], "7b9": [0, 4, 7, 10, 13],
    "madd2": [0, 2, 3, 7], "b2": [0, 1, 7],
}


def parse_chord(sym: str):
    """returns (root_pc, intervals, bass_pc)"""
    bass = None
    if "/" in sym:
        sym, b = sym.split("/")
        bass = pc(b)
    root_len = 2 if len(sym) > 1 and sym[1] in "#b" else 1
    root = pc(sym[:root_len])
    q = sym[root_len:]
    if q not in _QUAL:
        raise ValueError(f"unknown chord quality {q!r} in {sym}")
    return root, _QUAL[q], (bass if bass is not None else root)


def chord_pcs(sym):
    r, iv, _ = parse_chord(sym)
    return sorted({(r + i) % 12 for i in iv})


def voice_chord(sym, prev=None, low=55, high=79, n_voices=4):
    """choose an upper-structure voicing (n_voices notes) inside [low, high] with minimal movement"""
    r, iv, _ = parse_chord(sym)
    tones = [(r + i) for i in iv]
    # candidate pool: all chord tones in range
    pool = sorted({m for m in range(low, high + 1) if (m % 12) in {t % 12 for t in tones}})
    best, best_cost = None, 1e9
    import itertools
    k = min(n_voices, len(pool))
    # enumerate windows of consecutive pool notes (close/semi-open voicings)
    for start in range(len(pool)):
        for span in (k, k + 1, k + 2):
            cand_full = pool[start:start + span]
            if len(cand_full) < k:
                continue
            for cand in itertools.combinations(cand_full, k):
                pcs_c = {m % 12 for m in cand}
                need = {(r + i) % 12 for i in iv[:3]} if len(iv) >= 3 else {(r + i) % 12 for i in iv}
                # must contain 3rd (or sus) and at least most chord tones
                if len(pcs_c & need) < min(len(need), k) - (1 if len(need) > k else 0):
                    continue
                if max(cand) - min(cand) > 16:
                    continue
                if prev:
                    cost = sum(min(abs(a - b) for b in prev) for a in cand) + 0.3 * abs(np.mean(cand) - np.mean(prev))
                else:
                    cost = abs(np.mean(cand) - (low + high) / 2)
                if cost < best_cost:
                    best, best_cost = list(cand), cost
    return best or pool[:k]


def scale_pcs(root_name, mode="minor"):
    modes = {"minor": [0, 2, 3, 5, 7, 8, 10], "major": [0, 2, 4, 5, 7, 9, 11], "harm": [0, 2, 3, 5, 7, 8, 11],
             "dorian": [0, 2, 3, 5, 7, 9, 10], "phrygian": [0, 1, 3, 5, 7, 8, 10]}
    r = pc(root_name)
    return [(r + i) % 12 for i in modes[mode]]


def diatonic(m, steps, scale):
    """move midi note m by 'steps' scale degrees (negative = down) within scale (list of pcs)"""
    # snap to scale first
    cand = m
    while cand % 12 not in scale:
        cand -= 1
    k = 0
    d = 1 if steps > 0 else -1
    x = cand
    while k < abs(steps):
        x += d
        if x % 12 in scale:
            k += 1
    return x


def mel(s: str, transpose: int = 0):
    """'D4:1 A4:3 | r:2 ...'  -> [(offset_beats, dur_beats, midi or None, accent)]"""
    out, pos = [], 0.0
    for tok in s.replace("|", " ").split():
        acc = tok.endswith(">")
        tok = tok.rstrip(">")
        name, d = tok.split(":")
        d = float(d)
        out.append((pos, d, None if name == "r" else nm(name) + transpose, acc))
        pos += d
    return out


# ---------------------------------------------------------------------------------------------
# song container
# ---------------------------------------------------------------------------------------------
class Track:
    def __init__(self, name, kind, voice=None, program=None, gain_db=0.0, pan_=0.0, sends=None, sidechain=0.0,
                 humanize=0.0, voice_kw=None, insert=None, norm=True, channel=0, hp=None):
        self.name, self.kind, self.voice, self.program = name, kind, voice, program
        self.gain_db, self.pan, self.sends = gain_db, pan_, (sends or {})
        self.sidechain, self.humanize = sidechain, humanize
        self.voice_kw = voice_kw or {}
        self.insert = insert
        self.norm = norm
        self.channel = channel
        self.hp = hp
        self.events = []  # (beat, dur_beats, midi/kind, vel, kw)


class Song:
    def __init__(self, name, bpm, bars, beats_per_bar=4, tail=7.0, loop=True, seed=1, delay_beats=0.75,
                 delay_fb=0.38, target_lufs=-14.0):
        self.name, self.bpm, self.bars, self.bpb = name, bpm, bars, beats_per_bar
        self.spb = 60.0 / bpm
        self.tail, self.loop = tail, loop
        self.rng = np.random.default_rng(seed)
        self.tracks: dict[str, Track] = {}
        self.delay_beats, self.delay_fb = delay_beats, delay_fb
        self.target_lufs = target_lufs
        self.kick_track = "kick"
        self.automation = {}  # track -> list of (beat, gain_db) points
        self.master_env = None  # [(beat, dB)] section dynamics before mastering
        self.eq_lowmid, self.eq_presence, self.eq_air = -2.0, 1.5, 2.5

    # --- timeline -------------------------------------------------------------------------
    @property
    def total_beats(self):
        return self.bars * self.bpb

    @property
    def loop_samples(self):
        return int(round(self.total_beats * self.spb * SR))

    def bt(self, beat):
        return beat * self.spb

    def bar(self, b):
        return b * self.bpb

    # --- tracks ---------------------------------------------------------------------------
    def add(self, name, kind, **kw):
        self.tracks[name] = Track(name, kind, **kw)
        return self.tracks[name]

    def note(self, track, beat, dur, midi, vel=0.8, **kw):
        self.tracks[track].events.append((beat, dur, midi, vel, kw))

    def hit(self, track, beat, kind, vel=0.8, **kw):
        self.tracks[track].events.append((beat, 0, kind, vel, kw))

    def clip(self, track, beat, audio):
        self.tracks[track].events.append((beat, 0, audio, 1.0, {}))

    def melody(self, track, start_beat, s, vel=0.85, transpose=0, legato=1.0, accent_vel=1.0):
        for off, d, m, acc in mel(s, transpose):
            if m is None:
                continue
            self.note(track, start_beat + off, d * legato, m, accent_vel if acc else vel)

    def automate(self, track, points):
        """points: [(beat, gain_db), ...] linear in dB"""
        self.automation[track] = points

    # --- rendering ------------------------------------------------------------------------
    def _render_synth(self, tr: Track, n_total):
        buf = np.zeros((n_total, 2))
        for beat, dur, m, vel, kw in tr.events:
            t0 = self.bt(beat)
            if tr.humanize:
                t0 += self.rng.uniform(-tr.humanize, tr.humanize)
            f = midi_to_hz(m)
            args = dict(tr.voice_kw)
            args.update(kw)
            a = tr.voice(f, max(0.02, self.bt(dur)), vel, self.rng, **args)
            mix_into(buf, stereo(a) if a.ndim == 2 else pan(a, 0), ns(max(0.0, t0)))
        return buf

    def _render_drum(self, tr: Track, n_total):
        buf = np.zeros((n_total, 2))
        for beat, _, kind, vel, kw in tr.events:
            t0 = self.bt(beat)
            if tr.humanize:
                t0 += self.rng.uniform(-tr.humanize, tr.humanize)
            a = ins.drum(kind, vel, self.rng, **{k: v for k, v in kw.items() if k != "pan"})
            p = kw.get("pan", 0.0)
            a = stereo(a) if a.ndim == 2 else pan(a, p)
            mix_into(buf, a, ns(max(0.0, t0)))
        return buf

    def _render_audio(self, tr: Track, n_total):
        buf = np.zeros((n_total, 2))
        for beat, _, audio, vel, kw in tr.events:
            mix_into(buf, stereo(audio) * vel, ns(self.bt(beat)))
        return buf

    def _render_fluid(self, tr: Track, n_total):
        tpb = 960
        mid = mido.MidiFile(ticks_per_beat=tpb)
        mt = mido.MidiTrack()
        mid.tracks.append(mt)
        tempo = mido.bpm2tempo(self.bpm)
        mt.append(mido.MetaMessage("set_tempo", tempo=tempo, time=0))
        ch = tr.channel
        mt.append(mido.Message("program_change", program=tr.program, channel=ch, time=0))
        mt.append(mido.Message("control_change", control=7, value=110, channel=ch, time=0))
        mt.append(mido.Message("control_change", control=91, value=0, channel=ch, time=0))
        mt.append(mido.Message("control_change", control=93, value=0, channel=ch, time=0))
        evs = []
        # avoid same-pitch overlaps (note-off of the first would cut the second)
        notes = sorted([(b, d, m, v, kw) for b, d, m, v, kw in tr.events], key=lambda e: (e[0], e[2]))
        last_end = {}
        for b, d, m, v, kw in notes:
            if tr.humanize:
                b = b + self.rng.uniform(-tr.humanize, tr.humanize) / self.spb
            b = max(0.0, b)
            end = b + d
            if m in last_end and last_end[m][0] > b:
                # shorten previous
                prev = last_end[m][1]
                prev[1] = max(b - 0.02, prev[0] + 0.02)
            rec = [b, end, m, v]
            last_end[m] = (end, rec)
            evs.append(rec)
        msgs = []
        for b, e, m, v in evs:
            vel = int(np.clip(round(v * 127), 1, 127))
            msgs.append((int(round(b * tpb)), 1, mido.Message("note_on", note=int(m), velocity=vel, channel=ch)))
            msgs.append((int(round(e * tpb)), 0, mido.Message("note_off", note=int(m), velocity=0, channel=ch)))
        # CC11 expression automation if provided via kw 'expr' events
        msgs.sort(key=lambda x: (x[0], x[1]))
        cur = 0
        for tick, _, msg in msgs:
            msg.time = tick - cur
            cur = tick
            mt.append(msg)
        with tempfile.TemporaryDirectory() as td:
            mp = os.path.join(td, "t.mid")
            wp = os.path.join(td, "t.wav")
            mid.save(mp)
            subprocess.run(["fluidsynth", "-ni", "-q", "-g", "0.5", "-r", str(SR), "-R", "0", "-C", "0",
                            "-O", "float", "-T", "wav", "-F", wp, SF2, mp], check=True,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            a, sr = sf.read(wp)
        assert sr == SR
        buf = np.zeros((n_total, 2))
        mix_into(buf, stereo(a), 0)
        return buf

    def render_stems(self):
        n_total = self.loop_samples + ns(self.tail)
        stems = {}
        for name, tr in self.tracks.items():
            if not tr.events:
                continue
            if tr.kind == "synth":
                b = self._render_synth(tr, n_total)
            elif tr.kind == "drum":
                b = self._render_drum(tr, n_total)
            elif tr.kind == "audio":
                b = self._render_audio(tr, n_total)
            elif tr.kind == "fluid":
                b = self._render_fluid(tr, n_total)
            else:
                raise ValueError(tr.kind)
            if tr.hp:
                b = butter(b, "hp", tr.hp, 2)
            if tr.insert:
                b = tr.insert(b)
                b = pad_to(b, n_total)
            if tr.norm:
                b = normalize_stem(b)
            b = b * db(tr.gain_db)
            if tr.pan and tr.kind != "drum":
                b = balance(b, tr.pan)
            if name in self.automation:
                b = b * self._auto_env(self.automation[name], n_total)[:, None]
            stems[name] = b
        return stems

    def _auto_env(self, points, n):
        t = np.arange(n) / SR
        bts = np.array([self.bt(p[0]) for p in points])
        g = np.array([p[1] for p in points])
        return 10 ** (np.interp(t, bts, g) / 20)

    def kick_times(self):
        tr = self.tracks.get(self.kick_track)
        if not tr:
            return []
        return [self.bt(e[0]) for e in tr.events]

    def mix(self, stems):
        n_total = self.loop_samples + ns(self.tail)
        dry = np.zeros((n_total, 2))
        sends = {}
        from synthlib import sidechain_env
        duck = sidechain_env(n_total, self.kick_times(), depth=1.0, attack=0.003, release=self.spb * 0.38)
        for name, b in stems.items():
            tr = self.tracks[name]
            if tr.sidechain > 0:
                g = 1.0 - tr.sidechain * (1.0 - duck)
                b = b * g[:, None]
            dry += b
            for bus, amt in tr.sends.items():
                sends.setdefault(bus, np.zeros((n_total, 2)))
                sends[bus] += b * amt
        out = dry
        for bus, sig in sends.items():
            if bus == "delay":
                wet = pingpong_delay(sig, self.bt(self.delay_beats), self.delay_fb, 3800.0)
                wet = butter(wet, "hp", 250, 2)
                wet = reverb(wet, "plate", 0.25, dry=1.0, tail=False)
            else:
                wet = reverb(sig, bus, wet=1.0, dry=0.0, tail=False)
            out = out + pad_to(wet, n_total)
        return out

    def master(self, mixbuf):
        L = self.loop_samples
        if self.master_env:
            t = np.arange(mixbuf.shape[0]) / SR
            bts = np.array([self.bt(p[0]) for p in self.master_env])
            g = 10 ** (np.interp(t, bts, np.array([p[1] for p in self.master_env])) / 20)
            mixbuf = mixbuf * g[:, None]
        if self.loop:
            folded = fold_tail(mixbuf, L)
            reps = 3
            x = np.concatenate([folded] * reps)
        else:
            x = mixbuf.copy()
        import pedalboard as pb
        from synthlib import pb_process
        x = pb_process(x, [pb.HighpassFilter(28.0),
                           pb.PeakFilter(cutoff_frequency_hz=320.0, gain_db=self.eq_lowmid, q=0.8),
                           pb.PeakFilter(cutoff_frequency_hz=3000.0, gain_db=self.eq_presence, q=0.9),
                           pb.HighShelfFilter(cutoff_frequency_hz=7000.0, gain_db=self.eq_air, q=0.7)])
        # bring the mix to a defined level before the glue compressor
        mid0 = x[L:2 * L] if self.loop else x
        x = x * db(-18.0 - lufs(mid0))
        x = compress(x, threshold_db=-21, ratio=1.7, attack_ms=30, release_ms=200)
        # loudness: measure on the (steady-state) middle part
        mid = x[L:2 * L] if self.loop else x
        cur = lufs(mid)
        x = x * db(self.target_lufs + 0.6 - cur)
        x = limit(x, -1.6, 90)
        out = x[L:2 * L] if self.loop else x
        # final trim: loudness + true peak
        cur = lufs(out)
        g = db(self.target_lufs - cur)
        out = out * g
        tp = true_peak(out)
        if tp > -1.0:
            out = out * db(-1.0 - tp - 0.05)
        return out


def normalize_stem(b, target_db=-18.0):
    m = mono(b)
    w = ns(0.1)
    k = m.shape[0] // w
    if k == 0:
        return b
    rms = np.sqrt(np.mean(m[: k * w].reshape(k, w) ** 2, axis=1))
    active = rms[rms > rms.max() * db(-40)]
    if active.size == 0:
        return b
    level = np.percentile(active, 90)
    return b * (db(target_db) / max(level, 1e-9))


def balance(b, p):
    """pan a stereo stem (balance law)"""
    out = b.copy()
    if p > 0:
        out[:, 0] *= 1 - p
    else:
        out[:, 1] *= 1 + p
    return out


# ---------------------------------------------------------------------------------------------
# pattern helpers
# ---------------------------------------------------------------------------------------------
def chords_track(song, track, chords, start_bar=0, beats_per_chord=4, low=55, high=77, n_voices=4, vel=0.7,
                 legato=1.02, rhythm=None, bass_note=False, bass_oct=3):
    """sustained chords with voice leading. rhythm: list of (offset, dur) within the chord span."""
    prev = None
    for i, sym in enumerate(chords):
        if sym is None:
            continue
        v = voice_chord(sym, prev, low, high, n_voices)
        prev = v
        b0 = song.bar(start_bar) + i * beats_per_chord
        pattern = rhythm or [(0, beats_per_chord * legato)]
        for off, d in pattern:
            for m in v:
                song.note(track, b0 + off, d, m, vel)
            if bass_note:
                r, _, bpc = parse_chord(sym)
                song.note(track, b0 + off, d, 12 * (bass_oct + 1) + bpc, vel)


def arp_track(song, track, chords, start_bar=0, beats_per_chord=4, rate=4, pattern="up", low=60, octaves=2,
              vel=0.6, gate=0.6, accent_every=4, skip=None):
    for i, sym in enumerate(chords):
        if sym is None:
            continue
        pcs = chord_pcs(sym)
        pool = [m for m in range(low, low + 12 * octaves + 1) if m % 12 in pcs]
        if pattern == "up":
            seq = pool
        elif pattern == "down":
            seq = pool[::-1]
        elif pattern == "updown":
            seq = pool + pool[-2:0:-1]
        elif pattern == "pulse":
            seq = [pool[0], pool[2 % len(pool)], pool[1 % len(pool)], pool[3 % len(pool)]]
        elif pattern == "skip":
            seq = [pool[k % len(pool)] for k in (0, 2, 4, 1, 3, 5, 2, 4)]
        else:
            seq = pool
        b0 = song.bar(start_bar) + i * beats_per_chord
        steps = int(beats_per_chord * rate)
        for s in range(steps):
            if skip and skip(s):
                continue
            m = seq[s % len(seq)]
            v = vel * (1.0 if s % accent_every == 0 else 0.78)
            song.note(track, b0 + s / rate, gate / rate, m, v)


def bass_track(song, track, chords, start_bar=0, beats_per_chord=4, style="eighths", octave=2, vel=0.8,
               gate=0.85):
    for i, sym in enumerate(chords):
        if sym is None:
            continue
        r, _, bpc = parse_chord(sym)
        root = 12 * (octave + 1) + bpc
        if bpc >= 8:  # keep bass roots between Ab1 and G2 (for octave=2)
            root -= 12
        b0 = song.bar(start_bar) + i * beats_per_chord
        fifth = root + 7
        if style == "whole":
            song.note(track, b0, beats_per_chord * gate, root, vel)
        elif style == "half":
            for k in range(int(beats_per_chord // 2)):
                song.note(track, b0 + 2 * k, 2 * gate, root if k % 2 == 0 else fifth, vel)
        elif style == "quarter":
            for k in range(int(beats_per_chord)):
                song.note(track, b0 + k, gate, root, vel * (1 if k % 2 == 0 else 0.85))
        elif style == "eighths":
            for k in range(int(beats_per_chord * 2)):
                song.note(track, b0 + k / 2, 0.5 * gate, root, vel * (1 if k % 2 == 0 else 0.8))
        elif style == "eighths_oct":
            for k in range(int(beats_per_chord * 2)):
                song.note(track, b0 + k / 2, 0.5 * gate, root + (12 if k % 2 else 0), vel * (1 if k % 2 == 0 else 0.85))
        elif style == "sixteenths":
            for k in range(int(beats_per_chord * 4)):
                m = root + (12 if k % 4 == 3 else 0)
                song.note(track, b0 + k / 4, 0.25 * gate, m, vel * (1 if k % 4 == 0 else 0.78))
        elif style == "gallop":
            for k in range(int(beats_per_chord)):
                song.note(track, b0 + k, 0.5 * gate, root, vel)
                song.note(track, b0 + k + 0.5, 0.25 * gate, root, vel * 0.8)
                song.note(track, b0 + k + 0.75, 0.25 * gate, root + (12 if k % 2 else 0), vel * 0.8)
        elif style == "offbeat":
            for k in range(int(beats_per_chord)):
                song.note(track, b0 + k + 0.5, 0.5 * gate, root, vel)
        elif style == "pedal16":
            for k in range(int(beats_per_chord * 4)):
                song.note(track, b0 + k / 4, 0.25 * gate, root, vel * (1 if k % 4 == 0 else 0.7))
        else:
            raise ValueError(style)


_VEL = {"X": 1.0, "x": 0.82, "o": 0.55, "g": 0.32, ".": 0.0}


def drum_pattern(song, track, kind, pattern, start_bar, bars=1, steps_per_bar=16, every=None, **kw):
    """pattern string per bar ('x...x...'), repeated for 'bars' bars"""
    pat = pattern.replace(" ", "")
    spb = len(pat) if len(pat) != steps_per_bar else steps_per_bar
    for b in range(bars):
        if every and (b % every[0]) not in every[1]:
            continue
        for s, ch in enumerate(pat):
            v = _VEL.get(ch, 0.0)
            if v > 0:
                song.hit(track, song.bar(start_bar + b) + s * song.bpb / spb, kind, v, **kw)


def fill(song, track, kind, start_beat, n, step=0.25, v0=0.4, v1=1.0, **kw):
    for k in range(n):
        song.hit(track, start_beat + k * step, kind, v0 + (v1 - v0) * k / max(1, n - 1), **kw)


def write_song(song: Song, path_ogg: str, debug_wav: str | None = None):
    from synthlib import write_ogg
    stems = song.render_stems()
    mixbuf = song.mix(stems)
    out = song.master(mixbuf)
    if not song.loop:
        # clean ending: fade the last 1.5 s
        f = ns(1.5)
        out[-f:] *= (np.cos(np.linspace(0, np.pi / 2, f)) ** 2)[:, None]
    write_ogg(path_ogg, out, 6)
    if debug_wav:
        sf.write(debug_wav, out.astype(np.float32), SR, subtype="FLOAT")
    return out, stems
