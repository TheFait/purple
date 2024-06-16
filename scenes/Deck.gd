class_name Deck
extends Control

@export_file("*.json") var json_card_database_path : String
@export_file("*.json") var json_card_collection_path : String
@export var card_object : PackedScene
@export var random_deck : bool = false

@onready var card_location := $"../Stack"

var card_database := [] # Array of all card information
var card_collection := [] # Array of all cards in the deck

var deck := [] # Array of Card Objects
var stack := []
var discard_pile := []

func _ready():
	load_json_path()
	setup_deck()
	
func load_json_path():
	card_database = _load_cards_from_path(json_card_database_path)
	card_collection = _load_cards_from_path(json_card_collection_path)

func _load_cards_from_path(path : String):
	var loaded = []
	if path:
		var text = FileAccess.get_file_as_string(path)
		var parsed_text = JSON.parse_string(text)
		if parsed_text:
			for c in parsed_text:
				loaded.push_back(c)
	return loaded

func setup_deck():
	for card_name in card_collection:
		var card_data = _get_card_by_name(card_name)
		if card_data:
			var card = _create_card(card_data)
			deck.push_back(card)
		else:
			print("No Card Data")
	deck.shuffle()
	print("Deck Setup: cards = ", deck.size())
	Globals.cards_in_deck = deck.size()
	Globals.update_ui.emit()
	print("cards in deck: ", Globals.cards_in_deck)
	
func _get_card_by_name(p_name: String):
	for json_data in card_database:
		if json_data.nice_name == p_name:
			return json_data
	return null

func _create_card(card_data: Dictionary):
	var card = card_object.instantiate()
	card.setup_card(card_data.nice_name, int(card_data.rank), card_data.suit, card_data.texture_path, card_data.backface_texture_path)
	return card

func draw_card():
	var card
	if(random_deck):
		card = deck[randi_range(0,deck.size())]
	else:
		card = deck.pop_back() as Card
	print("Drawn card: ", card)
	stack.push_back(card)
	card.flip()
	return card
	#TODO Implement pure random card draw here, draw random card from entire deck and don't remove

func clear_stack():
	for c in stack:
		discard_pile.push_back(c)
	stack.clear()
	
	shuffle_deck()
	
func shuffle_deck():
	if (!random_deck):
		if discard_pile.size() > 0:
			for c in discard_pile:
				deck.push_back(c)
		
		if stack.size() > 0:
			for l in stack:
				deck.push_back(l)
	discard_pile.clear()
	stack.clear()
	deck.shuffle()
	
	Globals.cards_in_deck = deck.size()
	Globals.cards_in_stack = 0

func get_stack(num_cards:int) -> Array:
	var to_return = []
	for i in num_cards:
		to_return.push_back(stack[stack.size()-(i+1)])		
	return to_return
