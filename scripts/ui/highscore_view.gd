class_name HighscoreView
extends Control
## Highscore-Tabelle (lokal gespeichert).

signal closed

var highlight_rank := -1
var embedded := false


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
	vb.add_child(build_table(highlight_rank))
	if not embedded:
		var back := UITheme.button("ZURÜCK", _close)
		back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vb.add_child(back)
		await get_tree().process_frame
		back.grab_focus()


## compact = kleinere Schrift (Auswertung). Einträge mit Sieg tragen den Zusatz [SIEG].
static func build_table(hl: int, compact := false) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 28 if compact else 46)
	grid.add_theme_constant_override("v_separation", 2 if compact else 6)
	var fs := 22 if compact else 26
	for h in ["#", "NAME", "PUNKTE", "STUFE", "DATUM"]:
		grid.add_child(UITheme.label(h, 18 if compact else 20, UITheme.CYAN, "display"))
	for i in Highscores.entries.size():
		var e: Dictionary = Highscores.entries[i]
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


func _unhandled_input(event: InputEvent) -> void:
	if embedded:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		Audio.ui("ui_back")
		_close()
		get_viewport().set_input_as_handled()
