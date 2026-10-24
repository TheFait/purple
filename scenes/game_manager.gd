extends Node2D
class_name GameManager
## OFFLINE single-device presenter. Owns a GameEngine and forwards its events to the view.
## In hotseat play, whoever's turn it is acts on the shared screen, so can_act()
## is always true and we forward moves under the engine's own current_seat.
## Card visuals live in the UI/Table (driven by card_revealed's CardData), not here.

signal card_revealed(card: CardData)
signal table_cleared()
signal streak_changed(streak: int)
signal pool_changed(pool: int)
signal penalty_triggered(seat: int, amount: int)
signal pass_available(is_available: bool)
signal turn_changed(seat: int)
signal seats_changed(count: int, current_seat: int)   # never emitted offline; part of the shared presenter contract
signal player_left(player_name: String)                       # likewise
signal stack_passed(from_seat: int, to_seat: int, count: int)
signal away_changed(list: Array)                               # never emitted offline; part of the shared presenter contract
signal turn_skipped(from_seat: int, to_seat: int)              # likewise
signal table_restored(cards: Array)   # never emitted offline; part of the shared presenter contract
signal phantoms_added(cards: Array)
signal diamonds_forever()
signal round_log(text: String)

var _engine: GameEngine

func _ready() -> void:
	var deck := DeckEngine.new()
	deck.load_from_json("res://assets/database/card_database.json", "res://assets/database/card_collection.json")
	_engine = GameEngine.new()
	add_child(_engine)
	# Forward engine signals to the view.
	_engine.card_revealed.connect(func(card): card_revealed.emit(card))
	_engine.table_cleared.connect(func(): table_cleared.emit())
	_engine.streak_changed.connect(func(s): streak_changed.emit(s))
	_engine.pool_changed.connect(_on_engine_pool_changed)
	_engine.penalty_triggered.connect(func(seat, amt): penalty_triggered.emit(seat, amt))
	_engine.pass_available.connect(func(on): pass_available.emit(on))
	_engine.turn_changed.connect(func(seat): turn_changed.emit(seat))
	_engine.phantoms_added.connect(func(cards): phantoms_added.emit(cards))
	_engine.diamonds_forever.connect(func(): diamonds_forever.emit())
	_engine.stack_passed.connect(func(f, to, n): stack_passed.emit(f, to, n))
	_engine.round_log.connect(func(txt): round_log.emit(txt))
	_engine.setup(deck, 2)

# --- presenter contract ---

func act_move(move: int) -> void:
	_engine.submit_move(_engine.current_seat, move)

func act_pass() -> void:
	_engine.request_pass(_engine.current_seat)

func legal_moves() -> Array[int]:
	return _engine.legal_moves()

func seat_count() -> int:
	return _engine.seat_count

## Hotseat players have no names, only seats.
func player_name(seat: int) -> String:
	return "Player %d" % (seat + 1)

## One screen is shared by every player, so every message is shown to whoever holds the device.
func is_hotseat() -> bool:
	return true

func can_act() -> bool:
	return true

func local_seat() -> int:
	return _engine.current_seat

func current_streak() -> int:
	return _engine.current_streak

func drink_pool() -> int:
	return _engine.drink_pool()

# --- rendering ---

func _on_engine_pool_changed(p: int) -> void:
	Globals.cards_in_stack = p
	pool_changed.emit(p)
