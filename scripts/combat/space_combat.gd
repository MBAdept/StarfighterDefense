class_name SpaceCombat
extends CombatBase
## =============================================================================================
##  Weltraumkampf (Cockpit). Modi:
##   ORBIT     – Spielstart im Orbit des Heimatplaneten: 9/12 Fighter in Dreierwellen, nur Laser [ORIGINAL]
##   SQUADRON  – Schwadron im All: erst Fighter (Wellen), dann Zerstörer nacheinander, ggf. Flaggschiff
##   STATION   – Raumstation: ggf. Verteidigung (nur Fighter) [ORIGINAL], danach Andocken + Tanken
##   EMPTY     – leerer Raum (nach Vernichtung eines Schwadrons)
##   RECEPTION – Ankunft in einem Feindsystem: in Vorrhal das Empfangskomitee aus 12 aggressiven Fightern (4 Wellen),
##               danach Ruhe; im zweiten Feindsystem [0.14.0] gibt es keins
##  Steuerung [ORIGINAL]: links/rechts/rauf/runter, kein Rollen, keine freie Rotation.
## =============================================================================================

enum Mode { ORBIT, SQUADRON, STATION, EMPTY, RECEPTION, STAR }
enum Phase { IDLE, FIGHTERS, DESTROYERS, DONE, DOCK_APPROACH, DOCK_CLAMP, REFUEL, DOCKED }

var mode := Mode.EMPTY
var phase := Phase.IDLE
var squadron: SquadronData = null
var station: StationData = null
var orbit_total := 9
var orbit_spawned := 0
var orbit_killed := 0
var orbit_done := false

var yaw := 0.0
var pitch := 0.0
var yaw_rate := 0.0
var pitch_rate := 0.0

var wave := 0
var wave_timer := -1.0
var destroyer_timer := -1.0
var flagship: Flagship = null
var station_node: Node3D = null
var station_ring: Node3D = null
var station_beacons: Array = []
var bg_planet: Node3D = null
var dock_t := 0.0
var dock_from := Vector3.ZERO
var refuel_t := 0.0
var bomb_t := 0.0
var _repaired := ""           ## beim Andocken reparierter Systemschaden (Meldung)
var _station_was_occupied := false   ## [0.14.2] Verteidigung einer besetzten Station (Meldung „befreit“)
var _cam_center_from := Vector2.ZERO
var _done_handled := false
var arrival_home := false
var arrival_note := ""
var _sun_dir := Vector3(0.4, 0.3, -1.0)


static func create_orbit(skip := false) -> SpaceCombat:
	var s := SpaceCombat.new()
	s.mode = Mode.ORBIT
	s.orbit_done = skip or GameState.tutorial_done
	return s


static func create_squadron(sq: SquadronData) -> SpaceCombat:
	var s := SpaceCombat.new()
	s.mode = Mode.SQUADRON
	s.squadron = sq
	return s


static func create_station(st: StationData) -> SpaceCombat:
	var s := SpaceCombat.new()
	s.mode = Mode.STATION
	s.station = st
	return s


## arrival_home = true: Ankunft nach dem Rücksprung aus einem Feindsystem (an dessen Sprungpunkt in Helion)
## note: Hinweis bei der Ankunft (z. B. Ziel-Schwadron ist inzwischen weitergesprungen)
static func create_empty(arrival_home := false, note := "") -> SpaceCombat:
	var s := SpaceCombat.new()
	s.mode = Mode.EMPTY
	s.arrival_home = arrival_home
	s.arrival_note = note
	return s


static func create_reception() -> SpaceCombat:
	var s := SpaceCombat.new()
	s.mode = Mode.RECEPTION
	return s


## [Vorgabe] Stern des Systems (Helion, Vorrhal bzw. Ixmora): Schnelltanken (GameState._update_star), Hitze steigt.
static func create_star() -> SpaceCombat:
	var s := SpaceCombat.new()
	s.mode = Mode.STAR
	return s


func in_enemy_system() -> bool:
	return GameState.player_system != 0


## Ortsname im Feindsystem: "FEINDSYSTEM VORRHAL" bzw. "FEINDSYSTEM IXMORA".
func _enemy_place() -> String:
	return "FEINDSYSTEM %s" % GameState.star_name().to_upper()


func _ready() -> void:
	super._ready()
	camera.rotation = Vector3(pitch, yaw, 0)
	GameState.squadron_destroyed.connect(_on_squadron_destroyed)
	GameState.squadron_at_station.connect(_on_squadron_at_station)
	match mode:
		Mode.ORBIT:
			var home := GameState.home_planet()
			location_name = "ORBIT · " + home.name.to_upper()
			orbit_total = Config.orbit_fighter_count
			if orbit_done:
				phase = Phase.DONE
				location_sub = "Heimatplanet"
				hint_text = "LEERTASTE: Systemkarte"
			else:
				location_sub = "Angriff auf den Heimatplaneten!"
				hint_text = "STEUERN: Pfeile / WASD  ·  FEUER: Strg / Enter  ·  Karte erst nach dem Kampf"
				phase = Phase.FIGHTERS
				wave_timer = 2.4
				hud.show_message("ALARM!", "Feindliche Fighter im Orbit von %s – Bordlaser bereit" % home.name, 3.2, UITheme.RED)
				Audio.alarm(-6.0)
		Mode.SQUADRON:
			location_name = squadron.name.to_upper()
			location_sub = "Kurs auf " + GameState.squadron_target_name(squadron)
			if squadron.system != 0:
				location_sub = "Feindsystem · %s" % ("wartet am Sprungpunkt" if squadron.state == SquadronData.State.WAITING else "Kurs auf den Sprungpunkt nach " + GameState.STAR_NAME)
			_start_squadron_fight(true)
		Mode.STATION:
			location_name = station.name.to_upper()
			location_sub = "Reparatur & Energie"
			var att := GameState.squadron_by_id(station.attacker)
			if att and att.fighters > 0:
				squadron = att
				_start_station_defense()
			else:
				_start_docking()
		Mode.EMPTY:
			location_name = "TIEFRAUM" if not in_enemy_system() else _enemy_place()
			location_sub = "Keine Feindkontakte"
			if arrival_note != "":
				hud.show_message("ZIEL VERFEHLT", arrival_note, 3.0, UITheme.AMBER)
			if arrival_home:
				location_sub = "Sprungpunkt · zurück im %s-System" % GameState.STAR_NAME
				hud.show_message("%s-SYSTEM" % GameState.STAR_NAME.to_upper(), "Rücksprung abgeschlossen · Bomben gibt es beim Andocken an Stationen", 3.5, UITheme.CYAN)
			hint_text = "LEERTASTE: Systemkarte"
			phase = Phase.DONE
		Mode.STAR:
			var sn := GameState.star_name().to_upper()
			location_name = "STERN " + sn
			location_sub = "Schnelltanken · Hitze steigt!"
			hint_text = "Energie lädt  ·  LEERTASTE: Karte – rechtzeitig wegspringen!"
			phase = Phase.DONE
			hud.show_message("STERN " + sn, "Energie lädt fast sofort · keine Reparatur, keine Bomben · nach ~%d s verglüht das Schiff" % int(Config.star_heat_time), 3.6, UITheme.AMBER)
			Audio.sfx("refuel_complete", -6.0, 0.7)
		Mode.RECEPTION:
			location_name = _enemy_place()
			# [Vorgabe 0.14.0] Empfangskomitee nur in Vorrhal
			orbit_total = GameState.reception_size() if GameState.player_system == 1 else 0
			if orbit_total <= 0:
				_reception_done(false)
				if GameState.player_system == 2:
					location_sub = "Sprungpunkt · kein Empfangskomitee"
					hud.show_message(_enemy_place(), "Kein Empfangskomitee – der Sprungpunkt ist frei · LEERTASTE: Feindkarte", 3.2, UITheme.CYAN)
				else:
					location_sub = "Sprungpunkt · kein Empfangskomitee mehr"
					hud.show_message(_enemy_place(), "Der Sprungpunkt ist frei · LEERTASTE: Feindkarte", 3.0, UITheme.CYAN)
			else:
				location_sub = "Sprungpunkt · EMPFANGSKOMITEE!"
				hint_text = "Erst die Fighter abwehren  ·  LEERTASTE: Karte (nur Rücksprung)"
				phase = Phase.FIGHTERS
				wave_timer = 2.2
				var sub := "%d Fighter – sie schießen deutlich aggressiver" % orbit_total
				if Config.reception_once and orbit_total < Config.reception_fighter_count:
					sub = "Noch %d Fighter des Empfangskomitees – sie schießen deutlich aggressiver" % orbit_total
				if not Config.combat_intel:   # [0.14.4] ab Normal ohne Anzahl (steht auf der Karte)
					sub = "Die Fighter schießen deutlich aggressiver"
				hud.show_message("EMPFANGSKOMITEE!", sub, 3.2, UITheme.RED)
				Audio.alarm(-6.0)


func music_track() -> String:
	var calm := "enemy_system_theme" if in_enemy_system() else "map_theme"
	match mode:
		Mode.STATION:
			return "combat_space" if phase == Phase.FIGHTERS else "docking_theme"
		Mode.EMPTY:
			return calm
		Mode.ORBIT:
			return "combat_space" if not orbit_done else "map_theme"
		Mode.RECEPTION:
			return "combat_space" if phase == Phase.FIGHTERS else calm
		Mode.STAR:
			return "combat_space"   # Anspannung: die Hitze steigt
	# Schwadron: Kampfmusik nur, solange gekämpft wird (bzw. ein Flaggschiff noch da ist)
	if phase != Phase.DONE or _flagship_alive():
		return "combat_space"
	return calm


func _flagship_alive() -> bool:
	return flagship != null and is_instance_valid(flagship) and flagship.alive


func map_allowed() -> bool:
	if dying:
		return false
	if mode == Mode.ORBIT and not orbit_done:
		return false   # [ORIGINAL] Karte erst nach dem Orbit-Kampf
	return true


func on_map_denied() -> void:
	Audio.ui("ui_error")
	if mode == Mode.ORBIT and not orbit_done and not dying:
		hud.show_message("KARTE GESPERRT", "Erst die Angreifer im Orbit vernichten!", 1.8, UITheme.AMBER)


# =============================================================================================
#  Welt
# =============================================================================================
func _build_world() -> void:
	var my_pos := GameState.player_map_pos
	var enemy_sys := in_enemy_system()
	if mode == Mode.SQUADRON and squadron:
		my_pos = squadron.map_pos
	elif mode == Mode.STATION and station:
		my_pos = station.map_pos()
	elif mode == Mode.ORBIT:
		my_pos = GameState.home_planet().map_pos()
	elif mode == Mode.RECEPTION:
		my_pos = GameState.system_gate(GameState.player_system)
	if mode == Mode.STAR:
		_build_star_world(GameState.player_system)
		return
	# Richtung zur Sonne aus der Kartenposition (Karte x → Welt x, Karte y → Welt z)
	_sun_dir = Vector3(-my_pos.x, 0.0, -my_pos.y)
	if _sun_dir.length() < 1.0:
		_sun_dir = Vector3(0.4, 0.0, -1.0)
	_sun_dir = (_sun_dir.normalized() + Vector3(0, 0.22, 0)).normalized()
	if mode == Mode.ORBIT:
		_sun_dir = Vector3(0.95, 0.14, -0.3).normalized()   # seitliches Licht: Tag/Nacht-Grenze mit Stadtlichtern
	var sky := ShaderMaterial.new()
	sky.shader = load("res://shaders/space_sky.gdshader")
	var variant_b := mode == Mode.SQUADRON and squadron != null and squadron.id % 2 == 0
	var pano := Assets.tex("sky/space_panorama_b.png" if variant_b else "sky/space_panorama.png")
	if enemy_sys:
		# Feindsystem: eigener roter/violetter Himmel – im zweiten Feindsystem blau-violett (sonst eingefärbte Variante)
		var second := GameState.player_system == 2
		pano = Assets.tex("sky/space_panorama_enemy2.png" if second else "sky/space_panorama_enemy.png")
		if pano == null:
			pano = Assets.tex("sky/space_panorama_b.png")
			sky.set_shader_parameter("tint", Vector3(0.75, 0.85, 1.3) if second else Vector3(1.3, 0.6, 0.8))
	if pano == null:
		pano = Assets.tex("sky/space_panorama.png")
	if pano:
		sky.set_shader_parameter("panorama", pano)
		sky.set_shader_parameter("use_panorama", true)
	var dist_star := maxf(my_pos.length(), 60.0)
	var ang := clampf(30.0 / dist_star, 0.04, 0.3)   # scheinbarer Sonnenradius (Grad)
	sky.set_shader_parameter("sun_size", cos(deg_to_rad(ang)))
	sky.set_shader_parameter("sun_intensity", clampf(260.0 / dist_star, 0.5, 2.5))
	if enemy_sys and GameState.player_system == 2:
		make_environment(sky, Color(0.2, 0.24, 0.38), 0.55)
		make_sun(_sun_dir, Color(0.74, 0.82, 1.0), clampf(1.0 + 120.0 / dist_star, 1.2, 2.4))   # blauer Stern Ixmora
	elif enemy_sys:
		make_environment(sky, Color(0.34, 0.2, 0.26), 0.55)
		make_sun(_sun_dir, Color(1.0, 0.62, 0.48), clampf(1.0 + 120.0 / dist_star, 1.2, 2.4))   # roter Stern Vorrhal
	else:
		make_environment(sky, Color(0.22, 0.27, 0.38), 0.55)
		make_sun(_sun_dir, Color(1.0, 0.94, 0.85), clampf(1.0 + 120.0 / dist_star, 1.2, 2.4))
	_build_dust()
	match mode:
		Mode.ORBIT:
			_build_planet(GameState.home_planet(), 1400.0, Vector3(0, -1650, -900))
		Mode.STATION:
			_build_station()
			_build_distant_planet(my_pos)
		_:
			_build_distant_planet(my_pos)


## [Vorgabe] Stern zum Schnelltanken: riesige, ruhig wallende Sonne direkt voraus, Korona, Staub.
## sys: 0 = Helion (gelb-weiß), 1 = Vorrhal (rot-orange), 2 = Ixmora (blau-weiß)
func _build_star_world(sys: int) -> void:
	var enemy_sys := sys != 0
	_sun_dir = Vector3(0.0, 0.07, -1.0).normalized()
	var sky := ShaderMaterial.new()
	sky.shader = load("res://shaders/space_sky.gdshader")
	var pano := Assets.tex(["sky/space_panorama.png", "sky/space_panorama_enemy.png", "sky/space_panorama_enemy2.png"][clampi(sys, 0, 2)])
	if pano == null:
		pano = Assets.tex("sky/space_panorama.png")
	if pano:
		sky.set_shader_parameter("panorama", pano)
		sky.set_shader_parameter("use_panorama", true)
		sky.set_shader_parameter("pano_energy", 0.55)   # der Stern überstrahlt den Himmel
	sky.set_shader_parameter("sun_size", 1.0)   # Scheibe im Himmel aus: die Kugel unten ist der Stern
	sky.set_shader_parameter("sun_intensity", 0.6)
	var core := Color(1.0, 0.5, 0.26) if enemy_sys else Color(1.0, 0.92, 0.7)
	var limb := Color(0.75, 0.12, 0.04) if enemy_sys else Color(1.0, 0.46, 0.1)
	if sys == 2:
		core = Color(0.32, 0.46, 1.0)   # blauer Stern Ixmora (kräftig gesättigt: sonst überstrahlt er weiß)
		limb = Color(0.1, 0.14, 0.72)
	make_environment(sky, Color(0.26, 0.3, 0.45) if sys == 2 else Color(0.45, 0.3, 0.2), 0.7)
	make_sun(_sun_dir, core, 2.6)
	var star := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 560.0
	sm.height = 1120.0
	sm.radial_segments = 96
	sm.rings = 48
	star.mesh = sm
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/star_surface.gdshader")
	mat.set_shader_parameter("core_color", Vector3(core.r, core.g, core.b))
	mat.set_shader_parameter("limb_color", Vector3(limb.r, limb.g, limb.b))
	mat.set_shader_parameter("energy", [2.0, 1.45, 1.35][clampi(sys, 0, 2)])   # Vorrhal/Ixmora sichtbar farbig statt weiß überstrahlt
	star.material_override = mat
	star.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(star)
	star.position = _sun_dir * 1600.0
	var corona := Assets.glow_sprite(core.lerp(limb, 0.4), 2300.0, 1.4)
	add_child(corona)
	corona.position = _sun_dir * 1700.0
	_build_dust()


func _build_dust() -> void:
	var p := GPUParticles3D.new()
	p.amount = 260
	p.lifetime = 4.0
	p.preprocess = 4.0
	p.local_coords = true
	p.visibility_aabb = AABB(Vector3(-120, -80, -260), Vector3(240, 160, 300))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(90, 60, 110)
	pm.direction = Vector3(0, 0, 1)
	pm.spread = 2.0
	pm.initial_velocity_min = 30.0
	pm.initial_velocity_max = 50.0
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.08
	pm.scale_max = 0.22
	var g := Gradient.new()
	g.set_color(0, Color(0.6, 0.8, 1.0, 0.0))
	g.add_point(0.2, Color(0.6, 0.8, 1.0, 0.5))
	g.set_color(1, Color(0.6, 0.8, 1.0, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_texture = Assets.tex("fx/glow.png") if Assets.tex("fx/glow.png") else FallbackModels.radial_texture()
	m.albedo_color = Color(2, 2, 2)
	var q := QuadMesh.new()
	q.material = m
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	camera.add_child(p)
	p.position = Vector3(0, 0, -150)


func _planet_material(p: PlanetData) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/planet.gdshader")
	var t := Assets.tex("planets/%s.png" % p.type)
	if t:
		m.set_shader_parameter("albedo_tex", t)
	else:
		m.set_shader_parameter("use_fallback", true)
		var pal: Array = PlanetLook.palette(p.type)
		m.set_shader_parameter("fallback_a", pal[0])
		m.set_shader_parameter("fallback_b", pal[1])
	var clouds := Assets.tex("planets/clouds.png")
	var has_clouds: bool = clouds != null and p.type in ["terran", "jungle", "ocean", "ice", "toxic"]
	m.set_shader_parameter("has_clouds", has_clouds)
	if clouds:
		m.set_shader_parameter("clouds_tex", clouds)
	var etex := Assets.tex("planets/%s_emission.png" % p.type) if p.type in ["volcanic", "alien_ash", "alien_home", "alien_void", "alien_magma", "alien_bloom"] else null
	if etex:
		m.set_shader_parameter("emission_tex", etex)
		m.set_shader_parameter("has_emission", true)
	m.set_shader_parameter("atmo_color", PlanetLook.atmosphere(p.type))
	m.set_shader_parameter("sun_dir", _sun_dir)
	m.set_shader_parameter("night_light_strength", 1.6 if p.is_home else 0.0)
	if p.is_enemy:
		# Lichter der Feindstädte: magenta, im zweiten Feindsystem violett
		m.set_shader_parameter("night_lights", Color(0.6, 0.42, 1.0) if p.system == 2 else Color(1.0, 0.25, 0.55))
	m.set_shader_parameter("night_noise", Effects.noise_texture())
	m.set_shader_parameter("spin", float(p.id) * 0.13)
	return m


func _build_planet(p: PlanetData, radius: float, center: Vector3) -> void:
	bg_planet = Node3D.new()
	add_child(bg_planet)
	bg_planet.position = center
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 128
	sm.rings = 64
	mi.mesh = sm
	mi.material_override = _planet_material(p)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bg_planet.add_child(mi)
	var atmo := MeshInstance3D.new()
	var am := SphereMesh.new()
	am.radius = radius * 1.035
	am.height = radius * 2.07
	am.radial_segments = 128
	am.rings = 64
	atmo.mesh = am
	var amat := ShaderMaterial.new()
	amat.shader = load("res://shaders/atmosphere.gdshader")
	amat.set_shader_parameter("atmo_color", PlanetLook.atmosphere(p.type))
	amat.set_shader_parameter("sun_dir", _sun_dir)
	atmo.material_override = amat
	atmo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bg_planet.add_child(atmo)


func _build_distant_planet(my_pos: Vector2) -> void:
	var best: PlanetData = null
	var bd := INF
	for p in GameState.system_planets(GameState.player_system):
		var d: float = p.map_pos().distance_to(my_pos)
		if d < bd and d > 1.0:
			bd = d
			best = p
	if best == null:
		return
	var dir2 := best.map_pos() - my_pos
	var dir := Vector3(dir2.x, -0.18 * dir2.length(), dir2.y).normalized()
	var dist := 6000.0
	var ang := clampf(900.0 / maxf(bd, 20.0), 2.0, 14.0)
	var radius := dist * tan(deg_to_rad(ang))
	_build_planet(best, radius, dir * dist)


func _build_station() -> void:
	station_node = Assets.model("station")
	add_child(station_node)
	station_ring = Assets.find_node_named(station_node, "Ring")
	for i in range(1, 5):
		var b := Assets.find_node_named(station_node, "Beacon_%d" % i)
		if b:
			var g := Assets.glow_sprite(Color(1.0, 0.25, 0.2) if i % 2 == 0 else Color(0.3, 1.0, 0.5), 3.5, 4.0)
			b.add_child(g)
			station_beacons.append(g)
	var dp := Assets.find_node_named(station_node, "DockPort")
	if dp:
		var g2 := Assets.glow_sprite(Color(0.3, 0.9, 1.0), 6.0, 3.0)
		dp.add_child(g2)
	# Ausgangslage: links neben dem Spieler (für das Hereingleiten beim Andocken)
	station_node.position = dir_from_angles(deg_to_rad(68.0), 0.0) * 170.0
	_face_station()


func _face_station() -> void:
	if station_node:
		var to := camera.global_position - station_node.global_position
		if to.length() > 1.0:
			station_node.look_at(station_node.global_position - to, Vector3.UP)
			# Andockport (Front, -Z) zeigt zum Spieler
			station_node.rotate_object_local(Vector3.UP, PI)


# =============================================================================================
#  Steuerung
# =============================================================================================
func _update_controls(delta: float) -> void:
	var inp := steer_input()
	var max_rate := deg_to_rad(Config.space_turn_rate)
	var k := 1.0 - exp(-Config.space_turn_response * delta)
	yaw_rate = lerpf(yaw_rate, -inp.x * max_rate, k)
	pitch_rate = lerpf(pitch_rate, inp.y * max_rate, k)
	yaw += yaw_rate * delta
	var lim := deg_to_rad(Config.space_pitch_limit)
	pitch = clampf(pitch + pitch_rate * delta, -lim, lim)
	if absf(pitch) >= lim - 0.001:
		pitch_rate = 0.0
	camera.rotation = Vector3(pitch, yaw, 0)
	turn_norm = Vector2(yaw_rate, pitch_rate).length() / max_rate


func _process(delta: float) -> void:
	super._process(delta)
	if dying:
		return
	if station_ring:
		station_ring.rotate_object_local(Vector3(0, 0, 1), delta * 0.12)
	for i in station_beacons.size():
		station_beacons[i].visible = fmod(Time.get_ticks_msec() / 1000.0 + i * 0.35, 1.4) < 0.25
	if bg_planet:
		bg_planet.rotate_y(delta * 0.002)
	if mode == Mode.STAR:
		_update_star(delta)
	match phase:
		Phase.FIGHTERS:
			_update_fighter_phase(delta)
		Phase.DESTROYERS:
			_update_destroyer_phase(delta)
		Phase.DOCK_APPROACH, Phase.DOCK_CLAMP, Phase.REFUEL:
			_update_docking(delta)


# =============================================================================================
#  Stern: Schnelltanken (Energie und Hitze rechnet GameState – auch bei offener Karte)
# =============================================================================================
var _star_tick := 0.0
var _star_warned := false
var _star_beep := 0.0


func _update_star(delta: float) -> void:
	if GameState.player_loc != GameState.Loc.STAR:
		return
	var heat := GameState.star_heat
	# leichtes Zittern der Hitze wegen (Regler „Bildschirmwackeln“)
	shake = maxf(shake, 0.12 + heat * 0.35)
	# Tank-Tick wie an der Station, solange Energie fließt
	if GameState.energy < Config.energy_max - 0.01:
		_star_tick -= delta
		if _star_tick <= 0.0:
			_star_tick = 0.25
			Audio.sfx("refuel_tick", -4.0, 1.25)
	if heat >= Config.star_heat_warning:
		if not _star_warned:
			_star_warned = true
			hud.show_message("HITZE KRITISCH!", "Sofort springen – LEERTASTE: Karte", 2.6, UITheme.RED)
		_star_beep -= delta
		if _star_beep <= 0.0:
			_star_beep = lerpf(0.9, 0.35, clampf((heat - Config.star_heat_warning) / maxf(1.0 - Config.star_heat_warning, 0.01), 0.0, 1.0))
			Audio.sfx("warning_low_energy", -3.0, 1.2)


# =============================================================================================
#  Fighter-Wellen
# =============================================================================================
func _fighters_alive() -> int:
	var n := 0
	for e in enemies:
		if is_instance_valid(e) and e.alive and e.kind == Enemy.Kind.FIGHTER:
			n += 1
	return n


func _fighters_to_spawn() -> int:
	if mode == Mode.ORBIT or mode == Mode.RECEPTION:
		return orbit_total - orbit_spawned
	if squadron == null:
		return 0
	return maxi(squadron.fighters - _fighters_alive(), 0)


func _update_fighter_phase(delta: float) -> void:
	if _fighters_alive() > 0:
		return
	if _fighters_to_spawn() <= 0:
		_fighters_cleared()
		return
	if wave_timer < 0.0:
		wave_timer = Config.wave_delay
	wave_timer -= delta
	if wave_timer <= 0.0:
		wave_timer = -1.0
		_spawn_wave()


func _spawn_wave() -> void:
	var n := mini(Config.fighters_per_wave, _fighters_to_spawn())
	wave += 1
	var total_waves := 0
	var counted := mode == Mode.ORBIT or mode == Mode.RECEPTION
	if counted:
		total_waves = ceili(float(orbit_total) / Config.fighters_per_wave)
	var cb := camera.global_transform.basis
	for i in n:
		var f := Fighter.new()
		f.setup(self, squadron if not counted else null)
		if mode == Mode.RECEPTION:
			# [Vorgabe] deutlich aggressiver: doppelte Feuerrate und Doppelschuss
			f.fire_rate_factor = Config.reception_fire_rate_factor
			f.burst_shots = Config.reception_burst_shots
			f.damage = Config.enemy_fighter_damage
		var local := Vector3(randf_range(-55, 55) + (i - 1) * 30.0, randf_range(-12, 28), -randf_range(170, 230))
		add_enemy(f, camera.global_position + cb * local)
		if counted:
			orbit_spawned += 1
	Audio.sfx("wave_incoming", -2.0)
	if not Config.combat_intel:
		# [Vorgabe 0.14.4] ab Normal ohne Wellenzahl gesamt und ohne Anzahl der Fighter
		hud.show_message("WELLE %d" % wave, "FIGHTER IM ANFLUG", 1.8, UITheme.FIGHTER_COLOR)
		return
	var title := "WELLE %d" % wave + (" / %d" % total_waves if total_waves > 0 else "")
	hud.show_message(title, "%d FIGHTER IM ANFLUG" % n, 1.8, UITheme.FIGHTER_COLOR)


func _fighters_cleared() -> void:
	match mode:
		Mode.ORBIT:
			if not orbit_done:
				orbit_done = true
				phase = Phase.DONE
				GameState.add_score(Config.bonus_orbit_cleared, "Orbit gesichert")
				GameState.start_campaign()
				hint_text = "LEERTASTE: Systemkarte öffnen"
				location_sub = "Orbit gesichert"
				hud.show_message("ORBIT GESICHERT", "Drücke LEERTASTE für die Systemkarte", 5.0, UITheme.GREEN)
				Audio.sfx("squadron_destroyed")
				Audio.play_music("map_theme", 3.0)
		Mode.SQUADRON:
			if squadron and not squadron.destroyers.is_empty():
				phase = Phase.DESTROYERS
				destroyer_timer = Config.destroyer_next_delay
				hud.show_message("ZERSTÖRER IM ANFLUG", "Ionen-Kanone bereit – Zerstörer stehen seitlich außerhalb der Sicht", 2.6, UITheme.AMBER)
				if squadron.has_flagship and flagship == null:
					_spawn_flagship()
			else:
				phase = Phase.DONE
		Mode.STATION:
			# Squadron wurde von GameState vernichtet (alle Fighter weg) → Andocken
			phase = Phase.DONE
			_after_station_defense()
		Mode.RECEPTION:
			_reception_done(true)


## Empfangskomitee abgewehrt: Ruhe am Ankunftspunkt bis zum nächsten Sprung ins Feindsystem.
func _reception_done(fought: bool) -> void:
	if phase == Phase.DONE and not GameState.reception_active:
		return
	phase = Phase.DONE
	GameState.reception_active = false
	location_sub = "Sprungpunkt gesichert"
	hint_text = "LEERTASTE: Feindkarte – Planeten anfliegen, Schwadrone abfangen"
	if fought:
		var sub := "Ruhe am Sprungpunkt · LEERTASTE: Feindkarte"
		if Config.reception_once:
			sub = "Der Sprungpunkt bleibt ab jetzt frei · LEERTASTE: Feindkarte"
		hud.show_message("EMPFANGSKOMITEE VERNICHTET" if Config.reception_once else "EMPFANGSKOMITEE ABGEWEHRT", sub, 4.5, UITheme.GREEN)
		Audio.sfx("squadron_destroyed")
	Audio.play_music(music_track(), 3.0)


func _start_squadron_fight(intro: bool) -> void:
	if squadron.fighters > 0:
		phase = Phase.FIGHTERS
		wave_timer = 1.6
		if intro:
			hud.show_message(squadron.name.to_upper(), _composition_text(squadron), 2.6, UITheme.RED)
	elif not squadron.destroyers.is_empty():
		phase = Phase.DESTROYERS
		destroyer_timer = 1.6
		if intro:
			hud.show_message(squadron.name.to_upper(), _composition_text(squadron), 2.6, UITheme.RED)
		if squadron.has_flagship:
			_spawn_flagship()
	else:
		phase = Phase.DONE


func _composition_text(sq: SquadronData) -> String:
	if not Config.combat_intel:
		return "Feindkontakt"   # [Vorgabe 0.14.4] ab Normal: Zusammensetzung nur auf der Übersichtskarte
	var parts := []
	if sq.fighters > 0:
		parts.append("%d Fighter" % sq.fighters)
	if not sq.destroyers.is_empty():
		parts.append("%d Zerstörer" % sq.destroyers.size())
	if sq.has_flagship:
		parts.append("Flaggschiff")
	return " · ".join(parts)


# =============================================================================================
#  Zerstörer nacheinander + Flaggschiff
# =============================================================================================
func _current_destroyer() -> Destroyer:
	for e in enemies:
		if is_instance_valid(e) and e.alive and e.kind == Enemy.Kind.DESTROYER:
			return e
	return null


func _update_destroyer_phase(delta: float) -> void:
	if squadron == null or squadron.state == SquadronData.State.DESTROYED:
		return
	if _current_destroyer() != null:
		return
	if squadron.destroyers.is_empty():
		return
	destroyer_timer -= delta
	if destroyer_timer <= 0.0:
		destroyer_timer = Config.destroyer_next_delay
		_spawn_destroyer(squadron.destroyers[0])


## [ORIGINAL] Zerstörer erscheinen knapp außerhalb des Sichtfelds links oder rechts.
func _spawn_destroyer(dd: DestroyerData) -> void:
	var d := Destroyer.new()
	d.data = dd
	d.setup(self, squadron)
	var side := -1.0 if randf() < 0.5 else 1.0
	if flagship and is_instance_valid(flagship):
		# auf die andere Seite als das Flaggschiff
		var fy := wrapf(flagship.anchor_yaw - yaw, -PI, PI)
		side = -signf(fy) if fy != 0.0 else side
	var half_h := _half_hfov()
	var ang_r := atan2(14.0, Config.destroyer_distance)
	d.anchor_yaw = yaw + side * (half_h + deg_to_rad(Config.destroyer_offscreen_margin) + ang_r)
	d.anchor_pitch = clampf(pitch * 0.5 + deg_to_rad(randf_range(-6, 6)), deg_to_rad(-25), deg_to_rad(25))
	d.dist = Config.destroyer_distance
	add_enemy(d, camera.global_position + dir_from_angles(d.anchor_yaw, d.anchor_pitch) * d.dist)
	# [Vorgabe] nur "ZERSTÖRER" – Farbe (und damit die nötigen Treffer) erkennt man an der Schildfarbe
	hud.show_message("ZERSTÖRER", "<< LINKS" if side > 0.0 else "RECHTS >>", 2.2, UITheme.AMBER)


func _spawn_flagship() -> void:
	flagship = Flagship.new()
	flagship.setup(self, squadron)
	var side := -1.0 if randf() < 0.5 else 1.0
	flagship.anchor_yaw = yaw + side * (_half_hfov() + deg_to_rad(Config.destroyer_offscreen_margin + 16.0))
	flagship.anchor_pitch = deg_to_rad(randf_range(2, 9))
	flagship.dist = Config.flagship_distance
	add_enemy(flagship, camera.global_position + dir_from_angles(flagship.anchor_yaw, flagship.anchor_pitch) * flagship.dist)
	if Config.combat_intel:
		hud.show_message("FLAGGSCHIFF!", "Nur das rosa Quadrat – und nur kurz vor seinem Schuss", 3.0, UITheme.PINK)
	else:
		# [Vorgabe 0.14.4] ab Normal nur die Ankunft mit Richtung (wie beim Zerstörer), kein Hinweis zum Zeitpunkt
		hud.show_message("FLAGGSCHIFF!", "<< LINKS" if side > 0.0 else "RECHTS >>", 2.6, UITheme.PINK)


func _half_hfov() -> float:
	var vp := get_viewport().get_visible_rect().size
	var aspect := vp.x / maxf(vp.y, 1.0)
	return atan(tan(deg_to_rad(camera.fov) * 0.5) * aspect)


func _on_enemy_removed(e: Enemy) -> void:
	if e.kind == Enemy.Kind.FIGHTER:
		if mode == Mode.ORBIT or mode == Mode.RECEPTION:
			orbit_killed += 1
			GameState.on_fighter_killed(null)
			if mode == Mode.RECEPTION:
				GameState.on_reception_fighter_killed()
		else:
			GameState.on_fighter_killed(squadron)
	elif e.kind == Enemy.Kind.FLAGSHIP:
		GameState.on_flagship_killed(squadron if squadron and squadron.state != SquadronData.State.DESTROYED else null)
		flagship = null
		hud.show_message("FLAGGSCHIFF VERNICHTET!", "+%d Punkte" % Config.flagship_points, 3.0, UITheme.PINK)
		if phase == Phase.DONE:
			Audio.play_music(music_track(), 3.0)
	elif e.kind == Enemy.Kind.DESTROYER:
		if not Config.combat_intel:
			# [Vorgabe 0.14.4] ab Normal: nicht verraten, ob noch ein Zerstörer folgt. War es der letzte, steht schon
			# „SCHWADRON VERNICHTET“ (wird synchron vorher gemeldet) – das nicht überschreiben.
			if squadron and squadron.state != SquadronData.State.DESTROYED:
				hud.show_message("ZERSTÖRER VERNICHTET", "", 1.8, UITheme.GREEN)
		elif squadron and not squadron.destroyers.is_empty():
			hud.show_message("ZERSTÖRER VERNICHTET", "Nächster Zerstörer im Anflug …", 1.8, UITheme.GREEN)


func _on_squadron_destroyed(sq: SquadronData) -> void:
	if sq != squadron or _done_handled:
		return
	_done_handled = true
	if mode == Mode.STATION:
		return   # wird in _after_station_defense behandelt
	phase = Phase.DONE
	hint_text = "LEERTASTE: Systemkarte"
	location_name = "TIEFRAUM" if not in_enemy_system() else _enemy_place()
	location_sub = "Schwadron vernichtet"
	hud.show_message("SCHWADRON VERNICHTET", "+%d Bonus" % Config.bonus_squadron_destroyed, 3.5, UITheme.GREEN)
	Audio.sfx("squadron_destroyed")
	if _flagship_alive():
		flagship.start_retreat_timer()
		if Config.combat_intel:
			hud.show_message("SCHWADRON VERNICHTET", "Das Flaggschiff zieht sich gleich zurück – letzte Chance!", 3.5, UITheme.GREEN)
	else:
		Audio.play_music(music_track(), 3.0)


# =============================================================================================
#  Station: Verteidigung, Andocken, Tanken
# =============================================================================================
func _start_station_defense() -> void:
	phase = Phase.FIGHTERS
	wave_timer = 1.8
	_station_was_occupied = station != null and station.occupied
	if _station_was_occupied:
		# [Vorgabe 0.14.2] besetzte Station: die Fighter halten sie, bis sie vernichtet sind
		location_sub = "BESETZT!"
		if Config.combat_intel:
			hud.show_message("STATION BESETZT!", ("%d Fighter hält %s – vernichten, um sie zu befreien" if squadron.fighters == 1 else "%d Fighter halten %s – vernichten, um sie zu befreien") % [squadron.fighters, station.name], 3.0, UITheme.RED)
		else:
			hud.show_message("STATION BESETZT!", "Fighter halten %s – vernichten, um sie zu befreien" % station.name, 3.0, UITheme.RED)
	else:
		location_sub = "WIRD ANGEGRIFFEN!"
		if Config.combat_intel:
			hud.show_message("STATION WIRD ANGEGRIFFEN!", "%d Fighter – nur Fighter greifen Stationen an" % squadron.fighters, 2.8, UITheme.RED)
		else:
			hud.show_message("STATION WIRD ANGEGRIFFEN!", "Nur Fighter greifen Stationen an", 2.8, UITheme.RED)
	if not frozen:
		Audio.play_music("combat_space")   # bei offener Karte übernimmt close_map() die Musik
	controls_enabled = true
	fire_enabled = true


func _on_squadron_at_station(sq: SquadronData, st: StationData) -> void:
	if mode != Mode.STATION or st != station:
		return
	squadron = sq
	_done_handled = false
	if phase in [Phase.DOCK_APPROACH, Phase.DOCK_CLAMP, Phase.REFUEL, Phase.DOCKED, Phase.DONE, Phase.IDLE]:
		Audio.alarm(-3.0)
		_start_station_defense()


func _after_station_defense() -> void:
	hud.show_message("STATION BEFREIT" if _station_was_occupied else "STATION VERTEIDIGT", "+%d Bonus · Andocken beginnt" % Config.bonus_station_defended, 3.0, UITheme.GREEN)
	_station_was_occupied = false
	# Ortszeile zurück auf den Normalzustand (bis 0.14.1 blieb „WIRD ANGEGRIFFEN!“ bis zum Tankende stehen)
	location_sub = "Reparatur & Energie"
	Audio.sfx("squadron_destroyed")
	var tw := create_tween()
	tw.tween_interval(2.6)
	tw.tween_callback(_start_docking)


func _start_docking() -> void:
	if station == null or station.destroyed:
		phase = Phase.DONE
		return
	phase = Phase.DOCK_APPROACH
	dock_t = 0.0
	controls_enabled = false
	fire_enabled = false
	_cam_center_from = Vector2(yaw, pitch)
	# [ORIGINAL] Station fährt von links ins Bild bis zur Bildschirmmitte
	var base_yaw := yaw
	dock_from = camera.global_position + dir_from_angles(base_yaw + deg_to_rad(64.0), 0.0) * 175.0
	station_node.global_position = dock_from
	hint_text = "LEERTASTE: Systemkarte (Abflug)"
	Audio.sfx("dock_slide", 0.0)
	Audio.play_music("docking_theme", 2.0)
	hud.show_message("ANDOCKEN", "Andockvorgang an %s eingeleitet" % station.name, 2.2, UITheme.CYAN)


func _update_docking(delta: float) -> void:
	dock_t += delta
	match phase:
		Phase.DOCK_APPROACH:
			# Kamera richtet sich gerade aus (kein Nicken), Station gleitet zur Bildmitte
			var k := clampf(dock_t / Config.dock_slide_time, 0.0, 1.0)
			var e := 1.0 - pow(1.0 - k, 3.0)
			pitch = lerpf(_cam_center_from.y, 0.0, clampf(dock_t / 1.0, 0.0, 1.0))
			camera.rotation = Vector3(pitch, yaw, 0)
			var target := camera.global_position + dir_from_angles(yaw, 0.0) * 118.0 + Vector3(0, -4.0, 0)
			station_node.global_position = dock_from.lerp(target, e)
			_face_station()
			if k >= 1.0:
				phase = Phase.DOCK_CLAMP
				dock_t = 0.0
				Audio.sfx("dock_clamp", 0.0)
				shake = 0.5
		Phase.DOCK_CLAMP:
			if dock_t > 0.9:
				phase = Phase.REFUEL
				refuel_t = 0.0
				bomb_t = 0.0
				# [Vorgabe 0.12.0] Systemschäden werden nur an Stationen repariert – sofort beim Andocken
				_repaired = GameState.repair()
				if _repaired != "":
					Audio.sfx("repair_done" if Audio.has_sound("repair_done") else "refuel_complete", -2.0)
				if _refuel_complete():
					_refuel_done()
				else:
					var what := "Energie wird aufgefüllt"
					if GameState.bombs < Config.bombs_max:
						what = "Energie und Bomben werden aufgefüllt" if GameState.energy < Config.energy_max - 0.01 else "Bomben werden geladen"
					if _repaired != "":
						hud.show_message("REPARATUR · TANKEN", "%s repariert · %s" % [GameState.damage_name(_repaired).capitalize(), what], 2.4, UITheme.GREEN)
					else:
						hud.show_message("TANKEN", what, 1.5, UITheme.CYAN)
		Phase.REFUEL:
			# [ORIGINAL] ca. 10 % pro Sekunde, sichtbar in 5-%-Schritten
			refuel_t += delta
			var step_time := Config.refuel_step / Config.refuel_rate
			while refuel_t >= step_time and phase == Phase.REFUEL and GameState.energy < Config.energy_max - 0.01:
				refuel_t -= step_time
				var before := GameState.energy
				var target_e := minf(Config.energy_max, floorf(GameState.energy / Config.refuel_step + 0.001) * Config.refuel_step + Config.refuel_step)
				GameState.change_energy(target_e - before)
				GameState.stats.energy_refueled += target_e - before
				Audio.sfx("refuel_tick", 0.0, 0.9 + GameState.energy / Config.energy_max * 0.4)
			# [Vorgabe] Bomben werden – wie Energie – nur an eigenen Stationen aufgefüllt
			bomb_t += delta
			while bomb_t >= Config.bomb_refill_time and GameState.bombs < Config.bombs_max:
				bomb_t -= Config.bomb_refill_time
				GameState.refill_bomb()
				Audio.sfx("refuel_tick", -3.0, 1.35)
			if _refuel_complete():
				_refuel_done()


func _refuel_complete() -> bool:
	return GameState.energy >= Config.energy_max - 0.01 and (GameState.bombs >= Config.bombs_max or not Config.enemy_system_enabled)


func _refuel_done() -> void:
	phase = Phase.DOCKED
	Audio.sfx("refuel_complete", 0.0)
	var sub := "Reparatur abgeschlossen · LEERTASTE: Systemkarte"
	if Config.enemy_system_enabled:
		sub = "%d Bomben an Bord · LEERTASTE: Systemkarte" % GameState.bombs
	if _repaired != "":
		sub = "%s repariert · %s" % [GameState.damage_name(_repaired).capitalize(), sub]
	hud.show_message("ENERGIE 100 %", sub, 4.0, UITheme.GREEN)
	location_sub = "Angedockt"


func is_docking() -> bool:
	return phase in [Phase.DOCK_APPROACH, Phase.DOCK_CLAMP, Phase.REFUEL, Phase.DOCKED]


# =============================================================================================
#  Tests
# =============================================================================================
func debug_finish_orbit() -> void:
	if mode == Mode.RECEPTION and phase == Phase.FIGHTERS:
		GameState.reception_left = 0   # übersprungen = erledigt ("bleibt ab jetzt frei")
		for e in enemies.duplicate():
			if is_instance_valid(e):
				e.queue_free()
		enemies.clear()
		orbit_spawned = orbit_total
		_fighters_cleared()
		return
	if mode != Mode.ORBIT or orbit_done:
		return
	for e in enemies.duplicate():
		if is_instance_valid(e):
			e.queue_free()
	enemies.clear()
	orbit_spawned = orbit_total
	_fighters_cleared()


func on_flagship_retreated(f: Flagship) -> void:
	super.on_flagship_retreated(f)
	if flagship == f:
		flagship = null
	if phase == Phase.DONE:
		Audio.play_music(music_track(), 3.0)


func debug_look_at(what: String) -> void:
	for e in enemies:
		if not is_instance_valid(e) or not e.alive:
			continue
		var ok: bool = (what == "destroyer" and e.kind == Enemy.Kind.DESTROYER) or (what == "flagship" and e.kind == Enemy.Kind.FLAGSHIP) or (what == "fighter" and e.kind == Enemy.Kind.FIGHTER)
		if ok:
			var d: Vector3 = (e.global_position - camera.global_position).normalized()
			yaw = atan2(-d.x, -d.z)
			pitch = asin(clampf(d.y, -1.0, 1.0))
			camera.rotation = Vector3(pitch, yaw, 0)
			return
	if what == "station" and station_node:
		var d2 := (station_node.global_position - camera.global_position).normalized()
		yaw = atan2(-d2.x, -d2.z)
		pitch = asin(clampf(d2.y, -1.0, 1.0))
		camera.rotation = Vector3(pitch, yaw, 0)


func debug_kill_all() -> void:
	for e in enemies.duplicate():
		if is_instance_valid(e) and e.alive:
			if e.kind == Enemy.Kind.FIGHTER:
				e.on_laser_hit({})
			elif e.kind == Enemy.Kind.DESTROYER:
				while e.alive:
					e.on_ion_hit({"point": e.global_position})
			elif e.kind == Enemy.Kind.FLAGSHIP:
				e._destroy()
