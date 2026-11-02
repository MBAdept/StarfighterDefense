class_name EnemySystemState
extends CombatBase
## =============================================================================================
##  FEINDSYSTEM – Platzhalter [Spielbeschreibung §11]
##  Leerer Spielzustand, an den später ohne großen Umbau ein Endspiel angeschlossen werden kann.
##  Erreichbar vorerst nur über die Testtaste F8 (der Sprungpunkt auf der Karte ist deaktiviert,
##  Config.enemy_system_enabled = false).
##
##  Vorgesehene Erweiterung:
##   - start_endgame(): Wellen von Verteidigern, Heimatbasis der Gegner, Siegbedingung
##   - GameState.trigger_victory() o. ä. für den Abspann
## =============================================================================================

var yaw := 0.0
var pitch := 0.0
var yaw_rate := 0.0
var pitch_rate := 0.0


func _ready() -> void:
	super._ready()
	location_name = "FEINDSYSTEM"
	location_sub = "In Vorbereitung"
	hint_text = "LEERTASTE: Systemkarte (Rücksprung)"
	fire_enabled = false
	hud.show_message("FEINDSYSTEM", "Dieser Bereich ist in Vorbereitung – hier folgt später das Endspiel.", 6.0, Color(0.85, 0.55, 1.0))
	start_endgame()


func music_track() -> String:
	return "enemy_system_theme"


func _build_world() -> void:
	var sky := ShaderMaterial.new()
	sky.shader = load("res://shaders/space_sky.gdshader")
	var pano := Assets.tex("sky/space_panorama_b.png")
	if pano:
		sky.set_shader_parameter("panorama", pano)
		sky.set_shader_parameter("use_panorama", true)
		sky.set_shader_parameter("tint", Vector3(1.3, 0.6, 0.8))
	sky.set_shader_parameter("sun_size", cos(deg_to_rad(1.2)))
	sky.set_shader_parameter("sun_intensity", 0.9)
	make_environment(sky, Color(0.35, 0.15, 0.25), 0.5)
	make_sun(Vector3(0.2, 0.15, -1.0), Color(1.0, 0.35, 0.3), 1.4)


## Platzhalter-Einstieg für das spätere Endspiel.
func start_endgame() -> void:
	pass


func _update_controls(delta: float) -> void:
	var inp := steer_input()
	var max_rate := deg_to_rad(Config.space_turn_rate)
	var k := 1.0 - exp(-Config.space_turn_response * delta)
	yaw_rate = lerpf(yaw_rate, -inp.x * max_rate, k)
	pitch_rate = lerpf(pitch_rate, inp.y * max_rate, k)
	yaw += yaw_rate * delta
	var lim := deg_to_rad(Config.space_pitch_limit)
	pitch = clampf(pitch + pitch_rate * delta, -lim, lim)
	camera.rotation = Vector3(pitch, yaw, 0)
	turn_norm = Vector2(yaw_rate, pitch_rate).length() / max_rate
