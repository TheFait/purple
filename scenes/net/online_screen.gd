extends CanvasLayer
class_name OnlineScreen
## Base for the online screens (menu, lobby): a neon panel in the middle of the vaporwave
## backdrop, plus small builders so each screen only describes what is on it.

const SCENE_START := "res://scenes/start_screen.tscn"
const SCENE_MENU := "res://scenes/online_menu.tscn"
const SCENE_LOBBY := "res://scenes/lobby.tscn"
const SCENE_GAME := "res://scenes/online_game.tscn"

## A message the next screen should show (for example why the connection was lost).
static var flash_message: String = ""

var _status: Label

## A centred panel with a title; returns the box to put the screen's controls in.
func build_panel(title_text: String, width: float = 620.0) -> VBoxContainer:
	var holder := CenterContainer.new()
	holder.theme = NeonTheme.build()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(holder)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = width
	panel.add_theme_stylebox_override("panel", NeonTheme.panel_style(NeonTheme.PURPLE, Color(NeonTheme.INK, 0.88), 26, 3, 16))
	holder.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	margin.add_child(box)
	box.add_child(make_label(title_text, 40, NeonTheme.PINK, NeonTheme.FONT_HEAD, true))
	return box

func make_label(text: String, size: int, color: Color, font: Font = null, centered: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font if font != null else NeonTheme.FONT_BODY)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if centered:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

func make_button(text: String, accent: Color, height: float = 58.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = height
	NeonTheme.accent_button(b, accent)
	b.add_theme_font_size_override("font_size", 26)
	return b

func make_field(placeholder: String, text: String = "", max_length: int = 0) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.text = text
	e.max_length = max_length
	e.alignment = HORIZONTAL_ALIGNMENT_CENTER
	e.custom_minimum_size.y = 50.0
	e.add_theme_font_size_override("font_size", 24)
	return e

## The line of text under the controls that says what is happening or what went wrong.
func add_status(box: VBoxContainer) -> void:
	_status = make_label("", 22, NeonTheme.TEXT, null, true)
	box.add_child(_status)

func set_status(text: String, color: Color = NeonTheme.TEXT) -> void:
	if _status == null:
		return
	_status.text = text
	_status.add_theme_color_override("font_color", color)

func go(path: String) -> void:
	get_tree().change_scene_to_file(path)

## Where a room's state sends you: the lobby while gathering, the table once it is dealt.
func scene_for(info: Dictionary) -> String:
	return SCENE_GAME if info.get("state", "lobby") == "playing" else SCENE_LOBBY
