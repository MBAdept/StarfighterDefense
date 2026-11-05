class_name TransitionOverlay
extends CanvasLayer
## Übergänge: Abblenden und Hyperraumsprung (Sternstreifen + Weißblitz).

var hyper: ColorRect
var black: ColorRect
var _tween: Tween          ## Hyperraumsprung
var _fade_tween: Tween     ## Abblenden
var _phase := 0.0          ## Streifenfortschritt (auf der CPU integriert, fotosicher – siehe hyperspace.gdshader)
var _intensity := 0.0


func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	hyper = ColorRect.new()
	hyper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hyper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/hyperspace.gdshader")
	hyper.material = m
	hyper.visible = false
	add_child(hyper)
	black = ColorRect.new()
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	black.color = Color(0, 0, 0, 0)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(black)


func _set_param(p: String, v: float) -> void:
	if p == "intensity":
		_intensity = v
	(hyper.material as ShaderMaterial).set_shader_parameter(p, v)


## Streifen laufen mit begrenztem Tempo weiter (vorher TIME × Tempo: nach langer Spielzeit sprangen sie
## von Bild zu Bild – ein Stroboskop).
func _process(delta: float) -> void:
	if hyper.visible:
		_phase += delta * (0.4 + 1.0 * _intensity)
		(hyper.material as ShaderMaterial).set_shader_parameter("phase", _phase)


## Laufenden Hyperraumsprung sofort beenden (Effekt ausblenden, Tween stoppen).
func cancel_hyperjump() -> void:
	if hyper.visible:
		if _tween:
			_tween.kill()
		hyper.visible = false
		_set_param("intensity", 0.0)
		_set_param("flash", 0.0)
		_set_param("fade", 0.0)


## Abblenden → mid() → Aufblenden
func fade(mid: Callable, out_time := 0.4, in_time := 0.5) -> void:
	# eigener Tween: ein Hyperraumsprung darf eine laufende Blende nicht abbrechen (sonst bliebe Schwarz stehen)
	if _fade_tween:
		_fade_tween.kill()
	black.mouse_filter = Control.MOUSE_FILTER_STOP
	_fade_tween = create_tween()
	_fade_tween.tween_property(black, "color:a", 1.0, out_time)
	_fade_tween.tween_callback(mid)
	_fade_tween.tween_interval(0.05)
	_fade_tween.tween_property(black, "color:a", 0.0, in_time)
	_fade_tween.tween_callback(func(): black.mouse_filter = Control.MOUSE_FILTER_IGNORE)


const TINT_NORMAL := Vector3(0.55, 0.8, 1.0)
const TINT_ENEMY := Vector3(1.0, 0.5, 0.4)   ## [Vorgabe] rötlicher Hyperraum zwischen den Systemen (fotosicher: kein gesättigtes Rot)
## [0.14.0] violett beim Sprung vom/ins zweite Feindsystem – Leuchtdichte wie TINT_ENEMY bzw. dessen Blende
const TINT_ENEMY2 := Vector3(0.72, 0.52, 1.0)
const FLASH_ENEMY := Vector3(1.0, 0.55, 0.45)
const FLASH_ENEMY2 := Vector3(0.74, 0.58, 1.0)


## Hyperraumsprung: Streifen beschleunigen, Weißblitz (Szenenwechsel), Ankunft.
## long = Sprung zwischen Helion- und einem Feindsystem: Config.enemy_jump_duration_factor × so lang, rot
## (second = vom/ins zweite Feindsystem: violett).
func hyperjump(mid: Callable, done: Callable = Callable(), long := false, second := false) -> void:
	if _tween:
		_tween.kill()
	var d := Config.jump_duration * (Config.enemy_jump_duration_factor if long else 1.0)
	_phase = 0.0
	var vp := get_viewport().get_visible_rect().size
	_set_param("aspect", vp.x / maxf(vp.y, 1.0))
	_set_param("intensity", 0.0)
	_set_param("flash", 0.0)
	_set_param("fade", 0.0)
	(hyper.material as ShaderMaterial).set_shader_parameter("tint", (TINT_ENEMY2 if second else TINT_ENEMY) if long else TINT_NORMAL)
	(hyper.material as ShaderMaterial).set_shader_parameter("flash_color", (FLASH_ENEMY2 if second else FLASH_ENEMY) if long else Vector3(1.0, 1.0, 1.0))
	hyper.visible = true
	if long:
		Audio.sfx("hyperjump_long" if Audio.has_sound("hyperjump_long") else "hyperjump", -1.0, 1.0 if Audio.has_sound("hyperjump_long") else 0.62)
	else:
		Audio.sfx("hyperjump", -1.0)
	var arrive := "hyperjump_arrive_long" if long and Audio.has_sound("hyperjump_arrive_long") else "hyperjump_arrive"
	_tween = create_tween()
	_tween.tween_method(func(v): _set_param("fade", v), 0.0, 1.0, d * 0.15)
	_tween.parallel().tween_method(func(v): _set_param("intensity", v), 0.0, 1.0, d * 0.62).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.tween_method(func(v): _set_param("flash", v), 0.0, 1.0, d * 0.12)
	_tween.tween_callback(mid)
	_tween.tween_callback(func(): Audio.sfx(arrive, -2.0, 1.0 if arrive != "hyperjump_arrive" or not long else 0.8))
	_tween.tween_interval(0.06)
	_tween.tween_method(func(v): _set_param("flash", v), 1.0, 0.0, d * 0.3)
	_tween.parallel().tween_method(func(v): _set_param("intensity", v), 0.7, 0.0, d * 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_method(func(v): _set_param("fade", v), 1.0, 0.0, d * 0.12)
	_tween.tween_callback(func():
		hyper.visible = false
		if done.is_valid():
			done.call()
	)
