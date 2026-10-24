extends CanvasLayer

const SETTINGS_PATH := "user://online.cfg"
const CONNECT_TIMEOUT := 6.0

var _address: LineEdit
var _online_button: Button
var _status: Label
var _connecting := false

func _ready():
	$ScreenCover.modulate = "00000000"
	var theme := NeonTheme.build()
	$Control3.theme = theme
	var title: Label = $Control2/Label
	title.add_theme_font_override("font", NeonTheme.FONT_DISPLAY)
	title.add_theme_font_size_override("font_size", 96)
	title.add_theme_color_override("font_color", NeonTheme.PINK)
	title.add_theme_color_override("font_shadow_color", Color(NeonTheme.PINK, 0.8))
	title.add_theme_constant_override("shadow_outline_size", 14)
	# The shine's scroll_speed matches the road's, so it sweeps once per grid line.
	var shine := ShaderMaterial.new()
	shine.shader = load("res://assets/shaders/logo_shine.gdshader")
	var road := $Background/Backdrop.material as ShaderMaterial
	shine.set_shader_parameter("scroll_speed", road.get_shader_parameter("scroll_speed"))
	title.material = shine
	var button: Button = $Control3/Button
	NeonTheme.accent_button(button, NeonTheme.PINK)
	button.add_theme_font_size_override("font_size", 34)
	_build_online_controls()


func _on_button_pressed():
	$AnimationPlayer.play("fade_to_black")
	await $AnimationPlayer.animation_finished
	LevelTransition.change_scene("res://scenes/game.tscn")


# --- online play -----------------------------------------------------------
# A temporary way in until the lobby exists: connect to a server and join its public room.

func _build_online_controls() -> void:
	var box := VBoxContainer.new()
	box.theme = NeonTheme.build()
	box.anchor_left = 0.2
	box.anchor_right = 0.8
	box.anchor_top = 0.885
	box.anchor_bottom = 0.985
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	move_child(box, $ScreenCover.get_index())   # keep the fade-to-black cover on top

	_address = LineEdit.new()
	_address.placeholder_text = "server address"
	_address.text = _load_address()
	_address.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_address.custom_minimum_size.y = 40.0
	box.add_child(_address)

	_online_button = Button.new()
	_online_button.text = "PLAY ONLINE"
	_online_button.custom_minimum_size.y = 50.0
	NeonTheme.accent_button(_online_button, NeonTheme.CYAN)
	_online_button.add_theme_font_size_override("font_size", 26)
	_online_button.pressed.connect(_on_online_pressed)
	box.add_child(_online_button)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_override("font", NeonTheme.FONT_BODY)
	_status.add_theme_font_size_override("font_size", 20)
	box.add_child(_status)

func _on_online_pressed() -> void:
	if _connecting:
		return
	var host := _address.text.strip_edges()
	var port := Net.DEFAULT_PORT
	if host.count(":") == 1:
		var parts := host.split(":")
		host = parts[0]
		port = int(parts[1]) if parts[1].is_valid_int() else Net.DEFAULT_PORT
	if host.is_empty():
		host = "127.0.0.1"
	_connecting = true
	_online_button.disabled = true
	_set_status("Connecting...", NeonTheme.TEXT)
	_listen(true)
	if not Net.start_client(host, port):
		return   # connect_failed already fired
	get_tree().create_timer(CONNECT_TIMEOUT).timeout.connect(_on_connect_timeout)

func _on_connect_timeout() -> void:
	if _connecting:
		_fail("Could not reach the server.")

func _on_net_connected() -> void:
	_set_status("Joining the table...", NeonTheme.TEXT)
	Net.join_room("auto", "Player")

func _on_net_connect_failed() -> void:
	_fail("Could not reach the server.")

func _on_join_failed(reason: String) -> void:
	_fail("Could not join: %s" % reason)

func _on_seated(_seat: int, _room_name: String) -> void:
	_listen(false)
	_save_address(_address.text.strip_edges())
	$AnimationPlayer.play("fade_to_black")
	await $AnimationPlayer.animation_finished
	LevelTransition.change_scene("res://scenes/online_game.tscn")

func _fail(message: String) -> void:
	_listen(false)
	Net.stop_client()
	_connecting = false
	_online_button.disabled = false
	_set_status(message, NeonTheme.RED)

func _set_status(text: String, color: Color) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", color)

## Listen to (or stop listening to) the connection events of the attempt in progress.
func _listen(on: bool) -> void:
	var pairs: Array[Array] = [[Net.connected, _on_net_connected], [Net.connect_failed, _on_net_connect_failed],
		[Net.join_failed, _on_join_failed], [Net.seated, _on_seated]]
	for pair: Array in pairs:
		var sig: Signal = pair[0]
		var handler: Callable = pair[1]
		if on and not sig.is_connected(handler):
			sig.connect(handler)
		elif not on and sig.is_connected(handler):
			sig.disconnect(handler)

func _load_address() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		return String(cfg.get_value("online", "address", "127.0.0.1"))
	return "127.0.0.1"

func _save_address(address: String) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("online", "address", address)
	cfg.save(SETTINGS_PATH)
