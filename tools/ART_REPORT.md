# ART_REPORT – 3D-Modelle & Texturen (Abschnitt A + B der ASSET_SPEC)

Alles prozedural erzeugt (bpy 5.2.3 = Blender als Python-Modul, numpy/scipy/Pillow). Keine Fremd-Assets.
Übersicht: `tools/blender/previews/models_overview.png`, Einzel-Previews in `tools/blender/previews/` und `tools/textures/previews/`.

## Achsen / Konventionen (in Godot geprüft, Import in Wegwerf-Projekt mit Godot 4.7.2)
- Bug/Front aller Schiffe zeigt in Godot nach **-Z**, oben = +Y. `node.look_at(target)` richtet die Front auf das Ziel
  (gilt auch für Flaggschiff-Front mit WeakPoint und den Stations-Andockport).
- Einheiten Meter, Modell-Ursprung = Bounding-Box-Mitte (Ausnahmen: Städte/Felsen = Boden-Mittelpunkt).
- Empties kommen als `Node3D`, Meshes als `MeshInstance3D` direkt unter der Szenen-Wurzel an (kein Parenting).
- Emission kommt als StandardMaterial3D-Emission an (Energie = Blender-Strength, siehe Liste).

## Modelle (`assets/models/`)
| Datei | Maße (B×H×L in Godot, m) | Tris | Nodes | Materialien (Emission) |
|---|---|---|---|---|
| fighter.glb | 6.32 × 2.16 × 7.56 | 3.2k | `Fighter` (Mesh), `Engine_L/R` (±0.95, -0.04, +3.66), `Gun_L/R` (±0.62, -0.16, -3.95) | Hull, HullDark, Glass (1.0, rot), Accent (5.0, orange-rot), Glow (9.0, Triebwerk) |
| destroyer.glb | 15.2 × 8.35 × 26.1 | 5.3k | `Destroyer`, `Engine_1..4` (z=+12.85), `Gun_Main` (0, -2.25, -13.45), `BombBay` (0, -2.35, +1.0) | Hull, HullDark, **Accent** (3.0, weiß → einfärben), **AccentPaint** (weiß, nicht emissiv → optional mit einfärben), Glow (8.0, warmweiß) |
| flagship.glb | 75.7 × 45.4 × 104.0 | 7.7k | `Flagship`, **`WeakPoint`** (eigenes Mesh), `Engine_1..6` (z=+53.3), `Gun_Main` (0, 0, -48.25) | Hull, HullDark, Accent (4.0, violett), Glow (8.0), WeakPoint (3.0, pink #ff4fd0) |
| station.glb | Ring Ø 68, Solarflügel 76.8 breit, 51 lang | 13.0k | `Hub` (statisch), **`Ring`** (Ursprung = Stationsmitte, um lokale **Z** drehen), `DockPort` (0, 0, -17.8), `Beacon_1..4` | Structure, StructureDark, Windows (3.5, warm), Glow (6.0, cyan), Panels |
| city_a/b/c.glb | ca. 36–38 × 25–30 hoch | 2.9–4.0k | `CityA/B/C`, `Beacon` (höchster Punkt, a: (0, 29.5, -13), b: (0, 28.6, 0), c: (0, 25.2, 0)) | Structure, StructureDark, Dome (1.0, hellblau), Windows (3.2), Glow (5.0, cyan) |
| city_ruins.glb | 35.8 × 10.5 | 2.3k | `CityRuins` (min y = -0.55, leicht in den Boden versenkt) | Charred, Structure, Embers (2.5) |
| rocks.glb | 2.2–9.2 m | 0.1–0.4k | `Rock_0..4` (Mesh-Ursprung = Boden-Mitte; Nodes liegen nur zur Vorschau bei x = 0/8/15/22/29) | Rock |
| debris.glb | 1–2.6 m | <0.2k | `Debris_0..3` (Nodes bei x = 0/3.5/7/10.5; Mesh-Ursprung = Mitte) | Hull, Charred |

Details für die Integration:
- **WeakPoint**: Node-Position (0, 0, -46.45) im Modellraum, Ursprung in seiner eigenen Mitte, 7 × 7 × 0.5 m, zeigt nach -Z,
  liegt ~1.6 m vertieft im Rahmen (Rahmen + Torblöcke ragen davor). Zum Animieren das Material der Surface 0 von `WeakPoint` duplizieren.
- **Station**: Front/Andockport = -Z, beim Andocken also `station.look_at(kamera)`; `Ring` mit `rotate_object_local(Vector3.FORWARD, ...)` bzw. `rotation.z` drehen. Beacons sitzen auf statischen Teilen (Solarflügel-Spitzen, Antennen).
- **Zerstörer-Farbvarianten**: `Accent` (leuchtende Leisten, "Augenlinie" vorn, Bombenschacht) und `AccentPaint` (Panzerplatten/Turm) sind neutral weiß – beide tinten.
- Polybudgets aus der Spezifikation alle eingehalten.

## Texturen (`assets/textures/`, PNG, sRGB, straight alpha)
| Datei | Größe | Hinweis |
|---|---|---|
| sky/space_panorama.png | 4096×2048 RGB (5.6 MB) | equirektangular, nahtlos, polfrei; Nebel türkis/violett/amber, Milchstraßenband; Bildmitte (u=0.5) = Richtung -Z |
| sky/space_panorama_b.png | 4096×2048 RGB (5.9 MB) | Variante blau/magenta/cyan |
| map/map_background.png | 2560×1440 RGB | Mitte ruhig, Nebel oben links (Feind-Sprungpunkt), nur wenige helle Sterne (nicht mit Planeten verwechselbar) |
| planets/terran.png | **4096×2048** (Abweichung: doppelte Auflösung, da im Orbit-Start groß zu sehen) | Heimatplanet |
| planets/desert, ice, jungle, volcanic, ocean, toxic, barren, gas_giant .png | 2048×1024 | |
| planets/volcanic_emission.png | 2048×1024 | Lava-Leuchtmaske passend zu volcanic |
| planets/clouds.png | **4096×2048** RGBA (Abweichung: doppelte Auflösung) | weiß, Alpha = Dichte, mit Wirbelstürmen |
| fx/explosion_flipbook.png | 2048×2048, 8×8 Frames à 256 px | Frame 0–7 Blitz, ~8–24 Feuerball, 24–40 glühender Rauch, 40–63 Rauch blendet aus (Frame 63 Alpha 0). Für kurze Explosionen ~45–60 fps abspielen oder bei Frame ~48 abbrechen |
| fx/smoke_puff.png | 256×256 RGBA | grau, beleuchtet von oben links |
| fx/glow.png, spark.png (128×32, Kopf rechts), flare.png, shockwave.png | wie Spezifikation | RGB weiß, Form im Alpha → frei tintbar |
| fx/noise.png | 512×512 L | nahtlos kachelbar (geprüft) |
| ui/icon.png + ui/icon.ico | 256 + ICO 16/32/48/64/128/256 | weißer Spieler-Jäger über Heimatplanet, cyan Akzente |

Abweichung Explosion: statt Cycles-Volumen (funktioniert, `tools/blender/gen_explosion.py`, aber ~45 s/Frame und
der Denoiser verwäscht die Struktur) wurde ein eigener numpy-Volumen-Raymarcher genutzt (`tools/textures/gen_explosion_np.py`, 40 s für alle 64 Frames).

## Generator-Skripte (reproduzierbar)
`tools/blender/`: blib.py (Toolkit), model_fighter.py, model_destroyer.py, model_flagship.py, model_station.py,
model_cities.py, model_props.py (Felsen + Trümmer), gen_icon.py, gen_explosion.py (Cycles-Alternative), sheet.py.
`tools/textures/`: noiselib.py, gen_sky.py, gen_map_bg.py, gen_planets.py, gen_fx.py, gen_explosion_np.py.
Aufruf jeweils mit `/opt/tools/venv/bin/python <skript> [--preview]`.

## Umgebungs-Hinweis
Die ursprüngliche venv-Installation hing ~40 min am bpy-Download (Direktverbindung zu files.pythonhosted.org ~150 KB/s).
Gelöst durch Download des Wheels über den Proxy (`curl --noproxy '' --proxy "$HTTPS_PROXY" ...`, 25 MB/s) und
Installation aus `/opt/tools/wheels/`; `/opt/tools/pip.log` endet mit `PIP EXIT 0`. Cycles im bpy-Modul muss nach
`read_factory_settings` per `addon_utils.enable("cycles")` aktiviert werden (macht `blib.reset()`).
