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

Verteidige das Helion-System. Feindliche Schwadrone kommen aus dem Feindsystem **Vorrhal** (Galaxie oben links auf der Karte). Sie fliegen langsam auf Planeten oder Raumstationen zu, landen und bombardieren Städte.
**Gewonnen** hast du, sobald alle 12 Städte der feindlichen Heimatwelt **Xhal** zerbombt sind.
**Verloren** hast du, wenn deine Energie auf 0 fällt oder alle eigenen Städte zerstört sind.
Am Ende steht immer eine **Auswertung**: bei Sieg, Game Over und vorzeitigem Abbruch. Dazu gibt es eine lokale Highscore-Liste.

1. **Orbit-Start**: Wehre über dem Heimatplaneten Halcyon 9 (oder 12) Fighter in Dreierwellen ab. Danach ist die Karte freigeschaltet.
2. **Systemkarte (Leertaste)**: Ziel wählen (Planet, Station, Schwadron) und springen. Ein Sprung kostet Energie, je weiter, desto mehr (3–15 %).
3. **Weltraumkampf**: Erst die Fighter (Bordlaser), danach die Zerstörer nacheinander (Ionen-Kanone). Sie stehen knapp außerhalb des Sichtfelds, also links oder rechts suchen. Ein Flaggschiff kann zusätzlich auftauchen.
4. **Planetenkampf**: Die Zerstörer schweben über Städten und bombardieren sie. Im Scanner blinkt die bombardierte Stadt. Sind alle Zerstörer vernichtet, ist der Planet gerettet.
5. **Raumstation**: Andocken, auftanken (10 %/s in 5-%-Schritten) und **Bomben nachladen**. Wird die Station angegriffen, erst die Fighter vernichten.
6. **Feindsystem**: Siehe nächster Abschnitt.

## Das Feindsystem (taktischer Teil)

- **Hinspringen**: Galaxie oben links auf der Karte wählen. Hin- und Rücksprung kosten **je 20 % Energie** und dauern **dreimal so lange** (roter Hyperraum).
- **Empfangskomitee**: Bei *jedem* Sprung hinein warten **12 Fighter in 4 Wellen**. Sie schießen doppelt so oft und mit Doppelschuss. Zerstörer und Flaggschiffe sind nicht dabei. Solange das Komitee kämpft, ist auf der Karte nur der Rücksprung möglich. Danach herrscht Ruhe am Sprungpunkt.
- **Feindkarte**: Stern Vorrhal und 5 Planeten. Die Heimatwelt Xhal liegt innen und hat 12 Städte. Die 4 äußeren Planeten (Kethra, Uzhul, Drauth, Myrrax) haben je 6–8 Städte. Unten rechts liegt der **Rücksprungpunkt** nach Helion, als Symbol dient unser Stern. Sprünge innerhalb des Feindsystems kosten wie gewohnt 3–15 % je nach Entfernung.
- **Schwadron-Nachschub**: Von den äußeren Planeten starten sichtbar neue Schwadrone (Ring „START!“). Sie fliegen zum Sprungpunkt und springen ins Helion-System, sofern dort weniger als 4 unterwegs sind, sonst warten sie. Diese Schwadrone haben Zerstörer und eventuell ein Flaggschiff. Du kannst sie anwählen und **abfangen**.
- **Produktion**: Jede zerstörte Stadt auf einem äußeren Planeten verlangsamt den Nachschub spürbar (+15 % Abstand je Stadt). Ohne Städte auf den äußeren Planeten kommen **keine neuen Schwadrone** mehr. Die Heimatwelt baut keine Schwadrone.
- **Feindplaneten angreifen**: Die Städte werden von Fightern verteidigt. Außenplaneten haben 9–12, die Heimatwelt 18. Sie kommen in Dreierwellen und **regenerieren sich nicht**.
- **Bomben**: Du hast **15 Bomben**. Auf Feindplaneten wechselst du mit **Q / Tab** (Gamepad X) zwischen Bordlaser und Bomben. Im Bombenmodus neigt sich der Blick leicht nach unten. Eine **Aufschlagmarke** am Boden zeigt, wo eine jetzt abgeworfene Bombe einschlägt. Die Bombe fällt ballistisch und fliegt umso weiter, je schneller du fliegst (ca. 55–140 m voraus).
  - Wird die Marke grün, liegt eine Stadt im Trefferkreis: FEUER.
  - **1 Treffer zerstört eine Stadt** und bringt **5000 Punkte**. Ein Fehlwurf ist verloren.
  - „BOMBE UNTERWEGS“ heißt, auf diese Stadt fällt schon eine Bombe.
  - Bomben gibt es nur beim Andocken an **eigenen Stationen** (wie Energie). Du musst also zurückspringen.

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
| Waffe wechseln (bei manueller Waffenwahl; auf Feindplaneten immer: Bordlaser / Bomben) | Q, Tab | X, RB |
| Karte: Ziel wählen / springen | Pfeile, Maus / Enter, Klick | Stick / A |
| Karte: anderes System ansehen (nur Beobachtung) | Q, Tab | X |
| Pause | Esc, P | Start |
| Vollbild | F11 | – |

## Testfunktionen (für die Abnahme der Etappen)

| Taste | Funktion |
|---|---|
| F1 | Hilfe zu den Testtasten ein-/ausblenden |
| F2 | Energie +50 % und Bomben auffüllen |
| F3 | sofort ein neues Schwadron |
| F4 | Orbit-Kampf bzw. Empfangskomitee überspringen |
| F5 | alle Gegner im aktuellen Kampf vernichten |
| F6 | Schwadron auf einem Planeten landen lassen und direkt dorthin springen (Planetenkampf testen) |
| F7 | Strategiezeit ×4 (Schwadrone bewegen sich schneller) |
| F8 | Direkt ins Feindsystem (Empfangskomitee) |
| F9 | Game Over auslösen (Highscore testen) |
| F10 | Energie −20 % (Warnton und Tanken testen) |
| F12 | Screenshot (im Benutzerordner) |

Abschalten über `debug_keys_enabled=false` in der `balance.cfg` (siehe unten).

Testszenarien über die Kommandozeile (`StarfighterDefense -- --test=…`):

| Szenario | Inhalt |
|---|---|
| `enemy` | Sprung ins Feindsystem mit Empfangskomitee |
| `enemy_planet` | Feindplanet, `--planet=0…4` (0 = Heimatwelt), `--nodefenders` ohne Verteidiger |
| `victory` | Heimatwelt mit nur noch einer Stadt (Sieg testen) |
| `enemy_map` | Feindkarte mit startenden Schwadronen |
| `evaluation` | Auswertungsbildschirm, `--end=victory\|abort\|gameover` |

Mit `-- --autoplay --raid` greift der automatische Testfahrer auch das Feindsystem an. Optionen: `--human` und `--raid_target=auto|home|outer`.

## Auswertung

Am Ende jeder Partie (Sieg, Game Over oder Abbruch über *Pause → Spiel beenden*) zeigt das Spiel:
- zerstörte Fighter, abgeschossene Zerstörer, vernichtete Flaggschiffe und zerbombte Feindstädte, jeweils mit den erzielten Punkten,
- verlorene eigene Städte und die Spielzeit,
- Boni, vernichtete Schwadrone, Bombentreffer, Sprünge und erreichte Stufe.

Jede Auswertung wird zusätzlich als Zeile an **`auswertungen.csv`** im Benutzerordner angehängt (Semikolon-getrennt, für Excel/LibreOffice). So lassen sich Punktzahlen verschiedener Taktiken vergleichen.

## Spielwerte anpassen (ohne neu zu exportieren)

Alle Balancing-Werte stehen zentral in `scripts/autoload/config.gd`, jeweils markiert mit **[ORIGINAL]**, **[VERMUTET]** oder **[FREI]**.
Zum Ändern ohne Neuexport legst du eine Datei **`balance.cfg`** neben die ausführbare Datei:

```ini
[balance]
fighter_damage=2.0
bombard_time=14.0
single_destroyer_stops=false
orbit_fighter_count=12
enemy_home_defenders=30
enemy_home_burst_shots=2
enemy_production_slowdown=0.25
bomb_hit_radius=18.0
```

Eine Vorlage mit allen Werten schreibt das Spiel beim Start nach `balance_template.cfg` im Benutzerordner:
- Windows: `%APPDATA%\StarfighterDefense\`
- Linux: `~/.local/share/StarfighterDefense/`

Dort liegen auch `highscores.json` und `settings.cfg`.

Einige Optionen lassen sich auch direkt im Spiel umschalten (Optionen): automatische Waffenwahl, 9/12 Fighter im Orbit, die [VERMUTET]-Regel „Schwadron mit nur einem Zerstörer bleibt zeitweise stehen“, Schwierigkeit, Scanner-Ausrichtung, Randpfeile und Retro-Filter.

## Änderungen in Version 0.10.0 – Feindsystem

- **Feindsystem Vorrhal** ist spielbar: Sprung über die Galaxie oben links, je 20 % Energie hin und zurück, dreifache Sprungdauer, roter Hyperraum.
- **Empfangskomitee** bei jedem Sprung hinein: 12 aggressive Fighter in 4 Wellen.
- **Feindkarte** mit 5 Planeten (insgesamt 36–44 Städte), startenden Schwadronen, Produktionsanzeige und Rücksprungpunkt. Auf der Karte schaltet **Q/Tab** zwischen den beiden Systemen um (nur Ansicht).
- **Bomben**: 15 Stück, ballistischer Abwurf mit Aufschlagmarke und Flugbahn, 1 Treffer je Stadt, 5000 Punkte. Nachladen nur an eigenen Stationen.
- **Verteidiger** der Feindplaneten ohne Regeneration: 9–12, auf der Heimatwelt 18.
- **Nachschub** des Feindes kommt von den äußeren Planeten. Jede zerstörte Stadt verlangsamt ihn, ohne Städte dort stoppt er ganz. Schwadrone im Feindsystem lassen sich abfangen.
- **Sieg**, sobald alle Städte der Heimatwelt zerstört sind, mit Siegsequenz und Siegesmusik.
- **Auswertung** bei Sieg, Game Over und Abbruch. Zusätzlich wird `auswertungen.csv` geschrieben. Siege sind in der Highscore-Liste markiert.
- Neue Modelle (außerirdische Städte und Ruinen, Bombe), Planetentexturen, Himmel und Kartenhintergrund des Feindsystems, neue Klänge (Bomben, Langsprung, Stadtzerstörung, Waffenwechsel) und Musik (Sieg, Einsatzbesprechung).
- Alle neuen Werte stehen in `config.gd` (Abschnitte „Feindsystem“ und „Bomben“).

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

- **Militär-Rang und Siegbonus** folgen nach deinen Tests. Vorgesehen ist `bonus_victory` in `config.gd`, derzeit 0.
- **Balance-Hinweis**: Ein direkter Angriff auf die Heimatwelt gleich nach dem Orbit-Start ist möglich. Testläufe haben so nach 2–4 Minuten gewonnen. Wer das schwerer haben möchte, kann z. B. `enemy_home_defenders`, `enemy_home_fire_rate_factor` oder `enemy_home_burst_shots` erhöhen.

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
