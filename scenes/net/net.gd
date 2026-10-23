extends Node
## Shared network node present in BOTH server and client (autoload => same path
## `/root/Net`, which Godot RPC requires). Branches on multiplayer.is_server().

const DEFAULT_PORT := 9000
const ROOM_MANAGER := preload("res://server/room_manager.gd")
const GAME_ENGINE  := preload("res://scenes/engine/game_engine.gd")
const DECK_ENGINE  := preload("res://scenes/engine/deck_engine.gd")
const DB_PATH         := "res://assets/database/card_database.json"
const COLLECTION_PATH := "res://assets/database/card_collection.json"

# Client-facing signals
signal connected()
signal seated(seat: int, room_name: String)
signal join_failed(reason: String)
signal public_rooms(list: Array)

# Presenter contract (mirrors GameManager so ui.gd binds to Net unchanged)
signal card_revealed(card: CardData)
signal table_cleared()
signal streak_changed(streak: int)
signal pool_changed(pool: int)
signal penalty_triggered(seat: int, amount: int)
signal pass_available(is_available: bool)
signal turn_changed(seat: int)
signal phantoms_added(cards: Array)
signal diamonds_forever()
signal round_log(text: String)

var _rooms: RoomManager      # server only
var _auto_room: Room         # server only — the iteration-1 default public room

var _my_seat: int = -1           # client only
var _current_turn_seat: int = 0  # client only (mirror of server turn)
var _stack_size: int = 0         # client only (mirror of the server's pool, drives legal_moves)

func start_server(port: int) -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, 64)
	assert(err == OK, "server failed to start on port %d" % port)
	multiplayer.multiplayer_peer = peer
	_rooms = ROOM_MANAGER.new()
	add_child(_rooms)
	_auto_room = _rooms.create_room("Auto Public Room", true)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

func start_client(ip: String, port: int) -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	assert(err == OK, "client failed to connect to %s:%d" % [ip, port])
	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(func(): connected.emit())

# ---- client helper (sends to server via RPC) ----

func join_room(room_or_code: String, player_name: String) -> void:
	rpc_id(1, "rpc_join_room", room_or_code, player_name)

# ---- client -> server ----

@rpc("any_peer", "call_remote", "reliable")
func rpc_join_room(room_or_code: String, player_name: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	# Iteration 1: "auto" routes to the default public room.
	var target := _auto_room.id if room_or_code == "auto" else room_or_code
	var room := _rooms.join(sender, target, player_name)
	if room == null:
		rpc_id(sender, "_client_join_failed", "room full or not found")
		return
	rpc_id(sender, "_client_seated", room.seat_of(sender), room.room_name)
	_ensure_engine(room)

@rpc("any_peer", "call_remote", "reliable")
func rpc_create_room(name: String, is_public: bool) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var room := _rooms.create_room(name, is_public)
	_rooms.join(sender, room.id, "Host")
	rpc_id(sender, "_client_seated", room.seat_of(sender), room.room_name)
	_ensure_engine(room)

@rpc("any_peer", "call_remote", "reliable")
func rpc_list_public_rooms() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	rpc_id(sender, "_client_public_rooms", _rooms.list_public())

# ---- server -> client ----

@rpc("authority", "call_remote", "reliable")
func _client_seated(seat: int, room_name: String) -> void:
	_my_seat = seat
	seated.emit(seat, room_name)

@rpc("authority", "call_remote", "reliable")
func _client_join_failed(reason: String) -> void:
	join_failed.emit(reason)

@rpc("authority", "call_remote", "reliable")
func _client_public_rooms(list: Array) -> void:
	public_rooms.emit(list)

# ---- server internals ----

func _ensure_engine(room: Room) -> void:
	# Iteration-1 behavior: create engine on first join, then expand seat_count
	# as more players join so turn rotation stays live.
	# Late-joiner full state-sync (deck position, streak, pool) is iteration 2.
	if room.has_meta("engine"):
		var engine: GameEngine = room.get_meta("engine")
		engine.seat_count = room.player_count()
		return
	var deck := DECK_ENGINE.new()
	deck.load_from_json(DB_PATH, COLLECTION_PATH)
	var engine: GameEngine = GAME_ENGINE.new()
	add_child(engine)
	room.set_meta("engine", engine)
	# Fan out every engine event to all peers in THIS room.
	engine.card_revealed.connect(func(card: CardData): _broadcast(room, "_client_card_revealed", [card.to_dict()]))
	engine.table_cleared.connect(func(): _broadcast(room, "_client_table_cleared", []))
	engine.streak_changed.connect(func(s: int): _broadcast(room, "_client_streak", [s]))
	engine.pool_changed.connect(func(p: int): _broadcast(room, "_client_pool", [p]))
	engine.penalty_triggered.connect(func(s: int, amt: int): _broadcast(room, "_client_penalty", [s, amt]))
	engine.pass_available.connect(func(on: bool): _broadcast(room, "_client_pass_available", [on]))
	engine.turn_changed.connect(func(s: int): _broadcast(room, "_client_turn", [s]))
	engine.phantoms_added.connect(func(cards: Array):
		_broadcast(room, "_client_phantoms", [cards.map(func(c: CardData) -> Dictionary: return c.to_dict())]))
	engine.diamonds_forever.connect(func(): _broadcast(room, "_client_diamonds", []))
	engine.round_log.connect(func(txt: String): _broadcast(room, "_client_log", [txt]))
	engine.setup(deck, max(1, room.player_count()))

func _broadcast(room: Room, method: String, args: Array = []) -> void:
	for pid: int in room.peer_ids():
		callv("rpc_id", [pid, method] + args)

func _on_peer_disconnected(peer_id: int) -> void:
	if _rooms == null:
		return
	var room: Room = _rooms.leave(peer_id)
	# room is null when it was already empty and freed, or peer was unknown.
	# When still occupied and has a running engine, reconcile seat count and
	# turn so the engine never references a vacated seat index.
	if room == null or room.player_count() == 0:
		return
	if not room.has_meta("engine"):
		return
	var engine: GameEngine = room.get_meta("engine")
	engine.reconcile_seats(room.player_count())
	# Re-broadcast each remaining peer's seat so cached _my_seat stays valid
	# after remove_seat re-packed the indices.
	for pid: int in room.peer_ids():
		rpc_id(pid, "_client_seated", room.seat_of(pid), room.room_name)

# ---- server game RPCs (move/pass/ride) ----

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_move(move: int) -> void:
	if not multiplayer.is_server():
		return
	_route_action(multiplayer.get_remote_sender_id(), "move", move)

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_pass() -> void:
	if not multiplayer.is_server():
		return
	_route_action(multiplayer.get_remote_sender_id(), "pass", 0)

func _route_action(sender: int, kind: String, move: int) -> void:
	var room: Room = _rooms.room_of(sender)
	if room == null or not room.has_meta("engine"):
		return
	var engine: GameEngine = room.get_meta("engine")
	var seat := room.seat_of(sender)  # the engine itself rejects wrong-seat calls
	match kind:
		"move": engine.submit_move(seat, move)
		"pass": engine.request_pass(seat)

# ---- server -> client: game events ----

@rpc("authority", "call_remote", "reliable")
func _client_card_revealed(card_dict: Dictionary) -> void:
	card_revealed.emit(CardData.from_dict(card_dict))

@rpc("authority", "call_remote", "reliable")
func _client_table_cleared() -> void:
	table_cleared.emit()

@rpc("authority", "call_remote", "reliable")
func _client_streak(s: int) -> void:
	streak_changed.emit(s)

@rpc("authority", "call_remote", "reliable")
func _client_pool(p: int) -> void:
	_stack_size = p
	pool_changed.emit(p)

@rpc("authority", "call_remote", "reliable")
func _client_phantoms(card_dicts: Array) -> void:
	var cards: Array = []
	for d: Dictionary in card_dicts:
		cards.append(CardData.from_dict(d))
	phantoms_added.emit(cards)

@rpc("authority", "call_remote", "reliable")
func _client_diamonds() -> void:
	diamonds_forever.emit()

@rpc("authority", "call_remote", "reliable")
func _client_penalty(seat: int, amount: int) -> void:
	penalty_triggered.emit(seat, amount)

@rpc("authority", "call_remote", "reliable")
func _client_pass_available(on: bool) -> void:
	pass_available.emit(on)

@rpc("authority", "call_remote", "reliable")
func _client_turn(seat: int) -> void:
	_current_turn_seat = seat
	turn_changed.emit(seat)

@rpc("authority", "call_remote", "reliable")
func _client_log(txt: String) -> void:
	round_log.emit(txt)

# ---- presenter contract (client) ----

func act_move(move: int) -> void:
	rpc_id(1, "rpc_request_move", move)

func act_pass() -> void:
	rpc_id(1, "rpc_request_pass")

func legal_moves() -> Array[int]:
	return GAME_ENGINE.legal_moves_for(_stack_size)

## The server does not broadcast the player count yet (Iteration 2), so infer at least
## the seats this client has seen; the players row grows as higher seats take a turn.
func seat_count() -> int:
	return maxi(2, maxi(_my_seat, _current_turn_seat) + 1)

func can_act() -> bool:
	return _my_seat == _current_turn_seat

func local_seat() -> int:
	return _my_seat
