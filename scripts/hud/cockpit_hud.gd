class_name CockpitHUD
extends Control
## =============================================================================================
##  Cockpit-HUD. Minimalistisch [ORIGINAL]: Waffenanzeige, Energieanzeige, auf Planeten Scanner.
##  Zielanzeige [ORIGINAL]: Bordlaser = Rechteck, oben/unten ~80 % offen (zwei Klammern);
##  Ionen-Kanone = klassisches Fadenkreuz. Weitere Details [FREI].
## =============================================================================================

var combat: CombatBase
var shake_offset := Vector2.ZERO
var _msgs: Array = []
var _small: Array = []
var _popups: Array = []
var _t := 0.0
var _energy_shown := 100.0
var _hit_t := 10.0
var _hit_heavy := false
var _weapon_t := 10.0
var _f_title: Font
var _f_disp: Font
var _f_body: Font
var _f_mono: Font


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_f_title = Assets.font("title")
	_f_disp = Assets.font("display")
	_f_body = Assets.font("body_bold")
	_f_mono = Assets.font("mono")
	_energy_shown = GameState.energy


func _process(delta: float) -> void:
	_t += delta
	_hit_t += delta
	_weapon_t += delta
	for m in _msgs:
		m.t += delta
	_msgs = _msgs.filter(func(m): return m.t < m.dur)
	for m in _small:
		m.t += delta
	_small = _small.filter(func(m): return m.t < m.dur)
	for p in _popups:
		p.t += delta
	_popups = _popups.filter(func(p): return p.t < 1.4)
	_energy_shown = lerpf(_energy_shown, GameState.energy, 1.0 - exp(-6.0 * delta))
	queue_redraw()


# ---------------------------------------------------------------------------------------------
#  Schnittstelle
# ---------------------------------------------------------------------------------------------
func show_message(title: String, sub := "", dur := 2.0, color := UITheme.CYAN, small := false) -> void:
	var m := {"title": title, "sub": sub, "t": 0.0, "dur": dur, "color": color}
	if small:
		_small = [m]
	else:
		_msgs = [m]


func add_popup(world: Vector3, text: String, color: Color) -> void:
	_popups.append({"w": world, "text": text, "color": color, "t": 0.0})


func on_player_hit(heavy: bool, _dmg: float) -> void:
	_hit_t = 0.0
	_hit_heavy = heavy


func on_weapon_changed() -> void:
	_weapon_t = 0.0


# ---------------------------------------------------------------------------------------------
#  Zeichnen
# ---------------------------------------------------------------------------------------------
func _draw() -> void:
	if combat == null or combat.camera == null:
		return
	var vp := size
	draw_set_transform(shake_offset)
	_draw_lasers()
	_draw_canopy(vp)
	_draw_lens_flare(vp)
	_draw_hit_frame(vp)
	if not combat.dying:
		_draw_target_marker(vp)
		_draw_offscreen(vp)
		if combat.fire_enabled:
			_draw_crosshair(vp)
	_draw_popups()
	_draw_dashboard(vp)
	_draw_top(vp)
	_draw_docking(vp)
	_draw_messages(vp)


## Laserstrahlen als verjüngte 2D-Lichtlinien von den Bordkanonen zum Puls (Arcade-Look).
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
			var d := hp - tp
			if d.length() < 1.0:
				continue
			var n := d.normalized().orthogonal()
			var fade := clampf(1.5 - k, 0.0, 1.0)
			var w0 := 7.0 * fade + 1.0
			var w1 := 1.6
			for layer in [[3.5, 0.12], [1.8, 0.3], [1.0, 1.0]]:
				var m: float = layer[0]
				var col := Color(0.45, 0.92, 1.0, float(layer[1]) * fade) if m > 1.0 else Color(0.85, 1.0, 1.0, fade)
				var poly := PackedVector2Array([tp + n * w0 * m, hp + n * w1 * m, hp - n * w1 * m, tp - n * w0 * m])
				draw_colored_polygon(poly, col)


## Cockpit-Kanzelstreben (oben links/rechts) und obere Rahmenkante.
func _draw_canopy(vp: Vector2) -> void:
	var dark := Color(0.01, 0.015, 0.025, 0.92)
	var mid := Color(0.03, 0.05, 0.08, 0.55)
	var edge := Color(UITheme.CYAN, 0.22)
	var w := vp.x
	var h := vp.y - 128.0
	# linke Strebe
	var l := PackedVector2Array([Vector2(-20, -20), Vector2(w * 0.085, -20), Vector2(w * 0.012, h * 0.62), Vector2(-20, h * 0.7)])
	draw_polygon(l, PackedColorArray([dark, mid, mid, dark]))
	draw_line(Vector2(w * 0.085, 0), Vector2(w * 0.012, h * 0.62), edge, 2.0, true)
	draw_line(Vector2(w * 0.012, h * 0.62), Vector2(0, h * 0.66), edge, 2.0, true)
	# rechte Strebe
	var r := PackedVector2Array([Vector2(w + 20, -20), Vector2(w * 0.915, -20), Vector2(w * 0.988, h * 0.62), Vector2(w + 20, h * 0.7)])
	draw_polygon(r, PackedColorArray([dark, mid, mid, dark]))
	draw_line(Vector2(w * 0.915, 0), Vector2(w * 0.988, h * 0.62), edge, 2.0, true)
	draw_line(Vector2(w * 0.988, h * 0.62), Vector2(w, h * 0.66), edge, 2.0, true)
	# Nieten/Details
	for i in 5:
		var t := (i + 1) / 6.0
		var pl := Vector2(w * 0.085, 0).lerp(Vector2(w * 0.012, h * 0.62), t) + Vector2(-14, 0)
		var pr := Vector2(w * 0.915, 0).lerp(Vector2(w * 0.988, h * 0.62), t) + Vector2(14, 0)
		draw_circle(pl, 2.2, Color(UITheme.CYAN, 0.18), true, -1.0, true)
		draw_circle(pr, 2.2, Color(UITheme.CYAN, 0.18), true, -1.0, true)


func _glow_line(a: Vector2, b: Vector2, col: Color, w := 2.0) -> void:
	draw_line(a, b, Color(col, col.a * 0.18), w * 4.0, true)
	draw_line(a, b, col, w, true)


func _glow_arc(c: Vector2, r: float, a0: float, a1: float, col: Color, w := 2.0, pts := 48) -> void:
	draw_arc(c, r, a0, a1, pts, Color(col, col.a * 0.18), w * 4.0, true)
	draw_arc(c, r, a0, a1, pts, col, w, true)


func _text(pos: Vector2, s: String, f: Font, fs: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	draw_string(f, pos + Vector2(0, 2), s, align, width, fs, Color(0, 0, 0, col.a * 0.6))
	draw_string(f, pos, s, align, width, fs, col)


func _project(w: Vector3) -> Dictionary:
	var cam := combat.camera
	if cam.is_position_behind(w):
		return {"front": false, "pos": Vector2.ZERO}
	return {"front": true, "pos": cam.unproject_position(w)}


# --- Zielanzeige ------------------------------------------------------------------------------
func _draw_crosshair(vp: Vector2) -> void:
	if combat.weapon == CombatBase.Weapon.BOMB:
		_draw_bomb_sight(vp)
		return
	var c := (vp * 0.5).round()
	var lock := combat.locked
	var appear := clampf(_weapon_t * 5.0, 0.0, 1.0)
	if combat.weapon == CombatBase.Weapon.LASER:
		var col := Color(0.75, 1.0, 0.4) if lock else UITheme.CYAN
		var pulse := 1.0 + (0.06 * sin(_t * 18.0) if lock else 0.0)
		var w := 150.0 * pulse * (1.3 - 0.3 * appear)
		var h := 104.0 * pulse * (1.3 - 0.3 * appear)
		var stub := w * 0.1   # oben/unten ~80 % offen
		var tl := c + Vector2(-w, -h) * 0.5
		var tr := c + Vector2(w, -h) * 0.5
		var bl := c + Vector2(-w, h) * 0.5
		var br := c + Vector2(w, h) * 0.5
		col.a = appear
		_glow_line(tl, bl, col, 2.5)
		_glow_line(tr, br, col, 2.5)
		_glow_line(tl, tl + Vector2(stub, 0), col, 2.5)
		_glow_line(bl, bl + Vector2(stub, 0), col, 2.5)
		_glow_line(tr, tr - Vector2(stub, 0), col, 2.5)
		_glow_line(br, br - Vector2(stub, 0), col, 2.5)
		draw_circle(c, 2.5, col, true, -1.0, true)
	else:
		var col2 := Color(0.88, 0.8, 1.0) if not lock else Color(1.0, 0.75, 0.95)
		col2.a = appear
		var r := 44.0 * (1.25 - 0.25 * appear)
		_glow_arc(c, r, 0, TAU, col2, 2.0, 64)
		for i in 4:
			var d := Vector2.RIGHT.rotated(i * PI * 0.5)
			_glow_line(c + d * 12.0, c + d * (r + 26.0), col2, 2.0)
		for i in 4:
			var d2 := Vector2.RIGHT.rotated(i * PI * 0.5 + PI * 0.25)
			_glow_line(c + d2 * (r - 6.0), c + d2 * (r + 4.0), col2, 1.5)
		var ch := combat.ion_charge()
		var ring_col := UITheme.GREEN if ch >= 1.0 else UITheme.AMBER
		draw_arc(c, r + 12.0, -PI * 0.5, -PI * 0.5 + TAU * ch, 64, Color(ring_col, 0.85 * appear), 4.0, true)
		if ch < 1.0:
			_text(c + Vector2(r + 22.0, -r - 8.0), "%.1f s" % ((1.0 - ch) * Config.ion_cooldown), _f_mono, 20, Color(UITheme.AMBER, appear))


## Bombenvisier: Flugbahn als Punktreihe bis zur Aufschlagmarke (die Marke selbst liegt in 3D am Boden).
func _draw_bomb_sight(vp: Vector2) -> void:
	var pc := combat as PlanetCombat
	if pc == null:
		return
	var c := (vp * 0.5).round()
	var appear := clampf(_weapon_t * 5.0, 0.0, 1.0)
	var empty := GameState.bombs <= 0
	var locked := pc.impact_city >= 0 and not pc.impact_pending
	var col := Color(0.6, 0.6, 0.65) if empty else (UITheme.GREEN if locked else UITheme.AMBER)
	col.a = appear
	_glow_line(c + Vector2(-30, 0), c + Vector2(-12, 0), col, 2.0)
	_glow_line(c + Vector2(30, 0), c + Vector2(12, 0), col, 2.0)
	_glow_line(c + Vector2(0, 12), c + Vector2(0, 26), col, 2.0)
	var pts: Array = pc.bomb_trajectory(16)
	for i in pts.size():
		var pr := _project(pts[i])
		if pr.front:
			draw_circle(pr.pos, 3.2 - i * 0.1, Color(col, appear * (0.2 + 0.65 * float(i) / pts.size())), true, -1.0, true)
	var mp := _project(pc.impact_point)
	var screen := Rect2(Vector2(0, 0), vp - Vector2(0, 190))
	var under_scanner: bool = mp.front and (mp.pos as Vector2).distance_to(Vector2(vp.x * 0.5, vp.y - 150.0)) < 150.0
	if mp.front and screen.has_point(mp.pos) and not under_scanner:
		var txt := ""
		if empty:
			txt = "KEINE BOMBEN"
		elif pc.impact_pending:
			txt = "BOMBE UNTERWEGS"
		elif pc.impact_city >= 0:
			txt = "ZIEL: " + String(pc.planet.city_names[pc.impact_city]).to_upper()
		else:
			txt = "%d m" % int(Vector2(pc.impact_point.x, pc.impact_point.z).distance_to(pc.player_xz()))
		_text(mp.pos + Vector2(46, 8), txt, _f_disp, 20, col)
		if locked and not empty and fmod(_t, 0.5) < 0.35:
			_text(c + Vector2(-200, 74), "ABWURF: FEUER", _f_disp, 22, col, HORIZONTAL_ALIGNMENT_CENTER, 400)
	else:
		_text(c + Vector2(-300, 120), "AUFSCHLAG UNTER DEM SCHIFF – VORWÄRTS FLIEGEN", _f_body, 22, col, HORIZONTAL_ALIGNMENT_CENTER, 600)


func _draw_target_marker(_vp: Vector2) -> void:
	var e := combat.aim_target
	if e == null or not is_instance_valid(e) or not e.alive:
		return
	var p := _project(e.global_position)
	if not p.front:
		return
	var dist := e.distance_to_player()
	var px := combat.camera.unproject_position(e.global_position + combat.camera.global_transform.basis.x * e.hit_radius)
	var rad := clampf(px.distance_to(p.pos), 14.0, 220.0)
	var col := e.hud_color
	var lk := combat.locked
	var s := rad + 8.0 + (4.0 * sin(_t * 10.0) if lk else 0.0)
	var pos: Vector2 = p.pos
	for i in 4:
		var d := Vector2(1, 1).rotated(i * PI * 0.5)
		var corner := pos + d * s * 0.75
		_glow_line(corner, corner - Vector2(d.x, 0) * 12.0, Color(col, 0.9), 2.0)
		_glow_line(corner, corner - Vector2(0, d.y) * 12.0, Color(col, 0.9), 2.0)
	var label := "%s  %d m" % [e.display_name, int(dist)]
	_text(pos + Vector2(s * 0.75 + 10.0, -s * 0.75 + 16.0), label, _f_body, 20, Color(col.lightened(0.3), 0.95))
	if e is Destroyer:
		var d: Destroyer = e
		var hits: int = d.data.hits_left
		var total := Config.destroyer_hits_needed(d.data.color)
		for i in total:
			var pc := pos + Vector2(s * 0.75 + 16.0 + i * 16.0, -s * 0.75 + 34.0)
			if i < hits:
				draw_rect(Rect2(pc, Vector2(11, 11)), col.lightened(0.2))
			else:
				draw_rect(Rect2(pc, Vector2(11, 11)), Color(col, 0.6), false, 1.5)
	elif e is Flagship:
		var f: Flagship = e
		var wp := _project(f.weak_point_pos())
		if wp.front:
			var ch := f.charge_level()
			var vul := f.is_vulnerable()
			var bc := UITheme.PINK.lerp(Color(1, 1, 1), 0.5 if vul else 0.0)
			var bs := 34.0 + (6.0 * sin(_t * 20.0) if vul else 0.0)
			draw_rect(Rect2(wp.pos - Vector2(bs, bs), Vector2(bs, bs) * 2.0), Color(bc, 0.95), false, 3.0 if vul else 1.5)
			draw_rect(Rect2(wp.pos + Vector2(-bs, bs + 8.0), Vector2(bs * 2.0 * ch, 6.0)), bc)
			draw_rect(Rect2(wp.pos + Vector2(-bs, bs + 8.0), Vector2(bs * 2.0, 6.0)), Color(bc, 0.5), false, 1.0)
			if vul and fmod(_t, 0.3) < 0.2:
				_text(wp.pos + Vector2(-bs, -bs - 12.0), "VERWUNDBAR!", _f_disp, 22, Color(1, 0.85, 0.97))


# --- Pfeile zu Gegnern außerhalb der Sicht -----------------------------------------------------
func _draw_offscreen(vp: Vector2) -> void:
	var cam := combat.camera
	var inv := cam.global_transform.affine_inverse()
	var margin := 70.0
	var rsize := vp - Vector2(margin * 2.0, margin * 2.0 + 190.0)
	if rsize.x < 50.0 or rsize.y < 50.0:
		return
	var rect := Rect2(Vector2(margin, margin + 40.0), rsize)
	var c := rect.get_center()
	var items := []
	if Config.offscreen_indicators:
		for e in combat.enemies:
			if is_instance_valid(e) and e.alive:
				items.append({"w": e.global_position, "col": e.hud_color, "big": e.kind != Enemy.Kind.FIGHTER, "inc": false})
	for s in combat.shots.incoming_heavy():
		items.append({"w": s.pos, "col": UITheme.RED, "big": true, "inc": true})
	for it in items:
		var local: Vector3 = inv * it.w
		var on_screen := false
		var sp := Vector2.ZERO
		if local.z < 0.0:
			sp = cam.unproject_position(it.w)
			on_screen = rect.has_point(sp)
		if on_screen:
			if it.inc and fmod(_t, 0.4) < 0.25:
				draw_arc(sp, 22.0, 0, TAU, 24, Color(UITheme.RED, 0.9), 2.5, true)
			continue
		var d := Vector2(local.x, -local.y)
		if d.length() < 0.001:
			d = Vector2(0, 1)
		d = d.normalized()
		# Schnittpunkt mit dem Rechteck
		var tx := (rect.size.x * 0.5) / maxf(absf(d.x), 0.0001)
		var ty := (rect.size.y * 0.5) / maxf(absf(d.y), 0.0001)
		var p := c + d * minf(tx, ty)
		var sz := 18.0 if it.big else 11.0
		var col: Color = it.col
		if it.inc:
			sz = 22.0
			col = Color(UITheme.RED, 0.6 + 0.4 * sin(_t * 16.0))
		var tip := p + d * sz
		var side := d.orthogonal() * sz * 0.7
		var pts := PackedVector2Array([tip, p - d * sz * 0.4 + side, p - d * sz * 0.4 - side])
		draw_colored_polygon(pts, Color(col, 0.3))
		draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]), col, 2.0, true)
		if it.inc:
			_text(p - d * 34.0 + Vector2(-8, 8), "!", _f_disp, 26, col)


func _draw_popups() -> void:
	for p in _popups:
		var pr := _project(p.w)
		if not pr.front:
			continue
		var a := clampf(1.4 - p.t, 0.0, 1.0)
		_text(pr.pos + Vector2(-30, -30 - p.t * 50.0), p.text, _f_disp, 28, Color(p.color.lightened(0.4), a))


func _draw_hit_frame(vp: Vector2) -> void:
	var a := clampf(1.0 - _hit_t * (1.5 if _hit_heavy else 3.0), 0.0, 1.0)
	if a <= 0.0:
		return
	var col := Color(1.0, 0.25, 0.15, a * (0.55 if _hit_heavy else 0.3))
	var w := 40.0 if _hit_heavy else 18.0
	for i in 6:
		var k := float(i) / 6.0
		var cc := Color(col, col.a * (1.0 - k))
		var o := w * k
		draw_rect(Rect2(Vector2(o, o), vp - Vector2(o, o) * 2.0), cc, false, w / 6.0)


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
		var gc: Color = g[2]
		draw_circle(gp, g[1], Color(gc, 0.05 * fade), true, -1.0, true)
		draw_arc(gp, g[1], 0, TAU, 40, Color(gc, 0.07 * fade), 2.0, true)


# --- Armaturenbrett -----------------------------------------------------------------------------
func _draw_dashboard(vp: Vector2) -> void:
	var y0 := vp.y - 128.0
	var y1 := vp.y - 172.0
	var cx := vp.x * 0.5
	var pts := PackedVector2Array([
		Vector2(0, vp.y), Vector2(0, y0), Vector2(cx - 330, y0), Vector2(cx - 290, y1),
		Vector2(cx + 290, y1), Vector2(cx + 330, y0), Vector2(vp.x, y0), Vector2(vp.x, vp.y)])
	var top := Color(0.03, 0.07, 0.12, 0.92)
	var bot := Color(0.0, 0.01, 0.02, 0.98)
	draw_polygon(pts, PackedColorArray([bot, top, top, top, top, top, top, bot]))
	var edge := PackedVector2Array([Vector2(0, y0), Vector2(cx - 330, y0), Vector2(cx - 290, y1), Vector2(cx + 290, y1), Vector2(cx + 330, y0), Vector2(vp.x, y0)])
	draw_polyline(edge, Color(UITheme.CYAN, 0.12), 8.0, true)
	draw_polyline(edge, Color(UITheme.CYAN, 0.55), 2.0, true)
	# Rasterlinien (dezent)
	for i in range(1, 6):
		var yy := y0 + i * 22.0
		draw_line(Vector2(20, yy), Vector2(cx - 340, yy), Color(UITheme.CYAN, 0.03), 1.0)
		draw_line(Vector2(cx + 340, yy), Vector2(vp.x - 20, yy), Color(UITheme.CYAN, 0.03), 1.0)
	_draw_energy(Vector2(46, y0 + 16), vp)
	var planet := combat is PlanetCombat
	if planet:
		_draw_scanner(Vector2(cx, vp.y - 150.0), 132.0)
		_draw_weapon(Vector2(cx + 176, y0 + 16), 300.0, true)
		_draw_status(Vector2(maxf(vp.x - 46, cx + 176 + 330 + 420), y0 + 16), vp, true)
	else:
		_draw_weapon(Vector2(cx - 270, y1 + 14), 540.0, false)
		_draw_status(Vector2(vp.x - 46, y0 + 16), vp, false)
	if planet:
		_text(Vector2(40, 112), combat.hint_text, Assets.font("body_med"), 19, Color(UITheme.TEXT_DIM, 0.85))
	else:
		_text(Vector2(0, vp.y - 10), combat.hint_text, Assets.font("body_med"), 19, Color(UITheme.TEXT_DIM, 0.85), HORIZONTAL_ALIGNMENT_CENTER, vp.x)


func _draw_energy(o: Vector2, _vp: Vector2) -> void:
	var e := GameState.energy
	var col := UITheme.GREEN
	if e < 50.0:
		col = UITheme.AMBER
	if e < Config.energy_low_warning:
		col = UITheme.RED
	var blink := e < Config.energy_low_warning and fmod(_t, 0.6) < 0.3
	_text(o + Vector2(0, 18), "ENERGIE", _f_disp, 18, Color(UITheme.CYAN, 0.8))
	_text(o + Vector2(0, 84), "%3d" % int(ceil(e)), _f_mono, 66, col if not blink else Color(1, 1, 1))
	_text(o + Vector2(118, 84), "%", _f_mono, 32, Color(col, 0.8))
	var bx := o.x + 170.0
	var by := o.y + 34.0
	var segs := 20
	var sw := 15.0
	for i in segs:
		var on := (float(i) + 0.5) / segs * Config.energy_max <= _energy_shown
		var r := Rect2(Vector2(bx + i * (sw + 3.0), by), Vector2(sw, 34))
		if on:
			var sc := col.lerp(Color(1, 1, 1), 0.15 if i == int(_energy_shown / Config.energy_max * segs) - 1 else 0.0)
			draw_rect(r, Color(sc, 0.9))
			draw_rect(r.grow(2.0), Color(sc, 0.12))
		else:
			draw_rect(r, Color(col, 0.12))
	if e < Config.energy_low_warning and not GameState.game_over:
		_text(Vector2(bx, by + 64), "ENERGIE KRITISCH – STATION ANFLIEGEN!", _f_body, 20, Color(UITheme.RED, 0.6 + 0.4 * sin(_t * 8.0)))
	elif combat is SpaceCombat and (combat as SpaceCombat).is_docking():
		_text(Vector2(bx, by + 64), "ANGEDOCKT", _f_body, 20, Color(UITheme.CYAN, 0.9))
	else:
		_text(Vector2(bx, by + 64), "PUNKTE  %07d" % GameState.score, _f_mono, 22, Color(UITheme.TEXT, 0.85))


func _draw_weapon(o: Vector2, w: float, compact: bool) -> void:
	var laser := combat.weapon == CombatBase.Weapon.LASER
	var flash := clampf(1.0 - _weapon_t * 2.0, 0.0, 1.0)
	var mode := "AUTO" if Config.auto_weapon_switch else "MANUELL (Q)"
	if combat.bombs_allowed():
		mode = "MANUELL (Q)"
	if combat.weapon == CombatBase.Weapon.BOMB:
		_draw_bomb_weapon(o, w, compact, flash, mode)
		return
	var name := "BORDLASER" if laser else "IONEN-KANONE"
	var col := UITheme.CYAN if laser else Color(0.85, 0.78, 1.0)
	if compact:
		_text(o + Vector2(0, 18), "WAFFE · " + mode, _f_disp, 16, Color(UITheme.CYAN, 0.7))
		_text(o + Vector2(0, 52), name, _f_disp, 26, col.lerp(Color(1, 1, 1), flash))
	else:
		_text(o + Vector2(0, 16), "WAFFE · " + mode, _f_disp, 16, Color(UITheme.CYAN, 0.7), HORIZONTAL_ALIGNMENT_CENTER, w)
		_text(o + Vector2(0, 54), name, _f_disp, 32, col.lerp(Color(1, 1, 1), flash), HORIZONTAL_ALIGNMENT_CENTER, w)
	var bar_y := o.y + (66.0 if compact else 72.0)
	var bw := w * (0.9 if compact else 0.6)
	var bx := o.x if compact else o.x + (w - bw) * 0.5
	if laser:
		var heat := clampf(combat.laser_cd / Config.laser_fire_interval, 0.0, 1.0)
		for i in 12:
			var r := Rect2(Vector2(bx + i * bw / 12.0, bar_y), Vector2(bw / 12.0 - 3.0, 12))
			draw_rect(r, Color(col, 0.75 - 0.5 * heat * float(i % 2)))
		var sub := "gegen Fighter · Dauerfeuer"
		if combat.bombs_allowed():
			sub = "gegen Fighter · Q: Bomben (%d)" % GameState.bombs
		_text(Vector2(bx, bar_y + 34), sub, _f_body, 18, Color(UITheme.TEXT_DIM, 0.9))
	else:
		var ch := combat.ion_charge()
		draw_rect(Rect2(Vector2(bx, bar_y), Vector2(bw, 12)), Color(col, 0.15))
		draw_rect(Rect2(Vector2(bx, bar_y), Vector2(bw * ch, 12)), UITheme.GREEN if ch >= 1.0 else UITheme.AMBER)
		var st := "BEREIT" if ch >= 1.0 else "LÄDT  %.1f s" % ((1.0 - ch) * Config.ion_cooldown)
		_text(Vector2(bx, bar_y + 34), st + " · gegen Zerstörer/Flaggschiff", _f_body, 18, Color(UITheme.TEXT_DIM, 0.9))


func _draw_bomb_weapon(o: Vector2, w: float, compact: bool, flash: float, mode: String) -> void:
	var col := UITheme.AMBER
	var empty := GameState.bombs <= 0
	_text(o + Vector2(0, 18), "WAFFE · " + mode, _f_disp, 16, Color(UITheme.CYAN, 0.7))
	_text(o + Vector2(0, 52), "BOMBEN", _f_disp, 26, col.lerp(Color(1, 1, 1), flash))
	_text(o + Vector2(0, 52), "%d / %d" % [GameState.bombs, Config.bombs_max], _f_mono, 26, UITheme.RED if empty else col, HORIZONTAL_ALIGNMENT_RIGHT, w * 0.9)
	var bar_y := o.y + (66.0 if compact else 72.0)
	var bw := w * 0.9
	var n := maxi(Config.bombs_max, 1)
	var pw := bw / n
	for i in n:
		var r := Rect2(Vector2(o.x + i * pw, bar_y), Vector2(pw - 3.0, 12))
		if i < GameState.bombs:
			draw_rect(r, Color(col, 0.9))
		else:
			draw_rect(r, Color(col, 0.35), false, 1.0)
	var st := "LEER – Nachladen an Station" if empty else ("BEREIT · Abwurf mit FEUER · Q: Laser" if combat.bomb_cd <= 0.0 else "LÄDT … · Q: Laser")
	_text(Vector2(o.x, bar_y + 34), st, _f_body, 18, Color(UITheme.RED if empty else UITheme.TEXT_DIM, 0.9))


func _draw_status(o_right: Vector2, _vp: Vector2, _planet: bool) -> void:
	var x := o_right.x - 420.0
	var y := o_right.y
	_text(Vector2(x, y + 18), "LAGE", _f_disp, 18, Color(UITheme.CYAN, 0.8))
	var f_n := 0
	var d_n := 0
	var fl := false
	for e in combat.enemies:
		if not is_instance_valid(e) or not e.alive:
			continue
		match e.kind:
			Enemy.Kind.FIGHTER:
				f_n += 1
			Enemy.Kind.DESTROYER:
				d_n += 1
			Enemy.Kind.FLAGSHIP:
				fl = true
	var lines := []
	if combat is SpaceCombat:
		var sc: SpaceCombat = combat
		if (sc.mode == SpaceCombat.Mode.ORBIT and not sc.orbit_done) or (sc.mode == SpaceCombat.Mode.RECEPTION and sc.phase == SpaceCombat.Phase.FIGHTERS):
			lines.append(["FIGHTER", "%d / %d" % [sc.orbit_total - sc.orbit_killed, sc.orbit_total], UITheme.FIGHTER_COLOR])
		elif sc.squadron and sc.squadron.state != SquadronData.State.DESTROYED and not sc.is_docking():
			lines.append(["FIGHTER", "%d" % sc.squadron.fighters, UITheme.FIGHTER_COLOR])
			if sc.mode == SpaceCombat.Mode.SQUADRON:
				lines.append(["ZERSTÖRER", str(sc.squadron.destroyers.size()), UITheme.AMBER, sc.squadron.destroyer_colors()])
		if fl:
			lines.append(["FLAGGSCHIFF", "AKTIV", UITheme.PINK])
	elif combat is PlanetCombat and (combat as PlanetCombat).enemy_mode:
		var ep: PlanetCombat = combat
		lines.append(["FEINDSTÄDTE", "%d / %d" % [ep.planet.alive_cities(), ep.planet.cities.size()], Color(1.0, 0.4, 0.62)])
		lines.append(["VERTEIDIGER", "%d" % ep.planet.defenders, UITheme.FIGHTER_COLOR if ep.planet.defenders > 0 else UITheme.GREEN])
		lines.append(["BOMBEN", "%d / %d" % [GameState.bombs, Config.bombs_max], UITheme.AMBER if GameState.bombs > 0 else UITheme.RED])
	elif combat is PlanetCombat:
		var pc: PlanetCombat = combat
		lines.append(["STÄDTE", "%d / %d" % [pc.planet.alive_cities(), pc.planet.cities.size()], UITheme.CYAN])
		if pc.squadron and pc.squadron.state != SquadronData.State.DESTROYED:
			lines.append(["FIGHTER", "%d" % pc.squadron.fighters, UITheme.FIGHTER_COLOR])
			lines.append(["ZERSTÖRER", str(pc.squadron.destroyers.size()), UITheme.AMBER, pc.squadron.destroyer_colors()])
	if lines.is_empty():
		lines.append(["KONTAKTE", "KEINE", UITheme.GREEN])
	for i in lines.size():
		var l: Array = lines[i]
		_text(Vector2(x, y + 48 + i * 28), l[0], _f_body, 22, Color(UITheme.TEXT_DIM, 0.95))
		_text(Vector2(x + 170, y + 48 + i * 28), l[1], _f_mono, 24, l[2])
		if l.size() > 3:
			# Zerstörer als farbige Kästchen (wie auf der Karte) – die Farbe wird nicht ausgeschrieben
			var cols: Array = l[3]
			for k in cols.size():
				var r := Rect2(Vector2(x + 210 + k * 22, y + 31 + i * 28), Vector2(16, 16))
				draw_rect(r, UITheme.DESTROYER_COLORS[int(cols[k])])
				draw_rect(r, Color(1, 1, 1, 0.5), false, 1.0)


func _draw_top(vp: Vector2) -> void:
	_text(Vector2(40, 52), combat.location_name, _f_disp, 30, Color(UITheme.CYAN, 0.95))
	_text(Vector2(40, 84), combat.location_sub, _f_body, 24, Color(UITheme.TEXT_DIM, 0.95))
	_text(Vector2(0, 50), "%07d" % GameState.score, _f_mono, 40, Color(UITheme.TEXT, 0.9), HORIZONTAL_ALIGNMENT_CENTER, vp.x)
	if GameState.running:
		_text(Vector2(0, 76), "ZEIT %s  ·  STUFE %d" % [GameState.format_time(GameState.sim_time), GameState.level + 1], _f_body, 20, Color(UITheme.TEXT_DIM, 0.8), HORIZONTAL_ALIGNMENT_CENTER, vp.x)


func _draw_messages(vp: Vector2) -> void:
	for m in _msgs:
		var a := clampf(m.t * 6.0, 0.0, 1.0) * clampf((m.dur - m.t) * 3.0, 0.0, 1.0)
		var y := vp.y * 0.27
		var scale_in := 1.0 + (1.0 - clampf(m.t * 6.0, 0.0, 1.0)) * 0.25
		var col: Color = m.color
		var fs := int(54 * scale_in)
		_text(Vector2(0, y), m.title, _f_title, fs, Color(col.lightened(0.25), a), HORIZONTAL_ALIGNMENT_CENTER, vp.x)
		if m.sub != "":
			_text(Vector2(0, y + 46), m.sub, _f_body, 30, Color(UITheme.TEXT, a * 0.95), HORIZONTAL_ALIGNMENT_CENTER, vp.x)
	for m in _small:
		var a2 := clampf(m.t * 8.0, 0.0, 1.0) * clampf((m.dur - m.t) * 4.0, 0.0, 1.0)
		_text(Vector2(0, vp.y * 0.5 + 120), m.title, _f_disp, 30, Color(m.color, a2), HORIZONTAL_ALIGNMENT_CENTER, vp.x)
		if m.sub != "":
			_text(Vector2(0, vp.y * 0.5 + 152), m.sub, _f_body, 22, Color(UITheme.TEXT, a2 * 0.9), HORIZONTAL_ALIGNMENT_CENTER, vp.x)
	if not combat.shots.incoming_heavy().is_empty() and fmod(_t, 0.5) < 0.32 and not combat.dying:
		_text(Vector2(0, vp.y * 0.5 - 96), "GESCHOSS IM ANFLUG – AUSWEICHEN!", _f_disp, 24, UITheme.RED, HORIZONTAL_ALIGNMENT_CENTER, vp.x)


func _draw_docking(vp: Vector2) -> void:
	if not (combat is SpaceCombat):
		return
	var sc: SpaceCombat = combat
	if not sc.is_docking():
		return
	var w := 620.0
	var bombs := Config.enemy_system_enabled
	var h := 160.0 if bombs else 120.0
	var o := Vector2((vp.x - w) * 0.5, vp.y - 330.0 - (h - 120.0))
	draw_rect(Rect2(o, Vector2(w, h)), Color(0.02, 0.06, 0.1, 0.8))
	draw_rect(Rect2(o, Vector2(w, h)), Color(UITheme.CYAN, 0.6), false, 2.0)
	if bombs:
		# [Vorgabe] Bomben werden nur an eigenen Stationen aufgefüllt
		_text(o + Vector2(24, 136), "BOMBEN", _f_disp, 18, Color(UITheme.AMBER, 0.9))
		_text(o + Vector2(w - 24 - 200, 138), "%d / %d" % [GameState.bombs, Config.bombs_max], _f_mono, 24, UITheme.AMBER, HORIZONTAL_ALIGNMENT_RIGHT, 200)
		var bn := maxi(Config.bombs_max, 1)
		var bpw := 300.0 / bn
		for i in bn:
			var r := Rect2(o + Vector2(140 + i * bpw, 122), Vector2(bpw - 3.0, 18))
			if i < GameState.bombs:
				draw_rect(r, Color(UITheme.AMBER, 0.9))
			else:
				draw_rect(r, Color(UITheme.AMBER, 0.3), false, 1.0)
	var title := "ANDOCKEN …"
	match sc.phase:
		SpaceCombat.Phase.DOCK_CLAMP:
			title = "ANDOCKKLAMMERN"
		SpaceCombat.Phase.REFUEL:
			title = "TANKEN"
		SpaceCombat.Phase.DOCKED:
			title = "ABFLUGBEREIT"
	_text(o + Vector2(24, 40), title, _f_disp, 26, UITheme.CYAN)
	_text(o + Vector2(w - 24 - 200, 44), "%d %%" % int(round(GameState.energy)), _f_mono, 40, UITheme.GREEN, HORIZONTAL_ALIGNMENT_RIGHT, 200)
	var steps := int(Config.energy_max / Config.refuel_step)
	var sw := (w - 48.0) / steps
	for i in steps:
		var on := (i + 1) * Config.refuel_step <= GameState.energy + 0.01
		draw_rect(Rect2(o + Vector2(24 + i * sw, 70), Vector2(sw - 4, 28)), Color(UITheme.GREEN, 0.9) if on else Color(UITheme.CYAN, 0.12))


# --- Planetenscanner ---------------------------------------------------------------------------
## [ORIGINAL] Scanner mit Karte, zeigt nur das eigene Schiff und die Städte.
func _draw_scanner(c: Vector2, r: float) -> void:
	var pc: PlanetCombat = combat
	draw_circle(c, r + 10.0, Color(0.0, 0.02, 0.04, 0.95), true, -1.0, true)
	draw_arc(c, r + 10.0, 0, TAU, 96, Color(UITheme.CYAN, 0.55), 2.5, true)
	draw_circle(c, r, Color(0.01, 0.08, 0.1, 0.9), true, -1.0, true)
	for k in [0.33, 0.66]:
		draw_arc(c, r * k, 0, TAU, 64, Color(UITheme.CYAN, 0.12), 1.0, true)
	draw_line(c - Vector2(r, 0), c + Vector2(r, 0), Color(UITheme.CYAN, 0.08), 1.0)
	draw_line(c - Vector2(0, r), c + Vector2(0, r), Color(UITheme.CYAN, 0.08), 1.0)
	var sweep := fmod(_t * 1.6, TAU)
	for i in 12:
		var a := sweep - i * 0.04
		draw_line(c, c + Vector2.from_angle(a) * r, Color(UITheme.CYAN, 0.12 * (1.0 - i / 12.0)), 2.0, true)
	var heading_up := Config.scanner_heading_up
	var range_m := Config.planet_area_radius * (1.55 if heading_up else 1.12)
	var sc := r / range_m
	var ppos := pc.player_xz()
	var yaw := pc.yaw
	var center_world := ppos if heading_up else Vector2.ZERO
	var area_c := _scan(Vector2.ZERO, center_world, yaw, heading_up, sc)
	draw_arc(c + area_c, Config.planet_area_radius * sc, 0, TAU, 64, Color(UITheme.AMBER, 0.25), 1.5, true)
	for i in pc.planet.cities.size():
		var p := _scan(pc.planet.city_pos[i], center_world, yaw, heading_up, sc)
		if p.length() > r - 4.0:
			p = p.normalized() * (r - 4.0)
		var alive: bool = pc.planet.cities[i]
		var under := pc.city_under_attack(i)
		if pc.enemy_mode and alive:
			# Feindstadt (Ziel)
			var tgt := pc.impact_city == i and not pc.impact_pending and GameState.bombs > 0
			var ec := UITheme.GREEN if tgt else Color(1.0, 0.32, 0.58)
			draw_circle(c + p, 5.0, ec, true, -1.0, true)
			draw_arc(c + p, 8.5, 0, TAU, 20, Color(ec, 0.55), 1.5, true)
			continue
		if not alive:
			var q := c + p
			draw_line(q - Vector2(4, 4), q + Vector2(4, 4), Color(0.5, 0.5, 0.55, 0.8), 2.0)
			draw_line(q - Vector2(4, -4), q + Vector2(4, -4), Color(0.5, 0.5, 0.55, 0.8), 2.0)
		elif under:
			var blink := fmod(_t, 0.5) < 0.3
			draw_circle(c + p, 6.5, UITheme.RED if blink else Color(1.0, 0.7, 0.3), true, -1.0, true)
			draw_arc(c + p, 9.0 + fmod(_t * 14.0, 10.0), 0, TAU, 24, Color(UITheme.RED, 0.6 * (1.0 - fmod(_t * 14.0, 10.0) / 10.0)), 1.5, true)
		else:
			draw_circle(c + p, 4.5, Color(0.5, 1.0, 1.0), true, -1.0, true)
			draw_circle(c + p, 8.0, Color(UITheme.CYAN, 0.18), true, -1.0, true)
	# Aufschlagpunkt der Bombe (Bombenmodus)
	if pc.enemy_mode and pc.weapon == CombatBase.Weapon.BOMB:
		var ip := _scan(Vector2(pc.impact_point.x, pc.impact_point.z), center_world, yaw, heading_up, sc)
		if ip.length() < r - 2.0:
			var icol := UITheme.GREEN if pc.impact_city >= 0 and not pc.impact_pending and GameState.bombs > 0 else UITheme.AMBER
			draw_line(c + ip - Vector2(6, 0), c + ip + Vector2(6, 0), icol, 2.0)
			draw_line(c + ip - Vector2(0, 6), c + ip + Vector2(0, 6), icol, 2.0)
			draw_arc(c + ip, Config.bomb_hit_radius * sc, 0, TAU, 20, Color(icol, 0.6), 1.0, true)
	# eigenes Schiff
	var sp := _scan(ppos, center_world, yaw, heading_up, sc)
	var ang := 0.0 if heading_up else -yaw
	var fwd := Vector2(0, -1).rotated(ang)
	var tri := PackedVector2Array([c + sp + fwd * 11.0, c + sp - fwd * 7.0 + fwd.orthogonal() * 7.0, c + sp - fwd * 7.0 - fwd.orthogonal() * 7.0])
	draw_colored_polygon(tri, UITheme.GREEN)
	_text(c + Vector2(-r, -r - 18.0), "SCANNER", _f_disp, 16, Color(UITheme.CYAN, 0.8))


func _scan(world: Vector2, center_world: Vector2, yaw: float, heading_up: bool, sc: float) -> Vector2:
	var d := world - center_world
	if heading_up:
		# Flugrichtung zeigt nach oben
		d = d.rotated(yaw)
	return d * sc
