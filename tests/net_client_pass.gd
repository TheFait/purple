extends SceneTree
## Two roles, chosen by a user argument:
##   passer: joins as "Ann" and keeps guessing until it can pass, then passes.
##   other:  joins as "Bea" and watches.
## Both must be told who passed to whom, and every client must know both names.

var _t := TestHelper.new()
var _role := "passer"
var _elapsed := 0.0
var _started := false
var _my_seat := -1
var _last_try := -1.0
var _can_pass := false
var _passed := false
var _events: Array = []
var _local_seat_at_pass := -2
var _names_at_pass: Array[String] = []

func _process(delta: float) -> bool:
	var net = get_root().get_node("Net")
	if not _started:
		_started = true
		var args := OS.get_cmdline_user_args()
		if args.size() > 0:
			_role = args[0]
		net.connected.connect(func(): net.join_room("auto", "Ann" if _role == "passer" else "Bea"))
		net.seated.connect(func(seat, _rn): _my_seat = seat)
		net.pass_available.connect(func(on): _can_pass = on)
		net.stack_passed.connect(func(f, to, n):
			_events.append([f, to, n])
			_local_seat_at_pass = net.local_seat()
			_names_at_pass = [net.player_name(0), net.player_name(1)])
		net.start_client("127.0.0.1", net.DEFAULT_PORT)
		return false
	_elapsed += delta
	if _role == "passer" and _my_seat == 0 and _elapsed > 3.0 and _events.is_empty() and net.can_act():
		if _can_pass:
			if not _passed:
				_passed = true
				net.act_pass()
		elif _elapsed - _last_try > 0.25:
			_last_try = _elapsed
			var moves: Array[int] = net.legal_moves()
			net.act_move(moves[randi() % 3] if moves.size() >= 3 else moves[0])   # Red / Black / Purple
	if _elapsed > 40.0 or (not _events.is_empty() and _elapsed > 3.0 and _elapsed - _last_try > 1.0):
		_t.check(_events.size() == 1, "the pass reached this client exactly once")
		if _events.size() == 1:
			_t.eq(_events[0][0], 0, "from seat 0")
			_t.eq(_events[0][1], 1, "to seat 1")
			_t.check(_events[0][2] >= 3, "the stack had at least the 3 cards needed to pass")
		_t.eq(_names_at_pass, ["Ann", "Bea"], "both players' names are known when the pass arrives")
		_t.eq(_local_seat_at_pass, 0 if _role == "passer" else 1, "this client knows which seat is its own")
		_t.finish()
		return true
	return false
