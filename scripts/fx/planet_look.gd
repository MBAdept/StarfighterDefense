class_name PlanetLook
extends RefCounted
## Farbwelten der Planetentypen (Karte, Orbitansicht, Oberfläche).

const SURFACE := {
	"terran": {"ground_a": Color(0.16, 0.30, 0.13), "ground_b": Color(0.36, 0.31, 0.21), "grid": Color(0.3, 0.9, 1.0),
		"sky_top": Color(0.08, 0.26, 0.6), "sky_horizon": Color(0.6, 0.78, 0.95), "fog": Color(0.58, 0.74, 0.9), "sun": Color(1.0, 0.95, 0.85), "stars": 0.0, "lava": 0.0, "water": 0.25},
	"desert": {"ground_a": Color(0.74, 0.52, 0.29), "ground_b": Color(0.52, 0.33, 0.17), "grid": Color(1.0, 0.75, 0.35),
		"sky_top": Color(0.3, 0.42, 0.72), "sky_horizon": Color(0.97, 0.8, 0.58), "fog": Color(0.92, 0.77, 0.58), "sun": Color(1.0, 0.9, 0.75), "stars": 0.0, "lava": 0.0, "water": 0.0},
	"ice": {"ground_a": Color(0.82, 0.9, 0.97), "ground_b": Color(0.52, 0.66, 0.82), "grid": Color(0.4, 0.8, 1.0),
		"sky_top": Color(0.12, 0.3, 0.62), "sky_horizon": Color(0.78, 0.9, 1.0), "fog": Color(0.8, 0.9, 1.0), "sun": Color(0.95, 0.97, 1.0), "stars": 0.0, "lava": 0.0, "water": 0.0},
	"jungle": {"ground_a": Color(0.08, 0.27, 0.1), "ground_b": Color(0.22, 0.4, 0.14), "grid": Color(0.5, 1.0, 0.6),
		"sky_top": Color(0.08, 0.3, 0.36), "sky_horizon": Color(0.55, 0.85, 0.72), "fog": Color(0.45, 0.7, 0.6), "sun": Color(1.0, 0.97, 0.85), "stars": 0.0, "lava": 0.0, "water": 0.15},
	"volcanic": {"ground_a": Color(0.09, 0.07, 0.07), "ground_b": Color(0.22, 0.12, 0.08), "grid": Color(1.0, 0.45, 0.15),
		"sky_top": Color(0.07, 0.02, 0.02), "sky_horizon": Color(0.6, 0.2, 0.08), "fog": Color(0.38, 0.13, 0.06), "sun": Color(1.0, 0.7, 0.5), "stars": 0.3, "lava": 1.0, "water": 0.0},
	"ocean": {"ground_a": Color(0.05, 0.24, 0.42), "ground_b": Color(0.32, 0.42, 0.3), "grid": Color(0.4, 0.95, 1.0),
		"sky_top": Color(0.1, 0.38, 0.75), "sky_horizon": Color(0.68, 0.86, 1.0), "fog": Color(0.62, 0.8, 0.95), "sun": Color(1.0, 0.97, 0.9), "stars": 0.0, "lava": 0.0, "water": 0.85},
	"toxic": {"ground_a": Color(0.42, 0.52, 0.1), "ground_b": Color(0.28, 0.36, 0.09), "grid": Color(0.8, 1.0, 0.3),
		"sky_top": Color(0.22, 0.07, 0.32), "sky_horizon": Color(0.72, 0.76, 0.35), "fog": Color(0.56, 0.6, 0.3), "sun": Color(0.95, 1.0, 0.8), "stars": 0.1, "lava": 0.0, "water": 0.0},
	"barren": {"ground_a": Color(0.36, 0.34, 0.33), "ground_b": Color(0.2, 0.19, 0.19), "grid": Color(0.6, 0.8, 1.0),
		"sky_top": Color(0.005, 0.005, 0.02), "sky_horizon": Color(0.12, 0.12, 0.17), "fog": Color(0.07, 0.07, 0.1), "sun": Color(1.0, 0.98, 0.95), "stars": 1.0, "lava": 0.0, "water": 0.0},
	# Feindsystem (Stern Vorrhal, rötliches Licht)
	"alien_home": {"ground_a": Color(0.17, 0.07, 0.19), "ground_b": Color(0.08, 0.04, 0.1), "grid": Color(1.0, 0.22, 0.55),
		"sky_top": Color(0.04, 0.0, 0.06), "sky_horizon": Color(0.52, 0.13, 0.32), "fog": Color(0.32, 0.09, 0.22), "sun": Color(1.0, 0.58, 0.52), "stars": 0.8, "lava": 0.0, "water": 0.35,
		"water_color": Color(0.32, 0.03, 0.22)},
	"alien_crimson": {"ground_a": Color(0.44, 0.14, 0.08), "ground_b": Color(0.22, 0.08, 0.07), "grid": Color(1.0, 0.38, 0.3),
		"sky_top": Color(0.12, 0.02, 0.03), "sky_horizon": Color(0.78, 0.34, 0.2), "fog": Color(0.56, 0.23, 0.14), "sun": Color(1.0, 0.7, 0.55), "stars": 0.2, "lava": 0.0, "water": 0.0},
	"alien_spore": {"ground_a": Color(0.37, 0.39, 0.09), "ground_b": Color(0.18, 0.22, 0.06), "grid": Color(0.85, 1.0, 0.25),
		"sky_top": Color(0.16, 0.17, 0.04), "sky_horizon": Color(0.68, 0.63, 0.26), "fog": Color(0.5, 0.5, 0.2), "sun": Color(1.0, 0.92, 0.6), "stars": 0.05, "lava": 0.0, "water": 0.3,
		"water_color": Color(0.16, 0.2, 0.05)},
	"alien_ash": {"ground_a": Color(0.23, 0.22, 0.22), "ground_b": Color(0.1, 0.09, 0.1), "grid": Color(1.0, 0.45, 0.2),
		"sky_top": Color(0.06, 0.03, 0.03), "sky_horizon": Color(0.46, 0.22, 0.12), "fog": Color(0.3, 0.16, 0.1), "sun": Color(1.0, 0.62, 0.42), "stars": 0.4, "lava": 0.7, "water": 0.0},
	"alien_crystal": {"ground_a": Color(0.26, 0.16, 0.38), "ground_b": Color(0.1, 0.2, 0.26), "grid": Color(0.75, 0.45, 1.0),
		"sky_top": Color(0.05, 0.02, 0.12), "sky_horizon": Color(0.5, 0.3, 0.7), "fog": Color(0.35, 0.22, 0.5), "sun": Color(0.92, 0.85, 1.0), "stars": 0.6, "lava": 0.0, "water": 0.0},
	# [0.14.0] zweites Feindsystem (blauer Stern Ixmora, kaltes Licht)
	"alien_void": {"ground_a": Color(0.09, 0.09, 0.2), "ground_b": Color(0.04, 0.04, 0.11), "grid": Color(0.52, 0.48, 1.0),
		"sky_top": Color(0.01, 0.01, 0.06), "sky_horizon": Color(0.22, 0.21, 0.52), "fog": Color(0.14, 0.14, 0.34), "sun": Color(0.78, 0.84, 1.0), "stars": 0.9, "lava": 0.0, "water": 0.35,
		"water_color": Color(0.05, 0.06, 0.24)},
	"alien_glacier": {"ground_a": Color(0.62, 0.66, 0.8), "ground_b": Color(0.33, 0.37, 0.53), "grid": Color(0.55, 0.75, 1.0),
		"sky_top": Color(0.04, 0.06, 0.2), "sky_horizon": Color(0.5, 0.58, 0.85), "fog": Color(0.48, 0.54, 0.76), "sun": Color(0.82, 0.88, 1.0), "stars": 0.4, "lava": 0.0, "water": 0.0},
	"alien_magma": {"ground_a": Color(0.11, 0.09, 0.12), "ground_b": Color(0.21, 0.13, 0.12), "grid": Color(1.0, 0.5, 0.22),
		"sky_top": Color(0.04, 0.02, 0.07), "sky_horizon": Color(0.42, 0.21, 0.32), "fog": Color(0.3, 0.15, 0.2), "sun": Color(0.85, 0.86, 1.0), "stars": 0.5, "lava": 1.0, "water": 0.0},
	"alien_bloom": {"ground_a": Color(0.05, 0.21, 0.24), "ground_b": Color(0.09, 0.12, 0.21), "grid": Color(0.3, 1.0, 0.85),
		"sky_top": Color(0.02, 0.06, 0.12), "sky_horizon": Color(0.2, 0.48, 0.55), "fog": Color(0.14, 0.33, 0.4), "sun": Color(0.8, 0.9, 1.0), "stars": 0.3, "lava": 0.0, "water": 0.3,
		"water_color": Color(0.03, 0.15, 0.2)},
}


## [0.14.4] Gelände je Planetentyp (PlanetTerrain, shaders/ground.gdshader):
##   style  0 = Felder und Straßen, 1 = Bewässerungskreise und Straßen, 2 = nur Straßen, 3 = leuchtende Adern (Feind)
##   relief Faktor für Hügel und Berge außerhalb des Gebiets, relief_inner = Bodenwellen im Gebiet (m),
##   ridged = schroffe Grate, snow = Schnee auf den Höhen, rock = Felsfarbe der Hänge, accent = Farbe der Adern/Plätze
const TERRAIN := {
	"terran": {"style": 0, "relief": 1.0, "snow": 1.0, "rock": Color(0.34, 0.32, 0.29)},
	"desert": {"style": 1, "relief": 0.75, "relief_inner": 3.5, "rock": Color(0.58, 0.4, 0.24)},
	"ice": {"style": 2, "relief": 1.15, "snow": 1.0, "ridged": true, "rock": Color(0.5, 0.58, 0.7)},
	"jungle": {"style": 0, "relief": 0.9, "rock": Color(0.2, 0.25, 0.15)},
	"volcanic": {"style": 2, "relief": 1.3, "ridged": true, "rock": Color(0.13, 0.09, 0.08)},
	"ocean": {"style": 2, "relief": 0.6, "relief_inner": 2.0, "rock": Color(0.4, 0.42, 0.36)},
	"toxic": {"style": 2, "relief": 0.9, "rock": Color(0.3, 0.33, 0.13)},
	"barren": {"style": 2, "relief": 1.0, "ridged": true, "rock": Color(0.3, 0.29, 0.28)},
	"alien_home": {"style": 3, "relief": 1.0, "rock": Color(0.12, 0.05, 0.14)},
	"alien_crimson": {"style": 3, "relief": 1.2, "ridged": true, "rock": Color(0.3, 0.1, 0.07)},
	"alien_spore": {"style": 3, "relief": 0.8, "rock": Color(0.22, 0.24, 0.07)},
	"alien_ash": {"style": 3, "relief": 1.1, "ridged": true, "rock": Color(0.12, 0.11, 0.11)},
	"alien_crystal": {"style": 3, "relief": 1.2, "ridged": true, "rock": Color(0.18, 0.12, 0.3)},
	"alien_void": {"style": 3, "relief": 0.9, "rock": Color(0.06, 0.06, 0.15)},
	"alien_glacier": {"style": 3, "relief": 1.1, "snow": 1.0, "ridged": true, "rock": Color(0.36, 0.4, 0.56)},
	"alien_magma": {"style": 3, "relief": 1.25, "ridged": true, "rock": Color(0.1, 0.08, 0.1)},
	"alien_bloom": {"style": 3, "relief": 0.9, "rock": Color(0.05, 0.13, 0.17)},
}


static func surface(type: String) -> Dictionary:
	return SURFACE.get(type, SURFACE["terran"])


static func terrain(type: String) -> Dictionary:
	var t: Dictionary = TERRAIN.get(type, TERRAIN["terran"]).duplicate()
	if not t.has("accent"):
		t["accent"] = surface(type).grid
	return t


static func palette(type: String) -> Array:
	var s := surface(type)
	return [s.ground_a, s.ground_b]


static func atmosphere(type: String) -> Color:
	match type:
		"terran":
			return Color(0.35, 0.65, 1.0)
		"desert":
			return Color(1.0, 0.7, 0.4)
		"ice":
			return Color(0.6, 0.85, 1.0)
		"jungle":
			return Color(0.45, 0.95, 0.7)
		"volcanic":
			return Color(1.0, 0.35, 0.15)
		"ocean":
			return Color(0.35, 0.75, 1.0)
		"toxic":
			return Color(0.75, 1.0, 0.3)
		"alien_home":
			return Color(1.0, 0.3, 0.62)
		"alien_crimson":
			return Color(1.0, 0.42, 0.3)
		"alien_spore":
			return Color(0.82, 0.92, 0.3)
		"alien_ash":
			return Color(0.95, 0.48, 0.3)
		"alien_crystal":
			return Color(0.72, 0.5, 1.0)
		"alien_void":
			return Color(0.46, 0.46, 1.0)
		"alien_glacier":
			return Color(0.62, 0.74, 1.0)
		"alien_magma":
			return Color(1.0, 0.46, 0.32)
		"alien_bloom":
			return Color(0.32, 0.95, 0.86)
	return Color(0.4, 0.45, 0.55)


static func map_color(type: String) -> Color:
	var s := surface(type)
	return (s.ground_a as Color).lerp(s.ground_b, 0.4).lightened(0.25)
