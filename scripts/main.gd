class_name Main
extends Node
## =============================================================================================
##  Hauptknoten: Spielzustände, Karten-Overlay, Sprünge (Hyperraum), Pause, Testfunktionen.
##  Zustände [Spielbeschreibung §2]: Titel, Orbit-Start, Karte, Weltraumkampf, Planetenkampf,
##  Andocken, Auswertung (Game Over / Sieg / Abbruch). Das Feindsystem nutzt dieselben Kampfszenen
##  (Empfangskomitee = Weltraumkampf, Feindplanet = Planetenkampf mit Bomben).
## =============================================================================================

static var instance: Main

enum State { NONE, TITLE, ORBIT, SPACE, PLANET, STATION, GAME_OVER, ENEMY_SYSTEM }

var state := State.NONE
var scene: Node = null                 ## aktuelle Hauptszene (3D-Kampf, Titel …)
var state_root: Node
var map_layer: CanvasLayer
var map_screen: MapScreen = null
var postfx_layer: CanvasLayer
var postfx: ColorRect
var ticker_layer: CanvasLayer
var ticker: EventTicker
var transition: TransitionOverlay
var pause_layer: CanvasLayer
var pause_menu: PauseMenu = null
var debug_label: Label
var _jumping := false
var _jump_target_pos := Vector2.ZERO
var _test := {}


func _ready() -> void:
	instance = self
	get_tree().root.theme = UITheme.get_theme()
	state_root = Node.new()
	state_root.name = "StateRoot"
	state_root.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(state_root)

	postfx_layer = CanvasLayer.new()
	postfx_layer.layer = 1
	postfx_layer.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(postfx_layer)
	postfx = ColorRect.new()
	postfx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	postfx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pm := ShaderMaterial.new()
	pm.shader = load("res://shaders/postfx.gdshader")
	postfx.material = pm
	postfx_layer.add_child(postfx)
	postfx_layer.visible = false

	map_layer = CanvasLayer.new()
	map_layer.layer = 10
	map_layer.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(map_layer)

	ticker_layer = CanvasLayer.new()
	ticker_layer.layer = 20
	ticker_layer.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(ticker_layer)
	ticker = EventTicker.new()
	ticker_layer.add_child(ticker)

	transition = TransitionOverlay.new()
	add_child(transition)

	pause_layer = CanvasLayer.new()
	pause_layer.layer = 80
	pause_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(pause_layer)

	var dbg_layer := CanvasLayer.new()
	dbg_layer.layer = 99
	add_child(dbg_layer)
	debug_label = Label.new()
	debug_label.position = Vector2(12, 8)
	debug_label.add_theme_font_size_override("font_size", 18)
	debug_label.add_theme_color_override("font_color", Color(1, 1, 0.6, 0.9))
	debug_label.visible = false
	dbg_layer.add_child(debug_label)

	GameState.game_over_triggered.connect(_on_game_over)
	_parse_test_args()
	if _test.is_empty():
		goto_title()
	else:
		_run_test_scenario()


# =============================================================================================
#  Zustandswechsel
# =============================================================================================
func _set_scene(node: Node, new_state: State) -> void:
	if scene:
		# alte Szene sofort anhalten: ohne Physik-Schritt in diesem Frame (hohe Bildrate) liefe ihr _process
		# sonst noch einmal und startete Loops (Bombardement, Ladeton) nach stop_all_loops() neu
		scene.process_mode = Node.PROCESS_MODE_DISABLED
		scene.queue_free()
		scene = null
	Audio.stop_all_loops(0.2)
	state = new_state
	scene = node
	state_root.add_child(node)
	var is_3d := new_state in [State.ORBIT, State.SPACE, State.PLANET, State.STATION]
	postfx_layer.visible = is_3d and Settings.retro_filter
	ticker.visible = new_state in [State.ORBIT, State.SPACE, State.PLANET, State.STATION]


## Bricht einen laufenden Hyperraumsprung ab (z. B. Game Over während des Sprungs).
func _abort_jump() -> void:
	_jumping = false
	transition.cancel_hyperjump()


func goto_title() -> void:
	_abort_jump()
	close_map(false)
	get_tree().paused = false
	GameState.running = false
	GameState.in_game = false
	_set_scene(TitleScreen.new(), State.TITLE)


## Pausemenü "Spiel beenden": laufende Partie abbrechen → Auswertung (sonst Titel).
func abort_game() -> void:
	get_tree().paused = false
	if GameState.in_game and not GameState.game_over and not GameState.planets.is_empty():
		GameState.abort_game()   # → game_over_triggered("abort") → Auswertung
	else:
		goto_title()


func new_game() -> void:
	_abort_jump()
	GameState.new_game()
	if _test.has("simspeed"):
		GameState.time_scale = float(_test["simspeed"])
	ticker.clear()
	transition.fade(func():
		if Config.start_with_orbit:
			_set_scene(SpaceCombat.create_orbit(), State.ORBIT)
		else:
			GameState.start_campaign()
			_set_scene(SpaceCombat.create_orbit(true), State.ORBIT)
	, 0.6, 0.8)


func goto_game_over(out_time := 1.2) -> void:
	_abort_jump()
	close_map(false)
	get_tree().paused = false
	GameState.in_game = false
	transition.fade(func():
		_set_scene(GameOverScreen.new(), State.GAME_OVER)
	, out_time, 1.0)


func _on_game_over(reason: String) -> void:
	if reason == "abort":
		if scene is CombatBase and not (scene as CombatBase).frozen:
			(scene as CombatBase).set_frozen(true)   # kein weiterer Kampf während des Abblendens
		goto_game_over(0.6)
		return
	if reason == "victory":
		# Siegsequenz in der Kampfszene (Explosionen, Fanfare), danach Auswertung
		if not is_map_open() and scene and scene.has_method("play_victory_sequence") and not (scene as CombatBase).frozen:
			scene.play_victory_sequence(func(): goto_game_over(1.6))
		else:
			goto_game_over()
		return
	# Kampfszene zeigt ggf. noch die Zerstörung des eigenen Schiffs (siehe CombatBase)
	if is_map_open() or (scene is CombatBase and (scene as CombatBase).frozen):
		goto_game_over()
		return
	if scene and scene.has_method("play_death_sequence"):
		scene.play_death_sequence(func(): goto_game_over(), reason)
	else:
		goto_game_over()


# =============================================================================================
#  Übersichtskarte (Overlay)  [ORIGINAL] Leertaste öffnet die Karte jederzeit, auch im Kampf
# =============================================================================================
func is_map_open() -> bool:
	return map_screen != null


func can_open_map() -> bool:
	if state in [State.TITLE, State.GAME_OVER, State.NONE] or _jumping or GameState.game_over:
		return false
	if scene and scene.has_method("map_allowed"):
		return scene.map_allowed()
	return true


func open_map() -> void:
	if is_map_open():
		return
	if not can_open_map():
		if scene and scene.has_method("on_map_denied"):
			scene.on_map_denied()
		return
	if not GameState.running and GameState.tutorial_done == false and state == State.ORBIT:
		return
	if scene and scene.has_method("set_frozen"):
		scene.set_frozen(true)
	postfx_layer.visible = false
	map_screen = MapScreen.new()
	map_layer.add_child(map_screen)
	Audio.sfx("map_open", -2.0, 1.0, 0.0, "UI")
	Audio.play_music(map_music(), 1.2)


func close_map(resume := true) -> void:
	if not is_map_open():
		return
	map_screen.queue_free()
	map_screen = null
	if resume:
		Audio.sfx("map_close", -2.0, 1.0, 0.0, "UI")
		if scene and scene.has_method("set_frozen"):
			scene.set_frozen(false)
		postfx_layer.visible = state in [State.ORBIT, State.SPACE, State.PLANET, State.STATION] and Settings.retro_filter
		if scene and scene.has_method("music_track"):
			Audio.play_music(scene.music_track(), 1.0)


## Kartenmusik des Systems, in dem sich der Spieler befindet.
func map_music() -> String:
	return "enemy_system_theme" if GameState.player_system == 1 else "map_theme"


func is_jumping() -> bool:
	return _jumping


## Sprung zu einem Kartenziel. kind: GameState.Loc, id: Objekt-ID.
## Über die Systemgrenze (ins Feindsystem / zurück nach Helion): feste Kosten, 3× so lang, roter Hyperraum.
func request_jump(kind: int, id: int) -> void:
	if _jumping:
		return
	if scene is PlanetCombat:
		(scene as PlanetCombat).resolve_pending_bombs()
		if GameState.game_over:
			return   # die letzte Bombe hat die letzte Feindstadt getroffen: Sieg statt Sprung
	var target_pos := _loc_map_pos(kind, id)
	var long := GameState.is_cross_system(kind)
	_jumping = true
	_jump_target_pos = target_pos
	close_map(false)
	GameState.pay_jump_to(kind, target_pos)
	if GameState.game_over:
		_jumping = false
		return
	transition.hyperjump(func():
		_enter_location(kind, id)
	, func():
		_jumping = false
	, long)


func _loc_map_pos(kind: int, id: int) -> Vector2:
	match kind:
		GameState.Loc.PLANET:
			return GameState.planets[id].map_pos()
		GameState.Loc.STATION:
			return GameState.stations[id].map_pos()
		GameState.Loc.SQUADRON:
			var sq := GameState.squadron_by_id(id)
			return sq.map_pos if sq else GameState.player_map_pos
		GameState.Loc.ENEMY_SYSTEM:
			return GameState.JUMP_POINT
		GameState.Loc.ENEMY_PLANET:
			return GameState.enemy_planets[id].map_pos()
		GameState.Loc.HOME_SYSTEM:
			return GameState.ENEMY_GATE
	return GameState.player_map_pos


func _enter_location(kind: int, id: int) -> void:
	match kind:
		GameState.Loc.PLANET:
			GameState.set_player_location(GameState.Loc.PLANET, id)
			_set_scene(PlanetCombat.create(GameState.planets[id]), State.PLANET)
		GameState.Loc.STATION:
			GameState.set_player_location(GameState.Loc.STATION, id)
			_set_scene(SpaceCombat.create_station(GameState.stations[id]), State.STATION)
		GameState.Loc.SQUADRON:
			var sq := GameState.squadron_by_id(id)
			if sq == null or sq.system != GameState.player_system:
				# vernichtet – oder während des Sprungs ins andere System gewechselt
				GameState.set_player_location(GameState.Loc.SPACE, -1)
				GameState.player_map_pos = _jump_target_pos
				var note := ""
				if sq != null:
					note = "%s ist ins %s-System gesprungen" % [sq.name, GameState.STAR_NAME]
				_set_scene(SpaceCombat.create_empty(false, note), State.SPACE)
			elif sq.state == SquadronData.State.LANDED:
				_enter_location(GameState.Loc.PLANET, sq.target_id)
			elif sq.state == SquadronData.State.AT_STATION:
				_enter_location(GameState.Loc.STATION, sq.target_id)
			else:
				GameState.set_player_location(GameState.Loc.SQUADRON, id)
				_set_scene(SpaceCombat.create_squadron(sq), State.SPACE)
		GameState.Loc.ENEMY_SYSTEM:
			# Ankunft im Feindsystem: Empfangskomitee, solange es noch Fighter hat (Config.reception_once)
			GameState.enter_enemy_system()
			_set_scene(SpaceCombat.create_reception(), State.SPACE)
		GameState.Loc.HOME_SYSTEM:
			GameState.enter_home_system()
			_set_scene(SpaceCombat.create_empty(true), State.SPACE)
		GameState.Loc.ENEMY_PLANET:
			GameState.set_player_location(GameState.Loc.ENEMY_PLANET, id)
			_set_scene(PlanetCombat.create(GameState.enemy_planets[id]), State.PLANET)
		_:
			GameState.set_player_location(GameState.Loc.SPACE, -1)
			_set_scene(SpaceCombat.create_empty(), State.SPACE)


# =============================================================================================
#  Eingabe: Karte, Pause, Testfunktionen
# =============================================================================================
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fullscreen"):
		Settings.toggle_fullscreen()
		get_viewport().set_input_as_handled()
		return
	if get_tree().paused:
		return
	if event.is_action_pressed("pause"):
		if state in [State.ORBIT, State.SPACE, State.PLANET, State.STATION] and not _jumping and not GameState.game_over:
			open_pause()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("toggle_map") and not event.is_echo():
		if is_map_open():
			if map_screen.can_close():
				close_map()
			else:
				Audio.ui("ui_error")
		else:
			open_map()
		get_viewport().set_input_as_handled()
		return
	if Config.debug_keys_enabled and event is InputEventKey and event.pressed and not event.echo:
		_debug_key(event.keycode)


func open_pause() -> void:
	if pause_menu:
		return
	get_tree().paused = true
	pause_menu = PauseMenu.new()
	pause_layer.add_child(pause_menu)
	pause_menu.closed.connect(func():
		pause_menu = null
		get_tree().paused = false
	)


func _debug_key(code: int) -> void:
	match code:
		KEY_F1:
			debug_label.visible = not debug_label.visible
			debug_label.text = "TESTTASTEN: F2 Energie +50 und Bomben voll | F3 neues Schwadron | F4 Orbit-Kampf überspringen | F5 Gegner im Kampf vernichten\nF6 Schwadron auf nächsten Planeten landen + hinspringen | F7 Strategiezeit x4 | F8 direkt ins Feindsystem | F9 Game Over | F10 Energie -20 | F12 Screenshot"
		KEY_F2:
			GameState.change_energy(50.0)
			while GameState.refill_bomb():
				pass
		KEY_F3:
			GameState.debug_spawn_squadron()
		KEY_F4:
			if scene and scene.has_method("debug_finish_orbit") and not is_map_open() and not _jumping and not GameState.game_over and not (scene as CombatBase).dying:
				scene.debug_finish_orbit()   # Orbit-Kampf bzw. Empfangskomitee
		KEY_F5:
			if scene and scene.has_method("debug_kill_all"):
				scene.debug_kill_all()
		KEY_F6:
			if GameState.planets.is_empty():
				return
			if _jumping or GameState.game_over:
				return
			var p: PlanetData = GameState.planets[(GameState.player_loc_id + 1) % GameState.planets.size()] if GameState.player_loc == GameState.Loc.PLANET else GameState.home_planet()
			if GameState.player_system == 1:
				GameState.enter_home_system()
			GameState.debug_land_squadron_on(p)
			close_map(false)
			_enter_location(GameState.Loc.PLANET, p.id)
		KEY_F7:
			GameState.time_scale = 4.0 if GameState.time_scale == 1.0 else 1.0
			ticker.push("Strategiezeit x%d" % int(GameState.time_scale), GameState.Sev.INFO)
		KEY_F8:
			if not GameState.planets.is_empty() and not _jumping and not GameState.game_over and state in [State.ORBIT, State.SPACE, State.PLANET, State.STATION]:
				if not GameState.running:
					GameState.start_campaign()
				close_map(false)
				_enter_location(GameState.Loc.ENEMY_SYSTEM, -1)
		KEY_F9:
			if not GameState.planets.is_empty():
				GameState.trigger_game_over("energy")
		KEY_F10:
			GameState.change_energy(-20.0)
		KEY_F12:
			var img := get_viewport().get_texture().get_image()
			var path := "user://screenshot_%d.png" % Time.get_ticks_msec()
			img.save_png(path)
			ticker.push("Screenshot: " + ProjectSettings.globalize_path(path), GameState.Sev.INFO)


# =============================================================================================
#  Testszenarien über Kommandozeile (für automatisierte Screenshots):
#    godot --path . -- --test=orbit|space|planet|station|map|title|gameover|enemy --shot=/pfad.png --wait=4
#  Testfahrer (Balancing-Messung, Protokoll mit SQUAD_COST/RUN_SUMMARY in der Konsole):
#    godot --headless --path . --fixed-fps 60 --quit-after 54000 -- --autoplay [--human] [--h_evade=0.3 …]
# =============================================================================================
func _parse_test_args() -> void:
	# Hinweis: GameState.time_scale wird in new_game() zurückgesetzt; --simspeed greift danach erneut
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			var kv := a.substr(2).split("=", true, 1)
			_test[kv[0]] = kv[1]
		elif a.begins_with("--"):
			_test[a.substr(2)] = "1"


func _run_test_scenario() -> void:
	var what: String = _test.get("test", "title")
	if _test.has("autoplay"):
		var ap := AutoPilot.new()
		ap.passive = _test.has("passive")
		ap.human = _test.has("human")   # menschenähnlicher Testfahrer (Reaktionszeit, Zielfehler, ~70 % Drehrate)
		ap.apply_test_args(_test)       # optionale Feineinstellung: --h_evade=0.3 --h_err_max=3 … (siehe autopilot.gd)
		add_child(ap)
		move_child(ap, 0)
	if _test.has("simspeed"):
		GameState.time_scale = float(_test["simspeed"])
	if _test.has("holdfire"):
		Input.action_press("fire")

	if _test.has("speed"):
		Engine.time_scale = float(_test["speed"])
	GameState.new_game()
	if _test.has("simspeed"):
		GameState.time_scale = float(_test["simspeed"])
	match what:
		"title":
			goto_title()
		"orbit":
			_set_scene(SpaceCombat.create_orbit(), State.ORBIT)
		"space", "squadron":
			GameState.start_campaign()
			var sq: SquadronData = GameState.squadrons[0]
			if _test.has("destroyers"):
				sq.fighters = 0
			if _test.has("flagship"):
				sq.has_flagship = true
			_enter_location(GameState.Loc.SQUADRON, sq.id)
		"planet":
			var p := GameState.home_planet()
			if _test.has("planet"):
				p = GameState.planets[clampi(int(_test["planet"]), 0, GameState.planets.size() - 1)]
			GameState.debug_land_squadron_on(p)
			_enter_location(GameState.Loc.PLANET, p.id)
		"station":
			GameState.start_campaign()
			_enter_location(GameState.Loc.STATION, 0)
		"station_attack":
			GameState.start_campaign()
			var sq2: SquadronData = GameState.squadrons[0]
			sq2.target_kind = SquadronData.TargetKind.STATION
			sq2.target_id = 0
			sq2.map_pos = GameState.stations[0].map_pos()
			GameState._arrive(sq2)
			_enter_location(GameState.Loc.STATION, 0)
		"map":
			GameState.start_campaign()
			GameState.time_scale = 1.0
			_set_scene(SpaceCombat.create_orbit(true), State.ORBIT)
			await get_tree().process_frame
			open_map()
			if _test.get("select", "") == "enemy" and map_screen:
				map_screen._select(GameState.Loc.ENEMY_SYSTEM, -1, false)
			if _test.has("enemyview") and map_screen:
				map_screen.toggle_view()
			if _test.has("jumptest"):
				await get_tree().create_timer(1.5).timeout
				request_jump(GameState.Loc.SQUADRON, GameState.squadrons[0].id)
		"gameover", "evaluation":
			GameState.score = 12345
			GameState.end_kind = _test.get("end", "gameover")
			GameState.game_over_reason = {"victory": "victory", "abort": "abort"}.get(GameState.end_kind, "energy")
			GameState.victory = GameState.end_kind == "victory"
			GameState.play_time = 1534.0
			for k in ["fighters", "destroyers", "flagships", "enemy_cities", "cities_lost"]:
				GameState.stats[k] = {"fighters": 87, "destroyers": 14, "flagships": 2, "enemy_cities": 23, "cities_lost": 9}[k]
			GameState.stats.points = {"fighters": 4350, "destroyers": 10250, "flagships": 10000, "enemy_cities": 115000, "bonus": 7800}
			GameState.game_over = true
			GameState.in_game = false
			_set_scene(GameOverScreen.new(), State.GAME_OVER)
		"enemy":
			# Sprung ins Feindsystem: Empfangskomitee
			GameState.start_campaign()
			_enter_location(GameState.Loc.ENEMY_SYSTEM, -1)
		"enemy_planet", "victory":
			# Feindplanet (--planet=N, 0 = Heimatwelt); --nodefenders: Luftverteidigung bereits ausgeschaltet
			GameState.start_campaign()
			GameState.player_system = 1
			GameState.reception_active = false
			var idx := clampi(int(_test.get("planet", "0" if what == "victory" else "1")), 0, GameState.enemy_planets.size() - 1)
			var ep: PlanetData = GameState.enemy_planets[idx]
			if _test.has("nodefenders") or what == "victory":
				ep.defenders = 0
			if what == "victory":
				# nur noch eine einzige Feindstadt übrig (auf diesem Planeten)
				for op in GameState.enemy_planets:
					for ci in op.cities.size():
						if op != ep or ci < op.cities.size() - 1:
							op.cities[ci] = false
			_enter_location(GameState.Loc.ENEMY_PLANET, idx)
		"enemy_intercept":
			# Schwadron im Feindsystem abfangen (Zerstörer/Flaggschiff möglich)
			GameState.start_campaign()
			GameState.player_system = 1
			GameState.reception_active = false
			var esq: SquadronData = GameState._launch_enemy_squadron(GameState.enemy_planets[2], 2, 0.4)
			if _test.has("flagship"):
				esq.has_flagship = true
			_enter_location(GameState.Loc.SQUADRON, esq.id)
		"enemy_map":
			GameState.start_campaign()
			GameState.time_scale = 1.0
			GameState.player_system = 1
			GameState.reception_active = false
			for i in 2:
				GameState._launch_enemy_squadron(GameState.enemy_planets[1 + i], 1, 0.3 + 0.3 * i)
			GameState.set_player_location(GameState.Loc.ENEMY_SYSTEM, -1)
			_set_scene(SpaceCombat.create_empty(), State.SPACE)
			await get_tree().process_frame
			open_map()
	if _test.has("shot"):
		var wait := float(_test.get("wait", "3"))
		if _test.has("look"):
			await get_tree().create_timer(maxf(wait - 0.6, 0.1)).timeout
			if scene and scene.has_method("debug_look_at"):
				scene.debug_look_at(_test["look"])
			await get_tree().create_timer(0.6).timeout
		else:
			await get_tree().create_timer(wait).timeout
		var shots := int(_test.get("count", "1"))
		for i in shots:
			var img := get_viewport().get_texture().get_image()
			var path: String = _test["shot"]
			if shots > 1:
				path = path.get_basename() + "_%d.png" % i
			img.save_png(path)
			print("[Test] Screenshot gespeichert: ", path)
			if i < shots - 1:
				await get_tree().create_timer(float(_test.get("interval", "1"))).timeout
		get_tree().quit()
