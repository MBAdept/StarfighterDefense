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
# Trefferzone (Ellipsoid im lokalen Raum) und Ausweichen
var _hit_center := Vector3.ZERO
var _hit_radii := Vector3.ONE * 8.0
var _dodge := Vector2.ZERO        ## aktueller Ausweichversatz (Grad; x = Gieren, y = Nicken)
var _dodge_goal := Vector2.ZERO
var _dodge_t := 0.0
var _dodge_delay := 0.0
## [FREI] Planet: Höhenband (m) über/unter der Trefferzone, in dem Schüsse ohne Rücksicht auf die Höhe zählen
const PLANET_HIT_BAND := 6.0


func _ready() -> void:
	kind = Kind.DESTROYER
	var c: int = data.color
	hud_color = UITheme.DESTROYER_COLORS[c]
	display_name = "ZERSTÖRER"   # Farbe wird nicht genannt – sie zeigt sich an der Schildfarbe
	model = Assets.model("destroyer")
	model.scale = Vector3.ONE * Config.destroyer_size_scale
	add_child(model)
	Assets.tint(model, "Accent", hud_color, 3.5)
	spawn_engine_glows(["Engine"], hud_color.lightened(0.3), 3.2)
	gun_node = Assets.find_node_named(model, "Gun_Main")
	bay_node = Assets.find_node_named(model, "BombBay")
	var aabb := _model_aabb()
	# [FREI] Trefferzone = Ellipsoid eng um den Rumpf; die Schildblase zeigt genau diese Form
	var sc := Config.destroyer_size_scale
	_hit_center = (aabb.position + aabb.size * 0.5) * sc
	_hit_radii = (aabb.size * 0.5 * sc * 1.15 * Config.destroyer_hitbox_scale).max(Vector3.ONE * 2.0)
	hit_radius = clampf(maxf(_hit_radii.x, _hit_radii.y), 4.0, 16.0)
	# Schildblase
	shield = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 48
	sm.rings = 24
	shield.mesh = sm
	shield.scale = _hit_radii * 1.05
	shield.position = _hit_center
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
	if not Config.combat_intel:
		# [Vorgabe 0.14.4] ab Normal: Schildblase gleich stark bis zur Vernichtung – sie verrät nicht, wie viele
		# Treffer noch fehlen (die Farbe bleibt, der Treffer-Aufblitz auch)
		sh = Config.destroyer_hits_needed(data.color) - 1
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
	_update_dodge(delta)
	var yaw := anchor_yaw + deg_to_rad(amp) * sin(w * t + phase_off) + deg_to_rad(_dodge.x)
	var pitch := clampf(anchor_pitch + deg_to_rad(amp * 0.5) * sin(w * 1.37 * t + phase_off * 2.0) + deg_to_rad(_dodge.y), deg_to_rad(-40), deg_to_rad(40))
	var cp := combat.camera.global_position
	var new_pos := cp + CombatBase.dir_from_angles(yaw, pitch) * dist
	velocity = (new_pos - global_position) / maxf(delta, 0.001)
	global_position = new_pos
	# dem Spieler zugewandt, leicht in Bewegungsrichtung gedreht
	var to_player := cp - global_position
	var lateral := velocity - to_player.normalized() * velocity.dot(to_player.normalized())
	face_dir(to_player + lateral * 0.6, Vector3.UP)
	_update_fire(delta)


## [FREI] Ionen-Kugel im Anflug (Strahl origin + dir·t): Fliegt sie auf ihn zu oder knapp vorbei
## (destroyer_dodge_threat), weicht er mit Chance je Farbe (destroyer_dodge_chance) blitzschnell aus –
## immer vom Schuss weg, nie in ihn hinein. Klare Fehlschüsse ignoriert er.
func on_ion_incoming(origin: Vector3, dir: Vector3) -> void:
	if planet_mode or not alive or _dodge_t > 0.0 or _dodge_delay > 0.0:
		return
	# Bahn gegen die Lage beim Eintreffen prüfen (vorgehaltene Schüsse zählen als Bedrohung)
	var hc := aim_point()
	var lead := velocity * ((hc - origin).length() / Config.ion_speed)
	if _ray_norm_dist(origin - lead, dir, Config.ion_hit_tolerance) > Config.destroyer_dodge_threat:
		return
	if randf() >= float(Config.by_color(Config.destroyer_dodge_chance, data.color)):
		return
	# Ausweichrichtung in der Bildebene des Spielers: vom Schussstrahl weg (x = rechts, y = oben)
	var future := hc + lead
	var closest := origin + dir * maxf((future - origin).dot(dir), 0.0)
	var away := future - closest
	var cb := combat.camera.global_transform.basis
	var v := Vector2(away.dot(cb.x), away.dot(cb.y))
	if v.length() < 0.5:
		v = Vector2.from_angle(randf() * TAU)   # Kurs genau auf die Mitte: zufällige Seite
	v = v.normalized().rotated(randf_range(-0.5, 0.5))
	var amt := Config.destroyer_dodge_angle * randf_range(0.75, 1.0)
	# Gieren: + = nach links (dir_from_angles), Nicken: + = nach oben
	_dodge_goal = (_dodge + Vector2(-v.x, v.y * 0.6) * amt).limit_length(Config.destroyer_dodge_angle * 1.6)
	_dodge_delay = randf_range(Config.destroyer_dodge_reaction_min, Config.destroyer_dodge_reaction_max)
	_dodge_t = 2.0


func _update_dodge(delta: float) -> void:
	if _dodge_delay > 0.0:
		_dodge_delay -= delta
		return
	if _dodge_t > 0.0:
		_dodge_t -= delta
		_dodge = _dodge.lerp(_dodge_goal, 1.0 - exp(-7.0 * delta))   # schneller Seitenschritt
	else:
		_dodge = _dodge.lerp(Vector2.ZERO, 1.0 - exp(-0.7 * delta))  # langsam zurück auf die Bahn


## Mittelpunkt der Trefferzone (= Mitte der Schildblase) in Weltkoordinaten.
func aim_point() -> Vector3:
	return global_transform * _hit_center


## Radien der Trefferzone samt Toleranz. Auf Planeten zählt nur die waagerechte Lage (siehe segment_hit),
## dafür ist die Trefferbreite dort mit destroyer_planet_hit_scale einstellbar.
func _radii(tolerance: float) -> Vector3:
	var r := _hit_radii + Vector3.ONE * tolerance
	if planet_mode:
		r.x *= Config.destroyer_planet_hit_scale
		r.z *= Config.destroyer_planet_hit_scale
	return r


## Lage eines Weltpunkts relativ zur Mitte der Trefferzone (lokaler Raum des Zerstörers).
func _local(p: Vector3) -> Vector3:
	return global_transform.affine_inverse() * p - _hit_center


## Treffertest gegen die Trefferzone (Weltraum: Ellipsoid um den Rumpf; Planet: senkrechter Zylinder).
func segment_hit(p0: Vector3, p1: Vector3, tolerance: float) -> Dictionary:
	var r := _radii(tolerance)
	var a := _local(p0)
	var b := _local(p1)
	if planet_mode:
		var band := r.y + PLANET_HIT_BAND
		if (a.y > band and b.y > band) or (a.y < -band and b.y < -band):
			return {}
		a.y = 0.0
		b.y = 0.0
	if ShotSystem._seg_sphere(a / r, b / r, Vector3.ZERO, 1.0):
		return {"point": ShotSystem.seg_closest(p0, p1, aim_point()), "part": "hull"}
	return {}


## Kleinster Abstand eines Strahls (origin + dir·t, 0 ≤ t ≤ max_t Meter) zur Mitte der Trefferzone – gemessen in
## Trefferzonen-Radien: ≤ 1 = ein Schuss entlang des Strahls träfe (ohne Flugzeit/Bewegung).
func _ray_norm_dist(origin: Vector3, dir: Vector3, tolerance: float, max_t := INF) -> float:
	var r := _radii(tolerance)
	var lo := _local(origin)
	var ld := global_transform.affine_inverse().basis * dir
	if planet_mode:
		if absf(lo.y) > r.y + PLANET_HIT_BAND:
			return INF
		lo.y = 0.0
		ld.y = 0.0
	lo /= r
	ld /= r
	var dd := ld.length_squared()
	if dd < 0.000001:
		return lo.length()
	return (lo + ld * clampf(-lo.dot(ld) / dd, 0.0, max_t)).length()


## Zielerfassung passend zur Trefferzone: 0 = ein Ionen-Schuss in Blickrichtung träfe jetzt.
func aim_error_deg() -> float:
	var cam := combat.camera
	var o := cam.global_position
	var fwd := -cam.global_transform.basis.z
	var n := _ray_norm_dist(o, fwd, Config.ion_hit_tolerance, Config.ion_range)   # die Kugel erlischt nach ion_range
	if n <= 1.0:
		return 0.0
	var ang := rad_to_deg(fwd.angle_to(aim_point() - o))
	if is_inf(n):
		return maxf(ang, 0.02)
	return maxf(ang * (1.0 - 1.0 / n), 0.02)


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
