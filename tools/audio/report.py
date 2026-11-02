"""report.py – writes tools/AUDIO_REPORT.md (inventory + measurements of all audio assets)"""
import glob
import os

import numpy as np
import soundfile as sf

from synthlib import loop_seam, lufs, short_term_max, to_db, true_peak

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SFX = os.path.join(ROOT, "assets", "audio", "sfx")
MUS = os.path.join(ROOT, "assets", "audio", "music")

LOOPS = {"alarm_station", "bombard_loop", "flagship_charge_loop", "engine_loop", "title_theme", "map_theme",
         "combat_space", "combat_planet", "docking_theme", "enemy_system_theme"}

DESC = {
    "laser_1": "Bordlaser, Variante 1 (scharfer Pitch-Sweep, Square+FM)",
    "laser_2": "Bordlaser, Variante 2 (heller, kürzer)",
    "laser_3": "Bordlaser, Variante 3 (tiefer, mehr 'Zap')",
    "ion_fire": "Ionen-Kanone: Sub-Wumms + Supersaw-Entladung + elektrisches Sirren",
    "ion_ready": "Ionen-Kanone nachgeladen (dezenter Zweiklang)",
    "shield_hit": "Treffer auf Zerstörer-Schild (FM-Metall + Knistern)",
    "shield_break": "Schildschicht bricht (Glas-Splitter + Power-Down)",
    "laser_deflect": "Laser prallt wirkungslos ab (Ping)",
    "explosion_small_1": "Fighter-Explosion 1", "explosion_small_2": "Fighter-Explosion 2 (dunkler)",
    "explosion_small_3": "Fighter-Explosion 3 (heller)",
    "explosion_large_1": "Zerstörer-Explosion 1 (3 Detonationen, Trümmer, Grollen)",
    "explosion_large_2": "Zerstörer-Explosion 2 (4 Detonationen)",
    "explosion_huge": "Flaggschiff-Explosion (Kettenexplosion, Stereo, lange Rumpel-Fahne)",
    "player_hit_light": "Spieler von Fighter getroffen (Knistern + dumpfer Schlag)",
    "player_hit_heavy": "Schwerer Treffer (Krachen, Metallstress, Funken)",
    "enemy_shot_fighter": "Feindlicher Fighter-Schuss (ringmoduliert, 'fies')",
    "enemy_shot_destroyer": "Zerstörer-Torpedo (Aufladen + Abschuss)",
    "flagship_charge_loop": "Flaggschiff lädt (pulsierend; im Spiel pitch_scale hochziehen)",
    "flagship_fire": "Flaggschiff-Schuss (gewaltig, Stereo)",
    "near_miss": "Projektil zischt vorbei (Doppler + Panorama L->R)",
    "incoming": "Warnton: Geschoss im Anflug (3 Pieptöne)",
    "alarm_station": "Alarm: Station wird angegriffen (Sirene, 2 Whoops pro Loop)",
    "warning_low_energy": "Warnung: niedrige Energie (Doppel-Piep, fallend)",
    "wave_incoming": "Neue Gegnerwelle (Brass-Stabs + Schlag)",
    "hyperjump": "Hyperraumsprung (Aufladen, Woosh, Abriss)",
    "hyperjump_arrive": "Ankunft aus dem Hyperraum (Boom + Schimmer)",
    "warp_in": "Feindschiff erscheint (Riss + Zap)",
    "dock_slide": "Station gleitet heran (Hydraulik, Servo, Rumpeln)",
    "dock_clamp": "Andockklammern (2x Klonk + Druckausgleich)",
    "refuel_tick": "Tank-Schritt +5 %",
    "refuel_complete": "Tank voll (E-Piano-Arpeggio + Fläche)",
    "city_destroyed": "Stadt zerstört (ferne Detonation, Einsturz, Grollen)",
    "bombard_loop": "Bombardement-Strahl (Brummen + Knistern)",
    "ui_move": "UI: Cursor bewegen", "ui_select": "UI: Bestätigen", "ui_back": "UI: Zurück",
    "ui_error": "UI: Fehler / gesperrt", "ui_type": "UI: Tastendruck (Namenseingabe)",
    "map_open": "Karte öffnen (Sweep + digitale Chirps)", "map_close": "Karte schließen",
    "target_lock": "Ziel im Visier (leiser Doppel-Tick)",
    "squadron_destroyed": "Jingle: Schwadron vernichtet (Motiv-Quinte -> D-Dur)",
    "planet_saved": "Jingle: Planet gerettet (Motiv + bVI-bVII-I-Kadenz, Pauken)",
    "engine_loop": "Cockpit-Ambience: Triebwerksbrummen (Stereo)",
    "title_theme": "Titelthema, D-Moll, 96 BPM, heroisch synth-orchestral (Intro-A-B-Bridge-Klimax-Outro)",
    "map_theme": "Systemkarte, A-Moll, 80 BPM, ruhig-angespannt (Flächen, Glas-Arpeggio, Sonar, Horn-Motiv)",
    "combat_space": "Weltraumkampf, E-Moll, 136 BPM, treibend (16tel-Bass, Brass-Thema, Break, Klimax)",
    "combat_planet": "Planetenkampf, F-Moll, 142 BPM, dunkler/dringlicher (Reese-Bass, Taikos, Phrygische Stabs)",
    "docking_theme": "Andocken/Tanken, D-Dur, 84 BPM, warm (E-Piano, Glocken-Motiv in Dur)",
    "gameover_theme": "Game Over, D-Moll, 60 BPM, Horn-Motiv langsam in Moll, endet sauber (kein Loop)",
    "enemy_system_theme": "Feindsystem (Platzhalter), C-phrygisch/Tritonus, 70 BPM, fremdartig-düster",
}

# recommended in-game volume_db (relative, on top of bus volumes)
VOL = {"laser_1": -3, "laser_2": -3, "laser_3": -3, "engine_loop": -6, "alarm_station": -3, "bombard_loop": -2,
       "flagship_charge_loop": 0, "near_miss": -2, "target_lock": -2, "refuel_tick": 0}

# added later: bomb weapon, enemy home world, long hyperjump, victory / debrief music
LOOPS |= {"victory_theme", "debrief_theme"}
DESC.update({
    "bomb_release": "Bombe ausklinken (Haken-Klick + Rack-Klonk + pneumatisches Zischen)",
    "bomb_fall": "Fallende Bombe (absteigendes Pfeifen, leicht Sci-Fi; verklungen bei ~1.4 s, Einschlag ~1.3 s)",
    "bomb_impact": "Bombeneinschlag (harter Knall, tiefer Schlag, Erd-/Trümmerregen, rollendes Grollen + Geländeechos)",
    "alien_city_destroyed": "Feindstadt zerstört (Detonation, Kristall-Splittern, subharmonisches Ächzen, Glitzern; Stereo)",
    "weapon_bombs": "Waffe auf Bomben (Servo-Surren + Verriegelungsklick)",
    "weapon_laser": "Waffe auf Laser (kurzes Energie-Aufsirren)",
    "bomb_empty": "Keine Bomben mehr (trockener Klick + kurzes Brummen)",
    "hyperjump_long": "Langer Sprung (düsterer, rotverschobener Aufbau; Knall/Woosh exakt bei 3.75 s = Weißblitz; Stereo)",
    "hyperjump_arrive_long": "Ankunft nach langem Sprung (tiefer Boom + Braam, Woosh L->R, nachklingende Hülle; Stereo)",
    "victory_theme": "Sieg, D-Dur, 100 BPM, heroisch-orchestral (Motiv als Fanfare, Marsch, Streicher-B-Teil, "
                     "Tutti-Klimax mit bVI-bVII-I, Coda)",
    "debrief_theme": "Einsatzauswertung (abgebrochen), H-Moll, 72 BPM, ruhig-nachdenklich (Titelthema verlangsamt, "
                     "E-Piano, Streicher-B-Teil in D-Dur)",
})


def row(path, is_music):
    x, sr = sf.read(path)
    name = os.path.splitext(os.path.basename(path))[0]
    ch = 1 if x.ndim == 1 else x.shape[1]
    dur = x.shape[0] / sr
    pk = to_db(np.max(np.abs(x)))
    tp = true_peak(x)
    lu = lufs(x)
    st = short_term_max(x)
    loop = name in LOOPS
    seam = ""
    if loop:
        s = loop_seam(x)
        steps = np.abs(np.diff(x if x.ndim == 2 else x[:, None], axis=0)).max(axis=1)
        pct = 100 * (steps < s["jump"]).mean()
        seam = f"ja (Naht-Sprung im {pct:.0f}. Perzentil der Sample-Schritte)"
    else:
        seam = "nein"
    vol = VOL.get(name, 0)
    return (f"| `{os.path.relpath(path, ROOT)}` | {dur:.2f} s | {ch} | {sr} | {pk:.1f} / {tp:.1f} | "
            f"{lu:.1f} | {st:.1f} | {seam} | {vol if not is_music else '–'} | {DESC.get(name, '')} |")


def main():
    lines = ["# Audio-Report – Starfighter Defense", "",
             "Alle Klänge und Musikstücke sind vollständig selbst synthetisiert/komponiert (Code in `tools/audio/`).",
             "Einzige externe Klangquelle: der MIT-lizenzierte General-MIDI-Soundfont *FluidR3_GM* (via fluidsynth) "
             "für Orchester-Ebenen (Streicher, Celli, Chor, Hörner, Klavier, Tremolo-Streicher) in der Musik.", "",
             "Reproduzieren: `cd tools/audio && /opt/tools/audiovenv/bin/python sfx.py && "
             "/opt/tools/audiovenv/bin/python songs.py && /opt/tools/audiovenv/bin/python report.py`", "",
             "Spalten: Peak = Sample-Peak / True-Peak (dBFS), LUFS = integriert (BS.1770), ST-max = max. 400-ms-RMS "
             "(dBFS, Maß für die Lautheitshierarchie der kurzen SFX), Vol = empfohlenes `volume_db` im Spiel.", "",
             "## Soundeffekte (`assets/audio/sfx/`, WAV 44.1 kHz / 16 bit)", "",
             "| Datei | Dauer | Kanäle | Rate | Peak / TP | LUFS | ST-max | Loop | Vol | Beschreibung |",
             "|---|---|---|---|---|---|---|---|---|---|"]
    for p in sorted(glob.glob(os.path.join(SFX, "*.wav"))):
        lines.append(row(p, False))
    lines += ["", "## Musik (`assets/audio/music/`, Ogg Vorbis q6, 44.1 kHz Stereo)", "",
              "| Datei | Dauer | Kanäle | Rate | Peak / TP | LUFS | ST-max | Loop | Vol | Beschreibung |",
              "|---|---|---|---|---|---|---|---|---|---|"]
    for p in sorted(glob.glob(os.path.join(MUS, "*.ogg"))):
        lines.append(row(p, True))
    lines += ["", "## Integrationshinweise", "",
              "- **Loops**: `alarm_station`, `bombard_loop`, `flagship_charge_loop`, `engine_loop` (WAV) sowie alle "
              "Musikstücke außer `gameover_theme` sind exakt auf Loop-Länge geschnitten. In Godot: WAV -> "
              "`AudioStreamWAV.loop_mode = LOOP_FORWARD`, `loop_begin = 0`, `loop_end = Sampleanzahl` "
              "(oder Import-Option *Loop Mode: Forward*); OGG -> `AudioStreamOggVorbis.loop = true`.",
              "- **Lautheit**: SFX sind untereinander abgestimmt (UI leise, Explosionen kräftig). Musik ist auf ca. "
              "-14 LUFS (Kampf/Titel) bzw. -15/-16 LUFS (Karte, Docking, Feindsystem, Game Over) gemastert -> "
              "Musik-Bus im Spiel ca. -6 dB unter dem SFX-Bus fahren.",
              "- **Laser** werden schnell hintereinander gefeuert: Varianten zufällig wechseln, `volume_db` ca. -3, "
              "evtl. `pitch_scale` 0.97–1.03 randomisieren.",
              "- **flagship_charge_loop**: während der Aufladephase `pitch_scale` von ~0.8 auf ~1.6 hochziehen "
              "und Lautstärke mitfahren; beim Schuss stoppen und `flagship_fire` spielen.",
              "- **engine_loop** dauerhaft im Cockpit (leise), **bombard_loop** als 3D-Quelle am Zerstörer "
              "(AudioStreamPlayer3D) während des Bombardements.",
              "- **gameover_theme** endet sauber (Fade am Ende), nicht loopen.",
              "- `combat_space`/`combat_planet` beginnen mit einem 4-taktigen Intro und enden mit einem Turnaround, "
              "der nahtlos ins Intro zurückführt; Crossfades beim Zustandswechsel ~1 s.",
              "- **hyperjump_long** beim Start des langen Sprungs (3x `jump_duration`) spielen: Knall/Woosh exakt bei "
              "3.75 s (Weißblitz/Szenenwechsel), danach kurzes Ausklingen bis 4.6 s. `hyperjump_arrive_long` beim "
              "Szenenwechsel (~3.75 s) starten – beide sind aufeinander abgestimmt (Aufbau/Riss bzw. tiefer Boom).",
              "- **bomb_release** und **bomb_fall** gleichzeitig beim Abwurf; `bomb_fall` ist bei ~1.4 s verklungen, "
              "`bomb_impact` beim Einschlag (~1.3 s) spielen. `weapon_bombs`/`weapon_laser` beim Waffenwechsel, "
              "`bomb_empty` bei Abwurfversuch ohne Bomben.",
              "- **victory_theme** (-14 LUFS) und **debrief_theme** (-15 LUFS wie die anderen ruhigen Stücke) sind "
              "nahtlose Loops.", ""]
    out = os.path.join(ROOT, "tools", "AUDIO_REPORT.md")
    open(out, "w").write("\n".join(lines))
    print("written", out)


if __name__ == "__main__":
    main()
