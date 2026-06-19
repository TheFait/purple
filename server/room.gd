extends Node
class_name Room

class Seat extends RefCounted:
	var peer_id: int
	var player_name: String
	var seat_index: int
	func _init(p_peer: int, p_name: String, p_index: int) -> void:
		peer_id = p_peer
		player_name = p_name
		seat_index = p_index

var id: String = ""
var room_name: String = ""
var is_public: bool = true
var join_code: String = ""
var max_seats: int = 12
var seats: Array = []  # Array[Seat]

func is_full() -> bool:
	return seats.size() >= max_seats

func player_count() -> int:
	return seats.size()

func add_seat(peer_id: int, player_name: String) -> int:
	if is_full() or seat_of(peer_id) != -1:
		return -1
	var index := seats.size()
	seats.append(Seat.new(peer_id, player_name, index))
	return index

func remove_seat(peer_id: int) -> bool:
	for i in range(seats.size()):
		if seats[i].peer_id == peer_id:
			seats.remove_at(i)
			# Re-pack seat indices so turn order stays contiguous.
			for j in range(seats.size()):
				seats[j].seat_index = j
			return true
	return false

func seat_of(peer_id: int) -> int:
	for s in seats:
		if s.peer_id == peer_id:
			return s.seat_index
	return -1

func peer_ids() -> Array:
	var ids := []
	for s in seats:
		ids.append(s.peer_id)
	return ids
