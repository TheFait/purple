extends Node

enum SUITS {HEARTS, SPADES, DIAMONDS, CLUBS}
enum TURN_PHASE {GAME_START, TURN_START, GUESS, REVEAL, RESULT}
signal change_phase()
signal update_ui()

## The PURPLE logo is shown once per app launch: during the first game, until the first guess.
var logo_seen: bool = false

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
