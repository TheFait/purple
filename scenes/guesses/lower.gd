extends Guess
class_name LowerGuess

func _init():
	min_stack_size = 1
	max_stack_size = -1
	nice_name = "Lower"
	required_cards = 1
	required_stack = 1

func evaluate_guess(cards_array: Array) -> bool:
	var stack_card = cards_array[1] as Card
	var drawn_card = cards_array[0] as Card
	if drawn_card.rank < stack_card.rank:
		return true
	
	return false

func _to_string():
	return nice_name
