class_name SquadronData
extends RefCounted
## Zustand eines feindlichen Schwadrons.  [ORIGINAL] 3–12 Fighter, 1–3 Zerstörer, eventuell 1 Flaggschiff

enum State { TRANSIT, LANDED, AT_STATION, DESTROYED, WAITING }
enum TargetKind { PLANET, STATION, GATE }   ## GATE = Sprungpunkt des Feindsystems ins Helion-System

var id := 0
var name := ""
var map_pos := Vector2.ZERO
var target_kind := TargetKind.PLANET
var target_id := 0
var state := State.TRANSIT
var fighters := 0
var fighters_initial := 0
var destroyers: Array = []      ## DestroyerData
var has_flagship := false
var level := 0
var stop_clock := 0.0           ## [VERMUTET] Takt für "bleibt zeitweise stehen"
var group_city := -1            ## Stadt, um die sich das Schwadron auf dem Planeten gruppiert
var spawn_time := 0.0
var system := 0                 ## 0 = Helion-System, 1 = Feindsystem (auf dem Weg zum Sprungpunkt)
var origin := ""                ## Startplanet im Feindsystem (Anzeige)


func strength() -> float:
	return float(fighters) + 4.0 * destroyers.size() + (2.0 if has_flagship else 0.0)


func is_destroyed() -> bool:
	return fighters <= 0 and destroyers.is_empty()


func destroyer_colors() -> Array:
	var out := []
	for d in destroyers:
		out.append(d.color)
	return out
