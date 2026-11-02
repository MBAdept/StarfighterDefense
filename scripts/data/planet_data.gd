class_name PlanetData
extends RefCounted
## Zustand eines Planeten (Städte, Umlaufbahn, gelandetes Schwadron).

var id := 0
var name := ""
var type := "terran"            ## Optik: terran, desert, ice, jungle, volcanic, ocean, toxic, barren
var orbit_radius := 100.0       ## Karteneinheiten
var angle := 0.0
var angular_speed := 0.0
var is_home := false
var seed := 0
var cities: Array = []          ## bool: Stadt intakt?   [ORIGINAL] zerstörte Städte kommen nicht zurück
var city_pos: Array = []        ## Vector2 (m) – Lage der Stadt auf der Oberfläche (Planetenkampf)
var city_variant: Array = []    ## int 0..2 (Modellvariante)
var city_names: Array = []
var landed_squadron := -1       ## Schwadron-ID, die gerade auf dem Planeten ist (-1 = keins)


func alive_cities() -> int:
	var n := 0
	for c in cities:
		if c:
			n += 1
	return n


func map_pos() -> Vector2:
	return Vector2(cos(angle), sin(angle)) * orbit_radius
