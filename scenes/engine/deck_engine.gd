extends RefCounted
class_name DeckEngine
## Pure card storage + RNG. No scene nodes, no textures loaded. Server-safe.

var _deck: Array[CardData] = []
var _discard: Array[CardData] = []

func load_from_json(database_path: String, collection_path: String) -> void:
	_deck.clear()
	_discard.clear()
	var database: Array = _read_json_array(database_path)
	var collection: Array = _read_json_array(collection_path)
	for card_name in collection:
		var info := _find_by_name(database, String(card_name))
		if info.is_empty():
			push_warning("DeckEngine: no card data for %s" % card_name)
			continue
		_deck.append(CardData.new(
			int(info.get("rank", 0)),
			_suit_from_string(String(info.get("suit", ""))),
			String(info.get("nice_name", "")),
			String(info.get("texture_path", "")),
			String(info.get("backface_texture_path", ""))))
	shuffle()

func load_cards(cards: Array) -> void:
	## Unshuffled deck for tests; draw() pops from the back, so the last card is drawn first.
	_deck.clear()
	_discard.clear()
	for c in cards:
		_deck.append(c)

func shuffle() -> void:
	_deck.shuffle()

func deck_size() -> int:
	return _deck.size()

func discard_size() -> int:
	return _discard.size()

## The names of the cards still in the deck, in the order they will be drawn. Only for tests
## that check the server never reveals a card early; nothing in the game sends this anywhere.
func names_in_draw_order() -> Array:
	var names: Array = []
	for i in range(_deck.size() - 1, -1, -1):
		names.append(_deck[i].nice_name)
	return names

func draw() -> CardData:
	if _deck.is_empty():
		recycle()
	if _deck.is_empty():
		return null
	return _deck.pop_back()

func discard(cards: Array) -> void:
	for c in cards:
		_discard.append(c)

func recycle() -> void:
	_deck.append_array(_discard)
	_discard.clear()
	shuffle()

func return_to_deck(cards: Array) -> void:
	for c in cards:
		_deck.append(c)
	shuffle()

func _read_json_array(path: String) -> Array:
	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	return parsed if parsed is Array else []

func _find_by_name(database: Array, card_name: String) -> Dictionary:
	for entry in database:
		if entry is Dictionary and String(entry.get("nice_name", "")) == card_name:
			return entry
	return {}

func _suit_from_string(s: String) -> int:
	match s.to_lower():
		"h", "hearts": return Globals.SUITS.HEARTS
		"s", "spades": return Globals.SUITS.SPADES
		"d", "diamonds": return Globals.SUITS.DIAMONDS
		"c", "clubs": return Globals.SUITS.CLUBS
	return Globals.SUITS.HEARTS
