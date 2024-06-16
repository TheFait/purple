extends Button
class_name Guess

var min_stack_size:int
var max_stack_size:int
var nice_name:String
var required_cards:int = 1
var required_stack:int = 0

signal guess_chosen(guess:Guess)


func _on_pressed():
	guess_chosen.emit(self)

func is_valid_guess(stack_size: int) -> bool: 
	if (min_stack_size == -1 or stack_size >= min_stack_size) and (stack_size <= max_stack_size or max_stack_size == -1):
		return true
		
	return false
