extends Node
## Zentrale Asset-Verwaltung: Schriften, Texturen, 3D-Modelle (Blender-glTF) mit Fallbacks.
## Fehlt ein Asset, wird ein einfacher prozeduraler Ersatz erzeugt – das Spiel bleibt lauffähig.

const MODEL_DIR := "res://assets/models/"
const TEX_DIR := "res://assets/textures/"

var _scene_cache := {}
var _tex_cache := {}
var _mat_cache := {}
var fonts := {}


func _ready() -> void:
	var body := _load_font("rajdhani-latin-600-normal.woff2")
	var body_bold := _load_font("rajdhani-latin-700-normal.woff2")
	var body_med := _load_font("rajdhani-latin-500-normal.woff2")
	var title := _load_font("orbitron-latin-900-normal.woff2")
	var display := _load_font("orbitron-latin-700-normal.woff2")
	var display_med := _load_font("orbitron-latin-500-normal.woff2")
	var mono := _load_font("share-tech-mono-latin-400-normal.woff2")
	for f in [title, display, display_med, mono]:
		if f and body:
			f.fallbacks = [body]
	fonts["body"] = body if body else ThemeDB.fallback_font
	fonts["body_bold"] = body_bold if body_bold else fonts["body"]
	fonts["body_med"] = body_med if body_med else fonts["body"]
	fonts["title"] = _spaced(title, 4) if title else fonts["body_bold"]
	fonts["display"] = _spaced(display, 2) if display else fonts["body_bold"]
	fonts["display_med"] = _spaced(display_med, 1) if display_med else fonts["body"]
	fonts["mono"] = mono if mono else fonts["body"]


func _load_font(file: String) -> FontFile:
	var path := "res://assets/fonts/" + file
	if ResourceLoader.exists(path):
		var f: FontFile = load(path)
		if f:
			f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
			f.hinting = TextServer.HINTING_LIGHT
			f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
			f.oversampling = 0.0
		return f
	return null


func _spaced(f: Font, spacing: int) -> Font:
	var v := FontVariation.new()
	v.base_font = f
	v.spacing_glyph = spacing
	return v


func font(font_name: String) -> Font:
	return fonts.get(font_name, ThemeDB.fallback_font)


func tex(rel_path: String) -> Texture2D:
	if _tex_cache.has(rel_path):
		return _tex_cache[rel_path]
	var path := TEX_DIR + rel_path
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path)
	_tex_cache[rel_path] = t
	return t


func has_model(model_name: String) -> bool:
	return ResourceLoader.exists(MODEL_DIR + model_name + ".glb")


## Instanziert ein Modell; fehlt die Datei, wird ein Ersatzmodell gebaut.
func model(model_name: String) -> Node3D:
	var path := MODEL_DIR + model_name + ".glb"
	if not _scene_cache.has(model_name):
		_scene_cache[model_name] = load(path) if ResourceLoader.exists(path) else null
	var ps: PackedScene = _scene_cache[model_name]
	var root: Node3D
	if ps:
		root = ps.instantiate()
		_tune_materials(root)
	else:
		root = FallbackModels.build(model_name)
	return root


## Alle Meshes eines Modells (z. B. für MultiMesh-Streuung von Felsen).
func model_meshes(model_name: String) -> Array:
	var out := []
	var root := model(model_name)
	for mi in find_all_meshes(root):
		out.append(mi.mesh)
	root.free()
	return out


func find_all_meshes(root: Node) -> Array:
	var out := []
	if root is MeshInstance3D:
		out.append(root)
	for c in root.get_children():
		out.append_array(find_all_meshes(c))
	return out


func find_node_named(root: Node, node_name: String) -> Node:
	if root.name == node_name or String(root.name).begins_with(node_name):
		return root
	for c in root.get_children():
		var r := find_node_named(c, node_name)
		if r:
			return r
	return null


func find_nodes_prefixed(root: Node, prefix: String) -> Array:
	var out := []
	if String(root.name).begins_with(prefix) and root is Node3D:
		out.append(root)
	for c in root.get_children():
		out.append_array(find_nodes_prefixed(c, prefix))
	return out


## Leichte Nachbearbeitung importierter Materialien (Randlicht, Glanz, Emission verstärken).
func _tune_materials(root: Node) -> void:
	for mi in find_all_meshes(root):
		var m: Mesh = mi.mesh
		if m == null:
			continue
		for i in m.get_surface_count():
			var mat := m.surface_get_material(i)
			if mat is BaseMaterial3D:
				var key := mat.get_instance_id()
				if _mat_cache.has(key):
					continue
				_mat_cache[key] = true
				var bm := mat as BaseMaterial3D
				var n := String(bm.resource_name)
				if n.begins_with("Hull") or n.begins_with("Structure"):
					bm.rim_enabled = true
					bm.rim = 0.35
					bm.rim_tint = 0.6
				if n.begins_with("Glow") and bm.emission_enabled:
					bm.emission_energy_multiplier = clampf(bm.emission_energy_multiplier, 1.5, 4.0)


## Färbt alle Oberflächen mit Materialnamen-Präfix `mat_prefix` für diese Instanz um (z. B. Zerstörerfarbe).
func tint(root: Node, mat_prefix: String, color: Color, emission_energy := 3.0) -> Array:
	var made := []
	for mi in find_all_meshes(root):
		var m: Mesh = mi.mesh
		if m == null:
			continue
		for i in m.get_surface_count():
			var mat: Material = mi.get_active_material(i)
			if mat is BaseMaterial3D and String(mat.resource_name).begins_with(mat_prefix):
				var nm: BaseMaterial3D = mat.duplicate()
				if String(mat.resource_name).begins_with(mat_prefix + "Paint"):
					# Panzerplatten: nur einfärben, kaum Leuchten
					nm.albedo_color = color.darkened(0.35)
					nm.emission_enabled = true
					nm.emission = color
					nm.emission_energy_multiplier = 0.12
				else:
					nm.albedo_color = color.darkened(0.25)
					nm.emission_enabled = true
					nm.emission = color
					nm.emission_energy_multiplier = emission_energy
				mi.set_surface_override_material(i, nm)
				made.append(nm)
	return made


## Liefert die (ggf. überschriebenen) Materialien mit Präfix – für Animationen (z. B. WeakPoint).
func materials_with_prefix(root: Node, mat_prefix: String) -> Array:
	var out := []
	for mi in find_all_meshes(root):
		var m: Mesh = mi.mesh
		if m == null:
			continue
		for i in m.get_surface_count():
			var mat: Material = mi.get_active_material(i)
			if mat is BaseMaterial3D and String(mat.resource_name).begins_with(mat_prefix):
				var nm: BaseMaterial3D = mat.duplicate()
				mi.set_surface_override_material(i, nm)
				out.append(nm)
	return out


# ---------------------------------------------------------------------------------------------
#  Geteilte Materialien für Effekte
# ---------------------------------------------------------------------------------------------
func additive_material(color: Color, energy := 4.0, texture: Texture2D = null, billboard := false) -> StandardMaterial3D:
	var key := "add_%s_%s_%s_%s" % [color.to_html(), energy, texture.resource_path if texture else "", billboard]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(color.r * energy, color.g * energy, color.b * energy, color.a)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.no_depth_test = false
	m.disable_receive_shadows = true
	m.disable_fog = true
	if texture:
		m.albedo_texture = texture
	if billboard:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.billboard_keep_scale = true
	_mat_cache[key] = m
	return m


func glow_sprite(color: Color, size: float, energy := 3.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	mi.mesh = q
	var t := tex("fx/glow.png")
	if t == null:
		t = FallbackModels.radial_texture()
	mi.material_override = additive_material(color, energy, t, true)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
