class_name Enemy
extends Node3D
## Basisklasse aller Gegner. Positionen liegen relativ zum Spieler (Kamera) – die Darstellung
## ist echtes 3D, die Spiellogik entspricht der Pseudo-3D-Vorgabe (x, y, Tiefe relativ zum Spieler).

enum Kind { FIGHTER, DESTROYER, FLAGSHIP }

var kind := Kind.FIGHTER
var combat: CombatBase
var squadron: SquadronData = null
var hit_radius := 4.0
var alive := true
var model: Node3D
var velocity := Vector3.ZERO
var hud_color := Color(1.0, 0.55, 0.15)
var display_name := "FIGHTER"
var _hit_flash := 0.0


func setup(c: CombatBase, sq: SquadronData) -> void:
	combat = c
	squadron = sq


## Strecken-Treffertest. Rückgabe leer = kein Treffer, sonst {point, part}.
func segment_hit(p0: Vector3, p1: Vector3, tolerance: float) -> Dictionary:
	var c := global_position
	if ShotSystem._seg_sphere(p0, p1, c, hit_radius + tolerance):
		return {"point": ShotSystem.seg_closest(p0, p1, c), "part": "hull"}
	return {}


func on_laser_hit(_res: Dictionary) -> void:
	pass


func on_ion_hit(_res: Dictionary) -> void:
	pass


## Abstand und Winkel zur Bildmitte (für Zielerfassung).
func aim_error_deg() -> float:
	var cam := combat.camera
	var to := global_position - cam.global_position
	var fwd := -cam.global_transform.basis.z
	var ang := rad_to_deg(fwd.angle_to(to))
	var ang_r := rad_to_deg(atan2(hit_radius, maxf(to.length(), 0.1)))
	return maxf(ang - ang_r, 0.0)


func distance_to_player() -> float:
	return global_position.distance_to(combat.camera.global_position)


## Orientierung entlang einer Richtung mit Bank-Winkel (sicher gegen parallele Vektoren).
func face_dir(dir: Vector3, up: Vector3, bank := 0.0) -> void:
	if dir.length_squared() < 0.0001:
		return
	var f := dir.normalized()
	var u := up
	if absf(f.dot(u)) > 0.97:
		u = Vector3.FORWARD if absf(f.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	look_at(global_position + f, u)
	if bank != 0.0:
		rotate_object_local(Vector3.FORWARD, bank)


func spawn_engine_glows(prefixes: Array, color: Color, size: float) -> void:
	for pre in prefixes:
		for m in Assets.find_nodes_prefixed(model, pre):
			var g := Assets.glow_sprite(color, size, 1.6)
			m.add_child(g)
			var g2 := Assets.glow_sprite(color.lightened(0.6), size * 0.35, 2.4)
			m.add_child(g2)
