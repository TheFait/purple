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
signal connect_failed()
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
signal seats_changed(count: int, current_seat: int)   # someone joined or left; the turn order may have shifted
signal player_left(player_name: String)
signal stack_passed(from_seat: int, to_seat: int, count: int)
signal table_restored(cards: Array)   # a snapshot of the stack, for a client that joined or reloaded late
signal diamonds_forever()
signal round_log(text: String)

var _rooms: RoomManager      # server only
var _auto_room: Room         # server only — the iteration-1 default public room

var _my_seat: int = -1           # client only
var _current_turn_seat: int = 0  # client only (mirror of server turn)
var _stack_size: int = 0         # client only (mirror of the server's pool, drives legal_moves)
var _seat_count: int = 0         # client only (mirror of the room's player count)
var _names: Array = []           # client only (every player's name, in seat order)

func start_server(port: int) -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, 64)
	assert(err == OK, "server failed to start on port %d" % port)
	multiplayer.multiplayer_peer = peer
	_rooms = ROOM_MANAGER.new()
	add_child(_rooms)
	_auto_room = _rooms.create_room("Auto Public Room", true)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

## Connect to a server. Returns false (and emits connect_failed) when the address is unusable.
func start_client(ip: String, port: int) -> bool:
	stop_client()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		connect_failed.emit()
		return false
	multiplayer.multiplayer_peer = peer
	if not multiplayer.connected_to_server.is_connected(_on_connected):
		multiplayer.connected_to_server.connect(_on_connected)
		multiplayer.connection_failed.connect(_on_connection_failed)
	return true

## Drop the current connection (used before retrying, or when leaving an online game).
func stop_client() -> void:
	if multiplayer.multiplayer_peer != null and not multiplayer.is_server():
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	_my_seat = -1
	_current_turn_seat = 0
	_stack_size = 0
	_seat_count = 0
	_names = []

func _on_connected() -> void:
	connected.emit()

func _on_connection_failed() -> void:
	connect_failed.emit()

# ---- client helper (sends to server via RPC) ----

func join_room(room_or_code: String, player_name: String) -> void:
	rpc_id(1, "rpc_join_room", room_or_code, player_name)

## Ask the server for the table as it stands now. A UI that appears after the game began
## (or after the scene changed) calls this to catch up; the reply replays as events.
func request_sync() -> void:
	rpc_id(1, "rpc_request_sync")

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
func rpc_request_sync() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var room := _rooms.room_of(sender)
	if room == null or not room.has_meta("engine"):
		return
	rpc_id(sender, "_client_events", _snapshot(room))

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
	if room.has_meta("engine"):
		var existing: GameEngine = room.get_meta("engine")
		existing.seat_count = room.player_count()
		_queue_event(room, "seats", _seats_args(room, existing))
		_flush_events(room)
		return
	var deck := DECK_ENGINE.new()
	deck.load_from_json(DB_PATH, COLLECTION_PATH)
	var engine: GameEngine = GAME_ENGINE.new()
	add_child(engine)
	room.set_meta("engine", engine)
	# Every engine event is buffered and sent to the room as ONE ordered batch per action,
	# so related events (Purple's two cards, a win's card + pool + streak) arrive together.
	engine.card_revealed.connect(func(card: CardData): _queue_event(room, "card", [card.to_dict()]))
	engine.table_cleared.connect(func(): _queue_event(room, "clear", []))
	engine.streak_changed.connect(func(s: int): _queue_event(room, "streak", [s]))
	engine.pool_changed.connect(func(p: int): _queue_event(room, "pool", [p]))
	engine.penalty_triggered.connect(func(s: int, amt: int): _queue_event(room, "penalty", [s, amt]))
	engine.pass_available.connect(func(on: bool): _queue_event(room, "pass", [on]))
	engine.turn_changed.connect(func(s: int): _queue_event(room, "turn", [s]))
	engine.stack_passed.connect(func(f: int, to: int, n: int): _queue_event(room, "passed", [f, to, n]))
	engine.phantoms_added.connect(func(cards: Array): _queue_event(room, "phantoms", [_card_dicts(cards)]))
	engine.diamonds_forever.connect(func(): _queue_event(room, "diamonds", []))
	engine.round_log.connect(func(txt: String): _queue_event(room, "log", [txt]))
	engine.setup(deck, max(1, room.player_count()))
	_queue_event(room, "seats", _seats_args(room, engine))
	_flush_events(room)

## Player count, whose turn it is, and every name in seat order.
func _seats_args(room: Room, engine: GameEngine) -> Array:
	return [room.player_count(), engine.current_seat, room.seat_names()]

func _card_dicts(cards: Array) -> Array:
	var out: Array = []
	for c: CardData in cards:
		out.append(c.to_dict())
	return out

## Buffer one event for the room; _flush_events sends the whole buffer as a single RPC.
func _queue_event(room: Room, kind: String, args: Array) -> void:
	var buffer: Array = room.get_meta("events", [])
	buffer.append([kind, args])
	room.set_meta("events", buffer)

func _flush_events(room: Room) -> void:
	var buffer: Array = room.get_meta("events", [])
	if buffer.is_empty():
		return
	room.set_meta("events", [])
	_broadcast(room, "_client_events", [buffer])

## The table as events a client can replay to catch up: the revealed stack (phantoms
## included), the counters, whose turn it is and the seat count. Never the deck.
func _snapshot(room: Room) -> Array:
	var engine: GameEngine = room.get_meta("engine")
	return [
		["restore", [_card_dicts(engine.table_cards)]],
		["pool", [engine.drink_pool()]],
		["streak", [engine.current_streak]],
		["pass", [engine.can_pass()]],
		["turn", [engine.current_seat]],
		["seats", _seats_args(room, engine)],
	]

func _broadcast(room: Room, method: String, args: Array = []) -> void:
	for pid: int in room.peer_ids():
		callv("rpc_id", [pid, method] + args)

func _on_peer_disconnected(peer_id: int) -> void:
	if _rooms == null:
		return
	var old_room: Room = _rooms.room_of(peer_id)
	var seat := old_room.seat_of(peer_id) if old_room != null else -1
	var leaver_name := old_room.name_of(peer_id) if old_room != null else ""
	var room: Room = _rooms.leave(peer_id)
	# room is null when it was already empty and freed, or peer was unknown.
	# When still occupied and has a running engine, reconcile seat count and
	# turn so the engine never references a vacated seat index.
	if room == null or room.player_count() == 0:
		return
	if not room.has_meta("engine"):
		return
	var engine: GameEngine = room.get_meta("engine")
	# Tell the table who left first, then close the gap in the turn order.
	_queue_event(room, "left", [leaver_name])
	engine.remove_seat(seat)
	_queue_event(room, "seats", _seats_args(room, engine))
	_flush_events(room)
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
	_flush_events(room)

# ---- server -> client: game events ----

## One server action's worth of events, in order. Replayed through the presenter signals.
@rpc("authority", "call_remote", "reliable")
func _client_events(batch: Array) -> void:
	for event: Array in batch:
		_apply_event(String(event[0]), event[1])

func _apply_event(kind: String, args: Array) -> void:
	match kind:
		"card": card_revealed.emit(CardData.from_dict(args[0]))
		"clear": table_cleared.emit()
		"streak": streak_changed.emit(int(args[0]))
		"pool":
			_stack_size = int(args[0])
			pool_changed.emit(_stack_size)
		"penalty": penalty_triggered.emit(int(args[0]), int(args[1]))
		"pass": pass_available.emit(bool(args[0]))
		"turn":
			_current_turn_seat = int(args[0])
			turn_changed.emit(_current_turn_seat)
		"phantoms": phantoms_added.emit(_cards_from(args[0]))
		"restore": table_restored.emit(_cards_from(args[0]))
		"diamonds": diamonds_forever.emit()
		"log": round_log.emit(String(args[0]))
		"seats":
			_seat_count = int(args[0])
			_current_turn_seat = int(args[1])
			_names = args[2]
			seats_changed.emit(_seat_count, _current_turn_seat)
		"passed": stack_passed.emit(int(args[0]), int(args[1]), int(args[2]))
		"left": player_left.emit(String(args[0]))

func _cards_from(dicts: Array) -> Array:
	var cards: Array = []
	for d: Dictionary in dicts:
		cards.append(CardData.from_dict(d))
	return cards

# ---- presenter contract (client) ----

func act_move(move: int) -> void:
	rpc_id(1, "rpc_request_move", move)

func act_pass() -> void:
	rpc_id(1, "rpc_request_pass")

func legal_moves() -> Array[int]:
	return GAME_ENGINE.legal_moves_for(_stack_size)

## The room's player count as the server last announced it (never fewer than the seats
## this client has seen).
func seat_count() -> int:
	return maxi(maxi(_seat_count, 1), maxi(_my_seat, _current_turn_seat) + 1)

## A player's name as the server last announced it ("Player N" until then).
func player_name(seat: int) -> String:
	if seat >= 0 and seat < _names.size():
		return String(_names[seat])
	return "Player %d" % (seat + 1)

## Online, every device is its own seat (unlike hotseat play on one screen).
func is_hotseat() -> bool:
	return false

func can_act() -> bool:
	return _my_seat == _current_turn_seat

func local_seat() -> int:
	return _my_seat
