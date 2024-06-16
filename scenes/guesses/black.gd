extends Guess
class_name BlackGuess

func _init():
	min_stack_size = 0
	max_stack_size = -1
	nice_name = "Black"
	required_cards = 1

func evaluate_guess(cards_array: Array) -> bool:
	var to_test = cards_array[0] as Card
	if to_test.suit == Globals.SUITS.SPADES or to_test.suit == Globals.SUITS.CLUBS:
		return true
	else:
		return false

func _to_string():
	return nice_name
