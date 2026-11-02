class_name TransitionOverlay
extends CanvasLayer
## Übergänge: Abblenden und Hyperraumsprung (Sternstreifen + Weißblitz).

var hyper: ColorRect
var black: ColorRect
var _tween: Tween


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
	(hyper.material as ShaderMaterial).set_shader_parameter(p, v)


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
	if _tween:
		_tween.kill()
	black.mouse_filter = Control.MOUSE_FILTER_STOP
	_tween = create_tween()
	_tween.tween_property(black, "color:a", 1.0, out_time)
	_tween.tween_callback(mid)
	_tween.tween_interval(0.05)
	_tween.tween_property(black, "color:a", 0.0, in_time)
	_tween.tween_callback(func(): black.mouse_filter = Control.MOUSE_FILTER_IGNORE)


## Hyperraumsprung: Streifen beschleunigen, Weißblitz (Szenenwechsel), Ankunft.
func hyperjump(mid: Callable, done: Callable = Callable()) -> void:
	if _tween:
		_tween.kill()
	var d := Config.jump_duration
	var vp := get_viewport().get_visible_rect().size
	_set_param("aspect", vp.x / maxf(vp.y, 1.0))
	_set_param("intensity", 0.0)
	_set_param("flash", 0.0)
	_set_param("fade", 0.0)
	hyper.visible = true
	Audio.sfx("hyperjump", -1.0)
	_tween = create_tween()
	_tween.tween_method(func(v): _set_param("fade", v), 0.0, 1.0, d * 0.15)
	_tween.parallel().tween_method(func(v): _set_param("intensity", v), 0.0, 1.0, d * 0.62).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.tween_method(func(v): _set_param("flash", v), 0.0, 1.0, d * 0.12)
	_tween.tween_callback(mid)
	_tween.tween_callback(func(): Audio.sfx("hyperjump_arrive", -2.0))
	_tween.tween_interval(0.06)
	_tween.tween_method(func(v): _set_param("flash", v), 1.0, 0.0, d * 0.3)
	_tween.parallel().tween_method(func(v): _set_param("intensity", v), 0.7, 0.0, d * 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_method(func(v): _set_param("fade", v), 1.0, 0.0, d * 0.12)
	_tween.tween_callback(func():
		hyper.visible = false
		if done.is_valid():
			done.call()
	)
