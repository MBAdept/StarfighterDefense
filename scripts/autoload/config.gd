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
var difficulty_scale := 1.0             ## [FREI] Schwierigkeit (Optionen: 0.75 / 1.0 / 1.3): Gegnerschaden ×s, Schwadron-Tempo ×√s, Abstand neuer Schwadrone ÷s^0.7

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
var jump_cost_min := 3.0                ## [FREI] Mindestkosten eines Sprungs
var jump_cost_max := 15.0               ## [VERMUTET] im Heimatsystem bis ca. 15 %
var jump_cost_distance_ref := 850.0     ## [FREI] Kartendistanz, bei der jump_cost_max erreicht wird
var jump_can_kill := false              ## [FREI] false = ein Sprung lässt mindestens jump_min_energy_left übrig (kein Softlock)
var jump_min_energy_left := 1.0         ## [FREI]
var jump_duration := 1.7                ## [FREI] Dauer des Sprungeffekts

# ---------------------------------------------------------------------------------------------
#  Raumstation: Andocken / Tanken
# ---------------------------------------------------------------------------------------------
var station_count := 2                  ## [ORIGINAL] 2 Raumstationen
var dock_slide_time := 3.2              ## [ORIGINAL] Station fährt von links bis zur Bildmitte
var refuel_rate := 10.0                 ## [ORIGINAL] ca. 10 % pro Sekunde …
var refuel_step := 5.0                  ## [ORIGINAL] … sichtbar in 5-%-Schritten
var station_damage_per_fighter := 0.07  ## [FREI] % Stationsintegrität pro Sekunde und angreifendem Fighter
var station_can_be_destroyed := true    ## [FREI] unverteidigte Stationen können zerstört werden

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
var laser_hit_tolerance := 1.4          ## [FREI] zusätzlicher Trefferradius (m) – macht Zielen fairer
var ion_cooldown := 3.0                 ## [ORIGINAL] Ionen-Kanone: nur 1 Schuss alle 3 Sekunden
var ion_speed := 250.0                  ## [FREI]
var ion_range := 760.0                  ## [FREI]
var ion_hit_tolerance := 2.5            ## [FREI]
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
var fighter_steer := 2.4                ## [FREI] Wendigkeit
var fighter_distance_min := 34.0        ## [FREI] Abstand beim Kreisen um das Fadenkreuz
var fighter_distance_max := 78.0        ## [FREI]
var fighter_orbit_angle_min := 3.0      ## [ORIGINAL] fliegen meist um das Fadenkreuz herum (Winkelabstand, Grad)
var fighter_orbit_angle_max := 17.0     ## [FREI]
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
var fighter_damage := 1.8               ## [ORIGINAL] Treffer kostet sehr wenig Energie
var fighter_shot_speed := 95.0          ## [FREI]

# ---------------------------------------------------------------------------------------------
#  Zerstörer   (Index 0 = blau, 1 = grün, 2 = rot)
# ---------------------------------------------------------------------------------------------
var destroyer_points := [500, 750, 1000]            ## [ORIGINAL]
var destroyer_shields := [1, 2, 3]                  ## [ORIGINAL] Treffer nötig = Schilde + 1 (2/3/4)
var destroyer_osc_amplitude := [7.0, 10.0, 13.0]    ## [ORIGINAL qualitativ] Hin-und-her-Bewegung (Grad) langsam/schneller/noch schneller
var destroyer_osc_speed := [0.32, 0.5, 0.72]        ## [ORIGINAL qualitativ] Bewegungstempo
var destroyer_damage := [9.0, 11.0, 13.0]           ## [VERMUTET] ca. 7–15 % Energieverlust pro Treffer
var destroyer_fire_interval := [6.0, 5.2, 4.5]      ## [FREI]
var destroyer_first_fire_min := 0.45                ## [FREI] erster Schuss nach Erscheinen = Intervall × 0,45–0,7
var destroyer_first_fire_max := 0.7                 ## [FREI] (vorher 0,6–0,9: blaue waren oft vernichtet, bevor sie schossen)
var destroyer_hit_chance := 0.72                    ## [FREI]
var destroyer_shot_speed := 72.0                    ## [FREI]
var destroyer_offscreen_margin := 11.0              ## [ORIGINAL] steht knapp außerhalb des Sichtfelds (Grad jenseits des Bildrands)
var destroyer_distance := 88.0                      ## [FREI]
var destroyer_next_delay := 2.6                     ## [ORIGINAL] Zerstörer kommen nacheinander
var destroyer_size_scale := 1.25                    ## [FREI] Modellgröße

# ---------------------------------------------------------------------------------------------
#  Flaggschiff
# ---------------------------------------------------------------------------------------------
var flagship_points := 5000             ## [ORIGINAL]
var flagship_charge_time := 13.0        ## [ORIGINAL] lange Vorlaufzeit; Quadrat wird langsam heller
var flagship_vulnerable_time := 2.0     ## [ORIGINAL] nur kurz vor dem Schuss verwundbar
var flagship_cooldown := 4.5            ## [FREI] Pause nach dem Schuss
var flagship_damage := 35.0             ## [VERMUTET] gut ein Drittel der Energie
var flagship_hit_chance := 0.9          ## [FREI] (Ausweichen halbiert)
var flagship_shot_speed := 115.0        ## [FREI]
var flagship_distance := 195.0          ## [FREI]
var flagship_retreat_delay := 10.0      ## [FREI] nach Vernichtung des Schwadrons zieht es sich zurück
var flagship_weakpoint_radius := 5.0    ## [FREI] Trefferradius des rosa Quadrats (m)

# ---------------------------------------------------------------------------------------------
#  Schwadrone (Übersichtskarte)
# ---------------------------------------------------------------------------------------------
var max_squadrons := 4                  ## [ORIGINAL] bis zu 4 gleichzeitig
var squadron_fighters_min := 3          ## [ORIGINAL] 3–12 Fighter
var squadron_fighters_max := 12         ## [ORIGINAL]
var squadron_fighters_start_min := 5    ## [FREI] Mindest-Fighterzahl der ersten Stufen (Stufe 1–2: 5–8 Fighter), ab Stufe 3 unverändert
var squadron_fighters_start_max := 8    ## [FREI]
var squadron_destroyers_min := 1        ## [ORIGINAL] 1–3 Zerstörer
var squadron_destroyers_max := 3        ## [ORIGINAL]
var squadron_speed_min := 1.0           ## [ORIGINAL qualitativ] sehr langsam; kleineres Schwadron = langsamer (Karteneinheiten/s)
var squadron_speed_max := 3.3           ## [FREI]
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
#  Feindsystem (Platzhalter)
# ---------------------------------------------------------------------------------------------
var enemy_system_enabled := false       ## Sprungpunkt sichtbar, aber "in Vorbereitung"

# ---------------------------------------------------------------------------------------------
#  Darstellung (keine Spiellogik)
# ---------------------------------------------------------------------------------------------
var offscreen_indicators := true        ## [FREI] Pfeile am Bildrand zu Gegnern außerhalb der Sicht
var scanner_heading_up := true          ## [FREI] Planetenscanner dreht mit (Flugrichtung oben)
var screen_shake := 1.0                 ## [FREI]

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
				print("[Config] Überschrieben: %s = %s (%s)" % [key, str(v), path])


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
