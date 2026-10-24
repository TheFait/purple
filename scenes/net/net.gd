extends Node
## Shared network node present in BOTH server and client (autoload => same path
## `/root/Net`, which Godot RPC requires). Branches on multiplayer.is_server().

const DEFAULT_PORT := 9000
const ROOM_MANAGER := preload("res://server/room_manager.gd")
const GAME_ENGINE  := preload("res://scenes/engine/game_engine.gd")
const DECK_ENGINE  := preload("res://scenes/engine/deck_engine.gd")
const JOIN_THROTTLE := preload("res://server/join_throttle.gd")
const MAX_ROOMS := 200
const ROOM_NAME_MAX := 24
const DB_PATH         := "res://assets/database/card_database.json"
const COLLECTION_PATH := "res://assets/database/card_collection.json"

# Client-facing signals
signal connected()
signal connect_failed()
signal connection_lost()                 # the server went away after we had connected
signal lobby_changed(info: Dictionary)   # who is in the room, who hosts, and whether a game is running
signal left_room()
signal notice(text: String)              # a refusal worth showing ("only the host can start")
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
var _auto_room: Room         # server only — the always-open public table
var _throttle: JoinThrottle  # server only — slows down join-code guessing

## Server only, set before start_server: start the open table's game as soon as someone sits
## down (the lobby is skipped). The automated tests use this; a real server leaves it off.
var auto_start_open_table: bool = false

var room_info: Dictionary = {}   # client only — the last lobby info the server sent

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
	_auto_room = _rooms.create_room("Open Table", true, true)
	_auto_room.auto_start = auto_start_open_table
	_throttle = JOIN_THROTTLE.new()
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
		multiplayer.server_disconnected.connect(_on_server_disconnected)
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
	room_info = {}

func _on_connected() -> void:
	connected.emit()

func _on_connection_failed() -> void:
	connect_failed.emit()

func _on_server_disconnected() -> void:
	stop_client()
	connection_lost.emit()

## Forget the table (a lobby, a left room, a lost connection): its mirrors are stale.
func _reset_table_mirrors() -> void:
	_current_turn_seat = 0
	_stack_size = 0
	_seat_count = 0
	_names = []

# ---- client helpers (send to the server) ----

## True while connected to a server. (With no connection Godot still reports its built-in
## offline peer as "connected", so that one does not count.)
func is_online() -> bool:
	var peer := multiplayer.multiplayer_peer
	if peer == null or peer is OfflineMultiplayerPeer:
		return false
	return peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

func join_room(room_or_code: String, player_name: String) -> void:
	rpc_id(1, "rpc_join_room", room_or_code, player_name)

## Make a room and sit in it as its host. Public rooms show in the browser; private ones
## are joined with the invite code the lobby info carries.
func create_room(room_name: String, is_public: bool, player_name: String) -> void:
	rpc_id(1, "rpc_create_room", room_name, is_public, player_name)

func list_public_rooms() -> void:
	rpc_id(1, "rpc_list_public_rooms")

func leave_room() -> void:
	rpc_id(1, "rpc_leave_room")

## Host only: start the game once enough players are in.
func request_start() -> void:
	rpc_id(1, "rpc_start_game")

## Host only: stop the game and take everyone back to the lobby.
func request_end() -> void:
	rpc_id(1, "rpc_end_game")

## Ask the server for the table as it stands now. A UI that appears after the game began
## (or after the scene changed) calls this to catch up; the reply replays as events.
func request_sync() -> void:
	rpc_id(1, "rpc_request_sync")

func is_host() -> bool:
	return _my_seat >= 0 and int(room_info.get("host", -1)) == _my_seat

# ---- client -> server ----

@rpc("any_peer", "call_remote", "reliable")
func rpc_join_room(room_or_code: String, player_name: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var now := Time.get_ticks_msec()
	if _rooms.room_of(sender) != null:
		rpc_id(sender, "_client_join_failed", "already in a room")
		return
	if _throttle.blocked(sender, now):
		rpc_id(sender, "_client_join_failed", "too many wrong codes, try again in %d seconds" % _throttle.seconds_left(sender, now))
		return
	# "auto" is the always-open public table.
	var target := _auto_room.id if room_or_code.strip_edges() == "auto" else room_or_code
	var room := _rooms.join(sender, target, player_name)
	if room == null:
		_throttle.record_failure(sender, now)
		rpc_id(sender, "_client_join_failed", "room full or not found")
		return
	if room.state == Room.State.LOBBY and room.auto_start:
		_start_game(room)
	elif room.state == Room.State.PLAYING:
		_grow_engine(room)   # joining a running game: take the last seat
	_announce_room(room)

@rpc("any_peer", "call_remote", "reliable")
func rpc_create_room(room_name: String, is_public: bool, player_name: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if _rooms.room_of(sender) != null:
		rpc_id(sender, "_client_join_failed", "already in a room")
		return
	if _rooms.room_count() >= MAX_ROOMS:
		rpc_id(sender, "_client_join_failed", "the server is full, try again later")
		return
	var clean_name := Room.clean_text(room_name).left(ROOM_NAME_MAX).strip_edges()
	var room := _rooms.create_room(clean_name if not clean_name.is_empty() else "Table", is_public)
	_rooms.seat_player(room, sender, player_name)
	if clean_name.is_empty():
		room.room_name = "%s's table" % room.name_of(sender)
	_announce_room(room)

@rpc("any_peer", "call_remote", "reliable")
func rpc_leave_room() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	_remove_player(sender)
	rpc_id(sender, "_client_left_room")

@rpc("any_peer", "call_remote", "reliable")
func rpc_start_game() -> void:
	if not multiplayer.is_server():
		return
	var room := _host_room(multiplayer.get_remote_sender_id(), "Only the host can start the game.")
	if room == null or room.state != Room.State.LOBBY:
		return
	if not room.can_start():
		rpc_id(room.host_peer, "_client_notice", "Need at least %d players to start." % Room.MIN_PLAYERS)
		return
	_start_game(room)
	_announce_room(room)

@rpc("any_peer", "call_remote", "reliable")
func rpc_end_game() -> void:
	if not multiplayer.is_server():
		return
	var room := _host_room(multiplayer.get_remote_sender_id(), "Only the host can end the game.")
	if room == null or room.state != Room.State.PLAYING:
		return
	_end_game(room)
	_announce_room(room)

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

@rpc("authority", "call_remote", "reliable")
func _client_lobby(info: Dictionary) -> void:
	room_info = info
	if info.get("state", "") == "lobby":
		_reset_table_mirrors()
	lobby_changed.emit(info)

@rpc("authority", "call_remote", "reliable")
func _client_left_room() -> void:
	room_info = {}
	_my_seat = -1
	_reset_table_mirrors()
	left_room.emit()

@rpc("authority", "call_remote", "reliable")
func _client_notice(text: String) -> void:
	notice.emit(text)

# ---- server internals ----

## The room's roster went out of date (join, leave, new host, game started or ended):
## re-send every player their own seat and the room's roster to everybody.
func _announce_room(room: Room) -> void:
	for pid: int in room.peer_ids():
		rpc_id(pid, "_client_seated", room.seat_of(pid), room.room_name)
	_broadcast(room, "_client_lobby", [room.lobby_info()])

## The host's room, or null (with a notice to the sender) when they are not its host.
func _host_room(sender: int, refusal: String) -> Room:
	var room := _rooms.room_of(sender)
	if room == null:
		return null
	if room.host_peer != sender:
		rpc_id(sender, "_client_notice", refusal)
		return null
	return room

## Someone sat down in a game that is already running: they take the last seat.
func _grow_engine(room: Room) -> void:
	var engine: GameEngine = room.get_meta("engine")
	engine.seat_count = room.player_count()
	_queue_event(room, "seats", _seats_args(room, engine))
	_flush_events(room)

## Stop the game and go back to the lobby (the players stay in the room).
func _end_game(room: Room) -> void:
	if room.has_meta("engine"):
		var old: GameEngine = room.get_meta("engine")
		room.remove_meta("engine")
		old.queue_free()
	room.set_meta("events", [])
	room.state = Room.State.LOBBY

## Deal a new game to everyone in the room: one engine with a seat per player.
func _start_game(room: Room) -> void:
	room.state = Room.State.PLAYING
	room.set_meta("events", [])
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
	_remove_player(peer_id)

## A player is gone (disconnected or left on purpose): free their seat, tell the table who
## left, close the gap in the turn order, and pass the host role on if it was theirs.
func _remove_player(peer_id: int) -> void:
	if _rooms == null:
		return
	_throttle.forget(peer_id)
	var old_room: Room = _rooms.room_of(peer_id)
	if old_room == null:
		return
	var seat := old_room.seat_of(peer_id)
	var leaver_name := old_room.name_of(peer_id)
	var room: Room = _rooms.leave(peer_id)
	if room == null:
		return
	if room.player_count() == 0:
		if room.persistent:
			_end_game(room)   # the always-open table starts fresh for the next visitors
		return
	if room.state == Room.State.PLAYING and room.has_meta("engine"):
		var engine: GameEngine = room.get_meta("engine")
		# Tell the table who left first, then close the gap in the turn order.
		_queue_event(room, "left", [leaver_name])
		engine.remove_seat(seat)
		_queue_event(room, "seats", _seats_args(room, engine))
		_flush_events(room)
	# Everyone's seat number and the roster (and maybe the host) changed.
	_announce_room(room)

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
