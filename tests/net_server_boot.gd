extends SceneTree

var _started := false

func _initialize() -> void:
	seed(42)

func _process(_d: float) -> bool:
	if not _started:
		_started = true
		var net = get_root().get_node("Net")
		net.start_server(net.DEFAULT_PORT)
		print("SERVER: listening")
	return false  # keep running; the shell script kills us
