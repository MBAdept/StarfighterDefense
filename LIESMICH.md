# Starfighter Defense

Remake-Hommage an „Star Raiders II" (1986), umgesetzt mit **Godot 4.7** (Forward+), **Blender 5.2** (bpy, prozedurale Modelle, Cycles-Explosionen) und in Python synthetisierten Klängen und Kompositionen.
Alle Grafiken, Sounds und Musikstücke sind selbst erzeugt. Es werden keine Originalinhalte oder Markennamen verwendet.

## Starten

| System | Datei | Hinweis |
|---|---|---|
| Windows 10/11 (64 bit) | `StarfighterDefense.exe` | Doppelklick. Bei SmartScreen „Weitere Informationen → Trotzdem ausführen“ (unsigniert). |
| Linux (x86_64) | `StarfighterDefense.x86_64` | Ausführbar machen: `chmod +x StarfighterDefense.x86_64`, dann starten. |

Benötigt wird eine Grafikkarte mit Vulkan, DirectX 12 oder OpenGL 3.3. Godot fällt automatisch auf OpenGL zurück, wenn Vulkan fehlt.

## Spielziel

Verteidige das Helion-System. Feindliche Schwadrone kommen aus dem Feindsystem (Galaxie oben links auf der Karte). Sie fliegen langsam auf Planeten oder Raumstationen zu, landen und bombardieren Städte.
**Verloren** hast du, wenn deine Energie auf 0 fällt oder alle Städte zerstört sind. Ziel ist ein möglichst hoher Punktestand (lokale Highscore-Liste).

1. **Orbit-Start**: Wehre über dem Heimatplaneten Halcyon 9 (oder 12) Fighter in Dreierwellen ab. Danach ist die Karte freigeschaltet.
2. **Systemkarte (Leertaste)**: Ziel wählen (Planet, Station, Schwadron) und springen. Ein Sprung kostet Energie, je weiter, desto mehr (3–15 %).
3. **Weltraumkampf**: Erst die Fighter (Bordlaser), danach die Zerstörer nacheinander (Ionen-Kanone). Sie stehen knapp außerhalb des Sichtfelds, also links oder rechts suchen. Ein Flaggschiff kann zusätzlich auftauchen.
4. **Planetenkampf**: Die Zerstörer schweben über Städten und bombardieren sie. Im Scanner blinkt die bombardierte Stadt. Sind alle Zerstörer vernichtet, ist der Planet gerettet.
5. **Raumstation**: Andocken und auftanken (10 %/s in 5-%-Schritten). Wird die Station angegriffen, erst die Fighter vernichten.

Tipps:
- **Zerstörer**: blau = 2 Treffer, grün = 3, rot = 4. Jeder Treffer nimmt eine Schildschicht weg.
- **Flaggschiff**: Nur das rosa Quadrat ist verwundbar, und nur kurz vor dem eigenen Schuss, wenn es weiß-rosa leuchtet. Die Ionen-Kugel braucht Flugzeit, also leicht vorher feuern!
- **Ausweichen**: Wer im Moment des Einschlags kräftig lenkt (auf Planeten: schnell fliegt), halbiert die Trefferchance des Gegners. Laser können anfliegende Geschosse auch abschießen.
- **Taktik**: Kleinere Schwadrone fliegen langsamer. Ein angeschlagenes Schwadron zu verlangsamen kann klüger sein, als es ganz auszulöschen.

## Steuerung

| Aktion | Tastatur | Gamepad |
|---|---|---|
| Steuern (All: links/rechts/rauf/runter) | Pfeiltasten / WASD | Linker Stick / Steuerkreuz |
| Steuern (Planet: drehen, vor, zurück) | Pfeiltasten / WASD | Linker Stick / Steuerkreuz |
| Feuer | Strg, Enter, F, J, linke Maustaste | A, rechter Trigger |
| Systemkarte | Leertaste, M | Y, Back |
| Waffe wechseln (nur bei manueller Waffenwahl) | Q, Tab | X, RB |
| Karte: Ziel wählen / springen | Pfeile, Maus / Enter, Klick | Stick / A |
| Pause | Esc, P | Start |
| Vollbild | F11 | – |

## Testfunktionen (für die Abnahme der Etappen)

| Taste | Funktion |
|---|---|
| F1 | Hilfe zu den Testtasten ein-/ausblenden |
| F2 | Energie +50 % |
| F3 | sofort ein neues Schwadron |
| F4 | Orbit-Kampf überspringen (Karte freischalten) |
| F5 | alle Gegner im aktuellen Kampf vernichten |
| F6 | Schwadron auf einem Planeten landen lassen und direkt dorthin springen (Planetenkampf testen) |
| F7 | Strategiezeit ×4 (Schwadrone bewegen sich schneller) |
| F8 | Feindsystem-Platzhalter betreten |
| F9 | Game Over auslösen (Highscore testen) |
| F10 | Energie −20 % (Warnton und Tanken testen) |
| F12 | Screenshot (im Benutzerordner) |

Abschalten über `debug_keys_enabled=false` in der `balance.cfg` (siehe unten).

## Spielwerte anpassen (ohne neu zu exportieren)

Alle Balancing-Werte stehen zentral in `scripts/autoload/config.gd`, jeweils markiert mit **[ORIGINAL]**, **[VERMUTET]** oder **[FREI]**.
Zum Ändern ohne Neuexport legst du eine Datei **`balance.cfg`** neben die ausführbare Datei:

```ini
[balance]
fighter_damage=2.0
bombard_time=14.0
single_destroyer_stops=false
orbit_fighter_count=12
```

Eine Vorlage mit allen Werten schreibt das Spiel beim Start nach `balance_template.cfg` im Benutzerordner:
- Windows: `%APPDATA%\StarfighterDefense\`
- Linux: `~/.local/share/StarfighterDefense/`

Dort liegen auch `highscores.json` und `settings.cfg`.

Einige Optionen lassen sich auch direkt im Spiel umschalten (Optionen): automatische Waffenwahl, 9/12 Fighter im Orbit, die [VERMUTET]-Regel „Schwadron mit nur einem Zerstörer bleibt zeitweise stehen“, Schwierigkeit, Scanner-Ausrichtung, Randpfeile und Retro-Filter.

## Änderungen in Version 0.9.1 (nach dem ersten Spieltest)

- **Alarmsignal** endet nach höchstens 5 Sekunden (`alarm_duration`), mehrere Alarme stapeln sich nicht mehr. Zuvor lief der Alarm durch einen Fehler endlos weiter.
- **Energie-Warnton**: beim Unterschreiten von 25 % bzw. 10 % ein kurzer Stoß aus 3 Tönen, danach nur noch eine Erinnerung alle 15 s statt Dauerpiepen.
- **Fighter schießen zurück**: erster Schuss schon im Anflug (0,7–1,9 s nach dem Erscheinen), danach regelmäßig beim Kreisen. Die Schüsse sind deutlicher zu sehen und zu hören. Ein einzelner Treffer kostet weiterhin nur wenig Energie. Mit `fighter_burst_shots=2` wird daraus ein Doppelschuss (deutlich härter).
- **Frühspiel fordernder**: Stufe 1–2 mit 5–8 Fightern und mehr grünen Zerstörern. Das zweite Start-Schwadron hat die Zusammensetzung von Stufe 2. Zerstörer feuern früher als bisher.
- **Fehler behoben**:
  - Ein Flaggschiff zog sich unter Umständen nie zurück. Jetzt verschwindet es nach dem Sieg über sein Schwadron ohne weiteren Schuss. Ein gerade laufendes verwundbares Fenster bleibt als letzte Chance.
  - Die eigene Ionen-Kugel fing unbeabsichtigt Zerstörer-Torpedos ab. Abfangen kann jetzt nur noch der Bordlaser.
  - Der Ladeton des Flaggschiffs fehlte nach dem Öffnen der Karte.
  - Systemmeldungen spielten den Geschoss-Warnton.
  - Die Musik blieb nach dem Sieg im Kampfmodus.
- Alle neuen Werte stehen in `config.gd` und lassen sich per `balance.cfg` ändern, z. B. `alarm_duration`, `fighter_burst_shots`, `fighter_first_fire_min`, `initial_squadron_levels`, `destroyer_first_fire_min`.
- Weitere Verbesserungen:
  - Musik setzt nach dem Kartenblick nahtlos fort.
  - Das Pausemenü hält auch Dauertöne an.
  - Pausieren während eines Sprungs ist gesperrt.

## Stand / offene Punkte

- **Feindsystem**: Der Sprungpunkt ist sichtbar, aber deaktiviert („in Vorbereitung“). Der Spielzustand `EnemySystemState` (`scripts/states/enemy_system.gd`) existiert und ist mit F8 erreichbar. Dort schließt später das Endspiel an.
- Ein Sieg ist derzeit nicht möglich: Der Feind schickt mit steigender Stufe immer stärkere Schwadrone. Es geht um den Highscore.

## Projektstruktur (Quellcode)

```
project.godot                 Godot-Projekt
scripts/autoload/config.gd    ZENTRALE SPIELWERTE
scripts/autoload/game_state.gd  Strategische Simulation (Planeten, Schwadrone, Städte, Energie, Punkte)
scripts/main.gd               Zustände, Karte, Sprünge, Pause, Testtasten
scripts/combat/               Weltraum-/Planetenkampf, Fighter, Zerstörer, Flaggschiff, Projektile
scripts/map/map_screen.gd     Systemkarte
scripts/hud/cockpit_hud.gd    Cockpit-HUD (Klammer-Visier, Fadenkreuz, Energie, Scanner)
shaders/                      Himmel, Planeten, Boden, Schilde, Explosionen, Hyperraum, Nachbearbeitung
assets/                       Modelle (glb), Texturen, Audio, Schriften (OFL)
tools/                        Generatoren: Blender-Modelle, Texturen, Klangsynthese/Komposition
```

Schriften: Orbitron, Rajdhani, Share Tech Mono (SIL Open Font License, siehe `assets/fonts/`).
Orchesterklänge zum Teil aus FluidR3_GM (MIT-Lizenz).
