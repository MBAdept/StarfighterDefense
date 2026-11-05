extends Node
## =============================================================================================
##  ZENTRALE SPIELWERTE – "Starfighter Defense"
## =============================================================================================
##  Alle Balancing-Werte (Energie, Punkte, Geschwindigkeiten, Zeiten …) stehen hier gesammelt.
##
##  Kennzeichnung (wie in der Spielbeschreibung):
##    [ORIGINAL]  = so im Originalspiel (aus Spielererinnerung, sinngemäß)
##    [VERMUTET]  = Eindruck, nicht gesichert – Standardwert, leicht änderbar bzw. abschaltbar
##    [FREI]      = selbst gestaltet
##
##  Überschreiben OHNE neu zu exportieren:
##    Eine Datei "balance.cfg" neben die ausführbare Datei (oder nach user://balance.cfg) legen:
##        [balance]
##        fighter_damage=2.0
##        bombard_time=14.0
##    Schlüssel = Variablenname aus dieser Datei. Eine Vorlage mit allen Werten wird beim ersten Start
##    nach user://balance_template.cfg geschrieben (Benutzerordner siehe README).
##  Einheiten: Zeiten in Sekunden, Energie in Prozent, Distanzen im Kampf in Metern,
##             Distanzen auf der Karte in "Karteneinheiten" (Kartenbreite ≈ 1600).
## =============================================================================================

# ---------------------------------------------------------------------------------------------
#  Allgemein / Test
# ---------------------------------------------------------------------------------------------
var debug_keys_enabled := true          ## [FREI] F1–F12 Testfunktionen (siehe README)
var start_with_orbit := true            ## [ORIGINAL] Spielstart im Orbit des Heimatplaneten
## [FREI] Bildrate begrenzen (0 = unbegrenzt; mit VSync gilt zusätzlich die Bildwiederholrate). Schont die Grafikkarte
## und hält einen seltenen Absturz im Audio-Mischthread der Engine fern, der nur bei extrem hohen Bildraten auftritt.
var max_fps := 240
## [FREI] Cockpit-Ansicht: Nachfedern des Cockpits bei Drehungen (1 = Standard, 0 = starr) – die Ziel-
## symbolik bleibt immer deckungsgleich mit der Welt. Ein-/Ausschalten der Ansicht: Optionen.
var cockpit_lag := 1.0
var difficulty_scale := 1.0             ## [FREI] von der Schwierigkeitsstufe gesetzt: Gegnerschaden ×s, Schwadron-Tempo ×√s, Abstand neuer Schwadrone ÷s^0.7

## [Vorgabe 0.13.0] Schwierigkeitsstufen (Optionen). Die Stufe setzt beim Start jeder Partie die Werte unter "values"
## und gilt für die ganze Partie (eine Änderung mitten im Spiel wirkt ab der nächsten). Ausnahme: Schlüssel, die eine
## balance.cfg auf einen anderen Wert als den Standard setzt – die gehen vor. Jede Stufe hat eine eigene
## Highscore-Liste ("key").
## [Vorgabe 0.14.0/0.14.1] Hart und Experte: wie Fortgeschritten, Schwadrone in Helion 10 % schneller und ein zweites,
## kleineres Feindsystem (siehe „Zweites Feindsystem“ weiter unten). Schlüssel, die eine Stufe nicht nennt, gelten mit
## ihrem Standardwert. In "desc" werden {empty_time} und {empty_max} durch die aktuellen Auslöserwerte ersetzt
## (difficulty_desc), damit der Text auch mit einer balance.cfg stimmt.
const DIFFICULTY_LEVELS := [
	{"key": "kinderspiel", "name": "Kinderspiel",
		"desc": "Weniger Schaden, langsamere und seltenere Schwadrone (bis 0.12.0 „Leicht“)",
		"values": {"difficulty_scale": 0.75, "initial_squadrons": 2, "enemy_city_count_min": 6, "enemy_city_count_max": 8,
			"enemy_home_city_count": 12, "enemy_planet_area_factor": 1.0}},
	{"key": "anfaenger", "name": "Anfänger",
		"desc": "2 Schwadrone zu Beginn, 6–8 Städte je Feindplanet (bis 0.12.0 „Normal“)",
		"values": {"difficulty_scale": 1.0, "initial_squadrons": 2, "enemy_city_count_min": 6, "enemy_city_count_max": 8,
			"enemy_home_city_count": 12, "enemy_planet_area_factor": 1.0}},
	{"key": "normal", "name": "Normal",
		"desc": "Wie Anfänger, aber 3 Schwadrone zu Beginn",
		"values": {"difficulty_scale": 1.0, "initial_squadrons": 3, "enemy_city_count_min": 6, "enemy_city_count_max": 8,
			"enemy_home_city_count": 12, "enemy_planet_area_factor": 1.0}},
	{"key": "fortgeschritten", "name": "Fortgeschritten",
		"desc": "4 Schwadrone zu Beginn, 15–17 Städte je Feindplanet (Heimatwelt 20), weiter verteilt",
		"values": {"difficulty_scale": 1.0, "initial_squadrons": 4, "enemy_city_count_min": 15, "enemy_city_count_max": 17,
			"enemy_home_city_count": 20, "enemy_planet_area_factor": 1.45}},
	{"key": "hart", "name": "Hart",
		"desc": "Wie Fortgeschritten, Schwadrone in Helion 10 % schneller – kann Vorrhal keine Schwadrone mehr bauen, greift ein zweites, kleineres Feindsystem an",
		"values": {"difficulty_scale": 1.0, "initial_squadrons": 4, "enemy_city_count_min": 15, "enemy_city_count_max": 17,
			"enemy_home_city_count": 20, "enemy_planet_area_factor": 1.45, "squadron_speed_factor": 1.1, "second_system_mode": 1}},
	{"key": "experte", "name": "Experte",
		"desc": "Wie Hart – das zweite Feindsystem greift aber schon an, sobald in Helion erstmals {empty_time} s lang {empty_max} unterwegs ist",
		"values": {"difficulty_scale": 1.0, "initial_squadrons": 4, "enemy_city_count_min": 15, "enemy_city_count_max": 17,
			"enemy_home_city_count": 20, "enemy_planet_area_factor": 1.45, "squadron_speed_factor": 1.1, "second_system_mode": 2}},
]

# ---------------------------------------------------------------------------------------------
#  Energie
# ---------------------------------------------------------------------------------------------
var energy_max := 100.0                 ## [ORIGINAL] Energie 0..100 %, bei 0 ist das Spiel verloren
var energy_start := 100.0               ## [FREI]
var energy_low_warning := 25.0          ## [FREI] unterhalb: Warnton + rotes Blinken
var energy_critical_warning := 10.0     ## [FREI] zweite Warnstufe (erneuter Warnton-Stoß)
var energy_warning_interval := 2.2      ## [FREI] Abstand der Warntöne innerhalb eines Stoßes
var energy_warning_burst := 3           ## [FREI] Warntöne pro Stoß beim Unterschreiten einer Schwelle
var energy_warning_reminder := 15.0     ## [FREI] danach nur noch eine Erinnerung alle x s (0 = aus)

# ---------------------------------------------------------------------------------------------
#  Hyperraumsprung
# ---------------------------------------------------------------------------------------------
var jump_cost_min := 2.5                ## [FREI] Mindestkosten eines Sprungs (bis 0.10.1: 3,0)
var jump_cost_max := 12.0               ## [VERMUTET] im Heimatsystem bis ca. 12 % (bis 0.10.1: 15 – nach Spieltest "einen Tick zu energiefressend")
var jump_cost_distance_ref := 850.0     ## [FREI] Kartendistanz, bei der jump_cost_max erreicht wird
var jump_can_kill := false              ## [FREI] false = ein Sprung lässt mindestens jump_min_energy_left übrig (kein Softlock)
var jump_min_energy_left := 1.0         ## [FREI]
var jump_duration := 1.7                ## [FREI] Dauer des Sprungeffekts

# ---------------------------------------------------------------------------------------------
#  Raumstation: Andocken / Tanken
# ---------------------------------------------------------------------------------------------
var station_count := 2                  ## [ORIGINAL] 2 Raumstationen
var dock_slide_time := 3.2              ## [ORIGINAL] Station fährt von links bis zur Bildmitte
## [ORIGINAL qualitativ, Werte FREI] Stern (Helion/Vorrhal): Energie fast sofort voll – aber schnell wieder weg,
## sonst verglüht das Schiff. Keine Reparatur, keine Bomben. Die Hitze steigt auch bei offener Karte.
var star_refuel_enabled := true
var star_refuel_rate := 25.0           ## Energie %/s am Stern (0 → 100 % in 4 s)
var star_heat_time := 10.0             ## Sekunden am Stern bis zum Verglühen
var star_heat_warning := 0.6           ## ab diesem Hitzeanteil Warnton und rote Anzeige
## [Vorgabe] Systemschäden: Wer unter damage_energy_threshold Energie getroffen wird, riskiert je Treffer einen
## Schaden (je Art mit eigener Chance, zusammen 30 %, sonst nichts). Höchstens EIN Schaden gleichzeitig.
## Reparatur nur beim Andocken an einer Station (der Stern repariert nicht).
var damage_enabled := true
var damage_energy_threshold := 30.0     ## % Energie
var damage_chance_bombs := 0.1          ## Bombenschacht klemmt: keine Bomben abwerfbar
var damage_chance_screen := 0.1         ## Sichtsystem gestört: Außensicht wackelt, Rauschen/Störstreifen (fotosicher)
var damage_chance_comms := 0.1          ## Kommunikation gestört: Meldungen von außen fehlen oder sind verstümmelt
var damage_comms_lost := 0.35           ## Anteil der Meldungen von außen, die bei gestörter Kommunikation ganz fehlen
var damage_comms_garble := 0.45         ## Anteil verstümmelter Zeichen in den übrigen Meldungen
## Sichtstörung [Vorgabe, fotosicher]: Außensicht schwankt leicht; alle damage_screen_burst_min..max Sekunden ein
## Störungsstoß von damage_screen_burst_time Sekunden (feiner Schnee oder weiche grüne Streifen, weich ein-/ausgeblendet,
## mittlere Helligkeit bleibt) – höchstens ein Stoß alle 2,5 s, weit unter 3 Blitzen pro Sekunde.
var damage_screen_burst_time := 0.3
var damage_screen_burst_min := 2.5
var damage_screen_burst_max := 5.0
var damage_screen_wobble := 3.0         ## Bildpunkte (bei 1080p) Schwanken der Außensicht, × Optionen "Bildschirmwackeln"
var refuel_rate := 10.0                 ## [ORIGINAL] ca. 10 % pro Sekunde …
var refuel_step := 5.0                  ## [ORIGINAL] … sichtbar in 5-%-Schritten
var station_damage_per_fighter := 0.07  ## [FREI] % Stationsintegrität pro Sekunde und angreifendem Fighter (ohne squadron_fighter_factor gezählt)
var station_can_be_destroyed := true    ## [FREI] unverteidigte Stationen können zerstört werden
## [FREI 0.14.1] Sind ALLE Stationen zerstört, wird nach so vielen Sekunden (Strategiezeit) eine wieder aufgebaut –
## sonst gäbe es nie wieder Bomben und eine Partie mit Feindstädten ließe sich nicht mehr gewinnen. 0 = nie.
var station_rebuild_time := 180.0

# ---------------------------------------------------------------------------------------------
#  Spielerschiff / Steuerung
# ---------------------------------------------------------------------------------------------
var camera_fov := 62.0                  ## [FREI] vertikales Sichtfeld (Grad)
var space_turn_rate := 72.0             ## [FREI] Grad/s links/rechts/rauf/runter (kein Rollen) [ORIGINAL: 4 Richtungen]
var space_turn_response := 7.0          ## [FREI] Ansprechverhalten (höher = direkter)
var space_pitch_limit := 55.0           ## [FREI] max. Neigung rauf/runter (keine freie Rotation)
var planet_turn_rate := 78.0            ## [FREI] Drehen links/rechts auf Planeten
var planet_speed_forward := 60.0        ## [FREI] m/s vorwärts
var planet_speed_backward := 32.0       ## [FREI] m/s rückwärts
var planet_response := 2.6              ## [FREI] Beschleunigung (höher = direkter)
var planet_altitude := 30.0             ## [ORIGINAL] Flughöhe auf Planeten ist fest
var planet_area_radius := 640.0         ## [FREI] Einsatzgebiet (Radius in m)
var evasion_turn_fraction := 0.6        ## [FREI] ab diesem Anteil der max. Drehrate gilt man als "ausweichend"
var evasion_hit_factor := 0.55          ## [FREI] Trefferchance des Gegners × Faktor beim Ausweichen

# ---------------------------------------------------------------------------------------------
#  Waffen
# ---------------------------------------------------------------------------------------------
var laser_fire_interval := 0.13         ## [ORIGINAL] Bordlaser: schnelle Schussfolge
var laser_speed := 400.0                ## [FREI]
var laser_range := 420.0                ## [FREI]
var laser_hit_tolerance := 0.6          ## [FREI] zusätzlicher Trefferradius (m) – macht Zielen fairer (kleiner = schwerer; bis 0.10.1: 1,4)
var ion_cooldown := 3.0                 ## [ORIGINAL] Ionen-Kanone: nur 1 Schuss alle 3 Sekunden
var ion_speed := 250.0                  ## [FREI]
var ion_range := 760.0                  ## [FREI]
var ion_hit_tolerance := 1.0            ## [FREI] (bis 0.10.1: 2,5)
var auto_weapon_switch := true          ## [FREI, Vorschlag automatisch] Waffe passend zum anvisierten Gegnertyp
var laser_hurts_destroyers := false     ## [FREI] Laser prallt an Zerstörern/Flaggschiff ab
var ion_hurts_fighters := true          ## [FREI] Ionen-Kugel zerstört auch Fighter (ineffizient)

# ---------------------------------------------------------------------------------------------
#  Fighter
# ---------------------------------------------------------------------------------------------
var fighter_points := 50                ## [ORIGINAL]
var fighters_per_wave := 3              ## [ORIGINAL] Dreierwellen
var wave_delay := 2.2                   ## [FREI] Pause zwischen Wellen
var fighter_speed := 46.0               ## [FREI] m/s
var fighter_hit_radius := 2.9           ## [FREI] Trefferradius eines Fighters (m), dazu laser_hit_tolerance (bis 0.10.1: 3,6)
var fighter_orbit_speed_min := 0.65     ## [FREI] Tempo des Kreisens um das Fadenkreuz (rad/s) – höher = schwerer zu treffen (bis 0.10.1: 0,5)
var fighter_orbit_speed_max := 1.5      ## [FREI] (bis 0.10.1: 1,15)
var fighter_steer := 2.4                ## [FREI] Wendigkeit
var fighter_distance_min := 34.0        ## [FREI] Abstand beim Kreisen um das Fadenkreuz
var fighter_distance_max := 78.0        ## [FREI]
var fighter_orbit_angle_min := 3.0      ## [ORIGINAL] fliegen meist um das Fadenkreuz herum (Winkelabstand, Grad)
var fighter_orbit_angle_max := 23.0     ## [FREI] (bis 0.10.1: 17)
var fighter_flyover_min := 7.0          ## [ORIGINAL] Überflug (nach oben, nie darunter) – Intervall min
var fighter_flyover_max := 15.0         ## [FREI] Intervall max
var fighter_fire_min := 3.6             ## [FREI] Pause zwischen zwei Feuerstößen pro Fighter (s)
var fighter_fire_max := 6.5             ## [FREI]
var fighter_first_fire_min := 0.7       ## [FREI] erster Feuerstoß schon im Anflug: s nach Erscheinen (zählt nur in Reichweite/Sichtkegel)
var fighter_first_fire_max := 1.9       ## [FREI]
var fighter_burst_shots := 1            ## [FREI] Schüsse pro Feuerstoß (1 = Einzelschuss, 2 = Doppelschuss – deutlich härter)
var fighter_burst_gap := 0.18           ## [FREI] Abstand der Schüsse im Feuerstoß (s)
var fighter_fire_range := 230.0         ## [FREI] max. Schussdistanz (m) – deckt den Anflug ab
var fighter_fire_cone := 38.0           ## [FREI] max. Winkel zur Spieler-Blickachse, in dem gefeuert wird (Grad)
var fighter_hit_chance := 0.45          ## [FREI]
var fighter_damage := 1.3               ## [ORIGINAL] Treffer kostet sehr wenig Energie (bis 0.10.1: 1,8)
var fighter_shot_speed := 95.0          ## [FREI]

# ---------------------------------------------------------------------------------------------
#  Zerstörer   (Index 0 = blau, 1 = grün, 2 = rot)
# ---------------------------------------------------------------------------------------------
var destroyer_points := [500, 750, 1000]            ## [ORIGINAL]
var destroyer_shields := [1, 2, 3]                  ## [ORIGINAL] Treffer nötig = Schilde + 1 (2/3/4)
var destroyer_osc_amplitude := [11.5, 14.5, 15.5]   ## [ORIGINAL qualitativ] Hin-und-her-Bewegung (Grad) langsam/schneller/noch schneller (bis 0.10.1: 7/10/13)
var destroyer_osc_speed := [0.72, 0.78, 0.8]        ## [ORIGINAL qualitativ] Bewegungstempo (bis 0.10.1: 0,32/0,5/0,72)
var destroyer_damage := [5.5, 6.5, 7.5]             ## [VERMUTET] Energieverlust pro Treffer (bis 0.10.1: 9/11/13 – Zerstörer leben jetzt länger und schießen öfter)
var destroyer_fire_interval := [11.0, 10.0, 9.0]    ## [FREI] (bis 0.10.1: 6/5,2/4,5)
var destroyer_first_fire_min := 0.45                ## [FREI] erster Schuss nach Erscheinen = Intervall × 0,45–0,7
var destroyer_first_fire_max := 0.7                 ## [FREI] (vorher 0,6–0,9: blaue waren oft vernichtet, bevor sie schossen)
var destroyer_hit_chance := 0.65                    ## [FREI] (bis 0.10.1: 0,72)
var destroyer_shot_speed := 72.0                    ## [FREI]
var destroyer_offscreen_margin := 11.0              ## [ORIGINAL] steht knapp außerhalb des Sichtfelds (Grad jenseits des Bildrands)
var destroyer_distance := 110.0                     ## [FREI] (bis 0.10.1: 88 – weiter weg = kleineres Ziel)
var destroyer_next_delay := 2.6                     ## [ORIGINAL] Zerstörer kommen nacheinander
var destroyer_size_scale := 1.25                    ## [FREI] Modellgröße
## [FREI] Trefferzone der Zerstörer: Ellipsoid um den Rumpf (= sichtbare Schildblase); 1.0 = eng am Rumpf.
## (bis 0.10.1: großzügige Kugel – "zu leicht zu treffen"; 0.10.2: Ellipsoid × 0,9)
var destroyer_hitbox_scale := 0.9
## [FREI] Ausweichen: fliegt eine Ionen-Kugel auf einen Zerstörer zu, weicht er mit dieser Chance aus [blau, grün, rot]
## [Vorgabe 0.12.0] aus – die Pendelbewegung genügt (0.10.2–0.11.0: [0.62, 0.56, 0.32])
var destroyer_dodge_chance := [0.0, 0.0, 0.0]
var destroyer_dodge_angle := 12.0                   ## [FREI] Ausweichweg (Grad)
var destroyer_dodge_reaction_min := 0.04            ## [FREI] Reaktionszeit (s)
var destroyer_dodge_reaction_max := 0.12            ## [FREI]
var destroyer_dodge_threat := 1.6                   ## [FREI] weicht nur aus, wenn die Kugel so nah vorbeifliegt (in Trefferzonen-Radien, ≤ 1 = Treffer)
## [FREI] Planeten: Trefferbreite der Zerstörer (× Rumpf-Ellipse). Die Höhe zählt dort nicht, weil man nicht
## nach oben/unten zielen kann (vorher hing die Breite in Spielerhöhe vom Schaukeln ab).
var destroyer_planet_hit_scale := 0.7

# ---------------------------------------------------------------------------------------------
#  Flaggschiff
# ---------------------------------------------------------------------------------------------
var flagship_points := 5000             ## [ORIGINAL]
var flagship_charge_time := 13.0        ## [ORIGINAL] lange Vorlaufzeit; Quadrat wird langsam heller
var flagship_vulnerable_time := 2.0     ## [ORIGINAL] nur kurz vor dem Schuss verwundbar
var flagship_cooldown := 14.0           ## [FREI] Pause nach dem Schuss (bis 0.10.1: 4,5)
var flagship_damage := 20.0             ## [VERMUTET] ein Fünftel der Energie (bis 0.10.1: 35)
var flagship_hit_chance := 0.9          ## [FREI] (Ausweichen halbiert)
var flagship_shot_speed := 115.0        ## [FREI]
var flagship_distance := 195.0          ## [FREI]
var flagship_retreat_delay := 10.0      ## [FREI] nach Vernichtung des Schwadrons zieht es sich zurück
var flagship_weakpoint_radius := 5.0    ## [FREI] Trefferradius des rosa Quadrats (m)

# ---------------------------------------------------------------------------------------------
#  Schwadrone (Übersichtskarte)
# ---------------------------------------------------------------------------------------------
var max_squadrons := 6                  ## [Vorgabe 0.13.0] bis zu 6 gleichzeitig im Helion-System (bis 0.12.0: 4 [ORIGINAL]); [Vorgabe 0.14.0] gemeinsam für beide Feindsysteme
## [Vorgabe 0.12.0] Fighter je Schwadron × Faktor (längere Kämpfe). Orbit-Start, Empfangskomitee und
## Planetenverteidiger bleiben unverändert. Das Tempo der Schwadrone rechnet mit der Größe ohne Faktor.
var squadron_fighter_factor := 2.0
var squadron_fighters_min := 3          ## [ORIGINAL] 3–12 Fighter (vor squadron_fighter_factor)
var squadron_fighters_max := 12         ## [ORIGINAL]
var squadron_fighters_start_min := 5    ## [FREI] Mindest-Fighterzahl der ersten Stufen (Stufe 1–2: 5–8 Fighter), ab Stufe 3 unverändert
var squadron_fighters_start_max := 8    ## [FREI]
var squadron_destroyers_min := 1        ## [ORIGINAL] 1–3 Zerstörer
var squadron_destroyers_max := 3        ## [ORIGINAL]
var squadron_speed_min := 1.0           ## [ORIGINAL qualitativ] sehr langsam; kleineres Schwadron = langsamer (Karteneinheiten/s)
var squadron_speed_max := 3.3           ## [FREI]
var squadron_speed_home_factor := 0.8   ## [Vorgabe 0.12.0] Schwadrone im Heimatsystem langsamer (mehr Zeit für die längeren Kämpfe)
var squadron_strength_ref := 26.0       ## [FREI] Stärke (Fighter + 4×Zerstörer + 2×Flaggschiff) für Höchsttempo
var single_destroyer_stops := true      ## [VERMUTET] nur noch 1 Zerstörer → Schwadron bleibt zeitweise stehen (abschaltbar)
var single_destroyer_stop_time := 18.0  ## [VERMUTET]
var single_destroyer_move_time := 10.0  ## [VERMUTET]
var initial_squadrons := 2              ## [FREI] Schwadrone beim Öffnen der Karte nach dem Orbit-Kampf
var initial_squadron_levels := [0, 1]   ## [FREI] Stufe je Start-Schwadron (0 = Stufe 1); das zweite kommt mit Zusammensetzung von Stufe 2
var spawn_interval_start := 150.0       ## [FREI] Abstand neuer Schwadrone zu Beginn
var spawn_interval_min := 70.0          ## [FREI]
var spawn_interval_factor := 0.88       ## [FREI] pro Schwierigkeitsstufe
var difficulty_level_time := 180.0      ## [FREI] alle x Sekunden steigt die Stufe
var difficulty_max_level := 8           ## [FREI]
var flagship_chance_base := 0.15        ## [FREI] "eventuell 1 Flaggschiff"
var flagship_chance_per_level := 0.08   ## [FREI]
var flagship_chance_max := 0.6          ## [FREI]
## [FREI] Farbgewichte der Zerstörer je Stufe [blau, grün, rot]; letzte Zeile gilt für alle höheren Stufen
var destroyer_color_weights := [[55, 45, 0], [50, 42, 8], [46, 40, 14], [34, 42, 24], [24, 42, 34]]
var squadron_station_target_chance := 0.2  ## [FREI] Anteil der Schwadrone, die eine Station anfliegen
var squadron_arrival_radius := 7.0      ## [FREI]

# ---------------------------------------------------------------------------------------------
#  Planeten / Städte / Bombardement
# ---------------------------------------------------------------------------------------------
var planet_count := 7                   ## [FREI, Vorschlag 6–8]
var city_count_min := 8                 ## [ORIGINAL] 8–13 Städte
var city_count_max := 13                ## [ORIGINAL]
var home_city_count := 15               ## [ORIGINAL] Heimatplanet hat 15
var bombard_time := 13.0                ## [FREI, Vorschlag 10–15] bis die Stadt zerstört ist
var city_move_time := 7.0               ## [FREI] Zerstörer wechselt zur nächsten Stadt
var destroyer_land_time := 4.0          ## [FREI] Landeanflug
var destroyer_abort_distance := 230.0   ## [ORIGINAL qualitativ] Zerstörer kann Bombardement abbrechen
var destroyer_abort_chance := 0.14      ## [FREI] Chance pro Sekunde, wenn Spieler näher als abort_distance
var destroyer_engage_time := 18.0       ## [FREI] wie lange er sich dem Spieler zuwendet
var planet_max_engaging := 1            ## [FREI] wie viele Zerstörer sich gleichzeitig freiwillig dem Spieler zuwenden
var destroyer_disengage_distance := 380.0  ## [FREI]
var planet_destroyer_altitude := 34.0   ## [FREI] Schwebehöhe über der Stadt
var orbit_period_inner := 480.0         ## [FREI] Umlaufzeit innerster Planet (s)
var orbit_period_outer := 1600.0        ## [FREI] Umlaufzeit äußerster Planet (s)

# ---------------------------------------------------------------------------------------------
#  Orbit-Start (Tutorial)
# ---------------------------------------------------------------------------------------------
var orbit_fighter_count := 9            ## [ORIGINAL] 9 oder 12 Fighter in Dreierwellen

# ---------------------------------------------------------------------------------------------
#  Punkte
# ---------------------------------------------------------------------------------------------
var bonus_squadron_destroyed := 1000    ## [FREI]
var bonus_city_saved := 100             ## [FREI] je verbliebener Stadt, wenn ein Planet gerettet wird
var bonus_station_defended := 500       ## [FREI]
var bonus_orbit_cleared := 250          ## [FREI]
var highscore_entries := 10             ## [FREI]

# ---------------------------------------------------------------------------------------------
#  Feindsystem  (Sprungpunkt oben links auf der Karte)
# ---------------------------------------------------------------------------------------------
var enemy_system_enabled := true        ## [FREI] false = Sprungpunkt nur sichtbar, Schwadrone entstehen direkt am Sprungpunkt (wie 0.9)
var enemy_jump_cost := 20.0             ## [FREI, Vorgabe] Sprung ins Feindsystem und zurück kostet je 20 % Energie
var enemy_jump_duration_factor := 3.0   ## [FREI, Vorgabe] dieser Sprung dauert 3× so lange (roter Hyperraum)
var enemy_city_count_min := 6           ## [FREI, Vorgabe] die 4 äußeren Feindplaneten haben 6–8 Städte …
var enemy_city_count_max := 8           ## [FREI, Vorgabe]
var enemy_home_city_count := 12         ## [FREI, Vorgabe] … die feindliche Heimatwelt 12
var enemy_planet_area_factor := 1.0     ## [Vorgabe 0.13.0] Einsatzgebiet der Feindplaneten × Faktor (Fortgeschritten: Städte weiter verteilt)
var enemy_city_points := 5000           ## [FREI, Vorgabe] Punkte je zerbombter Feindstadt
var victory_all_enemy_cities := true    ## [FREI, Vorgabe] Sieg erst, wenn ALLE Städte im Feindsystem zerstört sind (false = nur die Heimatwelt)
## Empfangskomitee am Sprungpunkt des Feindsystems (nur einmal, siehe reception_once): nur Fighter (keine Zerstörer/Flaggschiffe)
var reception_fighter_count := 12       ## [FREI, Vorgabe] 12 Fighter = 4 Wellen à 3
var reception_once := true              ## [FREI, Vorgabe] nur EIN Empfangskomitee: abgeschossene Fighter kommen nicht wieder (false = bei jedem Sprung neu)
var reception_fire_rate_factor := 2.0   ## [FREI, Vorschlag] deutlich aggressiver: doppelte Feuerrate …
var reception_burst_shots := 2          ## [FREI, Vorschlag] … und Doppelschuss je Feuerstoß
## Verteidiger der Feindstädte: fester Bestand je Planet, Wellen à fighters_per_wave, KEINE Regeneration.
## [ORIGINAL qualitativ] Sie nehmen das eigene Schiff so heftig unter Beschuss, dass zum Bomben keine Zeit bleibt:
## erst die Verteidiger abwehren, dann bombardieren.
var enemy_defenders_min := 9            ## [FREI, Vorschlag] äußere Planeten 9–12 Fighter
var enemy_defenders_max := 12           ## [FREI, Vorschlag]
var enemy_home_defenders := 18          ## [FREI, Vorschlag] Heimatwelt 18 Fighter
var enemy_defender_fire_rate_factor := 2.5   ## [FREI, Vorgabe "heftiger Beschuss"] Feuerrate × gegenüber normalen Fightern (Empfangskomitee: 2.0)
var enemy_defender_burst_shots := 2     ## [FREI, Vorgabe] Schüsse je Feuerstoß der Verteidiger (2 = Doppelschuss)
var enemy_home_fire_rate_factor := 3.0  ## [FREI] dasselbe für die Verteidiger der Heimatwelt
var enemy_home_burst_shots := 2         ## [FREI]
## [FREI] Schaden je Treffer der Fighter im Feindsystem (Empfangskomitee, Verteidiger, Verstärkung), < 0 = fighter_damage.
## Die Senkung von fighter_damage in 0.10.2 galt den Kämpfen gegen Schwadrone. 1,6 hält das Feindsystem so gefährlich
## wie in 0.10.1 (gemessen ~1,9 statt ~2,0 Energie je abgeschossenem Verteidiger – sie sind jetzt schwerer zu treffen).
## 1,8 = alter Trefferwert, gemessen ~15 % gefährlicher als 0.10.1.
var enemy_fighter_damage := 1.6
var enemy_defender_wave_delay := 1.0    ## [FREI, Vorgabe] Pause bis zur nächsten Verteidiger-Welle (s) – zwischen den Wellen bleibt kaum Zeit zum Bomben
var enemy_defender_first_wave := 1.5    ## [FREI] erste Welle nach der Ankunft auf dem Planeten (s)
## [FREI, Vorgabe] Sind die Verteidiger eines Planeten vernichtet, kommt gelegentlich Verstärkung (1–3 Fighter),
## solange dort noch Städte stehen – so lässt sich ein Planet nicht in einem Zug "durchbomben".
var enemy_reinforce_enabled := true
var enemy_reinforce_interval_min := 14.0     ## [FREI] Abstand zweier Verstärkungen (s), gezählt ab der letzten abgeschossenen
var enemy_reinforce_interval_max := 26.0     ## [FREI]
var enemy_reinforce_min := 1                 ## [FREI, Vorgabe] Fighter je Verstärkung
var enemy_reinforce_max := 3                 ## [FREI, Vorgabe]
## Schwadron-Produktion: Schwadrone starten sichtbar von äußeren Planeten mit intakten Städten und fliegen
## zum Sprungpunkt ins Helion-System. Jede zerstörte Stadt auf einem äußeren Planeten verlangsamt die Produktion,
## ohne Städte auf den äußeren Planeten kommt kein neues Schwadron mehr (Heimatwelt produziert nicht).
var enemy_production_slowdown := 0.15   ## [FREI, Vorgabe "spürbar langsamer"] Abstand neuer Schwadrone +15 % je zerstörter Stadt …
var enemy_production_ref_cities := 28   ## [Vorgabe 0.13.0] … bezogen auf 28 äußere Städte: bei mehr Städten (Fortgeschritten) wirkt
										## jede einzelne entsprechend schwächer – die Bremse verläuft nach dem Anteil zerstörter Städte
var enemy_system_max_squadrons := 3     ## [FREI] höchstens so viele Schwadrone gleichzeitig in einem Feindsystem unterwegs (je System)
var enemy_transit_speed_factor := 2.5   ## [FREI] im eigenen System fliegen Schwadrone schneller (Transit zum Sprungpunkt)
var enemy_first_launch := 25.0          ## [FREI] erster Start im Feindsystem nach Beginn der Kampagne (s)
var bonus_victory := 0                  ## [später] Siegbonus/Militär-Rang – wird nach den Tests festgelegt

# ---------------------------------------------------------------------------------------------
#  Zweites Feindsystem [Vorgabe 0.14.0] (Hart/Experte): 4 Planeten (Heimatwelt + 3 äußere), eigener Stern,
#  KEIN Empfangskomitee, nur über Helion erreichbar (Sprungpunkt unten rechts, Sprung wie nach Vorrhal).
#  Produktion, Verteidiger und Bomben wie in Vorrhal. Beide Systeme teilen sich die Grenze max_squadrons in Helion:
#  am Sprungpunkt wartende Schwadrone springen in der Reihenfolge ihrer Ankunft, egal aus welchem System.
#  Sieg erst, wenn auch dort alle Städte zerstört sind.
# ---------------------------------------------------------------------------------------------
var second_system_mode := 0             ## [Vorgabe] von der Stufe gesetzt: 0 = kein zweites Feindsystem; 1 = es greift an, sobald Vorrhal
										## keine Schwadrone mehr bauen kann (Hart); 2 = zusätzlich, sobald in Helion erstmals
										## second_system_empty_time Sekunden lang höchstens second_system_empty_max feindliche Schwadrone
										## sind (Experte; was zuerst eintritt)
var second_system_empty_time := 60.0    ## [Vorgabe] Experte: so lange (s, Strategiezeit, am Stück) …
var second_system_empty_max := 1        ## [Vorgabe 0.14.1] … höchstens so viele feindliche Schwadrone in Helion (0.14.0: keins –
										## griff in den Messungen nie; mit 30 s und höchstens einem griff er einmal schon nach 6 min)
var second_city_count_min := 8          ## [Vorgabe 0.14.1] Städte der 3 äußeren Planeten (0.14.0: 15–17) …
var second_city_count_max := 10         ## [Vorgabe 0.14.1]
var second_home_city_count := 12        ## [Vorgabe 0.14.1] … und der Heimatwelt (0.14.0: 20)
var second_planet_area_factor := 1.0    ## [FREI 0.14.1] Einsatzgebiet der Ixmora-Planeten × Faktor (weniger Städte: Standardgröße, 0.14.0: 1,45)
var second_first_launch := 25.0         ## [FREI] erster Schwadron-Start dort nach dem Erwachen (s)
var second_transit_speed_factor := 0.8  ## [Vorgabe 0.14.1] Schwadrone in Ixmora (Weg zum Sprungpunkt) 20 % langsamer
var squadron_speed_factor := 1.0        ## [Vorgabe 0.14.1] Tempo der Schwadrone in Helion × Faktor (von der Stufe gesetzt: Hart/Experte 1,1;
										## 0.14.0: in allen Systemen)

# ---------------------------------------------------------------------------------------------
#  Bomben  (nur auf Feindplaneten; Waffenwechsel Bordlaser ↔ Bomben manuell mit Q/Tab/X)
# ---------------------------------------------------------------------------------------------
var bombs_max := 10                     ## [FREI, Vorgabe] 10 Bomben – so lässt sich kein System „in einem Zug durchbomben“; Auffüllen nur beim Andocken an eigenen Stationen
var bomb_cooldown := 0.9                ## [FREI] Mindestabstand zweier Abwürfe (s)
var bomb_gravity := 22.0                ## [FREI] Fallbeschleunigung (m/s², arcadehaft)
var bomb_drop_speed := 4.0              ## [FREI] Anfangsgeschwindigkeit nach unten (m/s)
var bomb_forward_speed := 38.0          ## [FREI] Vorwärtsimpuls zusätzlich zur Fluggeschwindigkeit → Aufschlag sichtbar vor dem Schiff
var bomb_hit_radius := 22.0             ## [FREI, Vorgabe "1 Treffer je Stadt"] Treffer, wenn der Aufschlag so nah an der Stadtmitte liegt (m); Fehlwurf = Bombe verloren
var bomb_refill_time := 0.25            ## [FREI] s je Bombe beim Andocken (parallel zum Tanken)
var bomb_camera_pitch := -14.0          ## [FREI] Blick im Bombenmodus nach unten (Grad), damit die Aufschlagmarke auch im Stand über dem Scanner liegt

# ---------------------------------------------------------------------------------------------
#  Darstellung (keine Spiellogik)
# ---------------------------------------------------------------------------------------------
var offscreen_indicators := true        ## [FREI] Pfeile am Bildrand zu Gegnern außerhalb der Sicht
var scanner_heading_up := true          ## [FREI] Planetenscanner dreht mit (Flugrichtung oben)
var screen_shake := 1.0                 ## [FREI]
var hit_flash_min_gap := 0.5            ## [FREI, fotosicher] Treffer-Farbblitze und rote Trefferkante höchstens alle … s (≤ 2/s)

# ---------------------------------------------------------------------------------------------
#  Audio-Warnungen
# ---------------------------------------------------------------------------------------------
var alarm_duration := 5.0               ## [FREI] Alarmsignal (Orbit, Stationsangriff, Landung) höchstens so lange (s); 0 = aus
var alarm_fade := 0.4                   ## [FREI] Ausblenden am Ende des Alarms (liegt innerhalb von alarm_duration)
var ticker_alert_cooldown := 6.0        ## [FREI] Mindestabstand der Hinweistöne für Meldungen aus dem System (s)


# =============================================================================================
#  Hilfsfunktionen
# =============================================================================================
var _defaults := {}
var _overridden := {}   ## Schlüssel, die eine balance.cfg ausdrücklich setzt (gehen den Schwierigkeitsstufen vor)


func _ready() -> void:
	for p in _value_properties():
		_defaults[p] = _copy(get(p))
	_load_overrides()
	_write_template()


func _value_properties() -> PackedStringArray:
	var out := PackedStringArray()
	for p in get_property_list():
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and not String(p.name).begins_with("_"):
			out.append(p.name)
	return out


func _copy(v: Variant) -> Variant:
	if v is Array:
		return (v as Array).duplicate(true)
	return v


## Lädt balance.cfg (neben der .exe/Binärdatei, danach user://) und überschreibt passende Werte.
func _load_overrides() -> void:
	var paths := [OS.get_executable_path().get_base_dir().path_join("balance.cfg"), "user://balance.cfg"]
	# Testhilfe: zusätzliche Datei per Kommandozeile ("-- --balance=/pfad/datei.cfg"), z. B. für Balancing-Läufe
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--balance="):
			paths.append(a.substr(10))
	for path in paths:
		if not FileAccess.file_exists(path):
			continue
		var cf := ConfigFile.new()
		if cf.load(path) != OK:
			push_warning("balance.cfg konnte nicht gelesen werden: " + path)
			continue
		if not cf.has_section("balance"):
			continue
		for key in cf.get_section_keys("balance"):
			if key in _defaults:
				var v: Variant = cf.get_value("balance", key)
				var cur: Variant = get(key)
				if typeof(cur) == TYPE_FLOAT and (typeof(v) == TYPE_INT):
					v = float(v)
				if typeof(cur) == TYPE_INT and typeof(v) == TYPE_FLOAT:
					v = int(v)
				if typeof(cur) == TYPE_BOOL and (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT):
					v = bool(v)
				if typeof(cur) == TYPE_ARRAY:
					var flat: bool = not (cur as Array).is_empty() and typeof((cur as Array)[0]) != TYPE_ARRAY
					if flat and (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT):
						v = [v]          # Einzelwert für eine flache Liste: gilt für alle Einträge
					elif typeof(v) >= TYPE_PACKED_BYTE_ARRAY and typeof(v) <= TYPE_PACKED_VECTOR4_ARRAY:
						v = Array(v)
				# Typ VOR dem Setzen prüfen (Vergleiche über Typgrenzen wären ein Laufzeitfehler)
				if typeof(v) != typeof(cur):
					push_warning("[Config] %s: Wert '%s' hat den falschen Typ (%s statt %s) und wurde ignoriert (%s)" % [key, str(v), type_string(typeof(v)), type_string(typeof(cur)), path])
					continue
				set(key, v)
				# nur ein vom Standard abweichender Wert geht den Schwierigkeitsstufen vor – eine unveränderte Kopie
				# der balance_template.cfg (alle Schlüssel mit Standardwerten) schaltet die Stufen also nicht ab
				if v != _defaults[key]:
					_overridden[key] = true
				print("[Config] Überschrieben: %s = %s (%s)" % [key, str(v), path])


## Schwierigkeitsstufe übernehmen (Settings.apply): setzt die Werte der Stufe, außer balance.cfg-Schlüsseln.
## Schlüssel, die nur andere Stufen setzen, gehen auf ihren Standardwert zurück (z. B. squadron_speed_factor nach Hart).
func apply_difficulty(idx: int) -> void:
	var lvl: Dictionary = difficulty_level(idx)
	for l in DIFFICULTY_LEVELS:
		for key in l.values:
			if not _overridden.has(key):
				set(key, _copy(lvl.values[key] if lvl.values.has(key) else _defaults[key]))


func difficulty_level(idx: int) -> Dictionary:
	return DIFFICULTY_LEVELS[clampi(idx, 0, DIFFICULTY_LEVELS.size() - 1)]


## Beschreibung einer Stufe mit den aktuellen Auslöserwerten (Experte; auch mit balance.cfg richtig).
func difficulty_desc(idx: int) -> String:
	var n := second_system_empty_max
	var what := "kein Schwadron" if n <= 0 else ("höchstens ein Schwadron" if n == 1 else "höchstens %d Schwadrone" % n)
	return str(difficulty_level(idx).desc).replace("{empty_time}", str(int(round(second_system_empty_time)))).replace("{empty_max}", what)


func _write_template() -> void:
	var cf := ConfigFile.new()
	for p in _value_properties():
		cf.set_value("balance", p, _defaults[p])
	cf.save("user://balance_template.cfg")


## Gibt einen Wert aus einem Farb-Array (blau/grün/rot) zurück.
func by_color(arr: Array, color: int) -> Variant:
	return arr[clampi(color, 0, arr.size() - 1)]


func destroyer_hits_needed(color: int) -> int:
	return int(by_color(destroyer_shields, color)) + 1
