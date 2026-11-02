class_name GameOverScreen
extends Control
## Game Over [ORIGINAL]: Energie 0 oder alle Städte zerstört. Punkte, Statistik, Highscore (lokal).

var _box: VBoxContainer
var _name_edit: LineEdit
var _rank := -1
var _t := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.get_theme()
	Audio.stop_all_loops(0.3)
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
		tr.modulate = Color(0.55, 0.4, 0.45)
		add_child(tr)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 12)
	_box.custom_minimum_size = Vector2(1000, 0)
	center.add_child(_box)
	_box.add_child(UITheme.title_label("SPIEL VORBEI", 84, UITheme.RED))
	var reason := "Die Energie deines Schiffs ist erschöpft." if GameState.game_over_reason == "energy" else "Alle Städte des Systems wurden zerstört."
	var rl := UITheme.label(reason, 30, UITheme.TEXT)
	rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(rl)
	var sc := UITheme.label("%07d" % GameState.score, 72, UITheme.AMBER, "mono")
	sc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(sc)
	var st: Dictionary = GameState.stats
	if not st.is_empty():
		var grid := GridContainer.new()
		grid.columns = 4
		grid.add_theme_constant_override("h_separation", 40)
		grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var rows := [["Fighter", st.fighters], ["Zerstörer", st.destroyers], ["Flaggschiffe", st.flagships],
			["Schwadrone", st.squadrons], ["Gerettete Planeten", st.planets_saved], ["Verlorene Städte", st.cities_lost],
			["Spielzeit", GameState.format_time(GameState.sim_time)], ["Stufe", GameState.level + 1]]
		for r in rows:
			grid.add_child(UITheme.label(r[0], 24, UITheme.TEXT_DIM))
			grid.add_child(UITheme.label(str(r[1]), 26, UITheme.TEXT, "mono"))
		_box.add_child(grid)
	if Highscores.qualifies(GameState.score):
		var nl := UITheme.label("NEUER HIGHSCORE! Dein Name:", 30, UITheme.GREEN, "display")
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_box.add_child(nl)
		_name_edit = LineEdit.new()
		_name_edit.max_length = 12
		_name_edit.placeholder_text = "PILOT"
		_name_edit.text = _last_name()
		_name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
		_name_edit.custom_minimum_size = Vector2(420, 64)
		_name_edit.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_name_edit.text_submitted.connect(func(_s): _submit())
		_name_edit.text_changed.connect(func(_s): Audio.ui("ui_type"))
		_box.add_child(_name_edit)
		var ok := UITheme.button("EINTRAGEN", _submit)
		ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_box.add_child(ok)
		await get_tree().process_frame
		_name_edit.grab_focus()
		_name_edit.caret_column = _name_edit.text.length()
	else:
		_show_table()


func _last_name() -> String:
	var cf := ConfigFile.new()
	if cf.load("user://settings.cfg") == OK:
		return str(cf.get_value("player", "name", "PILOT"))
	return "PILOT"


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
	_rank = Highscores.add(n, GameState.score, GameState.level, GameState.sim_time)
	Audio.ui("ui_select")
	for i in 3:
		_box.get_child(_box.get_child_count() - 1).queue_free()
		_box.remove_child(_box.get_child(_box.get_child_count() - 1))
	_name_edit = null
	_show_table()


func _show_table() -> void:
	var hl := HighscoreView.build_table(_rank)
	hl.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_box.add_child(hl)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 24)
	var again := UITheme.button("NOCHMAL SPIELEN", func(): Main.instance.new_game())
	hb.add_child(again)
	hb.add_child(UITheme.button("HAUPTMENÜ", func(): Main.instance.goto_title()))
	_box.add_child(hb)
	await get_tree().process_frame
	again.grab_focus()
