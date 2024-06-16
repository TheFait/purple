extends Guess
class_name RedGuess

func _init():
	min_stack_size = 0
	max_stack_size = -1
	nice_name = "Red"
	required_cards = 1

func evaluate_guess(cards_array: Array) -> bool:
	var to_test = cards_array[0] as Card
	if to_test.suit == Globals.SUITS.DIAMONDS or to_test.suit == Globals.SUITS.HEARTS:
		return true
	else:
		return false

func _to_string():
	return nice_name
