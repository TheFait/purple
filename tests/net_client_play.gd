extends SceneTree

var _t := TestHelper.new()
var _elapsed := 0.0
var _my_seat := -1
var _moves_made := 0
var _saw_turn := false
var _started := false

func _initialize() -> void:
	pass

func _process(delta: float) -> bool:
	if not _started:
		_started = true
		var net = get_root().get_node("Net")
		net.connected.connect(func(): net.join_room("auto", "Player"))
		net.seated.connect(func(seat, _rn):
			_my_seat = seat
			print("CLIENT seated seat=%d" % seat))
		net.turn_changed.connect(_on_turn.bind(net))
		net.pass_available.connect(func(on):
			if on and net.can_act():
				net.act_ride())
		net.start_client("127.0.0.1", net.DEFAULT_PORT)
		return false
	_elapsed += delta
	if _elapsed > 8.0:
		_t.check(_my_seat >= 0, "client seated")
		_t.check(_saw_turn, "client saw turn events from server")
		_t.finish()
		return true
	return false

func _on_turn(seat: int, net) -> void:
	_saw_turn = true
	print("CLIENT turn=%d mine=%d" % [seat, _my_seat])
	if seat == _my_seat and _moves_made < 8:
		_moves_made += 1
		net.act_move(_moves_made % 6)
