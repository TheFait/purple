extends CanvasLayer
class_name UI
## View layer. Binds to a presenter (offline GameManager today; online Net later —
## both expose the same signals/methods) and holds no game rules.
##
## The engine resolves a move instantly, so the presenter's signals arrive in one burst.
## This view queues them and plays each one in order (deal -> suspense -> flip ->
## celebrate / chaos -> clear), locking input until the queue drains.

const SEAT_COLORS: Array[Color] = [NeonTheme.CYAN, NeonTheme.PINK, NeonTheme.GOLD, NeonTheme.GREEN, NeonTheme.PURPLE, NeonTheme.RED]
const CONFETTI_WIN: PackedColorArray = [NeonTheme.GOLD, NeonTheme.PINK, NeonTheme.CYAN, NeonTheme.GREEN, Color.WHITE]
const CONFETTI_LOSE: PackedColorArray = [NeonTheme.RED, Color("ff7a00"), NeonTheme.PINK, Color("2b0030")]
const MOVE_BUTTONS := {
	"HigherButton": GameEngine.Move.HIGHER, "LowerButton": GameEngine.Move.LOWER,
	"InsideButton": GameEngine.Move.INSIDE, "OutsideButton": GameEngine.Move.OUTSIDE,
	"RedButton": GameEngine.Move.RED, "BlackButton": GameEngine.Move.BLACK,
	"PurpleButton": GameEngine.Move.PURPLE, "PostButton": GameEngine.Move.POST,
}
# The guesses sit on the deck face as neon buttons. Rows are listed top to bottom and
# centred; a row with no legal guess is skipped. The first state (a bare stack) only
# allows Red / Black / Purple, so those grow into big buttons.
const CHIP_GAP := 16.0
const CHIP_ROW_GAP := 14.0
const CHIP_LETTERS := {"RedButton": "R", "BlackButton": "B", "PurpleButton": "P", "PostButton": "MATCH"}
const CHIP_ICONS := {
	"HigherButton": GuessIcon.Kind.HIGHER, "LowerButton": GuessIcon.Kind.LOWER,
	"InsideButton": GuessIcon.Kind.INSIDE, "OutsideButton": GuessIcon.Kind.OUTSIDE,
}
const CHIP_TIPS := {
	"HigherButton": "HIGHER
The next card is higher than the top card.",
	"LowerButton": "LOWER
The next card is lower than the top card.",
	"InsideButton": "INSIDE
The next card falls between the top two cards.",
	"OutsideButton": "OUTSIDE
The next card falls outside the top two cards.",
	"RedButton": "RED
The next card is a heart or a diamond.",
	"BlackButton": "BLACK
The next card is a spade or a club.",
	"PurpleButton": "PURPLE
Draw two cards: one red, one black. Counts for 2.",
	"PostButton": "MATCH (POST)
The next card matches the top card's rank.
Hit it and the stack doubles.",
}
const CHIP_RADIUS := 46
const ESCORT_HEIGHT := 68.0   # the pressed button shrinks to about this tall while it rides with its card
const PLAYER_DOT := 20.0          # a waiting seat is a small filled dot; the active seat gets the big numbered circle
const PLAYER_DOT_ACTIVE := 62.0
const LONG_PRESS := 0.45      # seconds to hold a button before its tooltip appears (touch)
const FAST_FORWARD_CARDS := 3   # when more card reveals than this are waiting, skip the drama

## The offline GameManager when this UI sits under one; otherwise the online client (Net).
@onready var presenter: Node = _pick_presenter()

@onready var root: Control = $Root
@onready var table: Table = $Root/Table
@onready var title_label: Label = $Root/TitleLabel
@onready var players_row: HBoxContainer = $Root/PlayersRow
@onready var streak_label: Label = $Root/StatsColumn/StreakPanel/VBox/StreakLabel
@onready var pool_label: Label = $Root/StatsColumn/PoolPanel/VBox/PoolLabel
@onready var turn_log: Label = $Root/TurnLogLabel
@onready var guess_layer: Control = $Root/GuessLayer
@onready var pass_panel: PanelContainer = $Root/PassPanel

var fx: ScreenFx

var _queue: Array[Dictionary] = []
var _running: bool = false
var _start_pending: bool = false
var _active_seat: int = 0
var _turn_announced: bool = false  # false until the opening turn has played
var _lost_round: bool = false    # the table clear that follows a penalty is the chaotic one
var _streak_shown: int = 0
var _pool_shown: int = 0
var _backdrop_mat: ShaderMaterial
var _move_buttons: Dictionary = {}   # button name -> Button
var _chip_shown: Dictionary = {}     # button name -> bool (currently fanned out)
var _chip_target: Dictionary = {}    # button name -> Rect2 it is laid out at
var _chip_tweens: Dictionary = {}    # button name -> Tween
var _chosen: Button                  # the chip just pressed, until its card is dealt
var _escorting: Button               # the chip riding along with the dealt card
var _player_dots: Array[Panel] = []   # one per seat; the active seat's is the big one
var _tip: PanelContainer
var _tip_label: Label
var _hold_id: int = 0                # bumped on every press / release so stale hold timers are ignored
var _long_pressed: bool = false      # the press that just ended showed a tooltip, so it is not a guess

func _pick_presenter() -> Node:
	var parent := get_parent()
	return parent if parent.has_method("act_move") else Net

func _ready() -> void:
	root.theme = NeonTheme.build()
	_style_labels()
	title_label.visible = not Globals.logo_seen
	_build_tip()
	_style_buttons()

	fx = ScreenFx.new()
	add_child(fx)
	var shake_layers: Array[CanvasLayer] = [self]
	var bg := get_parent().get_node_or_null("Background") as CanvasLayer
	if bg:
		shake_layers.append(bg)
		var backdrop := bg.get_node_or_null("Backdrop") as ColorRect
		if backdrop:
			_backdrop_mat = backdrop.material as ShaderMaterial
	fx.setup(root, shake_layers)
	fx.set_vignette(0.25, 0.0)

	presenter.card_revealed.connect(func(c: CardData): _enqueue("card", [c]))
	presenter.table_cleared.connect(func(): _enqueue("clear"))
	presenter.streak_changed.connect(func(s: int): _enqueue("streak", [s]))
	presenter.pool_changed.connect(func(p: int): _enqueue("pool", [p]))
	presenter.penalty_triggered.connect(func(seat: int, amt: int): _enqueue("penalty", [seat, amt]))
	presenter.pass_available.connect(func(on: bool): _enqueue("pass", [on]))
	presenter.turn_changed.connect(func(seat: int): _enqueue("turn", [seat]))
	presenter.table_restored.connect(func(cs: Array): _enqueue("restore", [cs]))
	presenter.seats_changed.connect(func(count: int, current: int): _enqueue("seats", [count, current]))
	presenter.player_left.connect(func(who: String): _enqueue("left", [who]))
	presenter.stack_passed.connect(func(from: int, to: int, n: int): _enqueue("passed", [from, to, n]))
	presenter.phantoms_added.connect(func(cs: Array): _enqueue("phantoms", [cs]))
	presenter.diamonds_forever.connect(func(): _enqueue("diamonds"))
	presenter.round_log.connect(func(t: String): _enqueue("log", [t]))

	for button_name: String in MOVE_BUTTONS:
		var b: Button = _move_buttons[button_name]
		b.pressed.connect(_select.bind(MOVE_BUTTONS[button_name]))
	$Root/PassPanel/VBox/PassButtons/PassButton.pressed.connect(_on_pass_pressed)
	# An online table already exists by the time this UI appears: ask the server for it.
	if presenter.has_method("request_sync"):
		presenter.request_sync()

# --- styling ---------------------------------------------------------------

func _style_labels() -> void:
	_font(title_label, NeonTheme.FONT_DISPLAY, 72, NeonTheme.PINK)
	title_label.add_theme_color_override("font_shadow_color", Color(NeonTheme.PINK, 0.8))
	title_label.add_theme_constant_override("shadow_outline_size", 12)
	for cap: Label in [$Root/StatsColumn/StreakPanel/VBox/Caption, $Root/StatsColumn/PoolPanel/VBox/Caption]:
		_font(cap, NeonTheme.FONT_HEAD, 12, Color(NeonTheme.TEXT, 0.65))
	_font(streak_label, NeonTheme.FONT_BODY, 46, NeonTheme.GOLD)
	_font(pool_label, NeonTheme.FONT_BODY, 46, NeonTheme.PINK)
	_font(turn_log, NeonTheme.FONT_BODY, 22, NeonTheme.TEXT)
	turn_log.visible = false   # debug text: F1 toggles it
	$Root/StatsColumn/StreakPanel.add_theme_stylebox_override("panel", NeonTheme.panel_style(NeonTheme.GOLD))
	$Root/StatsColumn/PoolPanel.add_theme_stylebox_override("panel", NeonTheme.panel_style(NeonTheme.PINK))
	pass_panel.add_theme_stylebox_override("panel", NeonTheme.panel_style(NeonTheme.GOLD, Color(0.1, 0.02, 0.2, 0.94), 20, 3, 18))

func _font(l: Label, font: Font, size: int, color: Color) -> void:
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)

func _style_buttons() -> void:
	for button_name: String in MOVE_BUTTONS:
		_move_buttons[button_name] = guess_layer.get_node(button_name)
	var accents := {
		"HigherButton": NeonTheme.PINK, "LowerButton": NeonTheme.CYAN,
		"InsideButton": NeonTheme.GREEN, "OutsideButton": NeonTheme.GOLD,
		"RedButton": NeonTheme.RED, "BlackButton": Color("b9b2d6"),
		"PurpleButton": NeonTheme.PURPLE, "PostButton": NeonTheme.GOLD,
	}
	for button_name: String in accents:
		var b: Button = _move_buttons[button_name]
		NeonTheme.accent_button(b, accents[button_name], CHIP_RADIUS)
		b.text = CHIP_LETTERS.get(button_name, "")
		b.add_theme_font_override("font", NeonTheme.FONT_HEAD)
		b.add_theme_font_size_override("font_size", 28 if button_name == "PostButton" else 40)
		if CHIP_ICONS.has(button_name):
			var icon := GuessIcon.new()
			icon.kind = CHIP_ICONS[button_name]
			b.add_child(icon)
		# Hover tooltip on PC; a press-and-hold tooltip on touch screens (see _bind_tooltip).
		b.tooltip_text = CHIP_TIPS[button_name]
		_bind_tooltip(b, CHIP_TIPS[button_name])
		_chip_reset(b)
	NeonTheme.accent_button($Root/PassPanel/VBox/PassButtons/PassButton, NeonTheme.GREEN)

# --- input -----------------------------------------------------------------

func _busy() -> bool:
	return _running or not _queue.is_empty()

func _select(move: int) -> void:
	if _long_pressed:
		_long_pressed = false
		return
	if _busy() or not presenter.can_act() or not (move in presenter.legal_moves()):
		return
	Sfx.play("click")
	Sfx.vibrate(15)
	_chosen = _move_buttons[MOVE_BUTTONS.find_key(move)]
	presenter.act_move(move)
	if not _busy():
		_chosen = null   # the presenter refused the move; nothing will be dealt

func _on_pass_pressed() -> void:
	if _busy() or not presenter.can_act():
		return
	Sfx.play("click")
	presenter.act_pass()

func _refresh_buttons() -> void:
	var locked: bool = _busy() or not presenter.can_act()
	var legal: Array[int] = presenter.legal_moves()
	for button_name: String in _move_buttons:
		var b: Button = _move_buttons[button_name]
		var valid: bool = MOVE_BUTTONS[button_name] in legal
		# The pressed chip stays lit while it rides along with its card.
		b.disabled = (locked or not valid) and b != _chosen and b != _escorting
	# Fan the chips out only once the round has played out, never mid-animation.
	if not _busy():
		_fan_chips(legal)
	for b: Button in $Root/PassPanel/VBox/PassButtons.get_children():
		b.disabled = _busy() or not presenter.can_act()

## Where each legal guess sits on the deck face, as {button name: Rect2} in global space.
## Rows are compacted and centred, so a smaller set of guesses gives a tighter grid.
func _chip_targets(legal: Array[int]) -> Dictionary:
	var rows: Array[Array] = []
	if not (MOVE_BUTTONS["HigherButton"] in legal):
		# A bare stack only allows Red / Black / Purple: three big buttons.
		rows.append([["PurpleButton", Vector2(200, 190)], ["BlackButton", Vector2(120, 190)], ["RedButton", Vector2(120, 190)]])
	else:
		rows.append([["PurpleButton", Vector2(260, 92)], ["BlackButton", Vector2(92, 92)], ["RedButton", Vector2(92, 92)]])
		rows.append([["HigherButton", Vector2(92, 92)], ["LowerButton", Vector2(92, 92)],
			["InsideButton", Vector2(92, 92)], ["OutsideButton", Vector2(92, 92)]])
		rows.append([["PostButton", Vector2(240, 76)]])
	var kept: Array[Array] = []
	for row: Array in rows:
		var open: Array = row.filter(func(e: Array): return MOVE_BUTTONS[e[0]] in legal)
		if not open.is_empty():
			kept.append(open)
	var total_h := CHIP_ROW_GAP * (kept.size() - 1)
	for row: Array in kept:
		total_h += _row_height(row)
	var center := table.chips_global_center()
	var y := center.y - total_h * 0.5
	var targets := {}
	for row: Array in kept:
		var h := _row_height(row)
		var w := CHIP_GAP * (row.size() - 1)
		for e: Array in row:
			w += (e[1] as Vector2).x
		var x := center.x - w * 0.5
		for e: Array in row:
			var sz: Vector2 = e[1]
			targets[e[0]] = Rect2(Vector2(x, y + (h - sz.y) * 0.5), sz)
			x += sz.x + CHIP_GAP
		y += h + CHIP_ROW_GAP
	return targets

func _row_height(row: Array) -> float:
	var h := 0.0
	for e: Array in row:
		h = maxf(h, (e[1] as Vector2).y)
	return h

func _fan_chips(legal: Array[int]) -> void:
	var targets := _chip_targets(legal)
	var order := 0
	for button_name: String in targets:
		var b: Button = _move_buttons[button_name]
		var r: Rect2 = targets[button_name]
		if not _chip_shown.get(button_name, false) or _chip_target[button_name].size != r.size:
			_chip_shown[button_name] = true
			_chip_in(b, r, order)
			order += 1
		elif _chip_target[button_name] != r:
			_chip_move(b, r)
		_chip_target[button_name] = r
	for button_name: String in _move_buttons:
		if not targets.has(button_name) and _chip_shown.get(button_name, false):
			_chip_shown[button_name] = false
			_chip_fade_out(_move_buttons[button_name])

func _chip_kill(b: Button) -> void:
	if _chip_tweens.has(b.name):
		_chip_tweens[b.name].kill()
		_chip_tweens.erase(b.name)

## Invisible and untouchable until the next pop-in.
func _chip_reset(b: Button) -> void:
	_chip_kill(b)
	b.modulate = Color(1, 1, 1, 0)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.rotation = 0.0
	b.scale = Vector2.ONE

func _chip_fade_out(b: Button) -> void:
	_chip_kill(b)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tw := create_tween()
	_chip_tweens[b.name] = tw
	tw.tween_property(b, "modulate:a", 0.0, 0.18)
	tw.tween_callback(_chip_reset.bind(b))

## Pop up out of the deck face into place, staggered like cards being dealt.
func _chip_in(b: Button, r: Rect2, order: int) -> void:
	_chip_reset(b)
	if b == _escorting:
		_escorting = null
	b.size = r.size
	b.pivot_offset = r.size * 0.5
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	b.position = r.position + Vector2(0.0, 26.0)
	b.scale = Vector2(0.4, 0.4)
	var tw := create_tween()
	_chip_tweens[b.name] = tw
	tw.tween_interval(0.05 * order)
	if order == 0:
		tw.tween_callback(Sfx.play.bind("slide", 1.2))
	tw.tween_property(b, "modulate:a", 1.0, 0.08)
	tw.parallel().tween_property(b, "position", r.position, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(b, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _chip_move(b: Button, r: Rect2) -> void:
	_chip_kill(b)
	var tw := create_tween()
	_chip_tweens[b.name] = tw
	tw.tween_property(b, "position", r.position, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

## The pressed button leaves the deck and rides with the card to the stack (same duration
## and easing as Table's deal), shrinking to a tag; the other buttons fade away. Returns
## the button, or null when this card was not dealt by a guess (opening card, new round).
func _take_escort(pair: bool, quick: bool) -> Button:
	var chip := _chosen
	_chosen = null
	if chip == null:
		return null
	_hide_logo()
	for button_name: String in _move_buttons:
		var b: Button = _move_buttons[button_name]
		if _chip_shown.get(button_name, false) and b != chip:
			_chip_fade_out(b)
		_chip_shown[button_name] = false
	_chip_kill(chip)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_escorting = chip
	var travel := Table.travel_time(quick)
	var tag := minf(1.0, ESCORT_HEIGHT / chip.size.y) * (Table.PAIR_SCALE if pair else 1.0)
	var tw := create_tween().set_parallel(true)
	_chip_tweens[chip.name] = tw
	tw.tween_property(chip, "position", table.escort_global_pos(pair) - chip.size * 0.5, travel).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(chip, "scale", Vector2(tag, tag), travel).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return chip

## Once the card is flipped the button takes the verdict's colour, then fades out.
func _escort_finish(chip: Button, outcome: String) -> void:
	if chip == null:
		return
	var tint := Color.WHITE
	match outcome:
		"win": tint = Color(0.55, 1.0, 0.7)
		"lose": tint = Color(1.0, 0.4, 0.45)
	_chip_kill(chip)
	var tw := create_tween()
	_chip_tweens[chip.name] = tw
	tw.tween_property(chip, "modulate", tint, 0.1)
	tw.tween_interval(0.35)
	tw.tween_property(chip, "modulate:a", 0.0, 0.3)
	tw.tween_callback(_chip_reset.bind(chip))

# --- tooltips --------------------------------------------------------------
# PC shows Godot's own hover tooltip (tooltip_text). Touch screens have no hover, so
# pressing and holding a button shows the same text above it; that press is not a guess.

func _build_tip() -> void:
	_tip = PanelContainer.new()
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.visible = false
	_tip.z_index = 10
	_tip.add_theme_stylebox_override("panel", NeonTheme.panel_style(NeonTheme.CYAN, Color(NeonTheme.INK, 0.96), 14, 2, 12))
	_tip_label = Label.new()
	_tip_label.custom_minimum_size.x = 300
	_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_label.add_theme_font_override("font", NeonTheme.FONT_BODY)
	_tip_label.add_theme_font_size_override("font_size", 22)
	_tip.add_child(_tip_label)
	root.add_child(_tip)

func _bind_tooltip(b: Button, text: String) -> void:
	if not DisplayServer.is_touchscreen_available():
		return
	b.button_down.connect(_on_chip_down.bind(b, text))
	b.button_up.connect(_hide_tip)

func _on_chip_down(b: Button, text: String) -> void:
	_long_pressed = false
	_hold_id += 1
	var id := _hold_id
	await get_tree().create_timer(LONG_PRESS).timeout
	if id == _hold_id:
		_long_pressed = true
		_show_tip(b, text)

func _hide_tip() -> void:
	_hold_id += 1
	_tip.visible = false

func _show_tip(b: Button, text: String) -> void:
	_tip_label.text = text
	_tip.reset_size()
	var sz := _tip.get_combined_minimum_size()
	var rect := b.get_global_rect()
	var view_w := get_viewport().get_visible_rect().size.x
	_tip.position = Vector2(clampf(rect.get_center().x - sz.x * 0.5, 8.0, view_w - sz.x - 8.0), rect.position.y - sz.y - 12.0)
	_tip.visible = true
	Sfx.vibrate(20)

## F1 shows or hides the round log (the debug text along the bottom of the screen).
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F1:
		turn_log.visible = not turn_log.visible

# --- event queue -----------------------------------------------------------

func _enqueue(kind: String, args: Array = []) -> void:
	_queue.append({"kind": kind, "args": args})
	_refresh_buttons()
	if not _running and not _start_pending:
		# Wait for the end of the frame so a whole engine burst is queued first
		# (Purple's two cards are recognised as a pair by peeking at the queue).
		_start_pending = true
		_start_queue.call_deferred()

func _start_queue() -> void:
	_start_pending = false
	if not _running:
		_run_queue()

func _run_queue() -> void:
	_running = true
	while not _queue.is_empty():
		var ev: Dictionary = _queue.pop_front()
		await _play(ev.kind, ev.args)
	_running = false
	_chosen = null
	_escorting = null
	_refresh_buttons()

## True only when reveals have really piled up (several moves arrived at once). Counts
## waiting card reveals, not all events: one guess already queues a pool / streak / pass /
## turn / new-round burst, which grows with the stack and must not rush the flip.
func _fast() -> bool:
	var reveals := 0
	for ev in _queue:
		if ev.kind == "card":
			reveals += 1
	return reveals > FAST_FORWARD_CARDS

## Wait `seconds`, shortened when the queue is backed up.
func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds * (0.2 if _fast() else 1.0)).timeout

func _play(kind: String, args: Array) -> void:
	match kind:
		"card": await _on_card(args[0])
		"pool": _on_pool(args[0])
		"streak": await _on_streak(args[0])
		"penalty": await _on_penalty(args[0], args[1])
		"clear": await _on_clear()
		"restore": _on_restore(args[0])
		"seats": _on_seats(args[1])
		"left": await _on_left(args[0])
		"passed": await _on_passed(args[0], args[1], args[2])
		"phantoms": await _on_phantoms(args[0])
		"diamonds": await _on_diamonds()
		"pass": _on_pass_available(args[0])
		"turn": await _on_turn(args[0])
		"log": turn_log.text = args[0]

## What the cards still queued say about the card just flipped.
func _peek_outcome() -> String:
	for ev in _queue:
		match ev.kind:
			"card", "clear": return "neutral"
			"penalty": return "lose"
			"streak":
				if ev.args[0] > _streak_shown:
					return "win"
	return "neutral"

# --- event handlers --------------------------------------------------------

## Purple flips two cards in one burst: a second "card" event waiting behind this one
## (only pool/log events between them) is its partner. Takes it out of the queue.
func _take_pair_partner() -> CardData:
	for i in _queue.size():
		match _queue[i].kind:
			"pool", "log": continue
			"card":
				var partner: CardData = _queue[i].args[0]
				_queue.remove_at(i)
				return partner
			_: return null
	return null

func _on_card_pair(first: CardData, second: CardData) -> void:
	var quick := _fast()
	var chip := _take_escort(true, quick)
	var suspense := 0.0
	if not quick:
		suspense = clampf(0.7 + 0.1 * _pool_shown + 0.12 * _streak_shown, 0.7, 1.6)
		fx.set_vignette(0.6, 0.3, Color(0.12, 0.0, 0.2))
	var cards: Array[Card] = await table.reveal_pair(first, second, suspense, quick)
	fx.set_vignette(0.25, 0.35)
	var outcome := "neutral" if quick else _peek_outcome()
	var color := NeonTheme.CYAN
	match outcome:
		"win":
			color = NeonTheme.GREEN
			Sfx.play("win", 1.0 + 0.06 * _streak_shown)
		"lose":
			color = NeonTheme.RED
			fx.shake(7, 0.3)
		_:
			if not quick:
				Sfx.play("tick", 1.3)
	_escort_finish(chip, outcome)
	for c in cards:
		c.glow(color)
		if not quick and outcome != "neutral":
			var punch := create_tween()
			punch.tween_property(c, "scale", Vector2(0.92, 0.92), 0.08)
			punch.tween_property(c, "scale", Vector2(Table.PAIR_SCALE, Table.PAIR_SCALE), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if not quick:
		await _wait(0.4)
	if outcome != "lose":
		await table.settle(0.15 if quick else 0.45)

func _on_card(data: CardData) -> void:
	var partner := _take_pair_partner()
	if partner != null:
		await _on_card_pair(data, partner)
		return
	var quick := _fast()
	var chip := _take_escort(false, quick)
	var suspense := 0.0
	if not quick:
		suspense = clampf(0.5 + 0.1 * _pool_shown + 0.12 * _streak_shown, 0.5, 1.5)
		fx.set_vignette(0.6, 0.3, Color(0.12, 0.0, 0.2))
	var card: Card = await table.reveal(data, suspense, quick)
	fx.set_vignette(0.25, 0.35)
	if quick:
		card.glow(NeonTheme.CYAN)
		_escort_finish(chip, "neutral")
		await table.settle(0.15)
		return
	var outcome := _peek_outcome()
	_escort_finish(chip, outcome)
	match outcome:
		"win":
			card.glow(NeonTheme.GREEN)
			Sfx.play("win", 1.0 + 0.06 * _streak_shown)
			_punch(card, 1.18, Table.REVEAL_ZOOM)
		"lose":
			card.glow(NeonTheme.RED)
			fx.shake(7, 0.3)
			_punch(card, 1.12, Table.REVEAL_ZOOM)
		_:
			card.glow(NeonTheme.CYAN)
			Sfx.play("tick", 1.3)
	await _wait(0.4)
	if outcome != "lose":
		await table.settle()

func _on_pool(pool: int) -> void:
	var grew := pool > _pool_shown
	_pool_shown = pool
	pool_label.text = str(pool)
	if grew:
		_punch(pool_label, 1.35)

func _on_streak(streak: int) -> void:
	var gained := streak > _streak_shown
	_streak_shown = streak
	streak_label.text = str(streak)
	if not gained:
		return
	_punch(streak_label, 1.5)
	_pulse_backdrop(0.6)
	Sfx.vibrate(40)
	if streak >= 3:
		Sfx.play("streak")
	fx.confetti(table.global_center(), 28 + 18 * mini(streak, 8), CONFETTI_WIN, 0.8 + 0.12 * mini(streak, 8))
	fx.flash(NeonTheme.GOLD, 0.18, 0.3)
	if streak >= 2:
		fx.slam_text("STREAK x%d!" % streak, NeonTheme.GOLD, 72 + 8 * mini(streak, 6), 0.45, NeonTheme.FONT_HEAD)
	await _wait(0.5)

func _on_penalty(seat: int, amount: int) -> void:
	_lost_round = true
	Sfx.play("lose")
	Sfx.vibrate(450)
	fx.shake(18.0 + 3.0 * mini(amount, 8), 0.9)
	fx.flash(NeonTheme.RED, 0.65, 0.55)
	fx.aberrate(0.035, 0.9)
	fx.set_vignette(0.7, 0.2, Color(0.35, 0.0, 0.05))
	_pulse_backdrop(1.0)
	pool_label.modulate = Color(1, 0.3, 0.3)
	fx.confetti(table.global_center(), 60 + 8 * mini(amount, 10), CONFETTI_LOSE, 1.5)
	var who: String = presenter.player_name(seat)
	# A long name gets a smaller slam so it still fits on one line.
	var size := 92 if who.length() <= 8 else (72 if who.length() <= 12 else 56)
	await fx.slam_text("%s,
DRINK %d!" % [who, amount], NeonTheme.RED, size, 0.8, NeonTheme.FONT_HEAD)
	pool_label.modulate = Color.WHITE
	fx.set_vignette(0.25, 0.4)

func _on_clear() -> void:
	var chaotic := _lost_round
	_lost_round = false
	await table.sweep(chaotic)
	await _wait(0.15)

## Someone joined or left, so the turn order may have shifted: redraw the players row.
func _on_seats(current: int) -> void:
	_active_seat = current
	_show_players(current)

func _on_left(who: String) -> void:
	Sfx.play("lose", 0.8)
	await fx.slam_text("%s has disconnected" % who, NeonTheme.GOLD, 64, 1.1, NeonTheme.FONT_HEAD)

## A snapshot of the table (joined late or reloaded): put the stack down without any show.
func _on_restore(cards: Array) -> void:
	table.restore(cards)

func _on_phantoms(cards: Array) -> void:
	Sfx.play("streak")
	Sfx.vibrate(120)
	fx.flash(NeonTheme.CYAN, 0.35, 0.3)
	await fx.slam_text("POSTED.", NeonTheme.CYAN, 128, 0.7, NeonTheme.FONT_HEAD)
	await table.add_phantoms(cards)
	await _wait(0.2)

func _on_diamonds() -> void:
	Sfx.play("streak")
	Sfx.vibrate(200)
	fx.confetti(table.global_center(), 120, CONFETTI_WIN, 1.4)
	fx.flash(NeonTheme.CYAN, 0.5, 0.5)
	_pulse_backdrop(1.0)
	await fx.slam_text("DIAMONDS
ARE FOREVER!", NeonTheme.CYAN, 84, 0.9, NeonTheme.FONT_HEAD)

func _on_pass_available(on: bool) -> void:
	pass_panel.visible = on
	if on:
		pass_panel.pivot_offset = pass_panel.size * 0.5
		pass_panel.scale = Vector2(0.7, 0.7)
		pass_panel.modulate.a = 0.0
		var tw := create_tween().set_parallel(true)
		tw.tween_property(pass_panel, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(pass_panel, "modulate:a", 1.0, 0.15)
	_refresh_buttons()

func _on_turn(seat: int) -> void:
	_active_seat = seat
	_show_players(seat)
	_punch(_player_dots[seat], 1.3)
	Sfx.play("turn")
	# A loss keeps the same seat, so after the opening turn a turn change is the stack being
	# passed on (announced by its own "passed" event) or a player leaving: announce who is up.
	if _turn_announced and not _pass_queued():
		var color: Color = SEAT_COLORS[seat % SEAT_COLORS.size()]
		await fx.slam_text("%s,\nyou're up!" % presenter.player_name(seat), color, 80, 0.7, NeonTheme.FONT_HEAD)
	else:
		await _wait(0.25)
	_turn_announced = true

func _pass_queued() -> bool:
	for ev in _queue:
		if ev.kind == "passed":
			return true
	return false

## The stack changed hands. The player who passed sees where it went; everyone else is told
## who is up (on a shared hotseat screen the device holder is the one who passed).
func _on_passed(from_seat: int, to_seat: int, count: int) -> void:
	var color: Color = SEAT_COLORS[to_seat % SEAT_COLORS.size()]
	var who: String = presenter.player_name(to_seat)
	if presenter.is_hotseat() or from_seat == presenter.local_seat():
		await fx.slam_text("Passed stack of %d to %s" % [count, who], color, 56, 1.0, NeonTheme.FONT_HEAD)
	else:
		await fx.slam_text("%s,\nyou're up!" % who, color, 80, 0.8, NeonTheme.FONT_HEAD)

## One circle per player in seat colours; the player whose turn it is gets the big one.
func _show_players(active: int) -> void:
	var count: int = maxi(presenter.seat_count(), active + 1)
	while _player_dots.size() < count:
		var seat := _player_dots.size()
		var dot := Panel.new()
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var label := Label.new()
		label.text = str(seat + 1)
		label.name = "Seat"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_override("font", NeonTheme.FONT_BODY)
		dot.add_child(label)
		label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		players_row.add_child(dot)
		_player_dots.append(dot)
		dot.custom_minimum_size = Vector2(PLAYER_DOT, PLAYER_DOT)
	# Someone left: drop the extra dots (the row must never show more players than there are).
	while _player_dots.size() > count:
		_player_dots.pop_back().queue_free()
	for seat in _player_dots.size():
		var dot := _player_dots[seat]
		var color: Color = SEAT_COLORS[seat % SEAT_COLORS.size()]
		var is_active := seat == active
		var dot_size := PLAYER_DOT_ACTIVE if is_active else PLAYER_DOT
		if is_active:
			dot.add_theme_stylebox_override("panel", NeonTheme.panel_style(color, Color(NeonTheme.INK, 0.9), 100, 4, 18))
		else:
			dot.add_theme_stylebox_override("panel", NeonTheme.panel_style(color, Color(color, 0.85), 100, 0, 0))
		var label: Label = dot.get_node("Seat")
		label.visible = is_active   # only the active player shows a number
		label.add_theme_font_size_override("font_size", 34)
		label.add_theme_color_override("font_color", color.lightened(0.4))
		create_tween().tween_property(dot, "custom_minimum_size", Vector2(dot_size, dot_size), 0.2)

# --- helpers ---------------------------------------------------------------

## The title only greets the first game after the app opens; it leaves with the first guess.
func _hide_logo() -> void:
	Globals.logo_seen = true
	if title_label.visible:
		var tw := create_tween()
		tw.tween_property(title_label, "modulate:a", 0.0, 0.4)
		tw.tween_callback(title_label.hide)

## Pop `node` to `amount` times its resting scale and settle back (`rest` is 1 except for the zoomed cards).
func _punch(node: Control, amount: float = 1.3, rest: float = 1.0) -> void:
	node.pivot_offset = node.size * 0.5
	node.scale = Vector2.ONE * rest * amount
	var tw := create_tween()
	tw.tween_property(node, "scale", Vector2.ONE * rest, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _pulse_backdrop(amount: float) -> void:
	if _backdrop_mat == null:
		return
	_backdrop_mat.set_shader_parameter("pulse", amount)
	var tw := create_tween()
	tw.tween_method(func(v: float): _backdrop_mat.set_shader_parameter("pulse", v), amount, 0.0, 0.7)
