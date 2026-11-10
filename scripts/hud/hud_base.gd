class_name HudBase
extends Control
## =============================================================================================
##  Gemeinsame Grundlage der Kampf-HUDs: Schnittstelle für CombatBase und Szenen (Meldungen,
##  Punkte-Popups, Trefferrückmeldung, Waffenwechsel) und die Zeitgeber dafür.
##   - CockpitHUD: Cockpit mit Kampfjet-Head-Up-Display (Standard, Optionen: "Cockpit-Ansicht")
##   - ClassicHUD: die bisherige flache Anzeige
## =============================================================================================

var combat: CombatBase
var shake_offset := Vector2.ZERO   ## Bildschirmwackeln (von CombatBase gesetzt)
var _msgs: Array = []
var _small: Array = []
var _popups: Array = []
var _t := 0.0
var _energy_shown := 100.0
var _hit_t := 10.0
var _hit_heavy := false
var _pending_heavy := false   ## schwerer Treffer im Mindestabstand: Rückmeldung zum nächsten erlaubten Zeitpunkt
var _weapon_t := 10.0
var _f_title: Font
var _f_disp: Font
var _f_body: Font
var _f_mono: Font


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_f_title = Assets.font("title")
	_f_disp = Assets.font("display")
	_f_body = Assets.font("body_bold")
	_f_mono = Assets.font("mono")
	_energy_shown = GameState.energy


func _process(delta: float) -> void:
	_t += delta
	_hit_t += delta
	if _pending_heavy and _hit_t >= Config.hit_flash_min_gap:
		_start_hit_cue(true)
	_weapon_t += delta
	for m in _msgs:
		m.t += delta
	_msgs = _msgs.filter(func(m): return m.t < m.dur)
	for m in _small:
		m.t += delta
	_small = _small.filter(func(m): return m.t < m.dur)
	for p in _popups:
		p.t += delta
	_popups = _popups.filter(func(p): return p.t < 1.4)
	_energy_shown = lerpf(_energy_shown, GameState.energy, 1.0 - exp(-6.0 * delta))
	_update(delta)


## Von den HUDs überschrieben: Neuzeichnen anstoßen usw.
func _update(_delta: float) -> void:
	queue_redraw()


# ---------------------------------------------------------------------------------------------
#  Schnittstelle
# ---------------------------------------------------------------------------------------------
func show_message(title: String, sub := "", dur := 2.0, color := UITheme.CYAN, small := false) -> void:
	var m := {"title": title, "sub": sub, "t": 0.0, "dur": dur, "color": color}
	if small:
		_small = [m]
	else:
		_msgs = [m]


func add_popup(world: Vector3, text: String, color: Color) -> void:
	_popups.append({"w": world, "text": text, "color": color, "t": 0.0})


## Trefferrückmeldung (rote Kante, Projektor-Abdunkeln, Cockpitlicht). Fotosicher: höchstens alle
## Config.hit_flash_min_gap Sekunden neu ausgelöst (≤ 2 pro Sekunde). Ein schwerer Treffer kurz nach einem leichten
## wird zum nächsten erlaubten Zeitpunkt nachgeholt; einer kurz nach einem schweren geht in dessen (länger
## leuchtender) Rückmeldung auf. Der Farbblitz der Nachbearbeitung hat einen eigenen Takt (CombatBase).
## Gibt true zurück, wenn die Rückmeldung jetzt startet.
func on_player_hit(heavy: bool, _dmg: float) -> bool:
	if _hit_t < Config.hit_flash_min_gap:
		if heavy and not _hit_heavy:
			_pending_heavy = true
		return false
	_start_hit_cue(heavy)
	return true


func _start_hit_cue(heavy: bool) -> void:
	_hit_t = 0.0
	_hit_heavy = heavy
	_pending_heavy = false
	_on_hit_cue(heavy)


## Nachgeholte schwere Rückmeldung verwerfen (Karte, Pause, Untergang – sonst „Phantomtreffer“).
func clear_pending_hit() -> void:
	_pending_heavy = false


## Von CockpitHUD überschrieben: Cockpitlicht und Lampe TREFFER folgen derselben Rückmeldung.
func _on_hit_cue(_heavy: bool) -> void:
	pass


## Kurzzeile für einen aktiven Systemschaden ("" = keiner).
func _damage_line() -> String:
	if GameState.damage == "":
		return ""
	match GameState.damage:
		"bombs":
			return "SCHADEN: BOMBENSCHACHT KLEMMT"
		"screen":
			return "SCHADEN: SICHTSYSTEM GESTÖRT"
		"comms":
			return "SCHADEN: KOMMUNIKATION GESTÖRT"
	return "SCHADEN: " + GameState.damage_name()


func on_weapon_changed() -> void:
	_weapon_t = 0.0


# ---------------------------------------------------------------------------------------------
#  Gemeinsame Hilfen
# ---------------------------------------------------------------------------------------------
func _project(w: Vector3) -> Dictionary:
	var cam := combat.camera
	if cam.is_position_behind(w):
		return {"front": false, "pos": Vector2.ZERO}
	return {"front": true, "pos": cam.unproject_position(w)}


func _energy_color() -> Color:
	var e := GameState.energy
	if e < Config.energy_low_warning:
		return UITheme.RED
	if e < 50.0:
		return UITheme.AMBER
	return UITheme.GREEN


## Lage-Zeilen [Bezeichnung, Wert, Farbe, (Zerstörerfarben)] für die aktuelle Kampfszene.
func _lage_lines() -> Array:
	var fl := false
	for e in combat.enemies:
		if is_instance_valid(e) and e.alive and e.kind == Enemy.Kind.FLAGSHIP:
			fl = true
	if not Config.combat_intel:
		return _lage_lines_reduced(fl)
	var lines := []
	if combat is SpaceCombat:
		var sc: SpaceCombat = combat
		if (sc.mode == SpaceCombat.Mode.ORBIT and not sc.orbit_done) or (sc.mode == SpaceCombat.Mode.RECEPTION and sc.phase == SpaceCombat.Phase.FIGHTERS):
			lines.append(["FIGHTER", "%d / %d" % [sc.orbit_total - sc.orbit_killed, sc.orbit_total], UITheme.FIGHTER_COLOR])
		elif sc.squadron and sc.squadron.state != SquadronData.State.DESTROYED and not sc.is_docking():
			lines.append(["FIGHTER", "%d" % sc.squadron.fighters, UITheme.FIGHTER_COLOR])
			if sc.mode == SpaceCombat.Mode.SQUADRON:
				lines.append(["ZERSTÖRER", str(sc.squadron.destroyers.size()), UITheme.AMBER, sc.squadron.destroyer_colors()])
		if fl:
			lines.append(["FLAGGSCHIFF", "AKTIV", UITheme.PINK])
	elif combat is PlanetCombat and (combat as PlanetCombat).enemy_mode:
		var ep: PlanetCombat = combat
		lines.append(["FEINDSTÄDTE", "%d / %d" % [ep.planet.alive_cities(), ep.planet.cities.size()], Color(1.0, 0.4, 0.62)])
		var rf := ep.reinforcements_alive()
		if rf > 0:
			lines.append(["VERSTÄRKUNG", "%d" % rf, UITheme.FIGHTER_COLOR])   # nur bei 0 Verteidigern: ersetzt die Zeile
		else:
			lines.append(["VERTEIDIGER", "%d" % ep.planet.defenders, UITheme.FIGHTER_COLOR if ep.planet.defenders > 0 else UITheme.GREEN])
		lines.append(["BOMBEN", "%d / %d" % [GameState.bombs, Config.bombs_max], UITheme.AMBER if GameState.bombs > 0 else UITheme.RED])
	elif combat is PlanetCombat:
		var pc: PlanetCombat = combat
		lines.append(["STÄDTE", "%d / %d" % [pc.planet.alive_cities(), pc.planet.cities.size()], UITheme.CYAN])
		if pc.squadron and pc.squadron.state != SquadronData.State.DESTROYED:
			lines.append(["FIGHTER", "%d" % pc.squadron.fighters, UITheme.FIGHTER_COLOR])
			lines.append(["ZERSTÖRER", str(pc.squadron.destroyers.size()), UITheme.AMBER, pc.squadron.destroyer_colors()])
	if lines.is_empty():
		lines.append(["KONTAKTE", "KEINE", UITheme.GREEN])
	return lines


## [Vorgabe 0.14.4] ab Normal: Lage ohne Stärke des Gegners (keine Anzahl, keine Zerstörerfarben) – die steht nur
## auf der Übersichtskarte. Eigene Werte (Städte, Bomben) bleiben.
func _lage_lines_reduced(flagship_present: bool) -> Array:
	var lines := []
	var contact := flagship_present
	if combat is SpaceCombat:
		var sc: SpaceCombat = combat
		if (sc.mode == SpaceCombat.Mode.ORBIT and not sc.orbit_done) or (sc.mode == SpaceCombat.Mode.RECEPTION and sc.phase == SpaceCombat.Phase.FIGHTERS):
			contact = true
		elif sc.squadron and sc.squadron.state != SquadronData.State.DESTROYED and not sc.is_docking():
			contact = true
	elif combat is PlanetCombat and (combat as PlanetCombat).enemy_mode:
		var ep: PlanetCombat = combat
		lines.append(["FEINDSTÄDTE", "%d / %d" % [ep.planet.alive_cities(), ep.planet.cities.size()], Color(1.0, 0.4, 0.62)])
		var active := ep.planet.defenders > 0 or ep.reinforcements_alive() > 0
		lines.append(["VERTEIDIGER", "AKTIV" if active else "AUS", UITheme.FIGHTER_COLOR if active else UITheme.GREEN])
		lines.append(["BOMBEN", "%d / %d" % [GameState.bombs, Config.bombs_max], UITheme.AMBER if GameState.bombs > 0 else UITheme.RED])
		return lines
	elif combat is PlanetCombat:
		var pc: PlanetCombat = combat
		lines.append(["STÄDTE", "%d / %d" % [pc.planet.alive_cities(), pc.planet.cities.size()], UITheme.CYAN])
		if pc.squadron and pc.squadron.state != SquadronData.State.DESTROYED:
			contact = true
	if contact:
		lines.append(["KONTAKT", "FEIND", UITheme.RED])
	if lines.is_empty():
		lines.append(["KONTAKTE", "KEINE", UITheme.GREEN])
	return lines


## [Vorgabe 0.14.4] HUD-Farbe eines Gegners für Zielmarke, Randpfeile und Punkte-Popup: ab Normal ohne
## Zerstörerfarbe (die Farbe sieht man am Schiff selbst) und ohne Rosa für das Flaggschiff – neutral bernstein.
static func intel_color(e: Enemy) -> Color:
	if Config.combat_intel or e.kind == Enemy.Kind.FIGHTER:
		return e.hud_color
	return UITheme.AMBER
