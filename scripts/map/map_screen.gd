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
##  [0.14.0] Zweites Feindsystem (Hart/Experte, sobald es angreift): Stern Ixmora, 4 Planeten, Sprungpunkt in Helion
##  unten rechts, dort oben links; nur über Helion erreichbar.
##  Q/Tab: die anderen Systeme ansehen (nur Beobachtung).
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
var _galaxy2: ColorRect           ## [0.14.0] Sprungpunkt zum zweiten Feindsystem (Helion, unten rechts)
var _gate_sun: ColorRect          ## Feindsystem: Rücksprungpunkt (unser Stern als Symbol)
var view_system := 0              ## 0 = Helion, 1 = Vorrhal, 2 = zweites Feindsystem (angezeigt)
var _launch_fx: Array = []        ## [{pos: Vector2 (Karte), t}] Startanimation neuer Schwadrone
var _back: Control
var _front: Control
var _bg: TextureRect
var _message := ""
var _message_t := 10.0
var _star_beep := 0.0           ## Warnton am Stern (die Kampfszene ist bei offener Karte eingefroren)
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
	_galaxy2 = ColorRect.new()
	var gm2 := ShaderMaterial.new()
	gm2.shader = gm.shader
	gm2.set_shader_parameter("active", 1.0)
	gm2.set_shader_parameter("arm_active", Vector3(0.48, 0.5, 1.0))
	gm2.set_shader_parameter("spin", -0.8)
	_galaxy2.material = gm2
	_galaxy2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_galaxy2)
	_gate_sun = ColorRect.new()
	var gsm := ShaderMaterial.new()
	gsm.shader = load("res://shaders/map_sun.gdshader")
	_gate_sun.material = gsm
	_gate_sun.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_gate_sun)
	for p in GameState.planets + GameState.enemy_planets + GameState.enemy2_planets:
		_make_planet_rect(p)
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
	GameState.second_system_awakened.connect(_on_second_awakened)


func _make_planet_rect(p: PlanetData) -> ColorRect:
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
	if _front:
		move_child(r, _front.get_index())   # unter die Beschriftungen
	_planet_rects[p] = r
	r.visible = p.system == view_system
	return r


func _on_enemy_launch(_sq: SquadronData, p: PlanetData) -> void:
	_launch_fx.append({"planet": p, "t": 0.0})


## [0.14.0] Das zweite Feindsystem greift an: Sprungpunkt erscheint (bei verlorener Funkmeldung ohne Hinweis).
func _on_second_awakened() -> void:
	_apply_view()
	if not GameState.last_event_lost():
		_flash_message("ZWEITES FEINDSYSTEM: %s GREIFT AN!" % GameState.ENEMY2_STAR_NAME.to_upper())


## Darstellung auf das angezeigte System umstellen (Stern, Sprungpunkt-Symbole, Hintergrund, Planeten).
func _apply_view() -> void:
	var enemy := view_system != 0
	var sm := _sun.material as ShaderMaterial
	var sun_cols := [[Color(1.0, 0.92, 0.7), Color(1.0, 0.6, 0.2)], [Color(1.0, 0.72, 0.58), Color(1.0, 0.22, 0.12)],
		[Color(0.84, 0.9, 1.0), Color(0.36, 0.46, 1.0)]]
	sm.set_shader_parameter("core_color", sun_cols[view_system][0])
	sm.set_shader_parameter("corona_color", sun_cols[view_system][1])
	_galaxy.visible = not enemy
	_galaxy2.visible = not enemy and GameState.second_active
	_gate_sun.visible = enemy
	for p in _planet_rects:
		(_planet_rects[p] as ColorRect).visible = (p as PlanetData).system == view_system
	if _bg:
		var et: Texture2D = null
		if view_system == 2:
			et = Assets.tex("map/map_background_enemy2.png")
		elif enemy:
			et = Assets.tex("map/map_background_enemy.png")
		_bg.texture = et if et else Assets.tex("map/map_background.png")
		_bg.modulate = Color(0.85, 0.9, 1.0, 1.0)
		if enemy and et == null:
			_bg.modulate = Color(0.72, 0.76, 1.0) if view_system == 2 else Color(1.0, 0.72, 0.78)
	_layout()


func _view_planets() -> Array:
	return GameState.system_planets(view_system)


func _view_squadrons() -> Array:
	return GameState.system_squadrons(view_system)


## Sprungpunkt im angezeigten System: im Feindsystem der Rücksprung nach Helion, in Helion der Sprungpunkt
## des Systems, aus dem der Spieler gerade schaut (sonst Vorrhal).
func _gate_pos() -> Vector2:
	if view_system != 0:
		return GameState.system_gate(view_system)
	return GameState.helion_gate(maxi(GameState.player_system, 1))


func _planet_kind() -> int:
	return GameState.Loc.ENEMY_PLANET if view_system != 0 else GameState.Loc.PLANET


## Akzentfarbe eines Feindsystems (Beschriftungen, Umlaufbahnen): Vorrhal rosa-rot, Ixmora blau-violett.
static func enemy_accent(sys: int) -> Color:
	return Color(0.66, 0.6, 1.0) if sys == 2 else Color(1.0, 0.45, 0.62)


func _planet_of(kind: int, id: int) -> PlanetData:
	if kind == GameState.Loc.ENEMY_PLANET:
		var eps := GameState.system_planets(view_system)
		if view_system != 0 and id >= 0 and id < eps.size():
			return eps[id]
		return null
	if kind == GameState.Loc.PLANET and id >= 0 and id < GameState.planets.size():
		return GameState.planets[id]
	return null


## Nur Ansicht: das angezeigte System ist nicht das, in dem sich der Spieler befindet.
func is_foreign_view() -> bool:
	return view_system != GameState.player_system


## Q/Tab: Helion → Vorrhal → (zweites Feindsystem, sobald es angreift) → Helion.
func toggle_view() -> void:
	if not Config.enemy_system_enabled:
		return
	view_system += 1
	if view_system > 2 or (view_system == 2 and not GameState.second_active):
		view_system = 0
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
	var sr := 110.0 * map_scale / 0.9 * _sun_factor()
	_sun.position = map_center - Vector2(sr, sr)
	_sun.size = Vector2(sr, sr) * 2.0
	var gs := 92.0 * map_scale / 0.9
	var gp := to_screen(GameState.JUMP_POINT)
	_galaxy.position = gp - Vector2(gs, gs)
	_galaxy.size = Vector2(gs, gs) * 2.0
	var gp2 := to_screen(GameState.JUMP_POINT_2)
	_galaxy2.position = gp2 - Vector2(gs, gs) * 0.9
	_galaxy2.size = Vector2(gs, gs) * 1.8
	var hs := 46.0 * map_scale / 0.9
	var hp := to_screen(GameState.system_gate(view_system) if view_system != 0 else GameState.ENEMY_GATE)
	_gate_sun.position = hp - Vector2(hs, hs)
	_gate_sun.size = Vector2(hs, hs) * 2.0


## Größe des Sterns auf der Karte: Vorrhal (roter Zwerg) kleiner, Ixmora (blauer Riese) etwas größer.
func _sun_factor() -> float:
	return [1.0, 0.72, 1.12][clampi(view_system, 0, 2)]


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
	if view_system == 0:
		# Sprungpunkte zu den Feindsystemen (id = System)
		_targets.append({"kind": GameState.Loc.ENEMY_SYSTEM, "id": 1, "pos": to_screen(GameState.helion_gate(1))})
		if GameState.second_active:
			_targets.append({"kind": GameState.Loc.ENEMY_SYSTEM, "id": 2, "pos": to_screen(GameState.helion_gate(2))})
	else:
		_targets.append({"kind": GameState.Loc.HOME_SYSTEM, "id": -1, "pos": to_screen(GameState.system_gate(view_system))})
	if Config.star_refuel_enabled:
		# [Vorgabe] Stern: Schnelltanken (id = System)
		_targets.append({"kind": GameState.Loc.STAR, "id": view_system, "pos": to_screen(GameState.STAR_POS)})


func _squadron_screen(sq: SquadronData) -> Vector2:
	var p := to_screen(sq.map_pos)
	if sq.state == SquadronData.State.WAITING:
		# wartende Schwadrone neben dem Sprungpunkt gestapelt, zur Kartenmitte hin (Beschriftung rechts daneben)
		var widx := 0
		for o in GameState.system_squadrons(sq.system):
			if o == sq:
				break
			if o.state == SquadronData.State.WAITING:
				widx += 1
		var dir := -1.0 if GameState.system_gate(sq.system).y > 0.0 else 1.0
		p += Vector2(-24, (74 + 40 * widx) * dir) * map_scale / 0.9
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
	if GameState.reception_active and not is_foreign_view() and view_system != 0:
		_select(GameState.Loc.HOME_SYSTEM, -1, false)   # während des Empfangskomitees nur Rücksprung
		return
	match GameState.player_loc:
		GameState.Loc.PLANET, GameState.Loc.STATION, GameState.Loc.SQUADRON, GameState.Loc.ENEMY_PLANET, GameState.Loc.STAR:
			if _target_valid(GameState.player_loc, GameState.player_loc_id):
				_select(GameState.player_loc, GameState.player_loc_id, false)
				return
	# sonst: nächstgelegenes bedrohtes Ziel bzw. nächstes Ziel
	var best: Dictionary = {}
	var bd := INF
	var me := to_screen(GameState.player_map_pos if not is_foreign_view() else _gate_pos())
	for t in _targets:
		if t.kind == GameState.Loc.ENEMY_SYSTEM or t.kind == GameState.Loc.HOME_SYSTEM or t.kind == GameState.Loc.STAR:
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
			return GameState.system_planets(view_system)[sel_id].map_pos()
		GameState.Loc.HOME_SYSTEM:
			return GameState.system_gate(view_system)
		GameState.Loc.STATION:
			return GameState.stations[sel_id].map_pos()
		GameState.Loc.SQUADRON:
			var sq := GameState.squadron_by_id(sel_id)
			return sq.map_pos if sq else GameState.player_map_pos
		GameState.Loc.ENEMY_SYSTEM:
			return GameState.helion_gate(maxi(sel_id, 1))
		GameState.Loc.STAR:
			return GameState.STAR_POS
	return GameState.player_map_pos


func _confirm() -> void:
	if sel_kind < 0:
		return
	if is_foreign_view():
		Audio.ui("ui_error")
		_flash_message("Nur Ansicht – Q/Tab: weiter bis zum eigenen System")
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
## Stern: die Hitze steigt auch bei offener Karte (und beim Blick ins andere System) – dann warnt die Karte selbst,
## im selben Takt wie die Kampfszene (die ist bei offener Karte eingefroren).
func _update_star_warning(delta: float) -> void:
	if not is_visible_in_tree() or get_tree().paused or not GameState.is_at_star() or GameState.star_heat < Config.star_heat_warning:
		_star_beep = 0.0
		return
	_star_beep -= delta
	if _star_beep <= 0.0:
		_star_beep = lerpf(0.9, 0.35, clampf((GameState.star_heat - Config.star_heat_warning) / maxf(1.0 - Config.star_heat_warning, 0.01), 0.0, 1.0))
		Audio.sfx("warning_low_energy", -3.0, 1.2, 0.0, "UI")


func _process(delta: float) -> void:
	_t += delta
	_message_t += delta
	_update_star_warning(delta)
	_rebuild_targets()
	if not _target_valid(sel_kind, sel_id):
		_select_initial()
	for fx in _launch_fx:
		fx.t += delta
	_launch_fx = _launch_fx.filter(func(fx): return fx.t < 2.4)
	for p in _view_planets():
		var r: ColorRect = _planet_rects[p] if _planet_rects.has(p) else _make_planet_rect(p)   # Testhilfe: später angelegtes System
		var rad := _planet_radius(p)
		var sp := to_screen(p.map_pos())
		var half := rad / 0.72
		r.position = sp - Vector2(half, half)
		r.size = Vector2(half, half) * 2.0
		var m := r.material as ShaderMaterial
		m.set_shader_parameter("light_dir", (map_center - sp).normalized())
		m.set_shader_parameter("spin", p.id * 0.17 + _t * 0.01)
	(_galaxy.material as ShaderMaterial).set_shader_parameter("highlight", 1.0 if sel_kind == GameState.Loc.ENEMY_SYSTEM and sel_id != 2 else 0.0)
	(_galaxy2.material as ShaderMaterial).set_shader_parameter("highlight", 1.0 if sel_kind == GameState.Loc.ENEMY_SYSTEM and sel_id == 2 else 0.0)
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
			col = Color(enemy_accent(p.system), 0.3 if sel else 0.12)
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
	var enemy_view := view_system != 0
	# Stern
	var star_name := GameState.star_name(view_system)
	var star_cols := [Color(1.0, 0.85, 0.6, 0.7), Color(1.0, 0.6, 0.5, 0.75), Color(0.7, 0.78, 1.0, 0.8)]
	_text(f, map_center + Vector2(-60, 70 * map_scale / 0.9 * _sun_factor() + 10.0), star_name.to_upper(), _f_disp, 15, star_cols[view_system], HORIZONTAL_ALIGNMENT_CENTER, 120)
	if enemy_view:
		# Rücksprungpunkt (unser Stern als Symbol): Vorrhal unten rechts, zweites Feindsystem oben links
		var hp := to_screen(GameState.system_gate(view_system))
		f.draw_arc(hp, 52.0 * map_scale / 0.9, _t * 0.6, _t * 0.6 + TAU * 0.8, 48, Color(1.0, 0.85, 0.5, 0.45), 1.5, true)
		var waiting := 0
		for esq in _view_squadrons():
			if esq.state == SquadronData.State.WAITING:
				waiting += 1
		var gl := "Sprungpunkt ins %s-System" % GameState.STAR_NAME if waiting == 0 else "%d Schwadron(e) warten auf den Sprung" % waiting
		var gate_title := "%s · RÜCKSPRUNG" % GameState.STAR_NAME.to_upper()
		var gate_col := Color(UITheme.TEXT_DIM, 0.85) if waiting == 0 else Color(UITheme.RED, 0.9)
		if hp.x > map_center.x:
			# Beschriftung links unterhalb (rechts liegt das Infofenster)
			_text(f, hp + Vector2(-380, 60 * map_scale / 0.9 + 6), gate_title, _f_disp, 15, Color(1.0, 0.86, 0.55, 0.9), HORIZONTAL_ALIGNMENT_RIGHT, 420)
			_text(f, hp + Vector2(-380, 60 * map_scale / 0.9 + 28), gl, _f_body, 17, gate_col, HORIZONTAL_ALIGNMENT_RIGHT, 420)
		else:
			# oben links: Beschriftung über dem Sprungpunkt – rechts daneben kreuzen die Anflugkurse der Schwadrone,
			# darunter stapeln sich die wartenden
			var ly := hp.y - 52.0 * map_scale / 0.9 - 30.0
			_text(f, Vector2(hp.x - 52.0 * map_scale / 0.9, ly), gate_title, _f_disp, 15, Color(1.0, 0.86, 0.55, 0.9))
			_text(f, Vector2(hp.x - 52.0 * map_scale / 0.9, ly + 22.0), gl, _f_body, 17, gate_col)
	else:
		# Feindsysteme (Galaxien): Vorrhal oben links, das zweite unten rechts (sobald es angreift)
		var gp := to_screen(GameState.JUMP_POINT)
		_text(f, gp + Vector2(-110, 70 * map_scale / 0.9), "FEINDSYSTEM", _f_disp, 16, Color(0.85, 0.6, 1.0, 0.85), HORIZONTAL_ALIGNMENT_CENTER, 220)
		var gsub := "abgeschaltet"
		if Config.enemy_system_enabled:
			gsub = "%s · Sprung %d %%" % [GameState.ENEMY_STAR_NAME, int(Config.enemy_jump_cost)]
		_text(f, gp + Vector2(-110, 70 * map_scale / 0.9 + 22), gsub, _f_body, 18, Color(UITheme.TEXT_DIM, 0.8), HORIZONTAL_ALIGNMENT_CENTER, 220)
		if GameState.second_active:
			var gp2 := to_screen(GameState.JUMP_POINT_2)
			var fresh := clampf(1.0 - (GameState.sim_time - GameState.second_awake_time) / 30.0, 0.0, 1.0)
			if fresh > 0.0:
				# frisch erwacht: ruhig pulsierender Ring (langsam, < 1 Hz)
				var k2 := fmod(_t * 0.7, 1.0)
				f.draw_arc(gp2, (58.0 + 30.0 * k2) * map_scale / 0.9, 0, TAU, 48, Color(enemy_accent(2), 0.6 * (1.0 - k2) * fresh), 2.0, true)
			# Beschriftung oberhalb (unterhalb liegt das Meldungsprotokoll), nicht unter das Infofenster
			var lx := minf(gp2.x, vp.x - PANEL_W - 24.0 - 140.0)
			var ly := gp2.y - 66.0 * map_scale / 0.9
			_text(f, Vector2(lx - 130, ly - 26), "2. FEINDSYSTEM", _f_disp, 16, Color(enemy_accent(2), 0.9), HORIZONTAL_ALIGNMENT_CENTER, 260)
			_text(f, Vector2(lx - 130, ly - 4), "%s · Sprung %d %%" % [GameState.ENEMY2_STAR_NAME, int(Config.enemy_jump_cost)], _f_body, 18, Color(UITheme.TEXT_DIM, 0.8), HORIZONTAL_ALIGNMENT_CENTER, 260)
	# Startanimation neuer Schwadrone (Feindsystem)
	if enemy_view:
		for fx in _launch_fx:
			if (fx.planet as PlanetData).system != view_system:
				continue
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
			var ecol := enemy_accent(p.system) if ealive > 0 else Color(0.55, 0.55, 0.6)
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
				f.draw_arc(sp, rad + 3.0, 0, TAU, 40, Color(0.5, 0.42, 1.0, 0.6) if p.system == 2 else Color(1.0, 0.3, 0.55, 0.6), 1.5, true)
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
			if s == GameState.station_rebuild_target():
				# [0.14.1] alle Stationen zerstört: diese wird wieder aufgebaut
				_text(f, dp + Vector2(-90, 26), "Wiederaufbau in %s" % GameState.format_time(ceilf(GameState.station_rebuild_left())), _f_body, 15, Color(UITheme.AMBER, 0.85), HORIZONTAL_ALIGNMENT_CENTER, 180)
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
		elif sel_kind == GameState.Loc.STAR:
			s2 += 60.0 * map_scale / 0.9 * _sun_factor()
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
	# Hinweiszeilen unter der Kopfleiste, untereinander: Ansicht des anderen Systems, Stern-Hitze (immer – auch beim
	# Blick ins andere System steigt sie weiter), Empfangskomitee, Systemschaden
	var by := TOP_H + 40.0
	if is_foreign_view():
		var vn := "%s-SYSTEM" % GameState.STAR_NAME.to_upper()
		if enemy_view:
			vn = "FEINDSYSTEM %s" % GameState.star_name(view_system).to_upper()
		var bl := "ANSICHT %s – NUR BEOBACHTUNG · Q/TAB: WEITER" % vn
		_text(f, Vector2(0, by), bl, _f_disp, 20, Color(UITheme.AMBER, 0.6 + 0.3 * sin(_t * 3.0)), HORIZONTAL_ALIGNMENT_CENTER, vp.x - PANEL_W)
		by += 30.0
	var empty_t := GameState.helion_empty_time()
	if empty_t > 0.0 and GameState.running:
		# [0.14.0] Experte: Helion (fast) frei von Schwadronen – nach Config.second_system_empty_time greift das zweite
		# Feindsystem an
		var left_t := maxf(Config.second_system_empty_time - empty_t, 0.0)
		var cnt := GameState.squadrons.size()
		var what := "HELION FREI" if cnt == 0 else ("NUR NOCH %d SCHWADRON IN HELION" % cnt if cnt == 1 else "NUR NOCH %d SCHWADRONE IN HELION" % cnt)
		_text(f, Vector2(0, by), "%s – IN %s GREIFT EIN ZWEITES FEINDSYSTEM AN" % [what, GameState.format_time(ceilf(left_t))], _f_disp, 19, Color(UITheme.AMBER, 0.85), HORIZONTAL_ALIGNMENT_CENTER, vp.x - PANEL_W)
		by += 30.0
	if GameState.is_at_star():
		var hp := int(round(GameState.star_heat * 100.0))
		var hot := GameState.star_heat >= Config.star_heat_warning
		var hl := ("HITZE %d %% – SOFORT SPRINGEN! (noch %.1f s)" if hot else "AM STERN · HITZE %d %% · noch %.1f s") % [hp, GameState.star_time_left()]
		_text(f, Vector2(0, by), hl, _f_disp, 22, Color(UITheme.RED if hot else UITheme.AMBER, 0.75 + 0.25 * sin(_t * 6.0)), HORIZONTAL_ALIGNMENT_CENTER, vp.x - PANEL_W)
		by += 30.0
	elif GameState.reception_active and not is_foreign_view():
		_text(f, Vector2(0, by), "EMPFANGSKOMITEE AKTIV – NUR RÜCKSPRUNG MÖGLICH", _f_disp, 20, Color(UITheme.RED, 0.6 + 0.3 * sin(_t * 4.0)), HORIZONTAL_ALIGNMENT_CENTER, vp.x - PANEL_W)
		by += 30.0
	if GameState.damage != "" and not is_foreign_view():
		# Systemschaden: Reparatur nur an einer Station
		var dl := "SCHADEN: %s – REPARATUR NUR AN EINER STATION" % GameState.damage_name()
		_text(f, Vector2(0, by), dl, _f_disp, 18, Color(UITheme.RED, 0.8), HORIZONTAL_ALIGNMENT_CENTER, vp.x - PANEL_W)


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
		# [0.14.2] besetzte Station: statt der Integrität „BESETZT“
		_text(f, sp + Vector2(r + 8, 16), "BESETZT" if s.occupied else "%d %%" % int(s.integrity), _f_mono, 16, Color(UITheme.RED, 0.9))


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
	var enemy_view := view_system != 0
	var accent := UITheme.CYAN
	var top_bg := Color(0.0, 0.02, 0.05, 0.75)
	if view_system == 1:
		accent = Color(1.0, 0.42, 0.5)
		top_bg = Color(0.05, 0.0, 0.02, 0.78)
	elif view_system == 2:
		accent = Color(0.62, 0.58, 1.0)
		top_bg = Color(0.02, 0.01, 0.06, 0.78)
	f.draw_rect(Rect2(Vector2.ZERO, Vector2(vp.x, TOP_H - 14)), top_bg)
	f.draw_line(Vector2(0, TOP_H - 14), Vector2(vp.x, TOP_H - 14), Color(accent, 0.5), 2.0)
	_text(f, Vector2(36, 52), "FEINDKARTE" if enemy_view else "SYSTEMKARTE", _f_title, 30, accent)
	_text(f, Vector2(370, 50), "%s-SYSTEM" % GameState.star_name(view_system).to_upper(), _f_disp, 18, Color(UITheme.TEXT_DIM, 0.9))
	var x := vp.x - 1290.0
	var e := GameState.energy
	var ecol := UITheme.GREEN if e >= 50.0 else (UITheme.AMBER if e >= Config.energy_low_warning else UITheme.RED)
	_text(f, Vector2(x, 34), "ENERGIE", _f_disp, 14, Color(UITheme.CYAN, 0.8))
	_text(f, Vector2(x, 68), "%d %%" % int(ceil(e)), _f_mono, 32, ecol)
	f.draw_rect(Rect2(Vector2(x + 110, 46), Vector2(160, 14)), Color(ecol, 0.15))
	f.draw_rect(Rect2(Vector2(x + 110, 46), Vector2(160 * e / Config.energy_max, 14)), ecol)
	var stats := [["PUNKTE", "%07d" % GameState.score], ["ZEIT", GameState.format_time(GameState.sim_time)]]
	if enemy_view:
		var rate := GameState.enemy_production_rate(view_system)
		stats.append(["FEINDSTÄDTE", "%d / %d" % [GameState.enemy_cities_alive(view_system), GameState.enemy_cities_total(view_system)]])
		stats.append(["PRODUKTION", "%d %%" % int(round(rate * 100.0)) if rate > 0.0 else "GESTOPPT"])
		stats.append(["UNTERWEGS", "%d / %d" % [_view_squadrons().size(), Config.enemy_system_max_squadrons]])
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
			if s.attacker != -1 and s.occupied:
				# [Vorgabe 0.14.2] besetzt, aber nicht zerstörbar: befreien durch Vernichten der Fighter
				var sq5 := GameState.squadron_by_id(s.attacker)
				_text(f, Vector2(x, y), "BESETZT!", _f_disp, 24, UITheme.RED if fmod(_t, 0.6) < 0.4 else Color(1, 0.7, 0.4))
				y += 32
				_text(f, Vector2(x, y), "Kein Tanken, keine Bomben, keine Reparatur", _f_body, 22, UITheme.TEXT)
				y += 28
				if sq5:
					_text(f, Vector2(x, y), ("%d Fighter hält die Station" if sq5.fighters == 1 else "%d Fighter halten die Station") % sq5.fighters, _f_body, 22, UITheme.TEXT)
					y += 28
				_text(f, Vector2(x, y), "Fighter vernichten, um sie zu befreien.", _f_body, 20, UITheme.TEXT_DIM)
				y += 28
			elif s.attacker != -1:
				var sq3 := GameState.squadron_by_id(s.attacker)
				_text(f, Vector2(x, y), "WIRD ANGEGRIFFEN!", _f_disp, 24, UITheme.RED if fmod(_t, 0.6) < 0.4 else Color(1, 0.7, 0.4))
				y += 32
				_text(f, Vector2(x, y), "Integrität: %d %%" % int(s.integrity), _f_body, 22, UITheme.TEXT)
				y += 28
				if sq3:
					_text(f, Vector2(x, y), ("%d Fighter greift an" if sq3.fighters == 1 else "%d Fighter greifen an") % sq3.fighters, _f_body, 22, UITheme.TEXT)
					y += 28
				if not Config.station_can_be_destroyed:
					_text(f, Vector2(x, y), "Bei 0 % ist sie besetzt.", _f_body, 20, UITheme.TEXT_DIM)
					y += 26
				_text(f, Vector2(x, y), "Erst die Fighter vernichten, dann andocken.", _f_body, 20, UITheme.TEXT_DIM)
				y += 28
			else:
				_text(f, Vector2(x, y), "Betriebsbereit", _f_bold, 22, UITheme.GREEN)
				y += 30
				_text(f, Vector2(x, y), "Andocken: Energie auf 100 %", _f_body, 22, UITheme.TEXT)
				y += 28
				_text(f, Vector2(x, y), "(%d %% pro Sekunde)" % int(Config.refuel_rate), _f_body, 20, UITheme.TEXT_DIM)
				y += 28
			if GameState.damage != "":
				_text(f, Vector2(x, y), "Repariert beim Andocken: %s" % GameState.damage_name().capitalize(), _f_body, 21, UITheme.AMBER)
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
					SquadronData.State.TRANSIT when sq4.system != 0:
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
						var st4: StationData = GameState.stations[sq4.target_id]
						if st4.occupied:
							_text(f, Vector2(x, y), "Hält %s besetzt" % st4.name, _f_bold, 22, UITheme.RED)
						else:
							_text(f, Vector2(x, y), "Greift %s an" % st4.name, _f_bold, 22, UITheme.RED)
						y += 28
				_text(f, Vector2(x, y), "Kleinere Schwadrone fliegen langsamer.", _f_body, 19, UITheme.TEXT_DIM)
				y += 26
				if _is_current(GameState.Loc.SQUADRON, sq4.id):
					cost_line = "AKTUELLE POSITION"
		GameState.Loc.ENEMY_SYSTEM:
			var esys := 2 if sel_id == 2 else 1
			var etc := enemy_accent(2) if esys == 2 else Color(0.85, 0.6, 1.0)
			_text(f, Vector2(x, y), "2. FEINDSYSTEM" if esys == 2 else "FEINDSYSTEM", _f_title, 30, etc)
			y += 32
			_text(f, Vector2(x, y), "%s · Sprungpunkt (Galaxie)" % GameState.star_name(esys).to_upper(), _f_bold, 22, Color(etc, 0.9))
			y += 46
			if not Config.enemy_system_enabled:
				_text(f, Vector2(x, y), "Von hier kommen neue Schwadrone.", _f_body, 22, UITheme.TEXT)
				y += 30
				_text(f, Vector2(x, y), "Nächstes in ca. %s" % GameState.format_time(maxf(GameState.spawn_timer, 0.0)) if GameState.squadrons.size() < Config.max_squadrons else "Maximale Anzahl erreicht", _f_body, 22, UITheme.TEXT_DIM)
				y += 40
				_text(f, Vector2(x, y), "SPRUNG ABGESCHALTET", _f_disp, 24, UITheme.AMBER)
				can_jump = false
			else:
				y = _draw_enemy_summary(f, x, y, w, esys)
				var rs := GameState.reception_size() if esys == 1 else 0
				if rs > 0:
					_text(f, Vector2(x, y), "Ankunft: Empfangskomitee (%d Fighter)" % rs, _f_body, 20, UITheme.RED)
				elif esys == 2:
					_text(f, Vector2(x, y), "Ankunft: kein Empfangskomitee", _f_body, 20, UITheme.GREEN)
				else:
					_text(f, Vector2(x, y), "Ankunft: Sprungpunkt frei (kein Empfangskomitee mehr)", _f_body, 20, UITheme.GREEN)
				y += 26
				_text(f, Vector2(x, y), "Sprung dauert %d× so lange · Rückweg ebenfalls %d %%" % [int(Config.enemy_jump_duration_factor), int(Config.enemy_jump_cost)], _f_body, 19, UITheme.TEXT_DIM)
				y += 26
				if GameState.second_active:
					_text(f, Vector2(x, y), "Zwischen den Feindsystemen nur über %s" % GameState.STAR_NAME, _f_body, 19, UITheme.TEXT_DIM)
					y += 26
				_text(f, Vector2(x, y), "Q/Tab: Feindsysteme ansehen" if GameState.second_active else "Q/Tab: Feindsystem ansehen", _f_body, 19, UITheme.TEXT_DIM)
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
			_text(f, Vector2(x, y), "Bomben und Reparatur nur an Stationen,", _f_body, 19, UITheme.TEXT_DIM)
			y += 24
			_text(f, Vector2(x, y), "Energie auch am Stern.", _f_body, 19, UITheme.TEXT_DIM)
			y += 26
			if GameState.reception_active:
				_text(f, Vector2(x, y), "Einziger möglicher Sprung (Empfangskomitee)", _f_body, 19, UITheme.AMBER)
				y += 26
		GameState.Loc.STAR:
			var sname := GameState.star_name(sel_id)
			var warm: Color = [Color(1.0, 0.86, 0.55), Color(1.0, 0.62, 0.45), Color(0.72, 0.8, 1.0)][clampi(sel_id, 0, 2)]
			_text(f, Vector2(x, y), "STERN " + sname.to_upper(), _f_title, 30, warm)
			y += 32
			_text(f, Vector2(x, y), "SCHNELLTANKEN · nur Energie", _f_bold, 22, Color(warm, 0.9))
			y += 46
			var full_s := (Config.energy_max - GameState.energy) / maxf(Config.star_refuel_rate, 0.1)
			_text(f, Vector2(x, y), "Energie voll in", _f_body, 22, UITheme.TEXT_DIM)
			_text(f, Vector2(x, y), "ca. %d s" % int(ceil(full_s)), _f_mono, 24, UITheme.GREEN, HORIZONTAL_ALIGNMENT_RIGHT, w)
			y += 32
			_text(f, Vector2(x, y), "Verglühen nach", _f_body, 22, UITheme.TEXT_DIM)
			_text(f, Vector2(x, y), "ca. %d s" % int(Config.star_heat_time), _f_mono, 24, UITheme.RED, HORIZONTAL_ALIGNMENT_RIGHT, w)
			y += 32
			_text(f, Vector2(x, y), "Reparatur · Bomben", _f_body, 22, UITheme.TEXT_DIM)
			_text(f, Vector2(x, y), "nein", _f_mono, 24, UITheme.TEXT, HORIZONTAL_ALIGNMENT_RIGHT, w)
			y += 40
			if _is_current(GameState.Loc.STAR, sel_id):
				var hot2 := GameState.star_heat >= Config.star_heat_warning
				_text(f, Vector2(x, y), "HITZE %d %% · noch %.1f s" % [int(round(GameState.star_heat * 100.0)), GameState.star_time_left()], _f_disp, 22, UITheme.RED if hot2 else UITheme.AMBER)
				y += 30
				cost_line = "AKTUELLE POSITION"
			_text(f, Vector2(x, y), "Rechtzeitig wegspringen: die Hitze steigt", _f_body, 19, UITheme.TEXT_DIM)
			y += 24
			_text(f, Vector2(x, y), "auch, während die Karte offen ist.", _f_body, 19, UITheme.TEXT_DIM)
			y += 26
		GameState.Loc.ENEMY_PLANET:
			var ep: PlanetData = GameState.system_planets(view_system)[sel_id]
			var eac := enemy_accent(ep.system)
			_text(f, Vector2(x, y), ep.name.to_upper(), _f_title, 34, eac.lerp(Color.WHITE, 0.3))
			y += 32
			var hl := "FEINDLICHE HEIMATWELT" + ("" if Config.victory_all_enemy_cities else " · SIEGZIEL")
			var both_homes := not GameState.enemy2_planets.is_empty()   # Hart/Experte: beide Heimatwelten zählen
			_text(f, Vector2(x, y), (hl if ep.is_home else "FEINDPLANET · " + _type_name(ep.type)), _f_bold, 22, Color(eac, 0.95))
			y += 46
			_text(f, Vector2(x, y), "Städte", _f_body, 22, UITheme.TEXT_DIM)
			_text(f, Vector2(x, y), "%d / %d" % [ep.alive_cities(), ep.cities.size()], _f_mono, 26, UITheme.TEXT, HORIZONTAL_ALIGNMENT_RIGHT, w)
			y += 18
			var epip := minf(24.0, (w - 4) / maxf(ep.cities.size(), 1))
			for i in ep.cities.size():
				var pr2 := Rect2(Vector2(x + i * epip, y), Vector2(epip - 5, 14))
				if ep.cities[i]:
					f.draw_rect(pr2, Color(eac, 0.9))
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
					_text(f, Vector2(x, y), "Beide Heimatwelten zerstört = SIEG" if both_homes else "Alle Städte zerstört = SIEG", _f_bold, 22, UITheme.GREEN)
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
		_text(f, Vector2(x, fy + 76), "Q/Tab: weiter bis zum eigenen System", _f_body, 22, UITheme.TEXT_DIM)
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


## Siegbedingung mit Restzahl (Hart/Experte: beide Feindsysteme – vor dem Angriff des zweiten nur ein Hinweis).
func _victory_line() -> String:
	var left := GameState.victory_cities_left()
	if not Config.victory_all_enemy_cities:
		return "Sieg: Heimatwelt%s zerstören (noch %d Städte)" % ["en" if not GameState.enemy2_planets.is_empty() else "", left]
	if GameState.enemy2_planets.is_empty():
		return "Sieg: alle Feindstädte zerstören (noch %d)" % left
	if not GameState.second_active:
		return "Sieg: alle Feindstädte, auch im 2. Feindsystem (hier noch %d)" % GameState.enemy_cities_alive(1)
	return "Sieg: alle Städte beider Feindsysteme (noch %d)" % left


## Lage in einem Feindsystem (Städte, Produktion, nächster Start) – für das Infofenster.
func _draw_enemy_summary(f: Control, x: float, y: float, w: float, sys := 1) -> float:
	_text(f, Vector2(x, y), "Feindstädte", _f_body, 22, UITheme.TEXT_DIM)
	_text(f, Vector2(x, y), "%d / %d" % [GameState.enemy_cities_alive(sys), GameState.enemy_cities_total(sys)], _f_mono, 24, UITheme.TEXT, HORIZONTAL_ALIGNMENT_RIGHT, w)
	y += 32
	var home := GameState.enemy_home(sys)
	if home:
		_text(f, Vector2(x, y), "davon Heimatwelt %s" % home.name, _f_body, 22, UITheme.TEXT_DIM)
		_text(f, Vector2(x, y), "%d / %d" % [home.alive_cities(), home.cities.size()], _f_mono, 24, enemy_accent(sys), HORIZONTAL_ALIGNMENT_RIGHT, w)
		y += 32
	var rate := GameState.enemy_production_rate(sys)
	_text(f, Vector2(x, y), "Schwadron-Produktion", _f_body, 22, UITheme.TEXT_DIM)
	_text(f, Vector2(x, y), ("%d %%" % int(round(rate * 100.0))) if rate > 0.0 else "GESTOPPT", _f_mono, 24, UITheme.AMBER if rate > 0.0 else UITheme.GREEN, HORIZONTAL_ALIGNMENT_RIGHT, w)
	y += 32
	var eta := GameState.next_launch_eta(sys)
	var nl := "nächster Start in ca. %s" % GameState.format_time(eta) if eta >= 0.0 else ("keine Starts mehr" if rate <= 0.0 else "Höchstzahl unterwegs")
	_text(f, Vector2(x, y), "%d unterwegs · %s" % [GameState.system_squadrons(sys).size(), nl], _f_body, 20, UITheme.TEXT)
	y += 30
	_text(f, Vector2(x, y), _victory_line(), _f_bold, 20, UITheme.GREEN)
	y += 34
	return y


## Protokoll der letzten Meldungen (bei gestörter Kommunikation wie im Kampf: verstümmelt, verlorene fehlen).
func _draw_events(vp: Vector2) -> void:
	var f := _front
	var shown := []
	for i in range(GameState.events.size() - 1, -1, -1):
		var ev: Dictionary = GameState.events[i]
		if GameState.event_shown(ev) != "":
			shown.push_front(ev)
			if shown.size() >= 6:
				break
	var n := shown.size()
	var y := vp.y - 30.0 - n * 26.0
	for ev in shown:
		var age := GameState.sim_time - float(ev.t)
		var a := clampf(1.0 - age / 90.0, 0.35, 1.0)
		_text(f, Vector2(36, y), GameState.format_time(ev.t), _f_mono, 18, Color(UITheme.TEXT_DIM, a))
		_text(f, Vector2(110, y), GameState.event_shown(ev), _f_body, 21, Color(UITheme.sev_color(ev.sev).lightened(0.2), a))
		y += 26.0


func _type_name(t: String) -> String:
	return {"terran": "Gemäßigte Welt", "desert": "Wüstenwelt", "ice": "Eiswelt", "jungle": "Dschungelwelt",
		"volcanic": "Vulkanwelt", "ocean": "Ozeanwelt", "toxic": "Giftwelt", "barren": "Felswelt",
		"alien_home": "Heimatwelt", "alien_crimson": "Rote Wüstenwelt", "alien_spore": "Sporenwelt",
		"alien_ash": "Aschewelt", "alien_crystal": "Kristallwelt", "alien_void": "Heimatwelt",
		"alien_glacier": "Gletscherwelt", "alien_magma": "Magmawelt", "alien_bloom": "Leuchtwelt"}.get(t, t)


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
