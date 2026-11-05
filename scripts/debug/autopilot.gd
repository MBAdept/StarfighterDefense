class_name AutoPilot
extends Node
## Testfahrer (nur für automatisierte Tests, Start mit "-- --autoplay"):
## zielt, schießt, springt über die Karte, tankt – protokolliert den Ablauf in der Konsole.
##
##   --autoplay             perfekter Schütze: setzt die Blickrichtung direkt, voller Vorhalt
##   --autoplay --human     durchschnittlicher Mensch (Abschnitt "Mensch"): lenkt über die normalen
##                          Steueraktionen wie Tastatur/Gamepad (höchstens ~70 % der Drehrate, geglättet),
##                          Reaktionszeit beim Zielwechsel, langsam wandernder Zielfehler, feuert nur nahe am
##                          (fehlerhaften) Zielpunkt, gelegentlich verfrühte Ionen-Schüsse, ungenaues
##                          Flaggschiff-Timing, weicht einem Teil der schweren Geschosse aus, bricht bei
##                          kritischer Energie (< h_flee) den Kampf zum Tanken ab und gibt ein Flaggschiff nach
##                          Vernichtung seines Schwadrons nach h_flag_linger Sekunden auf. Kartenlogik wie oben.
##                          Feineinstellung: --h_<name>=<wert> (Variablen h_* unten), z. B. --h_evade=0 --h_flee=0
##   --autoplay --passive   nur die Strategie-Simulation beobachten (kein Kampf, keine Sprünge)
##   --raid                 zusätzlich Angriffe auf das Feindsystem: mit voller Energie und Bomben hinspringen,
##                          Empfangskomitee abwehren, Städte bombardieren, zum Nachladen zurück (--raid_target=
##                          auto|home|outer, --raid_energy=80, --raid_return=35). Protokoll: RAID_* / ENEMY_SUMMARY
##   --raid_safe            "Verteidigung zuerst" (Ziel: Sieg ohne verlorene Stadt): angreifen nur, wenn die nächste
##                          Landung in Helion mehr als --safe_eta=150 s entfernt ist; im Feindsystem sofort zurück,
##                          sobald eine Landung näher als --safe_return_eta=70 s rückt (auch mitten im Kampf);
##                          zu Hause zuerst das dringendste Schwadron. --raid_intercept: im Feindsystem zusätzlich
##                          startende Schwadrone abfangen, bevor sie nach Helion springen.
##
## Energie-Buchhaltung (in allen Modi): Sprungkosten und erlittene Treffer werden dem Schwadron
## zugeordnet, gegen das gerade gekämpft wird. Ausgaben (Schlüssel=Wert, für Auswertungsskripte):
##   SQUAD_COST name=… cost=… fighters_killed=… destroyers=… …   sobald ein Schwadron vernichtet ist
##   SQUAD_EXTRA …  Energieverlust nach der Vernichtung (Flaggschiff bis zu seinem Rückzug)
##   ORBIT_COST …   Orbit-Kampf zu Spielbeginn
##   REFUEL_TRIP …  Sprung zur Station, um zu tanken
##   OPEN_SQUAD …   beim Beenden: angegriffene, aber noch nicht vernichtete Schwadrone
##   RUN_SUMMARY …  beim Beenden: Durchschnitt/Maximum je Schwadron, Schaden nach Quelle, Game Over
## Felder: cost = Energie in %, dmg_* = Treffer nach Quelle, hits_x=Treffer/Schüsse des Gegners,
## nearmiss/blocked = feindliche Schüsse knapp vorbei / vom eigenen Schuss abgefangen (Fighter,Zerstörer,Flaggschiff),
## laser=vernichtete Fighter/Laserschüsse, ion=Treffer auf Zerstörer+Flaggschiff/Ionen-Schüsse

var _t := 0.0
var _clock := 0.0          ## fortlaufende Zeit (s)
var _sq_done_clock := -1000.0   ## _clock bei der letzten Schwadron-Vernichtung
var _decide_t := 0.0
var _fire_hold := false
var _fire_weapon := -1
var _steer_active := false
var _log_t := 0.0
var skill := 0.85
var passive := false   ## nur Strategie-Simulation beobachten (kein Kampf, keine Sprünge)
var human := false     ## menschenähnlicher Testfahrer (Testargument --human)
# --- Feindsystem (--raid) ---
var raid := false
var raid_target := "auto"   ## auto: äußere Planeten zuerst; die Heimatwelt, sobald die Bomben für ihre restlichen Städte reichen
var raid_energy := 80.0     ## Mindestenergie für den Sprung ins Feindsystem
var raid_return := 35.0     ## darunter (oder ohne Bomben) zurück nach Helion
var _bomb_city := -1
var _bomb_lock_t := 0.0
var _bomb_delay := 0.0
var _bomb_backing := false     ## zu nah an der Zielstadt: zurücksetzen, bis genug Anlauf da ist
var _bomb_city_t := 0.0        ## Zeit am aktuellen Ziel ohne Abwurf (danach anderes Ziel)
var _bomb_skip := -1           ## zuletzt aufgegebenes Ziel
var _switch_t := 0.0
var _raids := 0
var raid_safe := false
var raid_intercept := false
var safe_eta := 150.0        ## s – Mindestvorlauf bis zur nächsten Landung in Helion, um einen Angriff zu beginnen
var safe_return_eta := 70.0  ## s – im Feindsystem: Rückkehr, sobald eine Landung in Helion näher rückt
var _safe_check_t := 0.0
var _defend_returns := 0
var _intercepts := 0
var _raid := Acct.new()       ## Energieverlust im Feindsystem (Empfangskomitee, Feindplaneten, Langsprünge)

# ---------------------------------------------------------------------------------------------
#  Mensch: Parameter (überschreibbar mit Testargument --h_<name>=<wert>)
# ---------------------------------------------------------------------------------------------
var h_reaction := 0.35     ## s – Reaktionszeit bei Zielwechsel (je Wechsel ±30 % gestreut)
var h_rate_frac := 0.7     ## Anteil der max. Drehrate beim Nachführen
var h_err_min := 1.5       ## Grad – Betrag des langsam wandernden Zielfehlers liegt zwischen min …
var h_err_max := 3.0       ## … und max
var h_err_t_min := 0.4     ## s – neuer Zielfehler alle h_err_t_min … h_err_t_max Sekunden
var h_err_t_max := 0.8
var h_lead_min := 0.4      ## Vorhalt als Anteil des nötigen Vorhalts (je Ziel gewürfelt)
var h_lead_max := 1.0
var h_laser_tol := 2.5     ## Grad – Laser nur, wenn das Fadenkreuz so nah am (fehlerhaften) Zielpunkt ist
var h_ion_tol := 1.5       ## Grad – Ionen-Kanone ebenso …
var h_ion_early := 0.2     ## … außer bei verfrühten Schüssen (Anteil der Ionen-Schüsse, dann 2–4 × h_ion_tol)
var h_flag_jitter := 0.6   ## s – Timingfehler beim Flaggschiff (±, gleichverteilt je Ladezyklus)
var h_evade := 0.3         ## Chance, einem schweren Geschoss (Zerstörer/Flaggschiff) bewusst auszuweichen
var h_flag_linger := 12.0  ## s – nach Vernichtung des Schwadrons noch so lange auf das Flaggschiff gehen ("letzte Chance"), dann abdrehen
var h_flee := 20.0         ## % – darunter (Warnton läuft) bricht der Mensch den Kampf ab und fliegt tanken (0 = nie)
const H_KNOBS := ["h_reaction", "h_rate_frac", "h_err_min", "h_err_max", "h_err_t_min", "h_err_t_max",
	"h_lead_min", "h_lead_max", "h_laser_tol", "h_ion_tol", "h_ion_early", "h_flag_jitter", "h_evade", "h_flag_linger", "h_flee"]
const H_KP := 3.5          ## Lenkregler (1/s): ~1 s für 30°, kaum Überschwingen (gegen die Spielsteuerung getestet)
const H_KD := 0.3
const H_SMOOTH := 0.08     ## s – Glättung der Lenkbewegung (keine ruckartigen Sprünge)
const STEER := ["steer_left", "steer_right", "steer_up", "steer_down"]

# Mensch: Zustand
var _h_target: Enemy = null
var _h_react := 0.0
var _h_lead := 0.7
var _h_off := Vector2.ZERO        ## aktueller Zielfehler in Grad (x seitlich, y Höhe)
var _h_off_goal := Vector2.ZERO
var _h_off_t := 0.0
var _h_cmd := Vector2.ZERO        ## geglättete Lenkung (Anteil der max. Drehrate; x = Gieren, y = Nicken)
var _h_drive := 0.0               ## Planet: geglättetes Gas (-1 … 1)
var _h_prev_e := Vector2.ZERO
var _h_has_prev := false
var _h_ion_tol_cur := 1.5
var _h_flag_jit := 0.0
var _h_flag_roll := true
var _h_evade_t := 0.0
var _h_evade_dir := Vector2.ZERO
var _h_shot_plan := {}            ## Geschoss-ID → Reaktionszeit vor Einschlag (s), -1 = nicht ausweichen
var _h_stat := {"ion_n": 0, "ion_err": 0.0, "laser_n": 0, "laser_err": 0.0, "max_cmd": 0.0, "flag_shots": 0}  ## Plausibilitätswerte
var _h_near := 75.0               ## Planet: unter diesem Abstand zurücksetzen (je Ziel gewürfelt)
var _h_far := 160.0               ## Planet: über diesem Abstand vorwärts fliegen


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.event_logged.connect(func(text, _sev): print("[%s] EVENT %s" % [GameState.format_time(GameState.sim_time), text]))
	GameState.game_over_triggered.connect(func(r): print("[%s] GAME OVER (%s) score=%d stats=%s" % [GameState.format_time(GameState.sim_time), r, GameState.score, str(GameState.stats)]))
	GameState.energy_changed.connect(_on_energy_changed)
	GameState.score_changed.connect(_on_score_changed)
	GameState.squadron_spawned.connect(_on_squadron_spawned)
	GameState.squadron_destroyed.connect(_on_squadron_destroyed)
	GameState.damage_changed.connect(func(k): print("[%s] %s energy=%.1f" % [GameState.format_time(GameState.sim_time), ("DAMAGE " + k) if k != "" else "REPAIRED", GameState.energy]))
	_h_roll_ion_tol()
	var cfg := "mode=%s" % _mode_name()
	if human:
		for k in H_KNOBS:
			cfg += " %s=%s" % [k, str(get(k))]
	print("[AutoPilot] ", cfg)


## Optionale Feineinstellung des menschlichen Testfahrers über Testargumente (--h_evade=0 …).
func apply_test_args(args: Dictionary) -> void:
	for k in H_KNOBS:
		if args.has(k):
			set(k, float(args[k]))
	raid = args.has("raid") or args.has("raid_safe")
	raid_safe = args.has("raid_safe")
	raid_intercept = args.has("raid_intercept")
	safe_eta = float(args.get("safe_eta", safe_eta))
	safe_return_eta = float(args.get("safe_return_eta", safe_return_eta))
	raid_target = str(args.get("raid_target", raid_target))
	raid_energy = float(args.get("raid_energy", raid_energy))
	raid_return = float(args.get("raid_return", raid_return))


func _mode_name() -> String:
	return "passive" if passive else ("human" if human else "perfect")


func _process(delta: float) -> void:
	_t += delta
	_clock += delta
	var m := Main.instance
	if m == null or get_tree().paused:
		return
	_log_t += delta
	if _log_t > 20.0:
		_log_t = 0.0
		print("[%s] STATUS state=%d energy=%.1f score=%d squadrons=%d cities=%d loc=%d/%d" % [GameState.format_time(GameState.sim_time), m.state, GameState.energy, GameState.score, GameState.squadrons.size(), GameState.total_alive_cities(), GameState.player_loc, GameState.player_loc_id])
	if m.state == Main.State.TITLE:
		if _t > 1.0:
			_acct_reset()
			m.new_game()
			_t = -3.0
		return
	if m.state == Main.State.GAME_OVER:
		return
	if m.is_map_open():
		_release_steer()
		_decide_t += delta
		if _decide_t > 1.0:
			_decide_t = 0.0
			_choose_jump()
		return
	var sc: CombatBase = m.scene as CombatBase
	if sc == null or sc.dying:
		_release_steer()
		return
	_acct_frame(sc, delta)
	if passive:
		if sc is SpaceCombat and (sc as SpaceCombat).mode == SpaceCombat.Mode.ORBIT and not (sc as SpaceCombat).orbit_done:
			(sc as SpaceCombat).debug_finish_orbit()
		return
	if raid_safe and _safe_interrupt(sc, delta):
		return
	if sc is PlanetCombat and (sc as PlanetCombat).enemy_mode:
		if _enemy_planet(sc as PlanetCombat, delta):
			return
	if human:
		_fly_human(sc, delta)
	else:
		_fly(sc, delta)


func _release() -> void:
	if _fire_hold:
		Input.action_release("fire")
		_fire_hold = false


func _release_steer() -> void:
	if _steer_active:
		for a in STEER:
			Input.action_release(a)
		_steer_active = false
	_h_cmd = Vector2.ZERO
	_h_drive = 0.0
	_h_has_prev = false


## Kein Gegner da: kurz warten, dann Karte öffnen (beim Tanken erst, wenn die Energie voll ist).
func _no_target(sc: CombatBase, delta: float) -> void:
	_release()
	_release_steer()
	if GameState.player_loc == GameState.Loc.STAR:
		# Stern [0.12.0]: volltanken, aber spätestens bei halber Hitze weg (die Hitze steigt auch auf der Karte)
		if (GameState.energy >= Config.energy_max - 0.5 or GameState.star_heat >= 0.5) and Main.instance.can_open_map():
			_decide_t = 0.0
			Main.instance.open_map()
		return
	_decide_t += delta
	if _decide_t > 3.0:
		_decide_t = 0.0
		if sc is SpaceCombat and (sc as SpaceCombat).is_docking() and (GameState.energy < Config.energy_max - 0.5 or (Config.enemy_system_enabled and GameState.bombs < Config.bombs_max)):
			return
		if Main.instance.can_open_map():
			Main.instance.open_map()


# =============================================================================================
#  Perfekter Testfahrer (Standard)
# =============================================================================================
func _fly(sc: CombatBase, delta: float) -> void:
	var target: Enemy = null
	var best := INF
	for e in sc.enemies:
		if not is_instance_valid(e) or not e.alive:
			continue
		var d: float = e.global_position.distance_to(sc.camera.global_position)
		# Fighter zuerst (Weltraum), auf Planeten Zerstörer beim Bombardieren bevorzugen
		var pri := d
		if sc is PlanetCombat and e is Destroyer and e.is_bombarding():
			pri *= 0.3
		if e is Flagship:
			pri *= 2.5
		if pri < best:
			best = pri
			target = e
	if target == null:
		_no_target(sc, delta)
		return
	_decide_t = 0.0
	var aim: Vector3 = target.aim_point()
	if target is Flagship:
		aim = (target as Flagship).weak_point_pos()
	# Vorhalt
	var spd := Config.ion_speed if sc.weapon == CombatBase.Weapon.ION else Config.laser_speed
	var tof := aim.distance_to(sc.camera.global_position) / spd
	aim += target.velocity * tof * skill
	var dir := (aim - sc.camera.global_position).normalized()
	var want_yaw := atan2(-dir.x, -dir.z)
	var want_pitch := asin(clampf(dir.y, -1.0, 1.0))
	var max_rate := deg_to_rad(Config.space_turn_rate if not (sc is PlanetCombat) else Config.planet_turn_rate) * delta
	if sc is SpaceCombat:
		var s := sc as SpaceCombat
		if not s.controls_enabled:
			return
		s.yaw += clampf(wrapf(want_yaw - s.yaw, -PI, PI), -max_rate, max_rate)
		s.pitch += clampf(want_pitch - s.pitch, -max_rate, max_rate)
		s.camera.rotation = Vector3(s.pitch, s.yaw, 0)
	elif sc is PlanetCombat:
		var pc := sc as PlanetCombat
		pc.yaw += clampf(wrapf(want_yaw - pc.yaw, -PI, PI), -max_rate, max_rate)
		var dist := target.global_position.distance_to(sc.camera.global_position)
		pc.speed = Config.planet_speed_forward if dist > 140.0 else (0.0 if dist > 70.0 else -Config.planet_speed_backward)
		var fwd := Vector2(-sin(pc.yaw), -cos(pc.yaw))
		pc.pos += fwd * pc.speed * delta
	var to_aim := aim - sc.camera.global_position
	if sc is PlanetCombat:
		to_aim.y = 0.0   # keine Neigung auf Planeten: nur horizontal zielen
	var fwd3 := -sc.camera.global_transform.basis.z
	if sc is PlanetCombat:
		fwd3.y = 0.0
	var err := rad_to_deg(fwd3.angle_to(to_aim))
	var tol := 2.5 if sc.weapon == CombatBase.Weapon.LASER else 1.2
	if target is Flagship:
		var f := target as Flagship
		# kurz vor/zu Beginn des verwundbaren Fensters feuern
		var tof_f := tof
		var vul_soon := f.st == Flagship.St.CHARGING and (Config.flagship_charge_time - Config.flagship_vulnerable_time - f.st_time) < tof_f + 0.2 - Config.flagship_vulnerable_time * 0.5
		if not (f.is_vulnerable() or vul_soon):
			_release()
			return
	if err < tol:
		if sc.weapon == CombatBase.Weapon.ION:
			if sc.ion_cd <= 0.0:
				Input.action_press("fire")
				_fire_hold = true
			else:
				_release()
		else:
			if not _fire_hold:
				Input.action_press("fire")
				_fire_hold = true
	else:
		_release()


# =============================================================================================
#  Mensch (--human): lenkt über die Steueraktionen wie ein Spieler mit Tastatur/Gamepad
# =============================================================================================
func _fly_human(sc: CombatBase, delta: float) -> void:
	var planet := sc is PlanetCombat
	if not is_instance_valid(_h_target):
		_h_target = null
	# Energie kritisch: Kampf abbrechen und tanken (Kartenlogik wählt dann die Station); nicht an einer
	# Station selbst (dort wird nach dem Kampf ohnehin getankt) und nicht im gesperrten Orbit-Kampf
	# (am Stern nicht: dort wird getankt; ohne Stationen ist der Stern das Fluchtziel)
	if h_flee > 0.0 and GameState.energy < h_flee and GameState.player_loc != GameState.Loc.STATION and GameState.player_loc != GameState.Loc.STAR \
			and (_station_left() or Config.star_refuel_enabled) and Main.instance.can_open_map():
		_flees += 1
		print("[%s] FLEE energy=%.1f from=%s" % [GameState.format_time(GameState.sim_time), GameState.energy, _cur.name.replace(" ", "_") if _cur else "-"])
		_release()
		_release_steer()
		_h_target = null
		Main.instance.open_map()
		return
	var target := _h_pick_target(sc)
	if target == null:
		_h_target = null
		_no_target(sc, delta)
		return
	_decide_t = 0.0
	if not sc.controls_enabled or not (sc is SpaceCombat or planet):
		_release()
		_release_steer()
		return
	if target != _h_target:
		# Zielwechsel: erst orientieren (Reaktionszeit), Vorhalt-Gefühl und Wunschabstand je Ziel neu
		_h_target = target
		_h_react = h_reaction * randf_range(0.7, 1.3)
		_h_lead = randf_range(h_lead_min, h_lead_max)
		_h_near = randf_range(60.0, 90.0)
		_h_far = randf_range(120.0, 200.0)
		_h_has_prev = false
	_h_update_offset(delta, planet)
	if _h_evade(sc, delta, planet):
		return
	if _h_react > 0.0:
		_h_react -= delta
		_release()
		_h_steer(sc, Vector2.ZERO, delta, 0.0)   # Hände kurz vom Steuer: Drehung läuft aus
		return
	# Zielpunkt mit unvollständigem Vorhalt, dazu der wandernde Zielfehler
	var cam := sc.camera.global_position
	var aim: Vector3 = target.aim_point()
	if target is Flagship:
		aim = (target as Flagship).weak_point_pos()
	var spd := Config.ion_speed if sc.weapon == CombatBase.Weapon.ION else Config.laser_speed
	var tof := aim.distance_to(cam) / spd
	aim += target.velocity * tof * _h_lead
	var want := _h_offset_dir((aim - cam).normalized())
	var want_yaw := atan2(-want.x, -want.z)
	var raw := Vector2.ZERO
	var drive := 0.0
	if planet:
		var pc := sc as PlanetCombat
		var e_p := Vector2(wrapf(want_yaw - pc.yaw, -PI, PI), 0.0)
		raw = _h_control(e_p, delta, deg_to_rad(Config.planet_turn_rate))
		# vorwärts/rückwärts: erst eindrehen, dann (ungefähr) auf Wunschabstand gehen
		var flat := Vector2(target.global_position.x - cam.x, target.global_position.z - cam.z).length()
		if absf(rad_to_deg(e_p.x)) < 50.0:
			if target is Fighter:
				drive = 1.0 if flat > _h_far + 60.0 else 0.0   # Fighter kommen von selbst – nur drehen
			elif flat > _h_far:
				drive = 1.0
			elif flat < _h_near:
				drive = -1.0
	else:
		var s := sc as SpaceCombat
		var lim := deg_to_rad(Config.space_pitch_limit)
		var want_pitch := clampf(asin(clampf(want.y, -1.0, 1.0)), -lim, lim)
		var e_s := Vector2(wrapf(want_yaw - s.yaw, -PI, PI), want_pitch - s.pitch)
		raw = _h_control(e_s, delta, deg_to_rad(Config.space_turn_rate))
	_h_steer(sc, raw, delta, drive)
	_h_stat.max_cmd = maxf(_h_stat.max_cmd, raw.length())
	# Feuern: nur nahe am (fehlerhaften) Zielpunkt – auf Planeten nur horizontal gemessen
	var fwd3 := -sc.camera.global_transform.basis.z
	var want3 := want
	if planet:
		fwd3.y = 0.0
		want3.y = 0.0
	var err := rad_to_deg(fwd3.angle_to(want3))
	var ideal := aim + target.velocity * tof * (1.0 - _h_lead) - cam   # perfekter Zielpunkt (voller Vorhalt)
	if planet:
		ideal.y = 0.0
	var true_err := rad_to_deg(fwd3.angle_to(ideal))
	if target is Flagship and not _h_flagship_window(target as Flagship, tof):
		_release()
		return
	if sc.weapon == CombatBase.Weapon.ION:
		# einzelner Tastendruck je Schuss (Ionen-Kanone reagiert nur auf "gerade gedrückt")
		if _fire_hold:
			_release()
		elif sc.ion_cd <= 0.0 and err < _h_ion_tol_cur:
			Input.action_press("fire")
			_fire_hold = true
			_fire_weapon = CombatBase.Weapon.ION
			_h_roll_ion_tol()
			_h_stat.ion_n += 1
			_h_stat.ion_err += true_err
			if target is Flagship:
				_h_stat.flag_shots += 1
	elif err < h_laser_tol:
		if _fire_hold and _fire_weapon != CombatBase.Weapon.LASER:
			_release()
		if not _fire_hold:
			Input.action_press("fire")
			_fire_hold = true
			_fire_weapon = CombatBase.Weapon.LASER
		_h_stat.laser_n += 1
		_h_stat.laser_err += true_err
	else:
		_release()


## Zielwahl wie ein Mensch: was nah und vorn im Bild ist, zuerst; beim Ziel bleiben, bis es weg ist
## oder ein deutlich besseres auftaucht. Auf Planeten bombardierende Zerstörer bevorzugt.
func _h_pick_target(sc: CombatBase) -> Enemy:
	var cam := sc.camera.global_position
	var fwd := -sc.camera.global_transform.basis.z
	var best: Enemy = null
	var best_pri := INF
	var cur_pri := INF
	for e in sc.enemies:
		if not is_instance_valid(e) or not e.alive:
			continue
		if e is Flagship and _h_flag_given_up(e as Flagship):
			continue
		var to: Vector3 = e.global_position - cam
		var pri := to.length() * (1.0 + rad_to_deg(fwd.angle_to(to)) / 60.0)
		if sc is PlanetCombat and e is Destroyer and e.is_bombarding():
			pri *= 0.3
		if e is Flagship:
			pri *= 2.5
		if e == _h_target:
			cur_pri = pri
		if pri < best_pri:
			best_pri = pri
			best = e
	if cur_pri < INF and best_pri > cur_pri * 0.6:
		return _h_target
	return best


## Nach der Vernichtung seines Schwadrons versucht ein Mensch das Flaggschiff nur noch kurz
## (HUD: "letzte Chance"), dann dreht er ab und öffnet die Karte.
func _h_flag_given_up(f: Flagship) -> bool:
	if f.squadron == null or f.squadron.state != SquadronData.State.DESTROYED:
		return false
	return _clock - _sq_done_clock > h_flag_linger


func _station_left() -> bool:
	for st in GameState.stations:
		if not st.destroyed:
			return true
	return false


## Langsam wandernder Zielfehler: alle 0.4–0.8 s ein neuer Wunschfehler (Betrag 1.5–3°), weich angefahren.
func _h_update_offset(delta: float, planet: bool) -> void:
	_h_off_t -= delta
	if _h_off_t <= 0.0:
		_h_off_t = randf_range(h_err_t_min, h_err_t_max)
		var mag := randf_range(h_err_min, h_err_max)
		if planet:
			_h_off_goal = Vector2(mag * (1.0 if randf() < 0.5 else -1.0), 0.0)
		else:
			var a := randf() * TAU
			_h_off_goal = Vector2(cos(a), sin(a)) * mag
	_h_off = _h_off.lerp(_h_off_goal, 1.0 - exp(-delta / 0.25))


## Richtung zum Ziel, um den aktuellen Zielfehler verdreht (x seitlich, y nach oben).
func _h_offset_dir(dir: Vector3) -> Vector3:
	var right := dir.cross(Vector3.UP)
	if right.length_squared() < 0.000001:
		right = Vector3.RIGHT
	right = right.normalized()
	var up := right.cross(dir).normalized()
	return (dir + right * tan(deg_to_rad(_h_off.x)) + up * tan(deg_to_rad(_h_off.y))).normalized()


## Lenkregler: Fehler (rad, x = Gieren, y = Nicken) → Lenkausschlag, Betrag höchstens h_rate_frac.
func _h_control(e: Vector2, delta: float, max_rate: float) -> Vector2:
	var de := Vector2.ZERO
	if _h_has_prev and delta > 0.0:
		de = (e - _h_prev_e) / delta
		if absf(de.x) > 20.0 or absf(de.y) > 20.0:
			de = Vector2.ZERO   # Sprung (Winkelumbruch) ignorieren
	_h_prev_e = e
	_h_has_prev = true
	var r := (e * H_KP + de * H_KD) / max_rate
	if r.length() > h_rate_frac:
		r = r.normalized() * h_rate_frac
	return r


## Lenkausschlag geglättet auf die normalen Steueraktionen geben (wie Tastatur/Gamepad).
func _h_steer(sc: CombatBase, raw: Vector2, delta: float, drive: float) -> void:
	_h_cmd = _h_cmd.lerp(raw, 1.0 - exp(-delta / H_SMOOTH))
	_apply_axis("steer_left", "steer_right", -_h_cmd.x)
	if sc is PlanetCombat:
		_h_drive = lerpf(_h_drive, drive, 1.0 - exp(-delta / 0.15))
		_apply_axis("steer_down", "steer_up", _h_drive)   # Planet: rauf = vorwärts (unabhängig von invert_y)
	else:
		_apply_axis("steer_down", "steer_up", _h_cmd.y * (-1.0 if Settings.invert_y else 1.0))


func _apply_axis(neg: String, pos: String, v: float) -> void:
	if v > 0.01:
		Input.action_release(neg)
		Input.action_press(pos, minf(v, 1.0))
		_steer_active = true
	elif v < -0.01:
		Input.action_release(pos)
		Input.action_press(neg, minf(-v, 1.0))
		_steer_active = true
	else:
		Input.action_release(neg)
		Input.action_release(pos)


## Schwere Geschosse (Zerstörer/Flaggschiff): mit Chance h_evade kurz vor dem Einschlag kräftig lenken.
## Zählt im Spiel als Ausweichen (Trefferchance × evasion_hit_factor); zu späte Reaktion wirkt nicht.
func _h_evade(sc: CombatBase, delta: float, planet: bool) -> bool:
	if _h_evade_t > 0.0:
		_h_evade_t -= delta
		_release()
		_h_steer(sc, _h_evade_dir, delta, _h_drive)
		if _h_evade_t <= 0.0:
			_h_has_prev = false
		return true
	if h_evade <= 0.0:
		return false
	var cam := sc.camera.global_position
	var plan := {}
	var go := false
	for s in sc.shots.enemy_shots:
		if s.resolved or s.kind == ShotSystem.Kind.E_FIGHTER:
			continue
		var id: int = s.get_instance_id()
		var react: float = -1.0
		if _h_shot_plan.has(id):
			react = _h_shot_plan[id]
		elif randf() < h_evade:
			react = randf_range(0.2, 0.6)   # wie früh vor dem Einschlag reagiert wird
		if react > 0.0:
			var tti: float = (s.pos.distance_to(cam) - 7.0) / maxf(s.vel.length(), 1.0)
			if tti <= react:
				go = true
				react = -1.0
		plan[id] = react
	_h_shot_plan = plan
	if not go:
		return false
	_h_evade_t = randf_range(0.55, 0.85)
	_evade_attempts += 1
	_h_evade_dir = Vector2(1.0 if randf() < 0.5 else -1.0, 0.0 if planet else randf_range(-0.6, 0.6))
	_release()
	_h_steer(sc, _h_evade_dir, delta, _h_drive)
	return true


## Flaggschiff: Schuss so, dass er wie beim perfekten Testfahrer ~0.8 s nach Beginn des verwundbaren
## Fensters einschlägt – aber je Ladezyklus um ±h_flag_jitter verschoben.
func _h_flagship_window(f: Flagship, tof: float) -> bool:
	var until := 0.0   # Zeit bis zum Fensterbeginn
	if f.st == Flagship.St.CHARGING:
		until = Config.flagship_charge_time - Config.flagship_vulnerable_time - f.st_time
	elif f.st == Flagship.St.VULNERABLE:
		until = -f.st_time
	else:
		_h_flag_roll = true
		return false
	if _h_flag_roll:
		_h_flag_roll = false
		_h_flag_jit = randf_range(-h_flag_jitter, h_flag_jitter)
	var arrive := tof - until   # Einschlag relativ zum Fensterbeginn, falls jetzt gefeuert wird
	return arrive >= 0.8 + _h_flag_jit and arrive <= Config.flagship_vulnerable_time


func _h_roll_ion_tol() -> void:
	_h_ion_tol_cur = h_ion_tol if randf() >= h_ion_early else randf_range(h_ion_tol * 2.0, h_ion_tol * 4.0)


# =============================================================================================
#  Karte: Sprungziel wählen
# =============================================================================================
func _choose_jump() -> void:
	_release()
	var energy := GameState.energy
	var me := GameState.player_map_pos
	if GameState.player_system == 1:
		_choose_enemy_jump()
		return
	var threat := false
	for tsq in GameState.squadrons:
		if tsq.state == SquadronData.State.LANDED or tsq.state == SquadronData.State.AT_STATION:
			threat = true
	if raid_safe and _home_threat_eta() <= safe_eta:
		threat = true   # Verteidigung zuerst: erst die anfliegenden Schwadrone
	if raid and not threat and energy >= raid_energy and GameState.bombs >= mini(8, Config.bombs_max) and Config.enemy_system_enabled \
			and GameState.damage != "bombs":
		_raids += 1
		print("[%s] RAID_START n=%d energy=%.1f bombs=%d enemy_cities=%d/%d" % [GameState.format_time(GameState.sim_time), _raids, energy, GameState.bombs, GameState.enemy_cities_alive(), GameState.enemy_cities_total()])
		_do_jump(GameState.Loc.ENEMY_SYSTEM, -1, _raid)
		return
	# wenig Energie (bzw. bei Angriffen aufs Feindsystem: zu wenige Bomben) → nächste Station
	var any_station := false
	for st0 in GameState.stations:
		if not st0.destroyed:
			any_station = true
	# Bomben gibt es nur an Stationen: ohne Station kein Nachladen (sonst nie wieder zum Stern)
	var rearm := any_station and raid and not threat and GameState.bombs < mini(8, Config.bombs_max) and Config.enemy_system_enabled
	# Systemschaden [0.12.0]: klemmender Bombenschacht vor dem nächsten Angriff, gestörte Sicht (Mensch) sofort reparieren
	var dmg := GameState.damage
	var repair_now := any_station and not threat and ((dmg == "bombs" and raid) or (dmg == "screen" and human))
	var raid_possible := any_station or GameState.bombs >= mini(8, Config.bombs_max)
	if energy < 45.0 or rearm or repair_now or (raid and raid_possible and not threat and energy < raid_energy):
		var best: StationData = null
		for s in GameState.stations:
			if s.destroyed or (energy < 30.0 and s.attacker != -1):
				continue   # mit wenig Energie nicht mitten in einen Stationskampf springen
			if best == null or s.map_pos().distance_to(me) < best.map_pos().distance_to(me):
				best = s
		# nur Energie nötig und der Stern liegt nicht weiter weg: dort schnell tanken (ohne Reparatur und Bomben)
		if not rearm and not repair_now and Config.star_refuel_enabled and GameState.player_loc != GameState.Loc.STAR \
				and (best == null or GameState.jump_cost_to(GameState.Loc.STAR, GameState.STAR_POS) <= GameState.jump_cost_to(GameState.Loc.STATION, best.map_pos()) + 0.5):
			_star_trips += 1
			print("[%s] STAR_TRIP system=0 energy_before=%.1f" % [GameState.format_time(GameState.sim_time), energy])
			_do_jump(GameState.Loc.STAR, 0, null)
			return
		if best:
			if repair_now:
				_repair_trips += 1
				print("[%s] REPAIR_TRIP damage=%s station=%s" % [GameState.format_time(GameState.sim_time), dmg, best.name.replace(" ", "_")])
			if GameState.is_player_at_station(best.id):
				Main.instance.close_map()
				return
			print("[%s] JUMP station %s (energy %.1f)" % [GameState.format_time(GameState.sim_time), best.name, energy])
			_refuel_trips += 1
			_do_jump(GameState.Loc.STATION, best.id, null)
			print("[%s] REFUEL_TRIP station=%s energy_before=%.1f jump_cost=%.1f" % [GameState.format_time(GameState.sim_time), best.name.replace(" ", "_"), energy, energy - GameState.energy])
			return
	# gelandete Schwadrone zuerst, dann angegriffene Stationen, dann nächstes Schwadron
	var target_sq: SquadronData = null
	for sq in GameState.squadrons:
		if sq.state == SquadronData.State.LANDED:
			target_sq = sq
	if target_sq == null:
		for sq in GameState.squadrons:
			if sq.state == SquadronData.State.AT_STATION:
				target_sq = sq
	if target_sq == null and raid_safe:
		# Verteidigung zuerst: das Schwadron, das als nächstes landet
		var be := INF
		for sq in GameState.squadrons:
			var e := _squadron_threat_eta(sq)
			if e < be:
				be = e
				target_sq = sq
	if target_sq == null:
		var bd := INF
		for sq in GameState.squadrons:
			var d: float = sq.map_pos.distance_to(me)
			if d < bd:
				bd = d
				target_sq = sq
	if target_sq:
		print("[%s] JUMP squadron %s state=%d (energy %.1f)" % [GameState.format_time(GameState.sim_time), target_sq.name, target_sq.state, energy])
		_do_jump(GameState.Loc.SQUADRON, target_sq.id, _acct_for(target_sq))
	elif GameState.player_loc == GameState.Loc.STAR:
		# [0.12.0] nie am Stern bleiben (Hitze): ohne Ziel zur nächsten Station, sonst zum Heimatplaneten
		var park: StationData = null
		for s2 in GameState.stations:
			if not s2.destroyed and (park == null or s2.map_pos().distance_to(me) < park.map_pos().distance_to(me)):
				park = s2
		print("[%s] STAR_LEAVE idle energy=%.1f heat=%.2f" % [GameState.format_time(GameState.sim_time), energy, GameState.star_heat])
		if park:
			_do_jump(GameState.Loc.STATION, park.id, null)
		else:
			_do_jump(GameState.Loc.PLANET, GameState.home_planet().id, null)
	else:
		Main.instance.close_map()


## Feindsystem: Empfangskomitee abwarten, Planeten mit Bomben angreifen, zum Nachladen zurück.
func _choose_enemy_jump() -> void:
	var energy := GameState.energy
	if not GameState.reception_active and Config.star_refuel_enabled and GameState.player_loc != GameState.Loc.STAR \
			and energy < Config.enemy_jump_cost + 25.0:
		# [0.12.0] vor dem teuren Rücksprung (bzw. dem nächsten Angriff) erst am Stern Vorrhal tanken
		_star_trips += 1
		print("[%s] STAR_TRIP system=1 reason=low energy_before=%.1f bombs=%d" % [GameState.format_time(GameState.sim_time), energy, GameState.bombs])
		_do_jump(GameState.Loc.STAR, 1, _raid)
		return
	if raid_safe and _home_threat_eta() < safe_return_eta:
		_defend_returns += 1
		print("[%s] RAID_RETURN reason=defend eta=%.0f energy=%.1f bombs=%d" % [GameState.format_time(GameState.sim_time), _home_threat_eta(), energy, GameState.bombs])
		_do_jump(GameState.Loc.HOME_SYSTEM, -1, _raid)
		return
	if GameState.reception_active:
		if energy < 25.0:
			print("[%s] RAID_RETURN reason=reception energy=%.1f" % [GameState.format_time(GameState.sim_time), energy])
			_do_jump(GameState.Loc.HOME_SYSTEM, -1, _raid)
		else:
			Main.instance.close_map()   # weiterkämpfen
		return
	if raid_intercept and energy >= 55.0:
		# startende Schwadrone abfangen, bevor sie nach Helion springen (das dem Sprungpunkt nächste zuerst)
		var isq: SquadronData = null
		for esq in GameState.enemy_squadrons:
			if isq == null or esq.map_pos.distance_to(GameState.ENEMY_GATE) < isq.map_pos.distance_to(GameState.ENEMY_GATE):
				isq = esq
		if isq and not GameState.is_player_at_squadron(isq):
			_intercepts += 1
			print("[%s] RAID_INTERCEPT %s energy=%.1f" % [GameState.format_time(GameState.sim_time), isq.name, energy])
			_do_jump(GameState.Loc.SQUADRON, isq.id, _acct_for(isq))
			return
	if GameState.has_damage("bombs"):
		print("[%s] RAID_RETURN reason=jam energy=%.1f bombs=%d" % [GameState.format_time(GameState.sim_time), energy, GameState.bombs])
		_do_jump(GameState.Loc.HOME_SYSTEM, -1, _raid)
		return
	var target := _raid_planet()
	if raid and target != null and energy < raid_return and GameState.bombs > 0 and Config.star_refuel_enabled \
			and GameState.player_loc != GameState.Loc.STAR:
		# [0.12.0] am Stern Vorrhal schnell tanken statt nach Helion zurückzuspringen
		_star_trips += 1
		print("[%s] STAR_TRIP system=1 energy_before=%.1f bombs=%d" % [GameState.format_time(GameState.sim_time), energy, GameState.bombs])
		_do_jump(GameState.Loc.STAR, 1, _raid)
		return
	if not raid or target == null or energy < raid_return or GameState.bombs <= 0:
		print("[%s] RAID_RETURN energy=%.1f bombs=%d enemy_cities=%d/%d" % [GameState.format_time(GameState.sim_time), energy, GameState.bombs, GameState.enemy_cities_alive(), GameState.enemy_cities_total()])
		_do_jump(GameState.Loc.HOME_SYSTEM, -1, _raid)
		return
	if GameState.is_player_at_enemy_planet(target.id):
		Main.instance.close_map()
		return
	print("[%s] RAID_PLANET %s cities=%d defenders=%d energy=%.1f bombs=%d" % [GameState.format_time(GameState.sim_time), target.name, target.alive_cities(), target.defenders, energy, GameState.bombs])
	_do_jump(GameState.Loc.ENEMY_PLANET, target.id, _raid)


## Zeit (s) bis ein Schwadron in Helion Städte gefährdet: gelandet = 0, an einer Station ≈ 30 s, sonst Ankunftszeit.
func _squadron_threat_eta(sq: SquadronData) -> float:
	match sq.state:
		SquadronData.State.LANDED:
			return 0.0
		SquadronData.State.AT_STATION:
			return 30.0
		SquadronData.State.TRANSIT:
			var eta := GameState.squadron_eta(sq)
			if GameState.is_squadron_stopped(sq):
				eta += Config.single_destroyer_stop_time
			if sq.target_kind == SquadronData.TargetKind.STATION:
				eta += 30.0   # Stationsangriff: keine Stadt direkt in Gefahr
			return eta
	return INF


func _home_threat_eta() -> float:
	var best := INF
	for sq in GameState.squadrons:
		best = minf(best, _squadron_threat_eta(sq))
	return best


## "Verteidigung zuerst": Kampf abbrechen und über die Karte neu entscheiden, wenn in Helion eine Landung droht
## (im Feindsystem: zurückspringen; in Helion: zum dringenderen Schwadron, wenn das aktuelle noch Zeit hat).
func _safe_interrupt(sc: CombatBase, delta: float) -> bool:
	_safe_check_t -= delta
	if _safe_check_t > 0.0:
		return false
	_safe_check_t = 1.0
	if not Main.instance.can_open_map():
		return false
	var eta := _home_threat_eta()
	var go := false
	if GameState.player_system == 1:
		go = eta < safe_return_eta
	elif sc is SpaceCombat and (sc as SpaceCombat).mode == SpaceCombat.Mode.SQUADRON and (sc as SpaceCombat).squadron != null:
		var cur := (sc as SpaceCombat).squadron
		go = eta < 25.0 and _squadron_threat_eta(cur) > eta + 60.0
	if not go:
		return false
	print("[%s] SAFE_SWITCH eta=%.0f system=%d" % [GameState.format_time(GameState.sim_time), eta, GameState.player_system])
	_release()
	_release_steer()
	Main.instance.open_map()
	return true


func _raid_planet() -> PlanetData:
	var home := GameState.enemy_home()
	var home_ok := home != null and home.alive_cities() > 0
	var best: PlanetData = null
	for p in GameState.enemy_planets:
		if p.is_home or p.alive_cities() == 0:
			continue
		if best == null or p.alive_cities() > best.alive_cities():
			best = p
	match raid_target:
		"home":
			return home if home_ok else best
		"outer":
			return best if best else (home if home_ok else null)
	if home_ok and GameState.bombs >= home.alive_cities():
		return home
	return best if best else (home if home_ok else null)


## Feindplanet: erst die Verteidiger (Laser), dann Städte bombardieren – Aufschlagmarke auf die Stadt bringen.
## Gibt true zurück, wenn die Szene hier vollständig gesteuert wurde.
func _enemy_planet(sc: PlanetCombat, delta: float) -> bool:
	_switch_t -= delta
	var fighters := 0
	for e in sc.enemies:
		if is_instance_valid(e) and e.alive:
			fighters += 1
	if fighters > 0:
		_set_weapon(sc, CombatBase.Weapon.LASER)
		return false
	if sc.planet.alive_cities() == 0 or GameState.bombs <= 0 or GameState.game_over or GameState.has_damage("bombs"):
		_set_weapon(sc, CombatBase.Weapon.LASER)
		_no_target(sc, delta)
		return true
	_decide_t = 0.0
	_set_weapon(sc, CombatBase.Weapon.BOMB)
	if sc.weapon != CombatBase.Weapon.BOMB:
		_release()
		return true
	_bomb_city_t += delta
	if _bomb_city >= 0 and _bomb_city_t > 25.0:
		_bomb_skip = _bomb_city   # festgefahren: anderes Ziel versuchen
		_bomb_city = -1
	if _bomb_city < 0 or _bomb_city >= sc.planet.cities.size() or not sc.planet.cities[_bomb_city]:
		_bomb_city = _nearest_city(sc)
		_bomb_lock_t = 0.0
		_bomb_city_t = 0.0
		_bomb_backing = false
		_bomb_delay = randf_range(0.12, 0.5) if human else 0.0
	if _bomb_city < 0:
		return true
	var to: Vector2 = (sc.planet.city_pos[_bomb_city] as Vector2) - sc.player_xz()
	var dist := to.length()
	var want_yaw := atan2(-to.x, -to.y)
	var e_yaw := wrapf(want_yaw - sc.yaw, -PI, PI)
	# Anlauf mit Hysterese: zu nah → zurücksetzen bis ~120 m, dann mit Vollgas anfliegen; die Aufschlagmarke
	# wandert dabei von ~55 m (Stand) bis ~140 m (Vollgas) nach vorn und kreuzt die Stadt
	if dist < 70.0:
		_bomb_backing = true
	elif dist > 120.0:
		_bomb_backing = false
	var drive := 1.0
	if _bomb_backing:
		drive = -1.0
	elif absf(rad_to_deg(e_yaw)) > 30.0:
		drive = 0.0
	var raw := Vector2.ZERO
	if human:
		raw = _h_control(Vector2(e_yaw, 0.0), delta, deg_to_rad(Config.planet_turn_rate))
	else:
		raw = Vector2(clampf(e_yaw * 6.0, -1.0, 1.0), 0.0)
	_h_steer(sc, raw, delta, drive)
	if _fire_hold:
		_release()   # Bomben: jeder Abwurf ein eigener Tastendruck
		return true
	if sc.impact_city >= 0 and not sc.impact_pending and sc.bomb_cd <= 0.0:
		_bomb_lock_t += delta
		if _bomb_lock_t >= _bomb_delay:
			Input.action_press("fire")
			_fire_hold = true
			_fire_weapon = CombatBase.Weapon.BOMB
			_bomb_lock_t = 0.0
			_bomb_city_t = 0.0
			_bomb_delay = randf_range(0.12, 0.5) if human else 0.0
	else:
		_bomb_lock_t = 0.0
	return true


func _nearest_city(sc: PlanetCombat) -> int:
	var best := -1
	var bd := INF
	for i in sc.planet.cities.size():
		if sc.planet.cities[i]:
			var d: float = (sc.planet.city_pos[i] as Vector2).distance_to(sc.player_xz())
			if d < 90.0:
				d += 400.0   # zu nah für einen Abwurf: lieber eine andere Stadt
			if i == _bomb_skip:
				d += 1000.0  # gerade erst aufgegeben
			if d < bd:
				bd = d
				best = i
	return best


## Waffe über die normale Eingabe wechseln (Q/Tab), wie ein Spieler.
func _set_weapon(sc: CombatBase, w: int) -> void:
	if not sc.bombs_allowed() or sc.weapon == w or _switch_t > 0.0:
		return
	_switch_t = 0.5
	_release()
	for pressed in [true, false]:
		var ev := InputEventAction.new()
		ev.action = "switch_weapon"
		ev.pressed = pressed
		Input.parse_input_event(ev)


## Sprung mit Buchung der Sprungkosten (a = Konto des Ziel-Schwadrons, null = Tankfahrt/Sonstiges).
func _do_jump(kind: int, id: int, a: Acct) -> void:
	var e0 := GameState.energy
	_decide_t = 0.0   # Wartezeiten am Ziel ab Ankunft zählen (nicht schon während des Hyperraums)
	_jump_acct = a
	_in_jump = true
	Main.instance.request_jump(kind, id)
	_in_jump = false
	_jump_acct = null
	if a:
		a.e_in = e0


# =============================================================================================
#  Energie-Buchhaltung
# =============================================================================================
class Acct:
	var name := ""
	var level := 0
	var fighters0 := 0
	var colors0: Array = []
	var flagship0 := false
	var cost := 0.0            ## Energieverlust bis zur Vernichtung (Sprünge + Treffer)
	var jump := 0.0
	var dmg := {"F": 0.0, "D": 0.0, "S": 0.0, "?": 0.0}   ## Treffer nach Quelle: Fighter/Zerstörer/Flaggschiff/unklar
	var hits := {"F": 0, "D": 0, "S": 0, "?": 0}
	var shots := {"F": 0, "D": 0, "S": 0, "?": 0}          ## feindliche Schüsse auf den Spieler
	var nearmiss := {"F": 0, "D": 0, "S": 0, "?": 0}       ## knapp vorbei (Würfel/Ausweichen)
	var vanished := {"F": 0, "D": 0, "S": 0, "?": 0}       ## ohne "knapp vorbei" verschwunden = Treffer oder abgefangen
	var fk := 0                ## vernichtete Fighter
	var dk: Array = []         ## Farben der vernichteten Zerstörer
	var dhits := 0             ## Ionen-Treffer auf Zerstörer
	var flagship_killed := false
	var laser_shots := 0
	var ion_shots := 0
	var visits := 0
	var fight_time := 0.0
	var where: Array = []
	var e_in := -1.0           ## Energie vor dem letzten Hinsprung
	var e_out := -1.0          ## Energie bei der Vernichtung
	var done := false
	var extra := 0.0           ## Energieverlust nach der Vernichtung (Flaggschiff)
	var flag_after := false    ## Flaggschiff erst nach der Vernichtung des Schwadrons erwischt
	var extra_printed := false

var _accts := {}               ## Schwadron-ID → Acct
var _orbit := Acct.new()
var _overhead := Acct.new()    ## Tankfahrten, Sprünge ins Leere
var _destroyed: Array = []     ## Acct der vernichteten Schwadrone (in Reihenfolge)
var _jump_acct: Acct = null
var _in_jump := false
var _cur: Acct = null          ## Konto des laufenden Kampfes
var _scene_id := 0
var _seen := {}                ## feindliche Geschosse: Instanz-ID → [Art, aufgelöst]
var _seen_p := {}              ## eigene Geschosse (Instanz-ID)
var _dhl := {}                 ## DestroyerData-ID → zuletzt gesehene hits_left
var _orbit_reported := false
var _refuel_trips := 0
var _star_trips := 0           ## Schnelltanken am Stern (0.12.0)
var _repair_trips := 0         ## Stationsbesuche wegen eines Systemschadens
var _flees := 0
var _evade_attempts := 0
var _evading_time := 0.0
var _combat_time := 0.0


func _acct_reset() -> void:
	_accts.clear()
	_orbit = Acct.new()
	_orbit.name = "Orbit"
	_raid = Acct.new()
	_raid.name = "Feindsystem"
	_raids = 0
	_overhead = Acct.new()
	_destroyed.clear()
	_cur = null
	_scene_id = 0
	_seen.clear()
	_dhl.clear()
	_orbit_reported = false
	_refuel_trips = 0
	_star_trips = 0
	_repair_trips = 0
	_flees = 0
	_evade_attempts = 0
	_evading_time = 0.0
	_combat_time = 0.0
	_h_stat = {"ion_n": 0, "ion_err": 0.0, "laser_n": 0, "laser_err": 0.0, "max_cmd": 0.0, "flag_shots": 0}


func _acct_for(sq: SquadronData) -> Acct:
	if sq == null:
		return null
	if not _accts.has(sq.id):
		var a := Acct.new()
		a.name = sq.name
		a.level = sq.level
		a.fighters0 = sq.fighters_initial
		a.colors0 = sq.destroyer_colors()
		a.flagship0 = sq.has_flagship
		_accts[sq.id] = a
	return _accts[sq.id]


## Konto des Kampfes, der in dieser Szene läuft (null = kein Gegner-Schwadron).
func _fight_acct(sc: CombatBase) -> Acct:
	if sc is SpaceCombat:
		var s := sc as SpaceCombat
		if s.mode == SpaceCombat.Mode.ORBIT:
			return _orbit
		if s.mode == SpaceCombat.Mode.RECEPTION:
			return _raid
		return _acct_for(s.squadron)
	if sc is PlanetCombat:
		if (sc as PlanetCombat).enemy_mode:
			return _raid
		return _acct_for((sc as PlanetCombat).squadron)
	return null


func _where(sc: CombatBase) -> String:
	if sc is PlanetCombat:
		return "planet"
	match (sc as SpaceCombat).mode:
		SpaceCombat.Mode.ORBIT:
			return "orbit"
		SpaceCombat.Mode.STATION:
			return "station"
	return "space"


## Pro Bild im Kampf: Besuche, Kampfzeit, feindliche/eigene Schüsse und Ionen-Treffer zählen.
func _acct_frame(sc: CombatBase, delta: float) -> void:
	var a := _fight_acct(sc)
	var sid := sc.get_instance_id()
	if sid != _scene_id or a != _cur:
		_flush_extra(_cur)
		if a != null:
			a.visits += 1
			a.where.append(_where(sc))
		_scene_id = sid
		_cur = a
		_seen.clear()
		_seen_p.clear()
		_h_shot_plan.clear()
	if sc is SpaceCombat and (sc as SpaceCombat).mode == SpaceCombat.Mode.ORBIT and (sc as SpaceCombat).orbit_done and not _orbit_reported and _orbit.fk > 0:
		_orbit_reported = true
		print("[%s] ORBIT_COST cost=%.1f fighters_killed=%d %s" % [GameState.format_time(GameState.sim_time), _orbit.cost, _orbit.fk, _acct_details(_orbit)])
	_combat_time += delta
	if sc.is_evading():
		_evading_time += delta
	if a == null:
		return
	a.fight_time += delta
	var seen := {}
	for s in sc.shots.enemy_shots:
		var id: int = s.get_instance_id()
		var k := _kind_key(s.kind)
		seen[id] = [k, s.resolved]
		if not _seen.has(id):
			a.shots[k] += 1
		elif s.resolved and not _seen[id][1]:
			a.nearmiss[k] += 1   # aufgelöst, fliegt aber noch: knapp vorbei
	for id in _seen:
		if not seen.has(id) and not _seen[id][1]:
			a.vanished[_seen[id][0]] += 1
	_seen = seen
	var seen_p := {}
	for s in sc.shots.player_shots:
		var id2: int = s.get_instance_id()
		seen_p[id2] = true
		if not _seen_p.has(id2):
			if s.kind == ShotSystem.Kind.ION:
				a.ion_shots += 1
			else:
				a.laser_shots += 1
	_seen_p = seen_p
	for e in sc.enemies:
		if e is Destroyer and is_instance_valid(e) and e.alive:
			var did: int = e.data.get_instance_id()
			var hl: int = e.data.hits_left
			if _dhl.has(did) and hl < int(_dhl[did]):
				a.dhits += int(_dhl[did]) - hl
			_dhl[did] = hl


func _kind_key(kind: int) -> String:
	match kind:
		ShotSystem.Kind.E_FIGHTER:
			return "F"
		ShotSystem.Kind.E_DESTROYER:
			return "D"
		ShotSystem.Kind.E_FLAGSHIP:
			return "S"
	return "?"


## Quelle eines Treffers: das feindliche Geschoss, das gerade beim Spieler eingeschlagen ist.
func _hit_kind(sc: CombatBase, dmg: float) -> String:
	if sc == null or sc.shots == null:
		return "?"
	var cam := sc.camera.global_position
	var best := "?"
	var best_d := INF
	for s in sc.shots.enemy_shots:
		if not s.resolved or s.life >= s.max_life or s.pos.distance_to(cam) > 8.0:
			continue
		var dd: float = s.damage - dmg   # 0 beim Treffer; > 0, wenn die Energie bei 0 gekappt wurde
		if dd > -0.001 and dd < best_d:
			best_d = dd
			best = _kind_key(s.kind)
	return best


func _on_energy_changed(_value: float, delta: float) -> void:
	if delta >= 0.0:
		return
	var cost := -delta
	if _in_jump:
		var j: Acct = _jump_acct if _jump_acct else _overhead
		j.jump += cost
		if j.done:
			j.extra += cost
		else:
			j.cost += cost
		return
	var sc: CombatBase = Main.instance.scene as CombatBase if Main.instance else null
	var a: Acct = _fight_acct(sc) if sc else null
	if a == null:
		a = _overhead
	var k := _hit_kind(sc, cost)
	a.dmg[k] += cost
	a.hits[k] += 1
	if a.done:
		a.extra += cost
	else:
		a.cost += cost


func _on_score_changed(_value: int, pts: int, reason: String) -> void:
	var sc: CombatBase = Main.instance.scene as CombatBase if Main.instance else null
	var a: Acct = _fight_acct(sc) if sc else null
	if a == null:
		return
	if reason == "":
		if pts == Config.fighter_points:
			a.fk += 1
		else:
			var c := (Config.destroyer_points as Array).find(pts)
			if c >= 0:
				a.dk.append(c)
				a.dhits += 1   # der letzte Treffer (Zerstörer ist danach sofort weg)
	elif reason == "Flaggschiff":
		a.flagship_killed = true
		a.flag_after = a.done


func _on_squadron_spawned(sq: SquadronData) -> void:
	_acct_for(sq)


func _on_squadron_destroyed(sq: SquadronData) -> void:
	var a := _acct_for(sq)
	if a.done:
		return
	a.done = true
	a.e_out = GameState.energy
	_sq_done_clock = _clock
	_destroyed.append(a)
	print("[%s] SQUAD_COST name=%s cost=%.1f fighters_killed=%d destroyers=%s %s" % [GameState.format_time(GameState.sim_time),
		a.name.replace(" ", "_"), a.cost, a.fk, _colors(a.dk), _acct_details(a)])


func _flush_extra(a: Acct) -> void:
	if a == null or not a.done or a.extra_printed or (a.extra <= 0.0 and not a.flag_after):
		return
	a.extra_printed = true
	print("[%s] SQUAD_EXTRA name=%s extra=%.1f flagship=%s" % [GameState.format_time(GameState.sim_time), a.name.replace(" ", "_"), a.extra, _flag_state(a)])


func _colors(arr: Array) -> String:
	if arr.is_empty():
		return "none"
	var names := PackedStringArray()
	for c in arr:
		names.append(["blue", "green", "red"][clampi(int(c), 0, 2)])
	return ",".join(names)


func _flag_state(a: Acct) -> String:
	if a.flagship_killed:
		return "killed"
	return "alive" if a.flagship0 else "none"


## Abgefangen (vom eigenen Laser/Ionen-Schuss) = verschwunden ohne Treffer.
func _blocked(a: Acct, k: String) -> int:
	return maxi(int(a.vanished[k]) - int(a.hits[k]), 0)


func _acct_details(a: Acct) -> String:
	return "flagship=%s dest_initial=%s fighters_initial=%d level=%d jump=%.1f dmg_fighter=%.1f dmg_destroyer=%.1f dmg_flagship=%.1f dmg_other=%.1f hits_fighter=%d/%d hits_destroyer=%d/%d hits_flagship=%d/%d nearmiss=%d,%d,%d blocked=%d,%d,%d laser=%d/%d ion=%d/%d visits=%d where=%s fight_time=%.1f e_in=%.1f e_out=%.1f" % [
		_flag_state(a), _colors(a.colors0), a.fighters0, a.level, a.jump,
		a.dmg.F, a.dmg.D, a.dmg.S, a.dmg["?"],
		a.hits.F, a.shots.F, a.hits.D, a.shots.D, a.hits.S, a.shots.S,
		a.nearmiss.F, a.nearmiss.D, a.nearmiss.S, _blocked(a, "F"), _blocked(a, "D"), _blocked(a, "S"),
		a.fk, a.laser_shots, a.dhits + (1 if a.flagship_killed else 0), a.ion_shots,
		a.visits, ",".join(PackedStringArray(a.where)) if not a.where.is_empty() else "-", a.fight_time, a.e_in, a.e_out]


func _exit_tree() -> void:
	_print_summary()


## Zusammenfassung des Laufs (beim Beenden, z. B. durch --quit-after).
func _print_summary() -> void:
	if GameState.planets.is_empty():
		return
	_flush_extra(_cur)
	var costs: Array = []
	var total_x := 0.0
	for a in _destroyed:
		costs.append(a.cost)
		total_x += a.cost + a.extra
	costs.sort()
	var n := costs.size()
	var avg := 0.0
	for c in costs:
		avg += c
	avg = avg / n if n > 0 else 0.0
	var mid := floori(n * 0.5)
	var median: float = 0.0 if n == 0 else (costs[mid] if n % 2 == 1 else (costs[mid - 1] + costs[mid]) * 0.5)
	var dmg := {"F": 0.0, "D": 0.0, "S": 0.0, "?": 0.0}
	var hits := {"F": 0, "D": 0, "S": 0, "?": 0}
	var shots := {"F": 0, "D": 0, "S": 0, "?": 0}
	var nearmiss := {"F": 0, "D": 0, "S": 0, "?": 0}
	var blocked := {"F": 0, "D": 0, "S": 0, "?": 0}
	var jump_sq := 0.0
	var laser := [0, 0]
	var ion := [0, 0]
	var all: Array = _accts.values()
	all.append(_orbit)
	all.append(_overhead)
	for a in all:
		for k in dmg:
			dmg[k] += a.dmg[k]
			hits[k] += a.hits[k]
		for k in shots:
			shots[k] += a.shots[k]
			nearmiss[k] += a.nearmiss[k]
			blocked[k] += _blocked(a, k)
		if a != _overhead:
			jump_sq += a.jump
		laser[0] += a.fk
		laser[1] += a.laser_shots
		ion[0] += a.dhits + (1 if a.flagship_killed else 0)
		ion[1] += a.ion_shots
	for a in _accts.values():
		if not a.done and a.visits > 0:
			print("OPEN_SQUAD name=%s cost=%.1f fighters_killed=%d destroyers=%s %s" % [a.name.replace(" ", "_"), a.cost, a.fk, _colors(a.dk), _acct_details(a)])
	print("RUN_SUMMARY mode=%s sim=%s squadrons_destroyed=%d avg_cost=%.1f max_cost=%.1f min_cost=%.1f median_cost=%.1f avg_cost_incl_extra=%.1f dmg_fighter=%.1f dmg_destroyer=%.1f dmg_flagship=%.1f dmg_other=%.1f hits_fighter=%d/%d hits_destroyer=%d/%d hits_flagship=%d/%d nearmiss=%d,%d,%d blocked=%d,%d,%d jump_squadrons=%.1f jump_refuel=%.1f refuel_trips=%d flees=%d energy_refueled=%.1f laser=%d/%d ion=%d/%d evade_attempts=%d evading_frac=%.2f orbit_cost=%.1f game_over=%d reason=%s score=%d cities=%d/%d final_energy=%.1f" % [
		_mode_name(), GameState.format_time(GameState.sim_time), n, avg,
		costs.back() if n > 0 else 0.0, costs.front() if n > 0 else 0.0, median, total_x / n if n > 0 else 0.0,
		dmg.F, dmg.D, dmg.S, dmg["?"], hits.F, shots.F, hits.D, shots.D, hits.S, shots.S,
		nearmiss.F, nearmiss.D, nearmiss.S, blocked.F, blocked.D, blocked.S,
		jump_sq, _overhead.jump, _refuel_trips, _flees, float(GameState.stats.get("energy_refueled", 0.0)),
		laser[0], laser[1], ion[0], ion[1], _evade_attempts, _evading_time / maxf(_combat_time, 0.001), _orbit.cost,
		1 if GameState.game_over else 0, GameState.game_over_reason if GameState.game_over else "-", GameState.score,
		GameState.total_alive_cities(), GameState.total_cities(), GameState.energy])
	var st0: Dictionary = GameState.stats
	print("DAMAGE_SUMMARY damages=%d kinds=%s repairs=%d repair_trips=%d star_trips=%d star_visits=%d star_energy=%.1f active=%s" % [
		int(st0.get("damages", 0)), str(st0.get("damage_kinds", {})).replace(" ", ""), int(st0.get("repairs", 0)), _repair_trips,
		_star_trips, int(st0.get("star_visits", 0)), float(st0.get("star_energy", 0.0)), GameState.damage if GameState.damage != "" else "-"])
	if raid or int(GameState.stats.get("enemy_jumps", 0)) > 0:
		var st: Dictionary = GameState.stats
		print("SAFE_SUMMARY safe=%d intercept=%d defend_returns=%d intercepts=%d cities_lost=%d" % [1 if raid_safe else 0, 1 if raid_intercept else 0, _defend_returns, _intercepts, int(GameState.stats.get("cities_lost", 0))])
		print("ENEMY_SUMMARY raids=%d enemy_jumps=%d receptions=%d raid_cost=%.1f raid_jump_cost=%.1f fighters_killed=%d enemy_cities=%d/%d bombs=%d/%d intercepted=%d production=%.2f enemy_squadrons=%d victory=%d end=%s %s" % [
			_raids, st.get("enemy_jumps", 0), st.get("receptions", 0), _raid.cost, _raid.jump, _raid.fk,
			st.get("enemy_cities", 0), GameState.enemy_cities_total(), st.get("bombs_hit", 0), st.get("bombs_dropped", 0),
			st.get("enemy_squadrons_intercepted", 0), GameState.enemy_production_rate(), GameState.enemy_squadrons.size(),
			1 if GameState.victory else 0, GameState.end_kind if GameState.end_kind != "" else "-", _acct_details(_raid)])
	if human:
		print("HUMAN_STATS ion_shots=%d ion_true_err_avg=%.2f laser_frames=%d laser_true_err_avg=%.2f max_track_cmd=%.2f flagship_shots=%d" % [
			_h_stat.ion_n, _h_stat.ion_err / maxf(_h_stat.ion_n, 1.0), _h_stat.laser_n, _h_stat.laser_err / maxf(_h_stat.laser_n, 1.0),
			_h_stat.max_cmd, _h_stat.flag_shots])
