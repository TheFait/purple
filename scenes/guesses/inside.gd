extends Guess
class_name InsideGuess

func _init():
	min_stack_size = 2
	max_stack_size = -1
	nice_name = "Inside"
	required_cards = 1
	required_stack = 2

func evaluate_guess(cards_array: Array) -> bool:
	var drawn_card_rank = cards_array[0].rank
	var top_card_rank = cards_array[1].rank
	var drop_card_rank = cards_array[2].rank
	
	if top_card_rank > drop_card_rank:
		if (drop_card_rank < drawn_card_rank and drawn_card_rank < top_card_rank):
			return true
	elif drop_card_rank > top_card_rank:
		if (drop_card_rank > drawn_card_rank and drawn_card_rank > top_card_rank):
			return true
	
	return false

func _to_string():
	return nice_name
