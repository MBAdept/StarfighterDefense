extends Node
## Lokale Highscore-Listen (user://highscores.json) – [Vorgabe 0.13.0] eine eigene Liste je Schwierigkeitsstufe
## (Config.DIFFICULTY_LEVELS[i].key). Die Liste bis 0.12.0 (eine für alle) wird beim ersten Laden der Stufe
## „Anfänger“ zugeordnet: das war der bisherige Standard „Normal“.

const PATH := "user://highscores.json"
const LEGACY_KEY := "anfaenger"

var lists := {}   # Stufen-Schlüssel → [{name, score, date, level, time, won}]


func _ready() -> void:
	load_scores()


func load_scores() -> void:
	lists.clear()
	if not FileAccess.file_exists(PATH):
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if data is Array:
		# Format bis 0.12.0: eine einzige Liste
		lists[LEGACY_KEY] = _valid_entries(data)
	elif data is Dictionary and data.get("lists") is Dictionary:
		for key in data.lists:
			if data.lists[key] is Array:
				lists[str(key)] = _valid_entries(data.lists[key])
	for key in lists:
		_sort(lists[key])


func _valid_entries(arr: Array) -> Array:
	var out := []
	for e in arr:
		if e is Dictionary and e.has("name") and e.has("score"):
			out.append(e)
	return out


## Liste einer Stufe (leere Stufen bekommen die Startliste, damit die Tabelle nicht leer ist).
func list(key: String) -> Array:
	if not lists.has(key) or (lists[key] as Array).is_empty():
		lists[key] = _seed_defaults()
	return lists[key]


func _seed_defaults() -> Array:
	var out := []
	var names := ["ACE", "NOVA", "VEGA", "ORION", "LYRA", "RIGEL", "ATLAS", "DRACO", "ZETA", "IKARUS"]
	for i in names.size():
		out.append({"name": names[i], "score": (10 - i) * 2500, "date": "–", "level": 0, "time": 0})
	_sort(out)
	return out


func _sort(entries: Array) -> void:
	entries.sort_custom(func(a, b): return int(a.score) > int(b.score))
	while entries.size() > Config.highscore_entries:
		entries.pop_back()


func save_scores() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"version": 2, "lists": lists}, "  "))


func qualifies(score: int, key: String) -> bool:
	if score <= 0:
		return false
	var entries := list(key)
	if entries.size() < Config.highscore_entries:
		return true
	return score > int(entries[-1].score)


## Fügt einen Eintrag in die Liste der Stufe ein und gibt den Rang (0-basiert) zurück, -1 wenn nicht in der Liste.
func add(player_name: String, score: int, level: int, play_time: float, won: bool, key: String) -> int:
	var d := Time.get_datetime_dict_from_system()
	var e := {
		"name": player_name.strip_edges().substr(0, 12),
		"score": score,
		"date": "%02d.%02d.%04d" % [d.day, d.month, d.year],
		"level": level,
		"time": int(play_time),
		"won": won,
	}
	var entries := list(key)
	entries.append(e)
	_sort(entries)
	save_scores()
	return entries.find(e)
