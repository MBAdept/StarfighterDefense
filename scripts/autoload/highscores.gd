extends Node
## Lokale Highscore-Liste (user://highscores.json).  [FREI]

const PATH := "user://highscores.json"

var entries: Array = []   # [{name, score, date, level, time}]


func _ready() -> void:
	load_scores()


func load_scores() -> void:
	entries.clear()
	if not FileAccess.file_exists(PATH):
		_seed_defaults()
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		_seed_defaults()
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if data is Array:
		for e in data:
			if e is Dictionary and e.has("name") and e.has("score"):
				entries.append(e)
	if entries.is_empty():
		_seed_defaults()
	_sort()


func _seed_defaults() -> void:
	# Startliste, damit die Tabelle nicht leer ist
	var names := ["ACE", "NOVA", "VEGA", "ORION", "LYRA", "RIGEL", "ATLAS", "DRACO", "ZETA", "IKARUS"]
	for i in names.size():
		entries.append({"name": names[i], "score": (10 - i) * 2500, "date": "–", "level": 0, "time": 0})
	_sort()


func _sort() -> void:
	entries.sort_custom(func(a, b): return int(a.score) > int(b.score))
	while entries.size() > Config.highscore_entries:
		entries.pop_back()


func save_scores() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(entries, "  "))


func qualifies(score: int) -> bool:
	if score <= 0:
		return false
	if entries.size() < Config.highscore_entries:
		return true
	return score > int(entries[-1].score)


## Fügt einen Eintrag hinzu und gibt den Rang (0-basiert) zurück, -1 wenn nicht in der Liste.
func add(player_name: String, score: int, level: int, play_time: float) -> int:
	var d := Time.get_datetime_dict_from_system()
	var e := {
		"name": player_name.strip_edges().substr(0, 12),
		"score": score,
		"date": "%02d.%02d.%04d" % [d.day, d.month, d.year],
		"level": level,
		"time": int(play_time),
	}
	entries.append(e)
	_sort()
	save_scores()
	return entries.find(e)
