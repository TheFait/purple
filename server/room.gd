extends Node
class_name Room

class Seat extends RefCounted:
	var peer_id: int
	var player_name: String
	var seat_index: int
	var token: String = ""           # secret that lets this player take the seat back after a drop
	var away_since_msec: int = -1    # when the connection dropped, or -1 while connected
	var last_peer_id: int = -1       # the connection the seat had before it went away
	var idle_strikes: int = 0        # turns in a row they let run out without acting
	func _init(p_peer: int, p_name: String, p_index: int) -> void:
		peer_id = p_peer
		player_name = p_name
		seat_index = p_index
		token = Crypto.new().generate_random_bytes(12).hex_encode()
	func is_away() -> bool:
		return away_since_msec >= 0

var id: String = ""
var room_name: String = ""
var is_public: bool = true
var join_code: String = ""
var max_seats: int = 12
var seats: Array = []  # Array[Seat]

enum State { LOBBY, PLAYING }

const NAME_MAX := 16
const MIN_PLAYERS := 2   # the host can start with two ("best with 4+")

var state: State = State.LOBBY
var host_peer: int = -1          # the player who can start and end the game
var persistent: bool = false     # never freed when empty (the always-open public table)
var auto_start: bool = false     # start the game as soon as the first player joins (tests)
var turn_since_msec: int = 0     # when the current turn began (drives the wait for an away player)
var activity_msec: int = 0       # when the player on turn started waiting: the last action or turn change

func is_full() -> bool:
	return seats.size() >= max_seats

func player_count() -> int:
	return seats.size()

func add_seat(peer_id: int, player_name: String) -> int:
	if is_full() or seat_of(peer_id) != -1:
		return -1
	var index := seats.size()
	seats.append(Seat.new(peer_id, player_name, index))
	if host_peer == -1:
		host_peer = peer_id
	return index

## The name a player is shown under: trimmed, length-capped, never empty, and numbered
## ("Sam", "Sam 2") when someone in the room already has it.
func unique_name(wanted: String) -> String:
	var base := clean_text(wanted).left(NAME_MAX).strip_edges()
	if base.is_empty():
		base = "Player"
	var taken := {}
	for s in seats:
		taken[s.player_name] = true
	var candidate := base
	var n := 2
	while taken.has(candidate):
		candidate = "%s %d" % [base, n]
		n += 1
	return candidate

## Drops control characters (line breaks, tabs, escape codes) from a typed name.
static func clean_text(text: String) -> String:
	var out := ""
	for i in text.length():
		if text.unicode_at(i) >= 32:
			out += text[i]
	return out.strip_edges()

func can_start() -> bool:
	return state == State.LOBBY and player_count() >= MIN_PLAYERS

## What every player in the room is shown: who is here, who hosts, and where the game is at.
## The invite code is only revealed for private rooms.
func lobby_info() -> Dictionary:
	return {
		"room": room_name,
		"code": join_code,
		"public": is_public,
		"state": "playing" if state == State.PLAYING else "lobby",
		"host": seat_of(host_peer),
		"names": seat_names(),
		"max": max_seats,
		"min": MIN_PLAYERS,
	}

## Seats whose player has dropped but may still come back.
func away_seats() -> Array:
	return seats.filter(func(s: Seat) -> bool: return s.is_away())

func seat_by_token(token: String) -> Seat:
	if token.is_empty():
		return null
	for s in seats:
		if s.token == token:
			return s
	return null

## Take a seat out of the game for good (their hold ran out), whatever its connection.
func remove_seat_at(index: int) -> void:
	if index < 0 or index >= seats.size():
		return
	var gone: Seat = seats[index]
	seats.remove_at(index)
	for j in range(seats.size()):
		seats[j].seat_index = j
	if gone.peer_id == host_peer or gone.last_peer_id == host_peer:
		host_peer = _first_present_peer()

func _first_present_peer() -> int:
	for s in seats:
		if not s.is_away():
			return s.peer_id
	return -1

## Every player's name, in seat order.
func seat_names() -> Array:
	var names: Array = []
	for s in seats:
		names.append(s.player_name)
	return names

func name_of(peer_id: int) -> String:
	if peer_id < 0:
		return ""
	for s in seats:
		if s.peer_id == peer_id:
			return s.player_name
	return ""

func remove_seat(peer_id: int) -> bool:
	for i in range(seats.size()):
		if seats[i].peer_id == peer_id:
			seats.remove_at(i)
			# Re-pack seat indices so turn order stays contiguous.
			for j in range(seats.size()):
				seats[j].seat_index = j
			# The host left: the longest-seated player takes over.
			if peer_id == host_peer:
				host_peer = _first_present_peer()
			return true
	return false

func seat_of(peer_id: int) -> int:
	if peer_id < 0:
		return -1   # away seats have no connection; never match them
	for s in seats:
		if s.peer_id == peer_id:
			return s.seat_index
	return -1

## The connections currently in the room (seats that dropped have none).
func peer_ids() -> Array:
	var ids := []
	for s in seats:
		if not s.is_away():
			ids.append(s.peer_id)
	return ids
