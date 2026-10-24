extends Node2D
## The online table's frame around the shared UI: a MENU button to leave (or, for the host,
## to end the game for everyone), and the way back out when the room or connection changes.

var _overlay: Control
var _end_button: Button

func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	var root := Control.new()
	root.theme = NeonTheme.build()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	var menu := Button.new()
	menu.text = "MENU"
	menu.size = Vector2(110, 46)
	menu.position = Vector2(720 - 110 - 14, 14)
	NeonTheme.accent_button(menu, NeonTheme.PURPLE)
	menu.add_theme_font_size_override("font_size", 20)
	menu.pressed.connect(func(): _overlay.visible = true)
	root.add_child(menu)

	_overlay = ColorRect.new()
	_overlay.color = Color(0.03, 0.0, 0.1, 0.8)
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.visible = false
	root.add_child(_overlay)
	var holder := CenterContainer.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(holder)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 460
	panel.add_theme_stylebox_override("panel", NeonTheme.panel_style(NeonTheme.PURPLE, Color(NeonTheme.INK, 0.95), 26, 3, 16))
	holder.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 26)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	margin.add_child(box)
	box.add_child(_choice("RESUME", NeonTheme.CYAN, func(): _overlay.visible = false))
	_end_button = _choice("END GAME FOR EVERYONE", NeonTheme.GOLD, func(): Net.request_end())
	box.add_child(_end_button)
	box.add_child(_choice("LEAVE GAME", NeonTheme.RED, func(): Net.leave_room()))

	Net.lobby_changed.connect(_on_lobby_changed)
	Net.left_room.connect(func(): get_tree().change_scene_to_file(OnlineScreen.SCENE_MENU))
	Net.connection_lost.connect(func():
		OnlineScreen.flash_message = "The connection to the server was lost."
		get_tree().change_scene_to_file(OnlineScreen.SCENE_MENU))
	_overlay.visibility_changed.connect(func(): _end_button.visible = Net.is_host())

func _choice(text: String, accent: Color, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = 56
	NeonTheme.accent_button(b, accent)
	b.add_theme_font_size_override("font_size", 22)
	b.pressed.connect(action)
	return b

## The host ended the game: everyone goes back to the lobby.
func _on_lobby_changed(info: Dictionary) -> void:
	if info.get("state", "") == "lobby":
		get_tree().change_scene_to_file(OnlineScreen.SCENE_LOBBY)
