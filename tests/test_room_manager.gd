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
	# Names are trimmed, capped and numbered when taken.
	var named := rm.create_room("Names", true)
	rm.join(3000, named.id, "  Sam  ")
	rm.join(3001, named.id, "Sam")
	rm.join(3002, named.id, "")
	rm.join(3003, named.id, "A very long name indeed, far past the cap")
	t.eq(named.name_of(3000), "Sam", "name is trimmed")
	t.eq(named.name_of(3001), "Sam 2", "a duplicate name gets a number")
	t.eq(named.name_of(3002), "Player", "an empty name becomes Player")
	t.eq(named.name_of(3003).length(), Room.NAME_MAX, "a long name is capped")
	t.eq(named.seat_names().size(), 4, "seat_names lists every player")
	t.eq(named.seat_names()[1], "Sam 2", "seat_names are in seat order")

	# Control characters are stripped from names.
	rm.join(3004, named.id, "Li
ne	Break")
	t.eq(named.name_of(3004), "LineBreak", "control characters are dropped from names")

	# Host: the first player hosts; if they leave the longest-seated player takes over.
	var hosted := rm.create_room("Hosted", false)
	rm.join(4000, hosted.join_code, "A")
	rm.join(4001, hosted.join_code, "B")
	rm.join(4002, hosted.join_code, "C")
	t.eq(hosted.host_peer, 4000, "the first player to join hosts")
	t.eq(hosted.lobby_info().host, 0, "the host seat is reported")
	rm.leave(4001)
	t.eq(hosted.host_peer, 4000, "the host stays when someone else leaves")
	rm.leave(4000)
	t.eq(hosted.host_peer, 4002, "the host passes to the longest-seated player")
	t.eq(hosted.lobby_info().host, 0, "and is now seat 0")
	rm.leave(4002)

	# Codes work in any case; the invite code is only in a private room's info.
	var coded := rm.create_room("Coded", false)
	t.check(rm.join(4100, coded.join_code.to_lower(), "Lower") != null, "a join code can be typed in lower case")
	t.eq(coded.lobby_info().code, coded.join_code, "a private room reports its code")
	t.eq(pub.lobby_info().code, "", "a public room has no code")

	# Starting needs the minimum players and a lobby.
	t.check(not coded.can_start(), "one player cannot start")
	rm.join(4101, coded.join_code, "Second")
	t.check(coded.can_start(), "two players can start")
	coded.state = Room.State.PLAYING
	t.check(not coded.can_start(), "a running game cannot be started again")
	t.eq(coded.lobby_info().state, "playing", "the info says the game is running")

	# A persistent room stays after everyone leaves.
	var open := rm.create_room("Open", true, true)
	rm.join(4200, open.id, "Solo")
	rm.leave(4200)
	t.check(is_instance_valid(open) and not open.is_queued_for_deletion(), "a persistent room outlives its players")
	t.check(rm.join(4201, open.id, "Again") != null, "and can be joined again")

	# Private room must NOT be joinable by its internal id (security: ids are guessable).
	t.check(rm.join(2001, prv.id, "ByIdShouldFail") == null, "private room not joinable by id")

	# Public listing shows only public rooms.
	var listing := rm.list_public()
	var ids := []
	for entry in listing:
		ids.append(entry.id)
	t.check(ids.has(pub.id), "public room listed")
	t.check(not ids.has(prv.id), "private room not listed")
	t.finish()
	quit()
