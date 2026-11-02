class_name PlanetCombat
extends CombatBase
## =============================================================================================
##  Planetenkampf [ORIGINAL]: Cockpit mit Planetenoberfläche, Städte perspektivisch, feste Flughöhe,
##  Steuerung links/rechts (drehen) und vorwärts/rückwärts, Scanner mit eigenem Schiff und Städten.
##  Zerstörer bombardieren Städte (unbeweglich), können abbrechen und sich dem Spieler zuwenden.
##  Planet vorläufig gerettet, wenn alle Zerstörer auf ihm vernichtet sind.
## =============================================================================================

var planet: PlanetData
var squadron: SquadronData = null
var look: Dictionary
var yaw := 0.0
var turn_rate := 0.0
var speed := 0.0
var pos := Vector2.ZERO
var city_nodes: Array = []
var city_fx: Dictionary = {}       ## idx -> {root, light, fire}
var city_beacons: Array = []
var wave := 0
var wave_timer := -1.0
var _boundary_warn := 0.0
var _bob := 0.0
var _city_models := {}


static func create(p: PlanetData) -> PlanetCombat:
	var c := PlanetCombat.new()
	c.planet = p
	return c


func _ready() -> void:
	look = PlanetLook.surface(planet.type)
	if planet.landed_squadron != -1:
		squadron = GameState.squadron_by_id(planet.landed_squadron)
	super._ready()
	location_name = planet.name.to_upper() + " · OBERFLÄCHE"
	GameState.city_destroyed.connect(_on_city_destroyed)
	GameState.planet_saved.connect(_on_planet_saved)
	GameState.squadron_destroyed.connect(_on_squadron_destroyed)
	GameState.squadron_landed.connect(_on_squadron_landed)
	_place_player()
	_update_camera(0.0)
	if squadron:
		_begin_attack(false)
	else:
		location_sub = "Keine Feindaktivität · %d Städte" % planet.alive_cities()
		hint_text = "STEUERN: links/rechts drehen · rauf/runter vor/zurück  ·  LEERTASTE: Karte"
		hud.show_message(planet.name.to_upper(), "Keine Feindaktivität", 2.5, UITheme.CYAN)


func music_track() -> String:
	return "combat_planet" if squadron and squadron.state != SquadronData.State.DESTROYED else "map_theme"


# =============================================================================================
#  Welt
# =============================================================================================
func _build_world() -> void:
	var sky := ShaderMaterial.new()
	sky.shader = load("res://shaders/planet_sky.gdshader")
	sky.set_shader_parameter("top_color", look.sky_top)
	sky.set_shader_parameter("horizon_color", look.sky_horizon)
	sky.set_shader_parameter("ground_color", (look.fog as Color).darkened(0.3))
	sky.set_shader_parameter("star_amount", look.stars)
	sky.set_shader_parameter("sun_intensity", 1.0)
	# großer Nachbarplanet am Himmel
	var moon_tex := Assets.tex("planets/gas_giant.png")
	if moon_tex:
		sky.set_shader_parameter("moon_tex", moon_tex)
		sky.set_shader_parameter("has_moon", true)
		var rng := RandomNumberGenerator.new()
		rng.seed = planet.seed
		var a := rng.randf() * TAU
		sky.set_shader_parameter("moon_dir", Vector3(cos(a), rng.randf_range(0.18, 0.4), sin(a)).normalized())
		sky.set_shader_parameter("moon_radius", rng.randf_range(0.08, 0.16))
	make_environment(sky, (look.sky_horizon as Color).lerp(look.sky_top, 0.5), 0.55)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.6
	env.fog_enabled = true
	env.fog_light_color = look.fog
	env.fog_light_energy = 1.0
	env.fog_density = 0.00055
	env.fog_sky_affect = 0.0
	env.fog_aerial_perspective = 0.35
	env.glow_hdr_threshold = 1.15
	env.ssao_enabled = Settings.ssao_enabled()
	env.ssao_radius = 2.0
	env.ssao_intensity = 1.5
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = planet.seed + 3
	var sa := rng2.randf() * TAU
	make_sun(Vector3(cos(sa), rng2.randf_range(0.35, 0.6), sin(sa)), look.sun, 1.5, Settings.shadows_enabled())
	_build_ground()
	_build_mountains()
	_build_cities()
	_build_rocks()
	_build_dust()


func _build_ground() -> void:
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(8000, 8000)
	g.mesh = pm
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/ground.gdshader")
	m.set_shader_parameter("ground_a", look.ground_a)
	m.set_shader_parameter("ground_b", look.ground_b)
	m.set_shader_parameter("grid_color", look.grid)
	m.set_shader_parameter("noise_tex", Effects.noise_texture())
	m.set_shader_parameter("lava", look.lava)
	m.set_shader_parameter("water", look.water * 0.5)
	g.material_override = m
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(g)


func _build_mountains() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 320
	var radius := 3000.0
	var fn := FastNoiseLite.new()
	fn.seed = planet.seed
	fn.frequency = 0.9
	fn.fractal_octaves = 5
	var col: Color = (look.ground_b as Color).darkened(0.35)
	var ridge: Array = []
	for i in n + 1:
		var a := TAU * i / n
		var h := 70.0 + 260.0 * clampf(fn.get_noise_2d(cos(a) * 3.0, sin(a) * 3.0) * 0.5 + 0.55, 0.0, 1.3)
		h += 90.0 * absf(sin(a * 7.0 + planet.seed % 7))
		ridge.append(h)
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var p0 := Vector3(cos(a0) * radius, -20.0, sin(a0) * radius)
		var p1 := Vector3(cos(a1) * radius, -20.0, sin(a1) * radius)
		var q0 := Vector3(cos(a0) * radius * 0.97, ridge[i], sin(a0) * radius * 0.97)
		var q1 := Vector3(cos(a1) * radius * 0.97, ridge[i + 1], sin(a1) * radius * 0.97)
		for v in [[p0, q0, p1], [p1, q0, q1]]:
			var nrm: Vector3 = ((v[1] - v[0]).cross(v[2] - v[0])).normalized()
			if nrm.dot(-v[0]) < 0.0:
				nrm = -nrm
			for p in v:
				st.set_normal(nrm)
				st.set_color(col)
				st.add_vertex(p)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _city_model_name(i: int) -> String:
	return ["city_a", "city_b", "city_c"][int(planet.city_variant[i]) % 3]


func _build_cities() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = planet.seed + 11
	for i in planet.cities.size():
		var root := Node3D.new()
		add_child(root)
		var cp: Vector2 = planet.city_pos[i]
		root.position = Vector3(cp.x, 0.0, cp.y)
		root.rotation.y = rng.randf() * TAU
		city_nodes.append(root)
		_set_city_model(i, planet.cities[i])


func _set_city_model(i: int, alive: bool) -> void:
	var root: Node3D = city_nodes[i]
	for c in root.get_children():
		c.queue_free()
	var m := Assets.model(_city_model_name(i) if alive else "city_ruins")
	root.add_child(m)
	if alive:
		var b := Assets.find_node_named(m, "Beacon")
		if b:
			var g := Assets.glow_sprite(Color(1.0, 0.3, 0.25), 5.0, 4.0)
			b.add_child(g)
			city_beacons.append(g)
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.8, 0.55)
		l.light_energy = 1.2
		l.omni_range = 45.0
		l.position = Vector3(0, 12, 0)
		root.add_child(l)
	else:
		_add_smoke(root, 0.5)


func _add_smoke(root: Node3D, intensity: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = int(10 + 22 * intensity)
	p.lifetime = 6.0
	p.preprocess = 3.0
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-60, -10, -60), Vector3(120, 200, 120))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 10.0
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 15.0
	pm.initial_velocity_min = 4.0
	pm.initial_velocity_max = 9.0
	pm.gravity = Vector3(1.5, 0.8, 0.5)
	pm.scale_min = 8.0
	pm.scale_max = 16.0
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.4))
	sc.add_point(Vector2(1, 1.6))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var g := Gradient.new()
	g.set_color(0, Color(0.25, 0.2, 0.18, 0.0))
	g.add_point(0.12, Color(0.2, 0.17, 0.15, 0.6 * intensity + 0.2))
	g.set_color(1, Color(0.1, 0.1, 0.1, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var st := Assets.tex("fx/smoke_puff.png")
	m.albedo_texture = st if st else FallbackModels.radial_texture()
	var q := QuadMesh.new()
	q.material = m
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(p)
	p.position = Vector3(0, 6, 0)
	return p


func _build_rocks() -> void:
	var meshes := Assets.model_meshes("rocks")
	if meshes.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = planet.seed + 5
	var per := int(90 * Settings.particle_scale())
	for mesh in meshes:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = per
		for i in per:
			var p := Vector2.ZERO
			for tries in 10:
				var a := rng.randf() * TAU
				var r := sqrt(rng.randf()) * 2200.0
				p = Vector2(cos(a), sin(a)) * r
				var ok := true
				for c in planet.city_pos:
					if c.distance_to(p) < 45.0:
						ok = false
						break
				if ok:
					break
			var s := rng.randf_range(0.6, 2.4)
			var b := Basis().rotated(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.7, 1.4), s))
			mm.set_instance_transform(i, Transform3D(b, Vector3(p.x, -0.2, p.y)))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		var rm := StandardMaterial3D.new()
		rm.albedo_color = (look.ground_b as Color).lerp(Color(0.4, 0.38, 0.36), 0.4)
		rm.roughness = 0.95
		mmi.material_override = rm
		add_child(mmi)


func _build_dust() -> void:
	var p := GPUParticles3D.new()
	p.amount = int(200 * Settings.particle_scale())
	p.lifetime = 6.0
	p.preprocess = 6.0
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-200, -60, -200), Vector3(400, 120, 400))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(160, 25, 160)
	pm.gravity = Vector3(2.0, 0.0, 1.0)
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 1.0
	pm.scale_min = 0.12
	pm.scale_max = 0.3
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.add_point(0.3, Color(1, 1, 1, 0.5))
	g.set_color(1, Color(1, 1, 1, 0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_color = Color((look.fog as Color).lightened(0.4), 1.0)
	m.albedo_texture = Assets.tex("fx/glow.png") if Assets.tex("fx/glow.png") else FallbackModels.radial_texture()
	var q := QuadMesh.new()
	q.material = m
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	camera.add_child(p)


# =============================================================================================
#  Spieler
# =============================================================================================
func _place_player() -> void:
	var target := Vector2.ZERO
	if squadron and squadron.group_city >= 0 and squadron.group_city < planet.city_pos.size():
		target = planet.city_pos[squadron.group_city]
	var a := randf() * TAU
	pos = target + Vector2(cos(a), sin(a)) * 330.0
	if pos.length() > Config.planet_area_radius:
		pos = pos.normalized() * Config.planet_area_radius * 0.9
	var d := target - pos
	yaw = atan2(-d.x, -d.y)


func player_xz() -> Vector2:
	return pos


func _update_controls(delta: float) -> void:
	var inp := steer_input()
	if Settings.invert_y:
		inp.y = -inp.y   # auf Planeten: rauf = vorwärts, unabhängig von der Y-Invertierung
	var tr := deg_to_rad(Config.planet_turn_rate)
	var k := 1.0 - exp(-7.0 * delta)
	turn_rate = lerpf(turn_rate, -inp.x * tr, k)
	yaw += turn_rate * delta
	var target_speed := inp.y * (Config.planet_speed_forward if inp.y > 0.0 else Config.planet_speed_backward)
	speed = lerpf(speed, target_speed, 1.0 - exp(-Config.planet_response * delta))
	var fwd := Vector2(-sin(yaw), -cos(yaw))
	pos += fwd * speed * delta
	var lim := Config.planet_area_radius
	if pos.length() > lim:
		pos = pos.normalized() * lim
		_boundary_warn -= delta
		if _boundary_warn <= 0.0:
			_boundary_warn = 3.0
			hud.show_message("GRENZE DES EINSATZGEBIETS", "Wende, um zurückzufliegen", 1.5, UITheme.AMBER, true)
	turn_norm = maxf(absf(turn_rate) / tr, absf(speed) / Config.planet_speed_forward * 0.9)
	_update_camera(delta)


func _update_camera(delta: float) -> void:
	_bob += delta
	var alt := Config.planet_altitude + sin(_bob * 1.1) * 0.25
	camera.position = Vector3(pos.x, alt, pos.y)
	camera.rotation = Vector3(0.0, yaw, -turn_rate * 0.06)


func _process(delta: float) -> void:
	super._process(delta)
	if dying:
		return
	for i in city_beacons.size():
		if is_instance_valid(city_beacons[i]):
			city_beacons[i].visible = fmod(Time.get_ticks_msec() / 1000.0 + i * 0.37, 1.6) < 0.2
	_update_city_fx(delta)
	if squadron and squadron.state != SquadronData.State.DESTROYED:
		_update_waves(delta)
	_update_bombard_audio()


# =============================================================================================
#  Angriff / Wellen
# =============================================================================================
func _begin_attack(landing_now: bool) -> void:
	location_sub = "WIRD ANGEGRIFFEN!"
	hint_text = "Scanner: blinkende Stadt = Bombardement  ·  LEERTASTE: Karte"
	for dd in squadron.destroyers:
		var d := Destroyer.new()
		d.data = dd
		d.planet_mode = true
		d.setup(self, squadron)
		var start := city_world_pos(dd.city) + Vector3(0, Config.planet_destroyer_altitude, 0) if dd.city >= 0 else Vector3(0, 60, 0)
		add_enemy(d, start)
	wave_timer = 2.0
	var sub := "%d Zerstörer bombardieren die Städte" % squadron.destroyers.size()
	if landing_now:
		hud.show_message("FEINDLICHE LANDUNG!", sub, 3.0, UITheme.RED)
		Audio.alarm(-4.0)
	else:
		hud.show_message(planet.name.to_upper() + " WIRD ANGEGRIFFEN", sub, 3.0, UITheme.RED)
	Audio.play_music("combat_planet", 1.5)


func _on_squadron_landed(sq: SquadronData, p: PlanetData) -> void:
	if p != planet or squadron != null:
		return
	squadron = sq
	_begin_attack(true)


func _fighters_alive() -> int:
	var n := 0
	for e in enemies:
		if is_instance_valid(e) and e.alive and e.kind == Enemy.Kind.FIGHTER:
			n += 1
	return n


func _update_waves(delta: float) -> void:
	if _fighters_alive() > 0:
		return
	var left := squadron.fighters
	if left <= 0:
		return
	if wave_timer < 0.0:
		wave_timer = Config.wave_delay + 1.5
	wave_timer -= delta
	if wave_timer > 0.0:
		return
	wave_timer = -1.0
	wave += 1
	var n := mini(Config.fighters_per_wave, left)
	var cb := camera.global_transform.basis
	for i in n:
		var f := Fighter.new()
		f.planet_mode = true
		f.setup(self, squadron)
		var local := Vector3(randf_range(-70, 70), 0, -randf_range(180, 240))
		var wp := camera.global_position + cb * local
		wp.y = Config.planet_altitude + randf_range(0, 6)
		add_enemy(f, wp)
	Audio.sfx("wave_incoming", -2.0)
	hud.show_message("FIGHTER IM ANFLUG", "%d Fighter · Welle %d" % [n, wave], 1.6, UITheme.FIGHTER_COLOR, true)


func _on_enemy_removed(e: Enemy) -> void:
	if e.kind == Enemy.Kind.FIGHTER:
		GameState.on_fighter_killed(squadron)


func on_destroyer_engages(d: Destroyer) -> void:
	hud.show_message("ZERSTÖRER BRICHT BOMBARDEMENT AB", "Er wendet sich dir zu!", 1.8, d.hud_color, true)


func _on_planet_saved(p: PlanetData) -> void:
	if p != planet:
		return
	hud.show_message("PLANET GERETTET!", "%d Städte gehalten · +%d Bonus" % [p.alive_cities(), Config.bonus_city_saved * p.alive_cities()], 4.0, UITheme.GREEN)
	Audio.sfx("planet_saved")
	location_sub = "Vorerst gerettet"


func _on_squadron_destroyed(sq: SquadronData) -> void:
	if sq != squadron:
		return
	hud.show_message("SCHWADRON VERNICHTET", "+%d Bonus · LEERTASTE: Karte" % Config.bonus_squadron_destroyed, 3.5, UITheme.GREEN)
	Audio.sfx("squadron_destroyed")
	location_sub = "Feind vernichtet · %d Städte" % planet.alive_cities()
	hint_text = "LEERTASTE: Systemkarte"
	squadron = null
	Audio.play_music("map_theme", 3.0)


# =============================================================================================
#  Städte (Schnittstelle für Zerstörer)
# =============================================================================================
func city_world_pos(idx: int) -> Vector3:
	if idx < 0 or idx >= planet.city_pos.size():
		return Vector3.ZERO
	var p: Vector2 = planet.city_pos[idx]
	return Vector3(p.x, 0.0, p.y)


func city_alive(idx: int) -> bool:
	return idx >= 0 and idx < planet.cities.size() and planet.cities[idx]


func next_city_for(d: Destroyer) -> int:
	if squadron == null:
		return -1
	return GameState.next_city_for(squadron, planet, d.data)


func city_under_attack(idx: int) -> bool:
	for e in enemies:
		if e is Destroyer and is_instance_valid(e) and e.alive and e.is_bombarding() and e.data.city == idx:
			return true
	return false


func on_city_bombarded(idx: int, progress: float) -> void:
	if not city_fx.has(idx):
		var root: Node3D = city_nodes[idx]
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.4, 0.15)
		l.omni_range = 70.0
		root.add_child(l)
		l.position = Vector3(0, 8, 0)
		var smoke := _add_smoke(root, 0.4)
		city_fx[idx] = {"light": l, "smoke": smoke, "p": 0.0, "t": 0.0}
	city_fx[idx].p = progress
	city_fx[idx].t = 0.0


func _update_city_fx(delta: float) -> void:
	for idx in city_fx.keys():
		var fx: Dictionary = city_fx[idx]
		fx.t += delta
		var l: OmniLight3D = fx.light
		if is_instance_valid(l):
			var active: bool = fx.t < 0.3
			l.light_energy = (2.0 + 6.0 * fx.p) * (0.6 + 0.4 * sin(Time.get_ticks_msec() / 60.0)) if active else maxf(l.light_energy - delta * 4.0, 0.0)
		if fx.t < 0.3 and randf() < delta * (2.0 + 6.0 * fx.p):
			var root: Node3D = city_nodes[idx]
			var off := Vector3(randf_range(-14, 14), randf_range(2, 14), randf_range(-14, 14))
			Effects.flash(fx_root, root.global_position + off, Color(1.0, 0.55, 0.2), randf_range(6, 14), 0.25)


func _update_bombard_audio() -> void:
	var any := false
	var nearest := INF
	for e in enemies:
		if e is Destroyer and is_instance_valid(e) and e.alive and e.is_bombarding():
			any = true
			nearest = minf(nearest, e.distance_to_player())
	if any:
		var vol := clampf(-4.0 - nearest / 40.0, -24.0, -4.0)
		if not Audio.has_loop("bombard"):
			Audio.loop_start("bombard", "bombard_loop", vol, 0.6)
		else:
			Audio.loop_set("bombard", -1.0, vol)
	elif Audio.has_loop("bombard"):
		Audio.loop_stop("bombard", 0.6)


func destroy_city(idx: int) -> void:
	GameState.destroy_city(planet, idx)


func _on_city_destroyed(p: PlanetData, idx: int) -> void:
	if p != planet:
		return
	var root: Node3D = city_nodes[idx]
	Effects.explosion(fx_root, root.global_position + Vector3(0, 8, 0), 26.0, Color(1.0, 0.5, 0.2))
	Effects.explosion(fx_root, root.global_position + Vector3(8, 4, -6), 18.0, Color(1.0, 0.45, 0.15), false)
	Audio.sfx_3d("city_destroyed", self, root.global_position, 8.0, 0.0, 0, 300.0)
	Audio.sfx("city_destroyed", -6.0)
	shake = maxf(shake, 0.6)
	if city_fx.has(idx):
		city_fx.erase(idx)
	_set_city_model(idx, false)
	hud.show_message("STADT %s ZERSTÖRT" % p.city_names[idx].to_upper(), "%d Städte übrig" % p.alive_cities(), 2.4, UITheme.RED)


func _on_unfrozen() -> void:
	if squadron and squadron.state == SquadronData.State.DESTROYED:
		squadron = null


func debug_kill_all() -> void:
	for e in enemies.duplicate():
		if is_instance_valid(e) and e.alive:
			if e.kind == Enemy.Kind.FIGHTER:
				e.on_laser_hit({})
			elif e.kind == Enemy.Kind.DESTROYER:
				while e.alive:
					e.on_ion_hit({"point": e.global_position})
