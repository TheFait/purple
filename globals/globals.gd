extends Node

enum SUITS {HEARTS, SPADES, DIAMONDS, CLUBS}
enum TURN_PHASE {GAME_START, TURN_START, GUESS, REVEAL, RESULT}
signal change_phase()
signal update_ui()

var current_guess:Guess

var cards_in_deck: int:
	set(value):
		cards_in_deck = value
		update_ui.emit()
		
var cards_in_stack: int:
	set(value):
		cards_in_stack = value
		update_ui.emit()

func progress_game():
	change_phase.emit()

