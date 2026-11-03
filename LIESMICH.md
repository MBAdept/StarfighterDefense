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
**Gewonnen** hast du, sobald **alle Städte im Feindsystem** zerbombt sind. Das sind 36–44 Städte auf 5 Planeten und braucht mehrere Angriffe.
**Verloren** hast du, wenn deine Energie auf 0 fällt oder alle eigenen Städte zerstört sind.
Am Ende steht immer eine **Auswertung**: bei Sieg, Game Over und vorzeitigem Abbruch. Dazu gibt es eine lokale Highscore-Liste.

1. **Orbit-Start**: Wehre über dem Heimatplaneten Halcyon 9 (oder 12) Fighter in Dreierwellen ab. Danach ist die Karte freigeschaltet.
2. **Systemkarte (Leertaste)**: Ziel wählen (Planet, Station, Schwadron) und springen. Ein Sprung kostet Energie, je weiter, desto mehr (2,5–12 %).
3. **Weltraumkampf**: Erst die Fighter (Bordlaser), danach die Zerstörer nacheinander (Ionen-Kanone). Sie stehen knapp außerhalb des Sichtfelds, also links oder rechts suchen. Ein Flaggschiff kann zusätzlich auftauchen.
4. **Planetenkampf**: Die Zerstörer schweben über Städten und bombardieren sie. Im Scanner blinkt die bombardierte Stadt. Sind alle Zerstörer vernichtet, ist der Planet gerettet.
5. **Raumstation**: Andocken, auftanken (10 %/s in 5-%-Schritten) und **Bomben nachladen**. Wird die Station angegriffen, erst die Fighter vernichten.
6. **Feindsystem**: Siehe nächster Abschnitt.

## Das Feindsystem (taktischer Teil)

- **Hinspringen**: Galaxie oben links auf der Karte wählen. Hin- und Rücksprung kosten **je 20 % Energie** und dauern **dreimal so lange** (roter Hyperraum).
- **Empfangskomitee**: Beim ersten Sprung hinein warten **12 Fighter in 4 Wellen**. Sie schießen doppelt so oft und mit Doppelschuss. Zerstörer und Flaggschiffe sind nicht dabei. Solange das Komitee kämpft, ist auf der Karte nur der Rücksprung möglich.
  - Es gibt **nur ein Empfangskomitee**: Abgeschossene Fighter kommen nicht wieder. Wer vorher zurückspringt, trifft beim nächsten Mal nur noch auf den Rest.
  - Sind alle 12 vernichtet, bleibt der Sprungpunkt dauerhaft frei. Mit `reception_once=false` kommt das Komitee wieder bei jedem Sprung.
- **Feindkarte**: Stern Vorrhal und 5 Planeten. Die Heimatwelt Xhal liegt innen und hat 12 Städte. Die 4 äußeren Planeten (Kethra, Uzhul, Drauth, Myrrax) haben je 6–8 Städte. Unten rechts liegt der **Rücksprungpunkt** nach Helion, als Symbol dient unser Stern. Sprünge innerhalb des Feindsystems kosten wie gewohnt 2,5–12 % je nach Entfernung.
- **Schwadron-Nachschub**: Von den äußeren Planeten starten sichtbar neue Schwadrone (Ring „START!“). Sie fliegen zum Sprungpunkt und springen ins Helion-System, sofern dort weniger als 4 unterwegs sind, sonst warten sie. Diese Schwadrone haben Zerstörer und eventuell ein Flaggschiff. Du kannst sie anwählen und **abfangen**.
- **Produktion**: Jede zerstörte Stadt auf einem äußeren Planeten verlangsamt den Nachschub spürbar (+15 % Abstand je Stadt). Ohne Städte auf den äußeren Planeten kommen **keine neuen Schwadrone** mehr. Die Heimatwelt baut keine Schwadrone.
- **Feindplaneten angreifen**: Die Städte werden von Fightern verteidigt. Außenplaneten haben 9–12, die Heimatwelt 18. Sie kommen in Dreierwellen dicht hintereinander und **regenerieren sich nicht**.
  - Die Verteidiger nehmen dein Schiff so heftig unter Beschuss, dass zum Bomben keine Zeit bleibt: 2,5-fache Feuerrate mit Doppelschuss, auf der Heimatwelt sogar 3-fach.
  - Also erst die Verteidiger mit dem Bordlaser abwehren, dann bombardieren.
  - Ist der Verteidiger-Bestand vernichtet, trifft trotzdem **gelegentlich Verstärkung** ein: 1–3 Fighter, etwa alle 14–26 s, solange der Planet noch Städte hat. Durchbomben ohne Unterbrechung geht also nicht.
- **Bomben**: Du hast **10 Bomben**, das reicht für etwa einen äußeren Planeten pro Angriff. Auf Feindplaneten wechselst du mit **Q / Tab** (Gamepad X) zwischen Bordlaser und Bomben. Im Bombenmodus neigt sich der Blick leicht nach unten. Eine **Aufschlagmarke** am Boden zeigt, wo eine jetzt abgeworfene Bombe einschlägt. Die Bombe fällt ballistisch und fliegt umso weiter, je schneller du fliegst (ca. 55–140 m voraus).
  - Wird die Marke grün, liegt eine Stadt im Trefferkreis: FEUER.
  - **1 Treffer zerstört eine Stadt** und bringt **5000 Punkte**. Ein Fehlwurf ist verloren.
  - „BOMBE UNTERWEGS“ heißt, auf diese Stadt fällt schon eine Bombe.
  - Bomben gibt es nur beim Andocken an **eigenen Stationen** (wie Energie). Du musst also zurückspringen.

Tipps:
- **Zerstörer**: blau = 2 Treffer, grün = 3, rot = 4. Jeder Treffer nimmt eine Schildschicht weg. Getroffen wird nur die sichtbare Schildblase.
  - Zerstörer schwanken stark hin und her und **weichen anfliegenden Ionen-Kugeln oft blitzschnell aus**: blaue und grüne häufiger, rote seltener (die schwanken dafür am stärksten). Nicht jeder Schuss sitzt, also dranbleiben.
  - Auf Planeten weichen sie nicht aus.
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
| `victory` | Nur noch eine einzige Feindstadt im System, auf `--planet=N`, Standard Heimatwelt (Sieg testen) |
| `enemy_map` | Feindkarte mit startenden Schwadronen |
| `evaluation` | Auswertungsbildschirm, `--end=victory\|abort\|gameover` |

Mit `-- --autoplay --raid` greift der automatische Testfahrer auch das Feindsystem an. Optionen:
- `--human`: menschenähnlicher Testfahrer
- `--raid_target=auto|home|outer`: Wahl der Angriffsziele
- `--raid_safe`: „Verteidigung zuerst“. Er greift nur an, wenn in Helion länger keine Landung droht, und springt sofort zurück, sobald eine Landung näher rückt.
- `--raid_intercept`: Er fängt startende Schwadrone schon im Feindsystem ab.

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
bombs_max=12
enemy_defender_fire_rate_factor=2.0
enemy_production_slowdown=0.25
victory_all_enemy_cities=false
```

Eine Vorlage mit allen Werten schreibt das Spiel beim Start nach `balance_template.cfg` im Benutzerordner:
- Windows: `%APPDATA%\StarfighterDefense\`
- Linux: `~/.local/share/StarfighterDefense/`

Dort liegen auch `highscores.json` und `settings.cfg`.

Einige Optionen lassen sich auch direkt im Spiel umschalten (Optionen): automatische Waffenwahl, 9/12 Fighter im Orbit, die [VERMUTET]-Regel „Schwadron mit nur einem Zerstörer bleibt zeitweise stehen“, Schwierigkeit, Scanner-Ausrichtung, Randpfeile und Retro-Filter.

## Änderungen in Version 0.10.2 (nach dem zweiten Spieltest)

- **Empfangskomitee nur einmal**: Die 12 Fighter am Sprungpunkt des Feindsystems gibt es nur ein einziges Mal. Abgeschossene kommen nicht wieder. Wer vorher zurückspringt, trifft beim nächsten Mal nur noch auf den Rest. Danach ist der Sprungpunkt frei (`reception_once`).
- **Zerstörer-Meldung ohne Farbe**: Das Popup sagt nur noch „ZERSTÖRER“ und die Richtung („<< LINKS“ / „RECHTS >>“).
- **Zerstörer deutlich schwerer zu treffen** (der gravierendste Punkt):
  - Die Trefferzone ist jetzt die sichtbare Schildblase statt einer großzügigen Kugel (`destroyer_hitbox_scale=0.9`, `ion_hit_tolerance` 2,5 → 1,0).
  - Sie stehen weiter weg (88 → 110 m) und schwanken weiter und schneller hin und her.
  - **Sie weichen anfliegenden Ionen-Kugeln aus**, nach nur 0,04–0,12 s: blau mit 62 %, grün mit 56 %, rot mit 32 % Wahrscheinlichkeit (`destroyer_dodge_chance`).
  - Gemessen mit dem menschenähnlichen Testfahrer: Die Ionen-Kanone trifft noch etwa jedes zweite Mal (vorher fast immer). Ein Zerstörer hält etwa doppelt so lange durch.
- **Fighter schwerer zu treffen**: kleinere Trefferzone (3,6 → 2,9 m, Laser-Toleranz 1,4 → 0,6 m). Sie kreisen schneller und weiter ums Fadenkreuz.
- **Kämpfe dauern länger**: Ein Schwadron dauert im Schnitt etwa 70 s statt 45 s.
- **Weniger Schaden je Kampf**:
  - Fighter-Treffer kosten 1,3 % statt 1,8 %.
  - Zerstörer-Treffer kosten 5,5 / 6,5 / 7,5 % statt 9 / 11 / 13 %. Zerstörer feuern etwas seltener (alle 11 / 10 / 9 s).
  - Das Flaggschiff kostet 20 % statt 35 % und pausiert länger nach dem Schuss.
  - Gemessen: Ein Schwadron kostet trotz längerer Kämpfe im Schnitt etwa 19 statt 29 Prozentpunkte Energie.
  - Die Senkung gilt den Kämpfen gegen Schwadrone. Die Fighter im Feindsystem (Empfangskomitee, Verteidiger, Verstärkung) kosten 1,6 % je Treffer (`enemy_fighter_damage`). Weil sie jetzt schwerer zu treffen sind und länger leben, ist das Bomben unter Beschuss damit so gefährlich wie in 0.10.1.
- **Sprünge günstiger**: 2,5–12 % statt 3–15 % je nach Entfernung. Sprung ins Feindsystem und zurück bleibt bei 20 %.
- **Zielerfassung ehrlich**: Grünes Fadenkreuz, pulsierende Zielklammer und Lock-Ton gibt es nur noch, wenn ein Schuss in Blickrichtung jetzt treffen kann.
  - Beim Zerstörer heißt das: in der Schildblase und in Reichweite der Ionen-Kugel (760 m). Die Zielklammer sitzt auf der Schildblase.
  - Bei Fightern gilt die Laser-Reichweite (420 m).
  - Beim Flaggschiff entspricht der Lock dem Trefferradius des rosa Quadrats. Schüsse, die durch das Quadrat führen, prallen nicht mehr an der Rumpfkante davor ab. Vorher hing das von der Bildrate ab: Bei 240 Hz prallte ein Großteil der Schüsse ab.
- **Ausweichen nur bei echter Gefahr**: Zerstörer weichen nur Kugeln aus, die sie treffen würden oder knapp verfehlen (vorgehaltene Schüsse eingeschlossen), und immer vom Schuss weg. Sie springen also nie mehr in einen Fehlschuss hinein (`destroyer_dodge_threat`). Gemessen bleibt die Trefferquote der Ionen-Kanone praktisch gleich (41 % statt 42 %).
- **Zerstörer auf Planeten fair**: Weil man dort nicht nach oben oder unten zielen kann, zählt nur noch die waagerechte Lage. Vorher hing die Trefferbreite vom Schaukeln des Zerstörers ab. Mit der Breite 0,7 (`destroyer_planet_hit_scale`) bleiben Planetenkämpfe im Schnitt gleich schwer: gemessen 62 % Ionen-Treffer statt 63 %, 26 s statt 27 s je Kampf.
- **Verstärkung sichtbar**: Bei Verstärkung auf Feindplaneten setzt die Kampfmusik ein, und das Lagefeld zeigt „VERSTÄRKUNG n“.
- **Bildrate höchstens 240 fps** (`max_fps`): Das schont die Grafikkarte, wenn VSync aus ist. Außerdem hält es einen seltenen Absturz im Audio-Mischthread der Godot-Engine fern, der nur bei extrem hohen Bildraten auftritt. In den beschleunigten Testläufen traf er etwa 1 von 100 Partien.
- Testtaste F4 im Empfangskomitee: Das Komitee gilt danach wirklich als erledigt.
- **Verstärkung auf Feindplaneten**: Sind die Verteidiger vernichtet, treffen gelegentlich 1–3 Fighter nach (etwa alle 14–26 s), solange der Planet noch Städte hat. Ein Planet lässt sich nicht mehr in einem Zug „durchbomben“ (`enemy_reinforce_*`).
- Alle Werte stehen in `config.gd`, jeweils mit dem alten Wert als Kommentar („bis 0.10.1: …“). Per `balance.cfg` lassen sie sich zurückdrehen, siehe `balance_beispiel.cfg`.

## Änderungen in Version 0.10.1

- **Sieg erst, wenn alle Städte im Feindsystem zerstört sind**, nicht mehr nur die der Heimatwelt (`victory_all_enemy_cities`).
- **Verteidiger feuern heftig**: 2,5-fache Feuerrate mit Doppelschuss, Heimatwelt 3-fach. Die Wellen folgen nach 1 s statt nach 3,7 s. Zwischen den Wellen bleibt kaum Zeit zum Bomben.
- **10 Bomben** statt 15: Eine Ladung reicht für einen äußeren Planeten (6–8 Städte), aber nicht mehr für die Heimatwelt Xhal (12 Städte) und schon gar nicht für das ganze System (36–44 Städte).
- Alle drei Regeln stehen in `config.gd` und lassen sich per `balance.cfg` ändern (siehe `balance_beispiel.cfg`).

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
- **Sieg ohne Städteverlust ist möglich** (Endstand 0.10.2): Mit der Strategie „Verteidigung zuerst“ (`--raid_safe`) gewann der menschenähnliche Testfahrer 9 von 10 Partien, 7 davon ohne eine einzige verlorene eigene Stadt (sonst 1 bzw. 3). Er brauchte 15–35 Minuten, im Schnitt 24. Einmal ging ihm früh die Energie aus: Ein Flaggschiff traf ihn dreimal, und er floh zu spät. Der perfekte Testfahrer brauchte 8–11 Minuten.
  - Mit Sturmangriff (`--raid`) gewann der menschenähnliche Testfahrer 5 von 6 Partien in 12–17 Minuten, verlor dabei aber 5–16 eigene Städte. Einmal ging ihm nach 9,5 Minuten die Energie aus.
  - Die Gesamtspielzeit liegt damit etwa auf dem Niveau von 0.10.1 oder leicht darüber: Die Kämpfe dauern länger, dafür entfallen die wiederholten Empfangskomitees.
- **Balance** (ab 0.10.1): Für den Sieg müssen alle Feindstädte fallen, mit 10 Bomben je Anflug und heftig feuernden Verteidigern. Ein Sturmangriff gleich zu Beginn reicht damit nicht mehr. Feinjustierung über `enemy_defender_fire_rate_factor`, `enemy_defender_burst_shots`, `enemy_defender_wave_delay` und `bombs_max`.

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
