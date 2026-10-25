extends SceneTree
## One client plays Purple on a fresh table. Both flips must reach it inside a single
## batched RPC, so they surface in the same frame (this is what lets the UI pair them).

var _t := TestHelper.new()
var _elapsed := 0.0
var _started := false
var _my_seat := -1
var _sent := false
var _card_frames: Array[int] = []

func _process(delta: float) -> bool:
	var net = get_root().get_node("Net")
	if not _started:
		_started = true
		net.connected.connect(func(): net.join_room("auto", "Solo"))
		net.seated.connect(func(seat, _rn): _my_seat = seat)
		net.card_revealed.connect(func(_c): _card_frames.append(Engine.get_process_frames()))
		net.start_client("127.0.0.1", net.DEFAULT_PORT)
		return false
	_elapsed += delta
	if _my_seat == 0 and not _sent and _elapsed > 1.0:
		_sent = true
		net.act_move(GameEngine.Move.PURPLE)
	if _elapsed > 4.0:
		_t.check(_my_seat == 0, "client seated at seat 0")
		_t.eq(_card_frames.size(), 2, "Purple reveals exactly two cards")
		if _card_frames.size() == 2:
			_t.eq(_card_frames[0], _card_frames[1], "both Purple cards arrive in the same frame (one batch)")
		_t.finish()
		return true
	return false
