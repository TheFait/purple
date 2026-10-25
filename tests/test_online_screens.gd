extends SceneTree
## The online screens build and show the right things for a given room, with no server.

var _lobby: Node
var _menu: Node
var _frame := 0

func _initialize() -> void:
	var net = get_root().get_node("Net")
	net.room_info = {"room": "Ann's table", "code": "K7QX2", "public": false, "state": "lobby",
		"host": 0, "names": ["Ann", "Bea", "Cy"], "max": 12, "min": 2}
	net._my_seat = 0
	OnlineSettings.save_session("abc123", "10.0.0.5:9100")   # a game to rejoin, for the menu
	_lobby = load("res://scenes/lobby.tscn").instantiate()
	_menu = load("res://scenes/online_menu.tscn").instantiate()
	get_root().add_child(_lobby)
	get_root().add_child(_menu)

func _process(_d: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false
	var t := TestHelper.new()
	t.eq(_lobby._code_label.text, "K7QX2", "the lobby shows the invite code")
	t.check(_lobby._code_label.visible and _lobby._copy.visible, "a private room offers copying the code")
	t.eq(_lobby._roster.get_child_count(), 3, "one roster line per player")
	t.check(_lobby._start.visible and not _lobby._start.disabled, "the host can start with enough players")
	t.check(not _lobby._wait.visible, "the host is not told to wait")

	var net = get_root().get_node("Net")
	net._my_seat = 1
	_lobby._refresh(net.room_info)
	t.check(not _lobby._start.visible, "a guest has no start button")
	t.check(_lobby._wait.visible, "a guest is told to wait for the host")

	net._my_seat = 0
	_lobby._refresh({"room": "Open Table", "code": "", "public": true, "state": "lobby", "host": 0, "names": ["Ann"], "max": 12, "min": 2})
	t.check(not _lobby._code_label.visible and not _lobby._copy.visible, "a public room shows no code")
	t.check(_lobby._start.disabled, "the host cannot start alone")

	t.check(_menu._modes.size() == 4, "the menu has its four modes")
	t.check(_menu._modes["menu"].visible and not _menu._modes["host"].visible, "it opens on the main choices")
	_menu._show_mode("join")
	t.check(_menu._modes["join"].visible and not _menu._modes["menu"].visible, "modes swap")
	_menu._code_edit.text = "abcde"
	_menu._on_code_typed("abcde")
	t.eq(_menu._code_edit.text, "ABCDE", "typed codes are upper-cased")
	_menu._on_public_rooms([{"id": "room_1", "name": "Open Table", "count": 1, "max": 12, "state": "lobby"},
		{"id": "room_2", "name": "Late", "count": 3, "max": 12, "state": "playing"}])
	t.eq(_menu._rooms_box.get_child_count(), 2, "one button per public room")
	t.eq(OnlineSettings.parse_address("10.0.0.5:9100", 9000), ["10.0.0.5", 9100], "an address can carry a port")
	t.eq(OnlineSettings.parse_address("", 9000), ["127.0.0.1", 9000], "an empty address means this machine")

	# A game left behind by a closed app can be rejoined, but not forever.
	t.check(_menu._rejoin_button.visible, "the menu offers to rejoin a saved game")
	t.eq(OnlineSettings.load_session(), {"token": "abc123", "address": "10.0.0.5:9100"}, "the saved session is read back")
	var cfg := ConfigFile.new()
	cfg.load(OnlineSettings._path())
	cfg.set_value("session", "seen", Time.get_unix_time_from_system() - OnlineSettings.SESSION_MAX_AGE_SEC - 5)
	cfg.save(OnlineSettings._path())
	t.eq(OnlineSettings.load_session(), {}, "a session that is too old is ignored")
	OnlineSettings.save_session("fresh", "127.0.0.1")
	OnlineSettings.touch_session()
	t.eq(OnlineSettings.load_session().token, "fresh", "touching keeps a session alive")
	OnlineSettings.clear_session()
	t.check(not OnlineSettings.has_session(), "clearing removes it")
	t.finish()
	return true
