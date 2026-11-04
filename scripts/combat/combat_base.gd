class_name CombatBase
extends Node3D
## =============================================================================================
##  Gemeinsame Basis für Weltraum- und Planetenkampf: Cockpitkamera, Waffen, Zielerfassung,
##  Treffer am Spieler, HUD, Nachbearbeitung, Einfrieren beim Öffnen der Karte.
## =============================================================================================

enum Weapon { LASER, ION, BOMB }

var camera: Camera3D
var world_env: WorldEnvironment
var env: Environment
var sun: DirectionalLight3D
var fx_root: Node3D
var shots: ShotSystem
var hud_layer: CanvasLayer
var hud: HudBase
var enemies: Array = []
var frozen := false
var dying := false
var weapon := Weapon.LASER
var weapon_manual := Weapon.LASER
var laser_cd := 0.0
var ion_cd := 0.0
var bomb_cd := 0.0
var aim_target: Enemy = null
var locked := false
var turn_norm := 0.0              ## 0..1 aktuelle Lenkintensität (Ausweichen)
var location_name := ""
var location_sub := ""
var hint_text := "LEERTASTE: Karte  ·  STRG / ENTER: Feuer"
var fire_enabled := true
var controls_enabled := true
var shake := 0.0
var flash := 0.0
var flash_color := Color(1.0, 0.2, 0.1)
var aberr := 0.0
var noise_lines := 0.0
var _warn_stage := -1        ## 0 = normal, 1 = unter energy_low_warning, 2 = unter energy_critical_warning
var _warn_beeps_left := 0
var _warn_timer := 0.0
var _warn_reminder := 0.0
var _lock_beep_t := 0.0
var _lock_beeped: Enemy = null
var _death_cb: Callable
var _death_t := 0.0
var _death_reason := "energy"   ## "energy" = eigenes Schiff zerstört, "cities" = Helion gefallen (Schiff intakt)
var _last_lock_target: Enemy = null
var _incoming_warn_t := 0.0
var victory_mode := false
var _victory_cb: Callable
var _victory_t := 0.0
var _unfreeze_frame := -1     ## Bild, in dem die Karte geschlossen wurde (Feuer dieses Bildes gilt der Karte)


static func dir_from_angles(yaw: float, pitch: float) -> Vector3:
	return Basis.from_euler(Vector3(pitch, yaw, 0.0)) * Vector3(0, 0, -1)


func _ready() -> void:
	fx_root = Node3D.new()
	fx_root.name = "FX"
	add_child(fx_root)
	camera = Camera3D.new()
	camera.fov = Config.camera_fov
	camera.near = 0.25
	camera.far = 20000.0
	add_child(camera)
	camera.current = true
	_build_world()
	shots = ShotSystem.new(self)
	add_child(shots)
	hud_layer = CanvasLayer.new()
	hud_layer.layer = 5
	add_child(hud_layer)
	_make_hud()
	Settings.changed.connect(_on_settings_changed)
	GameState.energy_changed.connect(_on_energy_changed)
	Audio.loop_start("engine", "engine_loop", 0.0, 1.0)
	# erst nach dem _ready() der Unterklasse wählen (Modus/Phase sind dann gesetzt)
	_apply_music.call_deferred()


## HUD gemäß Optionen: Cockpit mit Head-Up-Display oder klassische flache Anzeige.
func _make_hud() -> void:
	hud = CockpitHUD.new() if Settings.cockpit_view else ClassicHUD.new()
	hud.combat = self
	hud_layer.add_child(hud)


func _on_settings_changed() -> void:
	if hud == null or (hud is CockpitHUD) == Settings.cockpit_view:
		return
	# Ansicht in den Optionen umgeschaltet: HUD neu aufbauen (Meldungen gehen dabei verloren)
	hud.queue_free()
	_make_hud()


## Von Unterklassen überschrieben: Umgebung, Licht, Hintergrund.
func _build_world() -> void:
	pass


func music_track() -> String:
	return "combat_space"


func _apply_music() -> void:
	if is_inside_tree() and not frozen and not dying:
		Audio.play_music(music_track())


func map_allowed() -> bool:
	return not dying


func on_map_denied() -> void:
	Audio.ui("ui_error")


func set_frozen(f: bool) -> void:
	frozen = f
	process_mode = Node.PROCESS_MODE_DISABLED if f else Node.PROCESS_MODE_INHERIT
	visible = not f
	hud_layer.visible = not f
	camera.current = not f
	if f:
		Audio.stop_all_loops(0.15)
	else:
		_unfreeze_frame = Engine.get_process_frames()
		Audio.loop_start("engine", "engine_loop", 0.0, 0.5)
		_on_unfrozen()


## Feuer-Tastendruck dieses Bildes – außer er hat gerade die Karte geschlossen (sonst fiele eine Bombe).
func _fire_just_pressed() -> bool:
	return Input.is_action_just_pressed("fire") and Engine.get_process_frames() != _unfreeze_frame


func _on_unfrozen() -> void:
	pass


# ---------------------------------------------------------------------------------------------
#  Hauptschleife
# ---------------------------------------------------------------------------------------------
func _process(delta: float) -> void:
	if dying:
		_update_death(delta)
		_update_post(delta)
		return
	if victory_mode:
		_update_victory(delta)
	if controls_enabled:
		_update_controls(delta)
	_update_targeting()
	_update_weapons(delta)
	_update_post(delta)
	_update_low_energy(delta)
	_update_incoming(delta)


func _update_controls(_delta: float) -> void:
	pass


func steer_input() -> Vector2:
	var x := Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")
	var y := Input.get_action_strength("steer_up") - Input.get_action_strength("steer_down")
	if Settings.invert_y:
		y = -y
	return Vector2(x, y)


func is_evading() -> bool:
	return turn_norm >= Config.evasion_turn_fraction


# ---------------------------------------------------------------------------------------------
#  Zielerfassung und Waffen
# ---------------------------------------------------------------------------------------------
func _update_targeting() -> void:
	var best: Enemy = null
	var best_err := 7.0
	for e in enemies:
		if not is_instance_valid(e) or not e.alive:
			continue
		var to: Vector3 = e.global_position - camera.global_position
		if to.dot(-camera.global_transform.basis.z) <= 0.0:
			continue
		var err: float = e.aim_error_deg()
		if e.kind == Enemy.Kind.FLAGSHIP:
			# beim Flaggschiff zählt das Quadrat
			var wp: Vector3 = e.weak_point_pos()
			var ang := rad_to_deg((-camera.global_transform.basis.z).angle_to(wp - camera.global_position))
			# Erfassung = Trefferradius des Quadrats (Flagship.segment_hit), damit ein Lock auch treffen kann
			err = maxf(ang - rad_to_deg(atan2(Config.flagship_weakpoint_radius + Config.ion_hit_tolerance * 0.5, wp.distance_to(camera.global_position))), 0.0)
		if err < best_err:
			best_err = err
			best = e
	aim_target = best
	locked = best != null and best_err <= 0.01
	if locked and best != _last_lock_target:
		# Piep nur bei neuem Ziel oder nach einer Pause – kein Dauerklicken beim Flackern der Erfassung
		if best != _lock_beeped or _lock_beep_t <= 0.0:
			Audio.sfx("target_lock", -2.0, 1.0 + (0.3 if best.kind != Enemy.Kind.FIGHTER else 0.0))
			_lock_beeped = best
			_lock_beep_t = 1.5
	_last_lock_target = best if locked else null


func has_enemy_kind(k: int) -> bool:
	for e in enemies:
		if is_instance_valid(e) and e.alive and e.kind == k:
			return true
	return false


## Bomben verfügbar? Nur über Feindplaneten (PlanetCombat im Feindsystem).
func bombs_allowed() -> bool:
	return false


## Bombe abwerfen (PlanetCombat).
func drop_bomb() -> void:
	pass


## [FREI, Vorschlag automatisch] Waffe passend zum anvisierten Gegnertyp.
func _select_weapon() -> void:
	if bombs_allowed():
		# [Vorgabe] über Feindplaneten wird manuell zwischen Bordlaser und Bomben gewechselt (Q/Tab/X)
		var wb := Weapon.BOMB if weapon_manual == Weapon.BOMB else Weapon.LASER
		if wb != weapon:
			weapon = wb
			hud.on_weapon_changed()
		return
	if weapon_manual == Weapon.BOMB:
		weapon_manual = Weapon.LASER
	if weapon == Weapon.BOMB:
		weapon = Weapon.LASER   # Bomben nur über Feindplaneten (z. B. nach dem Sieg)
		hud.on_weapon_changed()
	if not Config.auto_weapon_switch:
		weapon = weapon_manual
		return
	var w := weapon
	if aim_target:
		w = Weapon.LASER if aim_target.kind == Enemy.Kind.FIGHTER else Weapon.ION
	elif has_enemy_kind(Enemy.Kind.FIGHTER):
		w = Weapon.LASER
	elif has_enemy_kind(Enemy.Kind.DESTROYER) or has_enemy_kind(Enemy.Kind.FLAGSHIP):
		w = Weapon.ION
	if w != weapon:
		weapon = w
		hud.on_weapon_changed()


func _update_weapons(delta: float) -> void:
	var was_ready := ion_cd <= 0.0
	laser_cd -= delta
	ion_cd -= delta
	bomb_cd -= delta
	if not was_ready and ion_cd <= 0.0:
		Audio.sfx("ion_ready", 0.0)
	_select_weapon()
	if not fire_enabled or not controls_enabled:
		return
	if weapon == Weapon.BOMB:
		if _fire_just_pressed():
			if GameState.bombs <= 0:
				Audio.sfx("bomb_empty" if Audio.has_sound("bomb_empty") else "ui_error", -4.0, 1.0, 0.0, "UI")
				hud.show_message("KEINE BOMBEN MEHR", "Nachladen nur beim Andocken an eigenen Stationen", 2.2, UITheme.AMBER, true)
			elif bomb_cd > 0.0:
				Audio.ui("ui_error", -10.0)
			else:
				bomb_cd = Config.bomb_cooldown
				drop_bomb()
		return
	if weapon == Weapon.LASER:
		if Input.is_action_pressed("fire") and laser_cd <= 0.0:
			laser_cd = Config.laser_fire_interval
			var conv := aim_target.distance_to_player() if aim_target else 80.0
			shots.fire_laser(camera.global_position, -camera.global_transform.basis.z, clampf(conv, 20.0, 250.0))
			Audio.sfx("laser", 0.0, 1.0, 0.05, "SFX", 3)
			shake = maxf(shake, 0.05)
	else:
		if _fire_just_pressed():
			if ion_cd <= 0.0:
				ion_cd = Config.ion_cooldown
				shots.fire_ion(camera.global_position, -camera.global_transform.basis.z)
				Audio.sfx("ion_fire", 0.0)
				shake = maxf(shake, 0.35)
				aberr = maxf(aberr, 0.25)
			else:
				Audio.ui("ui_error", -10.0)


func _unhandled_input(event: InputEvent) -> void:
	if dying or victory_mode:
		return
	if event.is_action_pressed("switch_weapon") and bombs_allowed():
		weapon_manual = Weapon.LASER if weapon == Weapon.BOMB else Weapon.BOMB
		_select_weapon()
		var snd := "weapon_bombs" if weapon == Weapon.BOMB else "weapon_laser"
		if Audio.has_sound(snd):
			Audio.sfx(snd, -2.0, 1.0, 0.0, "UI")
		else:
			Audio.ui("ui_select")
		if weapon == Weapon.BOMB:
			if GameState.bombs > 0:
				hud.show_message("BOMBEN SCHARF", "%d an Bord · Aufschlagmarke auf eine Stadt, dann FEUER" % GameState.bombs, 1.6, UITheme.AMBER, true)
			else:
				hud.show_message("KEINE BOMBEN MEHR", "Nachladen nur beim Andocken an eigenen Stationen", 1.8, UITheme.AMBER, true)
		return
	if event.is_action_pressed("switch_weapon"):
		if Config.auto_weapon_switch:
			hud.show_message("AUTOMATISCHE WAFFENWAHL AKTIV", "Umschalten in den Optionen", 1.6, UITheme.TEXT_DIM)
		else:
			weapon_manual = Weapon.ION if weapon_manual == Weapon.LASER else Weapon.LASER
			hud.on_weapon_changed()
			Audio.ui("ui_select")


func ion_charge() -> float:
	return clampf(1.0 - ion_cd / Config.ion_cooldown, 0.0, 1.0)


# ---------------------------------------------------------------------------------------------
#  Treffer am Spieler
# ---------------------------------------------------------------------------------------------
func player_hit(damage: float, kind: int, _dir: Vector3) -> void:
	if dying or GameState.game_over:
		return
	var heavy := kind != ShotSystem.Kind.E_FIGHTER
	GameState.change_energy(-damage)
	if heavy:
		Audio.sfx("player_hit_heavy", 2.0)
		shake = maxf(shake, 1.4 if kind == ShotSystem.Kind.E_FLAGSHIP else 1.0)
		flash = 0.65
		flash_color = Color(1.0, 0.35, 0.2) if kind != ShotSystem.Kind.E_FLAGSHIP else Color(1.0, 0.5, 0.9)
		aberr = 1.0
		noise_lines = 1.0
		hud.on_player_hit(true, damage)
	else:
		Audio.sfx("player_hit_light", 0.0, 1.0, 0.08)
		shake = maxf(shake, 0.4)
		flash = maxf(flash, 0.25)
		flash_color = Color(1.0, 0.4, 0.3)
		aberr = maxf(aberr, 0.35)
		hud.on_player_hit(false, damage)


func on_near_miss(kind: int) -> void:
	if kind != ShotSystem.Kind.E_FIGHTER:
		hud.show_message("AUSGEWICHEN!", "", 0.9, UITheme.GREEN, true)
		shake = maxf(shake, 0.3)


func on_heavy_shot_fired(_src: Node) -> void:
	_incoming_warn_t = 0.0


func _update_incoming(delta: float) -> void:
	_incoming_warn_t -= delta
	var inc := shots.incoming_heavy()
	if not inc.is_empty() and _incoming_warn_t <= 0.0:
		_incoming_warn_t = 1.2
		Audio.sfx("incoming", -3.0)


func _on_energy_changed(_value: float, _delta: float) -> void:
	pass


## [FREI] Warnton bei niedriger Energie: ein kurzer Stoß beim Unterschreiten von energy_low_warning
## bzw. energy_critical_warning, danach nur noch seltene Erinnerungen – kein Dauerpiepen.
func _update_low_energy(delta: float) -> void:
	_lock_beep_t = maxf(_lock_beep_t - delta, 0.0)
	var e := GameState.energy
	var stage := 0
	if e < Config.energy_critical_warning:
		stage = 2
	elif e < Config.energy_low_warning:
		stage = 1
	if _warn_stage < 0:
		# Szenenstart: Stoß nur, wenn eine Schwelle seit der letzten Warnung neu unterschritten wurde
		# (z. B. durch die Sprungkosten), sonst sofort eine einzelne Erinnerung
		_warn_stage = mini(stage, GameState.warned_energy_stage)
	var docking: bool = has_method("is_docking") and call("is_docking")
	if GameState.game_over or docking:
		_warn_beeps_left = 0
		_warn_stage = stage
		GameState.warned_energy_stage = stage
		return
	if stage > _warn_stage:
		_warn_beeps_left = Config.energy_warning_burst
		_warn_timer = 0.0
		_warn_reminder = Config.energy_warning_reminder
	_warn_stage = stage
	GameState.warned_energy_stage = stage
	if stage == 0:
		_warn_beeps_left = 0
		return
	if _warn_beeps_left > 0:
		_warn_timer -= delta
		if _warn_timer <= 0.0:
			_warn_timer = Config.energy_warning_interval
			_warn_beeps_left -= 1
			Audio.sfx("warning_low_energy", -2.0)
	elif Config.energy_warning_reminder > 0.0:
		_warn_reminder -= delta
		if _warn_reminder <= 0.0:
			_warn_reminder = Config.energy_warning_reminder
			Audio.sfx("warning_low_energy", -5.0)


# ---------------------------------------------------------------------------------------------
#  Kamera-Effekte und Nachbearbeitung
# ---------------------------------------------------------------------------------------------
func _update_post(delta: float) -> void:
	shake = maxf(shake - delta * 2.2, 0.0)
	flash = maxf(flash - delta * 1.8, 0.0)
	aberr = maxf(aberr - delta * 1.5, 0.0)
	noise_lines = maxf(noise_lines - delta * 1.6, 0.0)
	var s := shake * shake * Config.screen_shake
	camera.h_offset = randf_range(-1, 1) * s * 0.25
	camera.v_offset = randf_range(-1, 1) * s * 0.25
	hud.shake_offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * s * 9.0
	var pf: ColorRect = Main.instance.postfx if Main.instance else null
	if pf:
		var m := pf.material as ShaderMaterial
		m.set_shader_parameter("aberration", aberr)
		m.set_shader_parameter("noise_lines", noise_lines)
		m.set_shader_parameter("flash_color", Color(flash_color, flash * 0.55))
		m.set_shader_parameter("scanlines", 0.035 if Settings.retro_filter else 0.0)


# ---------------------------------------------------------------------------------------------
#  Gegner-Verwaltung
# ---------------------------------------------------------------------------------------------
func add_enemy(e: Enemy, pos: Vector3) -> void:
	e.position = pos
	enemies.append(e)
	add_child(e)


func on_enemy_destroyed(e: Enemy) -> void:
	enemies.erase(e)
	shake = maxf(shake, 0.5 if e.kind == Enemy.Kind.FIGHTER else 1.2)
	match e.kind:
		Enemy.Kind.FIGHTER:
			hud.add_popup(e.global_position, "+%d" % Config.fighter_points, UITheme.FIGHTER_COLOR)
		Enemy.Kind.DESTROYER:
			var d := e as Destroyer
			hud.add_popup(e.global_position, "+%d" % int(Config.by_color(Config.destroyer_points, d.data.color)), d.hud_color)
		Enemy.Kind.FLAGSHIP:
			hud.add_popup(e.global_position, "+%d" % Config.flagship_points, UITheme.PINK)
	_on_enemy_removed(e)


func _on_enemy_removed(_e: Enemy) -> void:
	pass


func on_destroyer_damaged(_d: Destroyer) -> void:
	pass


func on_destroyer_engages(_d: Destroyer) -> void:
	pass


func on_flagship_vulnerable(_f: Flagship) -> void:
	hud.show_message("QUADRAT LEUCHTET!", "Jetzt Ionen-Kanone auf das Quadrat", 1.4, UITheme.PINK, true)


func on_flagship_immune(_f: Flagship, on_weak: bool) -> void:
	if on_weak:
		hud.show_message("ZU FRÜH!", "Nur verwundbar, wenn das Quadrat weiß-rosa leuchtet", 1.4, UITheme.AMBER, true)


func on_flagship_retreated(_f: Flagship) -> void:
	enemies.erase(_f)
	hud.show_message("FLAGGSCHIFF ZIEHT SICH ZURÜCK", "", 2.0, UITheme.TEXT_DIM)
	if _f.squadron:
		_f.squadron.has_flagship = false


func engaging_count() -> int:
	var n := 0
	for e in enemies:
		if e is Destroyer and is_instance_valid(e) and e.alive and e.is_engaging():
			n += 1
	return n


## Planeten-Schnittstelle (in PlanetCombat implementiert)
func city_world_pos(_idx: int) -> Vector3:
	return Vector3.ZERO


func city_alive(_idx: int) -> bool:
	return false


func next_city_for(_d: Destroyer) -> int:
	return -1


func on_city_bombarded(_idx: int, _progress: float) -> void:
	pass


func destroy_city(_idx: int) -> void:
	pass


# ---------------------------------------------------------------------------------------------
#  Sieg: alle Städte im Feindsystem vernichtet – kurze Siegsequenz, danach Auswertung
# ---------------------------------------------------------------------------------------------
func play_victory_sequence(cb: Callable) -> void:
	if dying or victory_mode:
		return
	victory_mode = true
	_victory_cb = cb
	_victory_t = 0.0
	fire_enabled = false
	Audio.stop_all_loops(1.0)
	Audio.play_music("victory_theme" if Audio.has_music("victory_theme") else "title_theme", 1.2)
	Audio.sfx("planet_saved", 2.0)
	var home := GameState.enemy_home()
	var what := "Alle Städte im %s-System sind zerstört" % GameState.ENEMY_STAR_NAME
	if not Config.victory_all_enemy_cities:
		what = "%s ist gefallen" % (home.name if home else "Die Heimatwelt")
	hud.show_message("SIEG!", "%s – das %s-System ist gerettet!" % [what, GameState.STAR_NAME], 7.0, UITheme.GREEN)
	location_sub = "SIEG"
	hint_text = "Auswertung folgt …"
	# verbliebene Gegner ziehen sich zurück (ohne Punkte/Statistik)
	for e in enemies.duplicate():
		if is_instance_valid(e) and e.alive:
			e.alive = false
			Effects.warp_in(fx_root, e.global_position, 6.0 if e.kind == Enemy.Kind.FIGHTER else 20.0, Color(1.0, 0.4, 0.6))
			e.queue_free()
	enemies.clear()
	shots.clear_all()


func _update_victory(delta: float) -> void:
	_victory_t += delta
	if fmod(_victory_t, 0.6) < delta and _victory_t < 5.0:
		var dir := (-camera.global_transform.basis.z).rotated(Vector3.UP, randf_range(-0.6, 0.6))
		var at := camera.global_position + Vector3(dir.x, 0.0, dir.z).normalized() * randf_range(200.0, 520.0)
		at.y = randf_range(4.0, 40.0)
		Effects.explosion(fx_root, at, randf_range(18.0, 34.0), Color(1.0, 0.45, 0.7), false)
		Audio.sfx_3d("explosion_large", self, at, 0.0, 0.1, 2, 400.0)
	if _victory_t > 7.5 and _victory_cb.is_valid():
		var cb := _victory_cb
		_victory_cb = Callable()
		cb.call()


# ---------------------------------------------------------------------------------------------
#  Eigene Zerstörung (Energie 0)
# ---------------------------------------------------------------------------------------------
func play_death_sequence(cb: Callable, reason := "energy") -> void:
	if dying:
		return
	dying = true
	_death_cb = cb
	_death_t = 0.0
	_death_reason = reason
	controls_enabled = false
	fire_enabled = false
	Audio.stop_all_loops(1.5)
	if reason == "cities":
		# [ORIGINAL] verloren, wenn alle Städte zerstört sind – das eigene Schiff bleibt dabei heil
		hud.show_message("%s GEFALLEN" % GameState.STAR_NAME.to_upper(), "Alle Städte des %s-Systems sind zerstört" % GameState.STAR_NAME, 4.0, UITheme.RED)
		Audio.sfx("city_destroyed", 0.0, 0.8)
		flash = 0.4
		flash_color = Color(0.6, 0.1, 0.1)
		return
	Audio.sfx("player_hit_heavy", 4.0, 0.8)
	Audio.sfx("explosion_large", 4.0, 0.7, 0.0, "SFX", 2)
	hud.show_message("ENERGIE ERSCHÖPFT", "Das Schiff verliert die Kontrolle …", 4.0, UITheme.RED)
	shake = 2.0
	flash = 1.0
	flash_color = Color(1.0, 0.3, 0.1)


func _update_death(delta: float) -> void:
	_death_t += delta
	if _death_reason != "energy":
		if _death_t > 3.2 and _death_cb.is_valid():
			var cb0 := _death_cb
			_death_cb = Callable()
			cb0.call()
		return
	shake = maxf(shake, 1.2 - _death_t * 0.2)
	noise_lines = 1.0
	aberr = 1.0
	camera.rotation.z += delta * 0.6
	if fmod(_death_t, 0.45) < delta:
		Effects.explosion(fx_root, camera.global_position + camera.global_transform.basis * Vector3(randf_range(-6, 6), randf_range(-4, 3), -randf_range(8, 16)), randf_range(4, 9), Color(1.0, 0.5, 0.2), false)
		Audio.sfx("explosion_small", 0.0, 0.8, 0.1, "SFX", 3)
	if _death_t > 3.2 and _death_cb.is_valid():
		var cb := _death_cb
		_death_cb = Callable()
		cb.call()


# ---------------------------------------------------------------------------------------------
#  Gemeinsame Umgebungsbausteine
# ---------------------------------------------------------------------------------------------
func make_environment(sky_mat: Material, ambient := Color(0.25, 0.3, 0.4), ambient_energy := 0.6) -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = ambient
	env.ambient_light_energy = ambient_energy
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_normalized = false
	env.glow_intensity = 0.65
	env.glow_strength = 1.0
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.0
	env.glow_hdr_scale = 2.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	for i in 7:
		env.set_glow_level(i, [0.0, 0.6, 1.0, 0.8, 0.5, 0.0, 0.0][i])
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.12
	world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)


func make_sun(dir_to_sun: Vector3, color := Color(1.0, 0.95, 0.88), energy := 1.6, shadows := false) -> void:
	sun = DirectionalLight3D.new()
	sun.light_color = color
	sun.light_energy = energy
	sun.shadow_enabled = shadows
	if shadows:
		sun.directional_shadow_max_distance = 900.0
		sun.shadow_blur = 1.5
	add_child(sun)
	var d := dir_to_sun.normalized()
	var up := Vector3.UP if absf(d.y) < 0.95 else Vector3.FORWARD
	sun.look_at_from_position(Vector3.ZERO, -d, up)
