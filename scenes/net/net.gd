extends Node
## Shared network node present in BOTH server and client (autoload => same path
## `/root/Net`, which Godot RPC requires). Branches on multiplayer.is_server().

const DEFAULT_PORT := 9000
const ROOM_MANAGER := preload("res://server/room_manager.gd")
const GAME_ENGINE  := preload("res://scenes/engine/game_engine.gd")
const DECK_ENGINE  := preload("res://scenes/engine/deck_engine.gd")
const JOIN_THROTTLE := preload("res://server/join_throttle.gd")
const SEAT_HOLD := preload("res://server/seat_hold.gd")
const IDLE_WATCH := preload("res://server/idle_watch.gd")
const RECONNECT_WINDOW_MSEC := 60_000   # how long a dropped client keeps trying to get its seat back
const RECONNECT_RETRY_MSEC := 2_000
const COLD_RESUME_MSEC := 15_000        # how long a freshly started app tries to rejoin its saved game
const SESSION_TOUCH_MSEC := 10_000
const MAX_ROOMS := 200
const ROOM_NAME_MAX := 24
const DB_PATH         := "res://assets/database/card_database.json"
const COLLECTION_PATH := "res://assets/database/card_collection.json"

# Client-facing signals
signal connected()
signal connect_failed()
signal connection_lost()                 # the server went away after we had connected
signal reconnecting(seconds_left: int)   # the connection dropped mid-game; we are trying to get the seat back
signal resumed()                         # ... and we got it
signal session_expired()                 # ... or the hold ran out / the server no longer knows us
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
signal away_changed(list: Array)      # players who dropped: [[seat, hold seconds left, turn seconds left or -1], ...]
signal turn_skipped(from_seat: int, to_seat: int)
signal idle_warning(seat: int, seconds_left: int, strike: int)   # the player on turn is about to be skipped (-1 seconds: cleared)
signal player_kicked(player_name: String)                       # someone was removed for sitting idle
signal kicked()                                                 # ... and it was us
signal stack_passed(from_seat: int, to_seat: int, count: int)
signal table_restored(cards: Array)   # a snapshot of the stack, for a client that joined or reloaded late
signal diamonds_forever()
signal round_log(text: String)
signal raw_batch(batch: Array)   # test hook: every event batch exactly as it arrived

var _rooms: RoomManager      # server only
var _auto_room: Room         # server only — the always-open public table
var _throttle: JoinThrottle  # server only — slows down join-code guessing

## Server only, set before start_server: start the open table's game as soon as someone sits
## down (the lobby is skipped). The automated tests use this; a real server leaves it off.
var auto_start_open_table: bool = false

## Server only, set before start_server: how long a dropped player's seat is held, and how long
## the table waits for them on their turn. The tests use short ones.
var hold_msec: int = SeatHold.HOLD_MSEC
var turn_wait_msec: int = SeatHold.TURN_WAIT_MSEC
var _seat_hold: SeatHold

## Server only, set before start_server: how long a connected player may sit on their turn
## (by number of idle turns so far) and how many seconds before that the table is warned.
var idle_limits_msec: Array = IdleWatch.LIMITS_MSEC
var idle_warn_seconds: int = IdleWatch.WARN_SECONDS
var _idle_watch: IdleWatch

## Server only, set before start_server (tests only): where to write the order of every new
## game's deck, so a test client can prove it was never shown a card before it was drawn.
var deck_dump_path: String = ""

var room_info: Dictionary = {}   # client only — the last lobby info the server sent
var session_token: String = ""   # client only — proves who we are when getting a seat back after a drop

var _server_ip: String = ""      # client only — where to reconnect to
var _server_port: int = 0
var _reconnecting: bool = false
var _reconnect_deadline_msec: int = 0
var _next_attempt_msec: int = 0
var _last_countdown: int = -1
var _next_touch_msec: int = 0

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
	_seat_hold = SEAT_HOLD.new()
	_seat_hold.hold_msec = hold_msec
	_seat_hold.turn_wait_msec = turn_wait_msec
	_idle_watch = IDLE_WATCH.new()
	_idle_watch.limits_msec = idle_limits_msec
	_idle_watch.warn_seconds = idle_warn_seconds
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

## Connect to a server. Returns false (and emits connect_failed) when the address is unusable.
func start_client(ip: String, port: int) -> bool:
	stop_client()
	_server_ip = ip
	_server_port = port
	if not _open_connection():
		connect_failed.emit()
		return false
	return true

func _open_connection() -> bool:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(_server_ip, _server_port)
	if err != OK:
		return false
	multiplayer.multiplayer_peer = peer
	if not multiplayer.connected_to_server.is_connected(_on_connected):
		multiplayer.connected_to_server.connect(_on_connected)
		multiplayer.connection_failed.connect(_on_connection_failed)
		multiplayer.server_disconnected.connect(_on_server_disconnected)
	return true

## Drop the current connection for good (leaving, going back, retrying): the seat is forgotten.
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
	session_token = ""
	_reconnecting = false
	OnlineSettings.clear_session()

func _on_connected() -> void:
	if _reconnecting:
		rpc_id(1, "rpc_resume", session_token)   # prove who we are and take the seat back
		return
	connected.emit()

func _on_connection_failed() -> void:
	if _reconnecting:
		return   # the retry timer will try again
	connect_failed.emit()

## The server went away. In a running game we hold on to our seat and keep trying to get it
## back; anywhere else the connection is simply lost.
func _on_server_disconnected() -> void:
	if _can_resume():
		_begin_reconnect()
		return
	stop_client()
	connection_lost.emit()

func _can_resume() -> bool:
	return not session_token.is_empty() and room_info.get("state", "") == "playing" and not _server_ip.is_empty()

func _begin_reconnect() -> void:
	if multiplayer.multiplayer_peer != null and not multiplayer.is_server():
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	_reconnecting = true
	var now := Time.get_ticks_msec()
	_reconnect_deadline_msec = now + RECONNECT_WINDOW_MSEC
	_next_attempt_msec = now + 500
	_last_countdown = -1
	reconnecting.emit(RECONNECT_WINDOW_MSEC / 1000)

## Simulate losing the connection (used by the tests, handy for trying the reconnect screens).
func lose_connection() -> void:
	if _can_resume():
		_begin_reconnect()
	else:
		stop_client()
		connection_lost.emit()

func _give_up_reconnecting() -> void:
	stop_client()
	session_expired.emit()

func _process(_delta: float) -> void:
	if _rooms != null:
		_hold_tick()
	elif _reconnecting:
		_reconnect_tick()
	elif not session_token.is_empty() and Time.get_ticks_msec() >= _next_touch_msec:
		# Still in the game: keep the saved session fresh so it is worth rejoining after a crash.
		_next_touch_msec = Time.get_ticks_msec() + SESSION_TOUCH_MSEC
		OnlineSettings.touch_session()

## True while we are trying to get our seat back.
func is_reconnecting() -> bool:
	return _reconnecting

## A freshly started app rejoins the game it was in when it closed (see OnlineSettings). The
## reply is the usual resumed / session_expired, and the room announces itself on success.
func resume_saved() -> bool:
	var saved := OnlineSettings.load_session()
	if saved.is_empty():
		return false
	var address := OnlineSettings.parse_address(String(saved.address), DEFAULT_PORT)
	_server_ip = address[0]
	_server_port = address[1]
	session_token = String(saved.token)
	room_info = {"state": "playing"}   # (so a resume is allowed; the server's answer sets the real state)
	_reconnecting = true
	var now := Time.get_ticks_msec()
	_reconnect_deadline_msec = now + COLD_RESUME_MSEC
	_next_attempt_msec = now
	_last_countdown = -1
	reconnecting.emit(COLD_RESUME_MSEC / 1000)
	return true

func _reconnect_tick() -> void:
	var now := Time.get_ticks_msec()
	if now >= _reconnect_deadline_msec:
		_give_up_reconnecting()
		return
	var left := ceili((_reconnect_deadline_msec - now) / 1000.0)
	if left != _last_countdown:
		_last_countdown = left
		reconnecting.emit(left)
	if now >= _next_attempt_msec:
		_next_attempt_msec = now + RECONNECT_RETRY_MSEC
		_open_connection()

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
	_send_session(room, sender)

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
	_send_session(room, sender)

## A player whose connection dropped comes back with the token the server gave them.
@rpc("any_peer", "call_remote", "reliable")
func rpc_resume(token: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var now := Time.get_ticks_msec()
	if _throttle.blocked(sender, now):
		rpc_id(sender, "_client_resume_failed")
		return
	var result := _rooms.resume(token, sender)
	if result.is_empty():
		_throttle.record_failure(sender, now)   # guessing tokens counts like guessing codes
		rpc_id(sender, "_client_resume_failed")
		return
	var room: Room = result.room
	if int(result.stale_peer) >= 0:
		multiplayer.multiplayer_peer.disconnect_peer(int(result.stale_peer))   # a half-dead old connection
	rpc_id(sender, "_client_resumed")
	_announce_room(room)
	if room.has_meta("engine"):
		rpc_id(sender, "_client_events", _snapshot(room))
		_seat_hold.status_now(room)
		_send_away_list(room)

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
func _client_session(token: String) -> void:
	session_token = token
	OnlineSettings.save_session(token, "%s:%d" % [_server_ip, _server_port])

@rpc("authority", "call_remote", "reliable")
func _client_resumed() -> void:
	_reconnecting = false
	resumed.emit()

@rpc("authority", "call_remote", "reliable")
func _client_resume_failed() -> void:
	if _reconnecting:
		_give_up_reconnecting()

@rpc("authority", "call_remote", "reliable")
func _client_lobby(info: Dictionary) -> void:
	room_info = info
	if info.get("state", "") == "lobby":
		_reset_table_mirrors()
	lobby_changed.emit(info)

## The server removed us for sitting idle.
@rpc("authority", "call_remote", "reliable")
func _client_kicked() -> void:
	room_info = {}
	_my_seat = -1
	session_token = ""
	OnlineSettings.clear_session()
	_reset_table_mirrors()
	kicked.emit()

@rpc("authority", "call_remote", "reliable")
func _client_left_room() -> void:
	session_token = ""
	OnlineSettings.clear_session()
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

func _send_session(room: Room, peer_id: int) -> void:
	var index := room.seat_of(peer_id)
	if index >= 0:
		rpc_id(peer_id, "_client_session", room.seats[index].token)

func _now() -> int:
	return Time.get_ticks_msec()

## Tell the room which players are away and how long each has left (an empty list clears it).
func _send_away_list(room: Room) -> void:
	if not room.has_meta("engine"):
		return
	var engine: GameEngine = room.get_meta("engine")
	_queue_event(room, "away", [_seat_hold.status_list(room, engine.current_seat, _now())])
	_flush_events(room)

## A connection dropped in a running game: keep the seat for a while instead of removing it.
func _hold_seat(room: Room, peer_id: int) -> void:
	_throttle.forget(peer_id)
	_rooms.mark_away(peer_id, _now())
	_seat_hold.status_now(room)
	_send_away_list(room)

## Called every frame on the server: skip players who are away on their turn, release seats
## whose hold ran out, and keep everybody's countdown fresh.
func _hold_tick() -> void:
	var now := _now()
	for room: Room in _rooms.all_rooms():
		if room.state != Room.State.PLAYING or not room.has_meta("engine"):
			continue
		var engine: GameEngine = room.get_meta("engine")
		for action: Dictionary in _seat_hold.tick(room, engine.current_seat, now):
			if not is_instance_valid(room) or not room.has_meta("engine"):
				break
			_run_hold_action(room, engine, action)
		if not is_instance_valid(room) or not room.has_meta("engine"):
			continue
		for action: Dictionary in _idle_watch.tick(room, engine.current_seat, now):
			if not is_instance_valid(room) or not room.has_meta("engine"):
				break
			_run_idle_action(room, engine, action, now)

func _run_hold_action(room: Room, engine: GameEngine, action: Dictionary) -> void:
	match action.type:
		"status":
			_send_away_list(room)
		"skip":
			var seat := room.seat_by_token(String(action.token))
			if seat != null and seat.seat_index == engine.current_seat:
				engine.skip_turn()
				_seat_hold.status_now(room)
				_send_away_list(room)
		"release":
			var seat := room.seat_by_token(String(action.token))
			if seat != null:
				_release_seat(room, seat.seat_index)

## A connected player on turn who does nothing: warn the table, skip them, and on the third
## idle turn in a row remove them.
func _run_idle_action(room: Room, engine: GameEngine, action: Dictionary, now: int) -> void:
	match action.type:
		"warn":
			_queue_event(room, "idle", [action.seat, action.seconds, action.strike])
			_flush_events(room)
		"clear":
			_queue_event(room, "idle", [-1, -1, 0])
			_flush_events(room)
		"skip":
			var seat := room.seat_by_token(String(action.token))
			if seat == null or seat.seat_index != engine.current_seat:
				return
			var peer := seat.peer_id
			seat.idle_strikes += 1
			_queue_event(room, "idle", [-1, -1, 0])
			engine.skip_turn()
			room.activity_msec = now
			if action.remove and peer >= 0:
				_remove_player(peer, "idle")
				rpc_id(peer, "_client_kicked")
			else:
				_flush_events(room)

## The hold ran out: the seat is gone for good. Same cleanup as someone leaving mid-game.
func _release_seat(room: Room, index: int) -> void:
	var engine: GameEngine = room.get_meta("engine")
	_queue_event(room, "left", [room.seats[index].player_name])
	engine.remove_seat(index)
	_rooms.drop_seat(room, index)
	if room.player_count() == 0:
		_seat_hold.forget(room)
		if room.persistent:
			_end_game(room)
		else:
			engine.queue_free()
		return
	_queue_event(room, "seats", _seats_args(room, engine))
	_flush_events(room)
	_seat_hold.status_now(room)
	_send_away_list(room)
	_announce_room(room)

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
	room.turn_since_msec = _now()
	room.activity_msec = _now()
	room.set_meta("events", [])
	var deck := DECK_ENGINE.new()
	deck.load_from_json(DB_PATH, COLLECTION_PATH)
	if not deck_dump_path.is_empty():
		var dump := FileAccess.open(deck_dump_path, FileAccess.WRITE)
		dump.store_string("\n".join(deck.names_in_draw_order()))
		dump.close()
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
	engine.turn_changed.connect(func(s: int):
		room.turn_since_msec = _now()
		room.activity_msec = _now()
		_queue_event(room, "turn", [s]))
	engine.turn_skipped.connect(func(f: int, to: int): _queue_event(room, "skipped", [f, to]))
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
		["away", [_seat_hold.status_list(room, engine.current_seat, _now())]],
	]

func _broadcast(room: Room, method: String, args: Array = []) -> void:
	for pid: int in room.peer_ids():
		callv("rpc_id", [pid, method] + args)

func _on_peer_disconnected(peer_id: int) -> void:
	if _rooms == null:
		return
	var room := _rooms.room_of(peer_id)
	# In a running game a dropped connection keeps its seat for a while; anywhere else it is gone.
	if room != null and room.state == Room.State.PLAYING and room.has_meta("engine") and room.seat_of(peer_id) >= 0:
		_hold_seat(room, peer_id)
	else:
		_remove_player(peer_id)

## A player is gone (disconnected or left on purpose): free their seat, tell the table who
## left, close the gap in the turn order, and pass the host role on if it was theirs.
func _remove_player(peer_id: int, reason: String = "") -> void:
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
		elif room.has_meta("engine"):
			var orphan: GameEngine = room.get_meta("engine")
			orphan.queue_free()
		_seat_hold.forget(room)
		return
	if room.state == Room.State.PLAYING and room.has_meta("engine"):
		var engine: GameEngine = room.get_meta("engine")
		# Tell the table who left first, then close the gap in the turn order.
		_queue_event(room, "kicked" if reason == "idle" else "left", [leaver_name])
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
	var accepted := false
	match kind:
		"move": accepted = engine.submit_move(seat, move)
		"pass": accepted = engine.request_pass(seat)
	if accepted:
		# Acting restarts the idle clock and clears any idle strikes.
		room.activity_msec = _now()
		room.seats[seat].idle_strikes = 0
	_flush_events(room)

# ---- server -> client: game events ----

## One server action's worth of events, in order. Replayed through the presenter signals.
@rpc("authority", "call_remote", "reliable")
func _client_events(batch: Array) -> void:
	raw_batch.emit(batch)
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
		"away": away_changed.emit(args[0])
		"skipped": turn_skipped.emit(int(args[0]), int(args[1]))
		"idle": idle_warning.emit(int(args[0]), int(args[1]), int(args[2]))
		"kicked": player_kicked.emit(String(args[0]))

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
	return not _reconnecting and _my_seat == _current_turn_seat

func local_seat() -> int:
	return _my_seat
