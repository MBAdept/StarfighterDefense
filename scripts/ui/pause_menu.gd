class_name PauseMenu
extends Control
## Pausemenü (Esc / Start).

signal closed

var _box: VBoxContainer
var _center: CenterContainer
var _sub: Control = null
var _quit_btn: Button
var _quit_armed := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.get_theme()
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := ColorRect.new()
	dim.color = Color(0, 0.01, 0.03, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_center = CenterContainer.new()
	_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 0)
	_center.add_child(panel)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 16)
	panel.add_child(_box)
	_box.add_child(UITheme.title_label("PAUSE", 54))
	_box.add_child(UITheme.button("WEITER", _resume))
	_box.add_child(UITheme.button("OPTIONEN", func(): _open_sub(OptionsMenu.new(), 2)))
	_box.add_child(UITheme.button("STEUERUNG", func(): _open_sub(ControlsHelp.new(), 3)))
	# [Vorgabe] vorzeitiger Abbruch führt zur Auswertung (Sicherheitsabfrage: zweimal bestätigen)
	_quit_btn = UITheme.button("SPIEL BEENDEN", _to_title)
	_box.add_child(_quit_btn)
	Audio.ui("map_open", -6.0)
	await get_tree().process_frame
	_box.get_child(1).grab_focus()


## from_idx: Knopf in _box, der die Unterseite geöffnet hat (bekommt danach wieder den Fokus).
func _open_sub(c: Control, from_idx: int) -> void:
	_sub = c
	# [0.14.3] Pause-Knöpfe ausblenden, solange Optionen/Steuerung offen sind: Sonst führten Steuerkreuz und Stick
	# (und Pfeiltasten) auf die verdeckten Knöpfe – zweimal A auf „SPIEL BEENDEN“ brach die Partie unbemerkt ab.
	_center.visible = false
	add_child(c)
	c.closed.connect(func():
		_sub = null
		_center.visible = true
		(_box.get_child(from_idx) as Control).grab_focus()
	)


func _resume() -> void:
	closed.emit()
	queue_free()


func _to_title() -> void:
	if not _quit_armed:
		_quit_armed = true
		_quit_btn.text = "WIRKLICH BEENDEN? (AUSWERTUNG)"
		var tw := create_tween()
		tw.tween_interval(4.0)
		tw.tween_callback(func():
			_quit_armed = false
			if is_instance_valid(_quit_btn):
				_quit_btn.text = "SPIEL BEENDEN"
		)
		return
	closed.emit()
	queue_free()
	Main.instance.abort_game()


func _unhandled_input(event: InputEvent) -> void:
	if _sub:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		Audio.ui("ui_back")
		_resume()
		get_viewport().set_input_as_handled()
