extends SceneTree

func _initialize() -> void:
	var t := TestHelper.new()
	var c := CardData.new(14, Globals.SUITS.HEARTS, "Ace of Hearts", "res://a.png", "res://b.png")
	t.eq(c.rank, 14, "rank stored")
	t.check(c.is_red(), "hearts is red")
	t.check(not c.is_black(), "hearts is not black")
	var spade := CardData.new(7, Globals.SUITS.SPADES, "7 of Spades", "", "")
	t.check(spade.is_black(), "spades is black")
	var round_trip := CardData.from_dict(c.to_dict())
	t.eq(round_trip.rank, 14, "round-trip rank")
	t.eq(round_trip.suit, Globals.SUITS.HEARTS, "round-trip suit")
	t.eq(round_trip.nice_name, "Ace of Hearts", "round-trip name")
	t.finish()
	quit()
