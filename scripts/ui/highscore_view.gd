class_name HighscoreView
extends Control
## Highscore-Tabellen (lokal gespeichert) – eine je Schwierigkeitsstufe, mit ◀ ▶ bzw. Links/Rechts umschalten.

signal closed

var highlight_rank := -1
var embedded := false
var level_idx := -1            ## angezeigte Stufe (-1 = aktuelle Stufe aus den Optionen)
var _table_box: VBoxContainer
var _level_label: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.get_theme()
	if not embedded:
		var dim := ColorRect.new()
		dim.color = Color(0, 0.01, 0.03, 0.8)
		dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(900, 0)
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)
	vb.add_child(UITheme.title_label("HIGHSCORES", 46, UITheme.AMBER))
	if level_idx < 0:
		level_idx = Settings.difficulty
	var sel := HBoxContainer.new()
	sel.alignment = BoxContainer.ALIGNMENT_CENTER
	sel.add_theme_constant_override("separation", 18)
	var prev := UITheme.button("◀", func(): _switch(-1))
	prev.focus_mode = Control.FOCUS_NONE   # Links/Rechts wechseln die Liste direkt (kein Fokussprung)
	sel.add_child(prev)
	_level_label = UITheme.label("", 28, UITheme.CYAN, "display")
	_level_label.custom_minimum_size = Vector2(380, 0)
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sel.add_child(_level_label)
	var nxt := UITheme.button("▶", func(): _switch(1))
	nxt.focus_mode = Control.FOCUS_NONE
	sel.add_child(nxt)
	vb.add_child(sel)
	_table_box = VBoxContainer.new()
	vb.add_child(_table_box)
	_show_level()
	if not embedded:
		var back := UITheme.button("ZURÜCK", _close)
		back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vb.add_child(back)
		await get_tree().process_frame
		back.grab_focus()


func _show_level() -> void:
	var lvl: Dictionary = Config.difficulty_level(level_idx)
	_level_label.text = String(lvl.name).to_upper()
	for c in _table_box.get_children():
		c.queue_free()
	var t := build_table(highlight_rank if level_idx == Settings.difficulty else -1, false, lvl.key)
	t.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_table_box.add_child(t)


func _switch(step: int) -> void:
	level_idx = wrapi(level_idx + step, 0, Config.DIFFICULTY_LEVELS.size())
	Audio.ui("ui_move")
	_show_level()


## compact = kleinere Schrift (Auswertung). Einträge mit Sieg tragen den Zusatz [SIEG].
## key = Schwierigkeitsstufe der Liste ("" = aktuelle Stufe aus den Optionen).
static func build_table(hl: int, compact := false, key := "") -> GridContainer:
	var entries: Array = Highscores.list(key if key != "" else Settings.difficulty_key())
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 28 if compact else 46)
	grid.add_theme_constant_override("v_separation", 2 if compact else 6)
	var fs := 22 if compact else 26
	for h in ["#", "NAME", "PUNKTE", "STUFE", "DATUM"]:
		grid.add_child(UITheme.label(h, 18 if compact else 20, UITheme.CYAN, "display"))
	for i in entries.size():
		var e: Dictionary = entries[i]
		var col := UITheme.GREEN if i == hl else (UITheme.TEXT if i > 2 else UITheme.AMBER)
		grid.add_child(UITheme.label("%d." % (i + 1), fs, col, "mono"))
		grid.add_child(UITheme.label(str(e.name) + ("  [SIEG]" if e.get("won", false) else ""), fs, col, "body_bold"))
		grid.add_child(UITheme.label("%07d" % int(e.score), fs, col, "mono"))
		grid.add_child(UITheme.label(str(int(e.get("level", 0)) + 1) if str(e.get("date", "–")) != "–" else "–", fs, col, "mono"))
		grid.add_child(UITheme.label(str(e.get("date", "–")), fs - 4, Color(col, 0.8), "body"))
	return grid


func _close() -> void:
	closed.emit()
	queue_free()


## Links/Rechts (Tasten, Steuerkreuz, Stick) wechseln die Liste – einmal je Druck. Abgefangen, bevor die
## Fokussteuerung sie nutzt; der Stick zählt erst wieder, wenn er losgelassen wurde (just_pressed).
func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event.is_action("ui_left") or event.is_action("ui_right"):
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("ui_left"):
		_switch(-1)
	elif Input.is_action_just_pressed("ui_right"):
		_switch(1)


func _unhandled_input(event: InputEvent) -> void:
	if embedded:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		Audio.ui("ui_back")
		_close()
		get_viewport().set_input_as_handled()
