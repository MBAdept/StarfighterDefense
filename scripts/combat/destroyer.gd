class_name Destroyer
extends Enemy
## Zerstörer [ORIGINAL]: blau/grün/rot mit 1/2/3 Schilden (2/3/4 Treffer), stehen knapp außerhalb des
## Sichtfelds links oder rechts, kommen nacheinander, bewegen sich hin und her sowie hoch und runter.
## Auf Planeten: schweben über Städten und bombardieren sie (unbeweglich), können abbrechen und sich
## dem Spieler zuwenden.

enum PSt { LANDING, MOVING, BOMBARDING, ENGAGE }

var data: DestroyerData
var planet_mode := false
# Weltraum
var anchor_yaw := 0.0
var anchor_pitch := 0.0
var dist := 125.0
var t := 0.0
var phase_off := 0.0
# gemeinsam
var fire_timer := 5.0
var charge := 0.0
var charge_glow: MeshInstance3D
var shield: MeshInstance3D
var shield_mat: ShaderMaterial
var shield_hit := 0.0
var gun_node: Node3D
var bay_node: Node3D
# Planet
var pst := PSt.LANDING
var beam: MeshInstance3D
var engage_timer := 0.0
var _move_from := Vector3.ZERO
var _land_from := Vector3.ZERO


func _ready() -> void:
	kind = Kind.DESTROYER
	var c: int = data.color
	hud_color = UITheme.DESTROYER_COLORS[c]
	display_name = "ZERSTÖRER " + UITheme.DESTROYER_NAMES[c].to_upper()
	model = Assets.model("destroyer")
	model.scale = Vector3.ONE * Config.destroyer_size_scale
	add_child(model)
	Assets.tint(model, "Accent", hud_color, 3.5)
	spawn_engine_glows(["Engine"], hud_color.lightened(0.3), 3.2)
	gun_node = Assets.find_node_named(model, "Gun_Main")
	bay_node = Assets.find_node_named(model, "BombBay")
	var aabb := _model_aabb()
	hit_radius = clampf(maxf(aabb.size.x, aabb.size.y) * 0.55, 7.0, 16.0)
	# Schildblase
	shield = MeshInstance3D.new()
	var sm := SphereMesh.new()
	var sr := maxf(aabb.size.length() * 0.55, hit_radius * 1.3)
	sm.radius = sr
	sm.height = sr * 2.0
	sm.radial_segments = 48
	sm.rings = 24
	shield.mesh = sm
	shield.scale = Vector3(1.0, 0.7, 1.05)
	shield_mat = ShaderMaterial.new()
	shield_mat.shader = load("res://shaders/shield.gdshader")
	shield_mat.set_shader_parameter("shield_color", hud_color)
	shield.material_override = shield_mat
	shield.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shield)
	_update_shield_visual()
	# Ladeleuchten am Geschütz
	charge_glow = Assets.glow_sprite(Color(1.0, 0.5, 0.15), 3.0, 2.2)
	charge_glow.visible = false
	(gun_node if gun_node else self).add_child(charge_glow)
	var interval: float = Config.by_color(Config.destroyer_fire_interval, c)
	fire_timer = interval * randf_range(Config.destroyer_first_fire_min, Config.destroyer_first_fire_max)   # [FREI] erster Schuss bald nach dem Erscheinen
	phase_off = randf() * TAU
	if planet_mode:
		_setup_planet()
	Audio.sfx_3d("warp_in", combat, global_position, 0.0)
	Effects.warp_in(combat.fx_root, global_position, 14.0, hud_color)


func _model_aabb() -> AABB:
	var out := AABB()
	var first := true
	for mi in Assets.find_all_meshes(model):
		var a: AABB = mi.mesh.get_aabb() if mi.mesh else AABB()
		var xf: Transform3D = model.global_transform.affine_inverse() * mi.global_transform if mi.is_inside_tree() else mi.transform
		a = xf * a
		if first:
			out = a
			first = false
		else:
			out = out.merge(a)
	if first:
		out = AABB(Vector3(-7, -3, -12), Vector3(14, 6, 24))
	return out


func _update_shield_visual() -> void:
	var sh := data.shields_left()
	shield.visible = sh > 0 or shield_hit > 0.0
	shield_mat.set_shader_parameter("strength", 0.12 + 0.13 * sh)
	shield_mat.set_shader_parameter("hit", shield_hit)


func _process(delta: float) -> void:
	if not alive:
		return
	t += delta
	if shield_hit > 0.0:
		shield_hit = maxf(shield_hit - delta * 2.2, 0.0)
		_update_shield_visual()
	if planet_mode:
		_process_planet(delta)
	else:
		_process_space(delta)


# ---------------------------------------------------------------------------------------------
#  Weltraum
# ---------------------------------------------------------------------------------------------
func _process_space(delta: float) -> void:
	var c := data.color
	var amp: float = Config.by_color(Config.destroyer_osc_amplitude, c)
	var w: float = Config.by_color(Config.destroyer_osc_speed, c)
	var yaw := anchor_yaw + deg_to_rad(amp) * sin(w * t + phase_off)
	var pitch := clampf(anchor_pitch + deg_to_rad(amp * 0.5) * sin(w * 1.37 * t + phase_off * 2.0), deg_to_rad(-40), deg_to_rad(40))
	var cp := combat.camera.global_position
	var new_pos := cp + CombatBase.dir_from_angles(yaw, pitch) * dist
	velocity = (new_pos - global_position) / maxf(delta, 0.001)
	global_position = new_pos
	# dem Spieler zugewandt, leicht in Bewegungsrichtung gedreht
	var to_player := cp - global_position
	var lateral := velocity - to_player.normalized() * velocity.dot(to_player.normalized())
	face_dir(to_player + lateral * 0.6, Vector3.UP)
	_update_fire(delta)


func _update_fire(delta: float) -> void:
	fire_timer -= delta
	var charge_time := 1.1
	if fire_timer < charge_time:
		charge = 1.0 - fire_timer / charge_time
		charge_glow.visible = true
		charge_glow.scale = Vector3.ONE * (0.15 + charge * 0.85)
		if fire_timer + delta >= charge_time:
			Audio.sfx_3d("enemy_shot_destroyer", combat, global_position, 2.0)
	if fire_timer <= 0.0:
		charge = 0.0
		charge_glow.visible = false
		var c := data.color
		fire_timer = float(Config.by_color(Config.destroyer_fire_interval, c)) * randf_range(0.85, 1.15)
		var from := gun_node.global_position if gun_node else global_position
		combat.shots.fire_enemy(ShotSystem.Kind.E_DESTROYER, from, float(Config.by_color(Config.destroyer_damage, c)), Config.destroyer_hit_chance, Config.destroyer_shot_speed, self)
		combat.on_heavy_shot_fired(self)


# ---------------------------------------------------------------------------------------------
#  Planet
# ---------------------------------------------------------------------------------------------
func _setup_planet() -> void:
	beam = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.9
	cm.bottom_radius = 3.0
	cm.height = 1.0
	cm.radial_segments = 16
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	beam.mesh = cm
	var bm := ShaderMaterial.new()
	bm.shader = load("res://shaders/beam.gdshader")
	bm.set_shader_parameter("beam_color", hud_color.lerp(Color(1.0, 0.35, 0.15), 0.6))
	beam.material_override = bm
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.visible = false
	combat.fx_root.add_child(beam)
	pst = PSt.LANDING
	match data.phase:
		DestroyerData.Phase.LANDING:
			pst = PSt.LANDING
		DestroyerData.Phase.MOVING:
			pst = PSt.MOVING
		DestroyerData.Phase.BOMBARDING:
			pst = PSt.BOMBARDING
	if data.city < 0:
		data.city = combat.next_city_for(self)
	var hover := _hover_pos()
	if pst == PSt.LANDING:
		_land_from = hover + Vector3(0, 160.0, 0)
		global_position = _land_from
	elif pst == PSt.MOVING:
		global_position = hover + Vector3(randf_range(-60, 60), 0, randf_range(-60, 60))
	else:
		global_position = hover


func _hover_pos() -> Vector3:
	var cp: Vector3 = combat.city_world_pos(data.city) if data.city >= 0 else global_position
	return Vector3(cp.x, Config.planet_destroyer_altitude, cp.z)


func _exit_tree() -> void:
	if is_instance_valid(beam):
		beam.queue_free()


func _process_planet(delta: float) -> void:
	var player := combat.camera.global_position
	var dist_player := Vector2(global_position.x, global_position.z).distance_to(Vector2(player.x, player.z))
	var bob := sin(t * 1.3 + phase_off) * 1.2
	beam.visible = false
	match pst:
		PSt.LANDING:
			data.phase = DestroyerData.Phase.LANDING
			data.timer -= delta
			var target := _hover_pos()
			var k := clampf(1.0 - data.timer / Config.destroyer_land_time, 0.0, 1.0)   # gestaffelt: wartet oben, bis timer < land_time
			global_position = _land_from.lerp(target, ease(k, 0.4))
			face_dir(Vector3(0, 0, -1).rotated(Vector3.UP, phase_off), Vector3.UP)
			if data.timer <= 0.0:
				pst = PSt.BOMBARDING
		PSt.MOVING:
			data.phase = DestroyerData.Phase.MOVING
			if data.city < 0 or not combat.city_alive(data.city):
				data.city = combat.next_city_for(self)
				if data.city < 0:
					return
			var target := _hover_pos()
			var to := target - global_position
			var spd := 22.0 + 6.0 * data.color
			if to.length() < 2.0:
				pst = PSt.BOMBARDING
			else:
				velocity = to.normalized() * minf(spd, to.length() * 2.0)
				global_position += velocity * delta
				face_dir(Vector3(to.x, 0, to.z), Vector3.UP)
		PSt.BOMBARDING:
			data.phase = DestroyerData.Phase.BOMBARDING
			if data.city < 0 or not combat.city_alive(data.city):
				data.city = combat.next_city_for(self)
				data.progress = 0.0
				pst = PSt.MOVING
				return
			# [ORIGINAL] beim Bombardement unbeweglich
			global_position = _hover_pos() + Vector3(0, bob * 0.3, 0)
			data.progress += delta / Config.bombard_time
			beam.visible = true
			var from := bay_node.global_position if bay_node else global_position - Vector3(0, 3, 0)
			var ground := Vector3(from.x, 0.0, from.z)
			beam.global_position = (from + ground) * 0.5
			beam.scale = Vector3(1, from.y - ground.y, 1)
			combat.on_city_bombarded(data.city, data.progress)
			if data.progress >= 1.0:
				var c := data.city
				data.progress = 0.0
				combat.destroy_city(c)
				data.city = combat.next_city_for(self)
				pst = PSt.MOVING
			# [ORIGINAL] kann das Bombardement abbrechen und sich dem Spieler zuwenden
			elif dist_player < Config.destroyer_abort_distance and combat.engaging_count() < Config.planet_max_engaging and randf() < Config.destroyer_abort_chance * delta:
				_engage()
		PSt.ENGAGE:
			engage_timer += delta
			var fwd := -combat.camera.global_transform.basis.z
			var right := combat.camera.global_transform.basis.x
			var target := player + Vector3(fwd.x, 0, fwd.z).normalized() * 105.0 + right * sin(t * 0.6 + phase_off) * 45.0
			target.y = Config.planet_destroyer_altitude + bob
			var to := target - global_position
			var spd := 14.0 + 5.0 * data.color
			velocity = velocity.lerp(to.normalized() * minf(spd, to.length() * 1.5), 1.0 - exp(-1.5 * delta))
			global_position += velocity * delta
			face_dir(player - global_position, Vector3.UP)
			_update_fire(delta)
			if engage_timer > Config.destroyer_engage_time or dist_player > Config.destroyer_disengage_distance:
				pst = PSt.MOVING   # zurück zur Stadt, Fortschritt bleibt
	if pst != PSt.ENGAGE and charge_glow.visible:
		charge_glow.visible = false


func _engage() -> void:
	if pst == PSt.ENGAGE:
		return
	pst = PSt.ENGAGE
	engage_timer = 0.0
	fire_timer = minf(fire_timer, 2.5)
	combat.on_destroyer_engages(self)


func is_bombarding() -> bool:
	return planet_mode and pst == PSt.BOMBARDING


func is_engaging() -> bool:
	return planet_mode and pst == PSt.ENGAGE


# ---------------------------------------------------------------------------------------------
#  Treffer
# ---------------------------------------------------------------------------------------------
func on_laser_hit(res: Dictionary) -> void:
	var p: Vector3 = res.get("point", global_position)
	if Config.laser_hurts_destroyers:
		on_ion_hit(res)
		return
	Effects.sparks(combat.fx_root, Vector3.ZERO, hud_color.lightened(0.5), 8, 10.0, 0.15, 0.3).global_position = p
	Audio.sfx_3d("laser_deflect", combat, p, -6.0, 0.15)
	shield_hit = maxf(shield_hit, 0.25)
	shield_mat.set_shader_parameter("hit_dir", to_local(p).normalized())
	_update_shield_visual()


func on_ion_hit(res: Dictionary) -> void:
	if not alive:
		return
	var p: Vector3 = res.get("point", global_position)
	var had_shield := data.shields_left() > 0
	var destroyed := GameState.on_destroyer_hit(squadron, data)
	if planet_mode and pst != PSt.ENGAGE and not destroyed:
		_engage()
	if destroyed:
		_destroy()
		return
	shield_hit = 1.0
	shield_mat.set_shader_parameter("hit_dir", to_local(p).normalized())
	_update_shield_visual()
	Effects.flash(combat.fx_root, p, hud_color.lightened(0.5), 16.0, 0.4)
	Effects.sparks(combat.fx_root, Vector3.ZERO, hud_color.lightened(0.6), 40, 26.0, 0.3, 0.7).global_position = p
	Audio.sfx_3d("shield_hit", combat, p, 2.0)
	if had_shield:
		Audio.sfx_3d("shield_break", combat, p, 0.0)
	combat.on_destroyer_damaged(self)


func _destroy() -> void:
	alive = false
	charge_glow.visible = false
	if is_instance_valid(beam):
		beam.visible = false
	Effects.explosion(combat.fx_root, global_position, 16.0, hud_color.lerp(Color(1.0, 0.55, 0.2), 0.6))
	Audio.sfx_3d("explosion_large", combat, global_position, 4.0, 0.06, 2, 120.0)
	combat.on_enemy_destroyed(self)
	queue_free()
