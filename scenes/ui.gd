extends CanvasLayer
class_name UI
## View layer. Binds to a presenter (offline GameManager today; online Net
## later — both expose the same signals/methods). Holds no game rules.

@onready var presenter: Node = get_parent()

@onready var streak_label: Label = $InfoPanel/StreakLabel
@onready var pool_label: Label = $InfoPanel/DrinkPoolLabel
@onready var deck_label: Label = $InfoPanel/DeckLabel
@onready var stack_label: Label = $InfoPanel/StackLabel
@onready var turn_log: Label = $TurnLogLabel
@onready var action_buttons: GridContainer = $ActionButtons
@onready var pass_buttons: HBoxContainer = $PassButtons
@onready var win_particles: CPUParticles2D = $ParticleHolder/WinParticles

var _last_streak: int = 0

func _ready() -> void:
	Globals.update_ui.connect(_update_counters)
	presenter.streak_changed.connect(_on_streak_changed)
	presenter.pool_changed.connect(_on_pool_changed)
	presenter.penalty_triggered.connect(_on_penalty)
	presenter.pass_available.connect(_on_pass_available)
	presenter.round_log.connect(_on_log)

	$ActionButtons/HigherButton.pressed.connect(_select.bind(GameEngine.Move.HIGHER))
	$ActionButtons/LowerButton.pressed.connect(_select.bind(GameEngine.Move.LOWER))
	$ActionButtons/RedButton.pressed.connect(_select.bind(GameEngine.Move.RED))
	$ActionButtons/BlackButton.pressed.connect(_select.bind(GameEngine.Move.BLACK))
	$ActionButtons/PurpleButton.pressed.connect(_select.bind(GameEngine.Move.PURPLE))
	$ActionButtons/PostButton.pressed.connect(_select.bind(GameEngine.Move.POST))
	$PassButtons/PassButton.pressed.connect(_on_pass_pressed)
	$PassButtons/RideButton.pressed.connect(_on_ride_pressed)
	pass_buttons.visible = false

func _select(move: int) -> void:
	if presenter.can_act():
		presenter.act_move(move)

func _on_pass_pressed() -> void:
	if presenter.can_act():
		presenter.act_pass()

func _on_ride_pressed() -> void:
	if presenter.can_act():
		presenter.act_ride()

func _update_counters() -> void:
	deck_label.text = "Deck Size: %d" % Globals.cards_in_deck
	stack_label.text = "Stack Size: %d" % Globals.cards_in_stack

func _on_streak_changed(streak: int) -> void:
	streak_label.text = "Streak: %d" % streak
	if streak > _last_streak:
		win_particles.restart()
	_last_streak = streak

func _on_pool_changed(pool: int) -> void:
	pool_label.text = "Drink Pool: %d" % pool

func _on_penalty(_seat: int, _amount: int) -> void:
	win_particles.emitting = false
	_last_streak = 0

func _on_pass_available(is_available: bool) -> void:
	pass_buttons.visible = is_available
	for child in action_buttons.get_children():
		if child is Button:
			child.disabled = is_available

func _on_log(text: String) -> void:
	turn_log.text = text
