class_name StationData
extends RefCounted
## Zustand einer Raumstation (Tanken/Reparieren).

var id := 0
var name := ""
var orbit_radius := 160.0
var angle := 0.0
var angular_speed := 0.0
var integrity := 100.0          ## [FREI] sinkt, solange Fighter unverteidigt angreifen
var destroyed := false
var attacker := -1              ## Schwadron-ID des Angreifers (-1 = keiner)


func map_pos() -> Vector2:
	return Vector2(cos(angle), sin(angle)) * orbit_radius
