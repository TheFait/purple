extends Control
class_name Card

var rank: int
var suit: Globals.SUITS
var image_path: String
var back_face_path: String
var deck_type: String
var nice_name: String

@onready var front_face : TextureRect = $FrontFace
@onready var back_face : TextureRect = $BackFace

@export var is_facedown : bool = true

func setup_card(p_nice_name:String, p_rank: int, p_suit: String, p_front_path: String, p_back_path: String, p_deck_type: String = "black"):
	nice_name = p_nice_name
	rank = p_rank
	set_suit(p_suit)
	deck_type = p_deck_type	
	image_path = p_front_path
	back_face_path = p_back_path
	print(nice_name, " setup at: ", image_path)
	
	
func _ready():
	update_display()
	set_front_face(image_path)
	set_back_face(back_face_path)

func set_suit(p_suit:String):
	match p_suit.to_lower():
		"h", "hearts":
			suit = Globals.SUITS.HEARTS
		"s", "spades":
			suit = Globals.SUITS.SPADES
		"d", "diamonds":
			suit = Globals.SUITS.DIAMONDS
		"c", "clubs":
			suit = Globals.SUITS.CLUBS
	print("Suit set from ",p_suit, " to ", str(Globals.SUITS.keys()[suit]))

func _to_string():
	return nice_name

func update_display():
	if (is_facedown):
		front_face.set_visible(false)		
		back_face.set_visible(true)
	else:
		back_face.set_visible(false)
		front_face.set_visible(true)

func set_back_face(path:String):
	back_face_path = path
	back_face.texture = load(back_face_path)
	
func set_front_face(path:String):
	image_path = path
	front_face.texture = load(image_path)
	
func flip():
	is_facedown = !is_facedown
