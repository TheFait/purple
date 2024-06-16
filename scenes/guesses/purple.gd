extends Guess
class_name PurpleGuess

func _init():
	min_stack_size = 0
	max_stack_size = -1
	nice_name = "Purple"
	required_cards = 2


func evaluate_guess(cards_array: Array) -> bool:
	var card1 = cards_array[0] as Card
	var card2 = cards_array[1] as Card
	if card1.suit == Globals.SUITS.DIAMONDS or card1.suit == Globals.SUITS.HEARTS:
		if card2.suit == Globals.SUITS.SPADES or card2.suit == Globals.SUITS.CLUBS:
			return true
	else:
		if card2.suit == Globals.SUITS.DIAMONDS or card2.suit == Globals.SUITS.HEARTS:
			return true
	return false

func _to_string():
	return nice_name
