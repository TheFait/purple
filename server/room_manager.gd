extends Node
class_name RoomManager

const ROOM_SCRIPT := preload("res://server/room.gd")

var _rooms: Dictionary = {}        # id -> Room
var _peer_to_room: Dictionary = {} # peer_id -> room id
var _counter: int = 0

func create_room(name: String, is_public: bool, persistent: bool = false) -> Room:
	_counter += 1
	var room: Room = ROOM_SCRIPT.new()
	room.id = "room_%d" % _counter
	room.room_name = name
	room.is_public = is_public
	room.persistent = persistent
	room.join_code = "" if is_public else _make_code()
	add_child(room)
	_rooms[room.id] = room
	return room

func join(peer_id: int, room_id_or_code: String, player_name: String) -> Room:
	if _peer_to_room.has(peer_id):
		return null  # one room per peer
	var wanted := room_id_or_code.strip_edges()
	var room := _resolve(wanted)
	if room == null:
		room = _resolve(wanted.to_upper())   # codes are typed in any case
	if room == null or not seat_player(room, peer_id, player_name):
		return null
	return room

## Put a player in a room they were not looked up for (the host of a room they just made).
func seat_player(room: Room, peer_id: int, player_name: String) -> bool:
	if _peer_to_room.has(peer_id) or room.is_full():
		return false
	if room.add_seat(peer_id, room.unique_name(player_name)) == -1:
		return false
	_peer_to_room[peer_id] = room.id
	return true

func room_count() -> int:
	return _rooms.size()

func leave(peer_id: int) -> Room:
	if not _peer_to_room.has(peer_id):
		return null
	var room: Room = _rooms.get(_peer_to_room[peer_id])
	_peer_to_room.erase(peer_id)
	if room != null:
		room.remove_seat(peer_id)
		if room.player_count() == 0 and not room.persistent:
			_rooms.erase(room.id)
			room.queue_free()
	return room

func room_of(peer_id: int) -> Room:
	if not _peer_to_room.has(peer_id):
		return null
	return _rooms.get(_peer_to_room[peer_id])

func list_public() -> Array:
	var out := []
	for room in _rooms.values():
		if room.is_public:
			out.append({"id": room.id, "name": room.room_name, "count": room.player_count(), "max": room.max_seats,
					"state": "playing" if room.state == Room.State.PLAYING else "lobby"})
	return out

func _resolve(room_id_or_code: String) -> Room:
	if _rooms.has(room_id_or_code):
		var candidate: Room = _rooms[room_id_or_code]
		if candidate.is_public:
			return candidate
	for room in _rooms.values():
		if not room.is_public and room.join_code == room_id_or_code:
			return room
	return null

func _make_code() -> String:
	var alphabet := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	var code := ""
	for i in range(5):
		code += alphabet[randi() % alphabet.length()]
	return code
