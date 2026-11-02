class_name ShotSystem
extends Node3D
## Projektile: Bordlaser (Doppelstrahl), Ionen-Kugel, feindliche Geschosse.
## Trefferprüfung über Strecken-Kugel-Tests (schnelle Schüsse tunneln nicht).

enum Kind { LASER, ION, E_FIGHTER, E_DESTROYER, E_FLAGSHIP }

class Shot:
	var kind := 0
	var pos := Vector3.ZERO
	var vel := Vector3.ZERO
	var life := 0.0
	var max_life := 2.0
	var node: Node3D
	var bolts: Array = []
	var bolt_vel: Array = []
	var damage := 0.0
	var hit_chance := 1.0
	var resolved := false
	var source: Node = null
	var radius := 0.6
	var light: OmniLight3D
	var beams: Array = []     ## Laser: [[tail, head, k], …] für die 2D-Darstellung im HUD

const BEAM_TIME := 0.09   ## Laufzeit des sichtbaren Laserpulses bis zum Zielpunkt

var combat: CombatBase
var player_shots: Array = []
var enemy_shots: Array = []
var _bolt_mesh: Mesh
var _bolt_mat: StandardMaterial3D
var _ion_mat: StandardMaterial3D


func _init(c: CombatBase) -> void:
	combat = c


func _ready() -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = 0.07
	cm.bottom_radius = 0.07
	cm.height = 1.0
	cm.radial_segments = 6
	cm.rings = 1
	_bolt_mesh = cm
	_bolt_mat = StandardMaterial3D.new()
	_bolt_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bolt_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_bolt_mat.albedo_color = Color(0.45 * 6.0, 0.95 * 6.0, 1.0 * 6.0)
	_bolt_mat.disable_fog = true
	_bolt_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ion_mat = StandardMaterial3D.new()
	_ion_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ion_mat.albedo_color = Color(6.0, 6.0, 7.0)
	_ion_mat.disable_fog = true


func clear_all() -> void:
	for s in player_shots + enemy_shots:
		_free_shot(s)
	player_shots.clear()
	enemy_shots.clear()


# ---------------------------------------------------------------------------------------------
#  Abfeuern
# ---------------------------------------------------------------------------------------------
## Laser: logisch ein Strahl entlang der Bildmitte; optisch zwei Bolzen aus den Bordkanonen,
## die sich auf Zieldistanz treffen.
func fire_laser(origin: Vector3, dir: Vector3, convergence: float) -> void:
	var s := Shot.new()
	s.kind = Kind.LASER
	s.pos = origin
	s.vel = dir * Config.laser_speed
	s.max_life = Config.laser_range / Config.laser_speed
	s.node = Node3D.new()
	add_child(s.node)
	var cb := combat.camera.global_transform.basis
	var aim := origin + dir * convergence
	# Optik: zwei Lichtpulse laufen von den unteren Bildecken zum Zielpunkt (Hit-Test bleibt auf der Mittelachse).
	# Die Strahlen selbst zeichnet das HUD als 2D-Linien (klassischer Arcade-Look), hier nur der Leuchtkopf.
	for side in [-1.0, 1.0]:
		var gun := origin + cb * Vector3(0.78 * side, -0.4, -1.0)
		var g := Assets.glow_sprite(Color(0.45, 0.9, 1.0), 1.3, 2.4)
		s.node.add_child(g)
		g.global_position = gun
		s.bolt_vel.append([gun, aim, g])
		s.beams.append([gun, gun, 0.0])
	Effects.flash(self, origin + cb * Vector3(0.78, -0.4, -1.05), Color(0.5, 0.9, 1.0), 0.07, 0.06, false)
	Effects.flash(self, origin + cb * Vector3(-0.78, -0.4, -1.05), Color(0.5, 0.9, 1.0), 0.07, 0.06, false)
	player_shots.append(s)


func fire_ion(origin: Vector3, dir: Vector3) -> void:
	var s := Shot.new()
	s.kind = Kind.ION
	s.pos = origin
	s.vel = dir * Config.ion_speed
	s.max_life = Config.ion_range / Config.ion_speed
	s.radius = Config.ion_hit_tolerance
	s.node = Node3D.new()
	add_child(s.node)
	var core := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.55
	sm.height = 1.1
	sm.radial_segments = 16
	sm.rings = 8
	core.mesh = sm
	core.material_override = _ion_mat
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s.node.add_child(core)
	s.node.add_child(Assets.glow_sprite(Color(0.85, 0.8, 1.0), 5.5, 3.5))
	s.node.add_child(Assets.glow_sprite(Color(0.6, 0.5, 1.0), 12.0, 1.2))
	s.light = OmniLight3D.new()
	s.light.light_color = Color(0.8, 0.75, 1.0)
	s.light.light_energy = 3.5
	s.light.omni_range = 26.0
	s.node.add_child(s.light)
	s.node.global_position = origin + combat.camera.global_transform.basis * Vector3(0, -0.9, -1.5)
	player_shots.append(s)


## Feindliches Geschoss in Richtung Spieler. hit_chance wird beim Einschlag gewürfelt (Ausweichen!).
func fire_enemy(kind: int, from: Vector3, damage: float, hit_chance: float, speed: float, source: Node) -> void:
	var s := Shot.new()
	s.kind = kind
	s.pos = from
	var target := combat.camera.global_position
	s.vel = (target - from).normalized() * speed
	s.max_life = 12.0
	s.damage = damage * Config.difficulty_scale
	s.hit_chance = hit_chance
	s.source = source
	s.node = Node3D.new()
	add_child(s.node)
	s.node.global_position = from
	var col := Color(1.0, 0.45, 0.15)
	var size := 2.2
	match kind:
		Kind.E_FIGHTER:
			col = Color(1.0, 0.35, 0.55)
			size = 2.6
			s.radius = 1.2
		Kind.E_DESTROYER:
			col = Color(1.0, 0.42, 0.12)
			size = 4.5
			s.radius = 2.0
		Kind.E_FLAGSHIP:
			col = Color(1.0, 0.4, 0.9)
			size = 9.0
			s.radius = 3.5
	s.node.add_child(Assets.glow_sprite(col, size, 4.0))
	s.node.add_child(Assets.glow_sprite(Color(1, 1, 1), size * 0.35, 4.0))
	if kind != Kind.E_FIGHTER:
		s.light = OmniLight3D.new()
		s.light.light_color = col
		s.light.light_energy = 3.0
		s.light.omni_range = size * 6.0
		s.node.add_child(s.light)
		Effects.flash(self, from, col, size * 2.0, 0.3)
	else:
		Effects.flash(self, from, col, 3.2, 0.12, false)   # kurzes Mündungsfeuer am Fighter (ohne Licht)
	enemy_shots.append(s)


# ---------------------------------------------------------------------------------------------
#  Simulation
# ---------------------------------------------------------------------------------------------
func _process(delta: float) -> void:
	_update_player_shots(delta)
	_update_enemy_shots(delta)


func _update_player_shots(delta: float) -> void:
	for s in player_shots.duplicate():
		var p0: Vector3 = s.pos
		s.pos += s.vel * delta
		s.life += delta
		var hit := false
		# Treffer auf Gegner
		for e in combat.enemies:
			if not is_instance_valid(e) or not e.alive:
				continue
			var tol := Config.laser_hit_tolerance if s.kind == Kind.LASER else Config.ion_hit_tolerance
			var res: Dictionary = e.segment_hit(p0, s.pos, tol)
			if res.is_empty():
				continue
			hit = true
			if s.kind == Kind.LASER:
				e.on_laser_hit(res)
			else:
				e.on_ion_hit(res)
			break
		# Nur der Laser kann feindliche Geschosse abfangen (die Ionen-Kugel flöge sonst auf derselben
		# Linie wie der Zerstörer-Torpedo und würde ihn unbeabsichtigt neutralisieren)
		if not hit and s.kind == Kind.LASER:
			for es in enemy_shots:
				if es.resolved:
					continue
				if _seg_sphere(p0, s.pos, es.pos, es.radius + 0.8):
					hit = true
					Effects.flash(self, es.pos, Color(1.0, 0.8, 0.5), 5.0, 0.3)
					Effects.sparks(self, Vector3.ZERO, Color(1.0, 0.7, 0.4), 16, 14.0, 0.2, 0.5).global_position = es.pos
					Audio.sfx("laser_deflect", -4.0, 0.8, 0.1)
					es.resolved = true
					es.life = es.max_life
					break
		# Optik
		if s.kind == Kind.LASER:
			var k: float = s.life / BEAM_TIME
			for i in s.bolt_vel.size():
				var info: Array = s.bolt_vel[i]
				var a: Vector3 = info[0]
				var z: Vector3 = info[1]
				var head := a.lerp(z, minf(k, 1.0))
				# Strahlende bleibt erst an der Kanone, dann zieht es nach
				var tail := a.lerp(z, clampf((k - 0.7) / 0.8, 0.0, 1.0))
				s.beams[i] = [tail, head, k]
				var glow: Node3D = info[2]
				glow.global_position = head
				var hd := head.distance_to(combat.camera.global_position)
				glow.visible = k < 1.5 and hd > 12.0
				var gs := clampf(hd / 40.0, 0.2, 1.0)
				if k >= 1.0:
					gs *= maxf(1.4 - (k - 1.0) * 2.5, 0.05)
				glow.scale = Vector3.ONE * gs
		else:
			var off_fade := clampf(1.0 - s.life * 3.0, 0.0, 1.0)
			s.node.global_position = s.pos + combat.camera.global_transform.basis * Vector3(0, -0.9 * off_fade, 0)
			s.node.scale = Vector3.ONE * clampf(s.pos.distance_to(combat.camera.global_position) / 28.0, 0.06, 1.0)
		if hit or s.life >= s.max_life:
			if s.kind == Kind.ION and not hit:
				Effects.flash(self, s.pos, Color(0.8, 0.75, 1.0), 8.0, 0.35)
			_free_shot(s)
			player_shots.erase(s)


func _update_enemy_shots(delta: float) -> void:
	var cam_pos := combat.camera.global_position
	for s in enemy_shots.duplicate():
		s.life += delta
		if not s.resolved:
			# leichte Zielsuche: Geschoss folgt dem Spieler
			var desired: Vector3 = (cam_pos - s.pos).normalized() * s.vel.length()
			s.vel = s.vel.lerp(desired, clampf(delta * 2.5, 0.0, 1.0))
		s.pos += s.vel * delta
		s.node.global_position = s.pos
		var dist: float = s.pos.distance_to(cam_pos)
		# kurz vor der Kamera verkleinern, damit das Leuchten nicht den Bildschirm füllt
		var sc := clampf(dist / 16.0, 0.15, 1.0)
		if s.kind == Kind.E_FIGHTER:
			sc *= 1.0 + clampf((dist - 60.0) / 140.0, 0.0, 0.7)   # aus dem Anflug (150–230 m) gut erkennbar
		s.node.scale = Vector3.ONE * sc
		if not s.resolved and dist < 7.0:
			s.resolved = true
			var chance: float = s.hit_chance
			if combat.is_evading():
				chance *= Config.evasion_hit_factor
			if randf() < chance:
				combat.player_hit(s.damage, s.kind, s.vel.normalized())
				s.life = s.max_life
			else:
				# knapp vorbei: seitlich ablenken
				var cb := combat.camera.global_transform.basis
				var side := cb.x * (1.0 if randf() < 0.5 else -1.0) + cb.y * randf_range(-0.4, 0.6)
				s.vel = (s.vel.normalized() + side * 0.9).normalized() * s.vel.length() * 1.3
				s.max_life = s.life + 1.2
				# Fighter-Fehlschüsse: hörbar, aber höchstens alle 0,6 s (kein Dauerrauschen)
				Audio.sfx("near_miss", -2.0 if s.kind != Kind.E_FIGHTER else -4.0, 1.0, 0.1, "SFX", 0, 0.6 if s.kind == Kind.E_FIGHTER else 0.0)
				combat.on_near_miss(s.kind)
		if s.life >= s.max_life:
			_free_shot(s)
			enemy_shots.erase(s)


func _free_shot(s: Shot) -> void:
	if is_instance_valid(s.node):
		s.node.queue_free()


static func _seg_sphere(p0: Vector3, p1: Vector3, c: Vector3, r: float) -> bool:
	var d := p1 - p0
	var l2 := d.length_squared()
	var t := 0.0 if l2 < 0.0001 else clampf((c - p0).dot(d) / l2, 0.0, 1.0)
	return (p0 + d * t).distance_squared_to(c) <= r * r


## Nächster Punkt auf der Strecke zu c (für Trefferpositionen).
static func seg_closest(p0: Vector3, p1: Vector3, c: Vector3) -> Vector3:
	var d := p1 - p0
	var l2 := d.length_squared()
	var t := 0.0 if l2 < 0.0001 else clampf((c - p0).dot(d) / l2, 0.0, 1.0)
	return p0 + d * t


static func _orient_y(n: Node3D, dir: Vector3) -> void:
	# Zylinder-Achse (Y) entlang dir ausrichten
	var y := dir.normalized()
	var x := y.cross(Vector3.UP)
	if x.length_squared() < 0.001:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y).normalized()
	n.global_transform.basis = Basis(x, y, z)


## Gibt die Richtung des nächsten schweren feindlichen Geschosses zurück (für "INCOMING"-Anzeige).
func incoming_heavy() -> Array:
	var out := []
	for s in enemy_shots:
		if not s.resolved and s.kind != Kind.E_FIGHTER:
			out.append(s)
	return out
