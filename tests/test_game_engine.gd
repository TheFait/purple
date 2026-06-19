extends SceneTree

func _initialize() -> void:
	var t := TestHelper.new()
	seed(12345)
	var deck := DeckEngine.new()
	deck.load_from_json("res://assets/database/card_database.json", "res://assets/database/card_collection.json")
	var engine := GameEngine.new()
	get_root().add_child(engine)  # Node, so it can emit signals in-tree
	engine.setup(deck, 2)

	# After setup there is exactly one active card and pool == 1.
	t.check(engine.active_card() != null, "active card seeded")
	t.eq(engine.drink_pool(), 1, "pool starts at 1")
	t.eq(engine.current_seat, 0, "starts on seat 0")

	# Authority: a move from the wrong seat is rejected (no state change).
	var pool_before := engine.drink_pool()
	t.check(not engine.submit_move(1, GameEngine.Move.HIGHER), "out-of-turn move rejected")
	t.eq(engine.drink_pool(), pool_before, "rejected move did not change state")

	# A move from the correct seat is accepted.
	t.check(engine.submit_move(0, GameEngine.Move.HIGHER), "in-turn move accepted")

	# Drive many moves; assert invariants never break.
	var penalties := {"n": 0}
	engine.penalty_triggered.connect(func(_s, _a): penalties.n += 1)
	for i in range(60):
		if engine.current_streak >= 3:
			# Resolve the pass gate so play can continue.
			engine.request_ride(engine.current_seat)
		var ok := engine.submit_move(engine.current_seat, (i % 6))
		t.check(engine.drink_pool() >= 1, "pool never below 1 (i=%d)" % i)
		t.check(engine.current_seat >= 0 and engine.current_seat < 2, "seat in range (i=%d)" % i)
	t.check(penalties.n > 0, "some penalties fired over 60 moves")
	t.finish()
	quit()
