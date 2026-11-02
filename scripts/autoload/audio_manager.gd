extends Node
## Musik (mit Überblendung) und Soundeffekte (Pool, Varianten, Loops, 3D-Positionierung).
## Fehlende Dateien werden still übersprungen.
##
## Regeln:
##  - sfx()/ui()/sfx_3d() spielen den Klang immer genau EINMAL (die geteilte Ressource wird nie auf
##    "Loop" umgestellt).
##  - Endlos-Klänge nur über loop_start() (eigene loopende Kopie) und loop_stop().
##  - alarm(): Alarmsirene, endet automatisch nach Config.alarm_duration Sekunden.

const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_DIR := "res://assets/audio/music/"
## Grundlautstärke je Effekt (dB) – Feinabstimmung der Mischung an einer Stelle.
const SFX_GAIN := {
	"laser_1": -3.0, "laser_2": -3.0, "laser_3": -3.0,
	"ion_fire": 0.0, "ion_ready": -4.0, "target_lock": -6.0,
	"engine_loop": -6.0, "alarm_station": -3.0, "bombard_loop": -2.0,
	"refuel_tick": -2.0, "enemy_shot_fighter": -3.0, "warning_low_energy": -2.0,
	"near_miss": -2.0, "laser_deflect": -4.0,
}

var _music_players: Array[AudioStreamPlayer] = []
var _music_idx := 0
var _current_music := ""
var _music_tween: Tween
var _pool: Array[AudioStreamPlayer] = []
var _loops := {}            ## key -> AudioStreamPlayer
var _loop_tweens := {}      ## key -> Tween (Einblenden)
var _loop_streams := {}     ## sound_name -> eigene, loopende Kopie (nur für loop_start)
var _loop_time_left := {}   ## key -> Restzeit (s); danach endet der Loop automatisch (Alarm)
var _cache := {}
var _last_play := {}
var _last_gap := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		p.volume_db = -80.0
		add_child(p)
		_music_players.append(p)
	for i in 24:
		var s := AudioStreamPlayer.new()
		s.bus = "SFX"
		add_child(s)
		_pool.append(s)


func _process(delta: float) -> void:
	if _loop_time_left.is_empty():
		return
	for key in _loop_time_left.keys():
		_loop_time_left[key] -= delta
		if _loop_time_left[key] <= 0.0:
			loop_stop(key, _alarm_fade())


func _stream(dir: String, sound_name: String) -> AudioStream:
	var key := dir + sound_name
	if _cache.has(key):
		return _cache[key]
	var st: AudioStream = null
	for ext in [".ogg", ".wav"]:
		var path: String = dir + sound_name + ext
		if ResourceLoader.exists(path):
			st = load(path)
			break
	if st and st is AudioStreamOggVorbis:
		(st as AudioStreamOggVorbis).loop = dir == MUSIC_DIR and sound_name != "gameover_theme"
	_cache[key] = st
	return st


## Loopende Kopie eines Effekts – die geteilte (gecachte) Ressource bleibt unverändert.
func _looping_stream(sound_name: String) -> AudioStream:
	if _loop_streams.has(sound_name):
		return _loop_streams[sound_name]
	var base := _stream(SFX_DIR, sound_name)
	var st: AudioStream = base
	if base is AudioStreamWAV:
		var w := base.duplicate() as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(round(w.get_length() * w.mix_rate))
		st = w
	elif base is AudioStreamOggVorbis:
		var o := base.duplicate() as AudioStreamOggVorbis
		o.loop = true
		st = o
	_loop_streams[sound_name] = st
	return st


func _is_looping(st: AudioStream) -> bool:
	return st is AudioStreamWAV and (st as AudioStreamWAV).loop_mode != AudioStreamWAV.LOOP_DISABLED


# ---------------------------------------------------------------------------------------------
#  Musik
# ---------------------------------------------------------------------------------------------
## Überblendet zur Spur `track`. War diese Spur gerade noch auf dem zweiten Player aktiv
## (z. B. nach dem Schließen der Karte), läuft sie nahtlos an der alten Stelle weiter.
func play_music(track: String, fade := 1.6) -> void:
	if track == _current_music:
		return
	var st := _stream(MUSIC_DIR, track)
	_current_music = track
	if _music_tween:
		_music_tween.kill()
	_music_tween = create_tween().set_parallel(true)
	var old := _music_players[_music_idx]
	_music_tween.tween_property(old, "volume_db", -80.0, fade).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	if st == null:
		_music_tween.chain().tween_callback(_pause_inactive_music.bind(true))
		return
	_music_idx = 1 - _music_idx
	var p := _music_players[_music_idx]
	if p.stream == st and (p.playing or p.stream_paused):
		p.stream_paused = false
		if not p.playing:
			p.play()
	else:
		p.stop()
		p.stream_paused = false
		p.stream = st
		p.volume_db = -40.0
		p.play()
	_music_tween.tween_property(p, "volume_db", 0.0, fade).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_music_tween.chain().tween_callback(_pause_inactive_music.bind(false))


## Ausgeblendete Spur anhalten (Position bleibt erhalten) bzw. bei stop alles anhalten.
func _pause_inactive_music(all: bool) -> void:
	for i in _music_players.size():
		var q := _music_players[i]
		if all or i != _music_idx:
			if q.playing:
				q.stream_paused = true


func stop_music(fade := 1.5) -> void:
	_current_music = ""
	if _music_tween:
		_music_tween.kill()
	_music_tween = create_tween().set_parallel(true)
	for p in _music_players:
		_music_tween.tween_property(p, "volume_db", -80.0, fade)
	_music_tween.chain().tween_callback(_pause_inactive_music.bind(true))


func current_music() -> String:
	return _current_music


# ---------------------------------------------------------------------------------------------
#  Effekte
# ---------------------------------------------------------------------------------------------
## Spielt einen Effekt einmal. `variants` > 1 wählt zufällig name_1..name_n.
## `min_gap` > 0: derselbe Klang frühestens nach so vielen Sekunden erneut (gegen Dauerrauschen).
func sfx(sound_name: String, volume_db := 0.0, pitch := 1.0, pitch_var := 0.0, bus := "SFX", variants := 0, min_gap := 0.0) -> AudioStreamPlayer:
	var real_name := sound_name
	if variants > 1:
		real_name = "%s_%d" % [sound_name, randi_range(1, variants)]
	var st := _stream(SFX_DIR, real_name)
	if st == null:
		return null
	if _is_looping(st):
		push_warning("Audio.sfx: '%s' ist als Loop importiert – bitte loop_start()/alarm() verwenden." % real_name)
		return null
	var now := Time.get_ticks_msec()
	# Schutz gegen exzessives Stapeln identischer Klänge im selben Frame
	if _last_play.get(real_name, -1000) > now - 25:
		return null
	if min_gap > 0.0:
		if _last_gap.get(sound_name, -100000) > now - int(min_gap * 1000.0):
			return null
		_last_gap[sound_name] = now
	_last_play[real_name] = now
	var p := _free_player()
	p.stream = st
	p.bus = bus
	p.volume_db = volume_db + SFX_GAIN.get(real_name, 0.0)
	p.pitch_scale = maxf(0.05, pitch + randf_range(-pitch_var, pitch_var))
	p.play()
	return p


func ui(sound_name: String, volume_db := 0.0) -> void:
	sfx(sound_name, volume_db, 1.0, 0.0, "UI")


func _free_player() -> AudioStreamPlayer:
	for p in _pool:
		if not p.playing:
			return p
	# alle belegt: ältesten (ersten) wiederverwenden
	var p: AudioStreamPlayer = _pool.pop_front()
	_pool.append(p)
	p.stop()
	return p


## Positionaler Effekt im 3D-Raum (für Gegner).
func sfx_3d(sound_name: String, parent: Node3D, pos: Vector3, volume_db := 0.0, pitch_var := 0.05, variants := 0, unit_size := 40.0) -> void:
	var real_name := sound_name
	if variants > 1:
		real_name = "%s_%d" % [sound_name, randi_range(1, variants)]
	var st := _stream(SFX_DIR, real_name)
	if st == null or parent == null or not parent.is_inside_tree():
		return
	if _is_looping(st):
		push_warning("Audio.sfx_3d: '%s' ist als Loop importiert – wird nicht abgespielt." % real_name)
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = st
	p.bus = "SFX"
	p.unit_size = unit_size
	p.max_db = 3.0
	p.volume_db = volume_db + SFX_GAIN.get(real_name, 0.0)
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.panning_strength = 0.9
	parent.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()


# ---------------------------------------------------------------------------------------------
#  Alarm  [FREI] – höchstens Config.alarm_duration Sekunden, nie endlos, nie mehrfach gestapelt
# ---------------------------------------------------------------------------------------------
func alarm(volume_db := 0.0) -> void:
	var dur := Config.alarm_duration
	if dur <= 0.0 or _loops.has("alarm"):
		return   # erneutes Auslösen während eines laufenden Alarms verlängert ihn nicht
	loop_start("alarm", "alarm_station", volume_db, minf(0.05, dur * 0.5))
	if _loops.has("alarm"):
		_loop_time_left["alarm"] = maxf(dur - _alarm_fade(), 0.0)


func _alarm_fade() -> float:
	return minf(Config.alarm_fade, maxf(Config.alarm_duration, 0.0))


func is_alarm_active() -> bool:
	return _loops.has("alarm")


# ---------------------------------------------------------------------------------------------
#  Loops (Alarm, Bombardement, Triebwerk …)
# ---------------------------------------------------------------------------------------------
func loop_start(key: String, sound_name: String, volume_db := 0.0, fade := 0.4, bus := "SFX") -> void:
	var gain: float = SFX_GAIN.get(sound_name, 0.0)
	if _loops.has(key):
		var existing: AudioStreamPlayer = _loops[key]
		_kill_loop_tween(key)
		var tw0 := create_tween()
		tw0.tween_property(existing, "volume_db", volume_db + gain, fade)
		_loop_tweens[key] = tw0
		return
	var st := _looping_stream(sound_name)
	if st == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = st
	p.bus = bus
	p.volume_db = -50.0
	p.set_meta("gain", gain)
	p.process_mode = Node.PROCESS_MODE_PAUSABLE   # Pausemenü hält auch Loops an
	add_child(p)
	p.play()
	if not p.can_process():
		p.stream_paused = true   # während der Pause gestartet: stumm bis zum Fortsetzen
	_loops[key] = p
	var tw := create_tween()
	tw.tween_property(p, "volume_db", volume_db + gain, fade)
	_loop_tweens[key] = tw


func _kill_loop_tween(key: String) -> void:
	if _loop_tweens.has(key):
		var t: Tween = _loop_tweens[key]
		if t and t.is_valid():
			t.kill()
		_loop_tweens.erase(key)


func loop_stop(key: String, fade := 0.5) -> void:
	_loop_time_left.erase(key)
	if not _loops.has(key):
		return
	_kill_loop_tween(key)
	var p: AudioStreamPlayer = _loops[key]
	_loops.erase(key)
	var tw := create_tween()
	tw.tween_property(p, "volume_db", -60.0, maxf(fade, 0.01))
	tw.tween_callback(p.queue_free)


## Tonhöhe und/oder Lautstärke (dB, ohne Grundlautstärke) eines laufenden Loops setzen.
func loop_set(key: String, pitch := -1.0, volume_db := 999.0) -> void:
	if not _loops.has(key):
		return
	var p: AudioStreamPlayer = _loops[key]
	if pitch > 0.0:
		p.pitch_scale = pitch
	if volume_db < 900.0:
		var tw: Tween = _loop_tweens.get(key)
		if tw and tw.is_valid() and tw.is_running():
			return   # Einblenden noch nicht fertig – nicht überschreiben
		p.volume_db = volume_db + float(p.get_meta("gain", 0.0))


func has_loop(key: String) -> bool:
	return _loops.has(key)


func stop_all_loops(fade := 0.3) -> void:
	for k in _loops.keys():
		loop_stop(k, fade)
