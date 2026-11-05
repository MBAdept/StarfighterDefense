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
		var home := GameState.enemy_home()
		if Config.victory_all_enemy_cities:
			reason = "Alle Städte im %s-System sind zerstört – das %s-System ist gerettet." % [GameState.ENEMY_STAR_NAME, GameState.STAR_NAME]
		else:
			reason = "Die feindliche Heimatwelt %s ist gefallen – das %s-System ist gerettet." % [home.name if home else "", GameState.STAR_NAME]
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
		_name_edit.text_changed.connect(func(_s): Audio.ui("ui_type"))
		_right.add_child(_name_edit)
		var ok := UITheme.button("EINTRAGEN", _submit)
		ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_right.add_child(ok)
		_entry_nodes = [nl, _name_edit, ok]
		await get_tree().process_frame
		if is_instance_valid(_name_edit):
			_name_edit.grab_focus()
			_name_edit.caret_column = _name_edit.text.length()
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
		["Vernichtete Schwadrone (im Feindsystem)", "%d (%d)" % [st.get("squadrons", 0), st.get("enemy_squadrons_intercepted", 0)]],
		["Gerettete Planeten · verteidigte Stationen", "%d · %d" % [st.get("planets_saved", 0), st.get("stations_defended", 0)]],
		["Bomben", bomb_line],
		["Sprünge (davon zwischen den Systemen)", "%d (%d)" % [st.get("jumps", 0), st.get("enemy_jumps", 0)]],
		["Sternbesuche · Systemschäden (repariert)", "%d · %d (%d)" % [st.get("star_visits", 0), st.get("damages", 0), st.get("repairs", 0)]],
		["Erreichte Stufe · Schwierigkeit", "%d · %s" % [GameState.level + 1, GameState.difficulty_name]],
	]
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
