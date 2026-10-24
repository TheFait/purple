extends SceneTree
## The players row must show exactly one dot per player, growing and shrinking with the room.

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
	var ui = _game.get_node("UI")
	var engine: GameEngine = _game._engine
	ui._show_players(0)
	t.eq(ui._player_dots.size(), 2, "hotseat starts with two players")

	engine.seat_count = 3
	ui._show_players(0)
	t.eq(ui._player_dots.size(), 3, "the row grows when a player joins")

	engine.seat_count = 1
	ui._show_players(0)
	t.eq(ui._player_dots.size(), 1, "the row shrinks when players leave: one player, one icon")

	t.eq(_game.player_name(1), "Player 2", "hotseat players are named by seat")
	t.check(_game.is_hotseat(), "offline play is hotseat")
	t.finish()
	_done = true
	return false
