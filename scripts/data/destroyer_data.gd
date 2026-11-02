class_name DestroyerData
extends RefCounted
## Zustand eines Zerstörers im Schwadron (bleibt bei Kampfunterbrechung erhalten).

enum Phase { LANDING, MOVING, BOMBARDING }

var color := 0                  ## 0 = blau, 1 = grün, 2 = rot   [ORIGINAL]
var hits_left := 2              ## verbleibende Treffer (Schilde + Rumpf)
# Bombardement auf Planeten
var phase := Phase.LANDING
var city := -1                  ## Zielstadt
var progress := 0.0             ## 0..1 Fortschritt des Bombardements
var timer := 0.0


func shields_left() -> int:
	return maxi(hits_left - 1, 0)


static func create(c: int) -> DestroyerData:
	var d := DestroyerData.new()
	d.color = c
	d.hits_left = Config.destroyer_hits_needed(c)
	return d
