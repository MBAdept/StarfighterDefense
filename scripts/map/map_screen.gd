class_name MapScreen
extends Control
## =============================================================================================
##  Übersichtskarte [ORIGINAL]: Stern in der Mitte, Planeten auf Umlaufbahnen, 2 Raumstationen,
##  Sprungpunkt zum Feindsystem oben links (kleine Galaxie), feindliche Schwadrone als kleine
##  Rechtecke (max. 4). Alle Ziele auswählbar; nach Auswahl Sprung.
##  Infofenster bei Planeten: Name, verbleibende Städte, ob ein Feind angreift.
##  Angegriffene Stationen blinken.
##  Feindsystem: Stern Vorrhal, 5 Planeten (Heimatwelt innen), startende Schwadrone auf dem Weg zum
##  Sprungpunkt unten rechts (Symbol: unser Stern = Rücksprung nach Helion).
##  Q/Tab: das jeweils andere System ansehen (nur Beobachtung).
## =============================================================================================

const PANEL_W := 470.0
const TOP_H := 96.0

var _t := 0.0
var map_center := Vector2.ZERO
var map_scale := 1.0
var sel_kind := -1
var sel_id := -1
var _targets: Array = []
var _planet_rects := {}
var _sun: ColorRect
var _galaxy: ColorRect
var _gate_sun: ColorRect          ## Feindsystem: Rücksprungpunkt (unser Stern als Symbol)
var view_system := 0              ## 0 = Helion, 1 = Feindsystem (angezeigt)
var _launch_fx: Array = []        ## [{pos: Vector2 (Karte), t}] Startanimation neuer Schwadrone
var _back: Control
var _front: Control
var _bg: TextureRect
var _message := ""
var _message_t := 10.0
var _f_title: Font
var _f_disp: Font
var _f_body: Font
var _f_bold: Font
var _f_mono: Font
var _last_hover := Vector2(-1, -1)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.get_theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	_f_title = Assets.font("title")
	_f_disp = Assets.font("display")
	_f_body = Assets.font("body")
	_f_bold = Assets.font("body_bold")
	_f_mono = Assets.font("mono")
	view_system = GameState.player_system
	var dark := ColorRect.new()
	dark.color = Color(0.0, 0.005, 0.02)
	dark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dark)
	var bgt := Assets.tex("map/map_background.png")
	if bgt:
		_bg = TextureRect.new()
		_bg.texture = bgt
		_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_bg.modulate = Color(0.85, 0.9, 1.0, 1.0)
		_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_bg)
	_back = Control.new()
	_back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back.draw.connect(_draw_back)
	add_child(_back)
	_sun = ColorRect.new()
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/map_sun.gdshader")
	_sun.material = sm
	_sun.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_sun)
	_galaxy = ColorRect.new()
	var gm := ShaderMaterial.new()
	gm.shader = load("res://shaders/map_galaxy.gdshader")
	gm.set_shader_parameter("active", 1.0 if Config.enemy_system_enabled else 0.0)
	_galaxy.material = gm
	_galaxy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_galaxy)
	_gate_sun = ColorRect.new()
	var gsm := ShaderMaterial.new()
	gsm.shader = load("res://shaders/map_sun.gdshader")
	_gate_sun.material = gsm
	_gate_sun.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_gate_sun)
	for p in GameState.planets + GameState.enemy_planets:
		var r := ColorRect.new()
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/map_planet.gdshader")
		var t := Assets.tex("planets/%s.png" % p.type)
		if t:
			m.set_shader_parameter("albedo_tex", t)
			m.set_shader_parameter("use_tex", true)
		var pal := PlanetLook.palette(p.type)
		m.set_shader_parameter("color_a", pal[0])
		m.set_shader_parameter("color_b", pal[1])
		m.set_shader_parameter("atmo", PlanetLook.atmosphere(p.type))
		m.set_shader_parameter("spin", p.id * 0.17)
		r.material = m
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(r)
		_planet_rects[p] = r
	_front = Control.new()
	_front.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_front.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_front.draw.connect(_draw_front)
	add_child(_front)
	_layout()
	_apply_view()
	_select_initial()
	get_viewport().size_changed.connect(_layout)
	GameState.enemy_squadron_launched.connect(_on_enemy_launch)


func _on_enemy_launch(_sq: SquadronData, p: PlanetData) -> void:
	_launch_fx.append({"planet": p, "t": 0.0})


## Darstellung auf das angezeigte System umstellen (Stern, Sprungpunkt-Symbol, Hintergrund, Planeten).
func _apply_view() -> void:
	var enemy := view_system == 1
	var sm := _sun.material as ShaderMaterial
	sm.set_shader_parameter("core_color", Color(1.0, 0.72, 0.58) if enemy else Color(1.0, 0.92, 0.7))
	sm.set_shader_parameter("corona_color", Color(1.0, 0.22, 0.12) if enemy else Color(1.0, 0.6, 0.2))
	_galaxy.visible = not enemy
	_gate_sun.visible = enemy
	for p in _planet_rects:
		(_planet_rects[p] as ColorRect).visible = (p as PlanetData).is_enemy == enemy
	if _bg:
		var et := Assets.tex("map/map_background_enemy.png") if enemy else null
		_bg.texture = et if et else Assets.tex("map/map_background.png")
		_bg.modulate = Color(1.0, 0.72, 0.78) if enemy and et == null else Color(0.85, 0.9, 1.0, 1.0)
	_layout()


func _view_planets() -> Array:
	return GameState.enemy_planets if view_system == 1 else GameState.planets


func _view_squadrons() -> Array:
	return GameState.enemy_squadrons if view_system == 1 else GameState.squadrons


func _gate_pos() -> Vector2:
	return GameState.ENEMY_GATE if view_system == 1 else GameState.JUMP_POINT


func _planet_kind() -> int:
	return GameState.Loc.ENEMY_PLANET if view_system == 1 else GameState.Loc.PLANET


func _gate_kind() -> int:
	return GameState.Loc.HOME_SYSTEM if view_system == 1 else GameState.Loc.ENEMY_SYSTEM


func _planet_of(kind: int, id: int) -> PlanetData:
	if kind == GameState.Loc.ENEMY_PLANET and id >= 0 and id < GameState.enemy_planets.size():
		return GameState.enemy_planets[id]
	if kind == GameState.Loc.PLANET and id >= 0 and id < GameState.planets.size():
		return GameState.planets[id]
	return null


## Nur Ansicht: das angezeigte System ist nicht das, in dem sich der Spieler befindet.
func is_foreign_view() -> bool:
	return view_system != GameState.player_system


func toggle_view() -> void:
	if not Config.enemy_system_enabled:
		return
	view_system = 1 - view_system
	_apply_view()
	sel_kind = -1
	sel_id = -1
	_select_initial()
	Audio.ui("ui_select")


func can_close() -> bool:
	return true


func _layout() -> void:
	var vp := get_viewport_rect().size
	var area := Rect2(Vector2(20, TOP_H + 10), Vector2(vp.x - PANEL_W - 50, vp.y - TOP_H - 70))
	map_scale = minf(area.size.x / GameState.MAP_SIZE.x, area.size.y / GameState.MAP_SIZE.y) * 0.98
	map_center = area.get_center()
	var sr := 110.0 * map_scale / 0.9 * (0.72 if view_system == 1 else 1.0)
	_sun.position = map_center - Vector2(sr, sr)
	_sun.size = Vector2(sr, sr) * 2.0
	var gs := 92.0 * map_scale / 0.9
	var gp := to_screen(GameState.JUMP_POINT)
	_galaxy.position = gp - Vector2(gs, gs)
	_galaxy.size = Vector2(gs, gs) * 2.0
	var hs := 46.0 * map_scale / 0.9
	var hp := to_screen(GameState.ENEMY_GATE)
	_gate_sun.position = hp - Vector2(hs, hs)
	_gate_sun.size = Vector2(hs, hs) * 2.0


func to_screen(m: Vector2) -> Vector2:
	return map_center + m * map_scale


func _planet_radius(p: PlanetData) -> float:
	return (17.0 if p.is_home else 13.0 + (p.id % 3) * 1.5) * map_scale / 0.9


# =============================================================================================
#  Ziele / Auswahl
# =============================================================================================
func _rebuild_targets() -> void:
	_targets.clear()
	for p in _view_planets():
		_targets.append({"kind": _planet_kind(), "id": p.id, "pos": to_screen(p.map_pos())})
	if view_system == 0:
		for s in GameState.stations:
			if not s.destroyed:
				_targets.append({"kind": GameState.Loc.STATION, "id": s.id, "pos": to_screen(s.map_pos())})
	for sq in _view_squadrons():
		_targets.append({"kind": GameState.Loc.SQUADRON, "id": sq.id, "pos": _squadron_screen(sq)})
	_targets.append({"kind": _gate_kind(), "id": -1, "pos": to_screen(_gate_pos())})


func _squadron_screen(sq: SquadronData) -> Vector2:
	var p := to_screen(sq.map_pos)
	if sq.state == SquadronData.State.WAITING:
		# wartende Schwadrone über dem Sprungpunkt gestapelt (Beschriftung rechts daneben)
		var widx := 0
		for o in GameState.enemy_squadrons:
			if o == sq:
				break
			if o.state == SquadronData.State.WAITING:
				widx += 1
		p += Vector2(-24, -74 - 40 * widx) * map_scale / 0.9
	elif sq.state != SquadronData.State.TRANSIT:
		p += Vector2(20, -20) * map_scale / 0.9
	return p


func _target_valid(kind: int, id: int) -> bool:
	for t in _targets:
		if t.kind == kind and t.id == id:
			return true
	return false


func _target_pos(kind: int, id: int) -> Vector2:
	for t in _targets:
		if t.kind == kind and t.id == id:
			return t.pos
	return map_center


func _select_initial() -> void:
	_rebuild_targets()
	if GameState.reception_active and not is_foreign_view() and view_system == 1:
		_select(GameState.Loc.HOME_SYSTEM, -1, false)   # während des Empfangskomitees nur Rücksprung
		return
	match GameState.player_loc:
		GameState.Loc.PLANET, GameState.Loc.STATION, GameState.Loc.SQUADRON, GameState.Loc.ENEMY_PLANET:
			if _target_valid(GameState.player_loc, GameState.player_loc_id):
				_select(GameState.player_loc, GameState.player_loc_id, false)
				return
	# sonst: nächstgelegenes bedrohtes Ziel bzw. nächstes Ziel
	var best: Dictionary = {}
	var bd := INF
	var me := to_screen(GameState.player_map_pos if not is_foreign_view() else _gate_pos())
	for t in _targets:
		if t.kind == GameState.Loc.ENEMY_SYSTEM or t.kind == GameState.Loc.HOME_SYSTEM:
			continue
		var d: float = t.pos.distance_to(me)
		if t.kind == GameState.Loc.SQUADRON:
			d *= 0.5
		if d < bd:
			bd = d
			best = t
	if not best.is_empty():
		_select(best.kind, best.id, false)


func _select(kind: int, id: int, sound := true) -> void:
	if kind == sel_kind and id == sel_id:
		return
	sel_kind = kind
	sel_id = id
	if sound:
		Audio.ui("ui_move")


func _move_selection(dir: Vector2) -> void:
	_rebuild_targets()
	var cur := _target_pos(sel_kind, sel_id)
	var best: Dictionary = {}
	var bs := INF
	for t in _targets:
		if t.kind == sel_kind and t.id == sel_id:
			continue
		var v: Vector2 = t.pos - cur
		var l := v.length()
		if l < 1.0:
			continue
		var dot := v.normalized().dot(dir)
		if dot < 0.35:
			continue
		var score := l * (2.2 - dot * 1.2)
		if score < bs:
			bs = score
			best = t
	if not best.is_empty():
		_select(best.kind, best.id)


func _cycle(step: int) -> void:
	_rebuild_targets()
	var idx := 0
	for i in _targets.size():
		if _targets[i].kind == sel_kind and _targets[i].id == sel_id:
			idx = i
	idx = (idx + step + _targets.size()) % _targets.size()
	_select(_targets[idx].kind, _targets[idx].id)


func _is_current(kind: int, id: int) -> bool:
	return GameState.player_loc == kind and GameState.player_loc_id == id


func _sel_map_pos() -> Vector2:
	match sel_kind:
		GameState.Loc.PLANET:
			return GameState.planets[sel_id].map_pos()
		GameState.Loc.ENEMY_PLANET:
			return GameState.enemy_planets[sel_id].map_pos()
		GameState.Loc.HOME_SYSTEM:
			return GameState.ENEMY_GATE
		GameState.Loc.STATION:
			return GameState.stations[sel_id].map_pos()
		GameState.Loc.SQUADRON:
			var sq := GameState.squadron_by_id(sel_id)
			return sq.map_pos if sq else GameState.player_map_pos
		GameState.Loc.ENEMY_SYSTEM:
			return GameState.JUMP_POINT
	return GameState.player_map_pos


func _confirm() -> void:
	if sel_kind < 0:
		return
	if is_foreign_view():
		Audio.ui("ui_error")
		_flash_message("Nur Ansicht – Q/Tab: zurück zum eigenen Standort")
		return
	if sel_kind == GameState.Loc.ENEMY_SYSTEM and not Config.enemy_system_enabled:
		Audio.ui("ui_error")
		_flash_message("Sprung ins Feindsystem ist abgeschaltet")
		return
	if GameState.reception_active and sel_kind != GameState.Loc.HOME_SYSTEM:
		Audio.ui("ui_error")
		_flash_message("Erst das Empfangskomitee abwehren! (nur Rücksprung möglich)")
		return
	if _is_current(sel_kind, sel_id):
		Main.instance.close_map()
		return
	var cost := GameState.jump_cost_to(sel_kind, _sel_map_pos())
	if Config.jump_can_kill and cost >= GameState.energy:
		Audio.ui("ui_error")
		_flash_message("Nicht genug Energie für diesen Sprung")
		return
	Audio.ui("ui_select")
	Main.instance.request_jump(sel_kind, sel_id)


func _flash_message(s: String) -> void:
	_message = s
	_message_t = 0.0


# =============================================================================================
#  Eingabe
# =============================================================================================
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var hit := _target_at(event.position)
		if not hit.is_empty():
			_select(hit.kind, hit.id)
		accept_event()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var hit2 := _target_at(event.position)
		if not hit2.is_empty():
			_select(hit2.kind, hit2.id, false)
			_confirm()
		accept_event()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouse:
		return
	if event.is_action_pressed("ui_cancel"):
		Main.instance.close_map()
		get_viewport().set_input_as_handled()
		return
	var dir := Vector2.ZERO
	if event.is_action_pressed("steer_left", true) or event.is_action_pressed("ui_left", true):
		dir = Vector2.LEFT
	elif event.is_action_pressed("steer_right", true) or event.is_action_pressed("ui_right", true):
		dir = Vector2.RIGHT
	elif event.is_action_pressed("steer_up", true) or event.is_action_pressed("ui_up", true):
		dir = Vector2.UP
	elif event.is_action_pressed("steer_down", true) or event.is_action_pressed("ui_down", true):
		dir = Vector2.DOWN
	if dir != Vector2.ZERO:
		_move_selection(dir)
		get_viewport().set_input_as_handled()
		return
	# RB ist zugleich "nächstes Ziel" – dann blättern statt umschalten
	if event.is_action_pressed("switch_weapon") and not event.is_echo() and not event.is_action_pressed("map_next"):
		toggle_view()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("map_next"):
		_cycle(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("map_prev"):
		_cycle(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("fire") and not (event is InputEventMouseButton):
		_confirm()
		get_viewport().set_input_as_handled()


func _target_at(p: Vector2) -> Dictionary:
	_rebuild_targets()
	var best: Dictionary = {}
	var bd := 30.0 * map_scale / 0.9 + 8.0
	for t in _targets:
		var d: float = t.pos.distance_to(p)
		if d < bd:
			bd = d
			best = t
	return best


# =============================================================================================
#  Zeichnen
# =============================================================================================
func _process(delta: float) -> void:
	_t += delta
	_message_t += delta
	_rebuild_targets()
	if not _target_valid(sel_kind, sel_id):
		_select_initial()
	for fx in _launch_fx:
		fx.t += delta
	_launch_fx = _launch_fx.filter(func(fx): return fx.t < 2.4)
	for p in _view_planets():
		var r: ColorRect = _planet_rects[p]
		var rad := _planet_radius(p)
		var sp := to_screen(p.map_pos())
		var half := rad / 0.72
		r.position = sp - Vector2(half, half)
		r.size = Vector2(half, half) * 2.0
		var m := r.material as ShaderMaterial
		m.set_shader_parameter("light_dir", (map_center - sp).normalized())
		m.set_shader_parameter("spin", p.id * 0.17 + _t * 0.01)
	(_galaxy.material as ShaderMaterial).set_shader_parameter("highlight", 1.0 if sel_kind == GameState.Loc.ENEMY_SYSTEM else 0.0)
	_back.queue_redraw()
	_front.queue_redraw()


func _draw_back() -> void:
	var c := map_center
	# feines Koordinatengitter
	for i in range(-8, 9):
		var x := c.x + i * 100.0 * map_scale
		_back.draw_line(Vector2(x, c.y - 450 * map_scale), Vector2(x, c.y + 450 * map_scale), Color(UITheme.CYAN, 0.025), 1.0)
	for j in range(-4, 5):
		var y := c.y + j * 100.0 * map_scale
		_back.draw_line(Vector2(c.x - 800 * map_scale, y), Vector2(c.x + 800 * map_scale, y), Color(UITheme.CYAN, 0.025), 1.0)
	# Umlaufbahnen
	for p in _view_planets():
		var sel: bool = sel_kind == _planet_kind() and sel_id == p.id
		var attacked: bool = p.landed_squadron != -1
		var col := Color(UITheme.CYAN, 0.32 if sel else 0.13)
		if attacked:
			col = Color(UITheme.RED, 0.25 + 0.15 * sin(_t * 5.0))
		if p.is_enemy:
			col = Color(1.0, 0.45, 0.6, 0.3 if sel else 0.12)
		_back.draw_arc(c, p.orbit_radius * map_scale, 0, TAU, 160, col, 1.5 if sel else 1.0, true)
	if view_system == 0:
		for s in GameState.stations:
			if not s.destroyed:
				_dashed_circle(_back, c, s.orbit_radius * map_scale, Color(0.6, 1.0, 0.8, 0.12))
	# Schwadron-Kurse
	for sq in _view_squadrons():
		if sq.state == SquadronData.State.TRANSIT:
			var a := to_screen(sq.map_pos)
			var b := to_screen(GameState.squadron_target_pos(sq))
			_dashed_line(_back, a, b, Color(UITheme.RED, 0.38), 8.0, 6.0, _t * 12.0)
	# Sprunglinie
	if sel_kind >= 0 and not is_foreign_view() and not _is_current(sel_kind, sel_id) and not (sel_kind == GameState.Loc.ENEMY_SYSTEM and not Config.enemy_system_enabled) and not (GameState.reception_active and sel_kind != GameState.Loc.HOME_SYSTEM):
		var a2 := to_screen(GameState.player_map_pos)
		var b2 := _target_pos(sel_kind, sel_id)
		var cross := GameState.is_cross_system(sel_kind)
		var lcol := Color(1.0, 0.35, 0.3, 0.8) if cross else Color(UITheme.CYAN, 0.7)
		_dashed_line(_back, a2, b2, lcol, 10.0, 6.0, -_t * 30.0)
		if a2.distance_to(b2) > 90.0:
			var mid := (a2 + b2) * 0.5
			var cost := GameState.effective_jump_cost_to(sel_kind, _sel_map_pos())
			_text(_back, mid + Vector2(10, -10), "−%d %%" % int(round(cost)), _f_mono, 20, lcol)


func _draw_front() -> void:
	var vp := size
	var f := _front
	var enemy_view := view_system == 1
	# Stern
	var star_name := GameState.ENEMY_STAR_NAME if enemy_view else GameState.STAR_NAME
	_text(f, map_center + Vector2(-60, 70 * map_scale / 0.9 + 10.0), star_name.to_upper(), _f_disp, 15, Color(1.0, 0.6, 0.5, 0.75) if enemy_view else Color(1.0, 0.85, 0.6, 0.7), HORIZONTAL_ALIGNMENT_CENTER, 120)
	if enemy_view:
		# Rücksprungpunkt (unser Stern als Symbol)
		var hp := to_screen(GameState.ENEMY_GATE)
		f.draw_arc(hp, 52.0 * map_scale / 0.9, _t * 0.6, _t * 0.6 + TAU * 0.8, 48, Color(1.0, 0.85, 0.5, 0.45), 1.5, true)
		# Beschriftung links unterhalb (rechts liegt das Infofenster)
		_text(f, hp + Vector2(-380, 60 * map_scale / 0.9 + 6), "%s · RÜCKSPRUNG" % GameState.STAR_NAME.to_upper(), _f_disp, 15, Color(1.0, 0.86, 0.55, 0.9), HORIZONTAL_ALIGNMENT_RIGHT, 420)
		var waiting := 0
		for esq in GameState.enemy_squadrons:
			if esq.state == SquadronData.State.WAITING:
				waiting += 1
		var gl := "Sprungpunkt ins %s-System" % GameState.STAR_NAME if waiting == 0 else "%d Schwadron(e) warten auf den Sprung" % waiting
		_text(f, hp + Vector2(-380, 60 * map_scale / 0.9 + 28), gl, _f_body, 17, Color(UITheme.TEXT_DIM, 0.85) if waiting == 0 else Color(UITheme.RED, 0.9), HORIZONTAL_ALIGNMENT_RIGHT, 420)
	else:
		# Feindsystem (Galaxie)
		var gp := to_screen(GameState.JUMP_POINT)
		_text(f, gp + Vector2(-110, 70 * map_scale / 0.9), "FEINDSYSTEM", _f_disp, 16, Color(0.85, 0.6, 1.0, 0.85), HORIZONTAL_ALIGNMENT_CENTER, 220)
		var gsub := "abgeschaltet"
		if Config.enemy_system_enabled:
			gsub = "%s · Sprung %d %%" % [GameState.ENEMY_STAR_NAME, int(Config.enemy_jump_cost)]
		_text(f, gp + Vector2(-110, 70 * map_scale / 0.9 + 22), gsub, _f_body, 18, Color(UITheme.TEXT_DIM, 0.8), HORIZONTAL_ALIGNMENT_CENTER, 220)
	# Startanimation neuer Schwadrone (Feindsystem)
	if enemy_view:
		for fx in _launch_fx:
			var lp := to_screen((fx.planet as PlanetData).map_pos())
			var k: float = fx.t / 2.4
			f.draw_arc(lp, 20.0 + k * 46.0, 0, TAU, 40, Color(UITheme.RED, 0.9 * (1.0 - k)), 2.5, true)
			_text(f, lp + Vector2(-90, -30 - k * 18.0), "START!", _f_disp, 16, Color(UITheme.RED, 1.0 - k), HORIZONTAL_ALIGNMENT_CENTER, 180)
	# Planeten-Beschriftung und Angriffsringe
	for p in _view_planets():
		var sp := to_screen(p.map_pos())
		var rad := _planet_radius(p)
		if p.landed_squadron != -1:
			var k := fmod(_t * 1.4, 1.0)
			f.draw_arc(sp, rad + 6.0 + k * 18.0, 0, TAU, 40, Color(UITheme.RED, 0.8 * (1.0 - k)), 2.0, true)
			f.draw_arc(sp, rad + 5.0, 0, TAU, 40, Color(UITheme.RED, 0.7), 2.0, true)
		if p.is_enemy:
			var ealive: int = p.alive_cities()
			var ecol := Color(1.0, 0.45, 0.62) if ealive > 0 else Color(0.55, 0.55, 0.6)
			_text(f, sp + Vector2(-150, rad + 24), p.name.to_upper(), _f_disp, 15, Color(ecol, 0.95), HORIZONTAL_ALIGNMENT_CENTER, 300)
			var esub := UITheme.cities_text(ealive) if ealive > 0 else "ausgeschaltet"
			if p.is_home:
				esub = "Heimatwelt · " + esub
			if ealive > 0 and p.defenders > 0:
				esub += " · %d Abwehr" % p.defenders
			# dunkle Unterlegung: die Heimatwelt kreist dicht am hellen Stern
			var tw := _f_body.get_string_size(esub, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
			f.draw_rect(Rect2(sp + Vector2(-tw * 0.5 - 6, rad + 27), Vector2(tw + 12, 24)), Color(0.02, 0.0, 0.03, 0.5))
			_text(f, sp + Vector2(-150, rad + 44), esub, _f_body, 18, Color(UITheme.TEXT_DIM if ealive > 0 else UITheme.GREEN, 0.9), HORIZONTAL_ALIGNMENT_CENTER, 300)
			if p.is_home:
				f.draw_arc(sp, rad + 3.0, 0, TAU, 40, Color(1.0, 0.3, 0.55, 0.6), 1.5, true)
			continue
		var incoming := false
		for sq in GameState.squadrons:
			if sq.state == SquadronData.State.TRANSIT and sq.target_kind == SquadronData.TargetKind.PLANET and sq.target_id == p.id:
				incoming = true
		var name_col := UITheme.RED if p.landed_squadron != -1 else (UITheme.AMBER if incoming else UITheme.TEXT)
		_text(f, sp + Vector2(-80, rad + 24), p.name.to_upper(), _f_disp, 15, Color(name_col, 0.95), HORIZONTAL_ALIGNMENT_CENTER, 160)
		var alive: int = p.alive_cities()
		_text(f, sp + Vector2(-80, rad + 44), UITheme.cities_text(alive), _f_body, 18, Color(UITheme.TEXT_DIM if alive > 0 else UITheme.RED, 0.9), HORIZONTAL_ALIGNMENT_CENTER, 160)
		if p.is_home:
			f.draw_arc(sp, rad + 3.0, 0, TAU, 40, Color(UITheme.GREEN, 0.5), 1.5, true)
	# Stationen
	for s in (GameState.stations if not enemy_view else []):
		if s.destroyed:
			var dp := to_screen(s.map_pos())
			_text(f, dp + Vector2(-60, 6), "✕ " + s.name, _f_body, 16, Color(0.5, 0.5, 0.55, 0.6), HORIZONTAL_ALIGNMENT_CENTER, 120)
			continue
		_draw_station_icon(f, s)
	# Schwadrone (kleine Rechtecke)  [ORIGINAL]
	for sq in _view_squadrons():
		_draw_squadron(f, sq)
	# Spieler
	if not is_foreign_view():
		var pp := to_screen(GameState.player_map_pos)
		var pr := 14.0 + 4.0 * sin(_t * 4.0)
		f.draw_arc(pp, pr, 0, TAU, 32, Color(UITheme.GREEN, 0.7), 2.0, true)
		var tri := PackedVector2Array([pp + Vector2(0, -9), pp + Vector2(7, 7), pp + Vector2(0, 3), pp + Vector2(-7, 7)])
		f.draw_colored_polygon(tri, UITheme.GREEN)
		_text(f, pp + Vector2(-pr - 44, 6), "DU", _f_disp, 14, UITheme.GREEN, HORIZONTAL_ALIGNMENT_RIGHT, 30)
	# Auswahl
	if sel_kind >= 0:
		var spos := _target_pos(sel_kind, sel_id)
		var s2 := 26.0 + 3.0 * sin(_t * 6.0)
		var selp := _planet_of(sel_kind, sel_id)
		if selp:
			s2 += _planet_radius(selp) - 8.0
		elif sel_kind == GameState.Loc.ENEMY_SYSTEM:
			s2 += 30.0
		elif sel_kind == GameState.Loc.HOME_SYSTEM:
			s2 += 14.0
		var col := UITheme.CYAN
		for i in 4:
			var d := Vector2(1, 1).rotated(i * PI * 0.5)
			var corner := spos + d * s2
			f.draw_line(corner, corner - Vector2(d.x, 0) * 12.0, col, 2.5, true)
			f.draw_line(corner, corner - Vector2(0, d.y) * 12.0, col, 2.5, true)
	_draw_top(vp)
	_draw_panel(vp)
	_draw_events(vp)
	if _message_t < 2.5:
		var a := clampf(2.5 - _message_t, 0.0, 1.0)
		_text(f, Vector2(0, vp.y * 0.5), _message, _f_disp, 30, Color(UITheme.AMBER, a), HORIZONTAL_ALIGNMENT_CENTER, vp.x - PANEL_W)
	if is_foreign_view():
		var bl := "ANSICHT %s – NUR BEOBACHTUNG · Q/TAB: ZURÜCK" % ("FEINDSYSTEM" if enemy_view else "%s-SYSTEM" % GameState.STAR_NAME.to_upper())
		_text(f, Vector2(0, TOP_H + 40), bl, _f_disp, 20, Color(UITheme.AMBER, 0.6 + 0.3 * sin(_t * 3.0)), HORIZONTAL_ALIGNMENT_CENTER, vp.x - PANEL_W)
	elif GameState.reception_active:
		_text(f, Vector2(0, TOP_H + 40), "EMPFANGSKOMITEE AKTIV – NUR RÜCKSPRUNG MÖGLICH", _f_disp, 20, Color(UITheme.RED, 0.6 + 0.3 * sin(_t * 4.0)), HORIZONTAL_ALIGNMENT_CENTER, vp.x - PANEL_W)


func _draw_station_icon(f: Control, s: StationData) -> void:
	var sp := to_screen(s.map_pos())
	var attacked := s.attacker != -1
	var blink := attacked and fmod(_t, 0.6) < 0.3   # [ORIGINAL] angegriffene Station blinkt
	var col := Color(0.55, 1.0, 0.8) if not attacked else (UITheme.RED if blink else Color(1.0, 0.75, 0.3))
	var r := 9.0 * map_scale / 0.9
	f.draw_arc(sp, r, 0, TAU, 28, col, 2.5, true)
	f.draw_arc(sp, r + 4.0, _t, _t + 1.2, 12, Color(col, 0.6), 1.5, true)
	f.draw_arc(sp, r + 4.0, _t + PI, _t + PI + 1.2, 12, Color(col, 0.6), 1.5, true)
	f.draw_line(sp - Vector2(r * 0.55, 0), sp + Vector2(r * 0.55, 0), col, 2.0)
	f.draw_line(sp - Vector2(0, r * 0.55), sp + Vector2(0, r * 0.55), col, 2.0)
	if attacked:
		f.draw_arc(sp, r + 10.0 + fmod(_t * 20.0, 14.0), 0, TAU, 32, Color(UITheme.RED, 0.7 * (1.0 - fmod(_t * 20.0, 14.0) / 14.0)), 2.0, true)
	var short_name := s.name.to_upper().replace("STATION ", "ST. ")
	_text(f, sp + Vector2(r + 8, -4), short_name, _f_disp, 12, Color(col, 0.9))
	if attacked:
		_text(f, sp + Vector2(r + 8, 16), "%d %%" % int(s.integrity), _f_mono, 16, Color(UITheme.RED, 0.9))


func _draw_squadron(f: Control, sq: SquadronData) -> void:
	var sp := _squadron_screen(sq)
	var w := 16.0 * map_scale / 0.9 + 2.0 * minf(sq.strength() / 10.0, 2.0)
	var h := w * 0.66
	var blink := sq.state != SquadronData.State.TRANSIT and fmod(_t, 0.5) < 0.25
	var col := UITheme.RED if not blink else Color(1.0, 0.8, 0.4)
	var rect := Rect2(sp - Vector2(w, h) * 0.5, Vector2(w, h))
	f.draw_rect(rect.grow(5.0), Color(col, 0.15))
	f.draw_rect(rect, Color(col, 0.85))
	f.draw_rect(rect, Color(1, 1, 1, 0.6), false, 1.0)
	if sq.has_flagship:
		f.draw_rect(Rect2(rect.position + Vector2(rect.size.x * 0.35, -5), Vector2(rect.size.x * 0.3, 3)), UITheme.PINK)
	var label := sq.name.to_upper().replace("SCHWADRON ", "")
	_text(f, sp + Vector2(w * 0.5 + 6, 5), label, _f_disp, 12, Color(UITheme.RED, 0.9))
	if GameState.is_squadron_stopped(sq):
		_text(f, sp + Vector2(w * 0.5 + 6, 22), "steht", _f_body, 15, Color(UITheme.TEXT_DIM, 0.9))
	elif sq.state == SquadronData.State.WAITING:
		_text(f, sp + Vector2(w * 0.5 + 6, 22), "wartet", _f_body, 15, Color(UITheme.TEXT_DIM, 0.9))


func _draw_top(vp: Vector2) -> void:
	var f := _front
	var enemy_view := view_system == 1
	var accent := Color(1.0, 0.42, 0.5) if enemy_view else UITheme.CYAN
	f.draw_rect(Rect2(Vector2.ZERO, Vector2(vp.x, TOP_H - 14)), Color(0.05, 0.0, 0.02, 0.78) if enemy_view else Color(0.0, 0.02, 0.05, 0.75))
	f.draw_line(Vector2(0, TOP_H - 14), Vector2(vp.x, TOP_H - 14), Color(accent, 0.5), 2.0)
	_text(f, Vector2(36, 52), "FEINDKARTE" if enemy_view else "SYSTEMKARTE", _f_title, 30, accent)
	_text(f, Vector2(370, 50), "%s-SYSTEM" % (GameState.ENEMY_STAR_NAME if enemy_view else GameState.STAR_NAME).to_upper(), _f_disp, 18, Color(UITheme.TEXT_DIM, 0.9))
	var x := vp.x - 1290.0
	var e := GameState.energy
	var ecol := UITheme.GREEN if e >= 50.0 else (UITheme.AMBER if e >= Config.energy_low_warning else UITheme.RED)
	_text(f, Vector2(x, 34), "ENERGIE", _f_disp, 14, Color(UITheme.CYAN, 0.8))
	_text(f, Vector2(x, 68), "%d %%" % int(ceil(e)), _f_mono, 32, ecol)
	f.draw_rect(Rect2(Vector2(x + 110, 46), Vector2(160, 14)), Color(ecol, 0.15))
	f.draw_rect(Rect2(Vector2(x + 110, 46), Vector2(160 * e / Config.energy_max, 14)), ecol)
	var stats := [["PUNKTE", "%07d" % GameState.score], ["ZEIT", GameState.format_time(GameState.sim_time)]]
	if enemy_view:
		var rate := GameState.enemy_production_rate()
		stats.append(["FEINDSTÄDTE", "%d / %d" % [GameState.enemy_cities_alive(), GameState.enemy_cities_total()]])
		stats.append(["PRODUKTION", "%d %%" % int(round(rate * 100.0)) if rate > 0.0 else "GESTOPPT"])
		stats.append(["UNTERWEGS", "%d / %d" % [GameState.enemy_squadrons.size(), Config.enemy_system_max_squadrons]])
	else:
		stats.append(["STUFE", str(GameState.level + 1)])
		stats.append(["STÄDTE", "%d / %d" % [GameState.total_alive_cities(), GameState.total_cities()]])
		stats.append(["SCHWADRONE", "%d / %d" % [GameState.squadrons.size(), Config.max_squadrons]])
	if Config.enemy_system_enabled:
		stats.append(["BOMBEN", "%d / %d" % [GameState.bombs, Config.bombs_max]])
	var sx := x + 300.0
	var step := minf(175.0, (vp.x - sx - 20.0) / maxf(stats.size(), 1))
	for s in stats:
		_text(f, Vector2(sx, 34), s[0], _f_disp, 14, Color(accent, 0.8))
		_text(f, Vector2(sx, 68), s[1], _f_mono, 26, UITheme.TEXT)
		sx += step


func _draw_panel(vp: Vector2) -> void:
	var f := _front
	var o := Vector2(vp.x - PANEL_W - 24, TOP_H + 10)
	var h := vp.y - TOP_H - 40
	var r := Rect2(o, Vector2(PANEL_W, h))
	f.draw_rect(r, Color(0.01, 0.04, 0.08, 0.86))
	f.draw_rect(r, Color(UITheme.CYAN, 0.45), false, 2.0)
	f.draw_rect(Rect2(o, Vector2(PANEL_W, 4)), Color(UITheme.CYAN, 0.8))
	var x := o.x + 26
	var y := o.y + 48
	var w := PANEL_W - 52
	var cost_line := ""
	var can_jump := true
	match sel_kind:
		GameState.Loc.PLANET:
			var p: PlanetData = GameState.planets[sel_id]
			_text(f, Vector2(x, y), p.name.to_upper(), _f_title, 34, Color(1, 1, 1))
			y += 32
			_text(f, Vector2(x, y), ("HEIMATPLANET · " if p.is_home else "") + _type_name(p.type), _f_bold, 22, Color(UITheme.CYAN, 0.9))
			y += 46
			_text(f, Vector2(x, y), "Verbleibende Städte", _f_body, 22, UITheme.TEXT_DIM)
			_text(f, Vector2(x, y), "%d / %d" % [p.alive_cities(), p.cities.size()], _f_mono, 26, UITheme.TEXT, HORIZONTAL_ALIGNMENT_RIGHT, w)
			y += 18
			var pip := minf(24.0, (w - 4) / maxf(p.cities.size(), 1))
			for i in p.cities.size():
				var pr := Rect2(Vector2(x + i * pip, y), Vector2(pip - 5, 14))
				if p.cities[i]:
					f.draw_rect(pr, Color(UITheme.CYAN, 0.85))
				else:
					f.draw_rect(pr, Color(UITheme.RED, 0.5), false, 1.5)
			y += 52
			_text(f, Vector2(x, y), "Status", _f_body, 22, UITheme.TEXT_DIM)
			y += 32
			if p.landed_squadron != -1:
				var sq := GameState.squadron_by_id(p.landed_squadron)
				_text(f, Vector2(x, y), "WIRD ANGEGRIFFEN!", _f_disp, 24, UITheme.RED if fmod(_t, 0.6) < 0.4 else Color(1, 0.7, 0.4))
				y += 30
				if sq:
					_text(f, Vector2(x, y), "%d Zerstörer bombardieren Städte" % sq.destroyers.size(), _f_body, 22, UITheme.TEXT)
					y += 28
					if sq.fighters > 0:
						_text(f, Vector2(x, y), "%d Fighter als Begleitschutz" % sq.fighters, _f_body, 22, UITheme.TEXT)
						y += 28
			else:
				var inc: SquadronData = null
				for sq2 in GameState.squadrons:
					if sq2.state == SquadronData.State.TRANSIT and sq2.target_kind == SquadronData.TargetKind.PLANET and sq2.target_id == p.id:
						inc = sq2
				if inc:
					_text(f, Vector2(x, y), "Kein Angriff – Schwadron im Anflug", _f_bold, 22, UITheme.AMBER)
					y += 28
					_text(f, Vector2(x, y), "Ankunft in ca. %s" % GameState.format_time(GameState.squadron_eta(inc)), _f_body, 22, UITheme.TEXT)
					y += 28
				else:
					_text(f, Vector2(x, y), "Kein Feind greift an", _f_bold, 22, UITheme.GREEN)
					y += 28
			if _is_current(GameState.Loc.PLANET, p.id):
				cost_line = "AKTUELLE POSITION"
		GameState.Loc.STATION:
			var s: StationData = GameState.stations[sel_id]
			_text(f, Vector2(x, y), s.name.to_upper(), _f_title, 30, Color(1, 1, 1))
			y += 32
			_text(f, Vector2(x, y), "RAUMSTATION · Reparatur & Energie", _f_bold, 22, Color(0.55, 1.0, 0.8, 0.9))
			y += 46
			if s.attacker != -1:
				var sq3 := GameState.squadron_by_id(s.attacker)
				_text(f, Vector2(x, y), "WIRD ANGEGRIFFEN!", _f_disp, 24, UITheme.RED if fmod(_t, 0.6) < 0.4 else Color(1, 0.7, 0.4))
				y += 32
				_text(f, Vector2(x, y), "Integrität: %d %%" % int(s.integrity), _f_body, 22, UITheme.TEXT)
				y += 28
				if sq3:
					_text(f, Vector2(x, y), "%d Fighter greifen an" % sq3.fighters, _f_body, 22, UITheme.TEXT)
					y += 28
				_text(f, Vector2(x, y), "Erst die Fighter vernichten, dann andocken.", _f_body, 20, UITheme.TEXT_DIM)
				y += 28
			else:
				_text(f, Vector2(x, y), "Betriebsbereit", _f_bold, 22, UITheme.GREEN)
				y += 30
				_text(f, Vector2(x, y), "Andocken: Energie auf 100 %%", _f_body, 22, UITheme.TEXT)
				y += 28
				_text(f, Vector2(x, y), "(%d %% pro Sekunde)" % int(Config.refuel_rate), _f_body, 20, UITheme.TEXT_DIM)
				y += 28
			if _is_current(GameState.Loc.STATION, s.id):
				cost_line = "AKTUELLE POSITION"
		GameState.Loc.SQUADRON:
			var sq4 := GameState.squadron_by_id(sel_id)
			if sq4:
				_text(f, Vector2(x, y), sq4.name.to_upper(), _f_title, 28, Color(1.0, 0.6, 0.55))
				y += 32
				_text(f, Vector2(x, y), "FEINDLICHES SCHWADRON", _f_bold, 22, Color(UITheme.RED, 0.9))
				y += 46
				_text(f, Vector2(x, y), "Fighter", _f_body, 22, UITheme.TEXT_DIM)
				_text(f, Vector2(x, y), str(sq4.fighters), _f_mono, 24, UITheme.FIGHTER_COLOR, HORIZONTAL_ALIGNMENT_RIGHT, w)
				y += 32
				_text(f, Vector2(x, y), "Zerstörer", _f_body, 22, UITheme.TEXT_DIM)
				var dx := x + w - 24.0
				for i in range(sq4.destroyers.size() - 1, -1, -1):
					f.draw_rect(Rect2(Vector2(dx, y - 17), Vector2(18, 18)), UITheme.DESTROYER_COLORS[sq4.destroyers[i].color])
					dx -= 26.0
				if sq4.destroyers.is_empty():
					_text(f, Vector2(x, y), "0", _f_mono, 24, UITheme.TEXT, HORIZONTAL_ALIGNMENT_RIGHT, w)
				y += 32
				_text(f, Vector2(x, y), "Flaggschiff", _f_body, 22, UITheme.TEXT_DIM)
				_text(f, Vector2(x, y), "JA" if sq4.has_flagship else "nein", _f_mono, 24, UITheme.PINK if sq4.has_flagship else UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT, w)
				y += 44
				match sq4.state:
					SquadronData.State.WAITING:
						_text(f, Vector2(x, y), "Wartet am Sprungpunkt nach %s" % GameState.STAR_NAME, _f_bold, 22, UITheme.AMBER)
						y += 28
						_text(f, Vector2(x, y), "(springt, sobald dort weniger als %d Schwadrone sind)" % Config.max_squadrons, _f_body, 19, UITheme.TEXT_DIM)
						y += 26
					SquadronData.State.TRANSIT when sq4.system == 1:
						_text(f, Vector2(x, y), "Gestartet von %s" % sq4.origin, _f_body, 22, UITheme.TEXT)
						y += 28
						_text(f, Vector2(x, y), "Ziel: Sprungpunkt nach %s" % GameState.STAR_NAME, _f_bold, 22, UITheme.AMBER)
						y += 28
						_text(f, Vector2(x, y), "Sprung in ca. %s" % GameState.format_time(GameState.squadron_eta(sq4)), _f_body, 22, UITheme.TEXT)
						y += 28
					SquadronData.State.TRANSIT:
						_text(f, Vector2(x, y), "Ziel: " + GameState.squadron_target_name(sq4), _f_bold, 22, UITheme.AMBER)
						y += 28
						if GameState.is_squadron_stopped(sq4):
							_text(f, Vector2(x, y), "steht derzeit still", _f_body, 22, UITheme.TEXT)
						else:
							_text(f, Vector2(x, y), "Ankunft in ca. %s" % GameState.format_time(GameState.squadron_eta(sq4)), _f_body, 22, UITheme.TEXT)
						y += 28
					SquadronData.State.LANDED:
						_text(f, Vector2(x, y), "Gelandet auf " + GameState.squadron_target_name(sq4), _f_bold, 22, UITheme.RED)
						y += 28
					SquadronData.State.AT_STATION:
						_text(f, Vector2(x, y), "Greift " + GameState.squadron_target_name(sq4) + " an", _f_bold, 22, UITheme.RED)
						y += 28
				_text(f, Vector2(x, y), "Kleinere Schwadrone fliegen langsamer.", _f_body, 19, UITheme.TEXT_DIM)
				y += 26
				if _is_current(GameState.Loc.SQUADRON, sq4.id):
					cost_line = "AKTUELLE POSITION"
		GameState.Loc.ENEMY_SYSTEM:
			_text(f, Vector2(x, y), "FEINDSYSTEM", _f_title, 30, Color(0.85, 0.6, 1.0))
			y += 32
			_text(f, Vector2(x, y), "%s · Sprungpunkt (Galaxie)" % GameState.ENEMY_STAR_NAME.to_upper(), _f_bold, 22, Color(0.85, 0.6, 1.0, 0.9))
			y += 46
			if not Config.enemy_system_enabled:
				_text(f, Vector2(x, y), "Von hier kommen neue Schwadrone.", _f_body, 22, UITheme.TEXT)
				y += 30
				_text(f, Vector2(x, y), "Nächstes in ca. %s" % GameState.format_time(maxf(GameState.spawn_timer, 0.0)) if GameState.squadrons.size() < Config.max_squadrons else "Maximale Anzahl erreicht", _f_body, 22, UITheme.TEXT_DIM)
				y += 40
				_text(f, Vector2(x, y), "SPRUNG ABGESCHALTET", _f_disp, 24, UITheme.AMBER)
				can_jump = false
			else:
				y = _draw_enemy_summary(f, x, y, w)
				_text(f, Vector2(x, y), "Ankunft: Empfangskomitee (%d Fighter)" % Config.reception_fighter_count, _f_body, 20, UITheme.RED)
				y += 26
				_text(f, Vector2(x, y), "Sprung dauert %d× so lange · Rückweg ebenfalls %d %%" % [int(Config.enemy_jump_duration_factor), int(Config.enemy_jump_cost)], _f_body, 19, UITheme.TEXT_DIM)
				y += 26
				_text(f, Vector2(x, y), "Q/Tab: Feindsystem ansehen", _f_body, 19, UITheme.TEXT_DIM)
				y += 26
		GameState.Loc.HOME_SYSTEM:
			_text(f, Vector2(x, y), "RÜCKSPRUNG", _f_title, 30, Color(1.0, 0.86, 0.55))
			y += 32
			_text(f, Vector2(x, y), "ins %s-System (Sprungpunkt)" % GameState.STAR_NAME, _f_bold, 22, Color(1.0, 0.86, 0.55, 0.9))
			y += 46
			_text(f, Vector2(x, y), "Städte in %s" % GameState.STAR_NAME, _f_body, 22, UITheme.TEXT_DIM)
			_text(f, Vector2(x, y), "%d / %d" % [GameState.total_alive_cities(), GameState.total_cities()], _f_mono, 24, UITheme.TEXT, HORIZONTAL_ALIGNMENT_RIGHT, w)
			y += 32
			_text(f, Vector2(x, y), "Schwadrone dort", _f_body, 22, UITheme.TEXT_DIM)
			_text(f, Vector2(x, y), "%d / %d" % [GameState.squadrons.size(), Config.max_squadrons], _f_mono, 24, UITheme.RED if GameState.squadrons.size() > 0 else UITheme.TEXT, HORIZONTAL_ALIGNMENT_RIGHT, w)
			y += 32
			var attacked := 0
			for hp in GameState.planets:
				if hp.landed_squadron != -1:
					attacked += 1
			if attacked > 0:
				_text(f, Vector2(x, y), "%d Planet(en) werden angegriffen!" % attacked, _f_bold, 22, UITheme.RED if fmod(_t, 0.6) < 0.4 else Color(1, 0.7, 0.4))
				y += 30
			_text(f, Vector2(x, y), "Energie und Bomben gibt es nur an den Stationen.", _f_body, 19, UITheme.TEXT_DIM)
			y += 26
			if GameState.reception_active:
				_text(f, Vector2(x, y), "Einziger möglicher Sprung (Empfangskomitee)", _f_body, 19, UITheme.AMBER)
				y += 26
		GameState.Loc.ENEMY_PLANET:
			var ep: PlanetData = GameState.enemy_planets[sel_id]
			_text(f, Vector2(x, y), ep.name.to_upper(), _f_title, 34, Color(1.0, 0.62, 0.72))
			y += 32
			var hl := "FEINDLICHE HEIMATWELT" + ("" if Config.victory_all_enemy_cities else " · SIEGZIEL")
			_text(f, Vector2(x, y), (hl if ep.is_home else "FEINDPLANET · " + _type_name(ep.type)), _f_bold, 22, Color(1.0, 0.45, 0.62, 0.95))
			y += 46
			_text(f, Vector2(x, y), "Städte", _f_body, 22, UITheme.TEXT_DIM)
			_text(f, Vector2(x, y), "%d / %d" % [ep.alive_cities(), ep.cities.size()], _f_mono, 26, UITheme.TEXT, HORIZONTAL_ALIGNMENT_RIGHT, w)
			y += 18
			var epip := minf(24.0, (w - 4) / maxf(ep.cities.size(), 1))
			for i in ep.cities.size():
				var pr2 := Rect2(Vector2(x + i * epip, y), Vector2(epip - 5, 14))
				if ep.cities[i]:
					f.draw_rect(pr2, Color(1.0, 0.35, 0.58, 0.9))
				else:
					f.draw_rect(pr2, Color(0.6, 0.6, 0.65, 0.5), false, 1.5)
			y += 46
			_text(f, Vector2(x, y), "Verteidiger", _f_body, 22, UITheme.TEXT_DIM)
			_text(f, Vector2(x, y), ("%d Fighter" % ep.defenders) if ep.defenders > 0 else "ausgeschaltet", _f_mono, 24, UITheme.FIGHTER_COLOR if ep.defenders > 0 else UITheme.GREEN, HORIZONTAL_ALIGNMENT_RIGHT, w)
			y += 32
			_text(f, Vector2(x, y), "Bomben an Bord", _f_body, 22, UITheme.TEXT_DIM)
			_text(f, Vector2(x, y), "%d / %d" % [GameState.bombs, Config.bombs_max], _f_mono, 24, UITheme.AMBER if GameState.bombs > 0 else UITheme.RED, HORIZONTAL_ALIGNMENT_RIGHT, w)
			y += 40
			if ep.is_home:
				if not Config.victory_all_enemy_cities:
					_text(f, Vector2(x, y), "Alle Städte zerstört = SIEG", _f_bold, 22, UITheme.GREEN)
					y += 28
				_text(f, Vector2(x, y), "Die Heimatwelt baut keine Schwadrone.", _f_body, 20, UITheme.TEXT_DIM)
				y += 26
			elif ep.alive_cities() > 0:
				_text(f, Vector2(x, y), "Baut Schwadrone für den Angriff auf %s." % GameState.STAR_NAME, _f_body, 20, UITheme.TEXT)
				y += 26
				_text(f, Vector2(x, y), "Jede zerstörte Stadt verlangsamt die Produktion.", _f_body, 19, UITheme.TEXT_DIM)
				y += 26
			else:
				_text(f, Vector2(x, y), "Ausgeschaltet – baut keine Schwadrone mehr.", _f_bold, 21, UITheme.GREEN)
				y += 28
			_text(f, Vector2(x, y), "Pro Stadt 1 Bombentreffer · %d Punkte" % Config.enemy_city_points, _f_body, 19, UITheme.TEXT_DIM)
			y += 26
			_text(f, Vector2(x, y), _victory_line(), _f_bold, 20, UITheme.GREEN)
			y += 26
			if _is_current(GameState.Loc.ENEMY_PLANET, ep.id):
				cost_line = "AKTUELLE POSITION"
	# Fußzeile: Sprungkosten
	var fy := o.y + h - 150
	f.draw_line(Vector2(x, fy), Vector2(x + w, fy), Color(UITheme.CYAN, 0.3), 1.0)
	if is_foreign_view():
		_text(f, Vector2(x, fy + 40), "NUR ANSICHT", _f_disp, 22, UITheme.AMBER)
		_text(f, Vector2(x, fy + 76), "Q/Tab: zurück zum eigenen Standort", _f_body, 22, UITheme.TEXT_DIM)
	elif GameState.reception_active and sel_kind != GameState.Loc.HOME_SYSTEM:
		_text(f, Vector2(x, fy + 40), "EMPFANGSKOMITEE ABWEHREN", _f_disp, 19, UITheme.RED)
		_text(f, Vector2(x, fy + 76), "Möglich ist nur der Rücksprung nach %s." % GameState.STAR_NAME, _f_body, 21, UITheme.TEXT_DIM)
	elif cost_line != "":
		_text(f, Vector2(x, fy + 40), cost_line, _f_disp, 22, UITheme.GREEN)
		_text(f, Vector2(x, fy + 76), "FEUER / LEERTASTE: zurück", _f_body, 22, UITheme.TEXT_DIM)
	elif can_jump and sel_kind >= 0:
		var cost := GameState.effective_jump_cost_to(sel_kind, _sel_map_pos())
		var after := GameState.energy - cost
		_text(f, Vector2(x, fy + 40), "LANGSPRUNG" if GameState.is_cross_system(sel_kind) else "SPRUNGKOSTEN", _f_disp, 18, Color(UITheme.CYAN, 0.8))
		_text(f, Vector2(x, fy + 40), "−%d %%" % int(round(cost)), _f_mono, 28, UITheme.AMBER, HORIZONTAL_ALIGNMENT_RIGHT, w)
		_text(f, Vector2(x, fy + 76), "Energie danach", _f_body, 22, UITheme.TEXT_DIM)
		_text(f, Vector2(x, fy + 76), "%d %%" % int(round(after)), _f_mono, 24, UITheme.RED if after < Config.energy_low_warning else UITheme.TEXT, HORIZONTAL_ALIGNMENT_RIGHT, w)
		_text(f, Vector2(x, fy + 116), "FEUER / ENTER / KLICK: SPRINGEN", _f_disp, 17, UITheme.CYAN if fmod(_t, 1.2) < 0.9 else Color(1, 1, 1))
	else:
		_text(f, Vector2(x, fy + 40), "SPRUNG NICHT MÖGLICH", _f_disp, 20, UITheme.TEXT_DIM)
	_text(f, Vector2(x, o.y + h - 12), "Pfeile: Ziel · E: nächstes · Q/Tab: System · LEERTASTE: zurück", _f_body, 16, Color(UITheme.TEXT_DIM, 0.8))


## Siegbedingung mit Restzahl.
func _victory_line() -> String:
	var left := GameState.victory_cities_left()
	if Config.victory_all_enemy_cities:
		return "Sieg: alle Feindstädte zerstören (noch %d)" % left
	return "Sieg: Heimatwelt zerstören (noch %d Städte)" % left


## Lage im Feindsystem (Städte, Produktion, nächster Start) – für das Infofenster.
func _draw_enemy_summary(f: Control, x: float, y: float, w: float) -> float:
	_text(f, Vector2(x, y), "Feindstädte", _f_body, 22, UITheme.TEXT_DIM)
	_text(f, Vector2(x, y), "%d / %d" % [GameState.enemy_cities_alive(), GameState.enemy_cities_total()], _f_mono, 24, UITheme.TEXT, HORIZONTAL_ALIGNMENT_RIGHT, w)
	y += 32
	var home := GameState.enemy_home()
	if home:
		_text(f, Vector2(x, y), "davon Heimatwelt %s" % home.name, _f_body, 22, UITheme.TEXT_DIM)
		_text(f, Vector2(x, y), "%d / %d" % [home.alive_cities(), home.cities.size()], _f_mono, 24, Color(1.0, 0.45, 0.62), HORIZONTAL_ALIGNMENT_RIGHT, w)
		y += 32
	var rate := GameState.enemy_production_rate()
	_text(f, Vector2(x, y), "Schwadron-Produktion", _f_body, 22, UITheme.TEXT_DIM)
	_text(f, Vector2(x, y), ("%d %%" % int(round(rate * 100.0))) if rate > 0.0 else "GESTOPPT", _f_mono, 24, UITheme.AMBER if rate > 0.0 else UITheme.GREEN, HORIZONTAL_ALIGNMENT_RIGHT, w)
	y += 32
	var eta := GameState.next_launch_eta()
	var nl := "nächster Start in ca. %s" % GameState.format_time(eta) if eta >= 0.0 else ("keine Starts mehr" if rate <= 0.0 else "Höchstzahl unterwegs")
	_text(f, Vector2(x, y), "%d unterwegs · %s" % [GameState.enemy_squadrons.size(), nl], _f_body, 20, UITheme.TEXT)
	y += 30
	_text(f, Vector2(x, y), _victory_line(), _f_bold, 20, UITheme.GREEN)
	y += 34
	return y


func _draw_events(vp: Vector2) -> void:
	var f := _front
	var n := mini(6, GameState.events.size())
	var y := vp.y - 30.0 - n * 26.0
	for i in n:
		var ev: Dictionary = GameState.events[GameState.events.size() - n + i]
		var age := GameState.sim_time - float(ev.t)
		var a := clampf(1.0 - age / 90.0, 0.35, 1.0)
		_text(f, Vector2(36, y), GameState.format_time(ev.t), _f_mono, 18, Color(UITheme.TEXT_DIM, a))
		_text(f, Vector2(110, y), ev.text, _f_body, 21, Color(UITheme.sev_color(ev.sev).lightened(0.2), a))
		y += 26.0


func _type_name(t: String) -> String:
	return {"terran": "Gemäßigte Welt", "desert": "Wüstenwelt", "ice": "Eiswelt", "jungle": "Dschungelwelt",
		"volcanic": "Vulkanwelt", "ocean": "Ozeanwelt", "toxic": "Giftwelt", "barren": "Felswelt",
		"alien_home": "Heimatwelt", "alien_crimson": "Rote Wüstenwelt", "alien_spore": "Sporenwelt",
		"alien_ash": "Aschewelt", "alien_crystal": "Kristallwelt"}.get(t, t)


func _text(c: Control, pos: Vector2, s: String, f: Font, fs: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	c.draw_string(f, pos + Vector2(0, 2), s, align, width, fs, Color(0, 0, 0, col.a * 0.7))
	c.draw_string(f, pos, s, align, width, fs, col)


func _dashed_line(c: Control, a: Vector2, b: Vector2, col: Color, dash := 8.0, gap := 6.0, offset := 0.0) -> void:
	var d := b - a
	var l := d.length()
	if l < 1.0:
		return
	var dir := d / l
	var s := fmod(offset, dash + gap)
	if s < 0.0:
		s += dash + gap
	var p := -s
	while p < l:
		var p0 := maxf(p, 0.0)
		var p1 := minf(p + dash, l)
		if p1 > p0:
			c.draw_line(a + dir * p0, a + dir * p1, col, 2.0, true)
		p += dash + gap


func _dashed_circle(c: Control, center: Vector2, r: float, col: Color) -> void:
	var n := 90
	for i in n:
		if i % 2 == 0:
			c.draw_arc(center, r, TAU * i / n, TAU * (i + 1) / n, 3, col, 1.0, true)
