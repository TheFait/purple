extends Control
class_name Table
## The felt: a deck, the stack of cards on the table, and the reveal of each new card.
## Owns all card-node animation (deal, suspense, flip, settle, sweep). Holds no rules.
##
## The stack has two looks. At rest it is shown zoomed and cropped by the top of the
## screen, so only each card's bottom-right corner is in view: the first card sits in the
## upper-right corner and every card after it is placed a little to the left and below, so
## each card's corner stays visible (a staircase stepping down-left). A freshly dealt card
## does not rest: it comes up to the middle of the screen at a size where it is fully
## visible, builds suspense and flips there. settle() then folds it into the stack.

const CARD_SCENE := preload("res://scenes/card.tscn")
const BACK_PATH := "res://assets/images/cards/card_backs/traditional_ai.png"
const MAX_POOL_VISIBLE := 14

# The reveal: a dealt card is fully visible, in the middle of the screen.
const REVEAL_Y := 0.383       # fraction of the table height
const REVEAL_ZOOM := 1.5
const PAIR_SCALE := 0.9       # Purple's two cards sit side by side, a little smaller than a lone card
const PAIR_SPREAD := 118.0    # horizontal offset of each Purple card from the centre

# The stack at rest: zoomed, cropped by the top of the screen, corners only.
const REST_ZOOM := 2.55
const REST_CORNER_X := 1.02   # where the first card's bottom-right corner sits (x as a fraction of width)
const REST_CORNER_Y := 262.0  # ... and y in pixels
const REST_STEP := Vector2(-65, 32)   # each later card's corner sits this much further down-left
const REST_SPAN := Vector2(470, 500)  # the most the staircase may cover; it tightens past this
const REST_TINT := Color(0.8, 0.74, 0.92)
const DIM_REVEAL := 0.5       # the resting stack dims while a card is being revealed

# The deck: one card back at the same size as the stack's cards, lying landscape and hanging off the bottom of the screen.
const DECK_VISIBLE := 430.0   # how much of the deck shows above the bottom edge of the screen
const SHOW_TAGS := false      # upright rank+suit labels on stack cards; the card art already reads fine
const DECK_TINT := Color(0.62, 0.58, 0.78)
const DECK_SHIFT_X := -40.0   # the deck slides left so the cards piled under it peek out on the right
const DECK_UNDER := 5         # cards in the pile under the deck
const DECK_UNDER_STEP := 8.0  # each one sits this much further right (tightly stacked)

const TRAVEL := 0.4         # deck -> reveal deal time; the escorted guess button matches it
const TRAVEL_QUICK := 0.18

const RANKS := {11: "J", 12: "Q", 13: "K", 14: "A"}

var _pile: Card
var _under: Array[Card] = []   # the pile of cards beneath the deck, nearest first
var _active: Card
var _pool: Array[Card] = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_deck()

# --- the deck ----------------------------------------------------------------

## The deck is a single card back, drawn exactly like the stack's cards, so the two match.
func _build_deck() -> void:
	# The pile underneath goes in first (furthest card at the very back), a little
	# darker and slightly crooked the further down it is, so it reads as a heap of cards.
	_under.resize(DECK_UNDER)
	for k in range(DECK_UNDER, 0, -1):
		var under := _back_card(DECK_TINT * (1.0 - 0.09 * k))
		under.rotation += (0.012 if k % 2 == 0 else -0.01) * k * 0.6
		add_child(under)
		under.glow(NeonTheme.PURPLE, 0.0)
		_under[k - 1] = under
	_pile = _back_card(DECK_TINT)
	add_child(_pile)
	_pile.glow(NeonTheme.PURPLE, 0.0)

## A card back lying landscape (turned a quarter turn about its centre), at the stack's size.
func _back_card(tint: Color) -> Card:
	var c: Card = CARD_SCENE.instantiate()
	c.setup_card("deck", 0, "hearts", "", BACK_PATH)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.scale = Vector2.ONE * REST_ZOOM
	c.rotation = PI * 0.5
	tint.a = 1.0
	c.modulate = tint
	return c

## Where the top edge of the deck is (the table's top is the top of the screen).
func _deck_top() -> float:
	return get_viewport_rect().size.y - DECK_VISIBLE

## Where the deck card is centred (turned landscape, so its height on screen is the card's width).
func _deck_face_pos() -> Vector2:
	return Vector2(_deck_x(), _deck_top() + Card.CARD_SIZE.x * REST_ZOOM * 0.5)

## The deck's horizontal centre: a little left of the screen's, to leave room for the pile.
func _deck_x() -> float:
	return size.x * 0.5 + DECK_SHIFT_X

## Dealt cards leave from just inside the deck's top edge.
func _deck_pos() -> Vector2:
	return Vector2(_deck_x(), _deck_top() + 40.0)

## The middle of the screen, where a dealt card is revealed.
func _reveal_pos() -> Vector2:
	return Vector2(size.x * 0.5, size.y * REVEAL_Y)

## How long a dealt card takes to travel from the deck to the reveal spot.
static func travel_time(quick: bool) -> float:
	return TRAVEL_QUICK if quick else TRAVEL

func deck_global_pos() -> Vector2:
	return global_position + _deck_pos()

## The middle of the area the guess buttons are laid out in (the visible part of the deck).
func chips_global_center() -> Vector2:
	return global_position + Vector2(_deck_x(), _deck_top() + DECK_VISIBLE * 0.5)

## Where a guess button rides while its card is dealt: straddling the revealed card's bottom edge.
func escort_global_pos(pair: bool) -> Vector2:
	var half_h := Card.CARD_SIZE.y * 0.5 * (PAIR_SCALE if pair else REVEAL_ZOOM)
	return global_center() + Vector2(0.0, half_h - 4.0)

func _set_center(c: Control, p: Vector2) -> void:
	c.position = p - Card.CARD_SIZE * 0.5

func _process(_delta: float) -> void:
	var origin := _deck_face_pos() - Card.CARD_SIZE * 0.5
	_pile.position = origin
	for k in _under.size():
		_under[k].position = origin + Vector2(DECK_UNDER_STEP * (k + 1), 0.0)

func active_card() -> Card:
	return _active

## The middle of the reveal spot (confetti and slam text are centred here).
func global_center() -> Vector2:
	return global_position + _reveal_pos()

func make_card(data: CardData) -> Card:
	var node: Card = CARD_SCENE.instantiate()
	node.setup_card(data.nice_name, data.rank, Globals.SUITS.keys()[data.suit].to_lower(), data.texture_path, data.backface_path)
	node.is_facedown = true
	return node

# --- reveal ------------------------------------------------------------------

## Deal `data` from the deck up to the middle of the screen, build suspense for `suspense`
## seconds, then flip. Awaitable; returns the revealed Card. `quick` skips the drama
## (opening card, fast-forward). The card stays in the middle until settle().
func reveal(data: CardData, suspense: float, quick: bool = false) -> Card:
	_retire_active()
	_dim_stack(DIM_REVEAL, 0.3)
	var card := make_card(data)
	add_child(card)
	_active = card
	_set_center(card, _deck_pos())
	card.scale = Vector2(0.62, 0.62)
	card.rotation = -0.5

	var travel := travel_time(quick)
	Sfx.play("slide", randf_range(0.95, 1.1))
	var tw := create_tween().set_parallel(true)
	tw.tween_property(card, "position", _reveal_pos() - Card.CARD_SIZE * 0.5, travel).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(card, "scale", Vector2.ONE * REVEAL_ZOOM, travel).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(card, "rotation", 0.0, travel).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await tw.finished

	if suspense > 0.0 and not quick:
		await _anticipate(card, suspense)

	Sfx.play("flip")
	await card.flip_animated(0.14 if quick else 0.34, REVEAL_ZOOM)
	return card

## Purple: both cards leave the deck together, shake together, then flip one after
## the other (a 1-2 beat). Awaitable; returns [first, second]. The second stays the
## active card and the first joins the pool beside it.
func reveal_pair(first: CardData, second: CardData, suspense: float, quick: bool = false) -> Array[Card]:
	_retire_active()
	_dim_stack(DIM_REVEAL, 0.3)
	var left_pos := _reveal_pos() + Vector2(-PAIR_SPREAD, 0.0)
	var right_pos := _reveal_pos() + Vector2(PAIR_SPREAD, 0.0)
	var cards: Array[Card] = [make_card(first), make_card(second)]
	var spots: Array[Vector2] = [left_pos, right_pos]
	var travel := travel_time(quick)
	Sfx.play("slide", randf_range(0.95, 1.1))
	var tw := create_tween().set_parallel(true)
	for i in 2:
		add_child(cards[i])
		_set_center(cards[i], _deck_pos())
		cards[i].scale = Vector2(0.62, 0.62)
		cards[i].rotation = -0.5
		tw.tween_property(cards[i], "position", spots[i] - Card.CARD_SIZE * 0.5, travel).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(cards[i], "scale", Vector2(PAIR_SCALE, PAIR_SCALE), travel).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(cards[i], "rotation", 0.0, travel).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await tw.finished

	if suspense > 0.0 and not quick:
		if suspense > 0.9:
			Sfx.play("drumroll")
		else:
			Sfx.play("heartbeat")
		var shake := create_tween().set_parallel(true)
		for c in cards:
			shake.tween_property(c, "scale", Vector2(PAIR_SCALE * 1.14, PAIR_SCALE * 1.14), suspense).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		shake.tween_method(_tremble_pair.bind(cards, spots), 0.0, 1.0, suspense)
		await shake.finished
		for i in 2:
			cards[i].rotation = 0.0
			cards[i].position = spots[i] - Card.CARD_SIZE * 0.5

	_pool.append(cards[0])
	_active = cards[1]
	Sfx.play("flip")
	await cards[0].flip_animated(0.14 if quick else 0.3, PAIR_SCALE)
	await get_tree().create_timer(0.05 if quick else 0.3).timeout   # the beat between 1 and 2
	Sfx.play("flip", 1.15)
	await cards[1].flip_animated(0.14 if quick else 0.3, PAIR_SCALE)
	return cards

## Both cards tremble with the same jitter, so they read as one shaking pair.
func _tremble_pair(t: float, cards: Array[Card], spots: Array[Vector2]) -> void:
	var amp := t * 5.0
	var jitter := Vector2(randf_range(-amp, amp), randf_range(-amp, amp))
	var rot := sin(t * 60.0) * 0.012 * (1.0 + t * 3.0)
	for i in cards.size():
		cards[i].rotation = rot
		cards[i].position = spots[i] - Card.CARD_SIZE * 0.5 + jitter

## The held breath before a flip: the card creeps up, trembles, and ticks faster.
func _anticipate(card: Card, duration: float) -> void:
	if duration > 0.9:
		Sfx.play("drumroll")
	else:
		Sfx.play("heartbeat")
	var tw := create_tween().set_parallel(true)
	tw.tween_property(card, "scale", Vector2.ONE * REVEAL_ZOOM * 1.1, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_method(_tremble.bind(card), 0.0, 1.0, duration)
	await tw.finished
	card.rotation = 0.0
	card.position = _reveal_pos() - Card.CARD_SIZE * 0.5

func _tremble(t: float, card: Card) -> void:
	var amp := t * 5.0
	card.rotation = sin(t * 60.0) * 0.012 * (1.0 + t * 3.0)
	card.position = _reveal_pos() - Card.CARD_SIZE * 0.5 + Vector2(randf_range(-amp, amp), randf_range(-amp, amp))

## Post doubling: ghostly copies of the stack fan out in the middle of the screen.
## They count toward the pool but are not real cards, so they are tinted differently.
func add_phantoms(datas: Array) -> void:
	var tw := create_tween().set_parallel(true)
	for data: CardData in datas:
		var ghost := make_card(data)
		ghost.is_facedown = false
		add_child(ghost)
		move_child(ghost, 0)
		ghost.set_meta("phantom", true)
		_pool.insert(0, ghost)
		_set_center(ghost, _reveal_pos())
		ghost.scale = Vector2.ONE * REVEAL_ZOOM * 0.6
		ghost.modulate = Color(0.55, 0.95, 1.0, 0.0)
		ghost.glow(NeonTheme.CYAN, 0.2)
		var jitter := Vector2(randf_range(-140, 140), randf_range(-90, 90))
		tw.tween_property(ghost, "position", _reveal_pos() - Card.CARD_SIZE * 0.5 + jitter, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(ghost, "rotation", randf_range(-0.5, 0.5), 0.45)
		tw.tween_property(ghost, "modulate:a", 0.65, 0.45)
	Sfx.play("shuffle", 1.3)
	while _pool.size() > MAX_POOL_VISIBLE:
		var gone: Card = _pool.pop_front()
		gone.queue_free()
	await tw.finished

# --- the stack at rest -------------------------------------------------------

## The previous active card joins the pool where it is; it is not moved until settle().
func _retire_active() -> void:
	if _active == null:
		return
	var old := _active
	_pool.append(old)
	_active = null
	old.glow(Color(NeonTheme.PURPLE), 0.2)
	while _pool.size() > MAX_POOL_VISIBLE:
		var gone: Card = _pool.pop_front()
		gone.queue_free()

## Fold the revealed card (or pair) into the stack: it flies to the zoomed corner at the
## top, the older cards step down-right, and the stack brightens again. Awaitable.
func settle(duration: float = 0.45) -> void:
	_layout_rest(duration)
	await get_tree().create_timer(duration).timeout

## Newest first: the active card, then the pool from newest to oldest (phantoms excluded).
func _stack_order() -> Array[Card]:
	var order: Array[Card] = []
	if _active != null:
		order.append(_active)
	for i in range(_pool.size() - 1, -1, -1):
		if not _pool[i].has_meta("phantom"):
			order.append(_pool[i])
	return order

## Corner of the card that is `age` places after the first (0 = the first card, upper right),
## in a stack of `count`. The staircase tightens when the stack grows past REST_SPAN.
func _rest_corner(age: int, count: int) -> Vector2:
	var gaps := maxi(count - 1, 1)
	var step := Vector2(-minf(-REST_STEP.x, REST_SPAN.x / gaps), minf(REST_STEP.y, REST_SPAN.y / gaps))
	return Vector2(size.x * REST_CORNER_X, REST_CORNER_Y) + step * age

## Card `position` (its top-left, before the scale about its centre) for a corner at `corner`.
func _rest_position(corner: Vector2) -> Vector2:
	return corner - Card.CARD_SIZE * REST_ZOOM * 0.5 - Card.CARD_SIZE * 0.5

func _layout_rest(duration: float) -> void:
	var order := _stack_order()
	var count := order.size()
	for d in count:
		var c := order[d]
		var tint := Color.WHITE if d == 0 else REST_TINT
		c.set_meta("tint", tint)
		var tw := create_tween().set_parallel(true)
		tw.tween_property(c, "position", _rest_position(_rest_corner(count - 1 - d, count)), duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(c, "rotation", 0.0, duration)
		tw.tween_property(c, "scale", Vector2.ONE * REST_ZOOM, duration)
		tw.tween_property(c, "modulate", tint, duration)
		_add_tag(c)
		if d > 0:
			c.glow(Color(NeonTheme.PURPLE), duration)
	# Paint order: the deck and its pile at the back, then the first card up to the newest on top.
	var slot := _under.size() + 1
	for c in _pool:
		move_child(c, slot)
		slot += 1
	if _active != null:
		move_child(_active, slot)

## Dim (or restore, with 1.0) the resting stack while a card is being revealed over it.
func _dim_stack(k: float, duration: float) -> void:
	for c in _pool:
		if c.has_meta("phantom"):
			continue
		var tint: Color = c.get_meta("tint", REST_TINT)
		create_tween().tween_property(c, "modulate", Color(tint.r * k, tint.g * k, tint.b * k, tint.a), duration)

## An upright rank + suit label in the bottom-right of a card in the stack. The card's own
## corner index is upside down there (a 6 reads as a 9), so this one is what the player
## reads. It sits in the strip of the card that the next card leaves uncovered.
func _add_tag(c: Card) -> void:
	if not SHOW_TAGS or c.has_node("Tag"):
		return
	var tag := Label.new()
	tag.name = "Tag"
	var symbol := "♥"
	match c.suit:
		Globals.SUITS.DIAMONDS: symbol = "♦"
		Globals.SUITS.SPADES: symbol = "♠"
		Globals.SUITS.CLUBS: symbol = "♣"
	tag.text = "%s%s" % [RANKS.get(c.rank, str(c.rank)), symbol]
	tag.size = Vector2(52.0, 30.0)
	tag.position = Vector2(Card.CARD_SIZE.x - tag.size.x - 6.0, Card.CARD_SIZE.y - tag.size.y - 6.0)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var red := c.suit == Globals.SUITS.HEARTS or c.suit == Globals.SUITS.DIAMONDS
	tag.add_theme_font_override("font", NeonTheme.FONT_HEAD)
	tag.add_theme_font_size_override("font_size", 22)
	tag.add_theme_color_override("font_outline_color", NeonTheme.INK)
	tag.add_theme_constant_override("outline_size", 5)
	tag.add_theme_color_override("font_color", NeonTheme.RED.lightened(0.2) if red else Color.WHITE)
	c.add_child(tag)

# --- clearing ----------------------------------------------------------------

## Clear the table. `chaotic` (a loss) flings the cards outward spinning; otherwise they
## are swept back into the deck. Awaitable.
func sweep(chaotic: bool) -> void:
	var cards: Array[Card] = _pool.duplicate()
	if _active:
		cards.append(_active)
	_pool.clear()
	_active = null
	if cards.is_empty():
		return
	var tw := create_tween().set_parallel(true)
	var duration := 0.55
	for c in cards:
		if chaotic:
			var dir := Vector2.from_angle(randf() * TAU) * randf_range(500, 900)
			tw.tween_property(c, "position", c.position + dir, duration).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
			tw.tween_property(c, "rotation", c.rotation + randf_range(-6.0, 6.0), duration)
			tw.tween_property(c, "modulate:a", 0.0, duration).set_delay(0.15)
		else:
			tw.tween_property(c, "position", _deck_pos() - Card.CARD_SIZE * 0.5, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
			tw.tween_property(c, "scale", Vector2(0.4, 0.4), duration)
			tw.tween_property(c, "modulate:a", 0.0, duration).set_delay(0.3)
	Sfx.play("shuffle" if not chaotic else "slide", 0.7 if chaotic else 1.0)
	await tw.finished
	for c in cards:
		c.queue_free()

## Instant clear (fast-forward / teardown).
func clear_now() -> void:
	for c in _pool:
		c.queue_free()
	_pool.clear()
	if _active:
		_active.queue_free()
		_active = null
