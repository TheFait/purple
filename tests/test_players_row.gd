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

	# Players whose connection dropped: a countdown banner and a greyed, pulsing dot.
	engine.seat_count = 2
	ui._show_players(0)
	ui._on_away_list([[1, 47, 14]])
	t.check(ui._away_banner.visible, "the away banner shows")
	t.check(ui._away_banner.text.contains("Player 2 lost connection, holding the seat... 0:47"), "it names the player and the hold time")
	t.check(ui._away_banner.text.contains("waiting for Player 2... 0:14"), "and the wait on their turn")
	t.check(ui._away_tweens.has(ui._player_dots[1]), "the away player's dot pulses")
	t.check(not ui._away_tweens.has(ui._player_dots[0]), "the others do not")
	ui._on_away_list([[1, 47, -1]])
	t.check(not ui._away_banner.text.contains("waiting for"), "no turn wait line when it is not their turn")
	ui._on_away_list([])
	t.check(not ui._away_banner.visible, "the banner hides when everyone is back")
	t.eq(ui._player_dots[1].modulate, Color.WHITE, "and the dot goes back to normal")
	t.check(not ui._away_tweens.has(ui._player_dots[1]), "with no pulse left")

	# Who is up and what they hold, and the idle countdown.
	engine.seat_count = 2
	ui._show_players(0)
	ui._active_seat = 0
	ui._pool_shown = 0
	ui._refresh_holder()
	t.eq(ui._holder_label.text, "Player 1 to guess", "an empty stack says who guesses")
	ui._pool_shown = 3
	ui._refresh_holder()
	t.eq(ui._holder_label.text, "Player 1 is holding the stack of 3 cards", "a stack names who holds it")
	ui._pool_shown = 1
	ui._refresh_holder()
	t.eq(ui._holder_label.text, "Player 1 is holding the stack of 1 card", "one card is singular")
	ui._on_idle_warning(0, 8, 0)
	t.eq(ui._holder_label.text, "Player 1 will be skipped in 0:08", "an idle warning counts down to a skip")
	ui._on_idle_warning(0, 5, 2)
	t.eq(ui._holder_label.text, "Player 1 will be REMOVED in 0:05", "the third strike warns of removal")
	ui._on_idle_warning(-1, -1, 0)
	t.eq(ui._holder_label.text, "Player 1 is holding the stack of 1 card", "clearing the warning restores the normal text")

	t.eq(_game.player_name(1), "Player 2", "hotseat players are named by seat")
	t.check(_game.is_hotseat(), "offline play is hotseat")
	t.finish()
	_done = true
	return false
