extends SceneTree
## The idle rule: skip after 60 s, then 30 s, then 15 s and remove; acting clears the strikes.

func _types(actions: Array) -> Array:
	return actions.map(func(a: Dictionary) -> String: return a.type)

func _initialize() -> void:
	var t := TestHelper.new()
	var rm := RoomManager.new()
	get_root().add_child(rm)
	var room := rm.create_room("Idle", false)
	rm.seat_player(room, 1, "Ann")
	rm.seat_player(room, 2, "Bea")
	room.state = Room.State.PLAYING
	var watch := IdleWatch.new()
	var ann: Room.Seat = room.seats[0]

	room.activity_msec = 0
	t.eq(watch.tick(room, 0, 30_000), [], "nothing to do while there is plenty of time")
	t.eq(_types(watch.tick(room, 0, 50_000)), ["warn"], "the last 10 seconds are counted down")
	var warn: Dictionary = watch.tick(room, 0, 52_000)[0]
	t.eq([warn.seat, warn.seconds, warn.strike], [0, 8, 0], "the warning names the seat, seconds left and strikes so far")
	t.eq(watch.tick(room, 0, 52_100), [], "the same second is announced once")
	var acts := watch.tick(room, 0, 60_000)
	t.eq(_types(acts), ["skip"], "the first idle turn is skipped after 60 seconds")
	t.check(not acts[0].remove, "and does not remove them")
	t.eq(acts[0].token, ann.token, "naming the player by token")

	# Strike one: next time they only get 30 seconds.
	ann.idle_strikes = 1
	room.activity_msec = 100_000
	t.eq(watch.tick(room, 0, 125_000), [{"type": "warn", "seat": 0, "seconds": 5, "strike": 1}], "a repeat offender is counted down from 30 s")
	acts = watch.tick(room, 0, 130_000)
	t.eq(_types(acts), ["skip"], "the second idle turn is skipped after 30 seconds")
	t.check(not acts[0].remove, "still not removed")

	# Strike two: 15 seconds, and the third skip removes them.
	ann.idle_strikes = 2
	room.activity_msec = 200_000
	acts = watch.tick(room, 0, 215_000)
	t.eq(_types(acts), ["skip"], "the third idle turn is skipped after 15 seconds")
	t.check(acts[0].remove, "and removes them")

	# Acting clears the strikes (the server resets them); the limit is 60 s again.
	ann.idle_strikes = 0
	room.activity_msec = 300_000
	t.eq(watch.tick(room, 0, 340_000), [], "after acting they have the full minute again")

	# The countdown clears when the turn moves on.
	watch.tick(room, 0, 355_000)
	room.activity_msec = 355_500   # the turn moved on: the next player's wait starts now
	t.eq(_types(watch.tick(room, 1, 355_500)), ["clear"], "a countdown ends when it stops being their turn")
	t.eq(watch.tick(room, 1, 355_600), [], "and is only cleared once")

	# Away players belong to SeatHold, and a lone player has nobody to skip to.
	rm.mark_away(1, 400_000)
	room.activity_msec = 400_000
	var away_acts := _types(watch.tick(room, 0, 999_999))
	t.check(not ("skip" in away_acts) and not ("warn" in away_acts), "an away player is not an idle player")
	var solo := rm.create_room("Solo", false)
	rm.seat_player(solo, 50, "Only")
	solo.state = Room.State.PLAYING
	solo.activity_msec = 0
	t.eq(watch.tick(solo, 0, 999_999), [], "a player alone at the table is never skipped")

	# Short limits for the networked tests.
	var fast := IdleWatch.new()
	fast.limits_msec = [1500, 1000, 800]
	fast.warn_seconds = 1
	var room2 := rm.create_room("Fast", false)
	rm.seat_player(room2, 70, "A")
	rm.seat_player(room2, 71, "B")
	room2.activity_msec = 0
	t.eq(_types(fast.tick(room2, 0, 1500)), ["skip"], "custom limits are honoured")
	t.finish()
	quit()
