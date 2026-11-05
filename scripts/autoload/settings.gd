extends Node
## Benutzereinstellungen (Audio, Grafik, Steuerung, Spieloptionen) + Tastenbelegung.
## Gespeichert in user://settings.cfg. Spieloptionen werden in die zentralen Werte (Config) übernommen.

signal changed

const PATH := "user://settings.cfg"
const QUALITY_NAMES := ["Hoch", "Mittel", "Niedrig"]
const SAVED_KEYS := ["master_volume", "music_volume", "sfx_volume", "fullscreen", "vsync", "retro_filter",
	"cockpit_view", "screen_shake", "invert_y", "auto_weapon", "offscreen_indicators", "scanner_heading_up",
	"orbit_fighters", "single_destroyer_stops", "difficulty", "quality"]

# Audio (0..1)
var master_volume := 0.9
var music_volume := 0.7
var sfx_volume := 0.9
# Grafik
var fullscreen := false
var vsync := true
var retro_filter := true      ## dezente Scanlines/Vignette
var cockpit_view := true      ## Cockpit mit Head-Up-Display (aus = klassische flache Anzeige)
var quality := 0              ## 0 = Hoch, 1 = Mittel, 2 = Niedrig
var screen_shake := 1.0
# Steuerung
var invert_y := false
# Spieloptionen (überschreiben Config-Standardwerte)
var auto_weapon := true
var offscreen_indicators := true
var scanner_heading_up := true
var orbit_fighters := 9                 ## [ORIGINAL] 9 oder 12
var single_destroyer_stops := true      ## [VERMUTET] abschaltbar
var difficulty := 1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	# Standardwerte der Spieloptionen aus Config übernehmen (balance.cfg kann sie vorgeben)
	auto_weapon = Config.auto_weapon_switch
	offscreen_indicators = Config.offscreen_indicators
	scanner_heading_up = Config.scanner_heading_up
	orbit_fighters = Config.orbit_fighter_count
	single_destroyer_stops = Config.single_destroyer_stops
	load_settings()
	apply()


func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	for key in SAVED_KEYS:
		if cf.has_section_key("settings", key):
			set(key, cf.get_value("settings", key))


func save_settings() -> void:
	var cf := ConfigFile.new()
	for key in SAVED_KEYS:
		cf.set_value("settings", key, get(key))
	cf.save(PATH)


func apply() -> void:
	_set_bus("Master", master_volume)
	_set_bus("Music", music_volume)
	_set_bus("SFX", sfx_volume)
	_set_bus("UI", sfx_volume)
	if not _headless():
		var mode := DisplayServer.window_get_mode()
		if fullscreen and mode != DisplayServer.WINDOW_MODE_FULLSCREEN and mode != DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		elif not fullscreen and (mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN):
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	var vp := get_viewport()
	if vp:
		vp.msaa_3d = Viewport.MSAA_2X if quality == 0 else Viewport.MSAA_DISABLED
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if quality > 0 else Viewport.SCREEN_SPACE_AA_DISABLED
	RenderingServer.directional_shadow_atlas_set_size(4096 if quality == 0 else 2048, true)
	Config.auto_weapon_switch = auto_weapon
	Config.offscreen_indicators = offscreen_indicators
	Config.scanner_heading_up = scanner_heading_up
	Config.orbit_fighter_count = orbit_fighters
	Config.single_destroyer_stops = single_destroyer_stops
	difficulty = clampi(difficulty, 0, Config.DIFFICULTY_LEVELS.size() - 1)
	# die Stufe gilt für die ganze Partie (eigene Highscore-Liste): mitten im Spiel erst ab der nächsten Partie
	if not GameState.in_game:
		Config.apply_difficulty(difficulty)
	Config.screen_shake = screen_shake
	changed.emit()


## Schwierigkeitsstufen [Vorgabe 0.13.0] – Index wie bis 0.12.0 (0 Leicht → Kinderspiel, 1 Normal → Anfänger,
## 2 Schwer → Normal), gespeicherte Einstellungen passen also weiter.
func difficulty_key() -> String:
	return Config.difficulty_level(difficulty).key


func difficulty_name() -> String:
	return Config.difficulty_level(difficulty).name


static func difficulty_names() -> Array:
	var out := []
	for l in Config.DIFFICULTY_LEVELS:
		out.append(l.name)
	return out


func shadows_enabled() -> bool:
	return quality < 2


func ssao_enabled() -> bool:
	return quality == 0


func particle_scale() -> float:
	return [1.0, 0.8, 0.5][clampi(quality, 0, 2)]


func _headless() -> bool:
	return DisplayServer.get_name() == "headless"


func _set_bus(bus_name: String, value: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	AudioServer.set_bus_mute(idx, value <= 0.001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(value, 0.0001)) + (-3.0 if bus_name == "Music" else 0.0))


func toggle_fullscreen() -> void:
	fullscreen = not fullscreen
	apply()
	save_settings()


# ---------------------------------------------------------------------------------------------
#  Tastenbelegung (Vorschlag aus der Spielbeschreibung: Pfeile/WASD, eine Feuertaste, Leertaste = Karte)
# ---------------------------------------------------------------------------------------------
func _setup_input() -> void:
	_action("steer_left", [KEY_LEFT, KEY_A], [JOY_BUTTON_DPAD_LEFT], [[JOY_AXIS_LEFT_X, -1.0]])
	_action("steer_right", [KEY_RIGHT, KEY_D], [JOY_BUTTON_DPAD_RIGHT], [[JOY_AXIS_LEFT_X, 1.0]])
	_action("steer_up", [KEY_UP, KEY_W], [JOY_BUTTON_DPAD_UP], [[JOY_AXIS_LEFT_Y, -1.0]])
	_action("steer_down", [KEY_DOWN, KEY_S], [JOY_BUTTON_DPAD_DOWN], [[JOY_AXIS_LEFT_Y, 1.0]])
	_action("fire", [KEY_CTRL, KEY_ENTER, KEY_KP_ENTER, KEY_J, KEY_F], [JOY_BUTTON_A], [[JOY_AXIS_TRIGGER_RIGHT, 1.0]])
	_action("toggle_map", [KEY_SPACE, KEY_M], [JOY_BUTTON_Y, JOY_BUTTON_BACK], [])
	_action("switch_weapon", [KEY_Q, KEY_TAB], [JOY_BUTTON_X, JOY_BUTTON_RIGHT_SHOULDER], [])
	_action("pause", [KEY_ESCAPE, KEY_P], [JOY_BUTTON_START], [])
	_action("map_next", [KEY_E, KEY_PAGEDOWN], [JOY_BUTTON_RIGHT_SHOULDER], [])
	_action("map_prev", [KEY_PAGEUP], [JOY_BUTTON_LEFT_SHOULDER], [])
	_action("toggle_fullscreen", [KEY_F11], [], [])
	# Mausklick als zusätzliche Feuertaste
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("fire", mb)


func _action(action_name: String, keys: Array, buttons: Array, axes: Array) -> void:
	if InputMap.has_action(action_name):
		InputMap.erase_action(action_name)
	InputMap.add_action(action_name, 0.3)
	for k in keys:
		var e := InputEventKey.new()
		e.keycode = k
		InputMap.action_add_event(action_name, e)
	for b in buttons:
		var j := InputEventJoypadButton.new()
		j.button_index = b
		j.device = -1
		InputMap.action_add_event(action_name, j)
	for a in axes:
		var m := InputEventJoypadMotion.new()
		m.axis = a[0]
		m.axis_value = a[1]
		m.device = -1
		InputMap.action_add_event(action_name, m)
