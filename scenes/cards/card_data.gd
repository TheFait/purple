extends RefCounted
class_name CardData
## Network-serializable card. The rules read only rank/suit; the client maps
## this to a visual Card (Control) for display. Never holds a scene node.

var rank: int = 0          # 2..14 (J=11, Q=12, K=13, A=14)
var suit: int = 0          # Globals.SUITS
var nice_name: String = ""
var texture_path: String = ""
var backface_path: String = ""

func _init(p_rank: int = 0, p_suit: int = 0, p_nice: String = "", p_tex: String = "", p_back: String = "") -> void:
	rank = p_rank
	suit = p_suit
	nice_name = p_nice
	texture_path = p_tex
	backface_path = p_back

func is_red() -> bool:
	return suit == Globals.SUITS.HEARTS or suit == Globals.SUITS.DIAMONDS

func is_black() -> bool:
	return suit == Globals.SUITS.SPADES or suit == Globals.SUITS.CLUBS

func to_dict() -> Dictionary:
	return {"rank": rank, "suit": suit, "nice_name": nice_name, "texture_path": texture_path, "backface_path": backface_path}

static func from_dict(d: Dictionary):
	var script = load("res://scenes/cards/card_data.gd")
	var card = script.new()
	card.rank = int(d.get("rank", 0))
	card.suit = int(d.get("suit", 0))
	card.nice_name = String(d.get("nice_name", ""))
	card.texture_path = String(d.get("texture_path", ""))
	card.backface_path = String(d.get("backface_path", ""))
	return card

func _to_string() -> String:
	return nice_name
