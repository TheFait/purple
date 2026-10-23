extends SceneTree
## Parity suite for the Purple rules (see the rules doc). Decks are rigged so each
## case is deterministic; `draws` lists cards in the order they will be drawn.

const H := 0
const S := 1
const D := 2
const C := 3

var t := TestHelper.new()

func _suit(code: int) -> int:
	match code:
		H: return Globals.SUITS.HEARTS
		S: return Globals.SUITS.SPADES
		D: return Globals.SUITS.DIAMONDS
	return Globals.SUITS.CLUBS

func _card(rank: int, suit_code: int) -> CardData:
	return CardData.new(rank, _suit(suit_code), "%d/%d" % [rank, suit_code])

func _make(draws: Array, seats: int = 2) -> Dictionary:
	# Filler sits at the bottom of the deck so tests can't run dry.
	var cards: Array = []
	for i in range(30):
		cards.append(_card(2 + (i % 13), C))
	for i in range(draws.size() - 1, -1, -1):
		cards.append(_card(draws[i][0], draws[i][1]))
	var deck := DeckEngine.new()
	deck.load_cards(cards)
	var engine := GameEngine.new()
	get_root().add_child(engine)
	var log := {"penalties": [], "diamonds": 0, "phantoms": 0, "pass": false}
	engine.penalty_triggered.connect(func(seat: int, amount: int): log.penalties.append([seat, amount]))
	engine.diamonds_forever.connect(func(): log.diamonds += 1)
	engine.phantoms_added.connect(func(cs: Array): log.phantoms += cs.size())
	engine.pass_available.connect(func(on: bool): log.pass = on)
	engine.setup(deck, seats)
	return {"engine": engine, "deck": deck, "log": log}

func _initialize() -> void:
	seed(12345)
	_test_setup()
	_test_legality()
	_test_color_and_higher_lower()
	_test_inside_outside()
	_test_losses_and_post_double()
	_test_post_call()
	_test_purple()
	_test_pass_inherits_stack()
	_test_diamonds()
	_test_fuzz_invariants()
	t.finish()
	quit()

func _test_setup() -> void:
	var g := _make([])
	var e: GameEngine = g.engine
	t.eq(e.drink_pool(), 0, "stack starts empty")
	t.check(e.active_card() == null, "no active card at start")
	t.eq(e.current_seat, 0, "starts on seat 0")
	t.eq(e.legal_moves(), [GameEngine.Move.RED, GameEngine.Move.BLACK, GameEngine.Move.PURPLE], "empty stack: color or Purple only")
	t.check(GameEngine.Move.INSIDE in GameEngine.legal_moves_for(2) and not (GameEngine.Move.INSIDE in GameEngine.legal_moves_for(1)), "Inside needs two cards")

func _test_legality() -> void:
	var g := _make([[5, H], [9, S]])
	var e: GameEngine = g.engine
	t.check(not e.submit_move(1, GameEngine.Move.RED), "out-of-turn move rejected")
	t.check(not e.submit_move(0, GameEngine.Move.HIGHER), "Higher illegal on empty stack")
	t.check(not e.submit_move(0, GameEngine.Move.POST), "Post illegal on empty stack")
	t.eq(e.drink_pool(), 0, "rejected moves change nothing")
	t.check(e.submit_move(0, GameEngine.Move.RED), "Red accepted")
	t.check(not e.submit_move(0, GameEngine.Move.INSIDE), "Inside illegal with one card")
	t.check(GameEngine.Move.HIGHER in e.legal_moves(), "Higher legal with one card")
	t.check(not (GameEngine.Move.POST in e.legal_moves()), "Post illegal with only one card")
	t.check(not e.submit_move(0, GameEngine.Move.POST), "Post call rejected with one card")
	e.submit_move(0, GameEngine.Move.HIGHER)
	t.check(GameEngine.Move.POST in e.legal_moves(), "Post legal once Inside/Outside are")

func _test_color_and_higher_lower() -> void:
	var g := _make([[5, H], [9, S], [4, D]])
	var e: GameEngine = g.engine
	e.submit_move(0, GameEngine.Move.RED)
	t.eq(e.drink_pool(), 1, "correct Red adds 1 card")
	t.eq(e.current_streak, 1, "correct guess is 1 contribution")
	e.submit_move(0, GameEngine.Move.HIGHER)
	t.eq(e.drink_pool(), 2, "correct Higher adds the flip to the stack")
	t.eq(e.active_card().rank, 9, "Top Card is the last correct flip")
	e.submit_move(0, GameEngine.Move.LOWER)
	t.eq(e.drink_pool(), 3, "correct Lower adds the flip")
	t.eq(e.current_seat, 0, "turn stays after correct guesses")

func _test_inside_outside() -> void:
	# Stack 5, 9 -> inside is 5<x<9. Flips: 7 (inside win), then stack 5,9,7 top 7 drop 9.
	var g := _make([[5, H], [9, S], [7, D], [2, C]])
	var e: GameEngine = g.engine
	e.submit_move(0, GameEngine.Move.RED)
	e.submit_move(0, GameEngine.Move.HIGHER)
	t.check(e.submit_move(0, GameEngine.Move.INSIDE), "Inside legal with two cards")
	t.eq(e.drink_pool(), 3, "7 is inside 5..9")
	t.eq(e.current_streak, 3, "three contributions so far")
	# Top 7, drop 9, flip 2 is outside the 7..9 range.
	e.submit_move(0, GameEngine.Move.OUTSIDE)
	t.eq(e.drink_pool(), 4, "2 is outside 7..9")

	# Tie with the Drop Card only is a plain loss (no Post double).
	var g2 := _make([[5, H], [9, S], [5, D]])
	var e2: GameEngine = g2.engine
	e2.submit_move(0, GameEngine.Move.RED)
	e2.submit_move(0, GameEngine.Move.HIGHER)
	e2.submit_move(0, GameEngine.Move.INSIDE)
	t.eq(g2.log.penalties, [[0, 3]], "tie with Drop Card loses without doubling (stack 2 + flip)")

	# Tie with the Top Card on Outside is a Post: doubled.
	var g3 := _make([[5, H], [9, S], [9, D]])
	var e3: GameEngine = g3.engine
	e3.submit_move(0, GameEngine.Move.RED)
	e3.submit_move(0, GameEngine.Move.HIGHER)
	e3.submit_move(0, GameEngine.Move.OUTSIDE)
	t.eq(g3.log.penalties, [[0, 6]], "tie with Top Card is an unguessed Post: (2+1)*2")

func _test_losses_and_post_double() -> void:
	# Higher loss on a stack of 1 + wrong flip = 2 drinks; same seat retries on empty stack.
	var g := _make([[8, H], [3, S]])
	var e: GameEngine = g.engine
	e.submit_move(0, GameEngine.Move.RED)
	e.submit_move(0, GameEngine.Move.HIGHER)
	t.eq(g.log.penalties, [[0, 2]], "wrong flip counts toward drinks")
	t.eq(e.drink_pool(), 0, "stack cleared after a loss")
	t.eq(e.current_seat, 0, "same player guesses again after a loss")
	t.eq(e.current_streak, 0, "contributions reset")
	t.eq(g.deck.discard_size(), 2, "cleared cards go to the discard")

	# Unguessed Post: Higher with a tie doubles.
	var g2 := _make([[8, H], [8, S]])
	var e2: GameEngine = g2.engine
	e2.submit_move(0, GameEngine.Move.RED)
	e2.submit_move(0, GameEngine.Move.HIGHER)
	t.eq(g2.log.penalties, [[0, 4]], "tie on Higher: (1+1)*2")

	# A wrong color guess that ties the Top Card's rank also doubles.
	var g3 := _make([[8, H], [8, S]])
	var e3: GameEngine = g3.engine
	e3.submit_move(0, GameEngine.Move.RED)
	e3.submit_move(0, GameEngine.Move.RED)
	t.eq(g3.log.penalties, [[0, 4]], "wrong color on a rank tie doubles")

func _test_post_call() -> void:
	# Stack 8, 9; Post flips another 9: contributes 1, stack doubles with phantoms.
	var g := _make([[8, H], [9, S], [9, H], [10, C]])
	var e: GameEngine = g.engine
	e.submit_move(0, GameEngine.Move.RED)
	e.submit_move(0, GameEngine.Move.HIGHER)
	e.submit_move(0, GameEngine.Move.POST)
	t.eq(e.drink_pool(), 6, "correct Post doubles the stack (3 -> 6)")
	t.eq(e.current_streak, 3, "Post is 1 contribution; doubling adds none")
	t.eq(g.log.phantoms, 3, "three phantom copies announced")
	var phantoms := 0
	for c in e.table_cards:
		if c.phantom:
			phantoms += 1
	t.eq(phantoms, 3, "phantoms flagged on the stack")
	t.eq(e.active_card().phantom, false, "Top Card remains the real Post flip")
	# Loss now: stack 6 + wrong flip. Phantoms never reach the discard.
	e.submit_move(0, GameEngine.Move.LOWER)
	t.eq(g.log.penalties, [[0, 7]], "phantoms count toward drinks")
	t.eq(g.deck.discard_size(), 4, "only real cards (3 + flip) are discarded")

	# Wrong Post call is a plain loss (not doubled).
	var g2 := _make([[8, H], [9, S], [3, H]])
	var e2: GameEngine = g2.engine
	e2.submit_move(0, GameEngine.Move.RED)
	e2.submit_move(0, GameEngine.Move.HIGHER)
	e2.submit_move(0, GameEngine.Move.POST)
	t.eq(g2.log.penalties, [[0, 3]], "failed Post call: stack + flip, no double")

func _test_purple() -> void:
	var g := _make([[5, H], [6, S]])
	var e: GameEngine = g.engine
	e.submit_move(0, GameEngine.Move.PURPLE)
	t.eq(e.drink_pool(), 2, "correct Purple adds 2 cards")
	t.eq(e.current_streak, 2, "correct Purple is 2 contributions")

	var g2 := _make([[5, H], [6, D]])
	var e2: GameEngine = g2.engine
	e2.submit_move(0, GameEngine.Move.PURPLE)
	t.eq(g2.log.penalties, [[0, 2]], "failed Purple drinks both flips")
	t.eq(e2.current_seat, 0, "same player after failed Purple")

func _test_pass_inherits_stack() -> void:
	var g := _make([[5, H], [6, H], [7, D], [9, S]])
	var e: GameEngine = g.engine
	e.submit_move(0, GameEngine.Move.RED)
	e.submit_move(0, GameEngine.Move.RED)
	t.check(not e.request_pass(0), "cannot pass with 2 contributions")
	e.submit_move(0, GameEngine.Move.RED)
	t.check(g.log.pass, "pass available at 3 contributions")
	t.check(e.submit_move(0, GameEngine.Move.HIGHER), "can keep guessing instead of passing")
	t.eq(e.drink_pool(), 4, "stack grew to 4")
	t.check(not e.request_pass(1), "wrong seat cannot pass")
	t.check(e.request_pass(0), "pass allowed after any correct guess at 3+")
	t.eq(e.current_seat, 1, "turn moves to the next seat")
	t.eq(e.drink_pool(), 4, "next player inherits the stack")
	t.eq(e.current_streak, 0, "inheritor's contributions start at 0")
	t.check(not e.request_pass(1), "inheritor cannot pass immediately")
	t.check(not g.log.pass, "pass no longer offered")
	e.submit_move(1, GameEngine.Move.RED)
	t.eq(g.log.penalties, [[1, 5]], "inheritor loses the inherited 4 + the wrong flip (filler card is black)")

func _test_diamonds() -> void:
	var g := _make([[2, D], [3, D], [4, D]])
	var e: GameEngine = g.engine
	e.submit_move(0, GameEngine.Move.RED)
	e.submit_move(0, GameEngine.Move.HIGHER)
	t.eq(g.log.diamonds, 0, "not with fewer than a Top and Drop")
	e.submit_move(0, GameEngine.Move.HIGHER)
	t.eq(g.log.diamonds, 1, "Flip, Top and Drop all diamonds on a correct guess")

	var g2 := _make([[2, D], [3, D], [4, H]])
	var e2: GameEngine = g2.engine
	e2.submit_move(0, GameEngine.Move.RED)
	e2.submit_move(0, GameEngine.Move.HIGHER)
	e2.submit_move(0, GameEngine.Move.HIGHER)
	t.eq(g2.log.diamonds, 0, "a heart flip is not Diamonds are Forever")

	# Wrong guess with three diamonds does not trigger it.
	var g3 := _make([[5, D], [9, D], [2, D]])
	var e3: GameEngine = g3.engine
	e3.submit_move(0, GameEngine.Move.RED)
	e3.submit_move(0, GameEngine.Move.HIGHER)
	e3.submit_move(0, GameEngine.Move.HIGHER)
	t.eq(g3.log.diamonds, 0, "only on correct guesses")

func _test_fuzz_invariants() -> void:
	var deck := DeckEngine.new()
	deck.load_from_json("res://assets/database/card_database.json", "res://assets/database/card_collection.json")
	var total: int = deck.deck_size()
	var engine := GameEngine.new()
	get_root().add_child(engine)
	var penalties := {"n": 0}
	engine.penalty_triggered.connect(func(_s: int, _a: int): penalties.n += 1)
	engine.setup(deck, 3)
	for i in range(400):
		var moves := engine.legal_moves()
		engine.submit_move(engine.current_seat, moves[randi() % moves.size()])
		if engine.current_streak >= engine.streak_to_pass and randf() < 0.5:
			engine.request_pass(engine.current_seat)
		var real := 0
		for c in engine.table_cards:
			if not c.phantom:
				real += 1
		t.check(real + deck.deck_size() + deck.discard_size() == total, "no real card lost or duplicated (i=%d)" % i)
		t.check(engine.current_seat >= 0 and engine.current_seat < 3, "seat in range (i=%d)" % i)
	t.check(penalties.n > 0, "penalties fired during fuzz")
