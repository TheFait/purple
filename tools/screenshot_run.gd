extends SceneTree
## Dev tool (needs a window, not --headless): autoplays the offline game and saves PNGs
## at key moments (idle, suspense, win, pass panel, loss).
##   godot --path . --script res://tools/screenshot_run.gd -- <out_dir> [seed] [max_seconds]

var _game: Node
var _ui: Node
var _out := "user://shots"
var _t := 0.0
var _max := 40.0
var _taken := {}
var _pending: Array = []   # [time_left, name]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	seed(int(args[1]) if args.size() > 1 else 3)
	if args.size() > 2:
		_max = float(args[2])
	DirAccess.make_dir_recursive_absolute(_out)
	root.size = Vector2i(720, 1280)
	_game = load("res://scenes/game.tscn").instantiate()
	root.add_child(_game)
	_ui = _game.get_node("UI")
	_game.streak_changed.connect(func(s: int): if s > 0: _later("win_streak%d" % s, 0.9))
	_game.penalty_triggered.connect(func(_s, _a): _later("loss", 1.2))

func _later(name: String, delay: float) -> void:
	# Event signals fire in one burst; the UI plays them out over time, so delay the shot.
	if not _taken.has(name):
		_pending.append([delay + _ui._queue.size() * 0.5, name])

func _shot(name: String) -> void:
	if _taken.has(name):
		return
	_taken[name] = true
	root.get_texture().get_image().save_png("%s/%s.png" % [_out, name])
	print("shot ", name)

func _process(delta: float) -> bool:
	_t += delta
	if _t > 1.2 and not _taken.has("idle"):
		_shot("idle")
	for p in _pending.duplicate():
		p[0] -= delta
		if p[0] <= 0.0:
			_pending.erase(p)
			_shot(p[1])
	if _ui.pass_panel.visible and not _taken.has("pass_panel") and not _ui._busy():
		_later("pass_panel", 0.7)
		_taken["pass_panel_queued"] = true
	if _t > 1.3 and not _ui._busy() and not _taken.has("pass_panel_queued"):
		var moves: Array[int] = _game.legal_moves()
		_game.act_move(moves[randi() % moves.size()])
	if _t > _max:
		quit()
	return false
