extends OnlineScreen
## Where online play starts: say who you are and where the server is, then host a game,
## join one with an invite code, or pick a public room. Connecting happens on demand.

const CONNECT_TIMEOUT := 6.0

var _name_edit: LineEdit
var _address_edit: LineEdit
var _code_edit: LineEdit
var _public_check: CheckButton
var _rooms_box: VBoxContainer
var _rejoin_button: Button
var _modes: Dictionary = {}          # mode name -> the controls shown in that mode
var _buttons: Array[Button] = []     # disabled while a connection attempt is running
var _connecting := false
var _after_connect: Callable

func _ready() -> void:
	var box := build_panel("PLAY ONLINE")
	_name_edit = make_field("your name", OnlineSettings.load_name(), Room.NAME_MAX)
	_address_edit = make_field("server address", OnlineSettings.load_address())
	box.add_child(make_label("YOUR NAME", 16, Color(NeonTheme.TEXT, 0.65), NeonTheme.FONT_HEAD))
	box.add_child(_name_edit)
	box.add_child(make_label("SERVER", 16, Color(NeonTheme.TEXT, 0.65), NeonTheme.FONT_HEAD))
	box.add_child(_address_edit)

	_build_menu_mode(box)
	_build_host_mode(box)
	_build_join_mode(box)
	_build_public_mode(box)
	add_status(box)
	_show_mode("menu")

	Net.session_expired.connect(_on_session_expired)
	Net.lobby_changed.connect(_on_lobby_changed)
	Net.join_failed.connect(_on_join_failed)
	Net.public_rooms.connect(_on_public_rooms)
	Net.connect_failed.connect(_on_connect_failed)
	Net.connected.connect(_on_connected)
	if not flash_message.is_empty():
		set_status(flash_message, NeonTheme.GOLD)
		flash_message = ""

# --- modes -------------------------------------------------------------------

func _build_menu_mode(box: VBoxContainer) -> void:
	var m := VBoxContainer.new()
	m.add_theme_constant_override("separation", 12)
	# A game that was running when the app last closed can be rejoined while its seat is held.
	_rejoin_button = _button("REJOIN YOUR GAME", NeonTheme.GOLD, _rejoin)
	_rejoin_button.visible = OnlineSettings.has_session()
	m.add_child(_rejoin_button)
	m.add_child(_button("HOST A GAME", NeonTheme.PINK, _show_mode.bind("host")))
	m.add_child(_button("JOIN WITH CODE", NeonTheme.CYAN, _show_mode.bind("join")))
	m.add_child(_button("PUBLIC ROOMS", NeonTheme.GREEN, _open_public))
	m.add_child(_button("BACK", NeonTheme.PURPLE, _back_to_start))
	box.add_child(m)
	_modes["menu"] = m

func _build_host_mode(box: VBoxContainer) -> void:
	var m := VBoxContainer.new()
	m.add_theme_constant_override("separation", 12)
	_public_check = CheckButton.new()
	_public_check.text = "Public room (listed for everyone)"
	_public_check.add_theme_font_override("font", NeonTheme.FONT_BODY)
	_public_check.add_theme_font_size_override("font_size", 22)
	m.add_child(_public_check)
	m.add_child(make_label("Private rooms get an invite code to share.", 18, Color(NeonTheme.TEXT, 0.65), null, true))
	m.add_child(_button("CREATE TABLE", NeonTheme.PINK, _create_room))
	m.add_child(_button("BACK", NeonTheme.PURPLE, _show_mode.bind("menu")))
	box.add_child(m)
	_modes["host"] = m

func _build_join_mode(box: VBoxContainer) -> void:
	var m := VBoxContainer.new()
	m.add_theme_constant_override("separation", 12)
	m.add_child(make_label("INVITE CODE", 16, Color(NeonTheme.TEXT, 0.65), NeonTheme.FONT_HEAD))
	_code_edit = make_field("ABCDE", "", 5)
	_code_edit.add_theme_font_size_override("font_size", 40)
	_code_edit.text_changed.connect(_on_code_typed)
	_code_edit.text_submitted.connect(func(_t: String): _join_with_code())
	m.add_child(_code_edit)
	m.add_child(_button("JOIN", NeonTheme.CYAN, _join_with_code))
	m.add_child(_button("BACK", NeonTheme.PURPLE, _show_mode.bind("menu")))
	box.add_child(m)
	_modes["join"] = m

func _build_public_mode(box: VBoxContainer) -> void:
	var m := VBoxContainer.new()
	m.add_theme_constant_override("separation", 12)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 260.0
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_rooms_box = VBoxContainer.new()
	_rooms_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rooms_box.add_theme_constant_override("separation", 8)
	scroll.add_child(_rooms_box)
	m.add_child(scroll)
	m.add_child(_button("REFRESH", NeonTheme.GREEN, _open_public))
	m.add_child(_button("BACK", NeonTheme.PURPLE, _show_mode.bind("menu")))
	box.add_child(m)
	_modes["public"] = m

func _button(text: String, accent: Color, action: Callable) -> Button:
	var b := make_button(text, accent)
	b.pressed.connect(action)
	_buttons.append(b)
	return b

func _show_mode(mode: String) -> void:
	for key: String in _modes:
		_modes[key].visible = (key == mode)
	set_status("")
	if mode == "join":
		_code_edit.grab_focus()

# --- actions -----------------------------------------------------------------

func _create_room() -> void:
	var player := _clean_name()
	var is_public := _public_check.button_pressed
	_run_online(func(): Net.create_room("", is_public, player))

func _join_with_code() -> void:
	var code := _code_edit.text.strip_edges()
	if code.length() < 5:
		set_status("Codes have five characters.", NeonTheme.RED)
		return
	var player := _clean_name()
	_run_online(func(): Net.join_room(code, player))

func _open_public() -> void:
	_show_mode("public")
	_run_online(func(): Net.list_public_rooms())

func _join_public(room_id: String) -> void:
	var player := _clean_name()
	_run_online(func(): Net.join_room(room_id, player))

func _rejoin() -> void:
	_set_busy(true)
	set_status("Rejoining your game...")
	if not Net.resume_saved():
		_set_busy(false)
		_rejoin_button.visible = false
		set_status("There is no game to rejoin.", NeonTheme.RED)

func _on_session_expired() -> void:
	_set_busy(false)
	_rejoin_button.visible = false
	set_status("That game has moved on without you.", NeonTheme.GOLD)

func _back_to_start() -> void:
	Net.stop_client()
	go(SCENE_START)

func _on_code_typed(text: String) -> void:
	var upper := text.to_upper()
	if upper != text:
		_code_edit.text = upper
		_code_edit.caret_column = upper.length()

func _clean_name() -> String:
	var player := Room.clean_text(_name_edit.text).left(Room.NAME_MAX).strip_edges()
	return player if not player.is_empty() else "Player"

# --- connecting --------------------------------------------------------------

## Run `action` once there is a connection, connecting first if needed.
func _run_online(action: Callable) -> void:
	var address := OnlineSettings.parse_address(_address_edit.text, Net.DEFAULT_PORT)
	OnlineSettings.save(_name_edit.text.strip_edges(), _address_edit.text.strip_edges())
	if Net.is_online():
		action.call()
		return
	if _connecting:
		return
	_connecting = true
	_after_connect = action
	_set_busy(true)
	set_status("Connecting...")
	if not Net.start_client(address[0], address[1]):
		return   # connect_failed already fired
	get_tree().create_timer(CONNECT_TIMEOUT).timeout.connect(_on_connect_timeout)

func _on_connected() -> void:
	if not _connecting:
		return
	_connecting = false
	_set_busy(false)
	set_status("")
	if _after_connect.is_valid():
		_after_connect.call()

func _on_connect_failed() -> void:
	_connection_failed("Could not reach the server.")

func _on_connect_timeout() -> void:
	if _connecting:
		_connection_failed("Could not reach the server.")

func _connection_failed(message: String) -> void:
	Net.stop_client()
	_connecting = false
	_set_busy(false)
	set_status(message, NeonTheme.RED)

func _set_busy(busy: bool) -> void:
	for b in _buttons:
		b.disabled = busy

# --- the server's answers ----------------------------------------------------

func _on_lobby_changed(info: Dictionary) -> void:
	go(scene_for(info))

func _on_join_failed(reason: String) -> void:
	set_status("Could not join: %s." % reason, NeonTheme.RED)

func _on_public_rooms(list: Array) -> void:
	for child in _rooms_box.get_children():
		child.queue_free()
	if list.is_empty():
		_rooms_box.add_child(make_label("No public rooms right now. Host one!", 20, Color(NeonTheme.TEXT, 0.7), null, true))
		return
	for entry: Dictionary in list:
		var label := "%s   %d/%d%s" % [entry.name, entry.count, entry.max, "   (in game)" if entry.state == "playing" else ""]
		var b := _button(label, NeonTheme.GREEN, _join_public.bind(entry.id))
		b.add_theme_font_size_override("font_size", 22)
		_rooms_box.add_child(b)
