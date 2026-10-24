extends SceneTree
## Two roles, chosen by a user argument:
##   stay:  joins as "Anna" and watches.
##   leave: joins as "Ben" a moment later, then disconnects.
## The staying client must be told who left and see the room shrink back to one player.

var _t := TestHelper.new()
var _role := "stay"
var _elapsed := 0.0
var _started := false
var _my_seat := -1
var _left_names: Array[String] = []
var _seat_counts: Array[int] = []

func _process(delta: float) -> bool:
	var net = get_root().get_node("Net")
	if not _started:
		_started = true
		var args := OS.get_cmdline_user_args()
		if args.size() > 0:
			_role = args[0]
		net.connected.connect(func(): net.join_room("auto", "Anna" if _role == "stay" else "Ben"))
		net.seated.connect(func(seat, _rn): _my_seat = seat)
		net.player_left.connect(func(who): _left_names.append(who))
		net.seats_changed.connect(func(count, _cur): _seat_counts.append(count))
		net.start_client("127.0.0.1", net.DEFAULT_PORT)
		return false
	_elapsed += delta
	if _role == "leave":
		if _elapsed > 2.0:
			net.stop_client()
			_t.check(_my_seat == 1, "leaver had the second seat")
			_t.finish()
			return true
	elif _elapsed > 6.0:
		_t.check(_my_seat == 0, "staying client keeps seat 0")
		_t.eq(_left_names, ["Ben"], "the staying client is told who disconnected")
		_t.check(_seat_counts.has(2), "it saw the room grow to two players")
		_t.eq(_seat_counts.back(), 1, "and then shrink back to one")
		_t.eq(net.seat_count(), 1, "seat_count() follows the room")
		_t.check(net.can_act(), "the remaining player is on turn")
		_t.finish()
		return true
	return false
