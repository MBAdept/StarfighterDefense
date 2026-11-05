class_name CockpitRig
extends Node3D
## =============================================================================================
##  Physisches Kampfjet-Cockpit (3D, Kind der Kamera): Konsole mit Blendschutz, Instrumententafel
##  mit zwei MFDs und Warnlampen, Mittelpult mit großem MFD (Scanner/Tanken/Waffen), Kanzelrahmen
##  und das Combiner-Glas des Head-Up-Displays.
##  Die Teile federn bei Drehungen leicht nach (Trägheit) und zittern bei Treffern. Die HUD-Symbolik
##  zeichnet CockpitHUD in 2D – deckungsgleich mit der Welt; das Glas begrenzt nur ihren Sichtbereich.
##  Alle Maße werden aus Bildschirmanteilen (0..1) und Tiefe (m) berechnet: _sp(sx, sy, tiefe).
## =============================================================================================

const LAG_TIME := 0.045         ## Nachlauf bei Drehungen (s Drehrate → Auslenkung), × Config.cockpit_lag
const LAG_MAX := 0.04           ## größte Auslenkung (rad, ~2,3°), × Config.cockpit_lag
const SPRING := 140.0           ## Federsteifigkeit der Aufhängung
const DAMP := 17.0              ## Dämpfung
## Kompakte Konsole (Bildanteile von oben): Blendschutzkante und Oberkante des Mittelpults
const LIP_SY := 0.845
const STACK_SY_SPACE := 0.79
const STACK_SY_PLANET := 0.765   ## auf Planeten etwas höher: größerer Scanner, Aufschlagmarke bleibt frei
const POWER_TIME := 0.9          ## Einschalten der Bildschirme beim Szenenstart (s)

var combat: CombatBase
var mfd_nav: CockpitMFD         ## links: Navigation (Ort, Zeit, Hinweise)
var mfd_center: CockpitMFD      ## Mitte: Scanner / Andocken / Waffen
var mfd_link: CockpitMFD        ## rechts: Datenlink (Meldungen)

## Lokale Eckpunkte (im Uhrzeigersinn: oben links, oben rechts, unten rechts, unten links)
var glass_corners := PackedVector3Array()
var stack_corners := PackedVector3Array()
## Zwei Punkte auf der Blendschutzkante (2D-Laser verschwinden dahinter)
var lip_points := PackedVector3Array()
var _canopy_band := PackedVector3Array()   ## Umriss Kanzelrahmen + Dichtung (Sichtstörung, ViewFX)
var _stack_box := PackedVector3Array()     ## acht Ecken des Mittelpults
var _frame_boxes: Array = []               ## Füße, Holme, obere Leiste des Combiner-Glases: {c: 8 Ecken, down: bis unter die Kante}

var _cam: Camera3D
var _aspect := 16.0 / 9.0
var _rebuild_queued := false
var _tan_v := 0.6
var _tan_h := 1.07
var _prev_basis := Basis.IDENTITY
var _have_prev := false
var _lag := Vector3.ZERO
var _lag_v := Vector3.ZERO
var _t := 0.0
var _hit := 0.0                 ## Lampe TREFFER (Restdauer, s)
var _hit_heavy := false
var _hit_hold := 0.0            ## rotes Cockpitlicht: Haltezeit nach der Rückmeldung (s)
var _glow := 0.0                ## rotes Cockpitlicht 0..1 – schneller Anstieg, langsames Abklingen
var _fill: OmniLight3D
var _lamps: Array = []          ## [{id, mat, label}]
var _viewports: Array = []
var _m_body: StandardMaterial3D
var _m_panel: StandardMaterial3D
var _m_bezel: StandardMaterial3D
var _m_frame: StandardMaterial3D
var _m_button: StandardMaterial3D
var _m_strip: StandardMaterial3D
var _m_hud_glow: StandardMaterial3D
var _m_seal: StandardMaterial3D
var _panel_p := Vector3(0.0, -0.334, -0.87)   ## Punkt auf der Instrumententafel
var _panel_n := Vector3(0.0, 0.379, 0.925)     ## Normale der Instrumententafel (zum Auge)
var _stack_p := Vector3.ZERO                   ## Punkt auf der Front des Mittelpults
var _stack_n := Vector3.BACK
var _dy := 0.0                                 ## Konsole nach unten versetzt (m), siehe LIP_SY
var _res := 1.0                                ## Bildpunkte je HUD-Pixel (MFDs scharf bei jeder Fenstergröße)
var _mfd_mats: Array = []


func setup(c: CombatBase) -> void:
	combat = c
	_cam = c.camera
	_build()
	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()   # auch beim Aufbau in eingefrorener Szene (Karte offen): MFDs nicht rendern
	get_viewport().size_changed.connect(_on_size_changed)
	_prev_basis = _cam.global_transform.basis.orthonormalized()


## Aufbau für das aktuelle Seitenverhältnis (bei Größenänderung des Fensters neu).
func _build() -> void:
	var vp := get_viewport().get_visible_rect().size
	_aspect = vp.x / maxf(vp.y, 1.0)
	_tan_v = tan(deg_to_rad(_cam.fov) * 0.5)
	_tan_h = _tan_v * _aspect
	_lamps.clear()
	_viewports.clear()
	_mfd_mats.clear()
	_frame_boxes.clear()
	_res = _res_scale()
	_make_materials()
	_build_console()
	_build_stack()
	_build_glass()
	_build_canopy()
	_build_visor()
	_build_mfds()
	_build_lamps()
	_build_lights()


func _on_size_changed() -> void:
	var vp := get_viewport().get_visible_rect().size
	if absf(vp.x / maxf(vp.y, 1.0) - _aspect) > 0.01 and not _rebuild_queued:
		_rebuild_queued = true
		_rebuild.call_deferred()
		return
	# nur die Fenstergröße geändert: MFD-Bilder in passender Auflösung rendern
	var r := _res_scale()
	if absf(r - _res) > 0.01:
		_res = r
		for v in _viewports:
			var sv := v as SubViewport
			sv.size = Vector2i((Vector2(sv.size_2d_override) * _res).round())


## Echte Bildpunkte je HUD-Pixel (Streckmodus canvas_items: HUD rechnet in 1920 × 1080).
func _res_scale() -> float:
	var vis := get_viewport().get_visible_rect().size.y
	return clampf(float(get_window().size.y) / maxf(vis, 1.0), 0.5, 3.0)


func _rebuild() -> void:
	_rebuild_queued = false
	for ch in get_children():
		remove_child(ch)
		ch.queue_free()
	_build()
	_on_visibility_changed()


# ---------------------------------------------------------------------------------------------
#  Laufzeit: Nachfedern, Zittern, Lampen
# ---------------------------------------------------------------------------------------------
func _process(delta: float) -> void:
	if _cam == null or delta <= 0.0:
		return
	_t += delta
	_hit = maxf(_hit - delta, 0.0)
	var b := _cam.global_transform.basis.orthonormalized()
	var target := Vector3.ZERO
	if _have_prev:
		var rel := _prev_basis.inverse() * b
		var e := rel.get_euler()
		if e.length() > 0.35:
			# Sprung (Testblick, Szenenwechsel): ohne Ausschlag übernehmen
			_lag = Vector3.ZERO
			_lag_v = Vector3.ZERO
		else:
			var rate := e / delta
			var lf := maxf(Config.cockpit_lag, 0.0)
			var lm := LAG_MAX * lf
			target = Vector3(clampf(-rate.x * LAG_TIME * lf, -lm, lm), clampf(-rate.y * LAG_TIME * lf, -lm, lm), clampf(rate.y * LAG_TIME * 0.25 * lf, -lm, lm))
	_prev_basis = b
	_have_prev = true
	# Feder-Dämpfer in festen Teilschritten (bildratenunabhängig, stabil)
	var steps := clampi(ceili(delta / 0.008), 1, 32)
	var k := delta / steps
	for i in steps:
		_lag_v += ((target - _lag) * SPRING - _lag_v * DAMP) * k
		_lag += _lag_v * k
	# Zittern bei Treffern/Explosionen: das Cockpit wackelt, die Symbolik bleibt ruhig (kollimiert)
	var s := combat.shake * combat.shake * Config.screen_shake
	var jit := Vector3(sin(_t * 61.0) * 0.6 + sin(_t * 23.0) * 0.4, sin(_t * 53.0 + 1.3) * 0.6 + sin(_t * 31.0) * 0.4, sin(_t * 47.0 + 2.1)) * s * 0.006
	# h_offset/v_offset verschieben die Kamera selbst (Weltwackeln) – das Cockpit fährt mit
	# kaum merkliches Wippen (Triebwerk/Sitz) – auch das trennt das Cockpit von der Welt
	var bob := Vector3(sin(_t * 0.83) * 0.0012, sin(_t * 1.9) * 0.0016 + sin(_t * 0.61) * 0.0011, 0.0) * maxf(Config.cockpit_lag, 0.0)
	transform = Transform3D(Basis.from_euler(_lag + jit), Vector3(_cam.h_offset, _cam.v_offset, 0.0) + Vector3(jit.y, jit.x, 0.0) * 0.3 + bob)
	_update_lamps()
	_update_power()
	# Hüllkurve statt An/Aus: Anstieg in ~60 ms, Halten, Abklingen über ~0,7 s – bei Dauerbeschuss (Rückmeldung
	# höchstens alle 0,5 s) pulsiert das Licht höchstens zweimal pro Sekunde, weich und ohne gesättigtes Rot
	_hit_hold = maxf(_hit_hold - delta, 0.0)
	var glow_target := (1.0 if _hit_heavy else 0.55) if _hit_hold > 0.0 else 0.0
	if glow_target > _glow:
		_glow = minf(_glow + delta / 0.06, glow_target)
	else:
		_glow = maxf(_glow - delta / 0.7, glow_target)
	_fill.light_color = Color(0.55, 0.72, 0.85).lerp(Color(1.0, 0.55, 0.4), _glow)
	_fill.light_energy = 0.55 + _glow * 1.2


## Einschalten beim Szenenstart: Bildschirme flackern kurz auf und werden hell.
func _update_power() -> void:
	if _t > POWER_TIME + 0.1:
		return
	var k := clampf(_t / POWER_TIME, 0.0, 1.0)
	var off := 1.0 - k * k
	if (_t > 0.18 and _t < 0.24) or (_t > 0.38 and _t < 0.42):
		off = 0.85   # kurzes Flackern beim Hochfahren
	for m in _mfd_mats:
		(m as ShaderMaterial).set_shader_parameter("flicker", clampf(off, 0.0, 1.0))


## Trefferrückmeldung (über HudBase höchstens alle Config.hit_flash_min_gap Sekunden).
func on_player_hit(heavy: bool) -> void:
	_hit = 0.9 if heavy else 0.6   # Lampe länger als der Mindestabstand: bei Dauerbeschuss ruhiges Dauerlicht
	_hit_heavy = heavy
	_hit_hold = 0.4 if heavy else 0.25


func _on_visibility_changed() -> void:
	# Karte offen (Szene eingefroren): MFD-Bilder nicht weiter rendern
	for v in _viewports:
		(v as SubViewport).render_target_update_mode = SubViewport.UPDATE_ALWAYS if is_visible_in_tree() else SubViewport.UPDATE_DISABLED


## Cockpitteile über der Blendschutzkante (lokal) für die Sichtstörung (ViewFX): [{pts, hull}].
## hull = true: konvexe Hülle der projizierten Punkte (Mittelpult). Reihenfolge so, dass beim Ausschneiden
## keine Löcher entstehen: Füße und Holme des Combiner-Rahmens reichen bis unter die Blendschutzkante.
func view_cutouts() -> Array:
	var out := []
	if not _canopy_band.is_empty():
		out.append({"pts": _canopy_band, "hull": false})
	if _stack_box.size() == 8:
		out.append({"pts": _stack_box, "hull": true})
	# Rahmen des Combiner-Glases: exakte Umrisse (konvexe Hülle der Stab-Ecken). Füße und Holme reichen bis unter
	# die Blendschutzkante (zusätzliche Punkte 0,15 m tiefer), die obere Leiste zuletzt – so entstehen keine Löcher.
	for fb in _frame_boxes:
		var corners: PackedVector3Array = fb.c
		var pts := corners.duplicate()
		if fb.down:
			# entlang der eigenen (schrägen) Achse des Stabs nach unten – sonst wölbt sich die Hülle nach außen
			var axis := (corners[2] - corners[0]).normalized()
			for c in corners:
				pts.append(c - axis * 0.15)
		out.append({"pts": pts, "hull": true})
	return out


## Glas- und Pultecken in Bildschirmkoordinaten (Laser-Ausblendung, Verdeckung durch die Konsole).
func project_quad(local: PackedVector3Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(local.size())
	for i in local.size():
		out[i] = _cam.unproject_position(to_global(local[i]))
	return out


## Wie project_quad, aber in Ruhelage (ohne Nachfedern, Zittern, Wippen): Maske der fest stehenden Glas-Symbolik.
func project_quad_rest(local: PackedVector3Array) -> PackedVector2Array:
	var rest := _cam.global_transform * Transform3D(Basis.IDENTITY, Vector3(_cam.h_offset, _cam.v_offset, 0.0))
	var out := PackedVector2Array()
	out.resize(local.size())
	for i in local.size():
		out[i] = _cam.unproject_position(rest * local[i])
	return out


# ---------------------------------------------------------------------------------------------
#  Hilfen für den Aufbau
# ---------------------------------------------------------------------------------------------
func _x(sx: float, depth: float) -> float:
	return (sx * 2.0 - 1.0) * _tan_h * depth


func _y(sy: float, depth: float) -> float:
	return (1.0 - sy * 2.0) * _tan_v * depth


## Punkt, der bei Bildschirmanteil (sx, sy) in der Tiefe depth liegt.
func _sp(sx: float, sy: float, depth: float) -> Vector3:
	return Vector3(_x(sx, depth), _y(sy, depth), -depth)


func _mat(albedo: Color, metal: float, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.metallic = metal
	m.roughness = rough
	m.disable_fog = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mark_stencil(m)
	return m


func _emissive(col: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(col.r * energy, col.g * energy, col.b * energy)
	m.disable_fog = true
	_mark_stencil(m)
	return m


## Cockpitteile schreiben Stencil 1: die Aufschlagmarke der Bomben (ohne Tiefentest, damit sie
## durch Städte hindurch sichtbar bleibt) wird dort nicht über das Cockpit gezeichnet.
static func _mark_stencil(m: StandardMaterial3D) -> void:
	m.stencil_mode = BaseMaterial3D.STENCIL_MODE_CUSTOM
	m.stencil_flags = BaseMaterial3D.STENCIL_FLAG_WRITE
	m.stencil_compare = BaseMaterial3D.STENCIL_COMPARE_ALWAYS
	m.stencil_reference = 1


func _make_materials() -> void:
	# Cockpits sind matt lackiert (keine Spiegelungen im Blickfeld)
	_m_body = _mat(Color(0.062, 0.068, 0.078), 0.15, 0.8)
	_m_panel = _mat(Color(0.042, 0.046, 0.052), 0.05, 0.9)
	_m_bezel = _mat(Color(0.022, 0.024, 0.028), 0.1, 0.6)
	_m_frame = _mat(Color(0.075, 0.08, 0.09), 0.5, 0.45)
	_m_button = _mat(Color(0.09, 0.095, 0.1), 0.2, 0.55)
	_m_button.emission_enabled = true
	_m_button.emission = Color(0.12, 0.35, 0.4)
	_m_button.emission_energy_multiplier = 0.35
	_m_strip = _emissive(UITheme.CYAN, 1.3)
	_m_seal = _mat(Color(0.05, 0.06, 0.07), 0.2, 0.5)
	_m_seal.emission_enabled = true
	_m_seal.emission = Color(0.2, 0.55, 0.62)
	_m_seal.emission_energy_multiplier = 0.45
	_m_hud_glow = _emissive(Color(0.42, 1.0, 0.58), 1.2)


## Mesh aus Dreiecken (je drei Punkte) mit flachen Normalen, die zur Kamera (Ursprung) zeigen.
## Godot wertet im Uhrzeigersinn gewundene Dreiecke als Vorderseite – die Reihenfolge wird so
## gedreht, dass die dem Auge zugewandte Seite vorne liegt.
func _tri_mesh(tris: PackedVector3Array, mat: Material, uv_scale := 1.0) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(0, tris.size(), 3):
		var a := tris[i]
		var b := tris[i + 1]
		var c := tris[i + 2]
		var n := (b - a).cross(c - a).normalized()
		if n.dot(-(a + b + c) / 3.0) > 0.0:
			var tmp := b
			b = c
			c = tmp
		else:
			n = -n
		for p in [a, b, c]:
			st.set_normal(n)
			st.set_uv(Vector2(p.x + p.z * 0.5, p.y + p.z * 0.5) * uv_scale)
			st.add_vertex(p)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _quad(tris: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	tris.append_array([a, b, c, a, c, d])


## Quader aus acht Ecken: vorne (ol, or, ur, ul), hinten (ol, or, ur, ul).
func _hexa(p: Array, mat: Material) -> MeshInstance3D:
	var t := PackedVector3Array()
	_quad(t, p[0], p[1], p[2], p[3])
	_quad(t, p[4], p[5], p[6], p[7])
	_quad(t, p[0], p[1], p[5], p[4])
	_quad(t, p[3], p[2], p[6], p[7])
	_quad(t, p[0], p[3], p[7], p[4])
	_quad(t, p[1], p[2], p[6], p[5])
	return _tri_mesh(t, mat)


## Profil (z, y) entlang der X-Achse extrudieren.
func _extrude(profile: PackedVector2Array, x0: float, x1: float, mat: Material) -> MeshInstance3D:
	var t := PackedVector3Array()
	for k in profile.size() - 1:
		var p := profile[k]
		var q := profile[k + 1]
		_quad(t, Vector3(x0, p.y, p.x), Vector3(x1, p.y, p.x), Vector3(x1, q.y, q.x), Vector3(x0, q.y, q.x))
	return _tri_mesh(t, mat, 2.0)


## Schnittpunkt des Sehstrahls durch (sx, sy) mit einer Ebene (Punkt p0, Normale n).
func _on_plane(sx: float, sy: float, p0: Vector3, n: Vector3) -> Vector3:
	var dir := Vector3(_x(sx, 1.0), _y(sy, 1.0), -1.0)
	return dir * (p0.dot(n) / dir.dot(n))


## Basis in einer Ebene (X waagerecht, +Z = Normale).
func _plane_basis(n: Vector3) -> Basis:
	var z := n.normalized()
	var x := Vector3.RIGHT - z * z.x
	x = x.normalized()
	return Basis(x, z.cross(x), z)


## Quader auf einer Ebene: Mittelpunkt in der Ebene, ragt um thick heraus (+ lift).
func _plane_box(center: Vector3, b: Basis, w: float, h: float, thick: float, mat: Material, lift := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(w, h, thick)
	mi.mesh = bm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.transform = Transform3D(b, center + b.z * (thick * 0.5 + lift))
	add_child(mi)
	return mi


# ---------------------------------------------------------------------------------------------
#  Konsole: Blendschutz mit Leuchtleiste, Instrumententafel
# ---------------------------------------------------------------------------------------------
func _build_console() -> void:
	var w := 3.2
	# Die Blendschutzkante (y = -0,300 in 0,84 m Tiefe) soll bei LIP_SY im Bild liegen: ganze Konsole versetzen
	_dy = _y(LIP_SY, 0.84) + 0.300
	# Profil (z, y): hinten unter der Frontscheibe → Blendschutzkante → Hohlkehle → Instrumententafel
	var prof := PackedVector2Array([
		Vector2(-1.30, -0.44), Vector2(-0.84, -0.300), Vector2(-0.815, -0.305),
		Vector2(-0.806, -0.322), Vector2(-0.84, -0.330), Vector2(-0.87, -0.334), Vector2(-0.72, -0.70)])
	for i in prof.size():
		prof[i].y += _dy
	_extrude(prof.slice(0, 5), -w, w, _m_body)
	_extrude(prof.slice(4), -w, w, _m_panel)
	var f := prof[5]
	var g := prof[6]
	_panel_p = Vector3(0.0, f.y, f.x)
	_panel_n = Vector3(0.0, g.x - f.x, -(g.y - f.y)).normalized()
	if _panel_n.dot(-_panel_p) < 0.0:
		_panel_n = -_panel_n
	# Oberste sichtbare Konsolenkante (dahinter verschwinden Laser, Linsenreflexe, Bombenbahn): bei FOV 62°
	# die hintere Kante der Blendschutz-Oberseite (prof[0]), bei engem FOV die Blendschutzkante (prof[1])
	var top := prof[0] if absf(prof[0].y / prof[0].x) < absf(prof[1].y / prof[1].x) else prof[1]
	lip_points = PackedVector3Array([Vector3(-0.6, top.y, top.x), Vector3(0.6, top.y, top.x)])
	# Leuchtleiste an der Unterkante des Blendschutzes
	_extrude(PackedVector2Array([Vector2(-0.8042, -0.3172 + _dy), Vector2(-0.8042, -0.3215 + _dy)]), -w, w, _m_strip)
	# Fugen auf der Abdeckung (dezente Paneele)
	for sx in [0.2, 0.36, 0.64, 0.8]:
		var x := _x(sx, 1.0)
		var seam := PackedVector2Array([Vector2(-1.25, -0.4365 + _dy), Vector2(-0.845, -0.3015 + _dy)])
		var t := PackedVector3Array()
		for k in 1:
			var p := seam[k]
			var q := seam[k + 1]
			_quad(t, Vector3(x - 0.003, p.y + 0.001, p.x), Vector3(x + 0.003, p.y + 0.001, p.x), Vector3(x + 0.003, q.y + 0.001, q.x), Vector3(x - 0.003, q.y + 0.001, q.x))
		_tri_mesh(t, _m_bezel)


# ---------------------------------------------------------------------------------------------
#  Mittelpult mit HUD-Projektor; davor steht das große MFD
# ---------------------------------------------------------------------------------------------
func _build_stack() -> void:
	var top_sy := STACK_SY_PLANET if combat is PlanetCombat else STACK_SY_SPACE
	# Breite wie bei 16:9 (gleiche Meter): bei breiteren Formaten nicht mitwachsen, sonst verdeckt das
	# Pult Waffenblock und Lage (die HUD-Symbolik steht in festen Pixeln um die Bildmitte)
	var k := minf(1.0, (16.0 / 9.0) / _aspect)
	var x0 := 0.5 - 0.086 * k
	var x1 := 0.5 + 0.086 * k
	var ftl := _sp(x0, top_sy, 0.775)
	var ftr := _sp(x1, top_sy, 0.775)
	var fbr := _sp(x1 + 0.012 * k, 1.25, 0.66)
	var fbl := _sp(x0 - 0.012 * k, 1.25, 0.66)
	var btl := Vector3(ftl.x * 1.08, ftl.y - 0.07, -1.0)
	var btr := Vector3(ftr.x * 1.08, ftr.y - 0.07, -1.0)
	var bbr := Vector3(fbr.x * 1.08, fbr.y, -0.9)
	var bbl := Vector3(fbl.x * 1.08, fbl.y, -0.9)
	_hexa([ftl, ftr, fbr, fbl, btl, btr, bbr, bbl], _m_body)
	_stack_box = PackedVector3Array([ftl, ftr, fbr, fbl, btl, btr, bbr, bbl])
	_stack_p = ftl
	_stack_n = (ftr - ftl).cross(fbl - ftl).normalized()
	if _stack_n.dot(-ftl) < 0.0:
		_stack_n = -_stack_n
	stack_corners = PackedVector3Array([ftl + Vector3(0, 0.004, 0), ftr + Vector3(0, 0.004, 0), fbr, fbl])
	# Projektoröffnung (grünes Glimmen) an der Oberkante
	var a := ftl.lerp(btl, 0.12) + Vector3(0.03, 0.002, 0)
	var b := ftr.lerp(btr, 0.12) + Vector3(-0.03, 0.002, 0)
	var c := ftr.lerp(btr, 0.32) + Vector3(-0.03, 0.002, 0)
	var d := ftl.lerp(btl, 0.32) + Vector3(0.03, 0.002, 0)
	var t := PackedVector3Array()
	_quad(t, a, b, c, d)
	_tri_mesh(t, _m_hud_glow)
	# Kantenleiste vorne oben
	var e := PackedVector3Array()
	_quad(e, ftl + Vector3(0, 0.001, 0.001), ftr + Vector3(0, 0.001, 0.001), ftr + Vector3(0, -0.006, 0.002), ftl + Vector3(0, -0.006, 0.002))
	_tri_mesh(e, _m_frame)


# ---------------------------------------------------------------------------------------------
#  Combiner-Glas mit dünnem Rahmen
# ---------------------------------------------------------------------------------------------
func _build_glass() -> void:
	var zb := 0.86
	var zt := 0.80
	var half := _x(0.755, zb)   # Unterkante reicht etwa von 24,5 % bis 75,5 % der Bildbreite
	var yb := -0.31 + _dy
	var yt := _y(0.085, zt)
	var tl := Vector3(-half, yt, -zt)
	var tr := Vector3(half, yt, -zt)
	var br := Vector3(half, yb, -zb)
	var bl := Vector3(-half, yb, -zb)
	glass_corners = PackedVector3Array([tl, tr, br, bl])
	# Glasfläche (fein unterteilt, damit der Glanzverlauf nicht knickt)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 8
	for j in n:
		for i in n:
			var quad := []
			for c in [[i, j], [i + 1, j], [i + 1, j + 1], [i, j + 1]]:
				var u := float(c[0]) / n
				var v := float(c[1]) / n
				quad.append([Vector2(u, v), tl.lerp(tr, u).lerp(bl.lerp(br, u), v)])
			for idx in [0, 1, 2, 0, 2, 3]:
				st.set_normal(Vector3(0, 0, 1))
				st.set_uv(quad[idx][0])
				st.add_vertex(quad[idx][1])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var gm := ShaderMaterial.new()
	gm.shader = load("res://shaders/hud_combiner.gdshader")
	mi.material_override = gm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.sorting_offset = 1.0
	add_child(mi)
	# Rahmen: seitliche Holme und obere Leiste
	var fw := 0.013
	for side: float in [-1.0, 1.0]:
		var top: Vector3 = tl if side < 0.0 else tr
		var bot: Vector3 = bl if side < 0.0 else br
		_frame_boxes.append({"c": _box_corners(_bar(bot + Vector3(side * fw * 0.5, -0.03, 0.0), top + Vector3(side * fw * 0.5, fw * 0.5, 0.0), fw, 0.016, _m_frame)), "down": true})
		# Fuß auf dem Blendschutz
		_frame_boxes.push_front({"c": _box_corners(_bar(bot + Vector3(side * 0.012, -0.045, 0.01), bot + Vector3(side * 0.012, 0.03, 0.0), 0.034, 0.03, _m_frame)), "down": true})
	_frame_boxes.append({"c": _box_corners(_bar(tl + Vector3(-fw, fw * 0.5, 0.0), tr + Vector3(fw, fw * 0.5, 0.0), fw, 0.016, _m_frame)), "down": false})   # zuletzt


## Acht Ecken eines Stabs aus _bar (lokale Cockpit-Koordinaten) – für die Sichtstörung (ViewFX).
func _box_corners(mi: MeshInstance3D) -> PackedVector3Array:
	var bm := mi.mesh as BoxMesh
	var h := bm.size * 0.5
	var out := PackedVector3Array()
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				out.append(mi.transform * Vector3(h.x * sx, h.y * sy, h.z * sz))
	return out


## Stab zwischen zwei Punkten (Breite quer zur Blickrichtung, Dicke entlang der Blickrichtung).
func _bar(a: Vector3, b: Vector3, width: float, thick: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	var len := a.distance_to(b)
	bm.size = Vector3(width, len, thick)
	mi.mesh = bm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var y := (b - a).normalized()
	var mid := (a + b) * 0.5
	var z := (-mid).normalized()
	var x := y.cross(z).normalized()
	z = x.cross(y).normalized()
	mi.transform = Transform3D(Basis(x, y, z), mid)
	add_child(mi)
	return mi


# ---------------------------------------------------------------------------------------------
#  Kanzelrahmen: Bogen über den Seiten (oben weitgehend außerhalb des Bildes)
# ---------------------------------------------------------------------------------------------
func _build_canopy() -> void:
	# Linienzug in Bildschirmanteilen: linker Holm (leicht nach innen geneigt) → abgerundete Ecke →
	# obere Strebe knapp über dem Bildrand → rechte Ecke → rechter Holm
	var half := PackedVector2Array()
	var bot := Vector2(0.006, 0.93)
	var top := Vector2(0.05, 0.13)
	for i in 8:
		half.append(bot.lerp(top, float(i) / 8.0))
	var ctrl := Vector2(0.068, -0.03)
	var end := Vector2(0.2, -0.036)
	for i in 10:
		var u := float(i) / 10.0
		half.append(top.lerp(ctrl, u).lerp(ctrl.lerp(end, u), u))
	var pts2 := PackedVector2Array(half)
	pts2.append(end)
	for i in range(half.size() - 1, -1, -1):
		pts2.append(Vector2(1.0 - half[i].x, half[i].y))
	var depth := 0.98
	var pts := PackedVector3Array()
	var seal := PackedVector3Array()
	for p in pts2:
		var q := _sp(p.x, p.y, depth)
		pts.append(q)
		# Dichtung an der Innenkante (zur Bildmitte hin), etwas näher am Auge
		var inward := (Vector3(0.0, 0.0, q.z) - q).normalized()
		seal.append((q + inward * 0.025) * 0.97)
	_sweep(pts, 0.05, 0.07, _m_frame)
	_sweep(seal, 0.006, 0.012, _m_seal)
	# Umriss für die Sichtstörung: Rahmen (halbe Breite 2,5 cm) und Dichtung innen, mit etwas Rand
	var outer := PackedVector3Array()
	var inner := PackedVector3Array()
	for q in pts:
		var inward := (Vector3(0.0, 0.0, q.z) - q).normalized()
		outer.append(q - inward * 0.035)
		inner.append(q + inward * 0.036)
	inner.reverse()
	_canopy_band = outer
	_canopy_band.append_array(inner)


## Getönter Streifen oben in der Kanzel (Blendschutz für die oberen Anzeigen).
func _build_visor() -> void:
	var d := 0.96
	var tl := _sp(-0.05, -0.05, d)
	var tr := _sp(1.05, -0.05, d)
	var br := _sp(1.05, 0.3, d)
	var bl := _sp(-0.05, 0.3, d)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var uv := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	var pts := [tl, tr, br, bl]
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_normal(Vector3(0, 0, 1))
		st.set_uv(uv[i])
		st.add_vertex(pts[i])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/hud_visor.gdshader")
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.sorting_offset = -1.0
	add_child(mi)


## Profil (Rechteck width × thick) entlang einer Punktfolge ziehen.
func _sweep(pts: PackedVector3Array, width: float, thick: float, mat: Material) -> void:
	var t := PackedVector3Array()
	var prev := []
	for i in pts.size():
		var p := pts[i]
		var tan := (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var view := (-p).normalized()
		var side := tan.cross(view).normalized()
		var depth_dir := side.cross(tan).normalized()
		var ring := [p - side * width * 0.5 + depth_dir * thick * 0.5, p + side * width * 0.5 + depth_dir * thick * 0.5,
			p + side * width * 0.5 - depth_dir * thick * 0.5, p - side * width * 0.5 - depth_dir * thick * 0.5]
		if not prev.is_empty():
			for k in 4:
				_quad(t, prev[k], ring[k], ring[(k + 1) % 4], prev[(k + 1) % 4])
		prev = ring
	_tri_mesh(t, mat, 4.0)


# ---------------------------------------------------------------------------------------------
#  MFDs (SubViewport-Texturen auf Bildschirmflächen)
# ---------------------------------------------------------------------------------------------
func _build_mfds() -> void:
	# Seitliche MFDs bei schmaleren Bildformaten etwas schmaler (Platz bis zum Mittelpult)
	# Seitliche MFDs unter der Hohlkehle des Blendschutzes (kompakte Konsole: etwas kleiner)
	var hw := 0.1125 * clampf(_aspect / (16.0 / 9.0), 0.72, 1.0)
	var px := Vector2i(int(round(380.0 * hw / 0.1125)), 202)
	mfd_nav = _mfd(CockpitMFD.Page.NAV, px, 0.33, 0.943, hw, 0.06, _panel_p, _panel_n)
	mfd_link = _mfd(CockpitMFD.Page.LINK, px, 0.67, 0.943, hw, 0.06, _panel_p, _panel_n)
	# Mittleres MFD auf dem Pult: auf Planeten (Scanner) etwas größer, im All kleiner, damit es ganz ins Bild passt
	if combat is PlanetCombat:
		mfd_center = _mfd(CockpitMFD.Page.CENTER, Vector2i(300, 266), 0.5, STACK_SY_PLANET + 0.112, 0.101, 0.0895, _stack_p, _stack_n, true)
	else:
		mfd_center = _mfd(CockpitMFD.Page.CENTER, Vector2i(300, 266), 0.5, STACK_SY_SPACE + 0.1, 0.0905, 0.08, _stack_p, _stack_n, true)


## MFD aufbauen: Bildschirmmitte beim Bildpunkt (sx, sy) auf der Ebene (p0, n), halbe Breite/Höhe (m).
func _mfd(page: int, px: Vector2i, sx: float, sy: float, hw: float, hh: float, p0: Vector3, n: Vector3, side_buttons := false) -> CockpitMFD:
	var vp := SubViewport.new()
	# Inhalt rechnet in px (HUD-Pixeln), gerendert wird in echten Bildpunkten → scharf bei 720p wie bei 4K
	vp.size_2d_override = px
	vp.size_2d_override_stretch = true
	vp.size = Vector2i((Vector2(px) * _res).round())
	vp.disable_3d = true
	vp.transparent_bg = false
	vp.gui_disable_input = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	_viewports.append(vp)
	var page_ctl := CockpitMFD.new()
	page_ctl.combat = combat
	page_ctl.page = page
	page_ctl.size = Vector2(px)
	vp.add_child(page_ctl)
	var center := _on_plane(sx, sy, p0, n)
	var b := _plane_basis(n)
	# Rahmen (Bezel) mit Tasten
	_plane_box(center, b, hw * 2.0 + (0.05 if side_buttons else 0.026), hh * 2.0 + (0.022 if side_buttons else 0.04), 0.012, _m_bezel)
	var nb := 5
	for i in nb:
		var f := (float(i) + 0.5) / nb * 2.0 - 1.0
		for s: float in [-1.0, 1.0]:
			if side_buttons:
				_plane_box(center + b.x * s * (hw + 0.0135) + b.y * f * hh * 0.8, b, 0.011, 0.014, 0.005, _m_button, 0.012)
			else:
				_plane_box(center + b.y * s * (hh + 0.012) + b.x * f * hw * 0.84, b, 0.024, 0.009, 0.005, _m_button, 0.012)
	# Bildschirm
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(hw * 2.0, hh * 2.0)
	mi.mesh = q
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/hud_mfd.gdshader")
	sm.set_shader_parameter("screen_tex", vp.get_texture())
	sm.set_shader_parameter("flicker", 1.0 if _t < POWER_TIME else 0.0)
	_mfd_mats.append(sm)
	mi.material_override = sm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.transform = Transform3D(b, center + b.z * 0.0128)
	add_child(mi)
	return page_ctl


# ---------------------------------------------------------------------------------------------
#  Warnlampen (Annunciator) links und rechts auf der Instrumententafel
# ---------------------------------------------------------------------------------------------
const LAMPS_L := [["TREFFER", "hit"], ["ENERGIE", "energy"], ["GESCHOSS", "incoming"],
	["ZIEL", "lock"], ["IONEN", "ion"], ["LASER", "laser"]]
const LAMPS_R := [["BOMBEN", "bombs"], ["ANDOCKEN", "dock"], ["DATENLINK", "link"],
	["SENSOREN", "sensors"], ["AUTO", "auto"], ["KARTE", "map"]]


func _build_lamps() -> void:
	var font := Assets.font("body_bold")
	var b := _plane_basis(_panel_n)
	for side in [0, 1]:
		var list: Array = LAMPS_L if side == 0 else LAMPS_R
		var x0 := 0.105 if side == 0 else 0.785
		for i in list.size():
			var col := i % 3
			var row := i / 3
			var c := _on_plane(x0 + col * 0.055, 0.905 + row * 0.055, _panel_p, _panel_n)
			_plane_box(c, b, 0.062, 0.034, 0.008, _m_bezel)
			var lm := StandardMaterial3D.new()
			lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			lm.albedo_color = Color(0.03, 0.035, 0.04)
			lm.disable_fog = true
			_mark_stencil(lm)
			_plane_box(c, b, 0.055, 0.027, 0.002, lm, 0.008)
			var lbl := Label3D.new()
			lbl.text = list[i][0]
			lbl.font = font
			lbl.font_size = 40
			lbl.pixel_size = 0.00027
			lbl.outline_size = 0
			lbl.shaded = false
			lbl.double_sided = false
			lbl.modulate = Color(0.25, 0.28, 0.3)
			lbl.transform = Transform3D(b, c + b.z * 0.0105)
			add_child(lbl)
			_lamps.append({"id": list[i][1], "mat": lm, "label": lbl})


func _update_lamps() -> void:
	var blink := fmod(_t, 0.5) < 0.28
	for l in _lamps:
		var on := Color(0, 0, 0, 0)   # a = 0: aus
		match l.id:
			"hit":
				if _hit > 0.0:
					on = UITheme.RED
			"energy":
				if GameState.energy < Config.energy_low_warning:
					on = UITheme.RED if blink else Color(0, 0, 0, 0)
				elif GameState.energy < 50.0:
					on = UITheme.AMBER
			"incoming":
				if not combat.shots.incoming_heavy().is_empty() and blink:
					on = UITheme.RED
			"lock":
				if combat.locked and combat.fire_enabled:
					on = UITheme.GREEN
			"ion":
				if combat.ion_charge() >= 1.0:
					on = UITheme.GREEN
				elif blink:
					on = UITheme.AMBER
			"laser":
				if combat.weapon == CombatBase.Weapon.LASER and combat.fire_enabled:
					on = UITheme.CYAN
			"bombs":
				if GameState.has_damage("bombs"):
					on = UITheme.RED   # Systemschaden: Bombenschacht klemmt (Dauerlicht)
				elif combat.bombs_allowed():
					on = UITheme.AMBER if GameState.bombs > 0 else (UITheme.RED if blink else Color(0, 0, 0, 0))
			"dock":
				if combat is SpaceCombat and (combat as SpaceCombat).is_docking():
					on = UITheme.CYAN if (combat as SpaceCombat).phase == SpaceCombat.Phase.DOCKED or blink else Color(0, 0, 0, 0)
			"link":
				if GameState.has_damage("comms"):
					on = UITheme.RED   # Systemschaden: Kommunikation gestört
				elif mfd_link and mfd_link.fresh_message():
					on = UITheme.CYAN if blink else Color(0, 0, 0, 0)
			"sensors":
				if GameState.has_damage("screen"):
					on = UITheme.RED   # Systemschaden: Sichtsystem gestört
				elif combat is PlanetCombat:
					on = UITheme.GREEN   # Planetenscanner aktiv (wie die Lampe SCANNER bis 0.11.0)
			"auto":
				if Config.auto_weapon_switch and not combat.bombs_allowed():
					on = UITheme.GREEN
			"map":
				if combat.map_allowed() and not (combat is SpaceCombat and (combat as SpaceCombat).mode == SpaceCombat.Mode.ORBIT and not (combat as SpaceCombat).orbit_done):
					on = Color(0.5, 0.6, 0.66)
		var lm: StandardMaterial3D = l.mat
		var lbl: Label3D = l.label
		if on.a > 0.0:
			lm.albedo_color = Color(on.r * 0.22, on.g * 0.22, on.b * 0.22)
			lbl.modulate = Color(on.r * 1.6, on.g * 1.6, on.b * 1.6)
		else:
			lm.albedo_color = Color(0.03, 0.035, 0.04)
			lbl.modulate = Color(0.2, 0.22, 0.24)


# ---------------------------------------------------------------------------------------------
#  Licht im Cockpit (geringe Reichweite: beleuchtet nur das Cockpit)
# ---------------------------------------------------------------------------------------------
func _build_lights() -> void:
	_fill = OmniLight3D.new()
	_fill.light_color = Color(0.55, 0.72, 0.85)
	_fill.light_energy = 0.55
	_fill.omni_range = 2.4
	_fill.omni_attenuation = 1.2
	_fill.shadow_enabled = false
	_fill.position = Vector3(0.0, 0.25, -0.15)
	add_child(_fill)
	var under := OmniLight3D.new()
	under.light_color = Color(0.35, 0.8, 0.75)
	under.light_energy = 0.35
	under.omni_range = 0.9
	under.shadow_enabled = false
	under.position = Vector3(0.0, -0.36, -0.5)
	add_child(under)
