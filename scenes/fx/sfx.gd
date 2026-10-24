extends Node
## Autoload `Sfx`: one-shot sound effects with a small voice pool, plus haptics.
## Sounds are synthesized by tools/gen_sfx.py into assets/audio/.

const DIR := "res://assets/audio/"
const NAMES := ["click", "tick", "slide", "flip", "heartbeat", "drumroll", "win", "streak", "lose", "shuffle", "turn"]
const VOICES := 8

var enabled: bool = true
var haptics_enabled: bool = true

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next: int = 0

func _ready() -> void:
	for n: String in NAMES:
		var path: String = DIR + n + ".wav"
		if ResourceLoader.exists(path):
			_streams[n] = load(path)
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)

func play(sound: String, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	if not enabled or not _streams.has(sound):
		return
	var p: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % VOICES
	p.stream = _streams[sound]
	p.pitch_scale = pitch
	p.volume_db = volume_db
	p.play()

func stop_all() -> void:
	for p in _players:
		p.stop()

func vibrate(ms: int) -> void:
	if haptics_enabled and OS.has_feature("mobile"):
		Input.vibrate_handheld(ms)
