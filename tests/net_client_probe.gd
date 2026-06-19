extends SceneTree

var _t := TestHelper.new()
var _elapsed := 0.0
var _seated := false
var _started := false

func _initialize() -> void:
	pass

func _process(delta: float) -> bool:
	if not _started:
		_started = true
		var net = get_root().get_node("Net")
		net.connected.connect(func(): net.join_room("auto", "Probe"))
		net.seated.connect(func(seat, room_name):
			_seated = true
			_t.check(seat >= 0, "probe received a seat (%d) in %s" % [seat, room_name]))
		net.start_client("127.0.0.1", net.DEFAULT_PORT)
		return false
	_elapsed += delta
	if _seated or _elapsed > 5.0:
		_t.check(_seated, "client got seated within timeout")
		_t.finish()
		return true
	return false
