class_name CockpitHUD
extends HudBase
## =============================================================================================
##  Cockpit mit Kampfjet-Head-Up-Display (Optionen: "Cockpit-Ansicht"; aus = ClassicHUD).
##  Inhalt wie bisher [ORIGINAL]: Waffenanzeige, Energieanzeige, auf Planeten Scanner; Zielanzeige:
##  Bordlaser = Rechteck, oben/unten ~80 % offen (zwei Klammern); Ionen-Kanone = Fadenkreuz.
##  Aufbau:
##   - CockpitRig (3D, an der Kamera): Konsole mit MFDs (Scanner, Andocken, Navigation, Datenlink),
##     Warnlampen, Kanzelrahmen und das Combiner-Glas – federt bei Drehungen leicht nach.
##   - Symbolik als gebündeltes Licht (Shader hud_light): dünne Leuchtlinien, eine HUD-Farbfamilie,
##     semantische Akzentfarben bleiben (Energie grün/gelb/rot, Zerstörerfarben, Flaggschiff rosa …).
##       Glas-Ebene: Visier, Neigungsleiter, Kursband, Energie-/Waffenskala, Punkte, Lage, Meldungen –
##                   maskiert auf das (nachfedernde) Glas, die Lage der Symbole bleibt aber fest.
##       Helm-Ebene: Zielmarken, Pfeile zu Gegnern außerhalb der Sicht, Punkte, Bombenbahn –
##                   überall im Blickfeld, exakt auf den Weltpositionen.
## =============================================================================================

const HUD_COL := Color(0.45, 1.0, 0.62)       ## Grundfarbe der Symbolik (Phosphorgrün)
const LOCK_COL := Color(0.86, 1.0, 0.36)      ## Laser-Lock
const ION_COL := Color(0.87, 0.8, 1.0)        ## Ionen-Visier
const ION_LOCK_COL := Color(1.0, 0.74, 0.95)
const SHADE := 0.24       ## dunkler Kontrastsaum unter Leuchtlinien (wirkt nur vor hellem Himmel/Explosionen)
const TEXT_SHADE := 0.4   ## … unter Leuchtschrift
const BOOT_TIME := 0.7    ## Einschalt-Sweep der Symbolik beim Szenenstart (s)
const _G := [&"g0", &"g1", &"g2", &"g3"]   ## Shader-Parameter: Glasecken
const _S := [&"s0", &"s1", &"s2", &"s3"]   ## Shader-Parameter: Mittelpult

## shake_offset (HudBase) wird hier nicht verwendet: die Symbolik bleibt ruhig (kollimiert), das Cockpit wackelt
var rig: CockpitRig
var _fx_layer: Control      ## Laser, Linsenreflexe (Welt-Effekte, verschwinden hinter der Konsole)
var _glass_layer: Control   ## Combiner-Symbolik
var _hmd_layer: Control     ## Helm-Symbolik
var _alert_layer: Control   ## rote Trefferkante
var _glass_mat: ShaderMaterial
var _hmd_mat: ShaderMaterial
var _fx_mat: ShaderMaterial
var _ci: CanvasItem         ## aktuelle Zeichenfläche der Hilfsfunktionen
var _lip := PackedVector2Array([Vector2(0, 870), Vector2(1920, 870)])
var _stack := PackedVector2Array()
var _impact_visible := false


func _ready() -> void:
	super()
	var light: Shader = load("res://shaders/hud_light.gdshader")
	_fx_mat = ShaderMaterial.new()
	_fx_mat.shader = light
	_fx_mat.set_shader_parameter("halo_add", 0.85)
	_fx_mat.set_shader_parameter("use_mask", true)
	_fx_mat.set_shader_parameter("feather", 1.5)
	_glass_mat = ShaderMaterial.new()
	_glass_mat.shader = light
	_glass_mat.set_shader_parameter("use_mask", true)
	_hmd_mat = ShaderMaterial.new()
	_hmd_mat.shader = light
	_fx_layer = _make_layer(_draw_fx, _fx_mat)
	_glass_layer = _make_layer(_draw_glass, _glass_mat)
	_hmd_layer = _make_layer(_draw_hmd, _hmd_mat)
	_alert_layer = _make_layer(_draw_alert, null)
	if combat and combat.camera:
		rig = CockpitRig.new()
		rig.name = "CockpitRig"
		combat.camera.add_child(rig)
		rig.setup(combat)


func _exit_tree() -> void:
	# das Cockpit hängt an der Kamera: beim Umschalten auf die klassische Ansicht mit entfernen
	if is_instance_valid(rig):
		rig.queue_free()


func _make_layer(cb: Callable, mat: Material) -> Control:
	var c := Control.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.material = mat
	c.draw.connect(cb)
	add_child(c)
	return c


func _update(_delta: float) -> void:
	_update_projection()
	_impact_visible = _calc_impact_visible()
	# schwerer Treffer: Projektor dunkelt kurz ab und erholt sich weich (fotosicher: kein Flackern)
	var flick := 1.0
	if _hit_heavy and _hit_t < 0.35:
		flick = 0.55 + 0.45 * smoothstep(0.0, 0.35, _hit_t)
	_glass_mat.set_shader_parameter("intensity", flick)
	_hmd_mat.set_shader_parameter("intensity", flick)
	var boot := clampf(_t / BOOT_TIME, 0.0, 1.0)
	_glass_mat.set_shader_parameter("boot", boot)
	_hmd_mat.set_shader_parameter("boot", boot)
	_fx_layer.queue_redraw()
	_glass_layer.queue_redraw()
	_hmd_layer.queue_redraw()
	_alert_layer.queue_redraw()


## Glas- und Pultumriss aus dem 3D-Cockpit auf den Bildschirm projizieren (Maske, Laser-Ausblendung).
func _update_projection() -> void:
	if rig == null or rig.glass_corners.size() < 4:
		return
	# Die Glas-Symbolik steht fest → Maske in Ruhelage (das Nachfedern um bis zu ~50 px darf Lage, Waffenblock
	# und Punkte nicht anschneiden). Laser, Linsenreflexe und Bombenbahn folgen dem echten Cockpit (_lip/_stack).
	var g := rig.project_quad_rest(rig.glass_corners)
	var gs := rig.project_quad_rest(rig.stack_corners)
	_stack = rig.project_quad(rig.stack_corners)
	_lip = rig.project_quad(rig.lip_points)
	_glass_mat.set_shader_parameter("view_size", size)
	_fx_mat.set_shader_parameter("view_size", size)
	# Welt-Effekte (Laser) nur oberhalb der Blendschutzkante: Viereck vom oberen Rand bis zur Kante
	var d := (_lip[1] - _lip[0]).normalized()
	var above := [Vector2(-4000.0, -4000.0), Vector2(6000.0, -4000.0), _lip[1] + d * 4000.0, _lip[0] - d * 4000.0]
	for i in 4:
		_glass_mat.set_shader_parameter(_G[i], g[i])
		_glass_mat.set_shader_parameter(_S[i], gs[i])
		_fx_mat.set_shader_parameter(_G[i], above[i])
		_fx_mat.set_shader_parameter(_S[i], _stack[i])


# ---------------------------------------------------------------------------------------------
#  Schnittstelle
# ---------------------------------------------------------------------------------------------
func _on_hit_cue(heavy: bool) -> void:
	if rig:
		rig.on_player_hit(heavy)


# ---------------------------------------------------------------------------------------------
#  Zeichenhilfen (Leuchtlinien: schwacher breiter Halo + heller Kern)
# ---------------------------------------------------------------------------------------------
func _core(col: Color) -> Color:
	return Color(col.lerp(Color(1, 1, 1), 0.25), col.a)


func _gl(a: Vector2, b: Vector2, col: Color, w := 1.6) -> void:
	_ci.draw_line(a, b, Color(0, 0, 0, col.a * SHADE), w + 3.5, true)
	_ci.draw_line(a, b, Color(col, col.a * 0.08), w + 7.0, true)
	_ci.draw_line(a, b, Color(col, col.a * 0.2), w + 2.6, true)
	_ci.draw_line(a, b, _core(col), w, true)


func _garc(c: Vector2, r: float, a0: float, a1: float, col: Color, w := 1.6, pts := 48) -> void:
	_ci.draw_arc(c, r, a0, a1, pts, Color(0, 0, 0, col.a * SHADE), w + 3.5, true)
	_ci.draw_arc(c, r, a0, a1, pts, Color(col, col.a * 0.08), w + 7.0, true)
	_ci.draw_arc(c, r, a0, a1, pts, Color(col, col.a * 0.2), w + 2.6, true)
	_ci.draw_arc(c, r, a0, a1, pts, _core(col), w, true)


func _gpoly(pts: PackedVector2Array, col: Color, w := 1.6) -> void:
	_ci.draw_polyline(pts, Color(0, 0, 0, col.a * SHADE), w + 3.5, true)
	_ci.draw_polyline(pts, Color(col, col.a * 0.08), w + 7.0, true)
	_ci.draw_polyline(pts, Color(col, col.a * 0.2), w + 2.6, true)
	_ci.draw_polyline(pts, _core(col), w, true)


func _gbox(r: Rect2, col: Color, w := 1.4) -> void:
	_gpoly(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), r.position]), col, w)


func _gdot(p: Vector2, r: float, col: Color) -> void:
	_ci.draw_circle(p, r + 1.6, Color(0, 0, 0, col.a * SHADE), true, -1.0, true)
	_ci.draw_circle(p, r + 3.5, Color(col, col.a * 0.12), true, -1.0, true)
	_ci.draw_circle(p, r, _core(col), true, -1.0, true)


## Leuchtschrift: dunkler Kontrastsaum (nur vor hellem Himmel sichtbar), farbiger Halo, heller Kern.
func _gtext(pos: Vector2, s: String, f: Font, fs: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	var halo := maxi(int(fs * 0.22), 3)
	_ci.draw_string_outline(f, pos, s, align, width, fs, halo + 3, Color(0, 0, 0, col.a * TEXT_SHADE))
	_ci.draw_string_outline(f, pos, s, align, width, fs, halo, Color(col, col.a * 0.13))
	_ci.draw_string(f, pos, s, align, width, fs, _core(col))


## Text in die Breite einpassen (kleiner, notfalls zweizeilig).
func _gtext_fit(pos: Vector2, s: String, f: Font, fs: int, col: Color, width: float, min_fs := 18) -> void:
	var n := fs
	while n > min_fs and f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, n).x > width:
		n -= 1
	if f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, n).x <= width:
		_gtext(pos, s, f, n, col, HORIZONTAL_ALIGNMENT_CENTER, width)
		return
	var halo := maxi(int(n * 0.22), 3)
	_ci.draw_multiline_string_outline(f, pos, s, HORIZONTAL_ALIGNMENT_CENTER, width, n, 2, halo + 3, Color(0, 0, 0, col.a * TEXT_SHADE))
	_ci.draw_multiline_string_outline(f, pos, s, HORIZONTAL_ALIGNMENT_CENTER, width, n, 2, halo, Color(col, col.a * 0.13))
	_ci.draw_multiline_string(f, pos, s, HORIZONTAL_ALIGNMENT_CENTER, width, n, 2, _core(col))


## Liegt ein Bildpunkt hinter der Konsole (Blendschutzkante bzw. Mittelpult)?
func _behind_console(p: Vector2, margin := 0.0) -> bool:
	if _side_of_lip(p) > -margin * (_lip[1].x - _lip[0].x):
		return true
	if _stack.size() == 4 and p.x > _stack[0].x - margin and p.x < _stack[1].x + margin:
		var k := clampf((p.x - _stack[0].x) / maxf(_stack[1].x - _stack[0].x, 1.0), 0.0, 1.0)
		return p.y > lerpf(_stack[0].y, _stack[1].y, k) - margin
	return false


## > 0: unterhalb der Blendschutzkante
func _side_of_lip(p: Vector2) -> float:
	var a := _lip[0]
	var b := _lip[1]
	return (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)


# ---------------------------------------------------------------------------------------------
#  Welt-Effekte (unter dem Glas): Laser, Linsenreflexe
# ---------------------------------------------------------------------------------------------
func _draw_fx() -> void:
	if combat == null or combat.camera == null:
		return
	_ci = _fx_layer
	_draw_lasers()
	_draw_lens_flare(size)


## Laserstrahlen als verjüngte 2D-Lichtlinien von den Bordkanonen zum Puls (Arcade-Look);
## der Anfang verschwindet hinter der Blendschutzkante.
func _draw_lasers() -> void:
	var cam := combat.camera
	for s in combat.shots.player_shots:
		if s.kind != ShotSystem.Kind.LASER:
			continue
		for bm in s.beams:
			var k: float = bm[2]
			if k >= 1.5:
				continue
			var t3: Vector3 = bm[0]
			var h3: Vector3 = bm[1]
			if cam.is_position_behind(t3) or cam.is_position_behind(h3):
				continue
			var tp := cam.unproject_position(t3)
			var hp := cam.unproject_position(h3)
			if (hp - tp).length() < 1.0:
				continue
			var fade := clampf(1.5 - k, 0.0, 1.0)
			var w0 := 7.0 * fade + 1.0
			var w1 := 1.6
			var st := _side_of_lip(tp)
			var sh := _side_of_lip(hp)
			if sh >= 0.0:
				continue
			if st > 0.0:
				var f := st / (st - sh)
				tp = tp.lerp(hp, f)
				w0 = lerpf(w0, w1, f)
			var n := (hp - tp).normalized().orthogonal()
			for layer in [[3.5, 0.12], [1.8, 0.3], [1.0, 1.0]]:
				var m: float = layer[0]
				var col := Color(0.45, 0.92, 1.0, float(layer[1]) * fade) if m > 1.0 else Color(0.85, 1.0, 1.0, fade)
				var poly := PackedVector2Array([tp + n * w0 * m, hp + n * w1 * m, hp - n * w1 * m, tp - n * w0 * m])
				_ci.draw_colored_polygon(poly, col)


func _draw_lens_flare(vp: Vector2) -> void:
	if combat.sun == null:
		return
	var cam := combat.camera
	var dir := combat.sun.global_transform.basis.z
	var w := cam.global_position + dir * 5000.0
	if cam.is_position_behind(w):
		return
	var sp := cam.unproject_position(w)
	if not Rect2(Vector2.ZERO, vp).grow(200.0).has_point(sp):
		return
	var c := vp * 0.5
	var fade := clampf(1.0 - sp.distance_to(c) / (vp.x * 0.75), 0.0, 1.0)
	var axis := c - sp
	var ghosts := [[0.35, 26.0, Color(1.0, 0.8, 0.5)], [0.6, 14.0, Color(0.5, 0.8, 1.0)], [0.9, 48.0, Color(0.6, 0.5, 1.0)], [1.3, 20.0, Color(1.0, 0.6, 0.4)], [1.7, 70.0, Color(0.4, 1.0, 0.8)]]
	for g in ghosts:
		var gp: Vector2 = sp + axis * float(g[0])
		if _behind_console(gp):
			continue
		var gc: Color = g[2]
		_ci.draw_circle(gp, g[1], Color(gc, 0.05 * fade), true, -1.0, true)
		_ci.draw_arc(gp, g[1], 0, TAU, 40, Color(gc, 0.07 * fade), 2.0, true)


# ---------------------------------------------------------------------------------------------
#  Combiner-Glas
# ---------------------------------------------------------------------------------------------
func _draw_glass() -> void:
	if combat == null or combat.camera == null:
		return
	_ci = _glass_layer
	var c := (size * 0.5).round()
	if _t < BOOT_TIME:
		# Einschalt-Sweep: Fläche für den Leuchtstreifen (der Shader zeichnet ihn)
		_ci.draw_rect(Rect2(Vector2.ZERO, size), Color(HUD_COL, 0.004))
	_draw_pitch_ladder(c)
	_draw_heading(c)
	_draw_score(c)
	if not combat.dying and combat.fire_enabled:
		_draw_sight(c)
	_draw_energy_tape(c)
	_draw_weapon_tape(c)
	_draw_weapon_block(c)
	_draw_lage(c)
	if GameState.player_loc == GameState.Loc.STAR:
		_draw_star_gauge(c)
	_draw_messages(c)


## Neigungsleiter: Horizont und 10°-Sprossen, deckungsgleich mit der Welt (rollt mit der Kamera).
## Nur im mittleren Band des Glases sichtbar (blendet zu den Rändern hin aus).
func _draw_pitch_ladder(c: Vector2) -> void:
	var cam := combat.camera
	var fwd := -cam.global_transform.basis.z
	var fh := Vector3(fwd.x, 0.0, fwd.z)
	if fh.length() < 0.05:
		return
	fh = fh.normalized()
	var right := fh.cross(Vector3.UP).normalized()
	var pitch := rad_to_deg(asin(clampf(fwd.y, -1.0, 1.0)))
	var step := 10
	var lo := int(ceil((pitch - 25.0) / step)) * step
	var hi := int(floor((pitch + 25.0) / step)) * step
	var band := 225.0
	for deg in range(lo, hi + 1, step):
		if absi(deg) > 80:
			continue
		var r := deg_to_rad(deg)
		var wp := cam.global_position + (fh * cos(r) + Vector3.UP * sin(r)) * 1000.0
		if cam.is_position_behind(wp):
			continue
		var p := cam.unproject_position(wp)
		var fade := clampf((band - absf(p.y - c.y)) / 50.0, 0.0, 1.0)
		if fade <= 0.0:
			continue
		var q := cam.unproject_position(wp + right * 60.0)
		var d := (q - p).normalized()
		var up := Vector2(d.y, -d.x)   # zur Himmelsseite
		var col := Color(HUD_COL, 0.32 * fade)
		if deg == 0:
			for s: float in [-1.0, 1.0]:
				_gl(p + d * s * 105.0, p + d * s * 235.0, Color(HUD_COL, 0.5 * fade), 1.4)
			continue
		var gap := 90.0
		var len := 95.0
		for s: float in [-1.0, 1.0]:
			var a := p + d * s * gap
			var b := p + d * s * (gap + len)
			if deg > 0:
				_gl(a, b, col, 1.3)
			else:
				for k in 4:
					_gl(a.lerp(b, k / 4.0), a.lerp(b, k / 4.0 + 0.15), col, 1.3)
			var tick := -up * (10.0 if deg > 0 else -10.0)
			_gl(b, b + tick, col, 1.3)
			var lab := p + d * s * (gap + len + 22.0) + Vector2(-14, 6)
			_gtext(lab, "%d" % absi(deg), _f_mono, 15, col)


## Kursband oben (Kompasskurs der Blickrichtung).
func _draw_heading(c: Vector2) -> void:
	var f := -combat.camera.global_transform.basis.z
	var heading := fposmod(rad_to_deg(atan2(f.x, -f.z)), 360.0)
	var y := c.y - 300.0
	var ppd := 7.0   # Pixel pro Grad
	var half := 210.0
	var d0 := int(floor(heading - half / ppd))
	for d in range(d0, d0 + int(half * 2.0 / ppd) + 2):
		if d % 5 != 0:
			continue
		var x := c.x + (float(d) - heading) * ppd
		var off := absf(x - c.x) / half
		if off > 1.0:
			continue
		var a := 0.85 * (1.0 - off * off)
		var major := d % 10 == 0
		_gl(Vector2(x, y), Vector2(x, y - (11.0 if major else 6.0)), Color(HUD_COL, a), 1.3)
		if major and absf(x - c.x) > 44.0:
			_gtext(Vector2(x - 20, y - 16), "%02d" % (posmod(d, 360) / 10), _f_mono, 17, Color(HUD_COL, a), HORIZONTAL_ALIGNMENT_CENTER, 40)
	_gl(Vector2(c.x - half, y + 1), Vector2(c.x + half, y + 1), Color(HUD_COL, 0.25), 1.0)
	# Kursmarke und Ablesung
	var caret := PackedVector2Array([Vector2(c.x, y + 3), Vector2(c.x - 7, y + 13), Vector2(c.x + 7, y + 13), Vector2(c.x, y + 3)])
	_gpoly(caret, HUD_COL, 1.4)
	_gbox(Rect2(Vector2(c.x - 28, y - 36), Vector2(56, 24)), Color(HUD_COL, 0.85), 1.3)
	_gtext(Vector2(c.x - 28, y - 17), "%03d" % (int(round(heading)) % 360), _f_mono, 19, HUD_COL, HORIZONTAL_ALIGNMENT_CENTER, 56)


func _draw_score(c: Vector2) -> void:
	_gtext(Vector2(c.x - 200, c.y - 392), "%07d" % GameState.score, _f_mono, 38, Color(HUD_COL, 0.95), HORIZONTAL_ALIGNMENT_CENTER, 400)
	if GameState.running:
		_gtext(Vector2(c.x - 250, c.y - 364), "ZEIT %s  ·  STUFE %d" % [GameState.format_time(GameState.sim_time), GameState.level + 1], _f_mono, 18, Color(HUD_COL, 0.65), HORIZONTAL_ALIGNMENT_CENTER, 500)


# --- Visier ------------------------------------------------------------------------------------
func _draw_sight(c: Vector2) -> void:
	if combat.weapon == CombatBase.Weapon.BOMB:
		_draw_bomb_center(c)
		return
	var lock := combat.locked
	var appear := clampf(_weapon_t * 5.0, 0.0, 1.0)
	if combat.weapon == CombatBase.Weapon.LASER:
		var col := LOCK_COL if lock else HUD_COL
		var pulse := 1.0 + (0.06 * sin(_t * 18.0) if lock else 0.0)
		var w := 150.0 * pulse * (1.3 - 0.3 * appear)
		var h := 104.0 * pulse * (1.3 - 0.3 * appear)
		var stub := w * 0.1   # oben/unten ~80 % offen
		var tl := c + Vector2(-w, -h) * 0.5
		var tr := c + Vector2(w, -h) * 0.5
		var bl := c + Vector2(-w, h) * 0.5
		var br := c + Vector2(w, h) * 0.5
		col.a = appear
		var lw := 2.2 if lock else 1.8
		_gl(tl, bl, col, lw)
		_gl(tr, br, col, lw)
		_gl(tl, tl + Vector2(stub, 0), col, lw)
		_gl(bl, bl + Vector2(stub, 0), col, lw)
		_gl(tr, tr - Vector2(stub, 0), col, lw)
		_gl(br, br - Vector2(stub, 0), col, lw)
		_gdot(c, 2.2, col)
		if lock:
			_gtext(Vector2(c.x - 60, c.y + h * 0.5 + 24.0), "LOCK", _f_mono, 16, Color(col, 0.9 * appear), HORIZONTAL_ALIGNMENT_CENTER, 120)
	else:
		var col2 := ION_LOCK_COL if lock else ION_COL
		col2.a = appear
		var r := 44.0 * (1.25 - 0.25 * appear)
		_garc(c, r, 0, TAU, col2, 1.6, 64)
		for i in 4:
			var d := Vector2.RIGHT.rotated(i * PI * 0.5)
			_gl(c + d * 12.0, c + d * (r + 26.0), col2, 1.6)
		for i in 4:
			var d2 := Vector2.RIGHT.rotated(i * PI * 0.5 + PI * 0.25)
			_gl(c + d2 * (r - 6.0), c + d2 * (r + 4.0), col2, 1.3)
		var ch := combat.ion_charge()
		var ring_col := UITheme.GREEN if ch >= 1.0 else UITheme.AMBER
		_garc(c, r + 12.0, -PI * 0.5, -PI * 0.5 + TAU * ch, Color(ring_col, 0.9 * appear), 3.0, 64)
		if ch < 1.0:
			_gtext(c + Vector2(r + 22.0, -r - 8.0), "%.1f s" % ((1.0 - ch) * Config.ion_cooldown), _f_mono, 20, Color(UITheme.AMBER, appear))


## Bombenvisier, Teil auf dem Glas: Mittelmarke und Hinweise (Bahn und Aufschlag: Helm-Ebene).
func _draw_bomb_center(c: Vector2) -> void:
	var pc := combat as PlanetCombat
	if pc == null:
		return
	var appear := clampf(_weapon_t * 5.0, 0.0, 1.0)
	var col := _bomb_color(pc)
	col.a = appear
	_gl(c + Vector2(-30, 0), c + Vector2(-12, 0), col, 1.8)
	_gl(c + Vector2(30, 0), c + Vector2(12, 0), col, 1.8)
	_gl(c + Vector2(0, 12), c + Vector2(0, 26), col, 1.8)
	var locked := pc.impact_city >= 0 and not pc.impact_pending
	if _impact_visible:
		if locked and GameState.bombs > 0 and fmod(_t, 0.5) < 0.35:
			_gtext(c + Vector2(-200, 74), "ABWURF: FEUER", _f_disp, 22, col, HORIZONTAL_ALIGNMENT_CENTER, 400)
	else:
		# gleicher Platz wie "ABWURF: FEUER" (schließen sich aus) – c.y+116/146 gehört den kleinen Meldungen
		_gtext_fit(c + Vector2(-300, 74), "AUFSCHLAG UNTER DEM SCHIFF – VORWÄRTS FLIEGEN", _f_body, 22, col, 600)


## Aufschlagmarke im Bild und nicht von der Konsole verdeckt?
func _calc_impact_visible() -> bool:
	var pc := combat as PlanetCombat
	if pc == null or pc.weapon != CombatBase.Weapon.BOMB:
		return false
	var mp := _project(pc.impact_point)
	return mp.front and Rect2(Vector2.ZERO, size).has_point(mp.pos) and not _behind_console(mp.pos, 12.0)


func _bomb_color(pc: PlanetCombat) -> Color:
	if GameState.bombs <= 0:
		return Color(0.6, 0.6, 0.65)
	return UITheme.GREEN if pc.impact_city >= 0 and not pc.impact_pending else UITheme.AMBER


# --- Energie (Skala links) ---------------------------------------------------------------------
func _draw_energy_tape(c: Vector2) -> void:
	var e := GameState.energy
	var col := _energy_color()
	var low := e < Config.energy_low_warning
	var blink := low and fmod(_t, 0.6) < 0.3
	var x := c.x - 280.0
	var top := c.y - 150.0
	var bot := c.y + 150.0
	_gtext(Vector2(x - 130, top - 22), "ENERGIE", _f_mono, 17, Color(HUD_COL, 0.75), HORIZONTAL_ALIGNMENT_RIGHT, 136)
	_gl(Vector2(x, top), Vector2(x, bot), Color(HUD_COL, 0.55), 1.3)
	var ye := lerpf(bot, top, clampf(_energy_shown / Config.energy_max, 0.0, 1.0))
	for i in 11:
		var y := lerpf(bot, top, i / 10.0)
		var major := i % 2 == 0
		_gl(Vector2(x - (12.0 if major else 6.0), y), Vector2(x, y), Color(HUD_COL, 0.55), 1.2)
		if major and i > 0 and absf(y - ye) > 24.0:
			_gtext(Vector2(x - 58, y + 6), "%d" % (i * 10), _f_mono, 15, Color(HUD_COL, 0.5), HORIZONTAL_ALIGNMENT_RIGHT, 40)
	# Füllstand als schmaler Leuchtbalken
	_ci.draw_rect(Rect2(Vector2(x + 5, ye), Vector2(5, bot - ye)), Color(col, 0.16))
	_gl(Vector2(x + 7.5, bot), Vector2(x + 7.5, ye), Color(col, 0.9), 3.0)
	# Zeiger mit Ablesefeld
	var pcol := Color(1, 1, 1) if blink else col
	var box := Rect2(Vector2(x - 104, ye - 18), Vector2(84, 36))
	_gpoly(PackedVector2Array([box.position, Vector2(box.end.x, box.position.y), Vector2(box.end.x + 10, ye), Vector2(box.end.x, box.end.y), Vector2(box.position.x, box.end.y), box.position]), pcol, 1.5)
	_gtext(Vector2(box.position.x + 2, ye + 11), "%3d" % int(ceil(e)), _f_mono, 30, pcol, HORIZONTAL_ALIGNMENT_RIGHT, 58)
	_gtext(Vector2(box.position.x + 62, ye + 10), "%", _f_mono, 16, Color(pcol, 0.8))
	if low and not GameState.game_over:
		_gtext_fit(Vector2(c.x - 230, c.y + 176), "ENERGIE KRITISCH – STATION ANFLIEGEN!", _f_body, 21, Color(UITheme.RED, 0.6 + 0.4 * sin(_t * 8.0)), 460)


# --- Waffe (Skala rechts, Block unten rechts) --------------------------------------------------
func _weapon_mode() -> String:
	if combat.bombs_allowed():
		return "MANUELL (Q)"
	return "AUTO" if Config.auto_weapon_switch else "MANUELL (Q)"


func _draw_weapon_tape(c: Vector2) -> void:
	var x := c.x + 280.0
	var top := c.y - 150.0
	var bot := c.y + 150.0
	var flash := clampf(1.0 - _weapon_t * 2.0, 0.0, 1.0)
	_gtext(Vector2(x - 6, top - 22), "WAFFE", _f_mono, 17, Color(HUD_COL, 0.75))
	match combat.weapon:
		CombatBase.Weapon.LASER:
			# 12 Segmente, ungerade flackern beim Dauerfeuer (Hitze)
			var heat := clampf(combat.laser_cd / Config.laser_fire_interval, 0.0, 1.0)
			var col := UITheme.CYAN.lerp(Color(1, 1, 1), flash)
			for i in 12:
				var y := lerpf(bot, top, (i + 0.5) / 12.0)
				var a := 0.8 - 0.55 * heat * float(i % 2)
				_gl(Vector2(x, y), Vector2(x + 16, y), Color(col, a), 3.0)
		CombatBase.Weapon.ION:
			var ch := combat.ion_charge()
			var col2 := UITheme.GREEN if ch >= 1.0 else UITheme.AMBER
			_gl(Vector2(x, top), Vector2(x, bot), Color(ION_COL, 0.5), 1.2)
			_gl(Vector2(x + 16, top), Vector2(x + 16, bot), Color(ION_COL, 0.5), 1.2)
			var yc := lerpf(bot, top, ch)
			_ci.draw_rect(Rect2(Vector2(x + 3, yc), Vector2(10, bot - yc)), Color(col2, 0.22))
			_gl(Vector2(x + 8, bot), Vector2(x + 8, yc), Color(col2, 0.95), 4.0)
			var label := "BEREIT" if ch >= 1.0 else "%.1f s" % ((1.0 - ch) * Config.ion_cooldown)
			_gtext(Vector2(x + 26, yc + 7), label, _f_mono, 19, col2)
		CombatBase.Weapon.BOMB:
			var n := maxi(Config.bombs_max, 1)
			var empty := GameState.bombs <= 0
			for i in n:
				var y := lerpf(bot, top, (i + 0.5) / n)
				var r := Rect2(Vector2(x, y - 8), Vector2(16, 16))
				if i < GameState.bombs:
					_ci.draw_rect(r, Color(UITheme.AMBER, 0.75))
				_gbox(r, Color(UITheme.AMBER, 0.85 if i < GameState.bombs else 0.35), 1.2)
			var yb := lerpf(bot, top, clampf((GameState.bombs - 0.5) / n, 0.0, 1.0))
			_gtext(Vector2(x + 26, yb + 7), "%d / %d" % [GameState.bombs, Config.bombs_max], _f_mono, 19, UITheme.RED if empty else UITheme.AMBER)
			if GameState.has_damage("bombs"):
				_gtext(Vector2(x + 26, yb + 31), "KLEMMT", _f_mono, 17, UITheme.RED.lightened(0.2))


func _draw_weapon_block(c: Vector2) -> void:
	var x := c.x + 172.0
	var y := _blocks_y(c)
	var w := 280.0
	var flash := clampf(1.0 - _weapon_t * 2.0, 0.0, 1.0)
	_gtext(Vector2(x, y), "WAFFE · " + _weapon_mode(), _f_mono, 16, Color(HUD_COL, 0.65))
	var name := "BORDLASER"
	var col := UITheme.CYAN
	var sub := "gegen Fighter · Dauerfeuer"
	match combat.weapon:
		CombatBase.Weapon.LASER:
			if combat.bombs_allowed():
				sub = "gegen Fighter · Q: Bomben (%d)" % GameState.bombs
		CombatBase.Weapon.ION:
			name = "IONEN-KANONE"
			col = ION_COL
			var ch := combat.ion_charge()
			sub = ("BEREIT" if ch >= 1.0 else "LÄDT  %.1f s" % ((1.0 - ch) * Config.ion_cooldown)) + " · gegen Zerstörer/Flaggschiff"
		CombatBase.Weapon.BOMB:
			var empty := GameState.bombs <= 0
			name = "BOMBEN  %d / %d" % [GameState.bombs, Config.bombs_max]
			col = UITheme.RED if empty else UITheme.AMBER
			sub = "LEER – Nachladen an Station" if empty else ("BEREIT · Abwurf mit FEUER · Q: Laser" if combat.bomb_cd <= 0.0 else "LÄDT … · Q: Laser")
			if GameState.has_damage("bombs"):
				col = UITheme.RED
				sub = "KLEMMT – Reparatur an einer Station · Q: Laser"
	var nfs := 25
	while nfs > 18 and _f_disp.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, nfs).x > w:
		nfs -= 1
	_gtext(Vector2(x, y + 32), name, _f_disp, nfs, col.lerp(Color(1, 1, 1), flash))
	var sfs := 18
	while sfs > 14 and _f_body.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, sfs).x > w:
		sfs -= 1
	_gtext(Vector2(x, y + 58), sub, _f_body, sfs, Color(UITheme.TEXT, 0.85))


# --- Lage (unten links auf dem Glas) -----------------------------------------------------------
## Gemeinsame Höhe von Lage und Waffenblock: die Statuszeile (Grundlinie y + 58) bleibt ganz über der
## Oberkante des Mittelpults – auch wenn es beim Drehen nachfedert.
func _blocks_y(c: Vector2) -> float:
	var ped_top := size.y * (CockpitRig.STACK_SY_PLANET if combat is PlanetCombat else CockpitRig.STACK_SY_SPACE)
	return minf(c.y + 232.0, ped_top - 84.0)


func _draw_lage(c: Vector2) -> void:
	var x := c.x - 452.0
	var y := _blocks_y(c)
	_gtext(Vector2(x, y), "LAGE", _f_mono, 16, Color(HUD_COL, 0.65))
	var lines := _lage_lines()
	for i in lines.size():
		var l: Array = lines[i]
		var ly := y + 27.0 + i * 25.0
		_gtext(Vector2(x, ly), l[0], _f_body, 19, Color(UITheme.TEXT, 0.8))
		_gtext(Vector2(x + 132, ly), l[1], _f_mono, 21, l[2])
		if l.size() > 3:
			# Zerstörer als farbige Kästchen (wie auf der Karte) – die Farbe wird nicht ausgeschrieben
			var cols: Array = l[3]
			for k in cols.size():
				var r := Rect2(Vector2(x + 168 + k * 20, ly - 14), Vector2(14, 14))
				var dc: Color = UITheme.DESTROYER_COLORS[int(cols[k])]
				_ci.draw_rect(r.grow(2.0), Color(dc, 0.18))
				_ci.draw_rect(r, dc)


# --- Stern: Hitzeanzeige ------------------------------------------------------------------------
func _draw_star_gauge(c: Vector2) -> void:
	var heat := GameState.star_heat
	var hot := heat >= Config.star_heat_warning
	var col := UITheme.RED if hot else UITheme.AMBER
	var w := 420.0
	var x := c.x - w * 0.5
	var y := c.y + 64.0
	_gtext(Vector2(x, y), "HITZE", _f_mono, 18, col)
	_gtext(Vector2(x, y), "%d %%" % int(round(heat * 100.0)), _f_mono, 18, col, HORIZONTAL_ALIGNMENT_RIGHT, w)
	var segs := 20
	var sw := w / segs
	for i in segs:
		var on := (float(i) + 0.5) / segs <= heat
		var r := Rect2(Vector2(x + i * sw + 1.5, y + 8.0), Vector2(sw - 3.0, 12.0))
		if on:
			_ci.draw_rect(r, Color(col, 0.85))
		_gbox(r, Color(col, 0.45 if not on else 0.9), 1.0)
	var line := "VERGLÜHEN IN %.1f s" % GameState.star_time_left()
	if hot and fmod(_t, 0.5) < 0.32:   # langsames Blinken (2 Hz), kleine Fläche
		line = "SOFORT SPRINGEN – LEERTASTE"
	_gtext(Vector2(x, y + 44.0), line, _f_disp, 20, col, HORIZONTAL_ALIGNMENT_CENTER, w)


# --- Meldungen ---------------------------------------------------------------------------------
func _draw_messages(c: Vector2) -> void:
	var w := 860.0
	for m in _msgs:
		var a := clampf(m.t * 6.0, 0.0, 1.0) * clampf((m.dur - m.t) * 3.0, 0.0, 1.0)
		var scale_in := 1.0 + (1.0 - clampf(m.t * 6.0, 0.0, 1.0)) * 0.2
		var col: Color = m.color
		_gtext_fit(Vector2(c.x - w * 0.5, c.y - 242), m.title, _f_title, int(50 * scale_in), Color(col.lightened(0.2), a), w, 26)
		if m.sub != "":
			_gtext_fit(Vector2(c.x - w * 0.5, c.y - 202), m.sub, _f_body, 28, Color(UITheme.TEXT, a * 0.95), w, 22)
	for m in _small:
		var a2 := clampf(m.t * 8.0, 0.0, 1.0) * clampf((m.dur - m.t) * 4.0, 0.0, 1.0)
		_gtext_fit(Vector2(c.x - 330, c.y + 116), m.title, _f_disp, 27, Color(m.color, a2), 660, 18)
		if m.sub != "":
			_gtext_fit(Vector2(c.x - 330, c.y + 146), m.sub, _f_body, 21, Color(UITheme.TEXT, a2 * 0.9), 660, 16)
	if not combat.shots.incoming_heavy().is_empty() and fmod(_t, 0.5) < 0.32 and not combat.dying:
		_gtext(Vector2(c.x - 400, c.y - 104), "GESCHOSS IM ANFLUG – AUSWEICHEN!", _f_disp, 23, UITheme.RED, HORIZONTAL_ALIGNMENT_CENTER, 800)


# ---------------------------------------------------------------------------------------------
#  Helm-Ebene (überall im Blickfeld, exakt auf Weltpositionen)
# ---------------------------------------------------------------------------------------------
func _draw_hmd() -> void:
	if combat == null or combat.camera == null:
		return
	_ci = _hmd_layer
	_draw_header()
	if not combat.dying:
		_draw_target_marker()
		_draw_offscreen(size)
		if combat.fire_enabled and combat.weapon == CombatBase.Weapon.BOMB:
			_draw_bomb_path()
	_draw_popups()


## Kopfspalte links (spiegelbildlich zur Meldungsspalte rechts): Ort, Lage-Untertitel, Bedienhinweise.
## Steht immer an derselben Stelle – auch zum Nachlesen beim Einstieg.
func _draw_header() -> void:
	var x := size.x * 0.072
	var w := size.x * 0.148
	var y := 128.0
	var dl := _damage_line()
	if dl != "":
		# Systemschaden: ruhige rote Zeile über dem Ort (langsames, weiches Pulsieren)
		var dfs := 18
		while dfs > 13 and _f_disp.get_string_size(dl, HORIZONTAL_ALIGNMENT_LEFT, -1, dfs).x > w:
			dfs -= 1
		_gtext(Vector2(x, y - 34.0), dl, _f_disp, dfs, Color(UITheme.RED.lightened(0.25), 0.85 + 0.15 * sin(_t * 2.5)))
	var name := combat.location_name
	var nfs := 22
	while nfs > 15 and _f_disp.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, nfs).x > w:
		nfs -= 1
	_gtext(Vector2(x, y), name, _f_disp, nfs, Color(UITheme.CYAN, 0.95))
	y += 8.0
	var sub := combat.location_sub
	if sub != "":
		var alarm := sub.contains("!")
		var sfs := 19
		var col := UITheme.AMBER if alarm else UITheme.TEXT
		if alarm:
			col = Color(col, 0.7 + 0.3 * sin(_t * 6.0))
		var h := _f_body.get_multiline_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, w, sfs).y
		_gtext_multi(Vector2(x, y + 22.0), sub, _f_body, sfs, col, w)
		y += h + 10.0
	var hint := combat.hint_text.replace("  ·  ", " · ")
	if hint != "":
		_gtext_multi(Vector2(x, y + 22.0), hint, Assets.font("body_med"), 17, Color(UITheme.TEXT_DIM, 0.95), w)


## Mehrzeilige Leuchtschrift (links bündig, umbrochen).
func _gtext_multi(pos: Vector2, s: String, f: Font, fs: int, col: Color, width: float) -> void:
	var halo := maxi(int(fs * 0.22), 3)
	_ci.draw_multiline_string_outline(f, pos, s, HORIZONTAL_ALIGNMENT_LEFT, width, fs, -1, halo + 3, Color(0, 0, 0, col.a * TEXT_SHADE))
	_ci.draw_multiline_string_outline(f, pos, s, HORIZONTAL_ALIGNMENT_LEFT, width, fs, -1, halo, Color(col, col.a * 0.13))
	_ci.draw_multiline_string(f, pos, s, HORIZONTAL_ALIGNMENT_LEFT, width, fs, -1, _core(col))


## Bombenvisier, Helm-Teil: Flugbahn als Punktreihe bis zur Aufschlagmarke (die Marke liegt in 3D am Boden).
func _draw_bomb_path() -> void:
	var pc := combat as PlanetCombat
	if pc == null:
		return
	var appear := clampf(_weapon_t * 5.0, 0.0, 1.0)
	var col := _bomb_color(pc)
	var pts: Array = pc.bomb_trajectory(16)
	for i in pts.size():
		var pr := _project(pts[i])
		if pr.front and not _behind_console(pr.pos):
			_gdot(pr.pos, 3.0 - i * 0.08, Color(col, appear * (0.25 + 0.65 * float(i) / pts.size())))
	var mp := _project(pc.impact_point)
	if _impact_visible:
		var txt := ""
		if GameState.bombs <= 0:
			txt = "KEINE BOMBEN"
		elif pc.impact_pending:
			txt = "BOMBE UNTERWEGS"
		elif pc.impact_city >= 0:
			txt = "ZIEL: " + String(pc.planet.city_names[pc.impact_city]).to_upper()
		else:
			txt = "%d m" % int(Vector2(pc.impact_point.x, pc.impact_point.z).distance_to(pc.player_xz()))
		_gtext(mp.pos + Vector2(46, 8), txt, _f_disp, 20, Color(col, appear))


func _draw_target_marker() -> void:
	var e := combat.aim_target
	if e == null or not is_instance_valid(e) or not e.alive:
		return
	var ap := e.aim_point()   # Mitte der Trefferzone (beim Zerstörer die Schildblase)
	var p := _project(ap)
	if not p.front:
		return
	var dist := e.distance_to_player()
	var px := combat.camera.unproject_position(ap + combat.camera.global_transform.basis.x * e.hit_radius)
	var rad := clampf(px.distance_to(p.pos), 14.0, 220.0)
	var col := intel_color(e)   # [0.14.4] ab Normal ohne Zerstörerfarbe
	var lk := combat.locked
	var s := rad + 8.0 + (4.0 * sin(_t * 10.0) if lk else 0.0)
	var pos: Vector2 = p.pos
	for i in 4:
		var d := Vector2(1, 1).rotated(i * PI * 0.5)
		var corner := pos + d * s * 0.75
		_gpoly(PackedVector2Array([corner - Vector2(d.x, 0) * 13.0, corner, corner - Vector2(0, d.y) * 13.0]), Color(col, 0.95), 1.7)
	var label := "%s  %d m" % [e.display_name, int(dist)]
	_gtext(pos + Vector2(s * 0.75 + 10.0, -s * 0.75 + 16.0), label, _f_body, 20, Color(col.lightened(0.3), 0.95))
	if e is Destroyer and Config.combat_intel:   # [0.14.4] Rest-Treffer nur bis Anfänger
		var d: Destroyer = e
		var hits: int = d.data.hits_left
		var total := Config.destroyer_hits_needed(d.data.color)
		for i in total:
			var pc := pos + Vector2(s * 0.75 + 16.0 + i * 16.0, -s * 0.75 + 30.0)
			var r := Rect2(pc, Vector2(11, 11))
			if i < hits:
				_ci.draw_rect(r.grow(2.0), Color(col, 0.2))
				_ci.draw_rect(r, col.lightened(0.2))
			else:
				_ci.draw_rect(r, Color(col, 0.6), false, 1.5)
	elif e is Flagship:
		var f: Flagship = e
		var wp := _project(f.weak_point_pos())
		if wp.front and not Config.combat_intel:
			# [Vorgabe 0.14.4] ab Normal nur die Markierung des Quadrats – kein Ladebalken, kein Fensterhinweis
			_gbox(Rect2(wp.pos - Vector2(34, 34), Vector2(68, 68)), Color(UITheme.PINK, 0.85), 1.6)
		elif wp.front:
			var ch := f.charge_level()
			var vul := f.is_vulnerable()
			var bc := UITheme.PINK.lerp(Color(1, 1, 1), 0.5 if vul else 0.0)
			var bs := 34.0 + (6.0 * sin(_t * 12.0) if vul else 0.0)
			_gbox(Rect2(wp.pos - Vector2(bs, bs), Vector2(bs, bs) * 2.0), Color(bc, 0.95), 3.0 if vul else 1.6)
			_ci.draw_rect(Rect2(wp.pos + Vector2(-bs, bs + 8.0), Vector2(bs * 2.0 * ch, 6.0)), bc)
			_ci.draw_rect(Rect2(wp.pos + Vector2(-bs, bs + 8.0), Vector2(bs * 2.0, 6.0)), Color(bc, 0.5), false, 1.0)
			if vul and fmod(_t, 0.5) < 0.32:   # 2 Hz (fotosicher)
				_gtext(wp.pos + Vector2(-bs, -bs - 12.0), "VERWUNDBAR!", _f_disp, 22, Color(1, 0.85, 0.97))


## Pfeile zu Gegnern bzw. schweren Geschossen außerhalb der Sicht. Sie sitzen auf einer Ellipse innerhalb
## der Kanzelöffnung (oben bis knapp unter den Rand, unten bis über die Blendschutzkante) – nie auf den Streben.
func _draw_offscreen(vp: Vector2) -> void:
	var cam := combat.camera
	var inv := cam.global_transform.affine_inverse()
	var c := vp * 0.5
	var rx := vp.x * 0.43
	var r_up := c.y - 92.0
	var r_down := maxf(minf(_lip[0].y, _lip[1].y) - 52.0 - c.y, 80.0)
	var items := []
	if Config.offscreen_indicators:
		for e in combat.enemies:
			if is_instance_valid(e) and e.alive:
				items.append({"w": e.global_position, "col": intel_color(e), "big": e.kind != Enemy.Kind.FIGHTER, "inc": false})
	for s in combat.shots.incoming_heavy():
		items.append({"w": s.pos, "col": UITheme.RED, "big": true, "inc": true})
	for it in items:
		var local: Vector3 = inv * it.w
		if local.z < 0.0:
			var sp := cam.unproject_position(it.w)
			var q := sp - c
			var ry := r_up if q.y < 0.0 else r_down
			if pow(q.x / rx, 2.0) + pow(q.y / ry, 2.0) <= 1.0:
				if it.inc and fmod(_t, 0.4) < 0.25:
					_garc(sp, 22.0, 0, TAU, Color(UITheme.RED, 0.9), 2.2, 24)
				continue
		var d := Vector2(local.x, -local.y)
		if d.length() < 0.001:
			d = Vector2(0, 1)
		d = d.normalized()
		var ry2 := r_up if d.y < 0.0 else r_down
		var p := c + d / sqrt(pow(d.x / rx, 2.0) + pow(d.y / ry2, 2.0))
		var sz := 17.0 if it.big else 11.0
		var col: Color = it.col
		if it.inc:
			sz = 21.0
			col = Color(UITheme.RED, 0.6 + 0.4 * sin(_t * 16.0))
		var side := d.orthogonal() * sz * 0.75
		var tip := p + d * sz
		var back := p - d * sz * 0.35
		_gpoly(PackedVector2Array([back + side, tip, back - side]), col, 2.0)
		if it.big:
			_gpoly(PackedVector2Array([back + side - d * 9.0, tip - d * 9.0, back - side - d * 9.0]), Color(col, col.a * 0.6), 1.6)
		if it.inc:
			_gtext(p - d * 36.0 + Vector2(-6, 9), "!", _f_disp, 26, col)


func _draw_popups() -> void:
	for p in _popups:
		var pr := _project(p.w)
		if not pr.front:
			continue
		var a := clampf(1.4 - p.t, 0.0, 1.0)
		_gtext(pr.pos + Vector2(-30, -30 - p.t * 50.0), p.text, _f_disp, 28, Color(p.color.lightened(0.4), a))


# ---------------------------------------------------------------------------------------------
#  Trefferkante (rotes Glimmen am Bildrand)
# ---------------------------------------------------------------------------------------------
func _draw_alert() -> void:
	# langsames Abklingen: bei Dauerbeschuss (Rückmeldung höchstens alle 0,5 s) bleibt die Kante ruhig statt zu pulsieren
	var a := clampf(1.0 - _hit_t * (1.2 if _hit_heavy else 1.6), 0.0, 1.0)
	if a <= 0.0:
		return
	var vp := size
	var col := Color(1.0, 0.55, 0.4, a * (0.5 if _hit_heavy else 0.28))   # kein gesättigtes Rot (fotosicher)
	var w := 44.0 if _hit_heavy else 20.0
	for i in 6:
		var k := float(i) / 6.0
		var cc := Color(col, col.a * (1.0 - k))
		var o := w * k
		_alert_layer.draw_rect(Rect2(Vector2(o, o), vp - Vector2(o, o) * 2.0), cc, false, w / 6.0)
