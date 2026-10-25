extends SceneTree
## Three roles, chosen by a user argument:
##   host:     creates a private room, tries to start alone (refused), starts with the guest,
##             ends the game, then leaves.
##   guest:    joins by the (lower-cased) invite code, tries to start (refused), watches the
##             game start and end, and ends up as the new host.
##   intruder: guesses wrong codes until it is throttled.

const CODE_FILE := "user://pp_lobby_code.txt"

var _t := TestHelper.new()
var _role := "host"
var _elapsed := 0.0
var _started := false
var _my_seat := -1
var _code := ""
var _infos: Array[Dictionary] = []
var _notices: Array[String] = []
var _failures: Array[String] = []
var _tried_alone := false
var _tried_start := false
var _guest_tried := false
var _playing_at := -1.0
var _ended := false
var _left := false
var _joined := false
var _wrong_sent := 0

func _process(delta: float) -> bool:
	var net = get_root().get_node("Net")
	if not _started:
		_started = true
		var args := OS.get_cmdline_user_args()
		if args.size() > 0:
			_role = args[0]
		net.seated.connect(func(seat, _rn): _my_seat = seat)
		net.lobby_changed.connect(func(info): _infos.append(info))
		net.notice.connect(func(text): _notices.append(text))
		net.join_failed.connect(func(reason): _failures.append(reason))
		match _role:
			"host":
				DirAccess.remove_absolute(ProjectSettings.globalize_path(CODE_FILE))
				net.connected.connect(func(): net.create_room("", false, "Ann"))
				net.start_client("127.0.0.1", net.DEFAULT_PORT)
			"intruder":
				net.connected.connect(func(): net.join_room("QQQQQ", "Mallory"))
				net.start_client("127.0.0.1", net.DEFAULT_PORT)
		return false
	_elapsed += delta
	match _role:
		"host": return _host_step(net)
		"guest": return _guest_step(net)
		"intruder": return _intruder_step(net)
	return false

func _last() -> Dictionary:
	return _infos.back() if not _infos.is_empty() else {}

func _host_step(net) -> bool:
	if _code == "" and not _infos.is_empty():
		_code = _infos[0].code
		var f := FileAccess.open(CODE_FILE, FileAccess.WRITE)
		f.store_string(_code)
		f.close()
	if not _tried_alone and _elapsed > 1.5 and _code != "":
		_tried_alone = true
		net.request_start()   # only one player: refused
	var info := _last()
	if info.get("names", []).size() == 2 and info.get("state") == "lobby" and not _tried_start and _playing_at < 0.0:
		_tried_start = true
		net.request_start()
	if info.get("state") == "playing" and _playing_at < 0.0:
		_playing_at = _elapsed
	if _playing_at >= 0.0 and not _ended and _elapsed - _playing_at > 1.0:
		_ended = true
		net.request_end()
	if _ended and info.get("state") == "lobby" and not _left and _elapsed - _playing_at > 2.5:
		_left = true
		net.leave_room()
	if _elapsed > 14.0:
		_t.eq(_infos[0].room, "Ann's table", "an unnamed room is called after its host")
		_t.eq(_code.length(), 5, "a private room has a five character invite code")
		_t.check(_notices.size() >= 1 and _notices[0].contains("at least 2"), "starting alone is refused with a reason")
		_t.check(_infos.any(func(i): return i.state == "playing" and i.names.size() == 2), "the game starts with both players")
		var first_playing := _infos.find_custom(func(i): return i.state == "playing")
		var back_in_lobby := false
		for k in range(first_playing + 1, _infos.size()):
			if _infos[k].state == "lobby" and _infos[k].names.size() == 2:
				back_in_lobby = true
		_t.check(_ended and first_playing >= 0 and back_in_lobby, "ending the game returns the room to the lobby")
		_t.check(_left and net.room_info.is_empty(), "leaving the room clears the host's room")
		_t.finish()
		return true
	return false

func _guest_step(net) -> bool:
	if not _joined:
		if FileAccess.file_exists(CODE_FILE) and _elapsed > 1.0:
			_code = FileAccess.get_file_as_string(CODE_FILE).strip_edges()
			if _code.length() == 5:
				_joined = true
				net.connected.connect(func(): net.join_room(_code.to_lower(), "Bea"))
				net.start_client("127.0.0.1", net.DEFAULT_PORT)
		return false
	var info := _last()
	if not _guest_tried and info.get("names", []).size() == 2 and info.get("state") == "lobby":
		_guest_tried = true
		net.request_start()   # not the host: refused
	if _elapsed > 14.0:
		_t.check(_my_seat == 0 or _my_seat == 1, "the guest was seated")
		_t.check(_infos.size() > 0 and _infos[0].names == ["Ann", "Bea"], "joining by a lower-case code works and shows both names")
		_t.check(_notices.size() >= 1 and _notices[0].contains("host"), "a guest cannot start the game")
		_t.check(_infos.any(func(i): return i.state == "playing"), "the guest sees the game start")
		_t.eq(_last().get("names"), ["Bea"], "after the host leaves only the guest is listed")
		_t.eq(_last().get("host"), 0, "and the guest has become the host")
		_t.check(net.is_host(), "is_host() agrees")
		_t.finish()
		return true
	return false

func _intruder_step(net) -> bool:
	if _failures.size() > _wrong_sent and _wrong_sent < 6:
		_wrong_sent += 1
		net.join_room("QQQQQ", "Mallory")
	if _elapsed > 6.0:
		_t.check(_failures.size() >= 6, "six wrong guesses all get an answer")
		if _failures.size() >= 6:
			_t.eq(_failures[0], "room full or not found", "a wrong code is refused")
			_t.check(_failures[5].contains("too many wrong codes"), "the sixth guess in a minute is throttled")
		_t.finish()
		return true
	return false
