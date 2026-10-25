extends RefCounted
class_name JoinThrottle
## Slows down anyone guessing join codes: a peer that fails to join too many times in a
## window is refused until the oldest failures age out. Time is passed in so tests can
## drive it without waiting.

const MAX_FAILURES := 5
const WINDOW_MSEC := 60_000

var _failures: Dictionary = {}   # peer id -> Array[int] of failure times (msec)

func record_failure(peer_id: int, now_msec: int) -> void:
	var times: Array = _failures.get(peer_id, [])
	times.append(now_msec)
	_failures[peer_id] = times

func blocked(peer_id: int, now_msec: int) -> bool:
	return _recent(peer_id, now_msec).size() >= MAX_FAILURES

## Seconds until this peer may try again (0 when not blocked).
func seconds_left(peer_id: int, now_msec: int) -> int:
	var recent := _recent(peer_id, now_msec)
	if recent.size() < MAX_FAILURES:
		return 0
	return ceili((recent[0] + WINDOW_MSEC - now_msec) / 1000.0)

func forget(peer_id: int) -> void:
	_failures.erase(peer_id)

func _recent(peer_id: int, now_msec: int) -> Array:
	var times: Array = _failures.get(peer_id, [])
	var recent: Array = times.filter(func(t: int) -> bool: return now_msec - t < WINDOW_MSEC)
	if recent.is_empty():
		_failures.erase(peer_id)
	else:
		_failures[peer_id] = recent
	return recent
