class_name Fighter
extends Enemy
## Fighter [ORIGINAL]: suchen den Spieler selbst und kommen aktiv auf ihn zu, fliegen meist um das
## Fadenkreuz herum, überfliegen den Spieler kurz (nach oben, nie darunter durch) und kehren schnell zurück.

enum St { ARRIVE, ORBIT, DIVE, OVER, RETURN }

var st := St.ARRIVE
var planet_mode := false
var orbit_phase := 0.0
var orbit_speed := 0.8
var orbit_angle := 10.0
var orbit_dist := 55.0
var flyover_timer := 9.0
var fire_timer := 4.0
var retune_timer := 3.0
var bank := 0.0
var return_x := 0.0
var _prev_vel := Vector3.ZERO
var _burst_left := 0
var _burst_t := 0.0
## Aggressivität (Empfangskomitee/Verteidiger im Feindsystem): Feuerrate × fire_rate_factor,
## Schüsse je Feuerstoß = burst_shots (< 0: Config.fighter_burst_shots). Vor add_enemy() setzen.
var fire_rate_factor := 1.0
var burst_shots := -1
var damage := -1.0   ## Energieverlust je Treffer (< 0: Config.fighter_damage), z. B. Config.enemy_fighter_damage


func _ready() -> void:
	kind = Kind.FIGHTER
	hit_radius = Config.fighter_hit_radius
	hud_color = UITheme.FIGHTER_COLOR
	display_name = "FIGHTER"
	model = Assets.model("fighter")
	add_child(model)
	spawn_engine_glows(["Engine_L", "Engine_R"], Color(1.0, 0.5, 0.18), 1.5)
	_retune()
	orbit_phase = randf() * TAU
	flyover_timer = randf_range(Config.fighter_flyover_min, Config.fighter_flyover_max)
	fire_timer = randf_range(Config.fighter_first_fire_min, Config.fighter_first_fire_max) / maxf(fire_rate_factor, 0.1)   # [FREI] erster Feuerstoß schon im Anflug
	Audio.sfx_3d("warp_in", combat, global_position, -6.0)
	Effects.warp_in(combat.fx_root, global_position, 5.0, Color(1.0, 0.5, 0.25))


func _retune() -> void:
	orbit_speed = randf_range(Config.fighter_orbit_speed_min, Config.fighter_orbit_speed_max) * (1.0 if randf() < 0.5 else -1.0)
	orbit_angle = randf_range(Config.fighter_orbit_angle_min, Config.fighter_orbit_angle_max)
	orbit_dist = randf_range(Config.fighter_distance_min, Config.fighter_distance_max)
	retune_timer = randf_range(2.5, 5.0)


func _process(delta: float) -> void:
	if not alive:
		return
	var cam := combat.camera
	var cb := cam.global_transform.basis
	var cp := cam.global_position
	var local := cb.inverse() * (global_position - cp)
	# laufender Feuerstoß (Schüsse kurz hintereinander)
	if _burst_left > 0:
		_burst_t -= delta
		if _burst_t <= 0.0:
			_burst_left -= 1
			_burst_t = Config.fighter_burst_gap
			if local.z < -8.0:
				_fire_shot()
	var speed := Config.fighter_speed
	var lt := Vector3.ZERO
	match st:
		St.ARRIVE, St.ORBIT:
			orbit_phase += orbit_speed * delta
			var r := tan(deg_to_rad(orbit_angle)) * orbit_dist
			var vy := 0.7 if not planet_mode else 0.12
			lt = Vector3(cos(orbit_phase) * r, sin(orbit_phase * 1.31) * r * vy, -orbit_dist)
			if st == St.ARRIVE:
				speed *= 1.6
				if local.z > -orbit_dist * 1.35:
					st = St.ORBIT
			else:
				retune_timer -= delta
				if retune_timer <= 0.0:
					_retune()
				flyover_timer -= delta
				if flyover_timer <= 0.0 and local.z < -15.0:
					st = St.DIVE
			# [FREI] feuert schon im Anflug (ARRIVE) und beim Kreisen (ORBIT), nicht beim Überflug
			_update_fire(delta, local)
		St.DIVE:
			# Anflug knapp über das Cockpit
			lt = Vector3(local.x * 0.4, 4.0, -4.0)
			speed *= 1.75
			if local.z > -11.0:
				st = St.OVER
		St.OVER:
			lt = Vector3(local.x * 0.5, 9.0, 34.0)
			speed *= 2.0
			if local.z > 20.0:
				st = St.RETURN
				return_x = randf_range(-25.0, 25.0)
		St.RETURN:
			# schnell zurück (oben herum) nach vorn
			lt = Vector3(return_x, 16.0 if local.z > -10.0 else 4.0, -orbit_dist)
			speed *= 1.9
			if local.z < -orbit_dist * 0.75:
				st = St.ORBIT
				flyover_timer = randf_range(Config.fighter_flyover_min, Config.fighter_flyover_max)
	var target := cp + cb * lt
	if planet_mode:
		target.y = clampf(target.y, Config.planet_altitude - 3.0, Config.planet_altitude + 22.0)
		if st == St.ORBIT or st == St.ARRIVE:
			target.y = clampf(target.y, Config.planet_altitude - 1.5, Config.planet_altitude + 1.5)
	var to := target - global_position
	var dist := to.length()
	var desired := Vector3.ZERO if dist < 0.01 else to / dist * minf(speed, dist * 2.2 + 6.0)
	velocity = velocity.lerp(desired, 1.0 - exp(-Config.fighter_steer * delta))
	global_position += velocity * delta
	# nie unter dem Spieler hindurch: beim Überflug immer oberhalb bleiben
	if st == St.DIVE or st == St.OVER or st == St.RETURN:
		var l2 := cb.inverse() * (global_position - cp)
		if absf(l2.z) < 18.0 and l2.y < 3.0:
			l2.y = 3.0
			global_position = cp + cb * l2
	if planet_mode and global_position.y < 6.0:
		global_position.y = 6.0
	# Ausrichtung mit Schräglage
	var accel := (velocity - _prev_vel) / maxf(delta, 0.001)
	_prev_vel = velocity
	var right := velocity.cross(cb.y).normalized() if velocity.length() > 0.5 else cb.x
	var target_bank := clampf(-accel.dot(right) * 0.03, -1.1, 1.1)
	bank = lerpf(bank, target_bank, 1.0 - exp(-4.0 * delta))
	face_dir(velocity if velocity.length() > 1.0 else -cb.z, cb.y, bank)


func _update_fire(delta: float, local: Vector3) -> void:
	if local.z > -8.0 or _burst_left > 0:
		return
	var ang := rad_to_deg(Vector3(0, 0, -1).angle_to(local))
	if ang > Config.fighter_fire_cone or local.length() > Config.fighter_fire_range:
		return
	fire_timer -= delta
	if fire_timer <= 0.0:
		fire_timer = randf_range(Config.fighter_fire_min, Config.fighter_fire_max) / maxf(fire_rate_factor, 0.1)
		_burst_left = maxi(burst_shots if burst_shots >= 0 else Config.fighter_burst_shots, 1) - 1
		_burst_t = Config.fighter_burst_gap
		_fire_shot()


func _fire_shot() -> void:
	# abwechselnd linke/rechte Bordkanone
	var gun := Assets.find_node_named(model, "Gun_L" if _burst_left % 2 == 0 else "Gun_R")
	var from := (gun as Node3D).global_position if gun else global_position
	combat.shots.fire_enemy(ShotSystem.Kind.E_FIGHTER, from, damage if damage >= 0.0 else Config.fighter_damage, Config.fighter_hit_chance, Config.fighter_shot_speed, self)
	Audio.sfx_3d("enemy_shot_fighter", combat, from, 0.0, 0.06, 0, 70.0)


func on_laser_hit(res: Dictionary) -> void:
	_destroy(res.get("point", global_position))


func on_ion_hit(res: Dictionary) -> void:
	if Config.ion_hurts_fighters:
		_destroy(res.get("point", global_position))


func _destroy(_at: Vector3) -> void:
	if not alive:
		return
	alive = false
	Effects.explosion(combat.fx_root, global_position, 6.0, Color(1.0, 0.55, 0.2))
	Audio.sfx_3d("explosion_small", combat, global_position, 2.0, 0.08, 3, 60.0)
	combat.on_enemy_destroyed(self)
	queue_free()
