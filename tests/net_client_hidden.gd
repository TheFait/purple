extends SceneTree
## Plays a few guesses on a real server and proves the server never showed this client a card
## before it was drawn. The test server wrote the whole deck, in draw order, when the game
## started. We then walk through every event batch the client received, in the order they
## arrived: a batch may only mention the cards drawn up to and including that batch (the
## first N of the dumped order). A card mentioned any earlier, in a snapshot, a log line or
## anywhere else, is a leak, even if it is drawn a moment later.

const DUMP := "user://pp_deck_dump.txt"

var _t := TestHelper.new()
var _elapsed := 0.0
var _started := false
var _my_seat := -1
var _last_try := -1.0
var _batches: Array = []
var _synced := false
var _moves := 0

func _process(delta: float) -> bool:
	var net = get_root().get_node("Net")
	if not _started:
		_started = true
		net.connected.connect(func(): net.join_room("auto", "Spy"))
		net.seated.connect(func(seat, _rn): _my_seat = seat)
		net.raw_batch.connect(func(batch): _batches.append(batch))
		net.start_client("127.0.0.1", net.DEFAULT_PORT)
		return false
	_elapsed += delta
	if _my_seat >= 0 and not _synced:
		_synced = true
		net.request_sync()   # a snapshot is another way cards could leak
	if _my_seat == 0 and _elapsed > 1.0 and _elapsed - _last_try > 0.3 and net.can_act() and _moves < 8:
		_last_try = _elapsed
		_moves += 1
		var moves: Array[int] = net.legal_moves()
		net.act_move(moves[_moves % moves.size()])   # a mix of every guess, Purple and Post included
	if _elapsed > 7.0:
		_check()
		return true
	return false

func _check() -> void:
	var dump := FileAccess.get_file_as_string(DUMP).split("\n", false)
	_t.eq(dump.size(), 52, "the server dumped a full 52 card deck")
	var drawn := 0              # cards drawn so far, counted from the "card" events
	var early: Array[String] = []   # cards mentioned before the batch that draws them
	var batches_checked := 0
	for batch: Array in _batches:
		for event: Array in batch:
			if event[0] == "card":
				drawn += 1
		var text := JSON.stringify(batch)
		for i in range(drawn, dump.size()):
			if text.contains(dump[i]):
				early.append("%s (in batch %d, only %d drawn)" % [dump[i], batches_checked, drawn])
		batches_checked += 1
	_t.check(drawn >= 3, "the client saw several cards drawn (%d)" % drawn)
	_t.check(batches_checked >= 4, "and several batches arrived (%d)" % batches_checked)
	_t.eq(early, [], "no card is mentioned before the batch that draws it")
	# The check must be able to see cards at all: every drawn card was mentioned somewhere.
	var everything := JSON.stringify(_batches)
	var unseen: Array[String] = []
	for i in drawn:
		if not everything.contains(dump[i]):
			unseen.append(dump[i])
	_t.eq(unseen, [], "every drawn card did show up (the scan is not blind)")
	_t.finish()
