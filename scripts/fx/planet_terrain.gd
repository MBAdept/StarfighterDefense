class_name PlanetTerrain
extends RefCounted
## =============================================================================================
##  [Vorgabe 0.14.4] Gelände der Planetenoberfläche – „ein wenig landschaftliche Struktur, auch um die Städte“.
##  Aufbau (Höhen in m):
##   - Einsatzgebiet bis area + INNER_MARGIN: sanfte Bodenwellen (± inner_amp, auf Wasserwelten flache Seen in
##     Senken). Um jede Stadt ein exakt ebener Platz (y = 0 bis PLATEAU_R, weich auslaufend bis
##     PLATEAU_R + PLATEAU_BLEND): Bombentreffer, Zerstörerstrahl, Ruinen und Brandflecken bleiben dort wie bisher.
##   - Ab area + INNER_MARGIN steigen Hügel an, weiter außen Berge (Talkessel). Dort fliegt niemand: Spieler und
##     Bomben bleiben im Gebiet, Gegner höchstens ~250 m darüber hinaus.
##  Die feste Flughöhe (30 m) [ORIGINAL] bleibt; das Gelände im Gebiet bleibt weit darunter (Fighter ≥ 6 m).
##  Bomben schlagen auf height() auf (PlanetCombat._impact_time) – nahe den Städten ist das genau y = 0.
## =============================================================================================

const INNER_MARGIN := 260.0
const PLATEAU_R := 34.0
const PLATEAU_BLEND := 40.0
const R_MAX := 4300.0
const WATER_LEVEL := -3.2       ## Seen: Wasser unterhalb dieser Höhe (Shader) – tiefer als die Bodenwellen
const LAKE_DEPTH := -4.6
const RING_EXP := 1.8           ## Ringabstand wächst nach außen (fein im Gebiet, grob am Horizont)

var area := 640.0
var inner_amp := 3.0
var hill_amp := 70.0
var mountain_amp := 380.0
var ridged := false
var lake := 0.0
var cities: Array = []          ## Vector2 – Stadtmitten
var _mesh_hts := PackedFloat32Array()   ## Höhen des zuletzt gebauten Meshes (für surface_height)
var _mesh_rings := 0
var _mesh_segs := 0
var _n_wave := FastNoiseLite.new()
var _n_lake := FastNoiseLite.new()
var _n_hill := FastNoiseLite.new()
var _n_mount := FastNoiseLite.new()


func _init(p: PlanetData, terrain_look: Dictionary, water: float) -> void:
	area = p.area()
	cities = p.city_pos.duplicate()
	var relief := float(terrain_look.get("relief", 1.0))
	inner_amp = float(terrain_look.get("relief_inner", 3.0))
	hill_amp = 70.0 * relief
	mountain_amp = 380.0 * relief
	ridged = bool(terrain_look.get("ridged", false))
	lake = water
	_n_wave.seed = p.seed
	_n_wave.frequency = 0.0042
	_n_wave.fractal_octaves = 3
	_n_lake.seed = p.seed + 17
	_n_lake.frequency = 0.0026
	_n_lake.fractal_octaves = 2
	_n_hill.seed = p.seed + 31
	_n_hill.frequency = 0.0017
	_n_hill.fractal_octaves = 4
	_n_mount.seed = p.seed + 47
	_n_mount.frequency = 0.00075
	_n_mount.fractal_octaves = 5
	if ridged:
		_n_mount.fractal_type = FastNoiseLite.FRACTAL_RIDGED


## Höhe ohne die ebenen Stadtplätze.
func base_height(x: float, z: float) -> float:
	var r := sqrt(x * x + z * z)
	var h := maxf(inner_amp * _n_wave.get_noise_2d(x, z), WATER_LEVEL + 0.6)   # Wellentäler bleiben trocken
	if lake > 0.0:
		# flache Seen, wo das Seen-Rauschen tief liegt (Anteil nach dem Wasseranteil des Planetentyps)
		var ln := _n_lake.get_noise_2d(x, z) * 0.5 + 0.5
		var thr := lake * 0.55
		var depth := 1.0 - smoothstep(thr - 0.05, thr + 0.05, ln)
		h = lerpf(h, LAKE_DEPTH, depth)
	var e := area + INNER_MARGIN
	if r > e:
		var t := smoothstep(e, e + 520.0, r)
		var hills := hill_amp * (0.55 + 0.45 * _n_hill.get_noise_2d(x, z))
		var m := smoothstep(e + 250.0, e + 1900.0, r)
		var mn := _n_mount.get_noise_2d(x, z)
		var mount := mountain_amp * (clampf(mn, -1.0, 1.0) * 0.5 + 0.5)
		h += t * hills + m * mount
		h += smoothstep(R_MAX * 0.78, R_MAX, r) * 240.0   # Horizont geschlossen
	return h


## Gewicht 0 auf den Stadtplätzen, 1 abseits (weicher Übergang).
func plateau_weight(x: float, z: float) -> float:
	var w := 1.0
	var p := Vector2(x, z)
	for c in cities:
		var d := p.distance_to(c)
		if d < PLATEAU_R + PLATEAU_BLEND:
			w = minf(w, smoothstep(PLATEAU_R, PLATEAU_R + PLATEAU_BLEND, d))
	return w


## Geländehöhe (m) an (x, z) – dieselbe Funktion für Mesh und Bombenflug.
func height(x: float, z: float) -> float:
	return base_height(x, z) * plateau_weight(x, z)


## Höhe der gerenderten Oberfläche (Mesh, bilinear im Polarfeld) – für Felsen auf fernen Hügeln, deren
## Feinstruktur das grobe Außengitter nicht abbildet. Ohne Mesh: analytische Höhe.
func surface_height(x: float, z: float) -> float:
	if _mesh_hts.is_empty():
		return height(x, z)
	var r := sqrt(x * x + z * z)
	var fi := ring_index(r, _mesh_rings)
	var i0 := clampi(int(floorf(fi)), 0, _mesh_rings - 1)
	var r0 := ring_radius(i0, _mesh_rings)
	var r1 := ring_radius(i0 + 1, _mesh_rings)
	var tr := clampf((r - r0) / maxf(r1 - r0, 0.001), 0.0, 1.0)
	var a := fposmod(atan2(z, x), TAU) / TAU * float(_mesh_segs)
	var j0 := int(floorf(a)) % _mesh_segs
	var j1 := (j0 + 1) % _mesh_segs
	var ta: float = a - floorf(a)
	var h00 := _mesh_hts[i0 * _mesh_segs + j0]
	var h01 := _mesh_hts[i0 * _mesh_segs + j1]
	var h10 := _mesh_hts[(i0 + 1) * _mesh_segs + j0]
	var h11 := _mesh_hts[(i0 + 1) * _mesh_segs + j1]
	return lerpf(lerpf(h00, h01, ta), lerpf(h10, h11, ta), tr)


static func ring_radius(i: int, rings: int) -> float:
	return R_MAX * pow(float(i) / float(rings), RING_EXP)


static func ring_index(r: float, rings: int) -> float:
	return float(rings) * pow(clampf(r / R_MAX, 0.0, 1.0), 1.0 / RING_EXP)


## Polares Gitter um den Gebietsmittelpunkt: rings × segs Felder, Normalen aus den Nachbarpunkten.
func build_mesh(rings: int, segs: int) -> ArrayMesh:
	var nv := (rings + 1) * segs
	var verts := PackedVector3Array()
	verts.resize(nv)
	var hts := PackedFloat32Array()
	hts.resize(nv)
	var cosv := PackedFloat32Array()
	var sinv := PackedFloat32Array()
	cosv.resize(segs)
	sinv.resize(segs)
	for j in segs:
		var a := TAU * float(j) / float(segs)
		cosv[j] = cos(a)
		sinv[j] = sin(a)
	for i in rings + 1:
		var r := ring_radius(i, rings)
		for j in segs:
			var k := i * segs + j
			var x := cosv[j] * r
			var z := sinv[j] * r
			verts[k] = Vector3(x, 0.0, z)
			hts[k] = base_height(x, z)
	# ebene Stadtplätze: nur die Punkte in der Nähe einer Stadt
	var rr := PLATEAU_R + PLATEAU_BLEND
	for c in cities:
		var cv: Vector2 = c
		var rc := cv.length()
		var i0 := maxi(int(floor(ring_index(maxf(rc - rr, 0.0), rings))) - 1, 0)
		var i1 := mini(int(ceil(ring_index(rc + rr, rings))) + 1, rings)
		for i in range(i0, i1 + 1):
			for j in segs:
				var k := i * segs + j
				var v := verts[k]
				var d := Vector2(v.x, v.z).distance_to(cv)
				if d < rr:
					hts[k] *= smoothstep(PLATEAU_R, rr, d)
	for k in nv:
		verts[k].y = hts[k]
	_mesh_hts = hts
	_mesh_rings = rings
	_mesh_segs = segs
	# Normalen: Kreuzprodukt aus radialer und tangentialer Richtung (zentrale Differenzen)
	var normals := PackedVector3Array()
	normals.resize(nv)
	for i in rings + 1:
		var ia := maxi(i - 1, 0)
		var ib := mini(i + 1, rings)
		for j in segs:
			var k := i * segs + j
			if i == 0:
				normals[k] = Vector3.UP
				continue
			var jm := (j - 1 + segs) % segs
			var jp := (j + 1) % segs
			var radial := verts[ib * segs + j] - verts[ia * segs + j]
			var tang := verts[i * segs + jp] - verts[i * segs + jm]
			var n := tang.cross(radial).normalized()
			if n.y < 0.0:
				n = -n
			normals[k] = n
	# Dreiecke: Vorderseite nach oben (Godot: im Uhrzeigersinn von vorn gesehen)
	var idx := PackedInt32Array()
	idx.resize(rings * segs * 6)
	var w := 0
	for i in rings:
		for j in segs:
			var jp := (j + 1) % segs
			var a := i * segs + j
			var b := i * segs + jp
			var c2 := (i + 1) * segs + j
			var d2 := (i + 1) * segs + jp
			idx[w] = a
			idx[w + 1] = b
			idx[w + 2] = c2
			idx[w + 3] = b
			idx[w + 4] = d2
			idx[w + 5] = c2
			w += 6
	# Umlaufsinn prüfen (ein Dreieck außerhalb der Mitte) und bei Bedarf drehen
	var t0 := verts[idx[segs * 6]]
	var t1 := verts[idx[segs * 6 + 1]]
	var t2 := verts[idx[segs * 6 + 2]]
	if (t1 - t0).cross(t2 - t0).y > 0.0:
		for q in range(0, idx.size(), 3):
			var tmp := idx[q + 1]
			idx[q + 1] = idx[q + 2]
			idx[q + 2] = tmp
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


## Straßennetz bzw. Adern: kürzeste Verbindung aller Städte (Prim) und zwei Ausfallstraßen bis in die Hügel.
## Rückgabe: Array aus {seg: Vector4 (x0, z0, x1, z1), a: Stadt am Anfang, b: Stadt am Ende (-1 = keine)}.
func road_segments(max_count: int) -> Array:
	var out := []
	var n := cities.size()
	if n == 0:
		return out
	var in_tree := []
	in_tree.resize(n)
	in_tree.fill(false)
	in_tree[0] = true
	var best_d := []
	var best_p := []
	best_d.resize(n)
	best_p.resize(n)
	for i in n:
		best_d[i] = (cities[i] as Vector2).distance_to(cities[0])
		best_p[i] = 0
	for step in n - 1:
		var bi := -1
		var bd := INF
		for i in n:
			if not in_tree[i] and float(best_d[i]) < bd:
				bd = best_d[i]
				bi = i
		if bi < 0:
			break
		in_tree[bi] = true
		var a: Vector2 = cities[best_p[bi]]
		var b: Vector2 = cities[bi]
		out.append({"seg": Vector4(a.x, a.y, b.x, b.y), "a": int(best_p[bi]), "b": bi})
		for i in n:
			if not in_tree[i]:
				var d := (cities[i] as Vector2).distance_to(b)
				if d < float(best_d[i]):
					best_d[i] = d
					best_p[i] = bi
	# zwei Ausfallstraßen von den äußersten Städten radial nach außen
	var order := range(n)
	order.sort_custom(func(x, y): return (cities[x] as Vector2).length() > (cities[y] as Vector2).length())
	for k in mini(2, n):
		var c: Vector2 = cities[order[k]]
		if c.length() < 1.0:
			continue
		var e := c.normalized() * (area + INNER_MARGIN + 420.0)
		out.append({"seg": Vector4(c.x, c.y, e.x, e.y), "a": int(order[k]), "b": -1})
	return out.slice(0, max_count)
