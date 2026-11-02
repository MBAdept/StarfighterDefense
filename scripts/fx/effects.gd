class_name Effects
extends RefCounted
## Visuelle Effekte: Explosionen, Funken, Lichtblitze, Schockwellen, Trümmer, Warp-Einflug.

static var _flipbook_shader: Shader
static var _fireball_shader: Shader
static var _noise: Texture2D
static var _spark_mat: StandardMaterial3D
static var _smoke_mat: StandardMaterial3D
static var _debris_meshes: Array = []


static func _flip_shader() -> Shader:
	if _flipbook_shader == null:
		_flipbook_shader = load("res://shaders/flipbook.gdshader")
	return _flipbook_shader


static func noise_texture() -> Texture2D:
	if _noise:
		return _noise
	var t := Assets.tex("fx/noise.png")
	if t == null:
		var nt := NoiseTexture2D.new()
		nt.width = 256
		nt.height = 256
		nt.seamless = true
		var fn := FastNoiseLite.new()
		fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		fn.frequency = 0.02
		fn.fractal_octaves = 4
		nt.noise = fn
		t = nt
	_noise = t
	return t


static func _auto_free(node: Node, seconds: float) -> void:
	if not node.is_inside_tree():
		return
	# Verbindung auf eine Methode des Knotens: wird beim Freigeben automatisch getrennt
	node.get_tree().create_timer(seconds, false).timeout.connect(node.queue_free)


## Große Explosion: Feuerball (Flipbook), Licht, Funken, Schockwelle, Trümmer, Rauch.
static func explosion(parent: Node3D, pos: Vector3, size: float, color := Color(1.0, 0.55, 0.22), with_debris := true) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = pos
	var atlas := Assets.tex("fx/explosion_flipbook.png")
	var dur := 1.3 + size * 0.04
	# Feuerbälle
	var balls := 1 if size < 8.0 else 3
	for i in balls:
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2.ONE
		q.mesh = qm
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var s := size * (1.6 if i == 0 else randf_range(0.8, 1.2))
		var off := Vector3.ZERO if i == 0 else Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * size * 0.4
		root.add_child(q)
		q.position = off
		if atlas:
			var m := ShaderMaterial.new()
			m.shader = _flip_shader()
			m.set_shader_parameter("atlas", atlas)
			q.material_override = m
			q.set_instance_shader_parameter("spin", randf() * TAU)
			q.set_instance_shader_parameter("frame", 0.0)
			q.scale = Vector3.ONE * s
			var tw := q.create_tween()
			tw.tween_interval(i * 0.12)
			tw.tween_method(func(v): q.set_instance_shader_parameter("frame", v), 0.0, 63.0, dur * (1.0 + i * 0.2))
		else:
			if _fireball_shader == null:
				_fireball_shader = load("res://shaders/fireball.gdshader")
			var m2 := ShaderMaterial.new()
			m2.shader = _fireball_shader
			m2.set_shader_parameter("noise_tex", noise_texture())
			q.material_override = m2
			q.set_instance_shader_parameter("seed", randf())
			q.set_instance_shader_parameter("tint", color)
			q.scale = Vector3.ONE * s * 0.3
			var tw2 := q.create_tween().set_parallel(true)
			tw2.tween_method(func(v): q.set_instance_shader_parameter("age", v), 0.0, 1.0, dur)
			tw2.tween_property(q, "scale", Vector3.ONE * s * 1.3, dur).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	# Kernblitz
	var core := Assets.glow_sprite(Color(1.0, 0.85, 0.6), size * 1.1, 2.6)
	root.add_child(core)
	var ct := core.create_tween()
	ct.tween_property(core, "scale", Vector3.ONE * 1.2, 0.06)
	ct.tween_property(core, "scale", Vector3.ONE * 0.01, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# Licht
	var light := OmniLight3D.new()
	light.light_color = color.lightened(0.2)
	light.light_energy = 6.0 + size * 0.4
	light.omni_range = size * 9.0 + 20.0
	light.shadow_enabled = false
	root.add_child(light)
	var lt := light.create_tween()
	lt.tween_property(light, "light_energy", 0.0, 0.6 + size * 0.02).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	# Funken
	sparks(root, Vector3.ZERO, color.lightened(0.4), int(clampf(size * 6.0, 18.0, 90.0)), 12.0 + size * 3.0, 0.18 + size * 0.02, 0.9)
	# Schockwelle
	shockwave(root, size * 3.2, color.lightened(0.3), 0.55)
	# Rauch
	if size >= 7.0:
		smoke(root, size)
	# Trümmer
	if with_debris:
		debris(root, size)
	_auto_free(root, 4.5)


static func sparks(parent: Node3D, local_pos: Vector3, color: Color, amount := 30, speed := 20.0, scale := 0.25, life := 0.8) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = maxi(int(amount * Settings.particle_scale()), 4)
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 1.0
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-80, -80, -80), Vector3(160, 160, 160))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 0, 1)
	pm.spread = 180.0
	pm.initial_velocity_min = speed * 0.35
	pm.initial_velocity_max = speed
	pm.gravity = Vector3.ZERO
	pm.damping_min = speed * 0.6
	pm.damping_max = speed * 1.2
	pm.scale_min = scale * 0.5
	pm.scale_max = scale * 1.6
	var sc := Curve.new()
	sc.add_point(Vector2(0, 1))
	sc.add_point(Vector2(1, 0))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(color.r, color.g * 0.6, color.b * 0.4, 0.0))
	g.add_point(0.25, color)
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	if _spark_mat == null:
		_spark_mat = StandardMaterial3D.new()
		_spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_spark_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_spark_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_spark_mat.vertex_color_use_as_albedo = true
		_spark_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_spark_mat.albedo_color = Color(4.0, 4.0, 4.0, 1.0)
		var st := Assets.tex("fx/glow.png")
		_spark_mat.albedo_texture = st if st else FallbackModels.radial_texture()
		_spark_mat.disable_fog = true
	var qm := QuadMesh.new()
	qm.size = Vector2.ONE
	qm.material = _spark_mat
	p.draw_pass_1 = qm
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	p.position = local_pos
	p.emitting = true
	_auto_free(p, life + 0.5)
	return p


static func smoke(parent: Node3D, size: float) -> void:
	var p := GPUParticles3D.new()
	p.amount = 14
	p.lifetime = 2.6
	p.one_shot = true
	p.explosiveness = 0.85
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-100, -100, -100), Vector3(200, 200, 200))
	var pm := ParticleProcessMaterial.new()
	pm.spread = 180.0
	pm.initial_velocity_min = size * 0.3
	pm.initial_velocity_max = size * 0.9
	pm.gravity = Vector3.ZERO
	pm.damping_min = size * 0.2
	pm.damping_max = size * 0.4
	pm.scale_min = size * 0.8
	pm.scale_max = size * 1.6
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.4))
	sc.add_point(Vector2(1, 1.3))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	var g := Gradient.new()
	g.set_color(0, Color(0.35, 0.3, 0.28, 0.0))
	g.set_color(1, Color(0.1, 0.1, 0.1, 0.0))
	g.add_point(0.15, Color(0.3, 0.27, 0.25, 0.55))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	if _smoke_mat == null:
		_smoke_mat = StandardMaterial3D.new()
		_smoke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_smoke_mat.vertex_color_use_as_albedo = true
		_smoke_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_smoke_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		var st := Assets.tex("fx/smoke_puff.png")
		_smoke_mat.albedo_texture = st if st else FallbackModels.radial_texture()
	var qm := QuadMesh.new()
	qm.material = _smoke_mat
	p.draw_pass_1 = qm
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	p.emitting = true


static func shockwave(parent: Node3D, size: float, color: Color, dur := 0.5) -> void:
	var t := Assets.tex("fx/shockwave.png")
	if t == null:
		return
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2.ONE
	mi.mesh = qm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = t
	m.albedo_color = Color(color.r * 3.0, color.g * 3.0, color.b * 3.0, 1.0)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.disable_fog = true
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.scale = Vector3.ONE * size * 0.15
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * size, dur).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


static func debris(parent: Node3D, size: float) -> void:
	if _debris_meshes.is_empty():
		_debris_meshes = Assets.model_meshes("debris")
	if _debris_meshes.is_empty():
		return
	var n := int(clampf(size * 0.6, 3, 9))
	for i in n:
		var mi := MeshInstance3D.new()
		mi.mesh = _debris_meshes[randi() % _debris_meshes.size()]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
		var s := size * randf_range(0.08, 0.2)
		mi.scale = Vector3.ONE * s
		mi.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		var dir := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
		var dist := size * randf_range(2.0, 5.0)
		var life := randf_range(1.6, 3.0)
		var tw := mi.create_tween().set_parallel(true)
		tw.tween_property(mi, "position", dir * dist, life).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(mi, "rotation", mi.rotation + Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6)), life)
		tw.tween_property(mi, "scale", Vector3.ONE * 0.001, life).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
		# glühende Kante
		var g := Assets.glow_sprite(Color(1.0, 0.5, 0.2), 4.0 / maxf(s, 0.01) * 0.3, 2.0)
		mi.add_child(g)


## Kleiner Lichtblitz/Glow an einer Position (Mündungsfeuer, Treffer …).
static func flash(parent: Node3D, pos: Vector3, color: Color, size: float, dur := 0.25, light := true) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var g := Assets.glow_sprite(color, size, 4.0)
	parent.add_child(g)
	g.global_position = pos
	var tw := g.create_tween()
	tw.tween_property(g, "scale", Vector3.ONE * 0.01, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(g.queue_free)
	if light:
		var l := OmniLight3D.new()
		l.light_color = color
		l.light_energy = 4.0
		l.omni_range = size * 4.0
		parent.add_child(l)
		l.global_position = pos
		var lt := l.create_tween()
		lt.tween_property(l, "light_energy", 0.0, dur)
		lt.tween_callback(l.queue_free)


## Einflug-Effekt (feindliches Schiff erscheint): Blitz + horizontale Lichtlinie + Ring.
static func warp_in(parent: Node3D, pos: Vector3, size: float, color: Color) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = pos
	var g := Assets.glow_sprite(color.lightened(0.5), size * 3.0, 5.0)
	root.add_child(g)
	g.scale = Vector3.ONE * 0.05
	var tw := g.create_tween()
	tw.tween_property(g, "scale", Vector3.ONE, 0.12).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(g, "scale", Vector3.ONE * 0.01, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	var streak := Assets.glow_sprite(color.lightened(0.3), size * 2.0, 5.0)
	root.add_child(streak)
	streak.scale = Vector3(6.0, 0.06, 1.0)
	var tw2 := streak.create_tween()
	tw2.tween_property(streak, "scale", Vector3(0.1, 0.02, 1.0), 0.55).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	shockwave(root, size * 2.5, color, 0.6)
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = 5.0
	l.omni_range = size * 6.0
	root.add_child(l)
	var lt := l.create_tween()
	lt.tween_property(l, "light_energy", 0.0, 0.7)
	_auto_free(root, 1.5)
