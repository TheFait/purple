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
## The Top card and the Drop card under it get room to read at a glance; older cards are
## tucked in tight and dimmed. Tapping the stack opens a scrolling grid of every card in it
## (newest first); tapping again folds them back (see open_browse / close_browse).

const CARD_SCENE := preload("res://scenes/card.tscn")
const BACK_PATH := "res://assets/images/cards/card_backs/traditional_ai.png"

# The reveal: a dealt card is fully visible, in the middle of the screen.
const REVEAL_Y := 0.383       # fraction of the table height
const REVEAL_ZOOM := 1.5
const PAIR_SCALE := 0.9       # Purple's two cards sit side by side, a little smaller than a lone card
const PAIR_SPREAD := 118.0    # horizontal offset of each Purple card from the centre

# The stack at rest: zoomed, cropped by the top of the screen, corners only.
const REST_ZOOM := 2.55
const REST_CORNER_X := 1.02   # where the first card's bottom-right corner sits (x as a fraction of width)
const REST_CORNER_Y := 262.0  # ... and y in pixels
const REST_DROP_STEP := Vector2(-128, 60)  # the Top card sits this far down-left of the Drop card, so the Drop's corner reads in full
const REST_OLD_STEP := Vector2(-24, 13)    # older cards are tucked in tight, a sliver of each showing
const REST_OLD_SPAN := Vector2(170, 92)    # the most the older cards may cover; they tighten past this
const REST_SHOWN := 10                     # cards deeper than this hide behind the deepest one shown
const REST_TINT := Color(0.92, 0.88, 1.0)  # the Drop card
const REST_OLD_TINT := Color(0.58, 0.53, 0.72)  # older cards, darker the deeper they sit
const REST_OLD_FADE := 0.06                # each older card is this much darker again (to a floor)
const BURN_SHADER := preload("res://assets/shaders/burn_away.gdshader")
const SPOTLIGHT_SHADER := preload("res://assets/shaders/spotlight.gdshader")
const FAKEOUT_Z := 30         # the fakeout's darkness draws over the HUD; the card over that
const FAKEOUT_GROW := 1.25    # in the fakeout the card swells this much (x REVEAL_ZOOM) ...
const FAKEOUT_SHAKE := 1.8    # ... and shakes this many times harder than a normal flip
const PHANTOM_TINT := Color(0.55, 0.95, 1.0, 0.72)   # Post's ghost copies: cyan and see-through
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

# The browse grid: every card in the stack, newest first, in a scrolling grid.
const BROWSE_TOP := 150.0      # room above the grid for the heading
const BROWSE_BOTTOM := 110.0   # room below it for the hint
const BROWSE_GAP := 22.0
const BROWSE_COLS_FEW := 3     # up to BROWSE_FEW cards go 3 across at full size ...
const BROWSE_FEW := 9
const BROWSE_COLS_MANY := 4    # ... more go 4 across, smaller
const BROWSE_OPEN := 0.42
const BROWSE_CLOSE := 0.34
const BROWSE_STAGGER := 0.025  # each card leaves a moment after the one before
const BROWSE_Z := 20           # the table draws above the HUD while browsing
const TAP_SLOP := 14.0         # a press that moves further than this is a scroll, not a tap

## Emitted when the grid opens (true) or starts folding back (false).
signal browse_changed(open: bool)

var _pile: Card
var _under: Array[Card] = []   # the pile of cards beneath the deck, nearest first
var _active: Card
var _pool: Array[Card] = []

## Set by the UI while it is playing events: the stack can't be opened mid-animation.
var browse_locked := false
var _browsing := false
var _scroll := 0.0
var _press_at := Vector2.ZERO
var _press_scroll := 0.0
var _pressing := false
var _dragged := false
var _shade: ColorRect      # darkens the felt behind the grid
var _chrome: Control       # the heading and the hint, drawn above the cards
var _heading: Label
var _subhead: Label

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_deck()
	_build_browse()

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
		under.set_outline(1, 0)
		under.glow(NeonTheme.PURPLE.darkened(0.25), 0.0)
		_under[k - 1] = under
	_pile = _back_card(DECK_TINT)
	add_child(_pile)
	_pile.set_outline(1, 0)
	_pile.glow(NeonTheme.PURPLE.darkened(0.25), 0.0)

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
	if data.phantom:
		node.set_meta("phantom", true)
	return node

## A card leaving the deck keeps the back that was showing on top, and the deck's top card
## then shows a new random back from the collection (the next card is now on top).
func _deal_back(card: Card) -> void:
	if _pile.back_choice >= 0:
		card.set_back_choice(_pile.back_choice)
	_pile.reroll_back()

# --- reveal ------------------------------------------------------------------

## Deal `data` from the deck up to the middle of the screen, build suspense for `suspense`
## seconds, then flip. Awaitable; returns the revealed Card. `quick` skips the drama
## (opening card, fast-forward). The card stays in the middle until settle().
func reveal(data: CardData, suspense: float, quick: bool = false, fakeout: bool = false) -> Card:
	_end_browse()
	_retire_active()
	_dim_stack(DIM_REVEAL, 0.3)
	var card := make_card(data)
	_deal_back(card)
	add_child(card)
	_active = card
	_set_center(card, _deck_pos())
	card.scale = Vector2(0.62, 0.62)
	card.rotation = -0.5
	var shade: ColorRect = _lights_out([card]) if fakeout and not quick else null

	var travel := travel_time(quick)
	Sfx.play("slide", randf_range(0.95, 1.1))
	var tw := create_tween().set_parallel(true)
	tw.tween_property(card, "position", _reveal_pos() - Card.CARD_SIZE * 0.5, travel).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(card, "scale", Vector2.ONE * REVEAL_ZOOM, travel).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(card, "rotation", 0.0, travel).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if shade != null:
		tw.tween_method(_follow_spot.bind(shade, [card]), 0.0, 1.0, travel)
	await tw.finished

	if shade != null:
		# Fakeout: a longer, slower creep and a much harder shake, alone in the spotlight.
		await _anticipate(card, fakeout_time(suspense), FAKEOUT_GROW, FAKEOUT_SHAKE, shade)
		await _lights_on(shade, [card])
	elif suspense > 0.0 and not quick:
		await _anticipate(card, suspense)

	Sfx.play("flip")
	await card.flip_animated(0.14 if quick else 0.34, REVEAL_ZOOM)
	return card

## How long a fakeout's creep-and-shake lasts, from the flip's normal suspense.
static func fakeout_time(suspense: float) -> float:
	return maxf(suspense, 0.5) * 1.6 + 1.2

## Fakeout, part 1: the moment the card (or Purple's pair) leaves the deck the lights go
## out, but for a spotlight that follows it (see _follow_spot). The cards draw above the dark.
func _lights_out(cards: Array) -> ColorRect:
	var shade := ColorRect.new()
	shade.top_level = true
	shade.position = Vector2.ZERO
	shade.size = get_viewport_rect().size
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.z_index = FAKEOUT_Z
	var mat := ShaderMaterial.new()
	mat.shader = SPOTLIGHT_SHADER
	shade.material = mat
	shade.modulate.a = 0.0
	add_child(shade)
	for c in cards:
		c.z_index = FAKEOUT_Z + 1
	_follow_spot(0.0, shade, cards)
	Sfx.stop_all()
	Sfx.play("tick", 0.45)
	Sfx.vibrate(30)
	create_tween().tween_property(shade, "modulate:a", 1.0, 0.18)
	return shade

## Keep the spotlight centred on the cards and sized to take them all in (it grows with them).
func _follow_spot(_t: float, shade: ColorRect, cards: Array) -> void:
	var centers: Array[Vector2] = []
	var mid := Vector2.ZERO
	for c in cards:
		var p: Vector2 = c.get_global_transform() * (c.size * 0.5)
		centers.append(p)
		mid += p
	mid /= maxf(cards.size(), 1)
	var reach := Vector2.ZERO
	for p in centers:
		reach = Vector2(maxf(reach.x, absf(p.x - mid.x)), maxf(reach.y, absf(p.y - mid.y)))
	var card_scale: Vector2 = cards[0].scale
	var mat := shade.material as ShaderMaterial
	mat.set_shader_parameter("center", mid)
	mat.set_shader_parameter("radii", reach + Card.CARD_SIZE * card_scale * Vector2(0.85, 0.75))

## Fakeout, part 2: the lights slam back on, right as the card flips.
func _lights_on(shade: ColorRect, cards: Array) -> void:
	Sfx.vibrate(80)
	var tw := create_tween()
	tw.tween_property(shade, "modulate:a", 0.0, 0.08)
	await tw.finished
	for c in cards:
		c.z_index = 0
	shade.queue_free()

## Purple: both cards leave the deck together, shake together, then flip one after
## the other (a 1-2 beat). Awaitable; returns [first, second]. The second stays the
## active card and the first joins the pool beside it. A fakeout spotlights the pair.
func reveal_pair(first: CardData, second: CardData, suspense: float, quick: bool = false, fakeout: bool = false) -> Array[Card]:
	_end_browse()
	_retire_active()
	_dim_stack(DIM_REVEAL, 0.3)
	var left_pos := _reveal_pos() + Vector2(-PAIR_SPREAD, 0.0)
	var right_pos := _reveal_pos() + Vector2(PAIR_SPREAD, 0.0)
	var cards: Array[Card] = [make_card(first), make_card(second)]
	for c in cards:
		_deal_back(c)
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
	var shade: ColorRect = _lights_out(cards) if fakeout and not quick else null
	if shade != null:
		tw.tween_method(_follow_spot.bind(shade, cards), 0.0, 1.0, travel)
	await tw.finished

	if (suspense > 0.0 or shade != null) and not quick:
		var wait := fakeout_time(suspense) if shade != null else suspense
		var grow := FAKEOUT_GROW if shade != null else 1.14
		var force := FAKEOUT_SHAKE if shade != null else 1.0
		if wait > 0.9:
			Sfx.play("drumroll")
		else:
			Sfx.play("heartbeat")
		var shake := create_tween().set_parallel(true)
		for c in cards:
			shake.tween_property(c, "scale", Vector2.ONE * PAIR_SCALE * grow, wait).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		shake.tween_method(_tremble_pair.bind(cards, spots, force, 60.0 * maxf(wait, 1.0)), 0.0, 1.0, wait)
		if shade != null:
			shake.tween_method(_follow_spot.bind(shade, cards), 0.0, 1.0, wait)
		await shake.finished
		for i in 2:
			cards[i].rotation = 0.0
			cards[i].position = spots[i] - Card.CARD_SIZE * 0.5
	if shade != null:
		await _lights_on(shade, cards)

	_pool.append(cards[0])
	_active = cards[1]
	Sfx.play("flip")
	await cards[0].flip_animated(0.14 if quick else 0.3, PAIR_SCALE)
	await get_tree().create_timer(0.05 if quick else 0.3).timeout   # the beat between 1 and 2
	Sfx.play("flip", 1.15)
	await cards[1].flip_animated(0.14 if quick else 0.3, PAIR_SCALE)
	return cards

## Both cards tremble with the same jitter, so they read as one shaking pair.
func _tremble_pair(t: float, cards: Array[Card], spots: Array[Vector2], shake: float = 1.0, cycles: float = 60.0) -> void:
	var amp := t * 5.0 * shake
	var jitter := Vector2(randf_range(-amp, amp), randf_range(-amp, amp))
	var rot := sin(t * cycles) * 0.012 * (1.0 + t * 3.0) * shake
	for i in cards.size():
		cards[i].rotation = rot
		cards[i].position = spots[i] - Card.CARD_SIZE * 0.5 + jitter

## The held breath before a flip: the card creeps up, trembles, and ticks faster.
## `grow` is how far the card swells (x REVEAL_ZOOM) and `shake` scales the tremble; the
## fakeout passes bigger values and its spotlight, which follows the card.
func _anticipate(card: Card, duration: float, grow: float = 1.1, shake: float = 1.0, spot: ColorRect = null) -> void:
	if duration > 0.9:
		Sfx.play("drumroll")
	else:
		Sfx.play("heartbeat")
	var tw := create_tween().set_parallel(true)
	tw.tween_property(card, "scale", Vector2.ONE * REVEAL_ZOOM * grow, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# The wobble keeps the same speed however long the wait is.
	tw.tween_method(_tremble.bind(card, shake, 60.0 * maxf(duration, 1.0)), 0.0, 1.0, duration)
	if spot != null:
		tw.tween_method(_follow_spot.bind(spot, [card]), 0.0, 1.0, duration)
	await tw.finished
	card.rotation = 0.0
	card.position = _reveal_pos() - Card.CARD_SIZE * 0.5

func _tremble(t: float, card: Card, shake: float = 1.0, cycles: float = 60.0) -> void:
	var amp := t * 5.0 * shake
	card.rotation = sin(t * cycles) * 0.012 * (1.0 + t * 3.0) * shake
	card.position = _reveal_pos() - Card.CARD_SIZE * 0.5 + Vector2(randf_range(-amp, amp), randf_range(-amp, amp))

## Post doubling: ghostly copies of the stack burst out of the middle of the screen at
## every angle, spinning, then sweep into the stack beneath the real cards and stay there
## (see PHANTOM_TINT) until the stack is cleared, so the doubling is something you can see
## (and count in the grid). Awaitable.
func add_phantoms(datas: Array) -> void:
	_end_browse()
	var origin := _reveal_pos()
	var ghosts: Array[Card] = []
	var tw := create_tween().set_parallel(true)
	var count := datas.size()
	var spin_offset := randf() * TAU
	for i in count:
		var ghost := make_card(datas[i] as CardData)
		ghost.is_facedown = false
		add_child(ghost)
		ghosts.append(ghost)
		_set_center(ghost, origin)
		ghost.scale = Vector2.ONE * REVEAL_ZOOM * 0.45
		ghost.modulate = Color(PHANTOM_TINT, 0.0)
		ghost.glow(NeonTheme.CYAN, 0.1)
		# Evenly spread directions with a little jitter, so they fan out in every direction.
		var angle := spin_offset + TAU * i / maxi(count, 1) + randf_range(-0.25, 0.25)
		var target := origin + Vector2.from_angle(angle) * randf_range(220.0, 420.0)
		tw.tween_property(ghost, "position", target - Card.CARD_SIZE * 0.5, 0.5).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		tw.tween_property(ghost, "rotation", randf_range(-3.5, 3.5), 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(ghost, "scale", Vector2.ONE * REVEAL_ZOOM * 0.8, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(ghost, "modulate:a", 0.95, 0.12)
	Sfx.play("shuffle", 1.3)
	await tw.finished
	# The copies go under the real cards (the engine prepends them too), oldest first.
	_pool = ghosts + _pool
	_layout_rest(0.55)
	await get_tree().create_timer(0.55).timeout

# --- restoring a snapshot ---------------------------------------------------

## Put `datas` (oldest first, phantoms included) on the table instantly, as it would look
## at rest. Used when a client joins a table that is already in play.
func restore(datas: Array) -> void:
	clear_now()
	for i in datas.size():
		var card := make_card(datas[i])
		card.is_facedown = false
		add_child(card)
		if card.has_meta("phantom"):
			card.glow(NeonTheme.CYAN, 0.0)
		if i == datas.size() - 1:
			_active = card
		else:
			_pool.append(card)
	_layout_rest(0.0)

# --- the stack at rest -------------------------------------------------------

## The previous active card joins the pool where it is; it is not moved until settle().
func _retire_active() -> void:
	if _active == null:
		return
	var old := _active
	_pool.append(old)
	_active = null
	old.glow(Color(NeonTheme.PURPLE), 0.2)

## Posted: the cards burn away from the bottom up, embers rising off the burning edge, and
## are gone for good (taken out of the stack, so the sweep that follows skips them). The
## cards are moved into a CanvasGroup so the burn shader sees each card (faces, frame and
## glow) as one picture. Awaitable.
func burn_away(cards: Array[Card], duration: float = 1.2) -> void:
	cards = cards.filter(func(c: Card) -> bool: return c != null and is_instance_valid(c))
	if cards.is_empty():
		return
	var group := CanvasGroup.new()
	group.fit_margin = 60.0
	group.clear_margin = 60.0
	add_child(group)
	var top := INF
	var bottom := -INF
	var left := INF
	var right := -INF
	for c in cards:
		if c.has_meta("layout_tween"):
			var tw_old: Tween = c.get_meta("layout_tween")
			if tw_old.is_valid():
				tw_old.kill()
		if c == _active:
			_active = null
		_pool.erase(c)
		var xf := c.get_global_transform()
		for corner in [Vector2.ZERO, Vector2(c.size.x, 0.0), Vector2(0.0, c.size.y), c.size]:
			var p: Vector2 = group.get_global_transform().affine_inverse() * (xf * corner)
			top = minf(top, p.y)
			bottom = maxf(bottom, p.y)
			left = minf(left, p.x)
			right = maxf(right, p.x)
		c.reparent(group)
	# The glow reaches past each card's edge; let the burn cover it too.
	top -= 30.0
	bottom += 30.0
	var mat := ShaderMaterial.new()
	mat.shader = BURN_SHADER
	mat.set_shader_parameter("top_y", top)
	mat.set_shader_parameter("bottom_y", bottom)
	mat.set_shader_parameter("progress", 0.0)
	group.material = mat

	var embers := CPUParticles2D.new()
	embers.amount = 90
	embers.lifetime = 0.8
	embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	embers.emission_rect_extents = Vector2((right - left) * 0.5, 10.0)
	embers.direction = Vector2(0, -1)
	embers.spread = 25.0
	embers.gravity = Vector2(0, -220)
	embers.initial_velocity_min = 40.0
	embers.initial_velocity_max = 200.0
	embers.scale_amount_min = 3.0
	embers.scale_amount_max = 8.0
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([ScreenFx.FIRE_COLORS[0], ScreenFx.FIRE_COLORS[1], ScreenFx.FIRE_COLORS[2], Color(ScreenFx.FIRE_COLORS[3], 0.0)])
	embers.color_ramp = ramp
	embers.position = Vector2((left + right) * 0.5, bottom)
	add_child(embers)

	Sfx.play("shuffle", 0.55)
	var tw := create_tween().set_parallel(true)
	tw.tween_method(func(v: float) -> void: mat.set_shader_parameter("progress", v), 0.0, 1.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# The embers ride the burning edge up the cards.
	tw.tween_property(embers, "position:y", top + 20.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	embers.emitting = false
	group.queue_free()
	get_tree().create_timer(embers.lifetime + 0.1).timeout.connect(embers.queue_free)

## Negative Post: the Top card the flip just matched leaves the stack and lines up beside
## the flip, both at full brightness, so the two equal ranks read side by side. Awaitable;
## returns the Top card (null when there is none). The stack is swept away after this.
func spotlight_match(duration: float = 0.4) -> Card:
	if _active == null or _pool.is_empty():
		return null
	var top: Card = _pool.back()
	top.show()
	move_child(top, get_child_count() - 1)
	move_child(_active, get_child_count() - 1)
	var size := PAIR_SCALE * 1.08
	var tw := _card_tween(top)
	tw.tween_property(top, "position", _reveal_pos() + Vector2(-PAIR_SPREAD, 0.0) - Card.CARD_SIZE * 0.5, duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(top, "scale", Vector2.ONE * size, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(top, "rotation", -0.06, duration)
	tw.tween_property(top, "modulate", Color.WHITE, duration * 0.6)
	var flip := _card_tween(_active)
	flip.tween_property(_active, "position", _reveal_pos() + Vector2(PAIR_SPREAD, 0.0) - Card.CARD_SIZE * 0.5, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	flip.tween_property(_active, "scale", Vector2.ONE * size, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	flip.tween_property(_active, "rotation", 0.06, duration)
	await tw.finished
	return top

## Fold the revealed card (or pair) into the stack: it flies to the zoomed corner at the
## top, the older cards step down-right, and the stack brightens again. Awaitable.
func settle(duration: float = 0.45) -> void:
	_layout_rest(duration)
	await get_tree().create_timer(duration).timeout

## Newest first: the active card, then the pool from newest to oldest (Post's phantom
## copies sit at the bottom, as in the engine).
func _stack_order() -> Array[Card]:
	var order: Array[Card] = []
	if _active != null:
		order.append(_active)
	for i in range(_pool.size() - 1, -1, -1):
		order.append(_pool[i])
	return order

## Corner of the card `depth` places under the Top card (0 = Top, 1 = Drop), in a stack of
## `count`. The deepest card shown sits in the upper-right; each newer card steps down-left,
## a sliver at a time, and the Top card takes one big step off the Drop card so both of
## their corners read at a glance. Cards deeper than REST_SHOWN hide behind the deepest one.
func _rest_corner(depth: int, count: int) -> Vector2:
	var shown := mini(count, REST_SHOWN)
	var old_gaps := maxi(shown - 2, 1)
	var old_step := Vector2(-minf(-REST_OLD_STEP.x, REST_OLD_SPAN.x / old_gaps), minf(REST_OLD_STEP.y, REST_OLD_SPAN.y / old_gaps))
	var corner := Vector2(size.x * REST_CORNER_X, REST_CORNER_Y)
	for d in range(shown - 2, mini(depth, shown - 1) - 1, -1):
		corner += REST_DROP_STEP if d == 0 else old_step
	return corner

## Card `position` (its top-left, before the scale about its centre) for a corner at `corner`.
func _rest_position(corner: Vector2) -> Vector2:
	return corner - Card.CARD_SIZE * REST_ZOOM * 0.5 - Card.CARD_SIZE * 0.5

func _rest_tint(c: Card, depth: int) -> Color:
	if c.has_meta("phantom"):
		var k := 1.0 if depth < 2 else maxf(1.0 - REST_OLD_FADE * (depth - 2), 0.6)
		return Color(PHANTOM_TINT.r * k, PHANTOM_TINT.g * k, PHANTOM_TINT.b * k, PHANTOM_TINT.a)
	if depth == 0:
		return Color.WHITE
	if depth == 1:
		return REST_TINT
	var k := maxf(1.0 - REST_OLD_FADE * (depth - 2), 0.6)
	return Color(REST_OLD_TINT.r * k, REST_OLD_TINT.g * k, REST_OLD_TINT.b * k)

## A fresh tween for `c`, replacing whatever layout tween it was still running (so the
## grid and the stack never fight over a card).
func _card_tween(c: Card) -> Tween:
	if c.has_meta("layout_tween"):
		var old: Tween = c.get_meta("layout_tween")
		if old.is_valid():
			old.kill()
	var tw := create_tween().set_parallel(true)
	c.set_meta("layout_tween", tw)
	return tw

func _layout_rest(duration: float) -> void:
	var order := _stack_order()
	var count := order.size()
	for d in count:
		var c := order[d]
		var tint := _rest_tint(c, d)
		c.set_meta("tint", tint)
		var tw := _card_tween(c)
		tw.tween_property(c, "position", _rest_position(_rest_corner(d, count)), duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(c, "rotation", 0.0, duration)
		tw.tween_property(c, "scale", Vector2.ONE * REST_ZOOM, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(c, "modulate", tint, duration)
		if d >= REST_SHOWN:   # tucked away behind the deepest card shown
			tw.chain().tween_callback(c.hide)
		else:
			c.show()
		_add_tag(c)
		if c.has_meta("phantom"):
			c.glow(NeonTheme.CYAN, duration)
		elif d > 0:
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

# --- browsing the stack ---------------------------------------------------------

func _build_browse() -> void:
	_shade = ColorRect.new()
	_shade.color = Color(NeonTheme.INK, 0.9)
	_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shade.modulate.a = 0.0
	_shade.visible = false
	add_child(_shade)

	_chrome = Control.new()
	_chrome.set_anchors_preset(Control.PRESET_FULL_RECT)
	_chrome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chrome.modulate.a = 0.0
	_chrome.visible = false
	add_child(_chrome)
	# A band behind the heading and one behind the hint, so cards scroll away under them.
	for spec in [[0.0, BROWSE_TOP - 14.0, true], [-BROWSE_BOTTOM + 24.0, 0.0, false]]:
		var band := ColorRect.new()
		band.mouse_filter = Control.MOUSE_FILTER_IGNORE
		band.color = Color(NeonTheme.INK, 0.96)
		if spec[2]:
			band.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
			band.offset_bottom = spec[1]
		else:
			band.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
			band.offset_top = spec[0]
		_chrome.add_child(band)

	_heading = _browse_label(NeonTheme.FONT_HEAD, 34, NeonTheme.PINK)
	_heading.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_heading.offset_top = 46.0
	_heading.offset_bottom = 92.0
	_heading.add_theme_color_override("font_shadow_color", Color(NeonTheme.PINK, 0.6))
	_heading.add_theme_constant_override("shadow_outline_size", 8)
	_chrome.add_child(_heading)
	_subhead = _browse_label(NeonTheme.FONT_BODY, 22, Color(NeonTheme.TEXT, 0.7))
	_subhead.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_subhead.offset_top = 92.0
	_subhead.offset_bottom = 122.0
	_chrome.add_child(_subhead)
	var hint := _browse_label(NeonTheme.FONT_HEAD, 18, Color(NeonTheme.CYAN, 0.85))
	hint.text = "TAP TO RESTACK"
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -BROWSE_BOTTOM + 40.0
	hint.offset_bottom = -BROWSE_BOTTOM + 80.0
	_chrome.add_child(hint)

func _browse_label(font: Font, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l

func is_browsing() -> bool:
	return _browsing

## A tap on a resting stack card opens the grid. Buttons and panels get the press first,
## so this only sees taps on the felt.
func _unhandled_input(event: InputEvent) -> void:
	if _browsing or browse_locked:
		return
	var mb := event as InputEventMouseButton
	if mb == null or mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	if _hits_stack(mb.position):
		get_viewport().set_input_as_handled()
		open_browse()

func _hits_stack(screen_pos: Vector2) -> bool:
	var p := get_global_transform_with_canvas().affine_inverse() * screen_pos
	for c in _stack_order():
		if c.visible and Rect2(c.position + Card.CARD_SIZE * 0.5 * (Vector2.ONE - c.scale), Card.CARD_SIZE * c.scale).has_point(p):
			return true
	return false

## While the grid is open it takes every press and drag before the HUD sees them: a drag
## scrolls, a tap anywhere folds the cards back into the stack.
func _input(event: InputEvent) -> void:
	if not _browsing:
		return
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		get_viewport().set_input_as_handled()   # the emulated mouse events do the work
		return
	var mb := event as InputEventMouseButton
	if mb != null:
		get_viewport().set_input_as_handled()
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed: _scroll_to(_scroll + 60.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed: _scroll_to(_scroll - 60.0)
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_pressing = true
					_dragged = false
					_press_at = mb.position
					_press_scroll = _scroll
				elif _pressing:
					_pressing = false
					if not _dragged:
						close_browse()
		return
	var mm := event as InputEventMouseMotion
	if mm != null:
		get_viewport().set_input_as_handled()
		if _pressing:
			var dy := mm.position.y - _press_at.y
			if absf(dy) > TAP_SLOP:
				_dragged = true
			if _dragged:
				_scroll_to(_press_scroll + dy / maxf(get_global_transform_with_canvas().get_scale().y, 0.01))

func _grid_cols(count: int) -> int:
	return BROWSE_COLS_FEW if count <= BROWSE_FEW else BROWSE_COLS_MANY

## The scale that fits `cols` cards across the screen with gaps on either side.
func _grid_scale(cols: int) -> float:
	return minf(1.0, (size.x - BROWSE_GAP * (cols + 1)) / (Card.CARD_SIZE.x * cols))

func _grid_center(i: int, count: int) -> Vector2:
	var cols := _grid_cols(count)
	var s := _grid_scale(cols)
	var cell := Card.CARD_SIZE * s + Vector2(BROWSE_GAP, BROWSE_GAP)
	var col := i % cols
	var row := i / cols
	var in_row := mini(cols, count - row * cols)   # a short last row is centred
	var x := size.x * 0.5 + (col - (in_row - 1) * 0.5) * cell.x
	var y := BROWSE_TOP + _scroll + row * cell.y + Card.CARD_SIZE.y * s * 0.5
	return Vector2(x, y)

func _max_scroll(count: int) -> float:
	var cols := _grid_cols(count)
	var rows := ceili(float(count) / cols)
	var content := rows * (Card.CARD_SIZE.y * _grid_scale(cols) + BROWSE_GAP) - BROWSE_GAP
	return maxf(0.0, content - (size.y - BROWSE_TOP - BROWSE_BOTTOM))

func _scroll_to(value: float) -> void:
	var order := _stack_order()
	_scroll = clampf(value, -_max_scroll(order.size()), 0.0)
	for i in order.size():
		var c := order[i]
		if c.has_meta("layout_tween"):
			var tw: Tween = c.get_meta("layout_tween")
			if tw.is_valid():
				tw.kill()
		c.scale = Vector2.ONE * _grid_scale(_grid_cols(order.size()))
		c.rotation = 0.0
		c.modulate = _grid_tint(c)
		_set_center(c, _grid_center(i, order.size()))

## Spread every card in the stack into a grid, newest first, over a darkened felt.
func open_browse() -> void:
	var order := _stack_order()
	if _browsing or order.is_empty():
		return
	_browsing = true
	_pressing = false
	_scroll = 0.0
	z_index = BROWSE_Z
	Sfx.play("slide", 1.2)
	Sfx.vibrate(12)
	browse_changed.emit(true)
	_heading.text = "THE STACK  ·  %d" % order.size()
	var ghosts := order.filter(func(c: Card): return c.has_meta("phantom")).size()
	_subhead.text = "Newest first" if ghosts == 0 else "Newest first  ·  %d ghost%s from Post" % [ghosts, "" if ghosts == 1 else "s"]
	_shade.visible = true
	_chrome.visible = true
	move_child(_shade, _under.size() + 1)   # above the deck, below every stack card
	move_child(_chrome, get_child_count() - 1)
	var fade := create_tween().set_parallel(true)
	fade.tween_property(_shade, "modulate:a", 1.0, BROWSE_OPEN * 0.7)
	fade.tween_property(_chrome, "modulate:a", 1.0, BROWSE_OPEN).set_delay(BROWSE_OPEN * 0.3)
	var count := order.size()
	var s := _grid_scale(_grid_cols(count))
	for i in count:
		var c := order[i]
		c.show()
		var delay := BROWSE_STAGGER * mini(i, 12)
		var tw := _card_tween(c)
		tw.tween_property(c, "position", _grid_center(i, count) - Card.CARD_SIZE * 0.5, BROWSE_OPEN).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(delay)
		tw.tween_property(c, "scale", Vector2.ONE * s, BROWSE_OPEN).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).set_delay(delay)
		tw.tween_property(c, "modulate", _grid_tint(c), BROWSE_OPEN * 0.6).set_delay(delay)
		tw.tween_property(c, "rotation", 0.0, BROWSE_OPEN).set_delay(delay)
		# A small tilt on the way, so the cards read as dealt out rather than slid.
		c.rotation = randf_range(-0.12, 0.12)
		c.set_meta("rest_glow", c.glow_state())
		var phantom := c.has_meta("phantom")
		c.glow(NeonTheme.PINK if i == 0 else (NeonTheme.CYAN if i == 1 or phantom else NeonTheme.PURPLE), BROWSE_OPEN)
		_badge(c, "TOP" if i == 0 else ("DROP" if i == 1 else ("GHOST" if phantom else "")))

## Real cards show plainly in the grid; Post's phantom copies stay cyan and see-through.
func _grid_tint(c: Card) -> Color:
	return Color(PHANTOM_TINT, 0.8) if c.has_meta("phantom") else Color.WHITE

## Fold the grid back into the resting stack. Awaitable.
func close_browse() -> void:
	if not _browsing:
		return
	_browsing = false
	_pressing = false
	Sfx.play("slide", 0.9)
	browse_changed.emit(false)
	var fade := create_tween().set_parallel(true)
	fade.tween_property(_shade, "modulate:a", 0.0, BROWSE_CLOSE)
	fade.tween_property(_chrome, "modulate:a", 0.0, BROWSE_CLOSE * 0.5)
	_unbadge_all(BROWSE_CLOSE)
	_layout_rest(BROWSE_CLOSE)
	await fade.finished
	await get_tree().create_timer(maxf(0.0, BROWSE_CLOSE * 0.1)).timeout
	if not _browsing:
		_shade.visible = false
		_chrome.visible = false
		z_index = 0

## Leave the grid before the table changes under it: a quick fold, or at once (`instant`).
func _end_browse(instant: bool = false) -> void:
	if not _browsing and z_index == 0:
		return
	if not instant:
		if _browsing:
			close_browse()
		z_index = 0   # the dealt card and its escorted chip go back under the HUD's order
		return
	_browsing = false
	_pressing = false
	browse_changed.emit(false)
	_unbadge_all(0.0)
	_layout_rest(0.0)
	_shade.modulate.a = 0.0
	_chrome.modulate.a = 0.0
	_shade.visible = false
	_chrome.visible = false
	z_index = 0

## Take the TOP / DROP pills off and give every card back the glow it had at rest.
## (_layout_rest re-lights the older cards purple afterwards.)
func _unbadge_all(duration: float) -> void:
	for c in _stack_order():
		_badge(c, "")
		if c.has_meta("rest_glow"):
			c.set_glow_state(c.get_meta("rest_glow"), duration)
			c.remove_meta("rest_glow")

## A TOP / DROP pill on a card in the grid (`text` empty removes it).
func _badge(c: Card, text: String) -> void:
	var old := c.get_node_or_null("Badge")
	if old != null:
		old.queue_free()
	if text == "":
		return
	var accent := NeonTheme.PINK if text == "TOP" else (NeonTheme.CYAN if text == "DROP" else Color(PHANTOM_TINT, 1.0))
	var pill := PanelContainer.new()
	pill.name = "Badge"
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_theme_stylebox_override("panel", NeonTheme.panel_style(accent, Color(NeonTheme.INK, 0.95), 14, 2, 6))
	var l := _browse_label(NeonTheme.FONT_HEAD, 22 if text != "GHOST" else 18, accent)
	l.text = text
	pill.add_child(l)
	c.add_child(pill)
	pill.reset_size()
	pill.position = Vector2((Card.CARD_SIZE.x - pill.size.x) * 0.5, -pill.size.y * 0.5)

# --- clearing ----------------------------------------------------------------

## Clear the table. `chaotic` (a loss) flings the cards outward spinning; otherwise they
## are swept back into the deck. Awaitable.
func sweep(chaotic: bool) -> void:
	_end_browse(true)
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
	_end_browse(true)
	for c in _pool:
		c.queue_free()
	_pool.clear()
	if _active:
		_active.queue_free()
		_active = null
