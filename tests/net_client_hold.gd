extends SceneTree
## A game in a private room with two players, one of whom loses their connection.
## Arguments: <role> <mode>
##   host/guest, mode "resume":   the guest's connection drops and comes back in time.
##   host/guest, mode "turnskip": the host (on turn) drops and never returns.
## The test server uses a 4 s hold and a 1.5 s turn wait, so nothing waits a minute.

const CODE_FILE := "user://pp_hold_code.txt"

var _t := TestHelper.new()
var _role := "host"
var _mode := "resume"
var _elapsed := 0.0
var _started := false
var _my_seat := -1
var _code := ""
var _joined := false
var _infos: Array[Dictionary] = []
var _playing_at := -1.0
var _dropped := false
var _away_lists: Array = []
var _left_names: Array[String] = []
var _skips: Array = []
var _reconnecting_seen := false
var _resumed := false
var _restored := false
var _can_act_after_skip := false

func _process(delta: float) -> bool:
	var net = get_root().get_node("Net")
	if not _started:
		_started = true
		var args := OS.get_cmdline_user_args()
		if args.size() > 0:
			_role = args[0]
		if args.size() > 1:
			_mode = args[1]
		net.seated.connect(func(seat, _rn): _my_seat = seat)
		net.lobby_changed.connect(func(info): _infos.append(info))
		net.away_changed.connect(func(list): _away_lists.append(list))
		net.player_left.connect(func(who): _left_names.append(who))
		net.turn_skipped.connect(func(f, to): _skips.append([f, to]))
		net.reconnecting.connect(func(_s): _reconnecting_seen = true)
		net.resumed.connect(func(): _resumed = true)
		net.table_restored.connect(func(_c): _restored = true)
		if _role == "host":
			DirAccess.remove_absolute(ProjectSettings.globalize_path(CODE_FILE))
			net.connected.connect(func(): net.create_room("", false, "Ann"))
			net.start_client("127.0.0.1", net.DEFAULT_PORT)
		return false
	_elapsed += delta
	if _role == "guest" and not _joined:
		if FileAccess.file_exists(CODE_FILE) and _elapsed > 1.0:
			_code = FileAccess.get_file_as_string(CODE_FILE).strip_edges()
			if _code.length() == 5:
				_joined = true
				net.connected.connect(func(): net.join_room(_code, "Bea"))
				net.start_client("127.0.0.1", net.DEFAULT_PORT)
		return false
	var info: Dictionary = _infos.back() if not _infos.is_empty() else {}
	if info.get("state") == "playing" and _playing_at < 0.0:
		_playing_at = _elapsed
	if _role == "host":
		if _code.is_empty() and not _infos.is_empty():
			_code = _infos[0].code
			var f := FileAccess.open(CODE_FILE, FileAccess.WRITE)
			f.store_string(_code)
			f.close()
		if info.get("names", []).size() == 2 and info.get("state") == "lobby":
			net.request_start()
	# The player who drops does so a moment after the game starts.
	var drops := (_role == "guest" and _mode == "resume") or (_role == "host" and _mode == "turnskip")
	if drops and _playing_at >= 0.0 and not _dropped and _elapsed - _playing_at > 1.0:
		_dropped = true
		if _mode == "resume":
			net.lose_connection()
		else:
			net.stop_client()
			_t.check(true, "the host dropped for good while on turn")
			_t.finish()
			return true
	if _mode == "turnskip" and _role == "guest" and net.can_act() and not _skips.is_empty():
		_can_act_after_skip = true
	if _elapsed > 16.0:
		_finish(net)
		return true
	return false

func _away_has(seat: int) -> bool:
	return _away_lists.any(func(list): return list.any(func(e): return e[0] == seat))

func _finish(net) -> void:
	if _mode == "resume":
		if _role == "guest":
			_t.check(_reconnecting_seen, "the dropped client knew it was reconnecting")
			_t.check(_resumed, "and got its seat back")
			_t.check(_restored, "the table was restored for it")
			_t.eq(net.local_seat(), 1, "in the same seat")
			_t.check(not net.can_act() or _my_seat == 1, "it is playing normally again")
		else:
			_t.check(_away_has(1), "the host was told the guest is away")
			_t.eq(_away_lists.back(), [], "and then that they are back")
			_t.eq(_left_names, [], "nobody was reported as having left")
			_t.eq(net.seat_count(), 2, "both players are still seated")
	else:
		_t.check(_away_has(0), "the guest was told the host is away")
		var turn_wait_seen := _away_lists.any(func(list): return list.any(func(e): return e[0] == 0 and e[2] >= 0))
		_t.check(turn_wait_seen, "including how long the table waits on their turn")
		_t.eq(_skips, [[0, 1]], "the away player's turn was skipped to the next seat")
		_t.eq(_left_names, ["Ann"], "after the hold ran out they were reported as gone")
		_t.eq(net.seat_count(), 1, "and the room shrank to one player")
		_t.check(net.is_host(), "the remaining player became the host")
		_t.check(_can_act_after_skip, "the guest could act once the turn was skipped")
	_t.finish()
