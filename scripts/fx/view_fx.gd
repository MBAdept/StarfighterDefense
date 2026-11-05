class_name ViewFX
extends Control
## =============================================================================================
##  Sichtstörung (Systemschaden "Sichtsystem", 0.12.0 [Vorgabe]): Nur die Außensicht ist gestört –
##  Cockpit und HUD bleiben klar. Die Welt hinter den Scheiben schwankt leicht; alle 2,5–5 s kommt ein
##  Störungsstoß von 0,3 s (feiner Schnee oder weiche grüne Streifen, Zeilen leicht versetzt).
##  Fotosicher: kein Aufblitzen, mittlere Helligkeit bleibt, weiche Hüllkurven, höchstens 0,4 Stöße pro
##  Sekunde, langsame Bewegungen. Schwanken und Zeilenversatz folgen der Option "Bildschirmwackeln".
##  Gezeichnet wird auf einer eigenen Ebene zwischen 3D-Szene und HUD, beschränkt auf die Scheibenflächen:
##  Bildbereich über der Blendschutzkante ohne Kanzelrahmen, Mittelpult und Rahmen des Combiner-Glases –
##  Zwei Lagen mit demselben Shader und derselben Bildkopie: der Randstreifen bis 2,5 px an die Cockpitkanten zeigt
##  nur Schnee/Streifen (ohne Verschiebung), die um die größte Verschiebung verkleinerte Innenfläche zusätzlich das
##  Schwanken – so wackelt keine Cockpitkante mit und es entsteht kein Geisterbild, der Schnee reicht aber bis an
##  die Kanten.
##  In der Pause und bei offener Karte ruht die Störung (die Shader-Zeit liefe sonst weiter).
## =============================================================================================

var combat: CombatBase
var forced := false            ## Tests: Störung ohne Schaden zeigen
var _mat: ShaderMaterial
var _rng := RandomNumberGenerator.new()
var _t := 0.0
var _next := 0.5               ## Sekunden bis zum nächsten Stoß
var _burst_t := -1.0           ## < 0: kein Stoß
var _polys: Array = []         ## Scheibenflächen (Randstreifen-Lage: nur Schnee/Streifen), Bildschirmkoordinaten
var _inner_polys: Array = []   ## Innenflächen (um die größte Verschiebung verkleinert): volle Störung
var _mat_band: ShaderMaterial
var _inner: Control
var bursts := 0                ## Zähler (Tests)
var test_burst_at := -1.0      ## Tests: Stoß nach so vielen Sekunden Störung erzwingen
var test_kind := -1            ## Tests: 0 = Schnee, 1 = grüne Streifen
var test_hold := false         ## Tests (Standbilder): Stoß dauerhaft auf voller Stärke
const TEAR_PX := 2.0           ## Zeilenversatz im Stoß (Bildpunkte bei 1080p, × Bildschirmwackeln)
## Beginn des letzten Stoßes (Echtzeit, ms) – über alle Szenen hinweg: jede Kampfszene hat ihre eigene ViewFX, nach
## einem Sprung gilt der Mindestabstand trotzdem (fotosicher: höchstens ein Stoß je damage_screen_burst_min).
static var _last_burst_ms := -1000000
const EDGE_PX := 2.5           ## Abstand der Randstreifen-Lage zu den Cockpitkanten (Ungenauigkeit der Umrisse)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh: Shader = load("res://shaders/view_fx.gdshader")
	_mat_band = ShaderMaterial.new()
	_mat_band.shader = sh
	material = _mat_band
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_inner = Control.new()
	_inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inner.material = _mat
	_inner.draw.connect(func():
		for p in _inner_polys:
			_inner.draw_colored_polygon(p, Color.WHITE))
	add_child(_inner)
	_rng.randomize()
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS   # auch in der Pause: dort ausblenden statt einfrieren


func is_active() -> bool:
	return (forced or GameState.damage == "screen") and combat != null and not combat.frozen and not get_tree().paused


func _process(delta: float) -> void:
	if not (forced or GameState.damage == "screen"):
		visible = false
		_burst_t = -1.0
		_next = 0.5   # der erste Stoß kommt kurz nach einem neuen Schaden
		return
	if not is_active():
		# Pause oder Karte: nichts zeigen. Ein laufender Stoß endet; der nächste kommt frühestens nach dem
		# üblichen Abstand – so bleibt es auch bei häufigem Pausieren bei höchstens einem Stoß je 2,5 s.
		visible = false
		if _burst_t >= 0.0:
			_burst_t = -1.0
			_next = Config.damage_screen_burst_min
		return
	visible = true
	_t += delta
	var dur := Config.damage_screen_burst_time
	if _burst_t >= 0.0:
		_burst_t += delta
		if _burst_t >= dur:
			_burst_t = -1.0
			_next = _rng.randf_range(Config.damage_screen_burst_min, Config.damage_screen_burst_max)
	else:
		_next -= delta
		if test_burst_at >= 0.0:
			_next = 1.0 if _t < test_burst_at else 0.0
			if _t >= test_burst_at:
				test_burst_at = -1.0
		if _next <= 0.0 and Time.get_ticks_msec() - _last_burst_ms < int(Config.damage_screen_burst_min * 1000.0) and test_burst_at < 0.0 and not test_hold:
			_next = float(int(Config.damage_screen_burst_min * 1000.0) - (Time.get_ticks_msec() - _last_burst_ms)) / 1000.0
		if _next <= 0.0:
			_burst_t = 0.0
			bursts += 1
			_last_burst_ms = Time.get_ticks_msec()
			var kind := (0.0 if _rng.randf() < 0.5 else 1.0) if test_kind < 0 else float(test_kind)
			var seed := _rng.randf() * 50.0
			for m in [_mat, _mat_band]:
				m.set_shader_parameter("kind", kind)
				m.set_shader_parameter("seed", seed)
			if Audio.has_sound("view_static"):
				Audio.sfx("view_static", -6.0, _rng.randf_range(0.92, 1.08))
	# weiche Hüllkurve: 60 ms ein, 120 ms aus (kein hartes An/Aus)
	var env := 0.0
	if _burst_t >= 0.0:
		env = smoothstep(0.0, 0.06, _burst_t) * (1.0 - smoothstep(dur - 0.12, dur, _burst_t))
	if test_hold:
		env = 1.0
		for m in [_mat, _mat_band]:
			m.set_shader_parameter("kind", float(maxi(test_kind, 0)))
	# Schwanken: Summe langsamer Sinusschwingungen (0,4–1,1 Hz), im Stoß etwas stärker
	var motion := clampf(Config.screen_shake, 0.0, 1.5)
	var px := Config.damage_screen_wobble * motion * (1.0 + env * 0.5)
	var tear_px := TEAR_PX * motion
	var wob := Vector2(sin(_t * TAU * 0.55) * 0.6 + sin(_t * TAU * 1.1 + 1.3) * 0.4,
		sin(_t * TAU * 0.43 + 0.7) * 0.5 + sin(_t * TAU * 0.9 + 2.1) * 0.5) * px
	var sz := size if size.x > 0.0 else Vector2(1920, 1080)
	_mat.set_shader_parameter("offset", wob / sz)
	_mat.set_shader_parameter("tear", tear_px / sz.x)
	var grain := maxf(2.0 * float(get_window().size.y) / 1080.0, 1.0)   # echte Bildpunkte
	for m in [_mat, _mat_band]:
		m.set_shader_parameter("burst", env)
		m.set_shader_parameter("grain", grain)
	# Randstreifen-Lage: ohne Verschiebung (offset/tear bleiben 0)
	# größte mögliche Verschiebung eines Bildpunkts (Schwanken im Stoß, diagonal, plus Zeilenversatz) + 1 px
	var margin := Config.damage_screen_wobble * motion * 1.5 * 1.415 + tear_px + 1.0
	_update_polys(sz, margin)
	queue_redraw()
	_inner.queue_redraw()


func _draw() -> void:
	for p in _polys:
		draw_colored_polygon(p, Color.WHITE)


# ---------------------------------------------------------------------------------------------
#  Scheibenflächen
# ---------------------------------------------------------------------------------------------
func _update_polys(sz: Vector2, margin: float) -> void:
	var full := PackedVector2Array([Vector2(-8, -8), Vector2(sz.x + 8, -8), Vector2(sz.x + 8, sz.y + 8), Vector2(-8, sz.y + 8)])
	var rig: CockpitRig = null
	if combat and combat.hud is CockpitHUD:
		rig = (combat.hud as CockpitHUD).rig
	if rig == null or not is_instance_valid(rig) or rig.lip_points.size() < 2 or rig.glass_corners.size() < 4:
		_polys = []
		_inner_polys = [full]   # klassische Ansicht: die ganze 3D-Sicht ist Außensicht (am Bildrand wird geklemmt)
		return
	# Bereich über der Blendschutzkante (folgt dem nachfedernden Cockpit)
	var lip := rig.project_quad(rig.lip_points)
	var d := lip[1] - lip[0]
	if absf(d.x) < 1.0:
		_polys = []
		_inner_polys = []
		return
	var k := d.y / d.x
	var e := margin + 8.0   # über den Bildrand hinaus, damit das Verkleinern dort keinen Streifen frei lässt
	var yl := lip[0].y + (-e - lip[0].x) * k
	var yr := lip[0].y + (sz.x + e - lip[0].x) * k
	var polys: Array = [PackedVector2Array([Vector2(-e, -e), Vector2(sz.x + e, -e), Vector2(sz.x + e, yr), Vector2(-e, yl)])]
	# Cockpitteile davor ausschneiden: Kanzelrahmen, Mittelpult, Rahmen und Füße des Combiner-Glases
	for cut in rig.view_cutouts():
		var pts := rig.project_quad(cut.pts)
		if cut.hull:
			var hull := Geometry2D.convex_hull(pts)
			var grown := Geometry2D.offset_polygon(hull, 3.0)
			pts = grown[0] if not grown.is_empty() else hull
		polys = _subtract(polys, pts)
	# Randstreifen-Lage knapp an den Kanten, Innenfläche um die größte Verschiebung verkleinert: dort holt sich
	# der Shader nie Bildpunkte vom Cockpit
	_polys = _shrink(polys, EDGE_PX)
	_inner_polys = _shrink(polys, maxf(margin, EDGE_PX))


func _shrink(polys: Array, by: float) -> Array:
	var out := []
	for p in polys:
		for q in Geometry2D.offset_polygon(p, -by):
			if q.size() >= 3 and not Geometry2D.is_polygon_clockwise(q) and not Geometry2D.triangulate_polygon(q).is_empty():
				out.append(q)
	return out


## Polygon(e) minus Ausschnitt. Entstünde ein Loch (Ausschnitt ganz innen), bleibt das Polygon unverändert –
## lieber ein Stück Cockpit mitgestört als eine falsch gefüllte Fläche.
func _subtract(polys: Array, cut: PackedVector2Array) -> Array:
	var out := []
	for p in polys:
		var res := Geometry2D.clip_polygons(p, cut)
		var hole := false
		for r in res:
			if Geometry2D.is_polygon_clockwise(r):
				hole = true
		if hole:
			out.append(p)
		else:
			out.append_array(res)
	return out
