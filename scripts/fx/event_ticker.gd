class_name EventTicker
extends Control
## Meldungen der strategischen Ebene (Angriffe, Landungen, zerstörte Städte …) – auch im Kampf.

const LIFETIME := 6.5
var _items: Array = []   # [{text, sev, t}]
var _cue_t := 0.0        ## Abklingzeit des Hinweistons (Config.ticker_alert_cooldown)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	GameState.event_logged.connect(_on_event)
	GameState.alert_raised.connect(_on_alert)
	# [Spielbeschreibung §12] Alarm bei Angriff auf eine Station – endet nach Config.alarm_duration
	GameState.squadron_at_station.connect(func(_sq, _st): Audio.alarm(0.0))


func _on_event(text: String, sev: int) -> void:
	push(text, sev)


## Hinweiston für Warnmeldungen aus dem System. Der Geschoss-Warnton ("incoming") bleibt echten
## Geschossen vorbehalten; Ereignisse am aktuellen Ort vertont die Szene selbst.
func _on_alert(kind: String, ref: int) -> void:
	if kind == "station_attack":
		return   # dafür gibt es den (zeitlich begrenzten) Alarm
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
	queue_redraw()


func _draw() -> void:
	if Main.instance and Main.instance.is_map_open():
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
