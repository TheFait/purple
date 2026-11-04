extends SceneTree

var _started := false

func _initialize() -> void:
	seed(42)

func _process(_d: float) -> bool:
	if not _started:
		_started = true
		var net = get_root().get_node("Net")
		net.auto_start_open_table = true   # tests skip the lobby
		net.deck_dump_path = "user://pp_deck_dump.txt"   # for the hidden-deck test
		if "idle" in OS.get_cmdline_user_args():
			net.idle_limits_msec = [1500, 1000, 800]   # the idle scenario: short limits so it need not wait minutes
			net.idle_warn_seconds = 1
		net.hold_msec = 4000                # and use a short seat hold ...
		net.turn_wait_msec = 1500           # ... and a short wait for an away player on their turn
		net.start_server(net.DEFAULT_PORT)
		print("SERVER: listening")
	return false  # keep running; the shell script kills us
