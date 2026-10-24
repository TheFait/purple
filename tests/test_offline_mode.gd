extends SceneTree

var _game: Node
var _done := false

func _initialize() -> void:
	seed(7)
	_game = load("res://scenes/game.tscn").instantiate()
	get_root().add_child(_game)

func _process(_d: float) -> bool:
	if _done:
		return true
	if _game == null or not _game.is_node_ready():
		return false
	var t := TestHelper.new()
	# Offline presenter is always actionable (hotseat).
	t.check(_game.can_act(), "offline can_act true")
	t.eq(_game.drink_pool(), 0, "stack starts empty")
	var seat0: int = _game.local_seat()
	# Drive 20 moves through the presenter API (illegal ones are rejected); never crash.
	for i in range(20):
		_game.act_move(i % 8)
		t.check(_game.drink_pool() >= 0, "pool >= 0 (i=%d)" % i)
	t.finish()
	_done = true
	return false
