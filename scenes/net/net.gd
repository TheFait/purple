extends Node
## Shared network node present in BOTH server and client (autoload => same path
## `/root/Net`, which Godot RPC requires). Branches on multiplayer.is_server().

const DEFAULT_PORT := 9000
const ROOM_MANAGER := preload("res://server/room_manager.gd")

# Client-facing signals
signal connected()
signal seated(seat: int, room_name: String)
signal join_failed(reason: String)
signal public_rooms(list: Array)

var _rooms: RoomManager      # server only
var _auto_room: Room         # server only — the iteration-1 default public room

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
	seated.emit(seat, room_name)

@rpc("authority", "call_remote", "reliable")
func _client_join_failed(reason: String) -> void:
	join_failed.emit(reason)

@rpc("authority", "call_remote", "reliable")
func _client_public_rooms(list: Array) -> void:
	public_rooms.emit(list)

# ---- server internals ----

func _ensure_engine(room: Room) -> void:
	# Game RPC wiring is added in Task 7; for the connection slice we only need
	# a room with seats. Engine creation is idempotent there.
	pass

func _on_peer_disconnected(peer_id: int) -> void:
	if _rooms != null:
		_rooms.leave(peer_id)
