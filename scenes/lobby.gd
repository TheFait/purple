extends OnlineScreen
## The waiting room: the invite code to share, who is here, and (for the host) the Start button.

const BEST_WITH := 4   # the rules are best with four or more

var _title: Label
var _code_label: Label
var _hint: Label
var _roster: VBoxContainer
var _count: Label
var _start: Button
var _wait: Label
var _copy: Button

func _ready() -> void:
	var info: Dictionary = Net.room_info
	if info.is_empty():
		go(SCENE_MENU)
		return
	var box := build_panel(info.room)
	_title = box.get_child(0)
	_code_label = make_label("", 64, NeonTheme.GOLD, NeonTheme.FONT_HEAD, true)
	_hint = make_label("", 18, Color(NeonTheme.TEXT, 0.7), null, true)
	box.add_child(_hint)
	box.add_child(_code_label)
	_copy = make_button("COPY CODE", NeonTheme.CYAN, 50.0)
	_copy.pressed.connect(_copy_code)
	box.add_child(_copy)
	_roster = VBoxContainer.new()
	_roster.add_theme_constant_override("separation", 6)
	box.add_child(_roster)
	_count = make_label("", 20, Color(NeonTheme.TEXT, 0.7), null, true)
	box.add_child(_count)
	_start = make_button("START GAME", NeonTheme.PINK)
	_start.pressed.connect(func(): Net.request_start())
	box.add_child(_start)
	_wait = make_label("Waiting for the host to start...", 22, NeonTheme.TEXT, null, true)
	box.add_child(_wait)
	var leave := make_button("LEAVE", NeonTheme.PURPLE)
	leave.pressed.connect(func(): Net.leave_room())
	box.add_child(leave)
	add_status(box)

	Net.lobby_changed.connect(_refresh)
	Net.seated.connect(func(_seat: int, _room: String): _refresh(Net.room_info))
	Net.left_room.connect(func(): go(SCENE_MENU))
	Net.connection_lost.connect(_on_connection_lost)
	Net.notice.connect(func(text: String): set_status(text, NeonTheme.GOLD))
	_refresh(info)

func _refresh(info: Dictionary) -> void:
	if info.get("state", "lobby") == "playing":
		go(SCENE_GAME)
		return
	_title.text = info.room
	var code: String = info.get("code", "")
	_code_label.visible = not code.is_empty()
	_code_label.text = code
	_copy.visible = not code.is_empty()
	_hint.text = "Share this code so friends can join:" if not code.is_empty() else "A public room: anyone can join it from the list."
	_fill_roster(info)
	var count: int = info.names.size()
	_count.text = "%d player%s  -  best with %d or more" % [count, "" if count == 1 else "s", BEST_WITH]
	var host := Net.is_host()
	_start.visible = host
	_start.disabled = count < int(info.min)
	_wait.visible = not host
	if host and count < int(info.min):
		set_status("Waiting for at least %d players." % int(info.min), Color(NeonTheme.TEXT, 0.7))
	else:
		set_status("")

func _fill_roster(info: Dictionary) -> void:
	for child in _roster.get_children():
		child.queue_free()
	var names: Array = info.names
	for seat in names.size():
		var color: Color = UI.SEAT_COLORS[seat % UI.SEAT_COLORS.size()]
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 12)
		var dot := make_label("●", 26, color)
		var who := String(names[seat])
		if seat == Net.local_seat():
			who += "  (you)"
		var name_label := make_label(who, 26, NeonTheme.TEXT)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(dot)
		line.add_child(name_label)
		if seat == int(info.get("host", -1)):
			var badge := make_label("HOST", 16, NeonTheme.GOLD, NeonTheme.FONT_HEAD)
			badge.autowrap_mode = TextServer.AUTOWRAP_OFF   # never wrap a one-word badge
			line.add_child(badge)
		_roster.add_child(line)

func _copy_code() -> void:
	DisplayServer.clipboard_set(_code_label.text)
	_copy.text = "COPIED!"
	await get_tree().create_timer(1.2).timeout
	if is_instance_valid(_copy):
		_copy.text = "COPY CODE"

func _on_connection_lost() -> void:
	OnlineScreen.flash_message = "The connection to the server was lost."
	go(SCENE_MENU)
