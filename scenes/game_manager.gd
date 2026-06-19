extends Node2D
class_name GameManager
## OFFLINE single-device presenter. Owns a GameEngine and renders it locally.
## In hotseat play, whoever's turn it is acts on the shared screen, so can_act()
## is always true and we forward moves under the engine's own current_seat.

const CARD_SCENE := preload("res://scenes/card.tscn")

signal card_revealed(card: CardData)
signal table_cleared()
signal streak_changed(streak: int)
signal pool_changed(pool: int)
signal penalty_triggered(seat: int, amount: int)
signal pass_available(is_available: bool)
signal turn_changed(seat: int)
signal round_log(text: String)

@export var table_zone_path: NodePath = ^"UI/Stack"

var _engine: GameEngine
@onready var _table_zone: Node = get_node(table_zone_path)

func _ready() -> void:
	var deck := DeckEngine.new()
	deck.load_from_json("res://assets/database/card_database.json", "res://assets/database/card_collection.json")
	_engine = GameEngine.new()
	add_child(_engine)
	# Forward engine signals to the view, instantiating visuals on reveal.
	_engine.card_revealed.connect(_on_card_revealed)
	_engine.table_cleared.connect(_on_table_cleared)
	_engine.streak_changed.connect(func(s): streak_changed.emit(s))
	_engine.pool_changed.connect(_on_engine_pool_changed)
	_engine.penalty_triggered.connect(func(seat, amt): penalty_triggered.emit(seat, amt))
	_engine.pass_available.connect(func(on): pass_available.emit(on))
	_engine.turn_changed.connect(func(seat): turn_changed.emit(seat))
	_engine.round_log.connect(func(txt): round_log.emit(txt))
	_engine.setup(deck, 2)

# --- presenter contract ---

func act_move(move: int) -> void:
	_engine.submit_move(_engine.current_seat, move)

func act_pass() -> void:
	_engine.request_pass(_engine.current_seat)

func act_ride() -> void:
	_engine.request_ride(_engine.current_seat)

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

func _on_card_revealed(card: CardData) -> void:
	var node: Card = CARD_SCENE.instantiate()
	node.setup_card(card.nice_name, card.rank, _suit_name(card.suit), card.texture_path, card.backface_path)
	node.is_facedown = false
	_table_zone.add_child(node)
	card_revealed.emit(card)

func _on_table_cleared() -> void:
	for child in _table_zone.get_children():
		_table_zone.remove_child(child)
		child.queue_free()
	table_cleared.emit()

func _suit_name(suit: int) -> String:
	return Globals.SUITS.keys()[suit].to_lower()
