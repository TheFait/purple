extends SceneTree
## Two connected players who never act. The test server uses short idle limits (1.5 s, 1 s,
## 0.8 s), so each is warned and skipped in turn and the first one (Ann, seat 0) is removed
## on her third idle turn. Roles: first (Ann) and second (Bea).

var _t := TestHelper.new()
var _role := "first"
var _elapsed := 0.0
var _started := false
var _my_seat := -1
var _warnings: Array = []
var _skips: Array = []
var _kicked := false
var _kicked_names: Array[String] = []
var _can_act_at_end := false

func _process(delta: float) -> bool:
	var net = get_root().get_node("Net")
	if not _started:
		_started = true
		var args := OS.get_cmdline_user_args()
		if args.size() > 0:
			_role = args[0]
		net.connected.connect(func(): net.join_room("auto", "Ann" if _role == "first" else "Bea"))
		net.seated.connect(func(seat, _rn): _my_seat = seat)
		net.idle_warning.connect(func(seat, secs, strike): _warnings.append([seat, secs, strike]))
		net.turn_skipped.connect(func(f, to): _skips.append([f, to]))
		net.kicked.connect(func(): _kicked = true)
		net.player_kicked.connect(func(who): _kicked_names.append(who))
		net.start_client("127.0.0.1", net.DEFAULT_PORT)
		return false
	_elapsed += delta
	if _elapsed > 13.0:
		if _role == "first":
			_t.check(_kicked, "the player who sat idle three turns in a row was removed")
			_t.check(_warnings.any(func(w): return w[0] == 0 and w[1] >= 0), "and was warned before being skipped")
			_t.check(not _skips.is_empty() and _skips[0] == [0, 1], "the first idle turn was skipped to the next player")
		else:
			_t.check(_warnings.any(func(w): return w[1] >= 0 and w[2] >= 1), "the table was warned, with the strike count rising")
			_t.eq(_skips.slice(0, 3), [[0, 1], [1, 0], [0, 1]], "turns were skipped in order as each player let theirs run out")
			_t.eq(_kicked_names, ["Ann"], "everyone was told who was removed for inactivity")
			_t.eq(net.seat_count(), 1, "the room shrank to one player")
			_t.check(net.can_act(), "and the remaining player is on turn")
		_t.finish()
		return true
	return false
