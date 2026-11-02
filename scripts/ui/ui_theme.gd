class_name UITheme
extends RefCounted
## Gemeinsame Farbpalette und Godot-Theme (Retro-Futurismus: dunkle Glas-Paneele, Cyan-Akzente).

const CYAN := Color(0.32, 0.9, 1.0)
const CYAN_DIM := Color(0.18, 0.5, 0.62)
const AMBER := Color(1.0, 0.72, 0.22)
const RED := Color(1.0, 0.28, 0.22)
const GREEN := Color(0.45, 1.0, 0.55)
const PINK := Color(1.0, 0.36, 0.84)
const TEXT := Color(0.86, 0.94, 1.0)
const TEXT_DIM := Color(0.52, 0.63, 0.74)
const PANEL := Color(0.02, 0.05, 0.1, 0.82)
const DESTROYER_COLORS := [Color(0.25, 0.55, 1.0), Color(0.25, 1.0, 0.45), Color(1.0, 0.22, 0.18)]
const DESTROYER_NAMES := ["blau", "grün", "rot"]
const FIGHTER_COLOR := Color(1.0, 0.55, 0.15)


static var _theme: Theme


## Gemeinsames Theme (Controls unter CanvasLayern erben das Fenster-Theme nicht → explizit setzen).
static func get_theme() -> Theme:
	if _theme == null:
		_theme = build()
	return _theme


static func sev_color(sev: int) -> Color:
	match sev:
		GameState.Sev.GOOD:
			return GREEN
		GameState.Sev.WARN:
			return AMBER
		GameState.Sev.ALERT:
			return RED
	return CYAN


static func panel_style(border := CYAN_DIM, bg := PANEL, radius := 6, border_w := 2) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 22
	s.content_margin_right = 22
	s.content_margin_top = 16
	s.content_margin_bottom = 16
	s.anti_aliasing = true
	return s


static func build() -> Theme:
	var t := Theme.new()
	t.default_font = Assets.font("body")
	t.default_font_size = 26

	var btn_normal := panel_style(Color(CYAN_DIM, 0.55), Color(0.03, 0.08, 0.14, 0.72), 4, 2)
	btn_normal.content_margin_left = 28
	btn_normal.content_margin_right = 28
	btn_normal.content_margin_top = 10
	btn_normal.content_margin_bottom = 10
	var btn_hover := btn_normal.duplicate() as StyleBoxFlat
	btn_hover.bg_color = Color(0.06, 0.18, 0.26, 0.85)
	btn_hover.border_color = CYAN
	btn_hover.shadow_color = Color(CYAN, 0.35)
	btn_hover.shadow_size = 10
	var btn_pressed := btn_hover.duplicate() as StyleBoxFlat
	btn_pressed.bg_color = Color(0.1, 0.35, 0.45, 0.95)
	var btn_disabled := btn_normal.duplicate() as StyleBoxFlat
	btn_disabled.border_color = Color(0.3, 0.35, 0.4, 0.4)
	btn_disabled.bg_color = Color(0.03, 0.05, 0.07, 0.5)
	for type in ["Button", "OptionButton", "CheckButton"]:
		t.set_stylebox("normal", type, btn_normal)
		t.set_stylebox("hover", type, btn_hover)
		t.set_stylebox("pressed", type, btn_pressed)
		t.set_stylebox("focus", type, btn_hover)
		t.set_stylebox("hover_pressed", type, btn_pressed)
		t.set_stylebox("disabled", type, btn_disabled)
		t.set_font("font", type, Assets.font("display_med"))
		t.set_font_size("font_size", type, 24)
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, Color(1, 1, 1))
		t.set_color("font_focus_color", type, Color(1, 1, 1))
		t.set_color("font_pressed_color", type, Color(1, 1, 1))
		t.set_color("font_disabled_color", type, TEXT_DIM)

	t.set_stylebox("panel", "Panel", panel_style())
	t.set_stylebox("panel", "PanelContainer", panel_style())
	t.set_color("font_color", "Label", TEXT)
	t.set_font("font", "Label", Assets.font("body"))
	t.set_font_size("font_size", "Label", 26)

	var line := StyleBoxFlat.new()
	line.bg_color = Color(0.1, 0.2, 0.28, 0.9)
	line.set_corner_radius_all(3)
	line.content_margin_top = 4
	line.content_margin_bottom = 4
	var fill := line.duplicate() as StyleBoxFlat
	fill.bg_color = CYAN
	t.set_stylebox("slider", "HSlider", line)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	var grab := GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1))
	g.set_color(1, Color(0.6, 0.95, 1.0))
	grab.gradient = g
	grab.width = 22
	grab.height = 22
	grab.fill = GradientTexture2D.FILL_RADIAL
	grab.fill_from = Vector2(0.5, 0.5)
	grab.fill_to = Vector2(0.5, 0.0)
	t.set_icon("grabber", "HSlider", grab)
	t.set_icon("grabber_highlight", "HSlider", grab)

	var le := panel_style(CYAN, Color(0.02, 0.06, 0.1, 0.9), 4, 2)
	le.content_margin_top = 8
	le.content_margin_bottom = 8
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("focus", "LineEdit", le)
	t.set_font("font", "LineEdit", Assets.font("display"))
	t.set_font_size("font_size", "LineEdit", 34)
	t.set_color("font_color", "LineEdit", Color(1, 1, 1))
	t.set_color("caret_color", "LineEdit", CYAN)

	var tip := panel_style(CYAN_DIM, Color(0.02, 0.05, 0.1, 0.95), 4, 1)
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_stylebox("panel", "PopupMenu", tip)
	t.set_font("font", "PopupMenu", Assets.font("body"))
	t.set_font_size("font_size", "PopupMenu", 24)
	return t


## Großer Titel-Label mit Schatten/Glow.
## "1 Stadt" / "n Städte"
static func cities_text(n: int) -> String:
	return "%d Stadt" % n if n == 1 else "%d Städte" % n


static func title_label(text: String, size := 72, color := CYAN) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", Assets.font("title"))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color.lightened(0.35))
	l.add_theme_color_override("font_shadow_color", Color(color, 0.55))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 0)
	l.add_theme_constant_override("shadow_outline_size", 18)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


static func label(text: String, size := 26, color := TEXT, font_name := "body") -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", Assets.font(font_name))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(func():
		Audio.ui("ui_select")
		cb.call()
	)
	b.focus_entered.connect(func(): Audio.ui("ui_move"))
	b.mouse_entered.connect(func(): b.grab_focus())
	return b
