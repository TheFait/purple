extends Control
class_name GuessIcon
## Chevron glyphs for the guess buttons that have no letter: Higher, Lower, Inside
## (> <) and Outside (< >). Drawn in code so they take the button's own neon colour.

enum Kind { HIGHER, LOWER, INSIDE, OUTSIDE }

const ARM := 17.0     # half-height of a chevron
const DEPTH := 13.0   # how far a chevron's tip sits from its arms
const WIDTH := 7.0

var kind: Kind = Kind.HIGHER
var _button: Button
var _last_color := Color.TRANSPARENT

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_button = get_parent() as Button

func _process(_delta: float) -> void:
	if _icon_color() != _last_color:
		queue_redraw()

func _icon_color() -> Color:
	if _button == null:
		return Color.WHITE
	if _button.disabled:
		return _button.get_theme_color("font_disabled_color")
	if _button.is_hovered() or _button.button_pressed:
		return _button.get_theme_color("font_hover_color")
	return _button.get_theme_color("font_color")

func _draw() -> void:
	_last_color = _icon_color()
	var c := size * 0.5
	match kind:
		Kind.HIGHER:
			_chevron(c + Vector2(0, -DEPTH * 0.5), Vector2.UP)
		Kind.LOWER:
			_chevron(c + Vector2(0, DEPTH * 0.5), Vector2.DOWN)
		Kind.INSIDE:   # > <  tips face each other
			_chevron(c + Vector2(-4, 0), Vector2.RIGHT)
			_chevron(c + Vector2(4, 0), Vector2.LEFT)
		Kind.OUTSIDE:  # < >  tips face away
			_chevron(c + Vector2(-20, 0), Vector2.LEFT)
			_chevron(c + Vector2(20, 0), Vector2.RIGHT)

## A "V" whose tip sits at `tip` and points along `dir`.
func _chevron(tip: Vector2, dir: Vector2) -> void:
	var back := -dir * DEPTH
	var side := dir.orthogonal() * ARM
	draw_polyline(PackedVector2Array([tip + back + side, tip, tip + back - side]), _last_color, WIDTH, true)
