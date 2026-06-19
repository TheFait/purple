extends SceneTree

func _initialize() -> void:
	var t := TestHelper.new()
	seed(1)
	var rm := RoomManager.new()
	get_root().add_child(rm)

	var pub := rm.create_room("Lobby", true)
	t.check(pub.is_public, "public room flagged public")
	t.eq(pub.max_seats, 12, "max seats 12")

	# Fill 12 seats; the 13th is rejected.
	for i in range(12):
		var r := rm.join(1000 + i, pub.id, "P%d" % i)
		t.check(r != null, "seat %d joined" % i)
	t.eq(pub.player_count(), 12, "room full at 12")
	t.check(rm.join(9999, pub.id, "Overflow") == null, "13th join rejected")

	# Leaving frees a seat.
	t.check(rm.leave(1000) != null, "peer leaves")
	t.eq(pub.player_count(), 11, "seat freed on leave")

	# Private room joins by code, not by id-as-public.
	var prv := rm.create_room("Secret", false)
	t.check(prv.join_code != "", "private room has a code")
	t.check(rm.join(2000, prv.join_code, "CodeJoiner") != null, "join by code works")
	t.eq(prv.seat_of(2000), 0, "first private seat is index 0")

	# Public listing shows only public rooms.
	var listing := rm.list_public()
	var ids := []
	for entry in listing:
		ids.append(entry.id)
	t.check(ids.has(pub.id), "public room listed")
	t.check(not ids.has(prv.id), "private room not listed")
	t.finish()
	quit()
