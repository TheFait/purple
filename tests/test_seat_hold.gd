extends SceneTree
## Held seats: the 60 second hold, the 20 second turn wait, and the status the room is told.
## Time is a plain number here, so nothing waits.

func _room(rm: RoomManager, count: int, base: int = 100) -> Room:
	var room := rm.create_room("Held", false)
	for i in count:
		rm.seat_player(room, base + i, "P%d" % i)
	room.state = Room.State.PLAYING
	return room

func _types(actions: Array) -> Array:
	return actions.map(func(a: Dictionary) -> String: return a.type)

func _initialize() -> void:
	var t := TestHelper.new()
	var rm := RoomManager.new()
	get_root().add_child(rm)
	var hold := SeatHold.new()

	# Nothing to do while everyone is connected.
	var room := _room(rm, 3)
	t.eq(hold.tick(room, 0, 1000), [], "no away seats, no actions")

	# Seat 1 drops at t=10s. It is seat 0's turn, so nobody is waited for.
	var token1: String = room.seats[1].token
	t.eq(rm.mark_away(101, 10_000), 1, "a dropped player keeps their seat index")
	t.eq(room.player_count(), 3, "and still counts as a player")
	t.eq(room.peer_ids(), [100, 102], "but has no connection to send to")
	t.eq(room.seat_of(101), -1, "the old connection no longer maps to a seat")
	var acts := hold.tick(room, 0, 10_000)
	t.eq(_types(acts), ["status"], "the first tick after a drop sends a status")
	t.eq(hold.status_list(room, 0, 10_000), [[1, 60, -1]], "60 seconds of hold, no turn wait")
	t.eq(_types(hold.tick(room, 0, 10_500)), [], "status is sent once a second, not more")
	t.eq(hold.status_list(room, 0, 40_000), [[1, 30, -1]], "the hold counts down")

	# It becomes seat 1's turn at t=30s: they get 20 seconds from then.
	room.turn_since_msec = 30_000
	t.eq(hold.status_list(room, 1, 35_000), [[1, 35, 15]], "the turn wait counts from the start of their turn")
	t.eq(_types(hold.tick(room, 1, 49_000)), ["status"], "not skipped yet (19 s of 20)")
	acts = hold.tick(room, 1, 50_000)
	t.check("skip" in _types(acts), "skipped after 20 seconds on their turn")
	t.eq(acts.filter(func(a): return a.type == "skip")[0].token, token1, "the skip names the away player by token")

	# After the skip the turn is someone else's, so no more waiting; the hold still runs out at 70s.
	room.turn_since_msec = 50_000
	t.check(not ("skip" in _types(hold.tick(room, 2, 60_000))), "no skip when it is not their turn")
	t.check(not ("release" in _types(hold.tick(room, 2, 69_000))), "held for the full 60 seconds")
	acts = hold.tick(room, 2, 70_000)
	t.check("release" in _types(acts), "released when 60 seconds are up")
	t.check(not ("skip" in _types(acts)), "a released seat is not also skipped")

	# Coming back in time: the token gets the seat back on a new connection.
	var back := rm.resume(token1, 555)
	t.eq(back.index, 1, "the returning player gets their own seat")
	t.eq(room.peer_ids(), [100, 555, 102], "on the new connection")
	t.eq(hold.status_list(room, 1, 80_000), [], "nobody is away any more")
	t.eq(rm.resume("not-a-token", 556), {}, "an unknown token gets nothing")
	t.check(rm.room_of(555) == room, "the new connection is mapped to the room again")

	# A token also works while the old connection still looks alive (a half-dead socket).
	var token2: String = room.seats[2].token
	var again := rm.resume(token2, 777)
	t.eq(again.stale_peer, 102, "the stale connection is reported so it can be dropped")
	t.eq(room.seat_of(777), 2, "the seat moved to the new connection")
	t.eq(room.seat_of(102), -1, "and the old one lost it")

	# The host dropping and returning keeps the host role; releasing a dropped host hands it on.
	var hroom := _room(rm, 3, 200)
	var host_token: String = hroom.seats[0].token
	var host_peer: int = hroom.host_peer
	rm.mark_away(host_peer, 0)
	t.eq(hroom.lobby_info().host, -1, "an away host has no connection to match, so no seat is reported")
	rm.resume(host_token, 900)
	t.eq(hroom.host_peer, 900, "the host role follows the player to the new connection")
	t.eq(hroom.lobby_info().host, 0, "and they are the host in seat 0 again")
	rm.mark_away(900, 0)
	rm.drop_seat(hroom, 0)
	t.eq(hroom.player_count(), 2, "a released seat is removed")
	t.check(hroom.host_peer != -1 and hroom.seat_of(hroom.host_peer) == 0, "the host role moved to a present player")

	# Custom timings (the tests and a quick server can use shorter ones).
	var fast := SeatHold.new()
	fast.hold_msec = 4000
	fast.turn_wait_msec = 1500
	var froom := _room(rm, 2, 300)
	rm.mark_away(froom.seats[0].peer_id, 0)
	froom.turn_since_msec = 0
	t.check("skip" in _types(fast.tick(froom, 0, 1500)), "short turn wait skips quickly")
	t.check("release" in _types(fast.tick(froom, 1, 4000)), "short hold releases quickly")
	t.finish()
	quit()
