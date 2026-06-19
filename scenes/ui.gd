extends CanvasLayer
class_name UI
## View layer for "Purple & Post". Holds NO game rules — it forwards button
## presses to the GameManager and renders the manager's signals into labels.
## The manager lives on the parent Game node; Deck and Stack are our children.

@onready var manager: GameManager = get_parent()

# Labels
@onready var streak_label: Label = $InfoPanel/StreakLabel
@onready var pool_label: Label = $InfoPanel/DrinkPoolLabel
@onready var deck_label: Label = $InfoPanel/DeckLabel
@onready var stack_label: Label = $InfoPanel/StackLabel
@onready var turn_log: Label = $TurnLogLabel

# Button groups
@onready var action_buttons: GridContainer = $ActionButtons
@onready var pass_buttons: HBoxContainer = $PassButtons
@onready var win_particles: CPUParticles2D = $ParticleHolder/WinParticles

var _last_streak: int = 0

func _ready() -> void:
	# Existing deck/stack counters still flow through Globals.update_ui.
	Globals.update_ui.connect(_update_counters)

	# Manager -> view.
	manager.streak_changed.connect(_on_streak_changed)
	manager.pool_changed.connect(_on_pool_changed)
	manager.penalty_triggered.connect(_on_penalty)
	manager.pass_available.connect(_on_pass_available)
	manager.log_message.connect(_on_log)

	# View -> manager. `.bind()` freezes the Move value passed to each handler.
	$ActionButtons/HigherButton.pressed.connect(_select.bind(GameManager.Move.HIGHER))
	$ActionButtons/LowerButton.pressed.connect(_select.bind(GameManager.Move.LOWER))
	$ActionButtons/RedButton.pressed.connect(_select.bind(GameManager.Move.RED))
	$ActionButtons/BlackButton.pressed.connect(_select.bind(GameManager.Move.BLACK))
	$ActionButtons/PurpleButton.pressed.connect(_select.bind(GameManager.Move.PURPLE))
	$ActionButtons/PostButton.pressed.connect(_select.bind(GameManager.Move.POST))

	$PassButtons/PassButton.pressed.connect(_on_pass_pressed)
	$PassButtons/RideButton.pressed.connect(_on_ride_pressed)

	pass_buttons.visible = false

# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _select(move: int) -> void:
	if not _can_act():
		return
	manager._on_move_selected(move)

func _on_pass_pressed() -> void:
	if _can_act():
		manager.request_pass()

func _on_ride_pressed() -> void:
	if _can_act():
		manager.request_ride()

## Multiplayer hook. In single-device (hotseat) play anyone at the device may
## act, so this is always true. Online play will override it to allow input
## only when it is the LOCAL player's turn (manager.current_player == my_seat).
func _can_act() -> bool:
	return true

# ---------------------------------------------------------------------------
# View updates
# ---------------------------------------------------------------------------

func _update_counters() -> void:
	deck_label.text = "Deck Size: %d" % Globals.cards_in_deck
	stack_label.text = "Stack Size: %d" % Globals.cards_in_stack

func _on_streak_changed(streak: int) -> void:
	streak_label.text = "Streak: %d" % streak
	if streak > _last_streak:
		win_particles.restart()  # burst on a correct guess (one_shot)
	_last_streak = streak

func _on_pool_changed(pool: int) -> void:
	pool_label.text = "Drink Pool: %d" % pool

func _on_penalty(amount: int) -> void:
	win_particles.emitting = false
	# The manager's play-by-play (via _on_log) already shows the drink line; we
	# keep the pool label as the lingering stakes readout.
	_last_streak = 0

func _on_pass_available(is_available: bool) -> void:
	pass_buttons.visible = is_available
	_set_actions_enabled(not is_available)  # lock moves until Pass/Ride resolves

func _on_log(text: String) -> void:
	turn_log.text = text

func _set_actions_enabled(enabled: bool) -> void:
	for child in action_buttons.get_children():
		if child is Button:
			child.disabled = not enabled
