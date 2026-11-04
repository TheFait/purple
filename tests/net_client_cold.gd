extends SceneTree
## A game is in progress, the app "crashes" (the connection just vanishes, nothing is cleaned
## up), and a freshly started app rejoins its seat from the session it saved on disk.

var _t := TestHelper.new()
var _elapsed := 0.0
var _started := false
var _my_seat := -1
var _saved_before_crash := {}
var _crashed := false
var _resumed := false
var _restored := false
var _expired := false
var _seat_after := -2

func _process(delta: float) -> bool:
	var net = get_root().get_node("Net")
	if not _started:
		_started = true
		OnlineSettings.clear_session()
		net.connected.connect(func(): net.join_room("auto", "Cold"))
		net.seated.connect(func(seat, _rn): _my_seat = seat)
		net.resumed.connect(func(): _resumed = true)
		net.table_restored.connect(func(_c): _restored = true)
		net.session_expired.connect(func(): _expired = true)
		net.start_client("127.0.0.1", net.DEFAULT_PORT)
		return false
	_elapsed += delta
	if not _crashed and _my_seat >= 0 and _elapsed > 1.5:
		_crashed = true
		_saved_before_crash = OnlineSettings.load_session()
		_t.check(not _saved_before_crash.is_empty(), "joining a game saved a session on disk")
		_t.eq(_saved_before_crash.get("token", ""), net.session_token, "it holds the token the server gave")
		# The app dies: the socket goes away and every bit of in-memory state is lost.
		net.multiplayer.multiplayer_peer.close()
		net.multiplayer.multiplayer_peer = null
		net.session_token = ""
		net.room_info = {}
		net._my_seat = -1
		net._reset_table_mirrors()
		_elapsed = 1.5   # (the clock below counts from the "restart")
	if _crashed and not net.is_reconnecting() and not _resumed and _elapsed > 2.0 and _seat_after == -2:
		_seat_after = -1
		# A fresh start: nothing in memory, only what is on disk.
		_t.check(net.resume_saved(), "a saved session can be resumed")
	if _crashed and _resumed and _seat_after == -1 and _elapsed > 4.0:
		_seat_after = net.local_seat()
	if _elapsed > 9.0:
		_t.check(_resumed, "the server gave the seat back")
		_t.check(_restored, "and replayed the table")
		_t.check(not _expired, "without the session expiring")
		_t.eq(net.local_seat(), 0, "in the same seat")
		_t.check(OnlineSettings.has_session(), "and the session is still saved while in the game")
		OnlineSettings.clear_session()
		_t.check(not OnlineSettings.has_session(), "a cleared session is gone")
		_t.finish()
		return true
	return false
