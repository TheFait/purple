extends Node
class_name GameEngine
## Authoritative "Purple & Post" rules. Pure data (CardData) — no visuals.
## Identical logic runs on the server, in offline mode, and in tests.

enum Move { HIGHER, LOWER, RED, BLACK, PURPLE, POST }

signal card_revealed(card: CardData)
signal table_cleared()
signal streak_changed(streak: int)
signal pool_changed(pool: int)
signal penalty_triggered(seat: int, amount: int)
signal pass_available(is_available: bool)
signal turn_changed(seat: int)
signal round_log(text: String)

var seat_count: int = 2
var streak_to_pass: int = 3
var count_drawn_card_in_penalty: bool = true

var table_cards: Array[CardData] = []
var current_streak: int = 0
var current_seat: int = 0

var _deck: DeckEngine
var _awaiting_pass: bool = false

func setup(deck: DeckEngine, seats: int) -> void:
	_deck = deck
	seat_count = max(1, seats)
	current_seat = 0
	current_streak = 0
	_awaiting_pass = false
	_seed_active_card()
	streak_changed.emit(current_streak)
	pass_available.emit(false)
	turn_changed.emit(current_seat)
	round_log.emit("Game start — seat %d's turn." % current_seat)

func active_card() -> CardData:
	return table_cards.back()

func drink_pool() -> int:
	return table_cards.size()

# --- authority-gated entry points (server passes the caller's seat) ---

func submit_move(seat: int, move: int) -> bool:
	if not _can_act(seat):
		return false
	var reference: CardData = active_card()
	var pool_before: int = table_cards.size()
	match move:
		Move.HIGHER:
			var c := _draw_one()
			if c.rank > reference.rank:
				_win(1, "Higher — %s beats %s" % [c, reference])
			elif c.rank == reference.rank:
				_lose(true, pool_before, "Accidental Post! %s ties %s" % [c, reference])
			else:
				_lose(false, pool_before, "Higher missed — %s under %s" % [c, reference])
		Move.LOWER:
			var c := _draw_one()
			if c.rank < reference.rank:
				_win(1, "Lower — %s under %s" % [c, reference])
			elif c.rank == reference.rank:
				_lose(true, pool_before, "Accidental Post! %s ties %s" % [c, reference])
			else:
				_lose(false, pool_before, "Lower missed — %s over %s" % [c, reference])
		Move.RED:
			var c := _draw_one()
			if c.is_red():
				_win(1, "Red — %s" % c)
			else:
				_lose(false, pool_before, "Red missed — %s is black" % c)
		Move.BLACK:
			var c := _draw_one()
			if c.is_black():
				_win(1, "Black — %s" % c)
			else:
				_lose(false, pool_before, "Black missed — %s is red" % c)
		Move.PURPLE:
			var first := _draw_one()
			var second := _draw_one()
			if first.is_red() != second.is_red():
				_win(2, "Purple! %s + %s split colors" % [first, second])
			else:
				_lose(false, pool_before, "Purple busted — %s + %s match color" % [first, second])
		Move.POST:
			var c := _draw_one()
			if c.rank == reference.rank:
				_win(1, "Post hit! %s matches %s" % [c, reference])
			else:
				_lose(true, pool_before, "Failed Post — %s misses %s" % [c, reference])
		_:
			return false
	return true

func request_pass(seat: int) -> bool:
	if not _awaiting_pass or seat != current_seat:
		return false
	round_log.emit("Seat %d passes the turn." % current_seat)
	_clear_table_and_reseed()
	_advance_seat()
	return true

func request_ride(seat: int) -> bool:
	if not _awaiting_pass or seat != current_seat:
		return false
	_awaiting_pass = false
	pass_available.emit(false)
	round_log.emit("Seat %d rides — pool now %d." % [current_seat, drink_pool()])
	return true

# --- internals ---

func _can_act(seat: int) -> bool:
	if _awaiting_pass:
		return false
	if seat != current_seat:
		return false
	if table_cards.is_empty():
		return false
	return true

func _win(streak_gain: int, reason: String) -> void:
	current_streak += streak_gain
	streak_changed.emit(current_streak)
	pool_changed.emit(drink_pool())
	round_log.emit("%s  (streak %d, pool %d)" % [reason, current_streak, drink_pool()])
	if current_streak >= streak_to_pass:
		_awaiting_pass = true
		pass_available.emit(true)
		round_log.emit("Streak %d — Pass to bank it, or Ride to push the pool." % current_streak)

func _lose(double_penalty: bool, pool_before_draw: int, reason: String) -> void:
	var base_pool: int = drink_pool() if count_drawn_card_in_penalty else pool_before_draw
	var amount: int = base_pool * (2 if double_penalty else 1)
	round_log.emit("%s  ->  seat %d drinks %d." % [reason, current_seat, amount])
	penalty_triggered.emit(current_seat, amount)
	_clear_table_and_reseed()
	_advance_seat()

func _draw_one() -> CardData:
	_ensure_cards(1)
	var card: CardData = _deck.draw()
	table_cards.append(card)
	card_revealed.emit(card)
	pool_changed.emit(drink_pool())
	return card

func _seed_active_card() -> void:
	table_cards.clear()
	table_cleared.emit()
	_draw_one()

func _clear_table_and_reseed() -> void:
	_deck.discard(table_cards)
	table_cards.clear()
	table_cleared.emit()
	current_streak = 0
	_awaiting_pass = false
	streak_changed.emit(current_streak)
	pass_available.emit(false)
	_draw_one()

func _ensure_cards(needed: int) -> void:
	# DeckEngine.draw() already recycles discard when empty. Last resort: if the
	# discard is also dry, recycle all table cards except the active one.
	if _deck.deck_size() + _deck.discard_size() >= needed:
		return
	if table_cards.size() > 1:
		var keep: CardData = table_cards.back()
		var recycled := table_cards.slice(0, table_cards.size() - 1)
		_deck.return_to_deck(recycled)
		table_cards = [keep]
		round_log.emit("Deck recycled mid-ride to keep play going.")

func reconcile_seats(new_count: int) -> void:
	## Called when a player disconnects mid-game. Clamps seat_count and
	## current_seat so turn rotation never lands on a vacated index.
	seat_count = max(1, new_count)
	if current_seat >= seat_count:
		current_seat = current_seat % seat_count
	turn_changed.emit(current_seat)
	round_log.emit("Player left — seat count now %d, seat %d's turn." % [seat_count, current_seat])

func _advance_seat() -> void:
	current_seat = (current_seat + 1) % seat_count
	turn_changed.emit(current_seat)
	round_log.emit("Seat %d's turn — pool starts at %d." % [current_seat, drink_pool()])
