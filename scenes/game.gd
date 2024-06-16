extends Node2D

@export var guesses: Array[PackedScene] = []

@onready var current_phase:int = Globals.TURN_PHASE.GAME_START

signal card_drawn(card:Card)

var card_scene:PackedScene = preload("res://scenes/card.tscn")
var clean_deck:Array = []

var deck_type:String = "black"

# Guess types
var current_guess: Guess
var loaded_guesses: Array = []
var guess_is_correct:bool = false

func _ready():
	print('Game.gd: ready')
	Globals.change_phase.connect(progress_turn)
	
	for guess in guesses:
		var loaded_guess = guess.instantiate()
		loaded_guesses.push_back(loaded_guess)
		loaded_guess.guess_chosen.connect(set_guess)
	Globals.update_ui.emit()

func _process(_delta):
# switch based on turn state
	match current_phase:
		Globals.TURN_PHASE.GAME_START:
			# Purple logo fades out
			pass
		Globals.TURN_PHASE.TURN_START:
			# Deck summon animation
			pass
		Globals.TURN_PHASE.GUESS:
			# Load Guesses
			pass
		Globals.TURN_PHASE.REVEAL:
			pass
		Globals.TURN_PHASE.RESULT:
			pass

func set_guess(p_guess:Guess):
	print("Setting guess: ", p_guess)
	current_guess = p_guess

func progress_turn():
	match current_phase:
		Globals.TURN_PHASE.GAME_START:
			current_phase = Globals.TURN_PHASE.TURN_START
			print("game start -> turn start")
			$UI.set_button_text("View Guesses")
		Globals.TURN_PHASE.TURN_START:
			current_phase = Globals.TURN_PHASE.GUESS
			print("turn start -> guess")
			# add valid guesses
			for guess in loaded_guesses:
				if guess.is_valid_guess(Globals.cards_in_stack):
					$UI.add_guess(guess)
			$UI.set_button_text("Submit Guess")
		Globals.TURN_PHASE.GUESS:
			if (current_guess):
				var drawn_cards = []
				if current_guess.required_stack > 0:
					drawn_cards = $UI.get_stack(current_guess.required_stack)
				drawn_cards = $UI.draw_cards(current_guess.required_cards) + drawn_cards
				if "evaluate_guess" in current_guess:
					if(current_guess.evaluate_guess(drawn_cards)):
						print("Guess is correct")
						guess_is_correct = true
						print("guess -> reveal")
						current_phase = Globals.TURN_PHASE.RESULT
					else:
						print("Guess is wrong")
						guess_is_correct = false
						current_phase = Globals.TURN_PHASE.RESULT
					$UI.play_particle(guess_is_correct)
					$UI.set_button_text("Next Turn")
					$UI.clear_guesses()
			else:
				print("Guess not chosen")
		Globals.TURN_PHASE.REVEAL:
			current_phase = Globals.TURN_PHASE.RESULT
			#TODO Play reveal animation for card and add to tree
		Globals.TURN_PHASE.RESULT:
			#clean everything up for next turn
			#TODO Reset current guess
			$UI.cleanup(guess_is_correct)
			current_phase = Globals.TURN_PHASE.TURN_START
			print("result -> turn start")
			$UI.set_button_text("View Guesses")
