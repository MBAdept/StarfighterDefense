class_name EventTicker
extends Control
## Meldungen der strategischen Ebene (Angriffe, Landungen, zerstörte Städte …) – auch im Kampf.

const LIFETIME := 6.5
var _items: Array = []   # [{text, sev, t}]
var _cue_t := 0.0        ## Abklingzeit des Hinweistons (Config.ticker_alert_cooldown)
var _glow_mat: ShaderMaterial   ## Cockpit-Ansicht: Leuchtschrift wie die HUD-Symbolik


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow_mat = ShaderMaterial.new()
	_glow_mat.shader = load("res://shaders/hud_light.gdshader")
	GameState.event_logged.connect(_on_event)
	GameState.alert_raised.connect(_on_alert)
	# [Spielbeschreibung §12] Alarm bei Angriff auf eine Station – endet nach Config.alarm_duration
	# (bei gestörter Kommunikation nur, wenn die Meldung durchkommt)
	GameState.squadron_at_station.connect(func(_sq, _st):
		if not GameState.last_event_lost():
			Audio.alarm(0.0))


## Meldung aus GameState.log_event: bei gestörter Kommunikation verstümmelt oder ganz verloren.
func _on_event(text: String, sev: int) -> void:
	var shown := text
	if not GameState.events.is_empty() and GameState.events.back().text == text:
		shown = GameState.event_shown(GameState.events.back())
	if shown != "":
		push(shown, sev)


## Hinweiston für Warnmeldungen aus dem System. Der Geschoss-Warnton ("incoming") bleibt echten
## Geschossen vorbehalten; Ereignisse am aktuellen Ort vertont die Szene selbst.
func _on_alert(kind: String, ref: int) -> void:
	if kind == "station_attack" or kind == "second_system" or GameState.last_event_lost():
		return   # Stationsangriff / zweites Feindsystem: dafür gibt es den (zeitlich begrenzten) Alarm; verlorene Meldung: kein Ton
	var here := false
	match kind:
		"landing", "city":
			here = GameState.is_player_at_planet(ref)
		"station_lost":
			here = GameState.is_player_at_station(ref)
	if here or _cue_t > 0.0:
		return
	_cue_t = Config.ticker_alert_cooldown
	Audio.ui("ui_error", -6.0)


func push(text: String, sev: int) -> void:
	_items.append({"text": text, "sev": sev, "t": 0.0})
	if _items.size() > 4:
		_items.pop_front()


func clear() -> void:
	_items.clear()


func _process(delta: float) -> void:
	_cue_t = maxf(_cue_t - delta, 0.0)
	for it in _items:
		it.t += delta
	_items = _items.filter(func(it): return it.t < LIFETIME)
	material = _glow_mat if Settings.cockpit_view else null
	queue_redraw()


func _draw() -> void:
	if Main.instance and Main.instance.is_map_open():
		return
	if Settings.cockpit_view:
		_draw_hud()
		return
	var f := Assets.font("body_bold")
	var vp := get_viewport_rect().size
	var y := 92.0
	for it in _items:
		var a := clampf(it.t * 5.0, 0.0, 1.0) * clampf((LIFETIME - it.t) * 1.5, 0.0, 1.0)
		var col: Color = UITheme.sev_color(it.sev)
		var fs := 24
		var w := f.get_string_size(it.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var x := vp.x - w - 40.0
		var slide := (1.0 - clampf(it.t * 4.0, 0.0, 1.0)) * 40.0
		draw_rect(Rect2(x - 16 + slide, y - 26, w + 32, 36), Color(0.02, 0.05, 0.1, 0.55 * a))
		draw_rect(Rect2(x - 16 + slide, y - 26, 4, 36), Color(col, a))
		draw_string(f, Vector2(x + slide, y), it.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(col.lightened(0.3), a))
		y += 44.0


## Cockpit-Ansicht: Helm-Projektion wie die HUD-Symbolik – Leuchtschrift ohne Kästen in einer Spalte
## rechts neben dem Combiner-Glas, lange Meldungen umgebrochen.
func _draw_hud() -> void:
	var f := Assets.font("body_bold")
	var vp := get_viewport_rect().size
	var w := vp.x * 0.136
	var x := vp.x * 0.784
	var y := 128.0
	var fs := 21
	for it in _items:
		var a := clampf(it.t * 5.0, 0.0, 1.0) * clampf((LIFETIME - it.t) * 1.5, 0.0, 1.0)
		var col: Color = UITheme.sev_color(it.sev)
		var slide := (1.0 - clampf(it.t * 4.0, 0.0, 1.0)) * 40.0
		var pos := Vector2(x + slide, y)
		var h := f.get_multiline_string_size(it.text, HORIZONTAL_ALIGNMENT_LEFT, w, fs).y
		# Leuchtmarke vor der Meldung, dann Schrift mit dunklem Kontrastsaum und schwachem Halo
		var m := pos + Vector2(-12, -7)
		var chev := PackedVector2Array([m + Vector2(-6, -6), m, m + Vector2(-6, 6)])
		draw_polyline(chev, Color(col, a * 0.2), 6.0, true)
		draw_polyline(chev, Color(col.lightened(0.3), a), 2.0, true)
		draw_multiline_string_outline(f, pos, it.text, HORIZONTAL_ALIGNMENT_LEFT, w, fs, -1, 8, Color(0, 0, 0, a * 0.4))
		draw_multiline_string_outline(f, pos, it.text, HORIZONTAL_ALIGNMENT_LEFT, w, fs, -1, 5, Color(col, a * 0.16))
		draw_multiline_string(f, pos, it.text, HORIZONTAL_ALIGNMENT_LEFT, w, fs, -1, Color(col.lightened(0.3), a))
		y += h + 12.0
