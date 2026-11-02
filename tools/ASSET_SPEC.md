# Starfighter Defense – Asset-Spezifikation

Alle Assets werden selbst erzeugt (prozedural / per Skript). Keine Fremd-Assets, keine Original-Assets.
Projektwurzel (Godot): `/home/user/starfighter-defense/`
Generator-Skripte gehören nach `tools/` (Ordner hat `.gdignore`, wird von Godot ignoriert).

Werkzeuge:
- Python-venv: `/opt/tools/venv/bin/python` (numpy, scipy, soundfile, pedalboard, mido, pretty_midi, pillow, bpy 5.2 = Blender als Modul)
- Godot 4.7.2: `godot` (headless möglich: `godot --headless --path <proj> ...`)
- ffmpeg, sox, fluidsynth + `/usr/share/sounds/sf2/FluidR3_GM.sf2` (MIT-lizenziert)

Stil: "Retro-Futurismus in hoher Qualität" – klare, kräftige Farben auf dunklem Weltraum, saubere Formen,
leuchtende Akzente (Emission/Bloom), keine Kitsch-Details. Gegner: kantig, aggressiv, gut lesbar.
Spielerseite (Stationen, Städte): freundlich, hell, cyan/weiß/warmes Licht.

---------------------------------------------------------------------------------------------------
## A) 3D-Modelle (Blender/bpy → glTF binär `.glb`) → `assets/models/`

Konventionen (wichtig für die Code-Integration):
- Einheiten: Meter. Blender: +Z = oben, **Bug/Front zeigt nach Blender +Y** (wird in Godot zu -Z = "forward").
- Ursprung = Mitte der Bounding-Box. Alle Modifier angewendet, Normalen korrekt (nach außen), Smooth/Flat sinnvoll (Auto-Smooth/"Smooth by Angle" ~35°).
- Export: `bpy.ops.export_scene.gltf(filepath=..., export_format='GLB', export_apply=True, export_yup=True, use_selection=False)`; Szene vorher leeren (nur das Modell exportieren, keine Kamera/Lichter).
- Materialien: Principled BSDF, Namen exakt wie unten (Godot ersetzt/tuned per Materialname). Base Color + Metallic + Roughness + ggf. Emission (Emission Strength 1–5). Keine Bildtexturen nötig (optional erlaubt, dann eingebettet).
- Polybudget: Fighter ≤ 4k Tris, Zerstörer ≤ 10k, Flaggschiff ≤ 25k, Station ≤ 20k, Stadt ≤ 8k, Ruine ≤ 6k.
- Leere Objekte (Empties) werden als Nodes exportiert – Namen exakt wie unten, dienen als Andockpunkte für Effekte.
- Detail durch Geometrie: Bevels (Bevel-Modifier, 1–2 Segmente), Panel-Inset/Extrude, Greebles, Antennen, Triebwerksdüsen. Formen sollen aus Distanz als Silhouette klar erkennbar sein.

| Datei | Größe | Beschreibung | Materialnamen | Pflicht-Objekte/Empties |
|---|---|---|---|---|
| `fighter.glb` | Länge ~7 m, Spannweite ~6 m | Feindlicher Jäger: pfeilförmig, nach vorn gezogene/gepfeilte Flügel, Cockpit-Kuppel, 2 Triebwerke hinten | `Hull` (dunkles Gunmetal), `HullDark`, `Accent` (Emission orange-rot), `Glow` (Triebwerk, Emission hell orange), `Glass` (Kanzel, Emission dunkelrot) | Empties `Engine_L`, `Engine_R` (Düsenmitte hinten), `Gun_L`, `Gun_R` (vorn) |
| `destroyer.glb` | Länge ~24 m, Breite ~14 m | Feindlicher Zerstörer: wuchtig, gepanzert, Hammerkopf-/Keilform, Geschütz unten vorn, Bombenschacht unten | `Hull`, `HullDark`, `Accent` (**neutral hellgrau/weiß mit Emission** – wird in Godot blau/grün/rot eingefärbt), `Glow` (Triebwerke) | Empties `Engine_1..n`, `Gun_Main` (vorn unten), `BombBay` (Unterseite Mitte) |
| `flagship.glb` | Länge ~100 m, Breite ~70 m | Flaggschiff: riesig, bedrohlich, breite Front die dem Spieler zugewandt ist. **In der Mitte der Front (Richtung +Y) ein quadratisches Feld ~7×7 m** als eigenes Objekt `WeakPoint` (leicht vertieft eingelassen, Rahmen drumherum) | `Hull`, `HullDark`, `Accent` (Emission violett), `Glow`, `WeakPoint` (Emission pink #ff4fd0, wird in Godot animiert) | Objekt `WeakPoint` (eigenes Mesh!), Empty `Gun_Main` (vor dem WeakPoint), `Engine_*` hinten |
| `station.glb` | Ø ~70 m | Raumstation der Spielerseite: zentrale Nabe mit Andockport vorn (+Y), großer Ring um die Y-Achse (Speichen), Solarpanels, Antennen | `Structure` (helles Grau/Weiß, leicht metallisch), `StructureDark`, `Windows` (Emission warmweiß), `Glow` (Emission cyan, Andock-Lichter), `Panels` (Solarzellen dunkelblau, glänzend) | Objekte `Ring` (dreht sich in Godot um lokale Y-Achse von Blender = Godot -Z), `Hub`; Empties `Beacon_1..4` (Blinklichter), `DockPort` |
| `city_a.glb`, `city_b.glb`, `city_c.glb` | Grundfläche Ø 36–44 m, max. Höhe 26 m | Planetenstädte: Kuppeln, Türme, Verbindungsröhren, Landeplattform; jede Variante anders | `Structure`, `StructureDark`, `Dome` (hellblau, halbtransparent wirkend, glänzend), `Windows` (Emission warm/cyan), `Glow` (Beacon) | Ursprung am **Boden-Mittelpunkt** (Ausnahme!), Empty `Beacon` an höchster Stelle |
| `city_ruins.glb` | wie Stadt | Zerstörte Stadt: Trümmer, abgebrochene Türme, aufgerissene Kuppel | `Charred` (fast schwarz), `Structure`, `Embers` (Emission dunkelorange) | Ursprung am Boden-Mittelpunkt |
| `rocks.glb` | 2–10 m | 5 Felsbrocken/Kristall-Varianten als eigene Objekte `Rock_0`..`Rock_4`, jeweils Ursprung am Boden-Mittelpunkt | `Rock` | – |
| `debris.glb` | 0.5–3 m | 4 Trümmerteile `Debris_0`..`Debris_3` (Panzerplatten, Rohre) | `Hull`, `Charred` | – |

Zusätzlich: Vorschau-Renders (Cycles, 512px) jedes Modells nach `tools/blender/previews/*.png` zur Qualitätskontrolle.

---------------------------------------------------------------------------------------------------
## B) Texturen → `assets/textures/`

Alle PNG, sRGB, straight alpha.

| Datei | Größe | Inhalt |
|---|---|---|
| `sky/space_panorama.png` | 4096×2048, equirektangular | Dunkler Weltraum: viele schwache Sterne (Farbtemperatur-Verteilung weiß/blau/gelb/orange), wenige helle mit kleinem Glow, dezentes Milchstraßenband, 2–3 farbige Nebel (Petrol/Violett/Orange) **dezent** (Action muss hervorstechen). Nahtlos an der linken/rechten Kante, keine Pol-Verzerrung (aus 3D-Richtungsvektoren erzeugt). |
| `sky/space_panorama_b.png` | 4096×2048 | Variante (andere Nebelfarben, z. B. Blau/Magenta), für Abwechslung |
| `map/map_background.png` | 2560×1440 | Hintergrund der Systemkarte: tiefes Blauschwarz, feiner Nebel, Sterne; Mitte eher ruhig (dort ist die Sonne), Ecke oben links darf etwas Nebel haben |
| `planets/terran.png` | 2048×1024 equirect | Heimatplanet: Ozeane, Kontinente (grün/braun), Polkappen |
| `planets/desert.png`, `ice.png`, `jungle.png`, `volcanic.png`, `ocean.png`, `toxic.png`, `barren.png` | 2048×1024 | Planetentypen, deutlich unterscheidbar, klare Farben |
| `planets/volcanic_emission.png` | 2048×1024 | Lava-Leuchtmaske (schwarz/orange) passend zu volcanic |
| `planets/clouds.png` | 2048×1024 | Wolkenschicht (weiß, Alpha = Dichte), nahtlos |
| `planets/gas_giant.png` | 2048×1024 | Gasriese mit Bändern (für Hintergründe) |
| `fx/explosion_flipbook.png` | 2048×2048 (8×8 Frames à 256px) | Explosion: Feuerball (hell weiß-gelb → orange → rot) wächst, zerfällt in dunklen Rauch; Frames zeilenweise oben links → unten rechts; Alpha zum Ende hin 0. Ideal: Blender Cycles Volumen-Render (Principled Volume + Noise, Emission nach "Temperatur"), sonst prozedural. |
| `fx/smoke_puff.png` | 256×256 | weiche Rauchwolke, grau, Alpha |
| `fx/glow.png` | 256×256 | radialer weicher Glow (weiß, Alpha-Falloff) |
| `fx/spark.png` | 128×32 | länglicher Funke (weiß, Alpha) |
| `fx/flare.png` | 512×512 | Stern-Flare mit 4–6 Strahlen (weiß, Alpha) |
| `fx/shockwave.png` | 512×512 | dünner leuchtender Ring (weiß, Alpha) |
| `fx/noise.png` | 512×512 | nahtlose Graustufen-Fraktalnoise (für Shader) |
| `ui/icon.png` + `ui/icon.ico` | 256×256 (+ICO mit 16/32/48/64/128/256) | App-Icon: stilisierter Starfighter vor Planet/Stern, klar erkennbar in klein |

---------------------------------------------------------------------------------------------------
## C) Audio → `assets/audio/`

SFX: `sfx/*.wav`, 44.1 kHz, 16 bit, mono (außer wo "stereo"), normalisiert auf ca. -1 dBFS Peak (Lautheit untereinander sinnvoll abgestimmt: UI leise, Explosionen kräftig). Keine Stille am Anfang (Attack sofort), kurzer Fade am Ende.
Musik: `music/*.ogg` (Vorbis q≈6, 44.1 kHz stereo), **nahtlos loopbar** (Ende geht ohne Klick/Lücke in den Anfang über; Hall-Fahne ans Loop-Ende "zurückfalten"). Mastering: ca. -14 LUFS integriert, True-Peak ≤ -1 dBTP.

| Datei | Dauer | Beschreibung |
|---|---|---|
| `sfx/laser_1.wav`, `laser_2.wav`, `laser_3.wav` | 0.25–0.4 s | Bordlaser, knackig, "pew" mit schnellem Pitch-Sweep, leicht unterschiedlich |
| `sfx/ion_fire.wav` | ~1.2 s | Ionen-Kanone: tiefer, mächtiger Wumms + elektrisches Sirren |
| `sfx/ion_ready.wav` | ~0.3 s | dezenter "bereit"-Ton (Ionen-Kanone nachgeladen) |
| `sfx/shield_hit.wav` | ~0.6 s | Treffer auf Zerstörer-Schild: elektrisch, metallisch |
| `sfx/shield_break.wav` | ~0.8 s | Schildschicht bricht zusammen: glasig, absteigend |
| `sfx/laser_deflect.wav` | ~0.3 s | Laser prallt wirkungslos ab ("ping") |
| `sfx/explosion_small_1..3.wav` | 1–1.5 s | Fighter-Explosion |
| `sfx/explosion_large_1..2.wav` | 2–3 s | Zerstörer-Explosion, mit Nachgrollen |
| `sfx/explosion_huge.wav` | ~5 s, stereo | Flaggschiff-Explosion, gewaltig, lange Rumpel-Fahne |
| `sfx/player_hit_light.wav` | ~0.4 s | Spieler von Fighter getroffen: kurzes Knistern + dumpfer Schlag |
| `sfx/player_hit_heavy.wav` | ~1.2 s | schwerer Treffer (Zerstörer/Flaggschiff): Krachen, Metallstress, Funken |
| `sfx/enemy_shot_fighter.wav` | ~0.3 s | feindlicher Fighter-Schuss (anders als Spielerlaser, "fieser") |
| `sfx/enemy_shot_destroyer.wav` | ~1 s | Zerstörer-Torpedo: kurzes Aufladen + Abschuss |
| `sfx/flagship_charge_loop.wav` | 2.0 s loopbar | tiefes, pulsierendes Aufladen (Pitch wird im Spiel hochgezogen) |
| `sfx/flagship_fire.wav` | ~2.5 s | gewaltiger Abschuss |
| `sfx/near_miss.wav` | ~0.8 s, stereo | Projektil zischt knapp vorbei |
| `sfx/incoming.wav` | ~0.6 s | kurzer Warnton "Geschoss im Anflug" |
| `sfx/alarm_station.wav` | 2.0 s loopbar | Alarm: Station wird angegriffen (Zweiton/Sirene) |
| `sfx/warning_low_energy.wav` | ~0.8 s | Warnton niedrige Energie (doppelter Piepton) |
| `sfx/hyperjump.wav` | ~2.5 s, stereo | Sprung: Aufladen, steigender Ton, Woosh, endet mit Abriss |
| `sfx/hyperjump_arrive.wav` | ~1.5 s, stereo | Ankunft: tiefer Boom, Nachhall |
| `sfx/warp_in.wav` | ~1 s | feindliches Schiff erscheint (Riss/Woosh) |
| `sfx/dock_slide.wav` | ~3 s | Station gleitet heran, Hydraulik/Brummen |
| `sfx/dock_clamp.wav` | ~1 s | Andockklammern greifen: mechanisches Klonk + Zischen |
| `sfx/refuel_tick.wav` | ~0.15 s | Tank-Schritt (+5 %) |
| `sfx/refuel_complete.wav` | ~1 s | Tank voll, freundlicher Akkord-Jingle |
| `sfx/city_destroyed.wav` | ~3 s | Stadt zerstört: ferne Detonation, Einsturz, Grollen |
| `sfx/bombard_loop.wav` | 2.0 s loopbar | Bombardement-Strahl, bedrohliches Brummen/Knistern |
| `sfx/ui_move.wav`, `ui_select.wav`, `ui_back.wav`, `ui_error.wav`, `ui_type.wav` | 0.05–0.4 s | UI: Cursor, Bestätigen, Zurück, Fehler/gesperrt, Tastendruck |
| `sfx/map_open.wav`, `map_close.wav` | ~0.5 s | Karte auf/zu (digitales Rauschen/Swoosh) |
| `sfx/wave_incoming.wav` | ~1 s | neue Gegnerwelle |
| `sfx/squadron_destroyed.wav` | ~2.5 s | Erfolgs-Jingle (Schwadron vernichtet) |
| `sfx/planet_saved.wav` | ~3 s | Erfolgs-Jingle (Planet gerettet), feierlicher |
| `sfx/engine_loop.wav` | 4.0 s loopbar, stereo | Cockpit-Ambience: tiefes Triebwerksbrummen, ruhig |
| `sfx/target_lock.wav` | ~0.1 s | leiser Klick, Ziel im Visier |
| `music/title_theme.ogg` | 90–120 s Loop | Heroisch, synth-orchestral (Retro-Synth + Streicher/Bläser-Flächen), einprägsames Thema |
| `music/map_theme.ogg` | 80–100 s Loop | Ruhig, angespannt, Flächen + langsames Arpeggio, Taktik-Stimmung |
| `music/combat_space.ogg` | 90–120 s Loop | Treibend (≈130–140 BPM), Bass-Sequenz, Drums, Synth-Lead, Thema-Zitate |
| `music/combat_planet.ogg` | 90–120 s Loop | Wie oben, aber dringlicher/dunkler, andere Tonart |
| `music/docking_theme.ogg` | 50–70 s Loop | Entspannt, warm, "sicherer Hafen" |
| `music/gameover_theme.ogg` | 30–45 s (kein Loop nötig, endet sauber) | Traurig, langsam, Thema in Moll |
| `music/enemy_system_theme.ogg` | 40–60 s Loop | Fremdartig, düster (Platzhalter-Zustand Feindsystem) |

Alle Klänge selbst synthetisiert (numpy/scipy, pedalboard für Hall/Kompressor/Chorus/Delay/Limiter), Musik komponiert per Code
(eigene Synths; FluidR3_GM-Soundfont via fluidsynth für Orchester-/Chor-Ebenen erlaubt).
