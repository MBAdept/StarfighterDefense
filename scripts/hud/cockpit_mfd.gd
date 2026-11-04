class_name CockpitMFD
extends Control
## =============================================================================================
##  Inhalt eines Multifunktionsdisplays (MFD) im Cockpit. Wird in einen SubViewport gezeichnet und
##  von CockpitRig als selbstleuchtender Bildschirm in die Konsole gesetzt.
##   NAV    – Ort, Lage-Untertitel, Zeit/Stufe/Kurs, Bedienhinweise
##   CENTER – Planet: Scanner [ORIGINAL] · Station: Andocken/Tanken · sonst: Waffen
##   LINK   – Datenlink: die letzten Meldungen der strategischen Ebene
## =============================================================================================

enum Page { NAV, CENTER, LINK }

const BG := Color(0.01, 0.026, 0.03)
const INK := Color(0.45, 1.0, 0.62)       ## MFD-Grün
const DIM := Color(0.45, 1.0, 0.62, 0.45)

var combat: CombatBase
var page := Page.NAV
var _t := 0.0
var _f_disp: Font
var _f_body: Font
var _f_med: Font
var _f_mono: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_f_disp = Assets.font("display")
	_f_body = Assets.font("body_bold")
	_f_med = Assets.font("body_med")
	_f_mono = Assets.font("mono")


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


## Neue Meldung in den letzten Sekunden? (Warnlampe DATENLINK)
func fresh_message() -> bool:
	if GameState.events.is_empty():
		return false
	return float(GameState.events.back().t) > GameState.sim_time - 4.0


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	if combat == null:
		return
	match page:
		Page.NAV:
			_draw_nav()
		Page.LINK:
			_draw_link()
		Page.CENTER:
			if combat is PlanetCombat:
				_draw_scanner()
			elif combat is SpaceCombat and (combat as SpaceCombat).is_docking():
				_draw_dock()
			else:
				_draw_weapons()
	# Rahmenlinie und leichte Rasterung (Displaycharakter)
	draw_rect(Rect2(Vector2(3, 3), size - Vector2(6, 6)), Color(INK, 0.12), false, 1.0)


# --- Hilfen ------------------------------------------------------------------------------------
func _txt(pos: Vector2, s: String, f: Font, fs: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	draw_string(f, pos, s, align, width, fs, col)


## Schriftgröße so wählen, dass der Text in die Breite passt.
func _fit(s: String, f: Font, fs: int, width: float, min_fs := 12) -> int:
	var n := fs
	while n > min_fs and f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, n).x > width:
		n -= 1
	return n


## Tastenbeschriftungen am oberen Rand (OSB), die aktive Seite hervorgehoben.
func _osb(labels: Array, active: int) -> void:
	var w := size.x / labels.size()
	for i in labels.size():
		var r := Rect2(Vector2(i * w + 6, 5), Vector2(w - 12, 19))
		if i == active:
			draw_rect(r, Color(INK, 0.16))
			draw_rect(r, Color(INK, 0.7), false, 1.0)
		_txt(Vector2(i * w, 20), labels[i], _f_mono, 14, INK if i == active else DIM, HORIZONTAL_ALIGNMENT_CENTER, w)


# --- NAV ---------------------------------------------------------------------------------------
func _draw_nav() -> void:
	_osb(["NAV", "TAKT", "SYS", "KOMM"], 0)
	var w := size.x - 28.0
	var name_fs := _fit(combat.location_name, _f_disp, 26, w)
	_txt(Vector2(14, 58), combat.location_name, _f_disp, name_fs, UITheme.CYAN)
	var sub := combat.location_sub
	var sub_col := UITheme.AMBER if sub.contains("!") else UITheme.TEXT
	_txt(Vector2(14, 86), sub, _f_body, _fit(sub, _f_body, 22, w), sub_col)
	draw_line(Vector2(14, 98), Vector2(size.x - 14, 98), Color(INK, 0.25), 1.0)
	var heading := 0.0
	if combat.camera:
		var f := -combat.camera.global_transform.basis.z
		heading = fposmod(rad_to_deg(atan2(f.x, -f.z)), 360.0)
	var line := "KURS %03d°" % (int(round(heading)) % 360)
	if GameState.running:
		line = "ZEIT %s   STUFE %d   %s" % [GameState.format_time(GameState.sim_time), GameState.level + 1, line]
	_txt(Vector2(14, 122), line, _f_mono, 18, INK)
	# Bedienhinweise (bis zu zwei Zeilen)
	var hint := combat.hint_text.replace("  ·  ", " · ")
	draw_multiline_string(_f_med, Vector2(14, 146), hint, HORIZONTAL_ALIGNMENT_LEFT, w, 16, 2, Color(UITheme.TEXT_DIM, 0.95))


# --- Datenlink ---------------------------------------------------------------------------------
func _draw_link() -> void:
	_osb(["KOMM", "DATENLINK", "SYS"], 1)
	var ev: Array = GameState.events
	if ev.is_empty():
		_txt(Vector2(0, 110), "KEINE MELDUNGEN", _f_mono, 18, DIM, HORIZONTAL_ALIGNMENT_CENTER, size.x)
		return
	var y := 34.0
	var shown := 0
	var w := size.x - 86.0
	for i in range(ev.size() - 1, -1, -1):
		var e: Dictionary = ev[i]
		var col := UITheme.sev_color(int(e.sev))
		var text: String = e.text
		var lines := 1 if _f_body.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x <= w else 2
		var h := 8.0 + lines * 19.0
		if y + h > size.y - 4.0:
			break
		var age := GameState.sim_time - float(e.t)
		var fresh := age < 4.0 and fmod(_t, 0.5) < 0.3
		draw_rect(Rect2(Vector2(10, y + 2), Vector2(3, h - 6)), col if not fresh else Color(1, 1, 1))
		_txt(Vector2(18, y + 17), GameState.format_time(float(e.t)), _f_mono, 14, Color(col, 0.6))
		draw_multiline_string(_f_body, Vector2(70, y + 17), text, HORIZONTAL_ALIGNMENT_LEFT, w, 17, 2, Color(col.lightened(0.25), 0.95 if shown == 0 else 0.75))
		y += h
		shown += 1
		if shown >= 4:
			break


# --- Scanner [ORIGINAL]: Karte mit eigenem Schiff und Städten ---------------------------------
func _draw_scanner() -> void:
	var pc: PlanetCombat = combat
	var c := Vector2(size.x * 0.5, size.y * 0.5 + 8.0)
	var r := minf(size.x, size.y) * 0.5 - 22.0
	_txt(Vector2(10, 20), "SCANNER", _f_mono, 15, INK)
	_txt(Vector2(0, 20), "KURS OBEN" if Config.scanner_heading_up else "NORD OBEN", _f_mono, 13, DIM, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 10.0)
	draw_circle(c, r, Color(0.01, 0.08, 0.1), true, -1.0, true)
	draw_arc(c, r, 0, TAU, 96, Color(UITheme.CYAN, 0.6), 2.0, true)
	for k in [0.33, 0.66]:
		draw_arc(c, r * k, 0, TAU, 64, Color(UITheme.CYAN, 0.16), 1.0, true)
	draw_line(c - Vector2(r, 0), c + Vector2(r, 0), Color(UITheme.CYAN, 0.1), 1.0)
	draw_line(c - Vector2(0, r), c + Vector2(0, r), Color(UITheme.CYAN, 0.1), 1.0)
	for i in 36:
		var a := i * TAU / 36.0
		var l := 7.0 if i % 9 == 0 else 3.0
		draw_line(c + Vector2.from_angle(a) * r, c + Vector2.from_angle(a) * (r + l), Color(UITheme.CYAN, 0.5), 1.0)
	var sweep := fmod(_t * 1.6, TAU)
	for i in 12:
		var a := sweep - i * 0.04
		draw_line(c, c + Vector2.from_angle(a) * r, Color(UITheme.CYAN, 0.14 * (1.0 - i / 12.0)), 2.0, true)
	var heading_up := Config.scanner_heading_up
	var range_m := Config.planet_area_radius * (1.55 if heading_up else 1.12)
	var sc := r / range_m
	var ppos := pc.player_xz()
	var yaw := pc.yaw
	var center_world := ppos if heading_up else Vector2.ZERO
	var area_c := _scan(Vector2.ZERO, center_world, yaw, heading_up, sc)
	draw_arc(c + area_c, Config.planet_area_radius * sc, 0, TAU, 64, Color(UITheme.AMBER, 0.3), 1.5, true)
	for i in pc.planet.cities.size():
		var p := _scan(pc.planet.city_pos[i], center_world, yaw, heading_up, sc)
		if p.length() > r - 4.0:
			p = p.normalized() * (r - 4.0)
		var alive: bool = pc.planet.cities[i]
		var under := pc.city_under_attack(i)
		if pc.enemy_mode and alive:
			var tgt := pc.impact_city == i and not pc.impact_pending and GameState.bombs > 0
			var ec := UITheme.GREEN if tgt else Color(1.0, 0.32, 0.58)
			draw_circle(c + p, 4.5, ec, true, -1.0, true)
			draw_arc(c + p, 8.0, 0, TAU, 20, Color(ec, 0.6), 1.5, true)
			continue
		if not alive:
			var q := c + p
			draw_line(q - Vector2(4, 4), q + Vector2(4, 4), Color(0.5, 0.5, 0.55, 0.85), 2.0)
			draw_line(q - Vector2(4, -4), q + Vector2(4, -4), Color(0.5, 0.5, 0.55, 0.85), 2.0)
		elif under:
			var blink := fmod(_t, 0.5) < 0.3
			draw_circle(c + p, 6.0, UITheme.RED if blink else Color(1.0, 0.7, 0.3), true, -1.0, true)
			draw_arc(c + p, 8.5 + fmod(_t * 14.0, 10.0), 0, TAU, 24, Color(UITheme.RED, 0.6 * (1.0 - fmod(_t * 14.0, 10.0) / 10.0)), 1.5, true)
		else:
			draw_circle(c + p, 4.2, Color(0.55, 1.0, 1.0), true, -1.0, true)
			draw_circle(c + p, 7.5, Color(UITheme.CYAN, 0.2), true, -1.0, true)
	if pc.enemy_mode and pc.weapon == CombatBase.Weapon.BOMB:
		var ip := _scan(Vector2(pc.impact_point.x, pc.impact_point.z), center_world, yaw, heading_up, sc)
		if ip.length() < r - 2.0:
			var icol := UITheme.GREEN if pc.impact_city >= 0 and not pc.impact_pending and GameState.bombs > 0 else UITheme.AMBER
			draw_line(c + ip - Vector2(6, 0), c + ip + Vector2(6, 0), icol, 2.0)
			draw_line(c + ip - Vector2(0, 6), c + ip + Vector2(0, 6), icol, 2.0)
			draw_arc(c + ip, Config.bomb_hit_radius * sc, 0, TAU, 20, Color(icol, 0.6), 1.0, true)
	var sp := _scan(ppos, center_world, yaw, heading_up, sc)
	var ang := 0.0 if heading_up else -yaw
	var fwd := Vector2(0, -1).rotated(ang)
	var tri := PackedVector2Array([c + sp + fwd * 10.0, c + sp - fwd * 6.0 + fwd.orthogonal() * 6.5, c + sp - fwd * 6.0 - fwd.orthogonal() * 6.5])
	draw_colored_polygon(tri, UITheme.GREEN)


func _scan(world: Vector2, center_world: Vector2, yaw: float, heading_up: bool, sc: float) -> Vector2:
	var d := world - center_world
	if heading_up:
		d = d.rotated(yaw)
	return d * sc


# --- Andocken / Tanken -------------------------------------------------------------------------
func _draw_dock() -> void:
	var sc: SpaceCombat = combat
	var title := "ANDOCKEN …"
	match sc.phase:
		SpaceCombat.Phase.DOCK_CLAMP:
			title = "ANDOCKKLAMMERN"
		SpaceCombat.Phase.REFUEL:
			title = "TANKEN"
		SpaceCombat.Phase.DOCKED:
			title = "ABFLUGBEREIT"
	_txt(Vector2(12, 22), "STATION", _f_mono, 15, INK)
	_txt(Vector2(12, 56), title, _f_disp, _fit(title, _f_disp, 24, size.x - 24.0), UITheme.CYAN)
	_txt(Vector2(12, 92), "ENERGIE", _f_mono, 16, DIM)
	_txt(Vector2(0, 124), "%d %%" % int(round(GameState.energy)), _f_mono, 50, UITheme.GREEN, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 14.0)
	var steps := int(Config.energy_max / Config.refuel_step)
	var x0 := 12.0
	var sw := (size.x - 24.0) / steps
	for i in steps:
		var on := (i + 1) * Config.refuel_step <= GameState.energy + 0.01
		draw_rect(Rect2(Vector2(x0 + i * sw, 140), Vector2(sw - 3.0, 30)), Color(UITheme.GREEN, 0.92) if on else Color(UITheme.CYAN, 0.12))
	if Config.enemy_system_enabled:
		# [Vorgabe] Bomben werden nur an eigenen Stationen aufgefüllt
		_txt(Vector2(12, 206), "BOMBEN", _f_mono, 16, Color(UITheme.AMBER, 0.85))
		_txt(Vector2(0, 206), "%d / %d" % [GameState.bombs, Config.bombs_max], _f_mono, 22, UITheme.AMBER, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 14.0)
		var bn := maxi(Config.bombs_max, 1)
		var bpw := (size.x - 24.0) / bn
		for i in bn:
			var r := Rect2(Vector2(x0 + i * bpw, 216), Vector2(bpw - 4.0, 18))
			if i < GameState.bombs:
				draw_rect(r, Color(UITheme.AMBER, 0.92))
			else:
				draw_rect(r, Color(UITheme.AMBER, 0.35), false, 1.0)
	var status := "VERRIEGELT" if sc.phase != SpaceCombat.Phase.DOCK_APPROACH else "ANFLUG"
	_txt(Vector2(0, size.y - 12.0), status, _f_mono, 15, DIM, HORIZONTAL_ALIGNMENT_CENTER, size.x)


# --- Waffen (Weltraum) -------------------------------------------------------------------------
func _draw_weapons() -> void:
	_txt(Vector2(12, 22), "WAFFEN", _f_mono, 15, INK)
	var mode := "AUTO" if Config.auto_weapon_switch else "MANUELL (Q)"
	_txt(Vector2(0, 22), mode, _f_mono, 14, DIM, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 12.0)
	# Draufsicht des eigenen Schiffs
	var c := Vector2(size.x * 0.5, 112.0)
	var s := 1.0
	var hull := PackedVector2Array([Vector2(0, -62), Vector2(9, -34), Vector2(12, 4), Vector2(76, 30), Vector2(80, 44),
		Vector2(14, 38), Vector2(10, 56), Vector2(-10, 56), Vector2(-14, 38), Vector2(-80, 44), Vector2(-76, 30),
		Vector2(-12, 4), Vector2(-9, -34), Vector2(0, -62)])
	for i in hull.size():
		hull[i] = c + hull[i] * s
	draw_polyline(hull, Color(INK, 0.55), 1.5, true)
	var laser := combat.weapon == CombatBase.Weapon.LASER
	var ch := combat.ion_charge()
	# Bordlaser an den Flügelspitzen, Ionen-Kanone im Bug
	for side: float in [-1.0, 1.0]:
		var gp := c + Vector2(side * 70.0, 18.0)
		draw_rect(Rect2(gp - Vector2(4, 12), Vector2(8, 24)), Color(UITheme.CYAN, 0.9 if laser else 0.35))
	var ion_col := UITheme.GREEN if ch >= 1.0 else UITheme.AMBER
	draw_circle(c + Vector2(0, -22), 7.0, Color(ion_col, 0.9 if not laser else 0.45), true, -1.0, true)
	draw_arc(c + Vector2(0, -22), 11.0, -PI * 0.5, -PI * 0.5 + TAU * ch, 24, ion_col, 2.0, true)
	# Statuszeilen
	var y := 196.0
	var rows := [["BORDLASER", "BEREIT", UITheme.CYAN, laser],
		["IONEN-KANONE", "BEREIT" if ch >= 1.0 else "LÄDT %.1f s" % ((1.0 - ch) * Config.ion_cooldown), ion_col, combat.weapon == CombatBase.Weapon.ION]]
	if Config.enemy_system_enabled:
		rows.append(["BOMBEN", "%d / %d" % [GameState.bombs, Config.bombs_max], UITheme.AMBER, false])
	for r in rows:
		if r[3]:
			draw_rect(Rect2(Vector2(8, y - 17), Vector2(size.x - 16, 23)), Color(INK, 0.12))
			draw_rect(Rect2(Vector2(8, y - 17), Vector2(size.x - 16, 23)), Color(INK, 0.6), false, 1.0)
		_txt(Vector2(14, y), r[0], _f_mono, 16, INK if r[3] else DIM)
		_txt(Vector2(0, y), r[1], _f_mono, 16, r[2], HORIZONTAL_ALIGNMENT_RIGHT, size.x - 14.0)
		y += 26.0
