extends Node2D
## The online table's frame around the shared UI: a MENU button to leave (or, for the host,
## to end the game for everyone), and the way back out when the room or connection changes.

var _overlay: Control
var _end_button: Button
var _recon: Control            # shown to a player whose connection dropped
var _recon_title: Label
var _recon_time: Label
var _recon_button: Button

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

	_build_reconnect_screen(root)
	Net.reconnecting.connect(_on_reconnecting)
	Net.resumed.connect(func(): _recon.visible = false)
	Net.session_expired.connect(_on_session_expired)
	Net.lobby_changed.connect(_on_lobby_changed)
	Net.left_room.connect(func(): get_tree().change_scene_to_file(OnlineScreen.SCENE_MENU))
	Net.connection_lost.connect(func():
		OnlineScreen.flash_message = "The connection to the server was lost."
		get_tree().change_scene_to_file(OnlineScreen.SCENE_MENU))
	_overlay.visibility_changed.connect(func(): _end_button.visible = Net.is_host())

## Shown over everything while this client is getting its seat back after a dropped connection.
func _build_reconnect_screen(root: Control) -> void:
	var cover := ColorRect.new()
	cover.color = Color(0.03, 0.0, 0.1, 0.88)
	cover.set_anchors_preset(Control.PRESET_FULL_RECT)
	cover.visible = false
	root.add_child(cover)
	_recon = cover
	var holder := CenterContainer.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	cover.add_child(holder)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	holder.add_child(box)
	_recon_title = _label("RECONNECTING...", 48, NeonTheme.GOLD, NeonTheme.FONT_HEAD)
	_recon_time = _label("", 30, NeonTheme.TEXT, NeonTheme.FONT_BODY)
	box.add_child(_recon_title)
	box.add_child(_recon_time)
	_recon_button = _choice("BACK TO MENU", NeonTheme.PURPLE, func():
		Net.stop_client()
		get_tree().change_scene_to_file(OnlineScreen.SCENE_MENU))
	_recon_button.visible = false
	box.add_child(_recon_button)

func _label(text: String, size: int, color: Color, font: Font) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

func _on_reconnecting(seconds_left: int) -> void:
	_overlay.visible = false
	_recon.visible = true
	_recon_title.text = "RECONNECTING..."
	_recon_time.text = "%d:%02d left to get your seat back" % [seconds_left / 60, seconds_left % 60]
	_recon_button.visible = false

func _on_session_expired() -> void:
	_recon.visible = true
	_recon_title.text = "YOU WERE REMOVED"
	_recon_time.text = "The table moved on without you."
	_recon_button.visible = true

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
