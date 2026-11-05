class_name PlanetData
extends RefCounted
## Zustand eines Planeten (Städte, Umlaufbahn, gelandetes Schwadron) – im Helion- wie im Feindsystem.

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
# Feindsystem
var is_enemy := false           ## Planet eines Feindsystems (Städte werden vom Spieler zerbombt)
var system := 0                 ## 0 = Helion, 1 = Vorrhal, 2 = zweites Feindsystem (id = Index innerhalb des Systems)
var defenders := 0              ## verbleibende Verteidiger-Fighter (keine Regeneration)
var area_radius := 0.0          ## Einsatzgebiet (m); 0 = Config.planet_area_radius (Feindplaneten: × enemy_planet_area_factor)
var defenders_initial := 0


func alive_cities() -> int:
	var n := 0
	for c in cities:
		if c:
			n += 1
	return n


func area() -> float:
	return area_radius if area_radius > 0.0 else Config.planet_area_radius


func map_pos() -> Vector2:
	return Vector2(cos(angle), sin(angle)) * orbit_radius
