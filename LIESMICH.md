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
**Gewonnen** hast du, sobald **alle Städte im Feindsystem** zerbombt sind. Je nach Schwierigkeitsstufe sind das 36–44 Städte auf 5 Planeten (Fortgeschritten: über 80) und braucht mehrere Angriffe.
Auf **Hart** und **Experte** greift im Lauf der Partie ein **zweites Feindsystem** an, **Ixmora** (Galaxie unten rechts). Gewonnen ist dann erst, wenn auch dort alle Städte zerbombt sind.
**Verloren** hast du, wenn deine Energie auf 0 fällt oder alle eigenen Städte zerstört sind.
Am Ende steht immer eine **Auswertung**: bei Sieg, Game Over und vorzeitigem Abbruch. Dazu gibt es lokale Highscore-Listen, eine je Schwierigkeitsstufe.

1. **Orbit-Start**: Wehre über dem Heimatplaneten Halcyon 9 (oder 12) Fighter in Dreierwellen ab. Danach ist die Karte freigeschaltet.
2. **Systemkarte (Leertaste)**: Ziel wählen (Planet, Station, Schwadron) und springen. Ein Sprung kostet Energie, je weiter, desto mehr (2,5–12 %).
3. **Weltraumkampf**: Erst die Fighter (Bordlaser), danach die Zerstörer nacheinander (Ionen-Kanone). Sie stehen knapp außerhalb des Sichtfelds, also links oder rechts suchen. Ein Flaggschiff kann zusätzlich auftauchen.
4. **Planetenkampf**: Die Zerstörer schweben über Städten und bombardieren sie. Im Scanner blinkt die bombardierte Stadt. Sind alle Zerstörer vernichtet, ist der Planet gerettet.
5. **Raumstation**: Andocken, auftanken (10 %/s in 5-%-Schritten), **Bomben nachladen** und **Systemschäden reparieren**. Wird die Station angegriffen, erst die Fighter vernichten. Stationen sind **besetzbar, aber nicht zerstörbar** (ab 0.14.2): Fällt die Integrität einer angegriffenen Station auf 0 %, ist sie **besetzt**. Die Fighter bleiben dort, Tanken, Bomben und Reparatur gibt es dort nicht mehr. Vernichtest du die Fighter, ist die Station befreit und wieder voll einsatzbereit.
6. **Stern** (Helion, Vorrhal bzw. Ixmora, Kartenmitte): Energie fast sofort auffüllen, aber schnell wieder weg. Siehe „Sterne und Systemschäden“.
7. **Feindsystem**: Siehe nächster Abschnitt.

## Das Feindsystem (taktischer Teil)

- **Hinspringen**: Galaxie oben links auf der Karte wählen. Hin- und Rücksprung kosten **je 20 % Energie** und dauern **dreimal so lange** (roter Hyperraum).
- **Empfangskomitee**: Beim ersten Sprung hinein warten **12 Fighter in 4 Wellen**. Sie schießen doppelt so oft und mit Doppelschuss. Zerstörer und Flaggschiffe sind nicht dabei. Solange das Komitee kämpft, ist auf der Karte nur der Rücksprung möglich.
  - Es gibt **nur ein Empfangskomitee**: Abgeschossene Fighter kommen nicht wieder. Wer vorher zurückspringt, trifft beim nächsten Mal nur noch auf den Rest.
  - Sind alle 12 vernichtet, bleibt der Sprungpunkt dauerhaft frei. Mit `reception_once=false` kommt das Komitee wieder bei jedem Sprung.
- **Feindkarte**: Stern Vorrhal und 5 Planeten. Die Heimatwelt Xhal liegt innen und hat 12 Städte. Die 4 äußeren Planeten (Kethra, Uzhul, Drauth, Myrrax) haben je 6–8 Städte. Auf Fortgeschritten sind es 20 bzw. 15–17. Unten rechts liegt der **Rücksprungpunkt** nach Helion, als Symbol dient unser Stern. Sprünge innerhalb des Feindsystems kosten wie gewohnt 2,5–12 % je nach Entfernung.
- **Schwadron-Nachschub**: Von den äußeren Planeten starten sichtbar neue Schwadrone (Ring „START!“). Sie fliegen zum Sprungpunkt und springen ins Helion-System, sofern dort weniger als 6 unterwegs sind (bis 0.12.0: 4), sonst warten sie. Diese Schwadrone haben Zerstörer und eventuell ein Flaggschiff. Du kannst sie anwählen und **abfangen**.
- **Produktion**: Jede zerstörte Stadt auf einem äußeren Planeten verlangsamt den Nachschub spürbar. Gezählt wird der Anteil der zerstörten äußeren Städte: Bei 28 äußeren Städten sind das +15 % Abstand je Stadt. Bei mehr Städten wirkt jede einzelne schwächer, bei weniger stärker. Ohne Städte auf den äußeren Planeten kommen **keine neuen Schwadrone** mehr. Die Heimatwelt baut keine Schwadrone.
- **Feindplaneten angreifen**: Die Städte werden von Fightern verteidigt. Außenplaneten haben 9–12, die Heimatwelt 18. Sie kommen in Dreierwellen dicht hintereinander und **regenerieren sich nicht**.
  - Die Verteidiger nehmen dein Schiff so heftig unter Beschuss, dass zum Bomben keine Zeit bleibt: 2,5-fache Feuerrate mit Doppelschuss, auf der Heimatwelt sogar 3-fach.
  - Also erst die Verteidiger mit dem Bordlaser abwehren, dann bombardieren.
  - Ist der Verteidiger-Bestand vernichtet, trifft trotzdem **gelegentlich Verstärkung** ein: 1–3 Fighter, etwa alle 14–26 s, solange der Planet noch Städte hat. Durchbomben ohne Unterbrechung geht also nicht.
- **Bomben**: Du hast **10 Bomben**, das reicht für etwa einen äußeren Planeten pro Angriff (auf Fortgeschritten für gut die Hälfte). Auf Feindplaneten wechselst du mit **Q / Tab** (Gamepad X) zwischen Bordlaser und Bomben. Im Bombenmodus neigt sich der Blick leicht nach unten. Eine **Aufschlagmarke** am Boden zeigt, wo eine jetzt abgeworfene Bombe einschlägt. Die Bombe fällt ballistisch und fliegt umso weiter, je schneller du fliegst (ca. 55–140 m voraus).
  - Wird die Marke grün, liegt eine Stadt im Trefferkreis: FEUER.
  - **1 Treffer zerstört eine Stadt** und bringt **5000 Punkte**. Ein Fehlwurf ist verloren.
  - „BOMBE UNTERWEGS“ heißt, auf diese Stadt fällt schon eine Bombe.
  - Bomben gibt es nur beim Andocken an **eigenen Stationen** (wie Energie). Du musst also zurückspringen.

Tipps:
- **Zerstörer**: blau = 2 Treffer, grün = 3, rot = 4. Jeder Treffer nimmt eine Schildschicht weg. Getroffen wird nur die sichtbare Schildblase.
  - Zerstörer schwanken stark hin und her (rote am stärksten). Nicht jeder Schuss sitzt, also dranbleiben. Die plötzlichen Ausweichmanöver vor Ionen-Kugeln gibt es seit 0.12.0 nicht mehr (`destroyer_dodge_chance`).
- **Flaggschiff**: Nur das rosa Quadrat ist verwundbar, und nur kurz vor dem eigenen Schuss, wenn es weiß-rosa leuchtet. Die Ionen-Kugel braucht Flugzeit, also leicht vorher feuern!
- **Ausweichen**: Wer im Moment des Einschlags kräftig lenkt (auf Planeten: schnell fliegt), halbiert die Trefferchance des Gegners. Laser können anfliegende Geschosse auch abschießen.
- **Taktik**: Kleinere Schwadrone fliegen langsamer. Ein angeschlagenes Schwadron zu verlangsamen kann klüger sein, als es ganz auszulöschen.

## Das zweite Feindsystem Ixmora (Hart und Experte, ab 0.14.0)

- **Wann es angreift**:
  - **Hart**: sobald Vorrhal **keine Schwadrone mehr bauen** kann, also alle Städte auf den äußeren Planeten Vorrhals zerstört sind.
  - **Experte**: zusätzlich schon dann, wenn im Helion-System **erstmals 60 Sekunden lang höchstens ein feindliches Schwadron** unterwegs ist (0.14.0: ohne jedes Schwadron). Was zuerst eintritt, gilt. Ist Helion so weit frei, zählt die Karte die Zeit bis zum Angriff herunter.
- **Ankündigung**: Funkmeldung „ALARM: Ein zweites Feindsystem greift an“, kurzer Alarm und ein Banner im Cockpit. Bei offener Karte oder mitten im Hyperraumsprung kommen Banner und Alarm, sobald du wieder im Cockpit bist. Bei gestörter Kommunikation kann die Meldung verstümmelt sein oder fehlen. Die Karte zeigt den neuen Sprungpunkt trotzdem.
- **Lage**: Galaxie **unten rechts** auf der Systemkarte, gegenüber von Vorrhal. Erreichbar **nur über Helion**: Es gibt keinen Sprung direkt zwischen Vorrhal und Ixmora. Hin- und Rücksprung kosten wie bei Vorrhal je 20 % und dauern dreimal so lange (violetter Hyperraum).
- **Ixmora**: blauer Stern, **4 Planeten**: Heimatwelt **Thurxa** mit 12 Städten, dazu **Ilvesh** (Gletscherwelt), **Gorrakh** (Magmawelt) und **Seyth** (Leuchtwelt) mit je 8–10 Städten, zusammen 36–42 (0.14.0: rund 68). Das Einsatzgebiet hat die normale Größe. Der Rücksprungpunkt nach Helion liegt dort **oben links**.
- **Tempo**: Auf Hart und Experte fliegen die Schwadrone **in Helion 10 % schneller**, in Vorrhal normal und **in Ixmora 20 % langsamer** zum Sprungpunkt (0.14.0: überall 10 % schneller).
- **Kein Empfangskomitee.** Verteidiger, Verstärkung, Bomben und Produktion funktionieren wie in Vorrhal. Am Stern Ixmora kann man ebenfalls schnell tanken.
- **Gemeinsame Grenze**: Beide Feindsysteme teilen sich die Grenze von **6 Schwadronen im Helion-System**. Warten an beiden Sprungpunkten Schwadrone, springt zuerst, wer am längsten wartet. Schwadrone aus Ixmora tauchen in Helion unten rechts auf.
- **Q/Tab auf der Karte** blättert durch Helion, Vorrhal und Ixmora (nur Ansicht). Springen kannst du nur im eigenen System.
- Die Auswertung zeigt, wann Ixmora angriff und wie viele seiner Städte zerbombt wurden.

## Schwierigkeitsstufen (ab 0.13.0)

Die Stufe wählst du unter **Optionen → Schwierigkeit**. Das Titelbild zeigt die gewählte Stufe an. Die Stufen unterscheiden sich vor allem in der Menge an Arbeit bis zum Sieg und damit in der Spieldauer. Jede Stufe hat eine **eigene Highscore-Liste**. Mit ◀ ▶ bzw. Links/Rechts wechselst du zwischen den Listen.

| Stufe | Schwadrone zu Beginn | Städte je Feindplanet | Besonderheit |
|---|---|---|---|
| Kinderspiel | 2 | 6–8, Heimatwelt 12 | weniger Gegnerschaden (75 %), Schwadrone langsamer und seltener (bis 0.12.0 „Leicht“) |
| Anfänger | 2 | 6–8, Heimatwelt 12 | wie bis 0.12.0 „Normal“ |
| Normal | 3 | 6–8, Heimatwelt 12 | – |
| Fortgeschritten | 4 | 15–17, Heimatwelt 20 | Städte weiter über die Oberfläche verteilt: Radius des Einsatzgebiets 45 % größer |
| Hart (ab 0.14.0) | 4 | Vorrhal 15–17, Heimatwelt 20; Ixmora 8–10, Heimatwelt 12 | wie Fortgeschritten, Schwadrone in Helion 10 % schneller. Kann Vorrhal keine Schwadrone mehr bauen, greift Ixmora an |
| Experte (ab 0.14.0) | 4 | wie Hart | wie Hart, Ixmora greift aber schon an, sobald in Helion erstmals 60 s lang höchstens ein Schwadron unterwegs ist |

- In **allen Stufen** sind jetzt bis zu **6 Schwadrone** gleichzeitig im Helion-System unterwegs (bis 0.12.0: 4).
- Die Nachschub-Bremse richtet sich nach dem **Anteil** zerstörter Städte auf den äußeren Feindplaneten. Bei 28 äußeren Städten wirkt sie wie bisher (+15 % Abstand je Stadt), bei mehr Städten wirkt jede einzelne entsprechend schwächer, bei weniger stärker.
- Die Stufe gilt für die ganze Partie und lässt sich nur im Hauptmenü ändern. Im Spiel ist sie in den Optionen gesperrt, denn die Punkte zählen für die Highscore-Liste der Stufe, mit der die Partie begann.
- Die bisherige Stufe „Schwer“ (130 % Gegnerschaden) entfällt. Wer sie gespeichert hatte, spielt jetzt „Normal“.
- Auf **Hart** und **Experte** gilt der Sieg erst, wenn die Städte **beider** Feindsysteme zerbombt sind, zusammen rund 120.
- Die bisherige Highscore-Liste (eine für alle) steht jetzt unter **Anfänger**, das war der bisherige Standard „Normal“.
- Eine `balance.cfg` geht den Stufen vor, wenn sie einen Wert **abweichend vom Standard** setzt. Setzt sie z. B. `initial_squadrons=5`, gilt das in jeder Stufe. Eine unveränderte Kopie der `balance_template.cfg` schaltet die Stufen dagegen nicht ab.

## Sterne und Systemschäden (ab 0.12.0)

**Stern – Schnelltanken**
- In der Mitte jeder Systemkarte liegt ein Stern: **Helion**, **Vorrhal** bzw. (Hart/Experte) **Ixmora**. Er lässt sich wie jedes andere Ziel anspringen.
- Am Stern füllt sich die Energie **fast sofort**: 25 % pro Sekunde, von 0 auf 100 % in 4 Sekunden.
- Er **repariert nichts** und lädt **keine Bomben** nach. Das geht nur an Stationen.
- Gleichzeitig steigt die **Hitze**. Nach **10 Sekunden** verglüht das Schiff (Game Over). Ab 60 % Hitze gibt es Warntöne und rote Anzeigen, auch auf der Karte.
- Die Hitze steigt **auch bei offener Karte** weiter. Also Ziel wählen und sofort springen.
- Ab dem Absprung ist die Hitze vorbei.
- Im Feindsystem spart der Stern Vorrhal den teuren Rücksprung, solange noch Bomben an Bord sind.

**Systemschäden**
- Unter **30 % Energie** kann jeder weitere Treffer ein Bordsystem beschädigen. Fällt die Energie durch einen Treffer unter 30 % und ist noch kein Bordsystem beschädigt, erscheint der Hinweis „ENERGIE UNTER 30 %“.
- Je Treffer gilt: 10 % **Bombenschacht**, 10 % **Sichtsystem**, 10 % **Kommunikation**, 70 % nichts passiert.
- Es gibt **höchstens einen Schaden gleichzeitig**. Weitere Treffer verursachen keinen zweiten.
- **Repariert wird nur an einer Station**, sofort beim Andocken. Der Stern repariert nicht.
- Ein aktiver Schaden steht im HUD links oben in Rot. Im Cockpit leuchtet dazu die passende Warnlampe dauerhaft rot: BOMBEN, SENSOREN oder DATENLINK. Auf der Karte erscheint ein Hinweis und an den Stationen „Repariert beim Andocken“.

| Schaden | Wirkung |
|---|---|
| Bombenschacht | Bomben klemmen und lassen sich nicht abwerfen. Bordlaser und Ionen-Kanone funktionieren normal. |
| Sichtsystem | Nur die Außensicht ist gestört, Cockpit und HUD bleiben klar. Die Welt hinter den Scheiben schwankt leicht. Etwa alle 2,5–5 Sekunden kommt ein Störungsstoß von 0,3 Sekunden, entweder feiner Schnee oder weiche grüne Streifen. |
| Kommunikation | Meldungen von außen (Ticker, DATENLINK, Kartenprotokoll) fehlen zu etwa einem Drittel ganz. Die übrigen kommen verstümmelt an. Auch der Stationsalarm bleibt aus, wenn seine Meldung verloren geht. Warnungen an Bord, eigene Erfolge und die Karte selbst bleiben korrekt. |

**Fotosensibilität**: Die Sichtstörung ist bewusst fotosicher gestaltet:
- Sie blitzt nicht auf und die mittlere Helligkeit bleibt erhalten.
- Ein- und Ausblendung sind weich.
- Es kommt höchstens ein Stoß alle 2,5 Sekunden, weit unter der Grenze von 3 Blitzen pro Sekunde.
- Es gibt keine harten oder regelmäßigen Streifenmuster.
- Das Schwanken ist langsam (unter 1,2 Hz) und folgt der Option „Bildschirmwackeln“. Bei 0 schwankt nichts.

Im selben Zug wurden auch ältere Effekte entschärft (gemessen nach WCAG 2.3.1):
- Treffer-Farbblitze und die rote Trefferkante kommen höchstens zweimal pro Sekunde und sind nicht mehr gesättigt rot. Ein schwerer Treffer kurz nach einem leichten wird kurz darauf nachgeholt, statt verloren zu gehen.
- Die Störstreifen bei schweren Treffern wechseln nur noch dreimal pro Sekunde (vorher 24-mal).
- Der Projektor flackert nicht mehr, sondern dunkelt kurz weich ab.
- Das Cockpitlicht glimmt bei Treffern nur noch lachsfarben statt grellrot auf, höchstens zweimal pro Sekunde, und klingt weich ab. Bei Dauerbeschuss pulsiert es deshalb weiterhin, aber ruhig (unter 2 Hz).
- **Hyperraumsprung**: Die Sternstreifen konnten nach längerer Spielzeit von Bild zu Bild springen, wie ein Stroboskop. Jetzt laufen sie mit begrenztem Tempo und weniger Kontrast. Beim Sprung zwischen den Systemen ist der Tunnel lachsfarben statt gesättigt rot.
- **Untergang des Schiffs** (Energie leer oder am Stern verglüht): Statt vieler greller Explosionen direkt vor dem Cockpit gibt es eine Explosion. Danach folgen ein ruhiges Ausklingen mit weichem Schwanken und Abdunkeln sowie wenige, weiter entfernte Explosionen ohne Lichtblitz.
- **Zerstörte Feindstadt**: Die Folgeexplosionen blitzen nicht mehr, und der zusätzliche Bildschirm-Farbblitz entfällt.
- **Explosionen allgemein**: Höchstens drei grelle Explosionen pro Sekunde. Weitere werden ohne Kernblitz, Lichtpuls und Schockwelle gezeichnet.
- Das verwundbare Quadrat des Flaggschiffs pulsiert ruhig mit 1,5 Hz (vorher 4,8 Hz), die Schrift „VERWUNDBAR!“ blinkt mit 2 Hz.

Abschalten bzw. anpassen über die `balance.cfg`: `damage_enabled`, `damage_energy_threshold`, `damage_chance_bombs/screen/comms`, `damage_comms_lost`, `damage_comms_garble`, `damage_screen_*`, `star_refuel_enabled`, `star_refuel_rate`, `star_heat_time`.

## Cockpit-Ansicht (Head-Up-Display)

Seit 0.11.0 sitzt du in einem echten 3D-Cockpit. Die Anzeigen leuchten wie bei einem Kampfjet auf einer schrägen Combiner-Scheibe vor dir, statt als flache Fläche über dem Bild zu liegen.

- **Auf dem Glas**:
  - Visier (Bordlaser-Klammern bzw. Ionen-Fadenkreuz)
  - links die **Energieskala** mit Ablesefeld, rechts die **Waffenskala** (Laser, Ladezustand der Ionen-Kanone bzw. Bomben)
  - oben Punkte, Zeit/Stufe und ein **Kursband**, dazu eine dezente Neigungsleiter
  - unten links die **Lage**, unten rechts Waffe und Modus
  - die großen Meldungen
- **Helmanzeige (im ganzen Blickfeld, genau auf den Zielen)**:
  - Zielklammern mit Entfernung und Schildkästchen
  - Flaggschiff-Quadrat, Bombenbahn und Aufschlagtext, Punkte
  - Pfeile zu Gegnern außerhalb der Sicht
  - Spalte links: Ort, Lage-Untertitel und Bedienhinweise
  - Spalte rechts: Meldungen der Systemkarte
- **Konsole**:
  - drei Bildschirme: NAV links, in der Mitte der **Planetenscanner** bzw. Andocken/Tanken bzw. Waffenstatus, DATENLINK rechts
  - Warnlampen, z. B. TREFFER, ENERGIE, GESCHOSS, ZIEL, BOMBEN, ANDOCKEN, SENSOREN. SENSOREN leuchtet auf Planeten grün (Scanner aktiv). Dauerhaft rot leuchtende BOMBEN, SENSOREN oder DATENLINK melden einen Systemschaden. Blinkt BOMBEN rot, sind die Bomben alle.
- **Bewegung**: Bei Drehungen federt das Cockpit leicht nach, bei Treffern wackelt es und das Licht glimmt rot auf. Die Zielsymbolik bleibt dabei immer deckungsgleich mit der Welt.
- **Einstellungen**:
  - **Optionen → „Cockpit mit Head-Up-Display“** schaltet auf die bisherige flache Anzeige zurück, auch mitten im Kampf.
  - Die Trägheit lässt sich über `cockpit_lag` in der `balance.cfg` einstellen (0 = starr).

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
| `enemy` | Sprung ins Feindsystem mit Empfangskomitee (`--system=2`: Ixmora, ohne Empfangskomitee) |
| `enemy_planet` | Feindplanet, `--planet=0…4` (0 = Heimatwelt), `--nodefenders` ohne Verteidiger, `--system=2` für Ixmora (`--planet=0…3`) |
| `victory` | Nur noch eine einzige Feindstadt, auf `--planet=N`, Standard Heimatwelt (Sieg testen); `--system=2` für Ixmora |
| `enemy_map` | Feindkarte mit startenden Schwadronen; `--system=2` für Ixmora, `--waiting=N` zusätzlich N am Sprungpunkt wartende Schwadrone |
| `enemy_intercept` | Schwadron im Feindsystem abfangen; `--system=2` für Ixmora |
| `map` | Systemkarte; `--awaken` lässt Ixmora angreifen, `--view=1\|2` zeigt Vorrhal bzw. Ixmora, `--select=enemy\|enemy2` wählt den Sprungpunkt nach Vorrhal bzw. Ixmora |
| `evaluation` | Auswertungsbildschirm, `--end=victory\|abort\|gameover` |
| `star` | Am Stern, `--system=1` für Vorrhal, `--system=2` für Ixmora, `--energy=N` Startenergie |
| `highscores` | Highscore-Tabellen je Schwierigkeitsstufe |
| `options` | Optionen aus dem Hauptmenü, `--scroll=PX` scrollt nach unten (z. B. zur Schwierigkeit) |

Schwierigkeitsstufe für Tests: `--difficulty=0…5` (Kinderspiel, Anfänger, Normal, Fortgeschritten, Hart, Experte). Sie wird nicht gespeichert und funktioniert auch mit `--autoplay`. `--system=2` legt Ixmora bei Bedarf auch auf niedrigeren Stufen an.

Zusätzliche Testhilfen (0.12.0, in allen Testszenarien `--test=…`; ein reines `--autoplay` ohne Szenario beginnt ein neues Spiel und setzt sie zurück):
- `--energy=N`: Startenergie, z. B. unter 30 %, damit Treffer Systemschäden auslösen können.
- `--damage=bombs|screen|comms`: Systemschaden gleich zu Beginn.
- `--burst=S` (nur mit `--damage=screen`, in Kampfszenen): erzwingt einen Störungsstoß nach S Sekunden.
- `--burst_kind=0|1` (mit `--burst`): Art der Stöße, 0 = Schnee, 1 = grüne Streifen.
- `--burst_hold` (mit `--burst`): hält den Stoß ab Szenenbeginn dauerhaft auf voller Stärke, für Standbilder.
- `--comms_demo` (mit `--damage=comms`): erzeugt einige Meldungen von außen, die verloren gehen oder verstümmelt ankommen.
- `--awaken_at=S` (0.14.0): Ixmora greift nach S Sekunden an, z. B. für Bilder von Banner und Alarm in einer laufenden Szene.

Mit `-- --autoplay --raid` greift der automatische Testfahrer auch das Feindsystem an. Optionen:
- `--human`: menschenähnlicher Testfahrer
- `--raid_target=auto|home|outer`: Wahl der Angriffsziele
- `--raid_safe`: „Verteidigung zuerst“. Er greift nur an, wenn in Helion länger keine Landung droht, und springt sofort zurück, sobald eine Landung näher rückt.
- `--raid_intercept`: Er fängt startende Schwadrone schon im Feindsystem ab.
- `--raid_patience=S` (mit `--raid_safe`, 0.14.0): Nach S Sekunden Strategiezeit ohne Angriff greift er trotzdem an und bleibt, bis die Bomben verbraucht sind. Nur gelandete Schwadrone und Stationsangriffe halten ihn dann noch ab, wie bei einem Menschen, der nicht endlos nur verteidigt.
- Auf Hart/Experte wählt er zuerst das Feindsystem, das noch Schwadrone baut und dessen Produktion am ehesten zu stoppen ist.
- `--fpscap=N` (0.14.0): Bildrate wie im Spiel begrenzen (die Testläufe laufen sonst unbegrenzt schnell). Wirkt nur ohne `--fixed-fps`; das Spiel läuft dann in Echtzeit.

## Auswertung

Am Ende jeder Partie (Sieg, Game Over oder Abbruch über *Pause → Spiel beenden*) zeigt das Spiel:
- zerstörte Fighter, abgeschossene Zerstörer, vernichtete Flaggschiffe und zerbombte Feindstädte, jeweils mit den erzielten Punkten,
- verlorene eigene Städte und die Spielzeit,
- Boni, vernichtete Schwadrone, Bombentreffer, Sprünge, Sternbesuche, Systemschäden (davon repariert) und erreichte Stufe,
- auf Hart/Experte, wann das zweite Feindsystem angriff und wie viele seiner Städte zerbombt wurden.

Jede Auswertung wird zusätzlich als Zeile an **`auswertungen.csv`** im Benutzerordner angehängt (Semikolon-getrennt, für Excel/LibreOffice). So lassen sich Punktzahlen verschiedener Taktiken vergleichen. Kommen neue Spalten hinzu (z. B. Sternbesuche in 0.12.0), schreibt das Spiel vor der nächsten Zeile eine neue Kopfzeile.

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

Einige Optionen lassen sich auch direkt im Spiel umschalten (Optionen): automatische Waffenwahl, 9/12 Fighter im Orbit, die [VERMUTET]-Regel „Schwadron mit nur einem Zerstörer bleibt zeitweise stehen“, Scanner-Ausrichtung, Randpfeile, Retro-Filter und die Cockpit-Ansicht. Die Schwierigkeit lässt sich nur im Hauptmenü ändern.

## Änderungen in Version 0.14.2 – Stationen besetzbar statt zerstörbar

- **Stationen werden nicht mehr zerstört**, sondern **besetzt**: Bei 0 % Integrität halten die Fighter des Angreifers die Station. Tanken, Bomben und Reparatur sind dort gesperrt, bis du die Fighter vernichtest. Danach ist die Station befreit (100 %) und sofort wieder nutzbar. Das besetzende Schwadron bleibt an der Station und greift keine Städte an.
- Karte: „BESETZT“ an der Station, im Infofenster der Hinweis zum Befreien, beim Schwadron „Hält Station … besetzt“. Im Cockpit: „STATION BESETZT!“ bzw. „STATION BEFREIT“.
- Wer zerstörbare Stationen will: `station_can_be_destroyed=true` in der `balance.cfg` (dann gilt wieder der Wiederaufbau aus 0.14.1). Achtung: Eine `balance.cfg`, die als vollständige Kopie einer älteren `balance_template.cfg` entstanden ist, enthält noch `station_can_be_destroyed=true`. Diese Zeile löschen, sonst bleiben die Stationen zerstörbar.
- **Behoben**: Der Wiederaufbau aus 0.14.1 fand im Spiel nie statt. Der Countdown lief ab, der Zähler landete aber bei echten Bildzeiten knapp unter 0, und die Station blieb zerstört. Betrifft seit 0.14.2 nur noch `station_can_be_destroyed=true`.
- Nach einer Befreiung oder Verteidigung zeigt die Ortszeile im HUD wieder „Reparatur & Energie“. Bisher blieb „WIRD ANGEGRIFFEN!“ bzw. „BESETZT!“ bis zum Ende des Tankens stehen. Außerdem: Das Stations-Infofenster zeigte „100 %%“, und bei einem einzelnen Fighter heißt es jetzt „1 Fighter hält …“.
- Neue Testhilfen: `--test=map --occupy --select=station` (Station Alpha besetzt und ausgewählt), `--test=station_attack --occupied`.

## Änderungen in Version 0.14.1 – Hart und Experte entschärft

- **Ixmora kleiner**: 8–10 Städte je äußerem Planeten, Heimatwelt 12 (vorher 15–17 bzw. 20), normales Einsatzgebiet (`second_city_count_min/max`, `second_home_city_count`, `second_planet_area_factor`).
- **Weniger Druck**: Die +10 % Schwadron-Tempo von Hart/Experte gelten nur noch in Helion (`squadron_speed_factor`). In Ixmora fliegen die Schwadrone 20 % langsamer zum Sprungpunkt (`second_transit_speed_factor=0.8`), in Vorrhal normal.
- **Kein Festfahren ohne Stationen** (seit 0.14.2 nur noch mit `station_can_be_destroyed=true`, denn Stationen werden jetzt besetzt statt zerstört): Sind beide Stationen zerstört, wird die zuerst zerstörte nach 3 Minuten wieder aufgebaut (`station_rebuild_time`, 0 = nie; wirksam erst ab 0.14.2, siehe dort). Bisher gab es dann nie wieder Bomben: Die Partie ließ sich nicht mehr gewinnen und lief, sobald kein Nachschub mehr kam, endlos weiter. In den Messungen von 0.14.0/0.14.1 fielen in 5 Partien auf Hart/Experte beide Stationen; 3 davon liefen ohne Ergebnis bis zum Abbruch nach 150 Minuten.
- **Experte-Auslöser gelockert**: Ixmora greift an, sobald in Helion erstmals 60 Sekunden lang höchstens ein Schwadron unterwegs ist (vorher: ohne jedes Schwadron; `second_system_empty_time`, `second_system_empty_max`) – oder wie bisher beim Produktionsstopp von Vorrhal. Der Kartenhinweis zeigt den Countdown auch bei einem verbliebenen Schwadron. Gemessen wurden drei Varianten: „30 s ohne Schwadron“ griff nie, „30 s mit höchstens einem“ einmal schon nach 6 Minuten (Partie verloren), „60 s mit höchstens einem“ gelegentlich mitten im Spiel.

## Änderungen in Version 0.14.0 – Zweites Feindsystem, Stufen Hart und Experte

- **Neue Stufen Hart und Experte**: wie Fortgeschritten, Schwadrone 10 % schneller, dazu das zweite Feindsystem **Ixmora**. Details siehe „Das zweite Feindsystem Ixmora“.
- **Ixmora**: blauer Stern, 4 Planeten mit eigenen Oberflächen (Gletscher-, Magma-, Leuchtwelt, Heimatwelt Thurxa), eigener Himmel und Kartenhintergrund, kein Empfangskomitee, nur über Helion erreichbar.
- **Gemeinsame Grenze** von 6 Schwadronen in Helion für beide Feindsysteme. Wer am längsten am Sprungpunkt wartet, springt zuerst.
- **Sieg** auf Hart/Experte erst, wenn die Städte beider Feindsysteme zerbombt sind.
- **Karte**: Q/Tab blättert durch alle drei Systeme. Zweiter Sprungpunkt unten rechts, Countdown bis zum Angriff auf Experte.
- Eigene Highscore-Listen für Hart und Experte. Die Auswertung und `auswertungen.csv` enthalten den Angriffszeitpunkt von Ixmora und dessen zerbombte Städte.
- Neue Testhilfen: `--system=2`, `--view=1|2`, `--awaken`, `--waiting=N` (siehe „Testfunktionen“).

## Änderungen in Version 0.13.0 – Schwierigkeitsstufen

- **Neue Stufen**: Kinderspiel, Anfänger, Normal und Fortgeschritten. Details siehe „Schwierigkeitsstufen“.
- **Bis zu 6 Schwadrone** gleichzeitig im Helion-System (bis 0.12.0: 4).
- **Eigene Highscore-Liste je Stufe**, umschaltbar mit ◀ ▶. Die Auswertung zeigt die Liste der gespielten Stufe.
- Die Nachschub-Bremse richtet sich nach dem Anteil zerstörter Städte.
- Fortgeschritten: 15–17 Städte je Feindplanet (Heimatwelt 20) auf einem größeren Einsatzgebiet. Scanner und Spielfeldgrenze passen sich an.
- Das Titelbild zeigt die gewählte Stufe. Die Auswertung und `auswertungen.csv` nennen die Stufe beim Namen.

## Änderungen in Version 0.12.0 – Sterne, Systemschäden, mehr Fighter

- **Mehr Fighter, ruhigere Zerstörer**:
  - Jedes Schwadron hat **doppelt so viele Fighter** (`squadron_fighter_factor=2.0`).
  - Dafür fliegen die Schwadrone im Helion-System **20 % langsamer** (`squadron_speed_home_factor=0.8`).
  - Die plötzlichen Ausweichmanöver der Zerstörer vor Ionen-Kugeln sind abgeschaltet. Das Hin- und Herschwanken bleibt.
- **Sterne Helion und Vorrhal**: Schnelltanken in Sekunden, aber nach 10 s verglüht das Schiff. Keine Reparatur, keine Bomben. Details siehe „Sterne und Systemschäden“.
- **Systemschäden** unter 30 % Energie: Bombenschacht, Sichtsystem oder Kommunikation, je 10 % pro Treffer, höchstens einer gleichzeitig. Repariert wird nur an Stationen.
- **Fotosicherheit**:
  - Die neue Sichtstörung kommt ohne Blitze aus.
  - Trefferblitze kommen höchstens zweimal pro Sekunde und sind nicht mehr gesättigt rot.
  - Störstreifen und Projektor flackern nicht mehr schnell.
  - Hyperraumsprung, Untergang des Schiffs, zerstörte Feindstädte und das Flaggschiff-Quadrat sind ruhiger.
  - Grelle Explosionen sind auf höchstens drei pro Sekunde begrenzt.
  - Details siehe „Sterne und Systemschäden“.
- Warnlampe SCANNER heißt jetzt SENSOREN: grün auf Planeten wie bisher, rot bei gestörtem Sichtsystem.
- Die Hitzewarnung am Stern erscheint auch auf der Karte und beim Blick ins andere System, mit Warnton.
- Neue Klänge: Systemschaden, Reparatur, Bildrauschen.
- Auswertung und `auswertungen.csv` zeigen zusätzlich Sternbesuche, Systemschäden und Reparaturen.

## Änderungen in Version 0.11.0 – Cockpit mit Head-Up-Display

- **Neue Cockpit-Ansicht** (Standard). Die Anzeigen sehen nicht mehr wie ein Overlay aus: Combiner-Glas mit Leuchtsymbolik, 3D-Cockpit mit Konsole, drei Bildschirmen und Warnlampen, Kanzelrahmen, Nachfedern bei Drehungen. Details siehe „Cockpit-Ansicht“ oben.
- Entstanden aus drei Prototypen (VR-Holo-Cockpit, Kampfjet-HUD, Helmvisier), die von zwei Gutachtern verglichen wurden. Die Kampfjet-Variante wurde übernommen und um Ideen der anderen ergänzt:
  - kompakte Konsole, Pfeile innerhalb der Kanzel
  - Kontrastsäume für hellen Himmel und Explosionen
  - Bildschirme in nativer Auflösung (scharf bei 720p und 4K)
  - Einschalt-Sweep beim Szenenstart
- Die bisherige flache Anzeige bleibt erhalten: **Optionen → „Cockpit mit Head-Up-Display“** aus.
- Testhilfen: `--classic` (klassisches HUD), `--bombmode` (Bombenmodus über Feindplaneten), `--toggle_hud=N` (Ansicht nach N s umschalten).

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
- **Messung 0.14.2** (Kontrolle nach der Umstellung auf besetzbare Stationen, 6 Partien): Alle gewonnen. Hart mit Angriff nach 40 und 46 Minuten (28 bzw. 56 von ~80 Städten verloren), Experte mit Angriff nach 53 (68 verloren), Experte ungeduldig nach 103 (43 verloren), Fortgeschritten mit Angriff nach 27, Anfänger nach 13 Minuten. In 2 Partien wurden insgesamt 3 Stationen besetzt. Der Testfahrer befreite sie jeweils nach 35 Sekunden bis 2½ Minuten. Zerstört wurde keine Station.
- **Messung 0.14.1** (Hart und Experte nach der Entschärfung; Experte mit dem Auslöser „60 s, höchstens ein Schwadron“), sonst wie bei 0.14.0. Spielzeit bis zum Sieg in Minuten:

  | Stufe | Angriff | vorsichtig | ungeduldig |
  |---|---|---|---|
  | Hart | 40 und 52 (41 bzw. 60 von ~80 Städten verloren); 1 Partie verloren (nach 38 Minuten) | 72 und 102 (3 bzw. 4 verloren) | 80 und 111 (46 bzw. 64 verloren) |
  | Experte | 39 und 43 (26 bzw. 15 verloren) | 106 (0 verloren); 1 Partie nach 150 Minuten offen | 93, 93 und 94 (48–69 verloren) |

  - Gegenüber 0.14.0 gewinnt der vorsichtige Testfahrer auf Hart jetzt (vorher 2 von 3 Partien festgefahren), der ungeduldige gewinnt alle Partien (vorher 1 von 3).
  - Ixmora griff auf Experte einmal schon nach 30 Minuten über den neuen Auslöser an, sonst nach 23–102 Minuten über den Produktionsstopp von Vorrhal.
  - Eine weitere Hart-Partie lief vor der Behebung in den Stations-Stillstand (beide Stationen zerstört, 116 von 121 Feindstädten zerbombt). Seit 0.14.2 kann das nicht mehr passieren: Stationen werden nur noch besetzt, und mit `station_can_be_destroyed=true` greift der reparierte Wiederaufbau.
- **Messung 0.14.0** (Hart und Experte) mit dem menschenähnlichen Testfahrer, Abbruch nach 150 Minuten Spielzeit. „Angriff“ = Sturmangriff (`--raid`), „vorsichtig“ = Verteidigung zuerst (`--raid_safe`), „ungeduldig“ = Verteidigung zuerst, aber nach 8 Minuten ohne Angriff greift er trotzdem an (`--raid_safe --raid_patience=480`). Spielzeit bis zum Sieg in Minuten:

  | Stufe | Angriff | vorsichtig | ungeduldig |
  |---|---|---|---|
  | Hart | 42 und 50 (27 bzw. 83 von ~80 Städten verloren) | 91 (13 verloren); 2 Partien nach 150 Minuten offen | 123 (64 verloren); 2 Partien verloren (nach 44 und 94 Minuten) |
  | Experte | 48 und 57 (47 bzw. 75 verloren) | 122 und 126 (0 bzw. 6 verloren); 1 Partie nach 150 Minuten offen | 94 und 104 (48 bzw. 52 verloren); 1 Partie verloren (nach 75 Minuten) |
  | Fortgeschritten (Vergleich) | 27 (27 verloren) | – | 56 und 76 (12 bzw. 26 verloren) |

  - Ixmora griff in allen Partien an, sobald Vorrhal keine Schwadrone mehr baute, meist nach 22–72 Minuten. Der 60-Sekunden-Auslöser von Experte kam in den Messungen nie zum Zug: Vorrhal liefert ständig nach, der Testfahrer räumt Helion nie so lange leer.
  - Auf Hart und Experte ist Helion fast ständig voll (6 Schwadrone). Wer nur verteidigt, kommt kaum zum Angriff. Wer angreift, verliert viele eigene Städte. Beide Stufen sind damit deutlich schwerer und länger als Fortgeschritten.
  - Drei von 23 beschleunigten Testläufen stürzten im bekannten Engine-Fehler des Audio-Mischthreads ab (gleiche Signatur wie 0.10.2). Er tritt nur bei über 1000 fps auf, in den langen, kampfreichen Partien auf Hart/Experte entsprechend öfter. Die Läufe wurden wiederholt. Im Spiel begrenzt `max_fps` (240) das Risiko.
  - Einstellschrauben (Stand 0.14.1): Städte von Ixmora `second_city_count_min/max`, `second_home_city_count`; Tempo in Helion `squadron_speed_factor`, in Ixmora `second_transit_speed_factor`; Experte-Auslöser `second_system_empty_time`, `second_system_empty_max`.
- **Messung 0.13.0** je Schwierigkeitsstufe mit dem menschenähnlichen Testfahrer. „Vorsichtig“ = Verteidigung zuerst (`--raid_safe`), „Angriff“ = Sturmangriff (`--raid`). Spielzeit in Minuten:

  | Stufe | vorsichtig | verlorene Städte | Angriff | verlorene Städte |
  |---|---|---|---|---|
  | Kinderspiel | 15–17 (3 von 3 gewonnen) | 0 | 11–13 | 2–4 |
  | Anfänger | 15–22 (3 von 3) | 0 | 12–14 | 4 |
  | Normal | 25–27 (3 von 3) | 0 | 14–16 | 0–3 |
  | Fortgeschritten | 52–63 (2 von 3, eine Partie nach 100 Minuten noch offen) | 0 | 32–36 | 25–30 |

  - Auf Fortgeschritten sind fast ständig bis zu 6 Schwadrone im Helion-System. Der vorsichtige Testfahrer greift nur an, wenn keine Landung droht. Deshalb kommt er lange nicht zum Angriff, und die Partie dauert sehr lange. Bei der offenen Partie waren nach 100 Minuten 70 von 83 Feindstädten zerstört und die Produktion gestoppt.
  - Wer angreift und dafür einzelne Städte opfert, kommt auf etwa 35 Minuten.
- **Messung 0.12.0** mit dem menschenähnlichen Testfahrer, alle Neuerungen aktiv (doppelte Fighter, Tempo 0,8, Sterne, Systemschäden):
  - „Verteidigung zuerst“ (`--raid_safe`): **12 von 12 Partien gewonnen**, alle ohne verlorene eigene Stadt. Dauer 14–24 Minuten, im Schnitt 21. Je Partie gab es 0–3 Systemschäden (im Schnitt 1,5), alle wurden an Stationen repariert. Dazu kamen 3–6 Sternbesuche.
  - Sturmangriff (`--raid`): 8 von 8 Partien gewonnen, in 13–20 Minuten. Dabei gingen 0–27 eigene Städte verloren.
  - Gegenüber 0.10.2 (im Schnitt 24 Minuten) sind die Partien kürzer, an den Sternen liegt das aber kaum. Ein Vergleichslauf ohne Sterne und Systemschäden dauerte ebenfalls rund 21 Minuten. Vorrhal erspart zwar manchen Rücksprung zum Tanken (5–6 statt 6–7 Angriffe), die Spieldauer ändert sich dadurch höchstens um ein bis zwei Minuten.
  - Schwadron-Tempo 1,0 statt 0,8 änderte im Vergleichslauf kaum etwas: 19,5 Minuten, keine Stadt verloren.
- **Sieg ohne Städteverlust ist möglich** (Messung 0.10.2): Mit der Strategie „Verteidigung zuerst“ (`--raid_safe`) gewann der menschenähnliche Testfahrer 9 von 10 Partien, 7 davon ohne eine einzige verlorene eigene Stadt (sonst 1 bzw. 3). Er brauchte 15–35 Minuten, im Schnitt 24. Einmal ging ihm früh die Energie aus: Ein Flaggschiff traf ihn dreimal, und er floh zu spät. Der perfekte Testfahrer brauchte 8–11 Minuten.
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
scripts/hud/cockpit_hud.gd    Cockpit-Ansicht: Head-Up-Display auf dem Combiner-Glas, Helmanzeige
scripts/hud/cockpit_rig.gd    3D-Cockpit (Konsole, Kanzel, Combiner-Glas, Warnlampen, Nachfedern)
scripts/hud/cockpit_mfd.gd    Bildschirme der Konsole (NAV, Scanner/Andocken/Waffen, Datenlink)
scripts/hud/classic_hud.gd    klassische flache Anzeige (Optionen)
scripts/fx/view_fx.gd         Sichtstörung (Systemschaden), nur auf den Scheibenflächen
shaders/                      Himmel, Planeten, Boden, Schilde, Explosionen, Hyperraum, Nachbearbeitung
assets/                       Modelle (glb), Texturen, Audio, Schriften (OFL)
tools/                        Generatoren: Blender-Modelle, Texturen, Klangsynthese/Komposition
tools/textures/gen_alien2_planets.py, gen_sky_enemy2.py, gen_map_bg_enemy2.py   Ixmora (0.14.0): Planeten, Himmel, Karte
```

Schriften: Orbitron, Rajdhani, Share Tech Mono (SIL Open Font License, siehe `assets/fonts/`).
Orchesterklänge zum Teil aus FluidR3_GM (MIT-Lizenz).
