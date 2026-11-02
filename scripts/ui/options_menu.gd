class_name OptionsMenu
extends Control
## Optionen: Audio, Grafik, Steuerung und Spieloptionen (inkl. [VERMUTET]-Schalter).

signal closed

var _first: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.get_theme()
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := ColorRect.new()
	dim.color = Color(0, 0.01, 0.03, 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1060, 0)
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	panel.add_child(vb)
	vb.add_child(UITheme.title_label("OPTIONEN", 46))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(1000, 700)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 30)
	grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(grid)

	_section(grid, "AUDIO")
	_first = _slider(grid, "Gesamtlautstärke", "master_volume", 0.0, 1.0)
	_slider(grid, "Musik", "music_volume", 0.0, 1.0)
	_slider(grid, "Effekte", "sfx_volume", 0.0, 1.0)
	_section(grid, "GRAFIK")
	_check(grid, "Vollbild (F11)", "fullscreen")
	_check(grid, "VSync", "vsync")
	_choice(grid, "Grafikqualität", "quality", Settings.QUALITY_NAMES, [0, 1, 2])
	_check(grid, "Retro-Filter (Scanlines/Vignette)", "retro_filter")
	_slider(grid, "Bildschirmwackeln", "screen_shake", 0.0, 1.5)
	_section(grid, "STEUERUNG & ANZEIGE")
	_check(grid, "Automatische Waffenwahl", "auto_weapon")
	_check(grid, "Y-Achse invertieren", "invert_y")
	_check(grid, "Pfeile zu Gegnern außerhalb der Sicht", "offscreen_indicators")
	_check(grid, "Planetenscanner dreht mit Flugrichtung", "scanner_heading_up")
	_section(grid, "SPIEL")
	_choice(grid, "Orbit-Start: Fighter", "orbit_fighters", ["9 Fighter", "12 Fighter"], [9, 12])
	_check(grid, "Schwadron mit nur 1 Zerstörer stoppt zeitweise (vermutet)", "single_destroyer_stops")
	_choice(grid, "Schwierigkeit", "difficulty", Settings.DIFFICULTY_NAMES, [0, 1, 2])

	var back := UITheme.button("ZURÜCK", _close)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(back)
	await get_tree().process_frame
	if _first:
		_first.grab_focus()


func _section(grid: GridContainer, text: String) -> void:
	var l := UITheme.label(text, 22, UITheme.CYAN, "display")
	grid.add_child(l)
	grid.add_child(Control.new())


func _row_label(grid: GridContainer, text: String) -> void:
	var l := UITheme.label(text, 26, UITheme.TEXT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(l)


func _slider(grid: GridContainer, text: String, key: String, mn: float, mx: float) -> Control:
	_row_label(grid, text)
	var s := HSlider.new()
	s.min_value = mn
	s.max_value = mx
	s.step = 0.05
	s.value = Settings.get(key)
	s.custom_minimum_size = Vector2(320, 36)
	s.focus_mode = Control.FOCUS_ALL
	s.value_changed.connect(func(v):
		Settings.set(key, v)
		Settings.apply()
		Audio.ui("ui_move", -6.0)
	)
	grid.add_child(s)
	return s


func _check(grid: GridContainer, text: String, key: String) -> Control:
	_row_label(grid, text)
	var c := CheckButton.new()
	c.button_pressed = Settings.get(key)
	c.text = "AN" if c.button_pressed else "AUS"
	c.focus_mode = Control.FOCUS_ALL
	c.toggled.connect(func(on):
		Settings.set(key, on)
		c.text = "AN" if on else "AUS"
		Settings.apply()
		Audio.ui("ui_select")
	)
	grid.add_child(c)
	return c


func _choice(grid: GridContainer, text: String, key: String, labels: Array, values: Array) -> Control:
	_row_label(grid, text)
	var o := OptionButton.new()
	for i in labels.size():
		o.add_item(labels[i], i)
	o.selected = maxi(values.find(Settings.get(key)), 0)
	o.focus_mode = Control.FOCUS_ALL
	o.item_selected.connect(func(i):
		Settings.set(key, values[i])
		Settings.apply()
		Audio.ui("ui_select")
	)
	grid.add_child(o)
	return o


func _close() -> void:
	Settings.save_settings()
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		Audio.ui("ui_back")
		_close()
		get_viewport().set_input_as_handled()
