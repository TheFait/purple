extends CanvasLayer
class_name UI

@onready var button:Button = $ButtonContainer/Button
@onready var deckLabel:Label = $VBoxContainer/DeckLabel
@onready var stackLabel:Label = $StackLabel
@onready var guess_container:BoxContainer = $GuessWrapper/GuessContainer
@onready var stack = $Stack
@onready var deck := $Deck
@onready var win_particles: CPUParticles2D = $ParticleHolder/WinParticles



signal draw_card()

func _ready():
	Globals.update_ui.connect(update_ui,1)

func _on_button_pressed():
	Globals.progress_game()


func _on_draw_card_pressed():
	draw_card.emit()

func update_ui():
	deckLabel.text = "Deck Size: " + str(Globals.cards_in_deck)
	stackLabel.text = "Stack Size: " + str(Globals.cards_in_stack)


func _on_draw_to_stack_pressed():
	var card = deck.draw_card()
	stack.add_child(card)
	Globals.cards_in_stack += 1
	Globals.cards_in_deck -= 1

func clear_stack():
	deck.clear_stack()
	for n in stack.get_children():
		stack.remove_child(n)
	
func _on_clear_stack_pressed():
	clear_stack()

func add_guess(in_guess: Guess):
	guess_container.add_child(in_guess)
	
func clear_guesses():
	for child in guess_container.get_children():
		guess_container.remove_child(child)

func draw_cards(to_draw:int):
	var drawn_cards = []
	for n in to_draw:
		var card = deck.draw_card()
		stack.add_child(card)
		Globals.cards_in_stack += 1
		Globals.cards_in_deck -= 1
		drawn_cards.push_back(card)
	return drawn_cards

func get_stack(cards:int):
	return deck.get_stack(cards)
	
func play_particle(was_correct:bool):
	if was_correct:
		win_particles.emitting = true
	# TODO  else play lose particle

func cleanup(correct_guess:bool):
	if !correct_guess:
		clear_stack()
	win_particles.emitting = false	

func set_button_text(text:String):
	button.text = text
