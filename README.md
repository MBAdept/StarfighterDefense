# Starfighter Defense

Remake-Hommage an ein klassisches Cockpit-Weltraumspiel der 80er-Jahre, umgesetzt mit **Godot 4.7** (Forward+),
**Blender** (bpy, prozedurale Modelle) und in Python synthetisierten Klängen und Kompositionen.
Alle Grafiken, Sounds und Musikstücke sind selbst erzeugt.

- Spielanleitung, Steuerung, Testtasten und Balancing: [LIESMICH.md](LIESMICH.md)
- Zentrale Spielwerte: [`scripts/autoload/config.gd`](scripts/autoload/config.gd) (markiert mit [ORIGINAL] / [VERMUTET] / [FREI])
- Asset-Generatoren (Blender, Texturen, Audio): [`tools/`](tools/)

## Projekt öffnen / exportieren

1. Godot 4.7 installieren, `project.godot` öffnen (der Importcache `.godot/` wird automatisch erzeugt).
2. Export-Vorlagen installieren, dann *Projekt → Exportieren* („Linux“ bzw. „Windows“, Ausgabe nach `../builds/`).

Headless-Testfahrer (siehe `scripts/main.gd`):

```bash
godot --headless --path . --fixed-fps 60 --quit-after 54000 -- --autoplay --human
```
