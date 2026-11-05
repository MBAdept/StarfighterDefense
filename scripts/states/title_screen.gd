class_name TitleScreen
extends Node3D
## Titel/Menü: 3D-Kulisse (Heimatplanet, Station, vorbeiziehende Jäger) + Menü.

var camera: Camera3D
var ui: CanvasLayer
var menu: VBoxContainer
var _diff_label: Label
var _sub: Control = null
var _t := 0.0
var _planet: Node3D
var _station: Node3D
var _ring: Node3D
var _ships: Array = []
var _logo: Control


func _ready() -> void:
	_build_scene()
	_build_ui()
	Audio.play_music("title_theme", 2.0)


func _build_scene() -> void:
	camera = Camera3D.new()
	camera.fov = 55.0
	camera.far = 20000.0
	add_child(camera)
	camera.current = true
	var sky := ShaderMaterial.new()
	sky.shader = load("res://shaders/space_sky.gdshader")
	var pano := Assets.tex("sky/space_panorama.png")
	if pano:
		sky.set_shader_parameter("panorama", pano)
		sky.set_shader_parameter("use_panorama", true)
	sky.set_shader_parameter("sun_size", cos(deg_to_rad(0.35)))
	sky.set_shader_parameter("sun_intensity", 1.6)
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var s := Sky.new()
	s.sky_material = sky
	env.sky = s
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.2, 0.25, 0.35)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	env.glow_intensity = 1.0
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	for i in 7:
		env.set_glow_level(i, 1.0 if i in [1, 2, 3, 4] else 0.0)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun_dir := Vector3(-0.75, 0.3, 0.6).normalized()
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.8
	sun.light_color = Color(1.0, 0.94, 0.86)
	add_child(sun)
	sun.look_at_from_position(Vector3.ZERO, -sun_dir, Vector3.UP)
	# Planet
	var home := PlanetData.new()
	home.type = "terran"
	home.is_home = true
	_planet = Node3D.new()
	add_child(_planet)
	_planet.position = Vector3(520, -260, -1500)
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 720.0
	sm.height = 1440.0
	sm.radial_segments = 128
	sm.rings = 64
	mi.mesh = sm
	var pm := ShaderMaterial.new()
	pm.shader = load("res://shaders/planet.gdshader")
	var t := Assets.tex("planets/terran.png")
	if t:
		pm.set_shader_parameter("albedo_tex", t)
	else:
		pm.set_shader_parameter("use_fallback", true)
	var cl := Assets.tex("planets/clouds.png")
	if cl:
		pm.set_shader_parameter("clouds_tex", cl)
	pm.set_shader_parameter("has_clouds", cl != null)
	pm.set_shader_parameter("sun_dir", sun_dir)
	pm.set_shader_parameter("night_light_strength", 1.6)
	pm.set_shader_parameter("night_noise", Effects.noise_texture())
	pm.set_shader_parameter("atmo_color", PlanetLook.atmosphere("terran"))
	mi.material_override = pm
	_planet.add_child(mi)
	var atmo := MeshInstance3D.new()
	var am := SphereMesh.new()
	am.radius = 745.0
	am.height = 1490.0
	am.radial_segments = 128
	am.rings = 64
	atmo.mesh = am
	var amat := ShaderMaterial.new()
	amat.shader = load("res://shaders/atmosphere.gdshader")
	amat.set_shader_parameter("atmo_color", PlanetLook.atmosphere("terran"))
	amat.set_shader_parameter("sun_dir", sun_dir)
	atmo.material_override = amat
	_planet.add_child(atmo)
	# Station
	_station = Assets.model("station")
	add_child(_station)
	_station.position = Vector3(-95, 18, -330)
	_station.rotation_degrees = Vector3(12, 35, 8)
	_ring = Assets.find_node_named(_station, "Ring")
	for i in range(1, 5):
		var b := Assets.find_node_named(_station, "Beacon_%d" % i)
		if b:
			b.add_child(Assets.glow_sprite(Color(1.0, 0.3, 0.25), 4.0, 4.0))
	# Patrouille (Jäger der Gegner als Bedrohung)
	for i in 3:
		var f := Assets.model("fighter")
		add_child(f)
		for n in ["Engine_L", "Engine_R"]:
			var m := Assets.find_node_named(f, n)
			if m:
				m.add_child(Assets.glow_sprite(Color(1.0, 0.5, 0.2), 3.0, 4.0))
		_ships.append({"node": f, "off": i * 2.1, "speed": 0.07 + i * 0.012})


func _process(delta: float) -> void:
	_t += delta
	camera.rotation = Vector3(deg_to_rad(2.0 + sin(_t * 0.07) * 1.5), deg_to_rad(sin(_t * 0.05) * 4.0), 0.0)
	_planet.rotate_y(delta * 0.01)
	if _ring:
		_ring.rotate_object_local(Vector3(0, 0, 1), delta * 0.15)
	for s in _ships:
		var k: float = fmod(_t * s.speed + s.off, 1.0)
		var p := Vector3(lerpf(-420.0, 420.0, k), 40.0 + sin(k * 6.0 + s.off) * 30.0, -260.0 - s.off * 60.0)
		var n: Node3D = s.node
		var nxt := Vector3(lerpf(-420.0, 420.0, k + 0.01), 40.0 + sin((k + 0.01) * 6.0 + s.off) * 30.0, -260.0 - s.off * 60.0)
		n.position = p
		if nxt.distance_to(p) > 0.01:
			n.look_at(nxt, Vector3.UP)
			n.rotate_object_local(Vector3.FORWARD, sin(k * 6.0 + s.off) * 0.5)
	if _logo:
		_logo.modulate.a = clampf(_t * 0.8, 0.0, 1.0)


func _build_ui() -> void:
	ui = CanvasLayer.new()
	ui.layer = 5
	add_child(ui)
	var root := Control.new()
	root.theme = UITheme.get_theme()
	ui.add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(0, 0.01, 0.03, 0.85))
	g.set_color(1, Color(0, 0.01, 0.03, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0)
	shade.texture = gt
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.anchor_right = 0.6
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)
	_logo = VBoxContainer.new()
	_logo.position = Vector2(110, 120)
	root.add_child(_logo)
	var t1 := UITheme.title_label("STARFIGHTER", 104, UITheme.CYAN)
	t1.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_logo.add_child(t1)
	var t2 := UITheme.title_label("D E F E N S E", 46, UITheme.AMBER)
	t2.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_logo.add_child(t2)
	var tag := UITheme.label("Verteidige das %s-System gegen die feindlichen Schwadrone." % GameState.STAR_NAME, 28, UITheme.TEXT_DIM)
	_logo.add_child(tag)
	menu = VBoxContainer.new()
	menu.position = Vector2(118, 470)
	menu.custom_minimum_size = Vector2(460, 0)
	menu.add_theme_constant_override("separation", 14)
	root.add_child(menu)
	menu.add_child(UITheme.button("NEUES SPIEL", func(): Main.instance.new_game()))
	menu.add_child(UITheme.button("OPTIONEN", func(): _open(OptionsMenu.new())))
	menu.add_child(UITheme.button("STEUERUNG", func(): _open(ControlsHelp.new())))
	menu.add_child(UITheme.button("HIGHSCORES", func(): _open(HighscoreView.new())))
	menu.add_child(UITheme.button("BEENDEN", func(): get_tree().quit()))
	for b in menu.get_children():
		(b as Button).alignment = HORIZONTAL_ALIGNMENT_LEFT
	# gewählte Schwierigkeitsstufe (Optionen) unter dem Menü – jede Stufe hat eine eigene Highscore-Liste
	_diff_label = UITheme.label("", 22, Color(UITheme.TEXT_DIM, 0.95))
	_diff_label.position = Vector2(122, 470 + 5 * 74 + 6)
	root.add_child(_diff_label)
	_update_difficulty_label()
	Settings.changed.connect(_update_difficulty_label)   # Methode: wird beim Freigeben automatisch getrennt
	var foot := UITheme.label("Remake-Hommage · Version %s · Grafik, Klang und Musik vollständig prozedural erzeugt · F11 Vollbild" % ProjectSettings.get_setting("application/config/version"), 18, Color(UITheme.TEXT_DIM, 0.7))
	root.add_child(foot)
	foot.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	foot.offset_left = 112
	foot.offset_top = -56
	foot.offset_bottom = -24
	await get_tree().process_frame
	menu.get_child(0).grab_focus()


func _update_difficulty_label() -> void:
	if is_instance_valid(_diff_label):
		_diff_label.text = "Schwierigkeit: %s  ·  ändern unter Optionen" % Settings.difficulty_name()


func _open(c: Control) -> void:
	_sub = c
	ui.add_child(c)
	menu.visible = false
	c.closed.connect(func():
		_sub = null
		menu.visible = true
		menu.get_child(0).grab_focus()
	)
