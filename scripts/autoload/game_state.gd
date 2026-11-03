extends Node
## =============================================================================================
##  Strategische Spielwelt: Planeten, Stationen, Schwadrone, Energie, Punkte – und Simulation.
##  Kampfszenen lesen/schreiben diesen Zustand direkt; dadurch bleibt ein unterbrochener Kampf
##  (verbleibende Gegner, Schäden) erhalten, wenn man später zurückspringt.   [ORIGINAL]
## =============================================================================================

signal changed
signal event_logged(text: String, severity: int)
## Warnmeldung mit Art (landing, city, station_attack, station_lost) und Bezug (Planet-/Stations-ID)
signal alert_raised(kind: String, ref: int)
signal energy_changed(value: float, delta: float)
signal score_changed(value: int, delta: int, reason: String)
signal squadron_spawned(sq: SquadronData)
signal squadron_landed(sq: SquadronData, planet: PlanetData)
signal squadron_at_station(sq: SquadronData, station: StationData)
signal squadron_destroyed(sq: SquadronData)
signal city_destroyed(planet: PlanetData, city_index: int)
signal station_destroyed(station: StationData)
signal planet_saved(planet: PlanetData)
## Spielende: reason = "energy" | "cities" (Game Over), "victory" (Sieg), "abort" (vorzeitiger Abbruch)
signal game_over_triggered(reason: String)
signal enemy_city_destroyed(planet: PlanetData, city_index: int)
signal enemy_squadron_launched(sq: SquadronData, planet: PlanetData)
signal defenders_changed(planet: PlanetData)
signal bombs_changed(value: int)

## ENEMY_SYSTEM = Ankunftspunkt im Feindsystem (Empfangskomitee), ENEMY_PLANET = Feindplanet,
## HOME_SYSTEM = Sprungziel "zurück ins Helion-System" (nur als Sprungziel auf der Feindkarte)
enum Loc { NONE, HOME_ORBIT, PLANET, STATION, SQUADRON, SPACE, ENEMY_SYSTEM, ENEMY_PLANET, HOME_SYSTEM }
enum Sev { INFO, GOOD, WARN, ALERT }

const MAP_SIZE := Vector2(1600, 900)
const JUMP_POINT := Vector2(-712, -372)     ## [ORIGINAL] Sprungpunkt zum Feindsystem: oben links
const STAR_NAME := "Helion"
const ENEMY_GATE := Vector2(712, 372)       ## [FREI] Sprungpunkt im Feindsystem zurück nach Helion: unten rechts
const ENEMY_STAR_NAME := "Vorrhal"

## [FREI] Feindsystem: 5 Planeten (die Heimatwelt innen) und ein Stern
const ENEMY_PLANET_DEFS := [
	{"name": "Xhal", "type": "alien_home", "radius": 152.0, "home": true},
	{"name": "Kethra", "type": "alien_crimson", "radius": 224.0},
	{"name": "Uzhul", "type": "alien_spore", "radius": 288.0},
	{"name": "Drauth", "type": "alien_ash", "radius": 349.0},
	{"name": "Myrrax", "type": "alien_crystal", "radius": 408.0},
]
const ENEMY_CITY_NAMES := ["Kh'tor", "Ulmaz", "Varkesh", "Druun", "Ssarak", "Ix-Thul", "Morgra", "Kezzar",
	"Tholl", "Vyrr", "Ashkar", "Gruvak", "Zeth", "Oruun", "Kavrax", "Yllith", "Nazzur", "Thraak", "Quorth",
	"Ixxa", "Brakk", "Selvoth", "Gorrun", "Vashti"]

## [FREI] Planeten (Vorschlag 6–8). Bei planet_count < 8 entfallen die äußeren (Heimat bleibt).
const PLANET_DEFS := [
	{"name": "Pyra", "type": "volcanic", "radius": 90.0},
	{"name": "Aurelia", "type": "desert", "radius": 138.0},
	{"name": "Halcyon", "type": "terran", "radius": 190.0, "home": true},
	{"name": "Thessa", "type": "jungle", "radius": 243.0},
	{"name": "Morrow", "type": "ocean", "radius": 296.0},
	{"name": "Kryos", "type": "ice", "radius": 349.0},
	{"name": "Nyx", "type": "toxic", "radius": 401.0},
	{"name": "Cinder", "type": "barren", "radius": 440.0},
]
const STATION_DEFS := [
	{"name": "Station Alpha", "radius": 164.0},
	{"name": "Station Beta", "radius": 322.0},
]
const CITY_NAMES := ["Nordhafen", "Sonnwacht", "Eisentor", "Lichtau", "Kuppelstadt", "Westring",
	"Silberbucht", "Hochfeld", "Morgenrot", "Sternfall", "Grünhain", "Felsgrund", "Neumark",
	"Ostwall", "Lumen", "Taltreu", "Wolkenheim", "Ankerplatz"]

var rng := RandomNumberGenerator.new()

var running := false            ## Strategie-Simulation aktiv (erst nach dem Orbit-Kampf)
var paused_by_scene := false
var time_scale := 1.0           ## Testfunktion (F7)
var sim_time := 0.0
var level := 0
var energy := 100.0
var score := 0
var game_over := false
var game_over_reason := ""
var tutorial_done := false
var warned_energy_stage := 0    ## zuletzt gewarnte Energie-Warnstufe (damit Sprünge den Warnstoß auslösen)

var planets: Array = []         ## PlanetData (Helion)
var stations: Array = []        ## StationData
var squadrons: Array = []       ## SquadronData im Helion-System
var enemy_planets: Array = []   ## PlanetData (Feindsystem, is_enemy = true)
var enemy_squadrons: Array = [] ## SquadronData im Feindsystem (auf dem Weg zum Sprungpunkt)
var player_system := 0          ## 0 = Helion-System, 1 = Feindsystem
var bombs := 15
var reception_active := false   ## Empfangskomitee am Ankunftspunkt noch nicht abgewehrt
var reception_left := 0         ## [Vorgabe] Fighter des (einzigen) Empfangskomitees, die noch leben (Config.reception_once)
var production_progress := 0.0  ## 0..1 bis zum nächsten Schwadron-Start im Feindsystem
var victory := false
var end_kind := ""              ## "gameover" | "victory" | "abort" – für die Auswertung
var in_game := false            ## eine Partie läuft (Titel/Auswertung: false)
var play_time := 0.0            ## echte Spielzeit inkl. Orbit-Start, ohne Pausen
var _production_stop_logged := false

var player_loc := Loc.NONE
var player_loc_id := -1
var player_map_pos := Vector2.ZERO

var spawn_timer := 0.0
var next_squadron_id := 1
var events: Array = []          ## [{t, text, sev}]
var stats := {}
var _changed_accum := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	rng.randomize()


# =============================================================================================
#  Neues Spiel
# =============================================================================================
func new_game() -> void:
	rng.randomize()
	running = false
	sim_time = 0.0
	time_scale = 1.0
	level = 0
	energy = Config.energy_start
	score = 0
	game_over = false
	game_over_reason = ""
	tutorial_done = false
	warned_energy_stage = 0
	events.clear()
	squadrons.clear()
	planets.clear()
	stations.clear()
	enemy_planets.clear()
	enemy_squadrons.clear()
	player_system = 0
	bombs = Config.bombs_max
	reception_active = false
	reception_left = Config.reception_fighter_count
	production_progress = 0.0
	victory = false
	end_kind = ""
	in_game = true
	play_time = 0.0
	_production_stop_logged = false
	next_squadron_id = 1
	spawn_timer = Config.spawn_interval_start
	stats = {"fighters": 0, "destroyers": 0, "flagships": 0, "squadrons": 0, "cities_lost": 0,
		"planets_saved": 0, "stations_defended": 0, "jumps": 0, "energy_refueled": 0.0,
		"enemy_cities": 0, "bombs_dropped": 0, "bombs_hit": 0, "enemy_jumps": 0, "receptions": 0,
		"enemy_squadrons_intercepted": 0,
		"points": {"fighters": 0, "destroyers": 0, "flagships": 0, "enemy_cities": 0, "bonus": 0}}
	_create_planets()
	_create_stations()
	_create_enemy_planets()
	var home := home_planet()
	player_loc = Loc.HOME_ORBIT
	player_loc_id = home.id
	player_map_pos = home.map_pos()
	changed.emit()


func _create_planets() -> void:
	var count := clampi(Config.planet_count, 3, PLANET_DEFS.size())
	var defs := []
	for i in PLANET_DEFS.size():
		defs.append(PLANET_DEFS[i])
	while defs.size() > count:
		# äußere Planeten zuerst entfernen, Heimat bleibt
		for j in range(defs.size() - 1, -1, -1):
			if not defs[j].get("home", false):
				defs.remove_at(j)
				break
	var r_in: float = defs[0].radius
	var r_out: float = defs[-1].radius
	for i in defs.size():
		var d: Dictionary = defs[i]
		var p := PlanetData.new()
		p.id = i
		p.name = d.name
		p.type = d.type
		p.orbit_radius = d.radius
		p.is_home = d.get("home", false)
		p.angle = rng.randf() * TAU
		# [FREI] Kepler-ähnlich: innen schneller
		var t := 0.0 if r_out == r_in else (p.orbit_radius - r_in) / (r_out - r_in)
		var period := lerpf(Config.orbit_period_inner, Config.orbit_period_outer, t)
		p.angular_speed = TAU / period
		p.seed = rng.randi()
		var n := Config.home_city_count if p.is_home else rng.randi_range(Config.city_count_min, Config.city_count_max)
		_layout_cities(p, n)
		planets.append(p)


func _layout_cities(p: PlanetData, n: int, name_pool: Array = CITY_NAMES) -> void:
	var lr := RandomNumberGenerator.new()
	lr.seed = p.seed
	var area := Config.planet_area_radius * 0.74
	var min_dist := 92.0
	var names := name_pool.duplicate()
	for i in names.size():
		var j := lr.randi_range(0, names.size() - 1)
		var tmp = names[i]
		names[i] = names[j]
		names[j] = tmp
	var tries := 0
	while p.city_pos.size() < n and tries < 5000:
		tries += 1
		var a := lr.randf() * TAU
		var r := sqrt(lr.randf()) * area
		var pos := Vector2(cos(a), sin(a)) * r
		var ok := pos.length() > 60.0
		for q in p.city_pos:
			if q.distance_to(pos) < min_dist:
				ok = false
				break
		if ok:
			p.city_pos.append(pos)
			p.cities.append(true)
			p.city_variant.append(lr.randi_range(0, 2))
			p.city_names.append(names[p.city_names.size() % names.size()])
		if tries % 800 == 0:
			min_dist *= 0.9


## [FREI] Feindsystem: Heimatwelt (12 Städte) innen, 4 äußere Planeten (6–8 Städte); feste Verteidiger je Planet.
func _create_enemy_planets() -> void:
	var r_in: float = ENEMY_PLANET_DEFS[0].radius
	var r_out: float = ENEMY_PLANET_DEFS[-1].radius
	for i in ENEMY_PLANET_DEFS.size():
		var d: Dictionary = ENEMY_PLANET_DEFS[i]
		var p := PlanetData.new()
		p.id = i
		p.name = d.name
		p.type = d.type
		p.orbit_radius = d.radius
		p.is_home = d.get("home", false)
		p.is_enemy = true
		p.angle = rng.randf() * TAU
		var t := (p.orbit_radius - r_in) / maxf(r_out - r_in, 1.0)
		p.angular_speed = -TAU / lerpf(Config.orbit_period_inner, Config.orbit_period_outer, t)   # Gegenlauf zu Helion
		p.seed = rng.randi()
		var n := Config.enemy_home_city_count if p.is_home else rng.randi_range(Config.enemy_city_count_min, Config.enemy_city_count_max)
		_layout_cities(p, n, ENEMY_CITY_NAMES)
		p.defenders = Config.enemy_home_defenders if p.is_home else rng.randi_range(Config.enemy_defenders_min, Config.enemy_defenders_max)
		p.defenders_initial = p.defenders
		enemy_planets.append(p)


func _create_stations() -> void:
	for i in mini(Config.station_count, STATION_DEFS.size()):
		var d: Dictionary = STATION_DEFS[i]
		var s := StationData.new()
		s.id = i
		s.name = d.name
		s.orbit_radius = d.radius
		s.angle = rng.randf() * TAU
		s.angular_speed = TAU / lerpf(Config.orbit_period_inner, Config.orbit_period_outer, 0.5) * (1.0 if i % 2 == 0 else -0.8)
		stations.append(s)


## Nach dem Orbit-Kampf: Strategie-Simulation starten.  [ORIGINAL] erst danach ist die Karte offen
func start_campaign() -> void:
	if running:
		return
	tutorial_done = true
	running = true
	spawn_timer = Config.spawn_interval_start
	# erster Start im Feindsystem nach enemy_first_launch Sekunden (danach Takt current_production_interval)
	production_progress = clampf(1.0 - Config.enemy_first_launch / maxf(current_production_interval(), 1.0), 0.0, 0.99)
	var lvls: Array = Config.initial_squadron_levels
	for i in Config.initial_squadrons:
		var lvl: int = 0 if lvls.is_empty() else clampi(int(lvls[mini(i, lvls.size() - 1)]), 0, Config.difficulty_max_level)
		_spawn_squadron(lvl, 0.25 + 0.2 * i)
	log_event("Feindliche Schwadrone im %s-System gesichtet!" % STAR_NAME, Sev.WARN)


# =============================================================================================
#  Simulation
# =============================================================================================
func _process(delta: float) -> void:
	if in_game and not game_over:
		play_time += delta
	if not running or game_over:
		return
	var dt := delta * time_scale
	sim_time += dt
	var new_level := mini(int(sim_time / Config.difficulty_level_time), Config.difficulty_max_level)
	if new_level > level:
		level = new_level
		log_event("Der Feind verstärkt seine Angriffe (Stufe %d)." % (level + 1), Sev.WARN)
	for p in planets:
		p.angle = wrapf(p.angle + p.angular_speed * dt, 0.0, TAU)
	for s in stations:
		if not s.destroyed:
			s.angle = wrapf(s.angle + s.angular_speed * dt, 0.0, TAU)
	for ep in enemy_planets:
		ep.angle = wrapf(ep.angle + ep.angular_speed * dt, 0.0, TAU)
	_update_spawning(dt)
	for sq in squadrons.duplicate():
		_update_squadron(sq, dt)
	for esq in enemy_squadrons.duplicate():
		_update_enemy_squadron(esq, dt)
	_update_player_map_pos()
	_changed_accum += dt
	if _changed_accum > 0.2:
		_changed_accum = 0.0
		changed.emit()


func _update_spawning(dt: float) -> void:
	if not Config.enemy_system_enabled:
		# ohne Feindsystem (wie 0.9): neue Schwadrone erscheinen direkt am Sprungpunkt
		if squadrons.size() >= Config.max_squadrons:
			return
		spawn_timer -= dt
		if spawn_timer <= 0.0:
			_spawn_squadron(level, 0.0)
			spawn_timer = current_spawn_interval()
		return
	# Feindsystem: Produktion auf den äußeren Planeten mit intakten Städten
	if not enemy_production_active():
		if not _production_stop_logged:
			_production_stop_logged = true
			log_event("Die feindliche Produktion ist zum Erliegen gekommen – keine neuen Schwadrone mehr!", Sev.GOOD)
		return
	if enemy_squadrons.size() >= Config.enemy_system_max_squadrons:
		return
	production_progress += dt / maxf(current_production_interval(), 1.0)
	if production_progress >= 1.0:
		production_progress = 0.0
		var p := _pick_production_planet()
		if p:
			_launch_enemy_squadron(p, level)


func current_spawn_interval() -> float:
	var base := maxf(Config.spawn_interval_min, Config.spawn_interval_start * pow(Config.spawn_interval_factor, level))
	return base / pow(Config.difficulty_scale, 0.7)


## Abstand zweier Schwadron-Starts im Feindsystem: Grundtakt × (1 + Verlangsamung je zerstörter Stadt der äußeren Planeten).
func current_production_interval() -> float:
	var oc := outer_enemy_cities()
	return current_spawn_interval() * (1.0 + Config.enemy_production_slowdown * float(oc.y - oc.x))


## Städte der äußeren Feindplaneten: x = intakt, y = gesamt.
func outer_enemy_cities() -> Vector2i:
	var alive := 0
	var total := 0
	for p in enemy_planets:
		if not p.is_home:
			alive += p.alive_cities()
			total += p.cities.size()
	return Vector2i(alive, total)


func enemy_production_active() -> bool:
	return Config.enemy_system_enabled and outer_enemy_cities().x > 0


## Relative Produktionsrate (1.0 = volle Produktion, 0 = gestoppt) – für die Anzeige.
func enemy_production_rate() -> float:
	if not enemy_production_active():
		return 0.0
	return current_spawn_interval() / maxf(current_production_interval(), 0.001)


## Restzeit bis zum nächsten Start im Feindsystem (s); -1 = kein Start (gestoppt oder Höchstzahl erreicht).
func next_launch_eta() -> float:
	if not enemy_production_active() or enemy_squadrons.size() >= Config.enemy_system_max_squadrons:
		return -1.0
	return (1.0 - production_progress) * current_production_interval()


func _pick_production_planet() -> PlanetData:
	var cands := []
	var total := 0.0
	for p in enemy_planets:
		if not p.is_home and p.alive_cities() > 0:
			cands.append(p)
			total += float(p.alive_cities())
	if cands.is_empty():
		return null
	var r := rng.randf() * total
	for p in cands:
		r -= float(p.alive_cities())
		if r <= 0.0:
			return p
	return cands[-1]


## [FREI] Ein Schwadron startet sichtbar von einem Feindplaneten und fliegt zum Sprungpunkt nach Helion.
func _launch_enemy_squadron(p: PlanetData, lvl: int, start_progress := 0.0) -> SquadronData:
	var sq := _make_squadron(lvl)
	sq.system = 1
	sq.origin = p.name
	sq.map_pos = p.map_pos()
	sq.target_kind = SquadronData.TargetKind.GATE
	sq.target_id = 0
	if start_progress > 0.0:
		sq.map_pos = sq.map_pos.lerp(ENEMY_GATE, start_progress)
	enemy_squadrons.append(sq)
	log_event("Feindsystem: %s startet von %s." % [sq.name, p.name], Sev.INFO)
	enemy_squadron_launched.emit(sq, p)
	return sq


func _update_enemy_squadron(sq: SquadronData, dt: float) -> void:
	if is_player_at_squadron(sq):
		return   # im Kampf mit dem Spieler: Schwadron hält an
	match sq.state:
		SquadronData.State.TRANSIT:
			var to := ENEMY_GATE - sq.map_pos
			var dist := to.length()
			var step := enemy_squadron_speed(sq) * dt
			if dist <= maxf(step, Config.squadron_arrival_radius):
				sq.map_pos = ENEMY_GATE
				sq.state = SquadronData.State.WAITING
				_try_transfer(sq)
			else:
				sq.map_pos += to / dist * step
		SquadronData.State.WAITING:
			_try_transfer(sq)


func enemy_squadron_speed(sq: SquadronData) -> float:
	return squadron_speed(sq) * Config.enemy_transit_speed_factor


## Schwadron am Sprungpunkt des Feindsystems springt ins Helion-System (sonst wartet es, bis dort Platz ist).
func _try_transfer(sq: SquadronData) -> void:
	if squadrons.size() >= Config.max_squadrons:
		return
	enemy_squadrons.erase(sq)
	sq.system = 0
	sq.state = SquadronData.State.TRANSIT
	sq.map_pos = JUMP_POINT
	sq.stop_clock = 0.0
	_choose_target(sq)
	squadrons.append(sq)
	log_event("Neues feindliches Schwadron aus dem Feindsystem! Ziel: %s" % squadron_target_name(sq), Sev.WARN)
	squadron_spawned.emit(sq)


func _update_squadron(sq: SquadronData, dt: float) -> void:
	match sq.state:
		SquadronData.State.TRANSIT:
			if is_player_at_squadron(sq):
				return   # im Kampf mit dem Spieler: Schwadron hält an
			if not _target_valid(sq):
				_choose_target(sq)
			if is_squadron_stopped(sq):
				sq.stop_clock += dt
				return
			if Config.single_destroyer_stops and sq.fighters == 0 and sq.destroyers.size() == 1:
				sq.stop_clock += dt
			var tp := squadron_target_pos(sq)
			var to := tp - sq.map_pos
			var dist := to.length()
			var step := squadron_speed(sq) * dt
			if dist <= maxf(step, Config.squadron_arrival_radius):
				_arrive(sq)
			else:
				sq.map_pos += to / dist * step
		SquadronData.State.LANDED:
			var p: PlanetData = planets[sq.target_id]
			sq.map_pos = p.map_pos()
			if is_player_at_planet(p.id):
				return   # Planetenkampf läuft lokal
			if sq.destroyers.is_empty():
				_liftoff(sq, "Die Jäger verlassen %s." % p.name)
				return
			_abstract_bombard(sq, p, dt)
		SquadronData.State.AT_STATION:
			var s: StationData = stations[sq.target_id]
			sq.map_pos = s.map_pos()
			if is_player_at_station(s.id):
				return
			if sq.fighters <= 0:
				_liftoff(sq, "")
				return
			s.integrity -= Config.station_damage_per_fighter * sq.fighters * dt
			if s.integrity <= 0.0 and Config.station_can_be_destroyed:
				_destroy_station(s)
				_liftoff(sq, "")


## [VERMUTET] Nur noch ein Zerstörer (und keine Fighter): Schwadron bleibt zeitweise stehen.
func is_squadron_stopped(sq: SquadronData) -> bool:
	if not Config.single_destroyer_stops or sq.state != SquadronData.State.TRANSIT or sq.system != 0:
		return false
	if sq.fighters > 0 or sq.destroyers.size() != 1:
		return false
	var cycle := Config.single_destroyer_stop_time + Config.single_destroyer_move_time
	return fmod(sq.stop_clock, cycle) < Config.single_destroyer_stop_time


## [ORIGINAL] Je kleiner das Schwadron, desto langsamer.
func squadron_speed(sq: SquadronData) -> float:
	var t := clampf(sq.strength() / Config.squadron_strength_ref, 0.0, 1.0)
	return lerpf(Config.squadron_speed_min, Config.squadron_speed_max, t) * sqrt(Config.difficulty_scale)


func squadron_target_pos(sq: SquadronData) -> Vector2:
	if sq.target_kind == SquadronData.TargetKind.GATE:
		return ENEMY_GATE
	if sq.target_kind == SquadronData.TargetKind.PLANET:
		return planets[sq.target_id].map_pos()
	return stations[sq.target_id].map_pos()


func squadron_target_name(sq: SquadronData) -> String:
	if sq.target_kind == SquadronData.TargetKind.GATE:
		return "Sprungpunkt nach %s" % STAR_NAME
	if sq.target_kind == SquadronData.TargetKind.PLANET:
		return planets[sq.target_id].name
	return stations[sq.target_id].name


func squadron_eta(sq: SquadronData) -> float:
	if sq.state != SquadronData.State.TRANSIT:
		return 0.0
	var spd := enemy_squadron_speed(sq) if sq.system == 1 else squadron_speed(sq)
	return sq.map_pos.distance_to(squadron_target_pos(sq)) / maxf(spd, 0.01)


func _target_valid(sq: SquadronData) -> bool:
	if sq.target_kind == SquadronData.TargetKind.STATION:
		var s: StationData = stations[sq.target_id]
		return not s.destroyed and sq.fighters > 0 and (s.attacker == -1 or s.attacker == sq.id)
	var p: PlanetData = planets[sq.target_id]
	if sq.destroyers.is_empty():
		return false
	return p.alive_cities() > 0 and (p.landed_squadron == -1 or p.landed_squadron == sq.id)


func _choose_target(sq: SquadronData) -> void:
	var free_stations := []
	for s in stations:
		if not s.destroyed and s.attacker == -1:
			free_stations.append(s)
	# Nur Fighter übrig → Stationen (die werden nur von Fightern angegriffen)  [ORIGINAL]
	var want_station := sq.destroyers.is_empty() or rng.randf() < Config.squadron_station_target_chance
	if sq.fighters > 0 and want_station and not free_stations.is_empty():
		var best: StationData = free_stations[0]
		for s in free_stations:
			if s.map_pos().distance_to(sq.map_pos) < best.map_pos().distance_to(sq.map_pos):
				best = s
		sq.target_kind = SquadronData.TargetKind.STATION
		sq.target_id = best.id
		return
	# Planeten: gewichtet nach Städten und Nähe  [FREI]
	var candidates := []
	var weights := []
	for p in planets:
		if p.alive_cities() == 0:
			continue
		if p.landed_squadron != -1 and p.landed_squadron != sq.id:
			continue
		var targeted := false
		for o in squadrons:
			if o != sq and o.target_kind == SquadronData.TargetKind.PLANET and o.target_id == p.id:
				targeted = true
		var w: float = float(p.alive_cities()) / (1.0 + p.map_pos().distance_to(sq.map_pos) / 280.0)
		if targeted:
			w *= 0.35
		if p.is_home:
			w *= 1.25
		candidates.append(p)
		weights.append(w)
	if candidates.is_empty():
		for p in planets:
			if p.alive_cities() > 0:
				candidates.append(p)
				weights.append(1.0)
	if candidates.is_empty():
		return
	var total := 0.0
	for w in weights:
		total += w
	var r := rng.randf() * total
	for i in candidates.size():
		r -= weights[i]
		if r <= 0.0:
			sq.target_kind = SquadronData.TargetKind.PLANET
			sq.target_id = candidates[i].id
			return
	sq.target_kind = SquadronData.TargetKind.PLANET
	sq.target_id = candidates[-1].id


func _arrive(sq: SquadronData) -> void:
	if sq.target_kind == SquadronData.TargetKind.PLANET:
		var p: PlanetData = planets[sq.target_id]
		if not _target_valid(sq):
			_choose_target(sq)
			return
		sq.state = SquadronData.State.LANDED
		sq.map_pos = p.map_pos()
		p.landed_squadron = sq.id
		# [ORIGINAL] Das Flaggschiff "verschwindet" bei der Landung
		sq.has_flagship = false
		sq.group_city = _pick_group_city(p)
		for i in sq.destroyers.size():
			var d: DestroyerData = sq.destroyers[i]
			d.phase = DestroyerData.Phase.LANDING
			d.timer = Config.destroyer_land_time + i * 3.0   # gestaffelte Landung
			d.city = -1
			d.progress = 0.0
		assign_cities(sq, p)
		log_event("ALARM: Schwadron landet auf %s – Städte in Gefahr!" % p.name, Sev.ALERT, "landing", p.id)
		squadron_landed.emit(sq, p)
	else:
		var s: StationData = stations[sq.target_id]
		if not _target_valid(sq):
			_choose_target(sq)
			return
		sq.state = SquadronData.State.AT_STATION
		sq.map_pos = s.map_pos()
		s.attacker = sq.id
		log_event("ALARM: %s wird angegriffen!" % s.name, Sev.ALERT, "station_attack", s.id)
		squadron_at_station.emit(sq, s)


func _pick_group_city(p: PlanetData) -> int:
	var alive := []
	for i in p.cities.size():
		if p.cities[i]:
			alive.append(i)
	if alive.is_empty():
		return -1
	return alive[rng.randi_range(0, alive.size() - 1)]


## Zerstörer bleiben als Gruppe zusammen: nächstgelegene freie Stadt zum Gruppenzentrum.  [ORIGINAL]
func assign_cities(sq: SquadronData, p: PlanetData) -> void:
	for d in sq.destroyers:
		if d.city < 0 or not p.cities[d.city]:
			d.city = next_city_for(sq, p, d)


func next_city_for(sq: SquadronData, p: PlanetData, d: DestroyerData) -> int:
	if sq.group_city < 0 or not p.cities[sq.group_city]:
		sq.group_city = _pick_group_city(p)
	if sq.group_city < 0:
		return -1
	var center: Vector2 = p.city_pos[sq.group_city]
	var best := -1
	var best_d := INF
	for i in p.cities.size():
		if not p.cities[i]:
			continue
		var taken := false
		for o in sq.destroyers:
			if o != d and o.city == i:
				taken = true
		var dist: float = p.city_pos[i].distance_to(center) + (100000.0 if taken else 0.0)
		if dist < best_d:
			best_d = dist
			best = i
	return best


func _abstract_bombard(sq: SquadronData, p: PlanetData, dt: float) -> void:
	for d in sq.destroyers:
		match d.phase:
			DestroyerData.Phase.LANDING, DestroyerData.Phase.MOVING:
				d.timer -= dt
				if d.timer <= 0.0:
					d.phase = DestroyerData.Phase.BOMBARDING
			DestroyerData.Phase.BOMBARDING:
				if d.city < 0 or not p.cities[d.city]:
					d.city = next_city_for(sq, p, d)
					d.progress = 0.0
					d.phase = DestroyerData.Phase.MOVING
					d.timer = Config.city_move_time
					continue
				d.progress += dt / Config.bombard_time
				if d.progress >= 1.0:
					destroy_city(p, d.city)
					d.progress = 0.0
					d.city = next_city_for(sq, p, d)
					d.phase = DestroyerData.Phase.MOVING
					d.timer = Config.city_move_time
	if p.alive_cities() == 0 and not game_over:
		_liftoff(sq, "%s ist verloren. Das Schwadron zieht weiter." % p.name)


func _liftoff(sq: SquadronData, msg: String) -> void:
	if sq.state == SquadronData.State.LANDED:
		var p: PlanetData = planets[sq.target_id]
		if p.landed_squadron == sq.id:
			p.landed_squadron = -1
	elif sq.state == SquadronData.State.AT_STATION:
		var s: StationData = stations[sq.target_id]
		if s.attacker == sq.id:
			s.attacker = -1
	sq.state = SquadronData.State.TRANSIT
	for d in sq.destroyers:
		d.city = -1
		d.progress = 0.0
	if sq.is_destroyed():
		return
	_choose_target(sq)
	if msg != "":
		log_event(msg, Sev.WARN)


func destroy_city(p: PlanetData, idx: int) -> void:
	if game_over or idx < 0 or idx >= p.cities.size() or not p.cities[idx]:
		return   # nach Spielende (Todessequenz, Abbruch) ändert sich nichts mehr
	p.cities[idx] = false
	stats.cities_lost += 1
	log_event("%s: Stadt %s zerstört! (%d übrig)" % [p.name, p.city_names[idx], p.alive_cities()], Sev.ALERT, "city", p.id)
	city_destroyed.emit(p, idx)
	if total_alive_cities() == 0:
		trigger_game_over("cities")


func _destroy_station(s: StationData) -> void:
	s.destroyed = true
	s.integrity = 0.0
	s.attacker = -1
	log_event("%s wurde zerstört!" % s.name, Sev.ALERT, "station_lost", s.id)
	station_destroyed.emit(s)


## Schwadron direkt im Helion-System am Sprungpunkt (Kampagnenstart, Testfunktionen, ohne Feindsystem).
func _spawn_squadron(lvl: int, start_progress: float) -> SquadronData:
	var sq := _make_squadron(lvl)
	sq.map_pos = JUMP_POINT
	_choose_target(sq)
	if start_progress > 0.0:
		var tp := squadron_target_pos(sq)
		sq.map_pos = sq.map_pos.lerp(tp, start_progress)
	squadrons.append(sq)
	log_event("Neues feindliches Schwadron aus dem Feindsystem! Ziel: %s" % squadron_target_name(sq), Sev.WARN)
	squadron_spawned.emit(sq)
	return sq


## Neues Schwadron (Zusammensetzung nach Stufe), noch ohne Ort und Ziel.
func _make_squadron(lvl: int) -> SquadronData:
	var sq := SquadronData.new()
	sq.id = next_squadron_id
	next_squadron_id += 1
	sq.name = "Schwadron %s" % _greek(sq.id)
	sq.level = lvl
	sq.spawn_time = sim_time
	# Zusammensetzung [ORIGINAL]: 3–12 Fighter, 1–3 Zerstörer, eventuell Flaggschiff; Steigerung [FREI]
	# [FREI] Untergrenze für die ersten Stufen (squadron_fighters_start_min/max), danach wachsend
	var fmin := clampi(maxi(Config.squadron_fighters_start_min, Config.squadron_fighters_min + lvl), Config.squadron_fighters_min, Config.squadron_fighters_max - 3)
	var fmax := clampi(maxi(Config.squadron_fighters_start_max, Config.squadron_fighters_min + 3 + lvl * 2), fmin, Config.squadron_fighters_max)
	sq.fighters = rng.randi_range(fmin, fmax)
	sq.fighters_initial = sq.fighters
	var dmin := Config.squadron_destroyers_min if lvl < 3 else mini(Config.squadron_destroyers_min + 1, Config.squadron_destroyers_max)
	var dmax := mini(Config.squadron_destroyers_min + 1 + lvl, Config.squadron_destroyers_max)
	var dn := rng.randi_range(dmin, maxi(dmin, dmax))
	var weights: Array = Config.destroyer_color_weights[mini(lvl, Config.destroyer_color_weights.size() - 1)]
	for i in dn:
		sq.destroyers.append(DestroyerData.create(_weighted_index(weights)))
	sq.has_flagship = rng.randf() < minf(Config.flagship_chance_base + Config.flagship_chance_per_level * lvl, Config.flagship_chance_max)
	return sq


func _weighted_index(weights: Array) -> int:
	var total := 0.0
	for w in weights:
		total += float(w)
	var r := rng.randf() * total
	for i in weights.size():
		r -= float(weights[i])
		if r <= 0.0:
			return i
	return weights.size() - 1


func _greek(n: int) -> String:
	var g := ["Alpha", "Beta", "Gamma", "Delta", "Epsilon", "Zeta", "Eta", "Theta", "Iota", "Kappa",
		"Lambda", "My", "Ny", "Xi", "Omikron", "Pi", "Rho", "Sigma", "Tau", "Ypsilon", "Phi", "Chi", "Psi", "Omega"]
	var s: String = g[(n - 1) % g.size()]
	if n > g.size():
		s += " %d" % (1 + (n - 1) / g.size())
	return s


# =============================================================================================
#  Ereignisse aus den Kampfszenen
# =============================================================================================
func on_fighter_killed(sq: SquadronData) -> void:
	if game_over:
		return   # Auswertung ist bereits geschrieben
	stats.fighters += 1
	add_score(Config.fighter_points, "", "fighters")
	if sq == null:
		return
	sq.fighters = maxi(sq.fighters - 1, 0)
	# [ORIGINAL] An Stationen: alle Fighter vernichtet → ganzes Schwadron vernichtet
	if sq.state == SquadronData.State.AT_STATION and sq.fighters == 0:
		var s: StationData = stations[sq.target_id]
		sq.destroyers.clear()
		sq.has_flagship = false
		stats.stations_defended += 1
		add_score(Config.bonus_station_defended, "Station verteidigt", "bonus")
		log_event("%s erfolgreich verteidigt!" % s.name, Sev.GOOD)
	_check_squadron(sq)


## Ein Ionen-Treffer auf einen Zerstörer; gibt true zurück, wenn er zerstört wurde.
func on_destroyer_hit(sq: SquadronData, d: DestroyerData) -> bool:
	d.hits_left -= 1
	if d.hits_left > 0:
		return false
	if game_over:
		return true   # zerstört (Optik), zählt aber nicht mehr
	stats.destroyers += 1
	add_score(int(Config.by_color(Config.destroyer_points, d.color)), "", "destroyers")
	if sq:
		sq.destroyers.erase(d)
		if sq.state == SquadronData.State.LANDED and sq.destroyers.is_empty():
			var p: PlanetData = planets[sq.target_id]
			stats.planets_saved += 1
			var bonus := Config.bonus_city_saved * p.alive_cities()
			add_score(bonus, "Planet gerettet", "bonus")
			log_event("%s ist vorerst gerettet! (+%d)" % [p.name, bonus], Sev.GOOD)
			planet_saved.emit(p)
		_check_squadron(sq)
	return true


func on_flagship_killed(sq: SquadronData) -> void:
	if game_over:
		return
	stats.flagships += 1
	add_score(Config.flagship_points, "Flaggschiff", "flagships")
	log_event("Flaggschiff vernichtet! (+%d)" % Config.flagship_points, Sev.GOOD)
	if sq:
		sq.has_flagship = false


func _check_squadron(sq: SquadronData) -> void:
	if sq.state == SquadronData.State.DESTROYED or not sq.is_destroyed():
		return
	# [ORIGINAL] Alle Fighter und Zerstörer vernichtet; Flaggschiff muss nicht zerstört werden
	if sq.state == SquadronData.State.LANDED:
		var p: PlanetData = planets[sq.target_id]
		if p.landed_squadron == sq.id:
			p.landed_squadron = -1
	elif sq.state == SquadronData.State.AT_STATION:
		var s: StationData = stations[sq.target_id]
		if s.attacker == sq.id:
			s.attacker = -1
	sq.state = SquadronData.State.DESTROYED
	squadrons.erase(sq)
	if enemy_squadrons.has(sq):
		enemy_squadrons.erase(sq)
		stats.enemy_squadrons_intercepted += 1
	stats.squadrons += 1
	add_score(Config.bonus_squadron_destroyed, "Schwadron vernichtet", "bonus")
	log_event("%s vernichtet! (+%d)" % [sq.name, Config.bonus_squadron_destroyed], Sev.GOOD)
	if player_loc == Loc.SQUADRON and player_loc_id == sq.id:
		player_loc = Loc.SPACE
		player_loc_id = -1
	squadron_destroyed.emit(sq)
	changed.emit()


# =============================================================================================
#  Spieler: Energie, Punkte, Position, Sprünge
# =============================================================================================
func change_energy(amount: float) -> void:
	if game_over:
		return
	var before := energy
	energy = clampf(energy + amount, 0.0, Config.energy_max)
	energy_changed.emit(energy, energy - before)
	if energy <= 0.0:
		trigger_game_over("energy")


## cat = Punktekategorie für die Auswertung: fighters, destroyers, flagships, enemy_cities, bonus
func add_score(points: int, reason: String, cat := "bonus") -> void:
	if points == 0 or game_over:
		return
	score += points
	var pts: Dictionary = stats.get("points", {})
	pts[cat] = int(pts.get(cat, 0)) + points
	score_changed.emit(score, points, reason)


## Game Over [ORIGINAL]: Energie 0 ("energy") oder alle Städte zerstört ("cities").
func trigger_game_over(reason: String) -> void:
	if game_over:
		return
	_end_game("gameover", reason)


## Sieg: alle Städte im Feindsystem zerstört (Config.victory_all_enemy_cities, sonst nur die Heimatwelt).
func trigger_victory() -> void:
	if game_over:
		return
	victory = true
	if Config.bonus_victory > 0:
		add_score(Config.bonus_victory, "Sieg", "bonus")
	log_event(victory_text(), Sev.GOOD)
	_end_game("victory", "victory")


func victory_text() -> String:
	if Config.victory_all_enemy_cities:
		return "SIEG! Alle Städte im %s-System sind zerstört." % ENEMY_STAR_NAME
	var home := enemy_home()
	return "SIEG! Die feindliche Heimatwelt %s ist gefallen." % (home.name if home else "")


## Vorzeitiger Abbruch (Pausemenü) – führt ebenfalls zur Auswertung.
func abort_game() -> void:
	if game_over or not in_game:
		return
	_end_game("abort", "abort")


func _end_game(kind: String, reason: String) -> void:
	game_over = true
	end_kind = kind
	game_over_reason = reason
	running = false
	reception_active = false
	_log_evaluation()
	game_over_triggered.emit(reason)


## Protokoll jeder Partie (für den Vergleich von Taktiken/Fähigkeiten): Konsole + user://auswertungen.csv
func _log_evaluation() -> void:
	var pts: Dictionary = stats.get("points", {})
	var d := Time.get_datetime_dict_from_system()
	var row := {
		"datum": "%04d-%02d-%02d %02d:%02d" % [d.year, d.month, d.day, d.hour, d.minute],
		"ende": end_kind, "grund": game_over_reason, "punkte": score,
		"fighter": stats.get("fighters", 0), "zerstoerer": stats.get("destroyers", 0),
		"flaggschiffe": stats.get("flagships", 0), "feindstaedte": stats.get("enemy_cities", 0),
		"eigene_staedte_verloren": stats.get("cities_lost", 0), "spielzeit_s": int(play_time),
		"stufe": level + 1, "schwierigkeit": str(Config.difficulty_scale).replace(".", ","), "schwadrone": stats.get("squadrons", 0),
		"abgefangen_im_feindsystem": stats.get("enemy_squadrons_intercepted", 0),
		"bomben_abgeworfen": stats.get("bombs_dropped", 0), "bomben_treffer": stats.get("bombs_hit", 0),
		"spruenge": stats.get("jumps", 0), "spruenge_feindsystem": stats.get("enemy_jumps", 0),
		"punkte_fighter": pts.get("fighters", 0), "punkte_zerstoerer": pts.get("destroyers", 0),
		"punkte_flaggschiffe": pts.get("flagships", 0), "punkte_feindstaedte": pts.get("enemy_cities", 0),
		"punkte_boni": pts.get("bonus", 0),
	}
	var parts := []
	for k in row:
		parts.append("%s=%s" % [k, str(row[k])])
	print("EVALUATION ", " ".join(parts))
	var path := "user://auswertungen.csv"
	var exists := FileAccess.file_exists(path)
	var f := FileAccess.open(path, FileAccess.READ_WRITE if exists else FileAccess.WRITE)
	if f == null:
		return
	if exists:
		f.seek_end()
	else:
		f.store_line(";".join(PackedStringArray(row.keys())))
	var vals := PackedStringArray()
	for k in row:
		vals.append(str(row[k]))
	f.store_line(";".join(vals))
	f.close()


func home_planet() -> PlanetData:
	for p in planets:
		if p.is_home:
			return p
	return planets[0]


func total_alive_cities() -> int:
	var n := 0
	for p in planets:
		n += p.alive_cities()
	return n


func total_cities() -> int:
	var n := 0
	for p in planets:
		n += p.cities.size()
	return n


func squadron_by_id(id: int) -> SquadronData:
	for sq in squadrons:
		if sq.id == id:
			return sq
	for sq in enemy_squadrons:
		if sq.id == id:
			return sq
	return null


## Schwadrone des Systems, in dem sich der Spieler befindet.
func local_squadrons() -> Array:
	return enemy_squadrons if player_system == 1 else squadrons


func enemy_home() -> PlanetData:
	for p in enemy_planets:
		if p.is_home:
			return p
	return enemy_planets[0] if not enemy_planets.is_empty() else null


func enemy_cities_alive() -> int:
	var n := 0
	for p in enemy_planets:
		n += p.alive_cities()
	return n


func enemy_cities_total() -> int:
	var n := 0
	for p in enemy_planets:
		n += p.cities.size()
	return n


## Eine Feindstadt wurde von einer Bombe getroffen.  [Vorgabe] 1 Treffer je Stadt, 5000 Punkte
func destroy_enemy_city(p: PlanetData, idx: int) -> void:
	if game_over or idx < 0 or idx >= p.cities.size() or not p.cities[idx]:
		return
	p.cities[idx] = false
	stats.enemy_cities += 1
	stats.bombs_hit += 1
	add_score(Config.enemy_city_points, "Feindstadt", "enemy_cities")
	log_event("%s: Feindstadt %s zerstört! (%d übrig)" % [p.name, p.city_names[idx], p.alive_cities()], Sev.GOOD)
	enemy_city_destroyed.emit(p, idx)
	if victory_cities_left() == 0:
		trigger_victory()
	elif p.alive_cities() == 0:
		if p.is_home:
			var n := enemy_cities_alive()
			log_event("Heimatwelt %s ausgeschaltet! Noch %d %s im System." % [p.name, n, "Feindstadt" if n == 1 else "Feindstädte"], Sev.GOOD)
		else:
			log_event("%s ist ausgeschaltet – von dort starten keine Schwadrone mehr." % p.name, Sev.GOOD)


## Bis zum Sieg verbleibende Feindstädte: [Vorgabe] alle im Feindsystem (bzw. nur die Heimatwelt, wenn
## Config.victory_all_enemy_cities = false).
func victory_cities_left() -> int:
	if Config.victory_all_enemy_cities:
		return enemy_cities_alive()
	var home := enemy_home()
	return home.alive_cities() if home else 0


## Ein Verteidiger eines Feindplaneten wurde abgeschossen (keine Regeneration).
func on_defender_killed(p: PlanetData) -> void:
	if game_over:
		return
	on_fighter_killed(null)
	if p == null:
		return
	p.defenders = maxi(p.defenders - 1, 0)
	defenders_changed.emit(p)
	if p.defenders == 0:
		log_event("%s: Luftverteidigung ausgeschaltet!" % p.name, Sev.GOOD)


func use_bomb() -> bool:
	if bombs <= 0 or game_over:
		return false
	bombs -= 1
	stats.bombs_dropped += 1
	bombs_changed.emit(bombs)
	return true


## Bomben auffüllen (nur beim Andocken an eigenen Stationen).
func refill_bomb() -> bool:
	if bombs >= Config.bombs_max:
		return false
	bombs += 1
	bombs_changed.emit(bombs)
	return true


func is_player_at_squadron(sq: SquadronData) -> bool:
	return player_loc == Loc.SQUADRON and player_loc_id == sq.id


func is_player_at_planet(pid: int) -> bool:
	return (player_loc == Loc.PLANET) and player_loc_id == pid


func is_player_at_enemy_planet(pid: int) -> bool:
	return player_loc == Loc.ENEMY_PLANET and player_loc_id == pid


## Ankunft im Feindsystem (Sprungpunkt unten rechts). [Vorgabe] Es gibt nur EIN Empfangskomitee: Seine
## Fighter warten bei jeder Ankunft, bis alle abgeschossen sind (Config.reception_once; sonst jedes Mal neu).
func enter_enemy_system() -> void:
	player_system = 1
	reception_active = reception_size() > 0
	if reception_active:
		stats.receptions += 1
	set_player_location(Loc.ENEMY_SYSTEM, -1)


## Fighter des Empfangskomitees bei der nächsten Ankunft.
func reception_size() -> int:
	return reception_left if Config.reception_once else Config.reception_fighter_count


func on_reception_fighter_killed() -> void:
	reception_left = maxi(reception_left - 1, 0)


## Rücksprung ins Helion-System: Ankunft im Tiefraum am Sprungpunkt oben links.
func enter_home_system() -> void:
	player_system = 0
	reception_active = false
	player_loc = Loc.SPACE
	player_loc_id = -1
	player_map_pos = JUMP_POINT
	changed.emit()


## Sprung über die Systemgrenze (ins Feindsystem oder zurück)?
static func is_cross_system(kind: int) -> bool:
	return kind == Loc.ENEMY_SYSTEM or kind == Loc.HOME_SYSTEM


## Sprungkosten zu einem Ziel: über die Systemgrenze fest (enemy_jump_cost), sonst nach Entfernung.
func jump_cost_to(kind: int, to: Vector2) -> float:
	if is_cross_system(kind) and Config.enemy_system_enabled:
		return Config.enemy_jump_cost
	return jump_cost(to)


func effective_jump_cost_to(kind: int, to: Vector2) -> float:
	var c := jump_cost_to(kind, to)
	if not Config.jump_can_kill:
		c = minf(c, maxf(energy - Config.jump_min_energy_left, 0.0))
	return c


func pay_jump_to(kind: int, to: Vector2) -> void:
	stats.jumps += 1
	if is_cross_system(kind):
		stats.enemy_jumps += 1
	change_energy(-effective_jump_cost_to(kind, to))


func is_player_at_station(sid: int) -> bool:
	return player_loc == Loc.STATION and player_loc_id == sid


func set_player_location(loc: Loc, id: int) -> void:
	player_loc = loc
	player_loc_id = id
	_update_player_map_pos()
	changed.emit()


func _update_player_map_pos() -> void:
	match player_loc:
		Loc.PLANET, Loc.HOME_ORBIT:
			if player_loc_id >= 0 and player_loc_id < planets.size():
				player_map_pos = planets[player_loc_id].map_pos()
		Loc.STATION:
			if player_loc_id >= 0 and player_loc_id < stations.size():
				player_map_pos = stations[player_loc_id].map_pos()
		Loc.SQUADRON:
			var sq := squadron_by_id(player_loc_id)
			if sq:
				player_map_pos = sq.map_pos
		Loc.ENEMY_PLANET:
			if player_loc_id >= 0 and player_loc_id < enemy_planets.size():
				player_map_pos = enemy_planets[player_loc_id].map_pos()
		Loc.ENEMY_SYSTEM:
			player_map_pos = ENEMY_GATE


## Sprungkosten abhängig von der Entfernung.  [VERMUTET] im Heimatsystem bis ca. 15 %
func jump_cost(to: Vector2) -> float:
	var d := player_map_pos.distance_to(to)
	var t := clampf(d / Config.jump_cost_distance_ref, 0.0, 1.0)
	return snappedf(lerpf(Config.jump_cost_min, Config.jump_cost_max, t), 0.1)


## Tatsächlicher Energieabzug (ohne Softlock, falls jump_can_kill = false).
func effective_jump_cost(to: Vector2) -> float:
	var c := jump_cost(to)
	if not Config.jump_can_kill:
		c = minf(c, maxf(energy - Config.jump_min_energy_left, 0.0))
	return c


func pay_jump(to: Vector2) -> void:
	stats.jumps += 1
	change_energy(-effective_jump_cost(to))


# =============================================================================================
#  Ereignisprotokoll / Hilfen
# =============================================================================================
func log_event(text: String, sev: int = Sev.INFO, kind := "", ref := -1) -> void:
	events.append({"t": sim_time, "text": text, "sev": sev})
	if events.size() > 40:
		events.pop_front()
	event_logged.emit(text, sev)
	if kind != "":
		alert_raised.emit(kind, ref)


static func format_time(t: float) -> String:
	var s := int(t)
	return "%02d:%02d" % [s / 60, s % 60]


## Debug (F3): sofort ein neues Schwadron.
func debug_spawn_squadron() -> void:
	if planets.is_empty():
		return
	if not running:
		start_campaign()
	_spawn_squadron(level, 0.6)


## Debug: Schwadron direkt auf einem Planeten landen lassen.
func debug_land_squadron_on(p: PlanetData) -> SquadronData:
	if not running:
		start_campaign()
	var sq := _spawn_squadron(level, 0.0)
	sq.target_kind = SquadronData.TargetKind.PLANET
	sq.target_id = p.id
	if p.landed_squadron != -1:
		return squadron_by_id(p.landed_squadron)
	sq.map_pos = p.map_pos()
	_arrive(sq)
	return sq
