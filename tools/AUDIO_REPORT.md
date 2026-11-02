# Audio-Report – Starfighter Defense

Alle Klänge und Musikstücke sind vollständig selbst synthetisiert/komponiert (Code in `tools/audio/`).
Einzige externe Klangquelle: der MIT-lizenzierte General-MIDI-Soundfont *FluidR3_GM* (via fluidsynth) für Orchester-Ebenen (Streicher, Celli, Chor, Hörner, Klavier, Tremolo-Streicher) in der Musik.

Reproduzieren: `cd tools/audio && /opt/tools/audiovenv/bin/python sfx.py && /opt/tools/audiovenv/bin/python songs.py && /opt/tools/audiovenv/bin/python report.py`

Spalten: Peak = Sample-Peak / True-Peak (dBFS), LUFS = integriert (BS.1770), ST-max = max. 400-ms-RMS (dBFS, Maß für die Lautheitshierarchie der kurzen SFX), Vol = empfohlenes `volume_db` im Spiel.

## Soundeffekte (`assets/audio/sfx/`, WAV 44.1 kHz / 16 bit)

| Datei | Dauer | Kanäle | Rate | Peak / TP | LUFS | ST-max | Loop | Vol | Beschreibung |
|---|---|---|---|---|---|---|---|---|---|
| `assets/audio/sfx/alarm_station.wav` | 2.00 s | 1 | 44100 | -7.3 / -7.3 | -15.0 | -14.0 | ja (Naht-Sprung im 3. Perzentil der Sample-Schritte) | -3 | Alarm: Station wird angegriffen (Sirene, 2 Whoops pro Loop) |
| `assets/audio/sfx/alien_city_destroyed.wav` | 4.10 s | 2 | 44100 | -1.3 / -1.2 | -13.5 | -9.5 | nein | 0 | Feindstadt zerstört (Detonation, Kristall-Splittern, subharmonisches Ächzen, Glitzern; Stereo) |
| `assets/audio/sfx/bomb_empty.wav` | 0.25 s | 1 | 44100 | -8.1 / -8.1 | -22.2 | -19.5 | nein | 0 | Keine Bomben mehr (trockener Klick + kurzes Brummen) |
| `assets/audio/sfx/bomb_fall.wav` | 1.50 s | 1 | 44100 | -6.9 / -6.8 | -17.9 | -17.0 | nein | 0 | Fallende Bombe (absteigendes Pfeifen, leicht Sci-Fi; verklungen bei ~1.4 s, Einschlag ~1.3 s) |
| `assets/audio/sfx/bomb_impact.wav` | 3.10 s | 1 | 44100 | -2.4 / -1.9 | -20.2 | -9.5 | nein | 0 | Bombeneinschlag (harter Knall, tiefer Schlag, Erd-/Trümmerregen, rollendes Grollen + Geländeechos) |
| `assets/audio/sfx/bomb_release.wav` | 0.59 s | 1 | 44100 | -1.3 / -1.2 | -17.4 | -15.0 | nein | 0 | Bombe ausklinken (Haken-Klick + Rack-Klonk + pneumatisches Zischen) |
| `assets/audio/sfx/bombard_loop.wav` | 2.00 s | 1 | 44100 | -9.3 / -9.3 | -17.3 | -14.0 | ja (Naht-Sprung im 81. Perzentil der Sample-Schritte) | -2 | Bombardement-Strahl (Brummen + Knistern) |
| `assets/audio/sfx/city_destroyed.wav` | 3.50 s | 1 | 44100 | -4.7 / -4.7 | -21.1 | -12.0 | nein | 0 | Stadt zerstört (ferne Detonation, Einsturz, Grollen) |
| `assets/audio/sfx/dock_clamp.wav` | 1.15 s | 1 | 44100 | -3.3 / -3.3 | -19.0 | -13.0 | nein | 0 | Andockklammern (2x Klonk + Druckausgleich) |
| `assets/audio/sfx/dock_slide.wav` | 3.28 s | 1 | 44100 | -5.4 / -5.4 | -21.6 | -16.0 | nein | 0 | Station gleitet heran (Hydraulik, Servo, Rumpeln) |
| `assets/audio/sfx/enemy_shot_destroyer.wav` | 1.25 s | 1 | 44100 | -4.9 / -4.9 | -16.2 | -13.0 | nein | 0 | Zerstörer-Torpedo (Aufladen + Abschuss) |
| `assets/audio/sfx/enemy_shot_fighter.wav` | 0.42 s | 1 | 44100 | -3.2 / -3.2 | -15.2 | -17.0 | nein | 0 | Feindlicher Fighter-Schuss (ringmoduliert, 'fies') |
| `assets/audio/sfx/engine_loop.wav` | 4.00 s | 2 | 44100 | -13.7 / -13.7 | -27.3 | -24.0 | ja (Naht-Sprung im 71. Perzentil der Sample-Schritte) | -6 | Cockpit-Ambience: Triebwerksbrummen (Stereo) |
| `assets/audio/sfx/explosion_huge.wav` | 5.60 s | 2 | 44100 | -1.0 / 2.5 | -13.7 | -9.2 | nein | 0 | Flaggschiff-Explosion (Kettenexplosion, Stereo, lange Rumpel-Fahne) |
| `assets/audio/sfx/explosion_large_1.wav` | 3.10 s | 1 | 44100 | -1.0 / 0.6 | -18.1 | -9.4 | nein | 0 | Zerstörer-Explosion 1 (3 Detonationen, Trümmer, Grollen) |
| `assets/audio/sfx/explosion_large_2.wav` | 3.20 s | 1 | 44100 | -2.2 / -2.2 | -19.5 | -10.0 | nein | 0 | Zerstörer-Explosion 2 (4 Detonationen) |
| `assets/audio/sfx/explosion_small_1.wav` | 1.55 s | 1 | 44100 | -1.8 / -1.8 | -20.7 | -12.0 | nein | 0 | Fighter-Explosion 1 |
| `assets/audio/sfx/explosion_small_2.wav` | 1.50 s | 1 | 44100 | -1.9 / -1.9 | -20.9 | -12.0 | nein | 0 | Fighter-Explosion 2 (dunkler) |
| `assets/audio/sfx/explosion_small_3.wav` | 1.55 s | 1 | 44100 | -1.8 / -1.8 | -20.7 | -12.0 | nein | 0 | Fighter-Explosion 3 (heller) |
| `assets/audio/sfx/flagship_charge_loop.wav` | 2.00 s | 1 | 44100 | -7.7 / -7.7 | -17.1 | -12.0 | ja (Naht-Sprung im 38. Perzentil der Sample-Schritte) | 0 | Flaggschiff lädt (pulsierend; im Spiel pitch_scale hochziehen) |
| `assets/audio/sfx/flagship_fire.wav` | 3.00 s | 2 | 44100 | -1.0 / -0.6 | -11.8 | -9.9 | nein | 0 | Flaggschiff-Schuss (gewaltig, Stereo) |
| `assets/audio/sfx/hyperjump.wav` | 2.80 s | 2 | 44100 | -1.0 / 0.5 | -8.8 | -11.6 | nein | 0 | Hyperraumsprung (Aufladen, Woosh, Abriss) |
| `assets/audio/sfx/hyperjump_arrive.wav` | 1.80 s | 2 | 44100 | -1.0 / -0.2 | -12.8 | -11.3 | nein | 0 | Ankunft aus dem Hyperraum (Boom + Schimmer) |
| `assets/audio/sfx/hyperjump_arrive_long.wav` | 2.60 s | 2 | 44100 | -1.2 / -1.2 | -11.8 | -11.0 | nein | 0 | Ankunft nach langem Sprung (tiefer Boom + Braam, Woosh L->R, nachklingende Hülle; Stereo) |
| `assets/audio/sfx/hyperjump_long.wav` | 4.60 s | 2 | 44100 | -1.2 / -1.2 | -11.4 | -10.9 | nein | 0 | Langer Sprung (düsterer, rotverschobener Aufbau; Knall/Woosh exakt bei 3.75 s = Weißblitz; Stereo) |
| `assets/audio/sfx/incoming.wav` | 0.60 s | 1 | 44100 | -7.5 / -7.5 | -17.3 | -17.0 | nein | 0 | Warnton: Geschoss im Anflug (3 Pieptöne) |
| `assets/audio/sfx/ion_fire.wav` | 1.45 s | 1 | 44100 | -3.9 / -3.9 | -18.4 | -11.0 | nein | 0 | Ionen-Kanone: Sub-Wumms + Supersaw-Entladung + elektrisches Sirren |
| `assets/audio/sfx/ion_ready.wav` | 0.50 s | 1 | 44100 | -12.9 / -12.8 | -24.0 | -24.0 | nein | 0 | Ionen-Kanone nachgeladen (dezenter Zweiklang) |
| `assets/audio/sfx/laser_1.wav` | 0.42 s | 1 | 44100 | -1.1 / -1.0 | -13.6 | -15.0 | nein | -3 | Bordlaser, Variante 1 (scharfer Pitch-Sweep, Square+FM) |
| `assets/audio/sfx/laser_2.wav` | 0.40 s | 1 | 44100 | -1.0 / 1.5 | -13.8 | -15.5 | nein | -3 | Bordlaser, Variante 2 (heller, kürzer) |
| `assets/audio/sfx/laser_3.wav` | 0.45 s | 1 | 44100 | -2.1 / -1.9 | -14.0 | -15.0 | nein | -3 | Bordlaser, Variante 3 (tiefer, mehr 'Zap') |
| `assets/audio/sfx/laser_deflect.wav` | 0.45 s | 1 | 44100 | -3.3 / -2.7 | -16.3 | -19.0 | nein | 0 | Laser prallt wirkungslos ab (Ping) |
| `assets/audio/sfx/map_close.wav` | 0.60 s | 1 | 44100 | -2.9 / -2.9 | -18.7 | -19.0 | nein | 0 | Karte schließen |
| `assets/audio/sfx/map_open.wav` | 0.65 s | 1 | 44100 | -5.9 / -5.3 | -16.2 | -18.0 | nein | 0 | Karte öffnen (Sweep + digitale Chirps) |
| `assets/audio/sfx/near_miss.wav` | 0.90 s | 2 | 44100 | -1.0 / -0.6 | -10.4 | -14.0 | nein | -2 | Projektil zischt vorbei (Doppler + Panorama L->R) |
| `assets/audio/sfx/planet_saved.wav` | 3.60 s | 2 | 44100 | -4.1 / -4.1 | -15.4 | -13.0 | nein | 0 | Jingle: Planet gerettet (Motiv + bVI-bVII-I-Kadenz, Pauken) |
| `assets/audio/sfx/player_hit_heavy.wav` | 1.40 s | 1 | 44100 | -3.1 / -3.0 | -19.0 | -10.0 | nein | 0 | Schwerer Treffer (Krachen, Metallstress, Funken) |
| `assets/audio/sfx/player_hit_light.wav` | 0.55 s | 1 | 44100 | -2.3 / -2.3 | -18.6 | -15.0 | nein | 0 | Spieler von Fighter getroffen (Knistern + dumpfer Schlag) |
| `assets/audio/sfx/refuel_complete.wav` | 1.50 s | 1 | 44100 | -4.9 / -4.9 | -18.4 | -16.0 | nein | 0 | Tank voll (E-Piano-Arpeggio + Fläche) |
| `assets/audio/sfx/refuel_tick.wav` | 0.20 s | 1 | 44100 | -7.0 / -6.9 | -25.4 | -23.4 | nein | 0 | Tank-Schritt +5 % |
| `assets/audio/sfx/shield_break.wav` | 1.05 s | 1 | 44100 | -1.0 / 2.0 | -16.5 | -13.5 | nein | 0 | Schildschicht bricht (Glas-Splitter + Power-Down) |
| `assets/audio/sfx/shield_hit.wav` | 0.80 s | 1 | 44100 | -4.1 / 0.6 | -16.9 | -14.0 | nein | 0 | Treffer auf Zerstörer-Schild (FM-Metall + Knistern) |
| `assets/audio/sfx/squadron_destroyed.wav` | 2.90 s | 2 | 44100 | -1.5 / -1.5 | -14.3 | -14.0 | nein | 0 | Jingle: Schwadron vernichtet (Motiv-Quinte -> D-Dur) |
| `assets/audio/sfx/target_lock.wav` | 0.07 s | 1 | 44100 | -12.0 / -12.0 | -30.6 | -26.5 | nein | -2 | Ziel im Visier (leiser Doppel-Tick) |
| `assets/audio/sfx/ui_back.wav` | 0.25 s | 1 | 44100 | -12.4 / -12.4 | -23.4 | -22.0 | nein | 0 | UI: Zurück |
| `assets/audio/sfx/ui_error.wav` | 0.38 s | 1 | 44100 | -10.2 / -10.2 | -21.3 | -20.0 | nein | 0 | UI: Fehler / gesperrt |
| `assets/audio/sfx/ui_move.wav` | 0.07 s | 1 | 44100 | -10.6 / -10.3 | -29.3 | -24.0 | nein | 0 | UI: Cursor bewegen |
| `assets/audio/sfx/ui_select.wav` | 0.30 s | 1 | 44100 | -10.9 / -10.8 | -21.1 | -21.0 | nein | 0 | UI: Bestätigen |
| `assets/audio/sfx/ui_type.wav` | 0.05 s | 1 | 44100 | -10.0 / -9.0 | -36.1 | -30.2 | nein | 0 | UI: Tastendruck (Namenseingabe) |
| `assets/audio/sfx/warning_low_energy.wav` | 0.63 s | 1 | 44100 | -9.9 / -9.9 | -17.7 | -16.0 | nein | 0 | Warnung: niedrige Energie (Doppel-Piep, fallend) |
| `assets/audio/sfx/warp_in.wav` | 1.15 s | 1 | 44100 | -3.1 / -2.3 | -13.8 | -14.0 | nein | 0 | Feindschiff erscheint (Riss + Zap) |
| `assets/audio/sfx/wave_incoming.wav` | 1.35 s | 1 | 44100 | -5.8 / -5.8 | -18.9 | -14.0 | nein | 0 | Neue Gegnerwelle (Brass-Stabs + Schlag) |
| `assets/audio/sfx/weapon_bombs.wav` | 0.38 s | 1 | 44100 | -6.4 / -6.4 | -19.1 | -19.5 | nein | 0 | Waffe auf Bomben (Servo-Surren + Verriegelungsklick) |
| `assets/audio/sfx/weapon_laser.wav` | 0.32 s | 1 | 44100 | -8.6 / -8.6 | -19.2 | -20.0 | nein | 0 | Waffe auf Laser (kurzes Energie-Aufsirren) |

## Musik (`assets/audio/music/`, Ogg Vorbis q6, 44.1 kHz Stereo)

| Datei | Dauer | Kanäle | Rate | Peak / TP | LUFS | ST-max | Loop | Vol | Beschreibung |
|---|---|---|---|---|---|---|---|---|---|
| `assets/audio/music/combat_planet.ogg` | 108.17 s | 2 | 44100 | -4.5 / -3.1 | -14.0 | -16.0 | ja (Naht-Sprung im 27. Perzentil der Sample-Schritte) | – | Planetenkampf, F-Moll, 142 BPM, dunkler/dringlicher (Reese-Bass, Taikos, Phrygische Stabs) |
| `assets/audio/music/combat_space.ogg` | 105.88 s | 2 | 44100 | -4.7 / -3.9 | -14.1 | -16.1 | ja (Naht-Sprung im 20. Perzentil der Sample-Schritte) | – | Weltraumkampf, E-Moll, 136 BPM, treibend (16tel-Bass, Brass-Thema, Break, Klimax) |
| `assets/audio/music/debrief_theme.ogg` | 80.00 s | 2 | 44100 | -5.5 / -5.5 | -15.0 | -18.0 | ja (Naht-Sprung im 5. Perzentil der Sample-Schritte) | – | Einsatzauswertung (abgebrochen), H-Moll, 72 BPM, ruhig-nachdenklich (Titelthema verlangsamt, E-Piano, Streicher-B-Teil in D-Dur) |
| `assets/audio/music/docking_theme.ogg` | 57.14 s | 2 | 44100 | -5.2 / -4.4 | -15.0 | -16.6 | ja (Naht-Sprung im 82. Perzentil der Sample-Schritte) | – | Andocken/Tanken, D-Dur, 84 BPM, warm (E-Piano, Glocken-Motiv in Dur) |
| `assets/audio/music/enemy_system_theme.ogg` | 48.00 s | 2 | 44100 | -5.3 / -2.5 | -15.0 | -16.7 | ja (Naht-Sprung im 87. Perzentil der Sample-Schritte) | – | Feindsystem (Platzhalter), C-phrygisch/Tritonus, 70 BPM, fremdartig-düster |
| `assets/audio/music/gameover_theme.ogg` | 43.00 s | 2 | 44100 | -6.3 / -6.2 | -16.0 | -18.8 | nein | – | Game Over, D-Moll, 60 BPM, Horn-Motiv langsam in Moll, endet sauber (kein Loop) |
| `assets/audio/music/map_theme.ogg` | 90.00 s | 2 | 44100 | -5.2 / -4.3 | -15.0 | -17.1 | ja (Naht-Sprung im 32. Perzentil der Sample-Schritte) | – | Systemkarte, A-Moll, 80 BPM, ruhig-angespannt (Flächen, Glas-Arpeggio, Sonar, Horn-Motiv) |
| `assets/audio/music/title_theme.ogg` | 100.00 s | 2 | 44100 | -4.6 / -4.2 | -14.0 | -15.7 | ja (Naht-Sprung im 9. Perzentil der Sample-Schritte) | – | Titelthema, D-Moll, 96 BPM, heroisch synth-orchestral (Intro-A-B-Bridge-Klimax-Outro) |
| `assets/audio/music/victory_theme.ogg` | 76.80 s | 2 | 44100 | -4.6 / -4.0 | -14.0 | -14.9 | ja (Naht-Sprung im 88. Perzentil der Sample-Schritte) | – | Sieg, D-Dur, 100 BPM, heroisch-orchestral (Motiv als Fanfare, Marsch, Streicher-B-Teil, Tutti-Klimax mit bVI-bVII-I, Coda) |

## Integrationshinweise

- **Loops**: `alarm_station`, `bombard_loop`, `flagship_charge_loop`, `engine_loop` (WAV) sowie alle Musikstücke außer `gameover_theme` sind exakt auf Loop-Länge geschnitten. In Godot: WAV -> `AudioStreamWAV.loop_mode = LOOP_FORWARD`, `loop_begin = 0`, `loop_end = Sampleanzahl` (oder Import-Option *Loop Mode: Forward*); OGG -> `AudioStreamOggVorbis.loop = true`.
- **Lautheit**: SFX sind untereinander abgestimmt (UI leise, Explosionen kräftig). Musik ist auf ca. -14 LUFS (Kampf/Titel) bzw. -15/-16 LUFS (Karte, Docking, Feindsystem, Game Over) gemastert -> Musik-Bus im Spiel ca. -6 dB unter dem SFX-Bus fahren.
- **Laser** werden schnell hintereinander gefeuert: Varianten zufällig wechseln, `volume_db` ca. -3, evtl. `pitch_scale` 0.97–1.03 randomisieren.
- **flagship_charge_loop**: während der Aufladephase `pitch_scale` von ~0.8 auf ~1.6 hochziehen und Lautstärke mitfahren; beim Schuss stoppen und `flagship_fire` spielen.
- **engine_loop** dauerhaft im Cockpit (leise), **bombard_loop** als 3D-Quelle am Zerstörer (AudioStreamPlayer3D) während des Bombardements.
- **gameover_theme** endet sauber (Fade am Ende), nicht loopen.
- `combat_space`/`combat_planet` beginnen mit einem 4-taktigen Intro und enden mit einem Turnaround, der nahtlos ins Intro zurückführt; Crossfades beim Zustandswechsel ~1 s.
- **hyperjump_long** beim Start des langen Sprungs (3x `jump_duration`) spielen: Knall/Woosh exakt bei 3.75 s (Weißblitz/Szenenwechsel), danach kurzes Ausklingen bis 4.6 s. `hyperjump_arrive_long` beim Szenenwechsel (~3.75 s) starten – beide sind aufeinander abgestimmt (Aufbau/Riss bzw. tiefer Boom).
- **bomb_release** und **bomb_fall** gleichzeitig beim Abwurf; `bomb_fall` ist bei ~1.4 s verklungen, `bomb_impact` beim Einschlag (~1.3 s) spielen. `weapon_bombs`/`weapon_laser` beim Waffenwechsel, `bomb_empty` bei Abwurfversuch ohne Bomben.
- **victory_theme** (-14 LUFS) und **debrief_theme** (-15 LUFS wie die anderen ruhigen Stücke) sind nahtlose Loops.
