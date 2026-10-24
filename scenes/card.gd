extends Control
class_name Card
## Client-only visual card. Faces are swapped by an animated flip; a neon frame
## on top glows to signal the result (see glow()).

const CARD_SIZE := Vector2(200, 284)

var rank: int
var suit: Globals.SUITS
var image_path: String
var back_face_path: String
var deck_type: String
var nice_name: String

@onready var front_face : TextureRect = $FrontFace
@onready var back_face : TextureRect = $BackFace

@export var is_facedown : bool = true

var _frame: Panel          # border, drawn above the faces
var _frame_style: StyleBoxFlat
var _glow: Panel           # opaque backing whose shadow is the outer glow
var _glow_style: StyleBoxFlat

func setup_card(p_nice_name:String, p_rank: int, p_suit: String, p_front_path: String, p_back_path: String, p_deck_type: String = "black"):
	nice_name = p_nice_name
	rank = p_rank
	set_suit(p_suit)
	deck_type = p_deck_type
	image_path = p_front_path
	back_face_path = p_back_path

func _ready():
	custom_minimum_size = CARD_SIZE
	size = CARD_SIZE
	pivot_offset = CARD_SIZE * 0.5
	set_front_face(image_path)
	set_back_face(back_face_path)
	_build_frame()
	update_display()

func _build_frame() -> void:
	# The glow lives on a backing panel *behind* the faces: a StyleBoxFlat shadow is also
	# drawn through a transparent middle, which would tint the whole card face.
	_glow = Panel.new()
	_glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow_style = StyleBoxFlat.new()
	_glow_style.bg_color = Color(0.05, 0.02, 0.12, 1.0)
	_glow_style.set_corner_radius_all(14)
	_glow_style.shadow_color = Color(NeonTheme.PURPLE, 0.0)
	_glow_style.shadow_size = 9   # a slim halo (was 22)
	_glow.add_theme_stylebox_override("panel", _glow_style)
	add_child(_glow)
	move_child(_glow, 0)

	_frame = Panel.new()
	_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame_style = StyleBoxFlat.new()
	_frame_style.bg_color = Color(0, 0, 0, 0)
	_frame_style.set_corner_radius_all(14)
	_frame_style.set_border_width_all(4)
	_frame_style.border_color = Color(NeonTheme.PURPLE, 0.0)
	_frame.add_theme_stylebox_override("panel", _frame_style)
	add_child(_frame)

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

func _to_string():
	return nice_name

func update_display():
	front_face.set_visible(not is_facedown)
	back_face.set_visible(is_facedown)

func set_back_face(path:String):
	back_face_path = path
	if path != "":
		back_face.texture = load(path)

func set_front_face(path:String):
	image_path = path
	if path != "":
		front_face.texture = load(path)

func flip():
	is_facedown = !is_facedown
	update_display()

## Animated flip: squash X to 0, swap faces at the edge-on moment, expand back.
## Awaitable. A small Y lift sells the "card turning in the air".
func flip_animated(duration: float = 0.32, rest_scale: float = 1.0) -> void:
	var half := duration * 0.5
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2(0.0, 1.12 * rest_scale), half).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(flip)
	tw.tween_property(self, "scale", Vector2(rest_scale, rest_scale), half).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tw.finished

## A thin outline with no halo, for cards in a heap (the deck), so each card's edge shows.
func set_outline(border_width: int, halo: int) -> void:
	if _frame_style == null:
		return
	_frame_style.set_border_width_all(border_width)
	_glow_style.shadow_size = halo

## Light the neon frame. Pass alpha 0 to turn it off.
func glow(color: Color, duration: float = 0.2) -> void:
	if _frame_style == null:
		return
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_frame_style, "border_color", Color(color, 1.0), duration)
	tw.tween_property(_glow_style, "shadow_color", Color(color, 0.85), duration)
