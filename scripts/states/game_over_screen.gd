class_name GameOverScreen
extends Control
## =============================================================================================
##  AUSWERTUNG am Spielende [Vorgabe] – bei Game Over, Sieg und vorzeitigem Abbruch:
##  zerstörte Fighter, abgeschossene Zerstörer, vernichtete Flaggschiffe, zerbombte Feindstädte,
##  verlorene eigene Städte und Spielzeit (jeweils mit den erzielten Punkten), danach Highscore.
##  Jede Partie wird zusätzlich nach user://auswertungen.csv geschrieben (siehe GameState).
##  Militär-Rang / Siegbonus: folgt nach den Tests (Config.bonus_victory).
## =============================================================================================

var _right: VBoxContainer
var _name_edit: LineEdit
var _entry_nodes: Array = []
var _rank := -1
var _kind := "gameover"
var _leaving := false   ## ein Knopf wurde gedrückt – weitere Klicks während des Abblendens ignorieren
## [0.14.4] Bildschirmtastatur für den Highscore-Namen (Gamepad, Steam Deck, Touch, Maus)
const OSK_ROWS := ["ABCDEFGHIJ", "KLMNOPQRST", "UVWXYZÄÖÜ-", "0123456789"]
var _osk_first: Button = null
var _name_fresh := true   ## vorbelegter Name noch unverändert: das erste Zeichen ersetzt ihn, Löschen leert ihn
static var _key_styles := {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.get_theme()
	_kind = GameState.end_kind if GameState.end_kind != "" else "gameover"
	Audio.stop_all_loops(0.3)
	match _kind:
		"victory":
			Audio.play_music("victory_theme" if Audio.has_music("victory_theme") else "title_theme", 1.5)
		"abort":
			Audio.play_music("debrief_theme" if Audio.has_music("debrief_theme") else "map_theme", 1.5)
		_:
			Audio.play_music("gameover_theme", 1.5)
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.005, 0.02)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var t := Assets.tex("map/map_background.png")
	if t:
		var tr := TextureRect.new()
		tr.texture = t
		tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.modulate = {"victory": Color(0.5, 0.62, 0.5), "abort": Color(0.45, 0.5, 0.58)}.get(_kind, Color(0.55, 0.4, 0.45))
		add_child(tr)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 70)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 36)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(root)

	var title := "SPIEL VORBEI"
	var tcol := UITheme.RED
	var reason := "Die Energie deines Schiffs ist erschöpft." if GameState.game_over_reason == "energy" else "Alle Städte des %s-Systems wurden zerstört." % GameState.STAR_NAME
	if GameState.game_over_reason == "star":
		reason = "Dein Schiff ist am Stern %s verglüht." % GameState.star_name()
	if _kind == "victory":
		title = "SIEG!"
		tcol = UITheme.GREEN
		if Config.victory_all_enemy_cities:
			reason = "Alle Städte %s sind zerstört – das %s-System ist gerettet." % [GameState.victory_systems_text(), GameState.STAR_NAME]
		else:
			reason = "%s gefallen – das %s-System ist gerettet." % [GameState.victory_homes_text(), GameState.STAR_NAME]
	elif _kind == "abort":
		title = "EINSATZ ABGEBROCHEN"
		tcol = UITheme.AMBER
		reason = "Auswertung deines Einsatzes"
	root.add_child(UITheme.title_label(title, 76, tcol))
	var rl := UITheme.label(reason, 28, UITheme.TEXT)
	rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(rl)
	var sc := UITheme.label("%07d" % GameState.score, 64, UITheme.AMBER, "mono")
	sc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(sc)

	var cols := HBoxContainer.new()
	cols.alignment = BoxContainer.ALIGNMENT_CENTER
	cols.add_theme_constant_override("separation", 40)
	root.add_child(cols)
	cols.add_child(_build_evaluation())
	_right = VBoxContainer.new()
	_right.add_theme_constant_override("separation", 12)
	_right.custom_minimum_size = Vector2(700, 0)
	cols.add_child(_right)

	if Highscores.qualifies(GameState.score, GameState.difficulty_key):
		var nl := UITheme.label("NEUER HIGHSCORE! Dein Name:", 28, UITheme.GREEN, "display")
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_right.add_child(nl)
		_name_edit = LineEdit.new()
		_name_edit.max_length = 12
		_name_edit.placeholder_text = "PILOT"
		_name_edit.text = _last_name()
		_name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
		_name_edit.custom_minimum_size = Vector2(420, 60)
		_name_edit.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_name_edit.text_submitted.connect(func(_s): _submit())
		_name_edit.gui_input.connect(_on_name_gui_input)
		_name_edit.focus_entered.connect(_on_name_focus)
		_name_edit.text_changed.connect(func(_s):
			Audio.ui("ui_type")
			_set_name_fresh(false))
		_right.add_child(_name_edit)
		# [0.14.4] eigene Bildschirmtastatur: Auf dem Steam Deck (und mit jedem Pad ohne Tastatur) ließ sich der
		# vorbelegte Name nicht ändern – die System-Tastatur erreicht das Spiel dort nicht zuverlässig.
		var osk := _build_osk()
		_right.add_child(osk)
		var pad_hint := UITheme.label("Gamepad: A tippt · B löscht · Start trägt ein\nTastatur: tippen, Enter trägt ein", 20, UITheme.TEXT_DIM)
		pad_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_right.add_child(pad_hint)
		_entry_nodes = [nl, _name_edit, osk, pad_hint]
		_set_name_fresh(true)
		await get_tree().process_frame
		if is_instance_valid(_name_edit):
			if Main.instance and Main.instance.last_input_pad and is_instance_valid(_osk_first):
				_osk_first.grab_focus()   # zuletzt mit dem Gamepad gespielt (Steam Deck): Bildschirmtastatur
			else:
				_name_edit.grab_focus()   # Tastatur: direkt tippen, der vorbelegte Name ist markiert
	else:
		_show_table()


## Auswertungstabelle: Anzahl und erzielte Punkte je Kategorie.
func _build_evaluation() -> Control:
	var st: Dictionary = GameState.stats
	var pts: Dictionary = st.get("points", {})
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(760, 0)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	panel.add_child(vb)
	vb.add_child(UITheme.title_label("AUSWERTUNG", 34, UITheme.CYAN))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 36)
	grid.add_theme_constant_override("v_separation", 4)
	vb.add_child(grid)
	var total_cities := GameState.total_cities()
	var rows := [
		["Zerstörte Fighter", str(st.get("fighters", 0)), pts.get("fighters", 0)],
		["Abgeschossene Zerstörer", str(st.get("destroyers", 0)), pts.get("destroyers", 0)],
		["Vernichtete Flaggschiffe", str(st.get("flagships", 0)), pts.get("flagships", 0)],
		["Zerbombte Feindstädte", "%d / %d" % [st.get("enemy_cities", 0), GameState.enemy_cities_total()] if GameState.enemy_cities_total() > 0 and Config.enemy_system_enabled else str(st.get("enemy_cities", 0)), pts.get("enemy_cities", 0)],
		["Verlorene eigene Städte", "%d / %d" % [st.get("cities_lost", 0), total_cities] if total_cities > 0 else str(st.get("cities_lost", 0)), null],
		["Spielzeit", _fmt_time(GameState.play_time), null],
	]
	for r in rows:
		grid.add_child(UITheme.label(r[0], 26, UITheme.TEXT_DIM))
		var v := UITheme.label(r[1], 28, UITheme.TEXT, "mono")
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(v)
		var p := UITheme.label(("+%d" % int(r[2])) if r[2] != null else "", 24, UITheme.AMBER, "mono")
		p.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		p.custom_minimum_size = Vector2(140, 0)
		grid.add_child(p)
	var sep := HSeparator.new()
	vb.add_child(sep)
	var extra := GridContainer.new()
	extra.columns = 2
	extra.add_theme_constant_override("h_separation", 30)
	vb.add_child(extra)
	var bomb_line := "–"
	if int(st.get("bombs_dropped", 0)) > 0:
		bomb_line = "%d Treffer / %d abgeworfen" % [st.get("bombs_hit", 0), st.get("bombs_dropped", 0)]
	var extras := [
		["Boni (Schwadrone, Planeten, Stationen, Orbit)", "+%d" % int(pts.get("bonus", 0))],
		["Vernichtete Schwadrone (in den Feindsystemen)" if not GameState.enemy2_planets.is_empty() else "Vernichtete Schwadrone (im Feindsystem)", "%d (%d)" % [st.get("squadrons", 0), st.get("enemy_squadrons_intercepted", 0)]],
		["Gerettete Planeten · verteidigte Stationen", "%d · %d" % [st.get("planets_saved", 0), st.get("stations_defended", 0)]],
		["Bomben", bomb_line],
		["Sprünge (davon zwischen den Systemen)", "%d (%d)" % [st.get("jumps", 0), st.get("enemy_jumps", 0)]],
		["Sternbesuche · Systemschäden (repariert)", "%d · %d (%d)" % [st.get("star_visits", 0), st.get("damages", 0), st.get("repairs", 0)]],
		["Erreichte Stufe · Schwierigkeit", "%d · %s" % [GameState.level + 1, GameState.difficulty_name]],
	]
	if not GameState.enemy2_planets.is_empty():
		# [0.14.0] Hart/Experte: wann das zweite Feindsystem angriff und wie viel davon zerbombt ist
		var s2 := "griff nicht an"
		if GameState.second_active:
			s2 = "ab %s · %d / %d Städte" % [GameState.format_time(GameState.second_awake_time), int(st.get("enemy2_cities", 0)), GameState.enemy_cities_total(2)]
		extras.insert(1, ["Zweites Feindsystem %s" % GameState.ENEMY2_STAR_NAME, s2])
	for e in extras:
		extra.add_child(UITheme.label(e[0], 21, UITheme.TEXT_DIM))
		var lv := UITheme.label(e[1], 21, UITheme.TEXT, "mono")
		lv.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		extra.add_child(lv)
	return panel


func _leave(again: bool) -> void:
	if _leaving:
		return
	_leaving = true
	if again:
		Main.instance.new_game()
	else:
		Main.instance.goto_title()


static func _fmt_time(t: float) -> String:
	var s := int(t)
	if s >= 3600:
		return "%d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]
	return "%02d:%02d" % [s / 60, s % 60]


func _last_name() -> String:
	var cf := ConfigFile.new()
	if cf.load("user://settings.cfg") == OK:
		return str(cf.get_value("player", "name", "PILOT"))
	return "PILOT"


## [0.14.3] Das Eingabefeld trägt nur bei Tasten-Enter ein. Gamepad A (ui_accept) soll den (vorbelegten)
## Namen ebenso eintragen – sonst hing man mit dem Pad in der Namenseingabe fest.
func _on_name_gui_input(event: InputEvent) -> void:
	if event is InputEventKey or _name_edit == null:
		return
	if event.is_action_pressed("ui_accept"):
		_name_edit.accept_event()
		_submit()


## [0.14.3] Godot schaltet ein Eingabefeld, das den Fokus per Steuerkreuz/Pfeilen bekommt, nicht in den
## Bearbeitungsmodus – getippte Zeichen (auch von der Steam-Deck-Bildschirmtastatur) gingen dann verloren,
## und Enter startete erst die Bearbeitung.
func _on_name_focus() -> void:
	if _name_edit == null:
		return
	if not _name_edit.is_editing():
		_name_edit.edit()
	_name_edit.caret_column = _name_edit.text.length()
	if _name_fresh:
		_name_edit.select_all()   # [0.14.4] vorbelegter Name markiert: Tippen ersetzt ihn


# ------------------------------------------------------------------ [0.14.4] Bildschirmtastatur
func _build_osk() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_osk_first = null
	for row in OSK_ROWS:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 6)
		hb.alignment = BoxContainer.ALIGNMENT_CENTER
		for i in String(row).length():
			var ch: String = String(row).substr(i, 1)
			var b := _osk_key(ch, _osk_type.bind(ch), Vector2(54, 50))
			hb.add_child(b)
			if _osk_first == null:
				_osk_first = b
		box.add_child(hb)
	var last := HBoxContainer.new()
	last.add_theme_constant_override("separation", 6)
	last.alignment = BoxContainer.ALIGNMENT_CENTER
	last.add_child(_osk_key("LEER", _osk_type.bind(" "), Vector2(150, 50)))
	last.add_child(_osk_key("LÖSCHEN", _osk_backspace, Vector2(170, 50)))
	last.add_child(_osk_key("EINTRAGEN", _submit, Vector2(240, 50)))
	box.add_child(last)
	return box


## Taste der Bildschirmtastatur: Knopf-Stil mit schmalen Innenrändern (UITheme.button ist für breite Menüknöpfe).
func _osk_key(text: String, cb: Callable, min_size: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = min_size
	b.add_theme_font_size_override("font_size", 24)
	if _key_styles.is_empty():
		var th := UITheme.get_theme()
		for st in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
			var sb := th.get_stylebox(st, "Button").duplicate() as StyleBox
			sb.content_margin_left = 4
			sb.content_margin_right = 4
			sb.content_margin_top = 4
			sb.content_margin_bottom = 4
			_key_styles[st] = sb
	for st in _key_styles:
		b.add_theme_stylebox_override(st, _key_styles[st])
	b.pressed.connect(cb)
	b.focus_entered.connect(func(): Audio.ui("ui_move", -8.0))
	b.mouse_entered.connect(func(): b.grab_focus())
	return b


func _set_name_fresh(on: bool) -> void:
	_name_fresh = on
	if _name_edit:
		# der vorbelegte Name erscheint gedämpft, solange das erste Zeichen ihn ersetzt
		_name_edit.add_theme_color_override("font_color", Color(UITheme.TEXT_DIM, 0.9) if on else Color(1, 1, 1))


func _osk_type(ch: String) -> void:
	if _name_edit == null or _leaving:
		return
	var t := "" if _name_fresh else _name_edit.text
	if t.length() >= _name_edit.max_length:
		Audio.ui("ui_error")
		return
	_name_edit.text = t + ch
	_name_edit.caret_column = _name_edit.text.length()
	_set_name_fresh(false)
	Audio.ui("ui_type")


func _osk_backspace() -> void:
	if _name_edit == null or _leaving:
		return
	_name_edit.text = "" if _name_fresh else _name_edit.text.left(maxi(_name_edit.text.length() - 1, 0))
	_name_edit.caret_column = _name_edit.text.length()
	_set_name_fresh(false)
	Audio.ui("ui_type")


## Physische Tastatur, während der Fokus auf der Bildschirmtastatur liegt: Zeichen, Rücktaste und Enter gehen in
## den Namen (sonst würden Enter/Leertaste die markierte Taste auslösen). Im Eingabefeld tippt Godot selbst.
func _input(event: InputEvent) -> void:
	if _name_edit == null or _leaving or not (event is InputEventKey) or not event.pressed:
		return
	if _name_edit.has_focus():
		return
	var k := event as InputEventKey
	if k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER:
		_submit()
	elif k.keycode == KEY_BACKSPACE:
		_osk_backspace()
	elif k.unicode >= 32 and not k.ctrl_pressed and not k.alt_pressed and not k.meta_pressed:
		_osk_type(String.chr(k.unicode))
	else:
		return
	get_viewport().set_input_as_handled()


## Gamepad in der Namenseingabe: B löscht ein Zeichen, Start trägt ein.
func _unhandled_input(event: InputEvent) -> void:
	if _name_edit == null or _leaving or not (event is InputEventJoypadButton):
		return
	if event.is_action_pressed("ui_cancel"):
		_osk_backspace()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pause"):
		_submit()
		get_viewport().set_input_as_handled()


func _submit() -> void:
	if _name_edit == null:
		return
	var n := _name_edit.text.strip_edges()
	if n == "":
		n = "PILOT"
	var cf := ConfigFile.new()
	cf.load("user://settings.cfg")
	cf.set_value("player", "name", n)
	cf.save("user://settings.cfg")
	_rank = Highscores.add(n, GameState.score, GameState.level, GameState.play_time, _kind == "victory", GameState.difficulty_key)
	Audio.ui("ui_select")
	for node in _entry_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_entry_nodes.clear()
	_name_edit = null
	_show_table()


func _show_table() -> void:
	_right.add_child(UITheme.title_label("HIGHSCORES · %s" % GameState.difficulty_name.to_upper(), 34, UITheme.AMBER))
	var hl := HighscoreView.build_table(_rank, true, GameState.difficulty_key)
	hl.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_right.add_child(hl)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 24)
	var again := UITheme.button("NOCHMAL SPIELEN", func(): _leave(true))
	hb.add_child(again)
	hb.add_child(UITheme.button("HAUPTMENÜ", func(): _leave(false)))
	_right.add_child(hb)
	await get_tree().process_frame
	if is_instance_valid(again):
		again.grab_focus()
