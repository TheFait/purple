extends SceneTree

var _t := TestHelper.new()
var _elapsed := 0.0
var _my_seat := -1
var _moves_made := 0
var _saw_events := false
var _started := false

func _initialize() -> void:
	pass

func _process(delta: float) -> bool:
	if not _started:
		_started = true
		var net = get_root().get_node("Net")
		net.connected.connect(func(): net.join_room("auto", "Player"))
		net.seated.connect(func(seat, _rn):
			var first_time := _my_seat < 0
			_my_seat = seat
			print("CLIENT seated seat=%d" % seat)
			if first_time:
				net.request_sync())   # like the real UI: catch up with a table already in play
		# A loss keeps the turn with the same player, so react to table events, not just turn changes.
		net.pool_changed.connect(func(_p): _on_event(net))
		net.turn_changed.connect(func(_s): _on_event(net))
		net.start_client("127.0.0.1", net.DEFAULT_PORT)
		return false
	_elapsed += delta
	if _elapsed > 8.0:
		_t.check(_my_seat >= 0, "client seated")
		_t.check(_saw_events, "client saw game events from server")
		_t.finish()
		return true
	return false

func _on_event(net) -> void:
	_saw_events = true
	if net.can_act() and _moves_made < 8:
		_moves_made += 1
		var moves: Array[int] = net.legal_moves()
		net.act_move(moves[_moves_made % moves.size()])
