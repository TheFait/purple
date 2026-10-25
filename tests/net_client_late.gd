extends SceneTree
## Two roles, chosen by a user argument:
##   first: joins, makes one guess, stays.
##   late:  joins a few seconds later, asks for a snapshot, and checks it matches the table.

var _t := TestHelper.new()
var _role := "first"
var _elapsed := 0.0
var _started := false
var _my_seat := -1
var _last_try := -1.0
var _pool := 0
var _synced := false
var _restored: Array = []
var _got_restore := false
var _pool_after_restore := -1

func _process(delta: float) -> bool:
	var net = get_root().get_node("Net")
	if not _started:
		_started = true
		var args := OS.get_cmdline_user_args()
		if args.size() > 0:
			_role = args[0]
		net.connected.connect(func(): net.join_room("auto", _role))
		net.seated.connect(func(seat, _rn): _my_seat = seat)
		net.table_restored.connect(func(cards): _restored = cards; _got_restore = true)
		net.pool_changed.connect(func(p): _pool = p)
		net.pool_changed.connect(func(p): if _got_restore and _pool_after_restore < 0: _pool_after_restore = p)
		net.start_client("127.0.0.1", net.DEFAULT_PORT)
		return false
	_elapsed += delta
	if _role == "first":
		# Keep guessing Red until a guess is right, so the table has cards for the snapshot.
		if _my_seat == 0 and _pool == 0 and _elapsed > 1.0 and _elapsed - _last_try > 0.25 and net.can_act():
			_last_try = _elapsed
			net.act_move(GameEngine.Move.RED)
		if _elapsed > 9.0:
			_t.check(_my_seat == 0, "first client seated at seat 0")
			_t.finish()
			return true
	else:
		if _my_seat >= 0 and not _synced:
			_synced = true
			net.request_sync()
		if _elapsed > 4.0:
			_t.check(_my_seat == 1, "late client takes the next seat")
			_t.check(_got_restore, "late client receives a table snapshot")
			_t.eq(_restored.size(), _pool_after_restore, "restored stack size matches the pool counter that follows it")
			_t.check(_restored.size() >= 1, "the snapshot carries real cards")
			_t.eq(net.seat_count(), 2, "late client learns the room has two players")
			_t.check(not net.can_act(), "late client is not on turn")
			_t.finish()
			return true
	return false
