extends Node2D
class_name GameManager
## game_manager.gd — "Purple & Post" turn engine.
##
## Replaces the old game.gd TURN_PHASE / per-move Guess-scene flow with a single
## state machine that owns the rules and drives the EXISTING visual nodes:
##   * Deck  (scenes/Deck.gd)  — card source: draw_card(), clear_stack(), shuffle.
##   * Stack (Control)         — the "table zone" where face-up Card nodes live.
##   * Card  (scenes/card.gd)  — a Control visual node exposing `rank` and `suit`.
##
## The six moves are expressed as a `Move` enum routed through `_on_move_selected`.
##
## Wiring contract (the manager NEVER touches Labels/Buttons directly):
##   * Action buttons  -> call `_on_move_selected(Move.HIGHER)` … `Move.POST`
##                        (e.g. `button.pressed.connect(_on_move_selected.bind(Move.HIGHER))`)
##   * Pass button     -> call `request_pass()`
##   * Ride button     -> call `request_ride()`
##   * Labels          -> bind to the signals below.

# ---------------------------------------------------------------------------
# Types
# ---------------------------------------------------------------------------

## The six legal moves a player may declare on their turn.
enum Move { HIGHER, LOWER, RED, BLACK, PURPLE, POST }

# ---------------------------------------------------------------------------
# Signals — UI binds to these for a fully decoupled view layer.
# ---------------------------------------------------------------------------

signal penalty_triggered(amount: int)      ## Loss occurred; `amount` drinks owed.
signal streak_changed(streak: int)         ## Active player's streak changed.
signal pool_changed(pool: int)             ## Drink pool == table_cards.size().
signal pass_available(is_available: bool)  ## Show/hide the Pass & Ride buttons.
signal turn_changed(player_index: int)     ## Active player handed off.
signal log_message(text: String)           ## Human-readable play-by-play.

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

@export var player_count: int = 2
@export var streak_to_pass: int = 3

## Resolves a spec ambiguity: are the just-drawn card(s) counted in the drink
## penalty?
##   true  -> penalty = table size AFTER the draw (the "cards face-up on the
##            table" reading; matches the Purple description in the blueprint).
##   false -> penalty = table size BEFORE the draw (the append-on-win reading).
@export var count_drawn_card_in_penalty: bool = true

## NodePaths into the existing scene tree (Deck and Stack live under the UI).
@export var deck_node_path: NodePath = ^"UI/Deck"
@export var table_zone_path: NodePath = ^"UI/Stack"

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var table_cards: Array[Card] = []   ## Face-up cards; the active card is the last.
var current_streak: int = 0         ## Correct guesses THIS turn only.
var current_player: int = 0         ## 0-based active player index.

var _awaiting_pass_decision: bool = false  ## True while waiting for Pass/Ride.

@onready var deck_component: Deck = get_node(deck_node_path)
@onready var table_zone: Node = get_node(table_zone_path)

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	# The Deck node is a grandchild, so its _ready() (which loads + shuffles the
	# full deck) has already run by the time we get here. Seed the opening card.
	_seed_active_card()
	current_streak = 0
	_awaiting_pass_decision = false
	streak_changed.emit(current_streak)
	pass_available.emit(false)
	turn_changed.emit(current_player)
	_log("Game start — player %d's turn." % current_player)

# ---------------------------------------------------------------------------
# Public API — wire your UI to these.
# ---------------------------------------------------------------------------

## Entry point for the six action buttons.
func _on_move_selected(chosen_move: Move) -> void:
	if _awaiting_pass_decision:
		_log("Resolve Pass or Ride before guessing again.")
		return
	if table_cards.is_empty():
		_log("No active card on the table yet.")
		return

	# The card we compare against, captured BEFORE this move's draw(s).
	var reference: Card = active_card()
	# Table size before this move — used when penalties exclude the drawn card.
	var pool_before: int = table_cards.size()

	var drawn: Card
	match chosen_move:
		Move.HIGHER:
			drawn = _draw_one()
			if drawn.rank > reference.rank:
				_win(1, "Higher — %s beats %s" % [drawn, reference])
			elif drawn.rank == reference.rank:
				_lose(true, pool_before, "Accidental Post! %s ties %s" % [drawn, reference])
			else:
				_lose(false, pool_before, "Higher missed — %s under %s" % [drawn, reference])

		Move.LOWER:
			drawn = _draw_one()
			if drawn.rank < reference.rank:
				_win(1, "Lower — %s under %s" % [drawn, reference])
			elif drawn.rank == reference.rank:
				_lose(true, pool_before, "Accidental Post! %s ties %s" % [drawn, reference])
			else:
				_lose(false, pool_before, "Lower missed — %s over %s" % [drawn, reference])

		Move.RED:
			drawn = _draw_one()
			if _is_red(drawn):
				_win(1, "Red — %s" % drawn)
			else:
				_lose(false, pool_before, "Red missed — %s is black" % drawn)

		Move.BLACK:
			drawn = _draw_one()
			if _is_black(drawn):
				_win(1, "Black — %s" % drawn)
			else:
				_lose(false, pool_before, "Black missed — %s is red" % drawn)

		Move.PURPLE:
			# Draw two simultaneously; both go on the table.
			var first: Card = _draw_one()
			var second: Card = _draw_one()
			# Win iff exactly one of the two is red (=> the other is black).
			if _is_red(first) != _is_red(second):
				_win(2, "Purple! %s + %s split colors" % [first, second])
			else:
				_lose(false, pool_before, "Purple busted — %s + %s match color" % [first, second])

		Move.POST:
			# Intentional Post: you WANT an exact rank match.
			drawn = _draw_one()
			if drawn.rank == reference.rank:
				_win(1, "Post hit! %s matches %s" % [drawn, reference])
			else:
				_lose(true, pool_before, "Failed Post — %s misses %s" % [drawn, reference])

## Player banks the turn after reaching the pass threshold.
func request_pass() -> void:
	if not _awaiting_pass_decision:
		return
	_log("Player %d passes the turn." % current_player)
	_clear_table_and_reseed()
	_advance_player()

## Player keeps riding to grow the pool for the next player.
func request_ride() -> void:
	if not _awaiting_pass_decision:
		return
	_awaiting_pass_decision = false
	pass_available.emit(false)
	_log("Player %d rides — pool now %d." % [current_player, drink_pool()])

# ---------------------------------------------------------------------------
# Convenience getters
# ---------------------------------------------------------------------------

## The most recently revealed card — the one the next guess is measured against.
func active_card() -> Card:
	return table_cards.back()

## Drinks currently at stake == number of face-up cards on the table.
func drink_pool() -> int:
	return table_cards.size()

# ---------------------------------------------------------------------------
# Outcome handling
# ---------------------------------------------------------------------------

func _win(streak_gain: int, reason: String) -> void:
	current_streak += streak_gain
	streak_changed.emit(current_streak)
	pool_changed.emit(drink_pool())
	_log("%s  (streak %d, pool %d)" % [reason, current_streak, drink_pool()])
	# Turn continues. At the threshold, surface the Pass / Ride choice and lock
	# out further moves until the player decides.
	if current_streak >= streak_to_pass:
		_awaiting_pass_decision = true
		pass_available.emit(true)
		_log("Streak %d — Pass to bank it, or Ride to push the pool higher." % current_streak)

func _lose(double_penalty: bool, pool_before_draw: int, reason: String) -> void:
	var base_pool: int = drink_pool() if count_drawn_card_in_penalty else pool_before_draw
	var amount: int = base_pool * (2 if double_penalty else 1)
	_log("%s  ->  player %d drinks %d." % [reason, current_player, amount])
	penalty_triggered.emit(amount)
	_clear_table_and_reseed()
	_advance_player()

# ---------------------------------------------------------------------------
# Table / deck plumbing — storage is delegated to the existing Deck node.
# ---------------------------------------------------------------------------

## Draw one card through the Deck node, reveal it on the table, and track it.
func _draw_one() -> Card:
	_ensure_cards(1)
	var card: Card = deck_component.draw_card()  # pops from deck, flips face-up
	table_zone.add_child(card)
	# Recycled cards don't re-run _ready(), so refresh their face explicitly.
	card.update_display()
	table_cards.append(card)
	_sync_counters()
	return card

## Seed a single fresh face-up card to start a turn.
func _seed_active_card() -> void:
	_draw_one()
	pool_changed.emit(drink_pool())

## Move the whole table to discard, reshuffle, and deal a fresh active card.
func _clear_table_and_reseed() -> void:
	_strip_table_visuals()
	deck_component.clear_stack()  # recycles the stack + discard back into the deck
	_seed_active_card()
	current_streak = 0
	_awaiting_pass_decision = false
	streak_changed.emit(current_streak)
	pass_available.emit(false)

## Remove the table's Card nodes from the scene and flip them face-down so the
## next draw's flip() reveals them correctly. Instances stay alive — the Deck
## still references them and recycles them back into the deck.
func _strip_table_visuals() -> void:
	for card in table_cards:
		if is_instance_valid(card):
			card.is_facedown = true
			card.update_display()
			if card.get_parent() == table_zone:
				table_zone.remove_child(card)
	table_cards.clear()

## Deck-exhaustion guard. The Deck reshuffles everything on each turn reset, so
## this only bites during a very long ride. Recycle the discard pile first (per
## spec, leaving the live table untouched); fall back to recycling all but the
## active card if we are still short.
func _ensure_cards(needed: int) -> void:
	if deck_component.deck.size() >= needed:
		return
	if deck_component.discard_pile.size() > 0:
		deck_component.deck.append_array(deck_component.discard_pile)
		deck_component.discard_pile.clear()
		deck_component.deck.shuffle()
		_log("Deck recycled from the discard pile.")
	if deck_component.deck.size() >= needed:
		return
	# Last resort: keep the active card, recycle the rest of the table.
	while deck_component.deck.size() < needed and table_cards.size() > 1:
		var bottom: Card = table_cards.pop_front()
		if is_instance_valid(bottom):
			bottom.is_facedown = true
			if bottom.get_parent() == table_zone:
				table_zone.remove_child(bottom)
			deck_component.deck.append(bottom)
	deck_component.deck.shuffle()
	_log("Deck recycled mid-ride to keep play going.")

func _advance_player() -> void:
	current_player = (current_player + 1) % player_count
	turn_changed.emit(current_player)
	_log("Player %d's turn — pool starts at %d." % [current_player, drink_pool()])

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _is_red(card: Card) -> bool:
	return card.suit == Globals.SUITS.HEARTS or card.suit == Globals.SUITS.DIAMONDS

func _is_black(card: Card) -> bool:
	return card.suit == Globals.SUITS.SPADES or card.suit == Globals.SUITS.CLUBS

func _sync_counters() -> void:
	# These setters emit Globals.update_ui, refreshing the existing Deck/Stack labels.
	Globals.cards_in_deck = deck_component.deck.size()
	Globals.cards_in_stack = table_cards.size()

func _log(text: String) -> void:
	print("[P&P] ", text)
	log_message.emit(text)
