extends SceneTree

func _initialize() -> void:
	var t := TestHelper.new()
	var d := DeckEngine.new()
	d.load_from_json("res://assets/database/card_database.json", "res://assets/database/card_collection.json")
	t.eq(d.deck_size(), 52, "full deck loaded")

	var first := d.draw()
	t.check(first != null, "draw returns a card")
	t.eq(d.deck_size(), 51, "draw removes from deck")

	# Discard the drawn card, then recycle it back.
	d.discard([first])
	t.eq(d.discard_size(), 1, "discard holds the card")
	d.recycle()
	t.eq(d.discard_size(), 0, "recycle empties discard")
	t.eq(d.deck_size(), 52, "recycle returns card to deck")

	# Draw the whole deck; no duplicates by nice_name.
	var seen := {}
	var dupes := 0
	for i in range(52):
		var c := d.draw()
		if seen.has(c.nice_name):
			dupes += 1
		seen[c.nice_name] = true
	t.eq(dupes, 0, "no duplicate cards in a full draw")
	t.eq(d.draw(), null, "draw on empty deck returns null")
	t.finish()
	quit()
