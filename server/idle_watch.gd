extends RefCounted
class_name IdleWatch
## What to do about a connected player who is on turn but does nothing. Each time they let
## their turn run out it is skipped, and the wait gets shorter: 60 s, then 30 s, then 15 s, and
## the third skip removes them. Acting at all clears their strikes. Like SeatHold this is pure
## timing logic: the caller passes in the time and carries out the answers.

const LIMITS_MSEC := [60_000, 30_000, 15_000]
const WARN_SECONDS := 10   # the last seconds before a skip are counted down to everyone

var limits_msec: Array = LIMITS_MSEC
var warn_seconds: int = WARN_SECONDS

var _warning: Dictionary = {}   # room id -> [token, seconds] of the countdown last announced

## What the server must do for `room` at time `now` (Array of dictionaries):
##   {"type": "skip", "token": ..., "remove": bool}   they ran out of time (remove = third strike)
##   {"type": "warn", "seat": ..., "seconds": ..., "strike": ...}   a seconds-left countdown tick
##   {"type": "clear"}                                the countdown that was showing is over
## `activity_msec` on the room is when the player's wait began (the last action or turn change).
func tick(room: Room, current_seat: int, now: int) -> Array:
	var actions: Array = []
	var seat: Room.Seat = null
	if room.player_count() >= 2 and current_seat >= 0 and current_seat < room.seats.size():
		seat = room.seats[current_seat]
	# Away players are SeatHold's business; a lone player has nobody to skip to.
	if seat == null or seat.is_away():
		_clear(room, actions)
		return actions
	var limit := limit_for(seat.idle_strikes)
	var idle := now - room.activity_msec
	if idle >= limit:
		_warning.erase(room.id)
		actions.append({"type": "skip", "token": seat.token, "remove": seat.idle_strikes + 1 >= limits_msec.size()})
		return actions
	var left := ceili((limit - idle) / 1000.0)
	if left <= warn_seconds:
		var shown: Array = _warning.get(room.id, [])
		if shown != [seat.token, left]:
			_warning[room.id] = [seat.token, left]
			actions.append({"type": "warn", "seat": current_seat, "seconds": left, "strike": seat.idle_strikes})
	else:
		_clear(room, actions)
	return actions

## How long the player may sit on their turn, given how many times they already let it lapse.
func limit_for(strikes: int) -> int:
	return int(limits_msec[mini(strikes, limits_msec.size() - 1)])

func forget(room: Room) -> void:
	_warning.erase(room.id)

func _clear(room: Room, actions: Array) -> void:
	if _warning.has(room.id):
		_warning.erase(room.id)
		actions.append({"type": "clear"})
