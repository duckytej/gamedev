extends Node
## Sfx autoload. Add in Project Settings -> Autoload as "Sfx".
## Drop wav files in res://assets/sfx/ named exactly like the keys in SOUNDS.md
## (e.g. res://assets/sfx/scope_in.wav). Missing files = silent + a warning,
## never a crash — so the game runs before your sound pass is done.

const SFX_DIR := "res://assets/sfx"
const VOICES := 10

var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _loops := {}  # name -> AudioStreamPlayer


func _ready() -> void:
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)
	if DirAccess.dir_exists_absolute(SFX_DIR):
		for f in DirAccess.get_files_at(SFX_DIR):
			if f.ends_with(".wav") or f.ends_with(".ogg"):
				_streams[f.get_basename()] = load(SFX_DIR + "/" + f)
	else:
		push_warning("Sfx: no sfx folder at " + SFX_DIR + " — weapons will be silent")


func play(sound_name: String, pitch := 1.0, volume_db := 0.0) -> void:
	if not _streams.has(sound_name):
		return  # silent until the sound pass lands
	var p := _players[_next]
	_next = (_next + 1) % VOICES
	p.stream = _streams[sound_name]
	p.pitch_scale = pitch * randf_range(0.97, 1.03)
	p.volume_db = volume_db
	p.play()


func play_loop(sound_name: String, volume_db := -6.0) -> void:
	if _loops.has(sound_name) or not _streams.has(sound_name):
		return
	var p := AudioStreamPlayer.new()
	p.stream = _streams[sound_name]
	p.volume_db = volume_db
	add_child(p)
	p.play()
	_loops[sound_name] = p


func stop_loop(sound_name: String) -> void:
	if _loops.has(sound_name):
		(_loops[sound_name] as AudioStreamPlayer).queue_free()
		_loops.erase(sound_name)


func set_loop_pitch(sound_name: String, pitch: float) -> void:
	if _loops.has(sound_name):
		(_loops[sound_name] as AudioStreamPlayer).pitch_scale = pitch
