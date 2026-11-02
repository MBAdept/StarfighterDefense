class_name FallbackModels
extends RefCounted
## Einfache Ersatzmodelle, falls ein Blender-Modell (noch) fehlt. Gleiche Konventionen wie die
## echten Modelle: Front zeigt nach -Z, Materialnamen wie in tools/ASSET_SPEC.md.

static var _radial: Texture2D


static func build(model_name: String) -> Node3D:
	match model_name:
		"fighter":
			return _fighter()
		"destroyer":
			return _destroyer()
		"flagship":
			return _flagship()
		"station":
			return _station()
		"city_a", "city_b", "city_c":
			return _city(model_name)
		"city_ruins":
			return _ruins()
		"rocks":
			return _rocks()
		"debris":
			return _debris()
	var r := Node3D.new()
	r.add_child(_part(BoxMesh.new(), _mat("Hull", Color.MAGENTA), Vector3.ZERO, "Box"))
	return r


static func _mat(mat_name: String, color: Color, emission := 0.0, metallic := 0.6, rough := 0.45) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = mat_name
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = rough
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	m.rim_enabled = true
	m.rim = 0.3
	return m


static func _part(mesh: Mesh, mat: Material, pos: Vector3, part_name: String, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = part_name
	mi.mesh = mesh
	mesh.surface_set_material(0, mat)
	mi.position = pos
	mi.rotation_degrees = rot
	mi.scale = scl
	return mi


static func _marker(parent: Node3D, marker_name: String, pos: Vector3) -> void:
	var n := Node3D.new()
	n.name = marker_name
	n.position = pos
	parent.add_child(n)


static func _fighter() -> Node3D:
	var r := Node3D.new()
	var hull := _mat("Hull", Color(0.22, 0.23, 0.27))
	var accent := _mat("Accent", Color(1.0, 0.35, 0.1), 3.0)
	var glow := _mat("Glow", Color(1.0, 0.6, 0.2), 6.0)
	var body := PrismMesh.new()
	body.size = Vector3(1.6, 7.0, 1.0)
	r.add_child(_part(body, hull, Vector3.ZERO, "Body", Vector3(-90, 0, 0)))
	var wing := BoxMesh.new()
	wing.size = Vector3(6.2, 0.18, 2.2)
	r.add_child(_part(wing, hull, Vector3(0, 0, 1.2), "Wings"))
	var stripe := BoxMesh.new()
	stripe.size = Vector3(6.3, 0.2, 0.35)
	r.add_child(_part(stripe, accent, Vector3(0, 0.02, 0.4), "Stripe"))
	for s in [-1, 1]:
		var eng := CylinderMesh.new()
		eng.top_radius = 0.35
		eng.bottom_radius = 0.35
		eng.height = 0.4
		r.add_child(_part(eng, glow, Vector3(0.7 * s, 0, 3.3), "Nozzle", Vector3(90, 0, 0)))
	_marker(r, "Engine_L", Vector3(-0.7, 0, 3.5))
	_marker(r, "Engine_R", Vector3(0.7, 0, 3.5))
	_marker(r, "Gun_L", Vector3(-1.2, 0, -2.0))
	_marker(r, "Gun_R", Vector3(1.2, 0, -2.0))
	return r


static func _destroyer() -> Node3D:
	var r := Node3D.new()
	var hull := _mat("Hull", Color(0.25, 0.26, 0.3))
	var dark := _mat("HullDark", Color(0.12, 0.12, 0.15))
	var accent := _mat("Accent", Color(0.9, 0.9, 0.95), 3.0)
	var glow := _mat("Glow", Color(0.6, 0.8, 1.0), 6.0)
	var body := BoxMesh.new()
	body.size = Vector3(9.0, 4.5, 22.0)
	r.add_child(_part(body, hull, Vector3.ZERO, "Body"))
	var head := PrismMesh.new()
	head.size = Vector3(14.0, 5.0, 3.0)
	r.add_child(_part(head, dark, Vector3(0, 0, -10.5), "Head", Vector3(-90, 0, 0)))
	var band := BoxMesh.new()
	band.size = Vector3(9.4, 0.7, 14.0)
	r.add_child(_part(band, accent, Vector3(0, 1.0, 1.0), "Band"))
	for s in [-1, 1]:
		var eng := CylinderMesh.new()
		eng.top_radius = 1.1
		eng.bottom_radius = 1.4
		eng.height = 1.0
		r.add_child(_part(eng, glow, Vector3(2.8 * s, 0, 11.2), "Nozzle", Vector3(90, 0, 0)))
	_marker(r, "Engine_1", Vector3(-2.8, 0, 11.6))
	_marker(r, "Engine_2", Vector3(2.8, 0, 11.6))
	_marker(r, "Gun_Main", Vector3(0, -2.0, -11.0))
	_marker(r, "BombBay", Vector3(0, -2.4, 0))
	return r


static func _flagship() -> Node3D:
	var r := Node3D.new()
	var hull := _mat("Hull", Color(0.2, 0.18, 0.24))
	var dark := _mat("HullDark", Color(0.1, 0.09, 0.12))
	var accent := _mat("Accent", Color(0.55, 0.2, 0.9), 2.5)
	var body := BoxMesh.new()
	body.size = Vector3(70.0, 22.0, 90.0)
	r.add_child(_part(body, hull, Vector3.ZERO, "Body"))
	var front := BoxMesh.new()
	front.size = Vector3(40.0, 30.0, 8.0)
	r.add_child(_part(front, dark, Vector3(0, 0, -46.0), "Front"))
	var ribs := BoxMesh.new()
	ribs.size = Vector3(72.0, 2.0, 60.0)
	r.add_child(_part(ribs, accent, Vector3(0, 11.5, 5.0), "Ribs"))
	var wp := QuadMesh.new()
	wp.size = Vector2(7.0, 7.0)
	var wpm := _mat("WeakPoint", Color(1.0, 0.31, 0.82), 1.0, 0.0, 0.3)
	r.add_child(_part(wp, wpm, Vector3(0, 0, -50.05), "WeakPoint", Vector3(0, 180, 0)))
	_marker(r, "Gun_Main", Vector3(0, -6, -51))
	return r


static func _station() -> Node3D:
	var r := Node3D.new()
	var st := _mat("Structure", Color(0.8, 0.82, 0.86), 0.0, 0.5, 0.4)
	var win := _mat("Windows", Color(1.0, 0.85, 0.6), 4.0)
	var glow := _mat("Glow", Color(0.3, 0.9, 1.0), 5.0)
	var ring := TorusMesh.new()
	ring.inner_radius = 28.0
	ring.outer_radius = 34.0
	ring.rings = 48
	var ring_node := _part(ring, st, Vector3.ZERO, "Ring", Vector3(90, 0, 0))
	r.add_child(ring_node)
	var lights := TorusMesh.new()
	lights.inner_radius = 33.8
	lights.outer_radius = 34.4
	ring_node.add_child(_part(lights, win, Vector3.ZERO, "RingLights"))
	var hub := CylinderMesh.new()
	hub.top_radius = 7.0
	hub.bottom_radius = 7.0
	hub.height = 26.0
	r.add_child(_part(hub, st, Vector3.ZERO, "Hub", Vector3(90, 0, 0)))
	var port := CylinderMesh.new()
	port.top_radius = 3.0
	port.bottom_radius = 3.0
	port.height = 1.0
	r.add_child(_part(port, glow, Vector3(0, 0, -13.2), "DockLight", Vector3(90, 0, 0)))
	for i in 4:
		var a := TAU * i / 4.0
		var spoke := BoxMesh.new()
		spoke.size = Vector3(1.6, 26.0, 1.6)
		ring_node.add_child(_part(spoke, st, Vector3(cos(a) * 17.0, 0, sin(a) * 17.0), "Spoke", Vector3(0, 0, 90).rotated(Vector3.UP, a)))
		_marker(r, "Beacon_%d" % (i + 1), Vector3(cos(a) * 36.0, sin(a) * 36.0, 0))
	_marker(r, "DockPort", Vector3(0, 0, -14))
	return r


static func _city(model_name: String) -> Node3D:
	var r := Node3D.new()
	var st := _mat("Structure", Color(0.78, 0.8, 0.84), 0.0, 0.3, 0.5)
	var dome := _mat("Dome", Color(0.55, 0.8, 1.0), 0.6, 0.2, 0.1)
	var win := _mat("Windows", Color(1.0, 0.8, 0.45), 3.5)
	var seed_val := model_name.hash()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var base := CylinderMesh.new()
	base.top_radius = 19.0
	base.bottom_radius = 21.0
	base.height = 2.0
	r.add_child(_part(base, st, Vector3(0, 1.0, 0), "Base"))
	var d := SphereMesh.new()
	d.radius = 9.0
	d.height = 12.0
	r.add_child(_part(d, dome, Vector3(rng.randf_range(-5, 5), 2.0, rng.randf_range(-5, 5)), "Dome"))
	for i in 5:
		var tower := BoxMesh.new()
		var h := rng.randf_range(8.0, 24.0)
		tower.size = Vector3(3.5, h, 3.5)
		var a := rng.randf() * TAU
		var dist := rng.randf_range(9.0, 16.0)
		r.add_child(_part(tower, st, Vector3(cos(a) * dist, h * 0.5 + 2.0, sin(a) * dist), "Tower"))
		var w := BoxMesh.new()
		w.size = Vector3(3.6, h * 0.7, 0.6)
		r.add_child(_part(w, win, Vector3(cos(a) * dist, h * 0.5 + 2.0, sin(a) * dist), "Win"))
	_marker(r, "Beacon", Vector3(0, 26, 0))
	return r


static func _ruins() -> Node3D:
	var r := Node3D.new()
	var ch := _mat("Charred", Color(0.06, 0.05, 0.05), 0.0, 0.0, 0.9)
	var emb := _mat("Embers", Color(1.0, 0.35, 0.05), 2.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var base := CylinderMesh.new()
	base.top_radius = 18.0
	base.bottom_radius = 21.0
	base.height = 1.5
	r.add_child(_part(base, ch, Vector3(0, 0.75, 0), "Base"))
	for i in 9:
		var b := BoxMesh.new()
		var h := rng.randf_range(1.5, 7.0)
		b.size = Vector3(rng.randf_range(2, 5), h, rng.randf_range(2, 5))
		r.add_child(_part(b, ch if i % 3 else emb, Vector3(rng.randf_range(-14, 14), h * 0.4, rng.randf_range(-14, 14)), "Rubble", Vector3(rng.randf_range(-20, 20), rng.randf() * 90, rng.randf_range(-20, 20))))
	return r


static func _rocks() -> Node3D:
	var r := Node3D.new()
	var rock := _mat("Rock", Color(0.4, 0.37, 0.34), 0.0, 0.0, 0.95)
	for i in 5:
		var s := SphereMesh.new()
		s.radius = 2.0 + i
		s.height = (2.0 + i) * 1.3
		s.radial_segments = 7
		s.rings = 4
		r.add_child(_part(s, rock, Vector3(i * 12, 0, 0), "Rock_%d" % i))
	return r


static func _debris() -> Node3D:
	var r := Node3D.new()
	var hull := _mat("Hull", Color(0.25, 0.25, 0.28))
	for i in 4:
		var b := BoxMesh.new()
		b.size = Vector3(0.6 + i * 0.4, 0.2 + i * 0.1, 0.9 + i * 0.5)
		r.add_child(_part(b, hull, Vector3(i * 3, 0, 0), "Debris_%d" % i))
	return r


static func radial_texture() -> Texture2D:
	if _radial:
		return _radial
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.25, Color(1, 1, 1, 0.45))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 128
	t.height = 128
	_radial = t
	return t
