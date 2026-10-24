extends RefCounted
class_name SeatHold
## What to do about players whose connection dropped mid-game. A dropped seat is held for
## `hold_msec` so the player can come back; if it is their turn the table waits
## `turn_wait_msec` and then skips them. Pure logic: the caller passes in the time and acts on
## the answers, so the timings can be tested without waiting.

const HOLD_MSEC := 60_000
const TURN_WAIT_MSEC := 20_000
const STATUS_EVERY_MSEC := 1_000

var hold_msec: int = HOLD_MSEC
var turn_wait_msec: int = TURN_WAIT_MSEC

var _last_status: Dictionary = {}   # room id -> msec of the last status broadcast

## What the server must do for `room` at time `now`: an Array of dictionaries
##   {"type": "release", "token": ...}  the hold ran out, the seat is gone for good
##   {"type": "skip", "token": ...}     it is their turn and they did not come back in time
##   {"type": "status"}                 tell the room how long each away player has left
## Seats are named by session token because releasing one renumbers the others.
func tick(room: Room, current_seat: int, now: int) -> Array:
	var actions: Array = []
	var away := room.away_seats()
	if away.is_empty():
		_last_status.erase(room.id)
		return actions
	var released := {}
	for seat: Room.Seat in away:
		if now - seat.away_since_msec >= hold_msec:
			actions.append({"type": "release", "token": seat.token})
			released[seat.token] = true
	for seat: Room.Seat in away:
		if released.has(seat.token) or seat.seat_index != current_seat:
			continue
		if now - _turn_started(room, seat) >= turn_wait_msec:
			actions.append({"type": "skip", "token": seat.token})
	if now - int(_last_status.get(room.id, -STATUS_EVERY_MSEC)) >= STATUS_EVERY_MSEC:
		_last_status[room.id] = now
		actions.append({"type": "status"})
	return actions

## Ask for the next status broadcast to go out on the next tick (something changed).
func status_now(room: Room) -> void:
	_last_status.erase(room.id)

## Every away seat as [seat index, seconds of hold left, seconds of turn wait left or -1].
func status_list(room: Room, current_seat: int, now: int) -> Array:
	var list: Array = []
	for seat: Room.Seat in room.away_seats():
		var hold_left := _seconds_left(hold_msec - (now - seat.away_since_msec))
		var turn_left := -1
		if seat.seat_index == current_seat:
			turn_left = _seconds_left(turn_wait_msec - (now - _turn_started(room, seat)))
		list.append([seat.seat_index, hold_left, turn_left])
	return list

func forget(room: Room) -> void:
	_last_status.erase(room.id)

## The turn wait counts from when the player dropped or when their turn began, whichever is later.
func _turn_started(room: Room, seat: Room.Seat) -> int:
	return maxi(seat.away_since_msec, room.turn_since_msec)

func _seconds_left(msec: int) -> int:
	return maxi(0, ceili(msec / 1000.0))
