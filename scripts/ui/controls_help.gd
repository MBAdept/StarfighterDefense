class_name ControlsHelp
extends Control
## Übersicht der Steuerung.

signal closed


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.get_theme()
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := ColorRect.new()
	dim.color = Color(0, 0.01, 0.03, 0.8)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)
	vb.add_child(UITheme.title_label("STEUERUNG", 46))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 40)
	grid.add_theme_constant_override("v_separation", 8)
	vb.add_child(grid)
	var rows := [
		["", "TASTATUR", "GAMEPAD"],
		["Steuern (All: links/rechts/rauf/runter)", "Pfeiltasten / W A S D", "Linker Stick / Steuerkreuz"],
		["Steuern (Planet: drehen / vor / zurück)", "Pfeiltasten / W A S D", "Linker Stick / Steuerkreuz"],
		["Feuer", "Strg / Enter / F / J / Maus", "A / rechter Trigger"],
		["Übersichtskarte", "Leertaste / M", "Y / Back"],
		["Waffe wechseln (Auto aus; Feindplanet: Laser / Bomben)", "Q / Tab", "X / RB"],
		["Karte: anderes System ansehen", "Q / Tab", "X"],
		["Karte: Ziel wählen", "Pfeile / Maus / E / Bild↑↓", "Stick / LB / RB"],
		["Karte: Springen", "Enter / Strg / Klick", "A"],
		["Pause", "Esc / P", "Start"],
		["Vollbild", "F11", ""],
		["Testfunktionen", "F1 (Hilfe), F2–F12", ""],
	]
	for r in rows:
		for i in 3:
			var col := UITheme.CYAN if r[0] == "" else (UITheme.TEXT if i == 0 else UITheme.AMBER)
			grid.add_child(UITheme.label(r[i], 26 if r[0] != "" else 22, col, "display" if r[0] == "" else "body"))
	var hint := UITheme.label("Waffen: Bordlaser gegen Fighter (Klammer-Visier), Ionen-Kanone gegen Zerstörer und Flaggschiff (Fadenkreuz).\nFlaggschiff: nur das rosa Quadrat – und nur, wenn es weiß-rosa leuchtet, kurz vor seinem Schuss!\nAusweichen: Im Moment des Einschlags kräftig lenken halbiert die Trefferchance des Gegners.", 22, UITheme.TEXT_DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(1100, 0)
	vb.add_child(hint)
	var back := UITheme.button("ZURÜCK", _close)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(back)
	await get_tree().process_frame
	back.grab_focus()


func _close() -> void:
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		Audio.ui("ui_back")
		_close()
		get_viewport().set_input_as_handled()
