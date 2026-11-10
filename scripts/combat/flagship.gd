class_name Flagship
extends Enemy
## Flaggschiff [ORIGINAL]: links/rechts knapp außerhalb des Sichtfelds; nur mit der Ionen-Kanone zu
## besiegen, 1 Treffer, aber nur auf das rosa Quadrat in der Schiffsmitte und nur kurz vor seinem
## eigenen Schuss (Quadrat wird von dunkel langsam heller bis weiß-rosa – genau dann verwundbar).

enum St { ARRIVE, COOLDOWN, CHARGING, VULNERABLE, RETREAT }

var st := St.ARRIVE
var st_time := 0.0
var anchor_yaw := 0.0
var anchor_pitch := 0.0
var dist := 260.0
var t := 0.0
var weak_node: Node3D
var weak_mats: Array = []
var weak_light: OmniLight3D
var weak_glow: MeshInstance3D
var _local_aabb := AABB()
var retreat_timer := 0.0
var _retreat_armed := false   ## Rückzug nach Vernichtung des Schwadrons angesetzt
var brightness := 0.0


func _ready() -> void:
	kind = Kind.FLAGSHIP
	hud_color = UITheme.PINK
	display_name = "FLAGGSCHIFF"
	model = Assets.model("flagship")
	add_child(model)
	Assets.tint(model, "Accent", Color(0.55, 0.25, 1.0), 2.0)
	spawn_engine_glows(["Engine"], Color(0.7, 0.4, 1.0), 8.0)
	weak_node = Assets.find_node_named(model, "WeakPoint")
	if weak_node:
		weak_mats = Assets.materials_with_prefix(weak_node, "WeakPoint")
		if weak_mats.is_empty():
			weak_mats = Assets.materials_with_prefix(model, "WeakPoint")
	else:
		weak_mats = Assets.materials_with_prefix(model, "WeakPoint")
	var anchor: Node3D = weak_node if weak_node else self
	weak_light = OmniLight3D.new()
	weak_light.light_color = UITheme.PINK
	weak_light.omni_range = 40.0
	weak_light.light_energy = 0.0
	anchor.add_child(weak_light)
	weak_light.position = Vector3(0, 0, -3) if weak_node == null else Vector3.ZERO
	weak_glow = Assets.glow_sprite(Color(1.0, 0.45, 0.9), 18.0, 3.0)
	anchor.add_child(weak_glow)
	weak_glow.visible = false
	_local_aabb = _compute_aabb()
	hit_radius = clampf(maxf(_local_aabb.size.x, _local_aabb.size.y) * 0.5, 20.0, 60.0)
	_set_brightness(0.0)
	Audio.sfx_3d("warp_in", combat, global_position, 6.0, 0.0, 0, 200.0)
	Effects.warp_in(combat.fx_root, global_position, 40.0, Color(0.8, 0.4, 1.0))
	st = St.ARRIVE
	st_time = 0.0


func _compute_aabb() -> AABB:
	var out := AABB()
	var first := true
	for mi in Assets.find_all_meshes(model):
		if mi.mesh == null:
			continue
		var xf: Transform3D = global_transform.affine_inverse() * mi.global_transform
		var a: AABB = xf * mi.mesh.get_aabb()
		if first:
			out = a
			first = false
		else:
			out = out.merge(a)
	if first:
		out = AABB(Vector3(-35, -12, -50), Vector3(70, 24, 100))
	return out


func weak_point_pos() -> Vector3:
	if weak_node:
		return weak_node.global_position
	return global_position - global_transform.basis.z * (_local_aabb.size.z * 0.5)


func is_vulnerable() -> bool:
	return st == St.VULNERABLE


## Ladezustand 0..1 (für HUD).
func charge_level() -> float:
	if st == St.CHARGING:
		return clampf(st_time / maxf(Config.flagship_charge_time - Config.flagship_vulnerable_time, 0.1), 0.0, 1.0)
	if st == St.VULNERABLE:
		return 1.0
	return 0.0


func _set_brightness(b: float) -> void:
	brightness = b
	# dunkel → pink → weiß-rosa
	var col := Color(0.25, 0.02, 0.15).lerp(Color(1.0, 0.31, 0.82), clampf(b * 1.4, 0.0, 1.0))
	if b > 0.85:
		col = col.lerp(Color(1.0, 0.85, 0.97), (b - 0.85) / 0.15)
	for m in weak_mats:
		var bm := m as BaseMaterial3D
		bm.emission_enabled = true
		bm.emission = col
		bm.albedo_color = col.darkened(0.3)
		bm.emission_energy_multiplier = 0.2 + b * b * 9.0
	weak_light.light_energy = b * b * 6.0
	weak_glow.visible = b > 0.3
	weak_glow.scale = Vector3.ONE * (0.3 + b)


func _process(delta: float) -> void:
	if not alive:
		return
	t += delta
	st_time += delta
	# langsames Driften, dem Spieler zugewandt
	var yaw := anchor_yaw + deg_to_rad(3.0) * sin(t * 0.17)
	var pitch := anchor_pitch + deg_to_rad(1.5) * sin(t * 0.23 + 1.0)
	var cp := combat.camera.global_position
	global_position = cp + CombatBase.dir_from_angles(yaw, pitch) * dist
	# leicht schräg, damit die Tiefe des Rumpfs sichtbar bleibt (Quadrat bleibt sichtbar)
	face_dir((cp - global_position).rotated(Vector3.UP, deg_to_rad(16.0)) + Vector3(0, -12.0, 0), Vector3.UP)
	match st:
		St.ARRIVE:
			_set_brightness(0.0)
			if st_time > 2.5:
				_enter(St.COOLDOWN)
		St.COOLDOWN:
			_set_brightness(0.0)
			# [FREI] nach dem Schwadronsieg kein neuer Ladezyklus mehr – es wartet nur auf den Rückzug
			if st_time > Config.flagship_cooldown and not _retreat_armed:
				_enter(St.CHARGING)
				_ensure_charge_sound(1.0)
		St.CHARGING:
			var ramp := Config.flagship_charge_time - Config.flagship_vulnerable_time
			var k := clampf(st_time / maxf(ramp, 0.1), 0.0, 1.0)
			_set_brightness(k * 0.85)
			_ensure_charge_sound(0.3)
			Audio.loop_set("flagship_charge", 0.8 + k * 0.7)
			if st_time >= ramp:
				_enter(St.VULNERABLE)
				combat.on_flagship_vulnerable(self)
		St.VULNERABLE:
			_set_brightness(0.96 + 0.04 * sin(t * TAU * 1.5))   # fotosicher: ruhiges Pulsieren (vorher 4,8 Hz)
			_ensure_charge_sound(0.1)
			# [Vorgabe 0.14.4] ab Normal kein eigenes Tonsignal fürs Fenster (Tonhöhe bleibt oben, ohne Vibrato)
			Audio.loop_set("flagship_charge", (1.55 + 0.05 * sin(t * 20.0)) if Config.combat_intel else 1.5)
			if st_time >= Config.flagship_vulnerable_time:
				if _retreat_armed:
					# [FREI] kein Abschiedsschuss nach dem Schwadronsieg: das Fenster war die letzte Chance
					_retreat()
					return
				_fire()
				_enter(St.COOLDOWN)
		St.RETREAT:
			_set_brightness(0.0)
	# Rückzug nach Ablauf – fällt das Ende ins verwundbare Fenster, wird dieses noch abgewartet
	if _retreat_armed and st != St.RETREAT:
		retreat_timer -= delta
		if retreat_timer <= 0.0 and st != St.VULNERABLE:
			_retreat()


## Ladeton (Loop) sicherstellen – z. B. nach dem Schließen der Karte, aber nicht beim eigenen Tod.
func _ensure_charge_sound(fade: float) -> void:
	if not Audio.has_loop("flagship_charge") and not combat.dying and not combat.frozen:
		Audio.loop_start("flagship_charge", "flagship_charge_loop", -6.0, fade)


func _enter(s: St) -> void:
	st = s
	st_time = 0.0


func _fire() -> void:
	Audio.loop_stop("flagship_charge", 0.1)
	Audio.sfx("flagship_fire", 2.0)
	var from := weak_point_pos() + (combat.camera.global_position - weak_point_pos()).normalized() * 6.0
	combat.shots.fire_enemy(ShotSystem.Kind.E_FLAGSHIP, from, Config.flagship_damage, Config.flagship_hit_chance, Config.flagship_shot_speed, self)
	combat.on_heavy_shot_fired(self)
	Effects.flash(combat.fx_root, from, UITheme.PINK, 40.0, 0.6)


func start_retreat_timer() -> void:
	if not _retreat_armed:
		_retreat_armed = true
		retreat_timer = Config.flagship_retreat_delay


func _retreat() -> void:
	_enter(St.RETREAT)
	Audio.loop_stop("flagship_charge", 0.3)
	Effects.warp_in(combat.fx_root, global_position, 50.0, Color(0.8, 0.4, 1.0))
	Audio.sfx_3d("warp_in", combat, global_position, 6.0, 0.0, 0, 200.0)
	alive = false
	combat.on_flagship_retreated(self)
	queue_free()


## Treffertest: zuerst das rosa Quadrat, dann der Rumpf (lokale Bounding-Box).
func segment_hit(p0: Vector3, p1: Vector3, tolerance: float) -> Dictionary:
	var wp := weak_point_pos()
	if ShotSystem._seg_sphere(p0, p1, wp, Config.flagship_weakpoint_radius + tolerance * 0.5):
		return {"point": ShotSystem.seg_closest(p0, p1, wp), "part": "weak"}
	var inv := global_transform.affine_inverse()
	var a := inv * p0
	var b := inv * p1
	var box := _local_aabb.grow(tolerance)
	if box.intersects_segment(a, b):
		# Das Quadrat sitzt knapp hinter der Vorderkante der Box: Führt die Bahn noch hindurch, zählt der Schuss
		# dafür. Sonst hinge der Treffer vom Bildtakt ab (kurze Segmente bei hoher Bildrate prallen am Rumpf ab).
		var wr := Config.flagship_weakpoint_radius + tolerance * 0.5
		var ahead := p1 + (p1 - p0).normalized() * (2.0 * wr + 8.0)
		if ShotSystem._seg_sphere(p0, ahead, wp, wr):
			return {"point": ShotSystem.seg_closest(p0, ahead, wp), "part": "weak"}
		var mid := ShotSystem.seg_closest(p0, p1, global_position)
		return {"point": mid, "part": "hull"}
	return {}


func on_laser_hit(res: Dictionary) -> void:
	var p: Vector3 = res.get("point", global_position)
	Effects.sparks(combat.fx_root, Vector3.ZERO, Color(0.9, 0.7, 1.0), 8, 10.0, 0.2, 0.3).global_position = p
	Audio.sfx_3d("laser_deflect", combat, p, -6.0, 0.15)


func on_ion_hit(res: Dictionary) -> void:
	if not alive:
		return
	var p: Vector3 = res.get("point", global_position)
	if res.get("part", "") == "weak" and is_vulnerable():
		_destroy()
		return
	# kein Schaden – Ionen-Kugel verpufft am Rumpf
	Effects.flash(combat.fx_root, p, Color(0.8, 0.7, 1.0), 14.0, 0.4)
	Effects.sparks(combat.fx_root, Vector3.ZERO, Color(0.9, 0.8, 1.0), 30, 22.0, 0.3, 0.6).global_position = p
	Audio.sfx_3d("shield_hit", combat, p, 0.0)
	combat.on_flagship_immune(self, res.get("part", "") == "weak")


func _destroy() -> void:
	alive = false
	Audio.loop_stop("flagship_charge", 0.1)
	var c := global_position
	Effects.explosion(combat.fx_root, weak_point_pos(), 30.0, Color(1.0, 0.5, 0.9))
	for i in 5:
		var off := Vector3(randf_range(-1, 1), randf_range(-0.5, 0.5), randf_range(-1, 1)) * _local_aabb.size * 0.4
		var at := c + global_transform.basis * off
		var tw := combat.create_tween()
		tw.tween_interval(0.25 + i * 0.22)
		tw.tween_callback(func(): Effects.explosion(combat.fx_root, at, randf_range(22.0, 34.0), Color(1.0, 0.55, 0.3)))
	Audio.sfx("explosion_huge", 3.0)
	combat.on_enemy_destroyed(self)
	# Wrack bleibt kurz sichtbar und zerfällt
	var tw2 := create_tween()
	tw2.tween_property(model, "scale", Vector3.ONE * 0.85, 1.4)
	tw2.tween_callback(queue_free)
