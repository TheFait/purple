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
	t.check(_game.drink_pool() >= 1, "pool seeded")
	var seat0: int = _game.local_seat()
	# Drive 20 moves through the presenter API; never crash, pool stays >= 1.
	for i in range(20):
		if _game.current_streak() >= 3:
			_game.act_ride()
		_game.act_move(i % 6)
		t.check(_game.drink_pool() >= 1, "pool >= 1 (i=%d)" % i)
	t.finish()
	_done = true
	return false
