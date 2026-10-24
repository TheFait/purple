extends Node
class_name GameEngine
## Authoritative "Purple & Post" rules. Pure data (CardData) — no visuals.
## Identical logic runs on the server, in offline mode, and in tests.
##
## The Stack (`table_cards`) holds correct guesses; the flip being judged is
## appended tentatively, so a wrong flip counts toward the drinks before the
## stack clears. Top Card = last, Drop Card = the one before it.

enum Move { HIGHER, LOWER, RED, BLACK, PURPLE, POST, INSIDE, OUTSIDE }

signal card_revealed(card: CardData)
signal phantoms_added(cards: Array)
signal table_cleared()
signal streak_changed(streak: int)
signal pool_changed(pool: int)
signal penalty_triggered(seat: int, amount: int)
signal pass_available(is_available: bool)
signal turn_changed(seat: int)
signal diamonds_forever()
signal round_log(text: String)

var seat_count: int = 2
var streak_to_pass: int = 3

var table_cards: Array[CardData] = []
## Cards the current player has added to the stack since they took over
## (Purple counts 2; Post doubling adds none).
var current_streak: int = 0
var current_seat: int = 0

var _deck: DeckEngine

func setup(deck: DeckEngine, seats: int) -> void:
	_deck = deck
	seat_count = max(1, seats)
	current_seat = 0
	current_streak = 0
	table_cards.clear()
	table_cleared.emit()
	pool_changed.emit(drink_pool())
	streak_changed.emit(current_streak)
	pass_available.emit(false)
	turn_changed.emit(current_seat)
	round_log.emit("Game start — seat %d's turn." % (current_seat + 1))

func active_card() -> CardData:
	return table_cards.back() if not table_cards.is_empty() else null

func drink_pool() -> int:
	return table_cards.size()

func legal_moves() -> Array[int]:
	return legal_moves_for(table_cards.size())

## Which guesses a stack of `stack_size` allows. Static so a client presenter can
## gray out buttons from the pool count alone.
static func legal_moves_for(stack_size: int) -> Array[int]:
	var moves: Array[int] = [Move.RED, Move.BLACK, Move.PURPLE]
	if stack_size >= 1:
		moves.append_array([Move.HIGHER, Move.LOWER])
	if stack_size >= 2:
		moves.append_array([Move.INSIDE, Move.OUTSIDE, Move.POST])
	return moves

func can_pass() -> bool:
	return current_streak >= streak_to_pass

# --- authority-gated entry points (server passes the caller's seat) ---

func submit_move(seat: int, move: int) -> bool:
	if seat != current_seat or not (move in legal_moves()):
		return false
	var top: CardData = active_card()
	var drop: CardData = table_cards[table_cards.size() - 2] if table_cards.size() >= 2 else null
	match move:
		Move.HIGHER:
			var c := _draw_one()
			_resolve(c.rank > top.rank, 1, c, top, drop, "Higher — %s vs %s" % [c, top])
		Move.LOWER:
			var c := _draw_one()
			_resolve(c.rank < top.rank, 1, c, top, drop, "Lower — %s vs %s" % [c, top])
		Move.INSIDE:
			var c := _draw_one()
			var lo := mini(top.rank, drop.rank)
			var hi := maxi(top.rank, drop.rank)
			_resolve(c.rank > lo and c.rank < hi, 1, c, top, drop, "Inside — %s in %s..%s" % [c, drop, top])
		Move.OUTSIDE:
			var c := _draw_one()
			var lo := mini(top.rank, drop.rank)
			var hi := maxi(top.rank, drop.rank)
			_resolve(c.rank < lo or c.rank > hi, 1, c, top, drop, "Outside — %s vs %s..%s" % [c, drop, top])
		Move.RED:
			var c := _draw_one()
			_resolve(c.is_red(), 1, c, top, drop, "Red — %s" % c)
		Move.BLACK:
			var c := _draw_one()
			_resolve(c.is_black(), 1, c, top, drop, "Black — %s" % c)
		Move.PURPLE:
			var first := _draw_one()
			var second := _draw_one()
			# Post doubling is judged on a single flip, so Purple never doubles.
			_resolve(first.is_red() != second.is_red(), 2, null, null, null, "Purple — %s + %s" % [first, second])
		Move.POST:
			var c := _draw_one()
			if c.rank == top.rank:
				_win(1, "Post hit! %s matches %s" % [c, top])
				_double_stack()
			else:
				_lose(false, "Failed Post — %s misses %s" % [c, top])
	return true

func request_pass(seat: int) -> bool:
	if seat != current_seat or not can_pass():
		return false
	round_log.emit("Seat %d passes with a stack of %d." % [current_seat + 1, drink_pool()])
	current_streak = 0
	streak_changed.emit(current_streak)
	pass_available.emit(false)
	_advance_seat()
	return true

# --- internals ---

func _resolve(correct: bool, gain: int, flip: CardData, top: CardData, drop: CardData, reason: String) -> void:
	if correct:
		_win(gain, reason)
		if flip != null and top != null and drop != null and flip.suit == Globals.SUITS.DIAMONDS \
				and top.suit == Globals.SUITS.DIAMONDS and drop.suit == Globals.SUITS.DIAMONDS:
			round_log.emit("Diamonds are Forever! Everyone drinks.")
			diamonds_forever.emit()
	else:
		# A wrong guess whose flip ties the Top Card's rank is an unguessed Post.
		_lose(flip != null and top != null and flip.rank == top.rank, reason)

func _win(streak_gain: int, reason: String) -> void:
	current_streak += streak_gain
	streak_changed.emit(current_streak)
	pool_changed.emit(drink_pool())
	round_log.emit("%s  (contributed %d, stack %d)" % [reason, current_streak, drink_pool()])
	if can_pass():
		pass_available.emit(true)
		round_log.emit("Contributed %d — Pass the stack on, or keep guessing." % current_streak)

func _lose(post_double: bool, reason: String) -> void:
	var amount: int = drink_pool() * (2 if post_double else 1)
	if post_double:
		round_log.emit("Post! The flip ties the Top Card — drinks double.")
	round_log.emit("%s  ->  seat %d drinks %d." % [reason, current_seat + 1, amount])
	penalty_triggered.emit(current_seat, amount)
	_clear_table()

func _double_stack() -> void:
	## A called Post duplicates every stack card as phantoms (they count, but never
	## return to the deck). Prepended so the real Top and Drop Cards are unchanged.
	var copies: Array[CardData] = []
	for c in table_cards:
		copies.append(c.phantom_copy())
	table_cards = copies + table_cards
	phantoms_added.emit(copies)
	pool_changed.emit(drink_pool())
	round_log.emit("Phantom cards! The stack doubles to %d." % drink_pool())

func _draw_one() -> CardData:
	_ensure_cards()
	var card: CardData = _deck.draw()
	table_cards.append(card)
	card_revealed.emit(card)
	pool_changed.emit(drink_pool())
	return card

func _clear_table() -> void:
	var real: Array[CardData] = []
	for c in table_cards:
		if not c.phantom:
			real.append(c)
	_deck.discard(real)
	table_cards.clear()
	current_streak = 0
	table_cleared.emit()
	pool_changed.emit(drink_pool())
	streak_changed.emit(current_streak)
	pass_available.emit(false)

func _ensure_cards() -> void:
	# DeckEngine.draw() already recycles discard when empty. Last resort: if the
	# discard is also dry, recycle real stack cards except the Top and Drop.
	if _deck.deck_size() + _deck.discard_size() > 0:
		return
	var keep_from: int = maxi(table_cards.size() - 2, 0)
	var recycled: Array[CardData] = []
	var kept: Array[CardData] = []
	for i in table_cards.size():
		if i < keep_from and not table_cards[i].phantom:
			recycled.append(table_cards[i])
		elif i < keep_from:
			continue
		else:
			kept.append(table_cards[i])
	_deck.return_to_deck(recycled)
	table_cards = kept
	round_log.emit("Deck recycled mid-stack to keep play going.")

func reconcile_seats(new_count: int) -> void:
	## Called when a player disconnects mid-game. Clamps seat_count and
	## current_seat so turn rotation never lands on a vacated index.
	seat_count = max(1, new_count)
	if current_seat >= seat_count:
		current_seat = current_seat % seat_count
	turn_changed.emit(current_seat)
	round_log.emit("Player left — seat count now %d, seat %d's turn." % [seat_count, current_seat + 1])

func _advance_seat() -> void:
	current_seat = (current_seat + 1) % seat_count
	turn_changed.emit(current_seat)
	round_log.emit("Seat %d's turn — inheriting a stack of %d." % [current_seat + 1, drink_pool()])
