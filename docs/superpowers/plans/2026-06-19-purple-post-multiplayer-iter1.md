# Purple & Post — Authoritative Multiplayer (Iteration 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split the verified Purple & Post rules out of the visual layer into a pure `GameEngine`, run it on a dedicated authoritative ENet server with a room/seat model (≤12 seats), and prove a local 2-client slice plays turns correctly — while keeping a fun offline single-device mode.

**Architecture:** A pure-data rules core (`CardData` + `DeckEngine` + `GameEngine`) runs identically on the server (authoritative), in offline mode, and in tests. Clients are thin views: they send move *intents* and render revealed `CardData`. Networking is one shared `Net` autoload (so RPC node paths match on both ends) that branches on `multiplayer.is_server()`.

**Tech Stack:** Godot 4.6 (GDScript, static typing), `ENetMultiplayerPeer`, Godot high-level multiplayer (RPC).

## Global Constraints

- Engine: **Godot 4.6**, GDScript with **static typing** throughout.
- Transport: **ENet only** (`ENetMultiplayerPeer`). No web/WebSocket in this iteration.
- Max seats per room: **12**.
- Rank encoding (existing JSON, do not change): `2..14`, **J=11, Q=12, K=13, A=14**.
- Suit values come from the existing `Globals.SUITS` enum: `HEARTS=0, SPADES=1, DIAMONDS=2, CLUBS=3`. Red = HEARTS/DIAMONDS; Black = SPADES/CLUBS.
- **Anti-cheat invariant:** the undrawn deck and its order are NEVER serialized to clients. Only revealed cards cross the wire.
- Penalty rule (resolved in spec): drawn card(s) count toward the pool; `count_drawn_card_in_penalty = true` default. Accidental Post (Hi/Lo tie) and failed intentional Post both pay **×2**.
- Card data source: `res://assets/database/card_database.json` (card info) + `res://assets/database/card_collection.json` (names in the deck).
- Test command convention: `godot --headless --path . --script res://tests/<name>.gd`; a passing test prints a final line `RESULT: PASS`.
- Commit after every task. Branch is `ultra` (already a feature branch — commit directly, do not branch again).

---

## File Structure

**New**
- `tests/test_helper.gd` — tiny assert helper (`OK`/`FAIL` counters, `finish()` prints `RESULT:`).
- `scenes/cards/card_data.gd` — `CardData` (RefCounted), the network unit.
- `scenes/engine/deck_engine.gd` — `DeckEngine` (RefCounted): JSON→`CardData`, shuffle/draw/discard/recycle.
- `scenes/engine/game_engine.gd` — `GameEngine` (Node): the ported rules, seat-aware, authority-gated.
- `scenes/net/net.gd` — `Net` autoload: ENet start, room RPCs, game RPCs, branches on `is_server()`.
- `server/room.gd` — `Room`/`Seat` data + per-room `GameEngine`.
- `server/room_manager.gd` — `RoomManager`: create/join/leave/list, 12-seat cap.
- `server/server.tscn` + `server/server_main.gd` — headless server entry (`Net.start_server`).
- `tests/test_card_data.gd`, `tests/test_deck_engine.gd`, `tests/test_game_engine.gd`, `tests/test_room_manager.gd` — unit harnesses.
- `tests/net_server_boot.gd`, `tests/net_client_probe.gd` — integration harness scripts.
- `tests/run_net_integration.sh` — orchestrates server + 2 clients.

**Changed**
- `scenes/game_manager.gd` — becomes the **offline presenter**: owns a `GameEngine`, forwards its signals, exposes `act_move/act_pass/act_ride/can_act`.
- `scenes/ui.gd` — binds to a generic `presenter` (offline `GameManager` or online `Net`); renders `card_revealed`/`table_cleared`.
- `project.godot` — register `Net` autoload.

**Interface contract shared by both presenters (offline `GameManager` and online `Net`):**
Signals: `card_revealed(card: CardData)`, `table_cleared()`, `streak_changed(streak: int)`, `pool_changed(pool: int)`, `penalty_triggered(seat: int, amount: int)`, `pass_available(is_available: bool)`, `turn_changed(seat: int)`, `round_log(text: String)`.
Methods: `act_move(move: int) -> void`, `act_pass() -> void`, `act_ride() -> void`, `can_act() -> bool`, `local_seat() -> int`.

---

## Task 1: Test helper + `CardData`

**Files:**
- Create: `tests/test_helper.gd`
- Create: `scenes/cards/card_data.gd`
- Test: `tests/test_card_data.gd`

**Interfaces:**
- Produces: `CardData` with `rank:int`, `suit:int`, `nice_name:String`, `texture_path:String`, `backface_path:String`; `is_red()->bool`, `is_black()->bool`, `to_dict()->Dictionary`, `static from_dict(d)->CardData`, `_to_string()->String`. Test helper `TestHelper.new()` with `.check(cond, msg)` and `.finish()`.

- [ ] **Step 1: Write the test helper**

Create `tests/test_helper.gd`:
```gdscript
extends RefCounted
class_name TestHelper
## Minimal assert helper for headless SceneTree tests.

var _passed := 0
var _failed := 0

func check(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
		print("OK: ", message)
	else:
		_failed += 1
		print("FAIL: ", message)

func eq(actual, expected, message: String) -> void:
	check(actual == expected, "%s (got %s, expected %s)" % [message, actual, expected])

func finish() -> void:
	print("RESULT: %s  (%d passed, %d failed)" % ["PASS" if _failed == 0 else "FAIL", _passed, _failed])
```

- [ ] **Step 2: Write the failing test**

Create `tests/test_card_data.gd`:
```gdscript
extends SceneTree

func _initialize() -> void:
	var t := TestHelper.new()
	var c := CardData.new(14, Globals.SUITS.HEARTS, "Ace of Hearts", "res://a.png", "res://b.png")
	t.eq(c.rank, 14, "rank stored")
	t.check(c.is_red(), "hearts is red")
	t.check(not c.is_black(), "hearts is not black")
	var spade := CardData.new(7, Globals.SUITS.SPADES, "7 of Spades", "", "")
	t.check(spade.is_black(), "spades is black")
	var round_trip := CardData.from_dict(c.to_dict())
	t.eq(round_trip.rank, 14, "round-trip rank")
	t.eq(round_trip.suit, Globals.SUITS.HEARTS, "round-trip suit")
	t.eq(round_trip.nice_name, "Ace of Hearts", "round-trip name")
	t.finish()
	quit()
```

- [ ] **Step 3: Run test to verify it fails**

Run: `godot --headless --path . --script res://tests/test_card_data.gd`
Expected: parse error / `Could not find type "CardData"` (the class does not exist yet).

- [ ] **Step 4: Implement `CardData`**

Create `scenes/cards/card_data.gd`:
```gdscript
extends RefCounted
class_name CardData
## Network-serializable card. The rules read only rank/suit; the client maps
## this to a visual Card (Control) for display. Never holds a scene node.

var rank: int = 0          # 2..14 (J=11, Q=12, K=13, A=14)
var suit: int = 0          # Globals.SUITS
var nice_name: String = ""
var texture_path: String = ""
var backface_path: String = ""

func _init(p_rank: int = 0, p_suit: int = 0, p_nice: String = "", p_tex: String = "", p_back: String = "") -> void:
	rank = p_rank
	suit = p_suit
	nice_name = p_nice
	texture_path = p_tex
	backface_path = p_back

func is_red() -> bool:
	return suit == Globals.SUITS.HEARTS or suit == Globals.SUITS.DIAMONDS

func is_black() -> bool:
	return suit == Globals.SUITS.SPADES or suit == Globals.SUITS.CLUBS

func to_dict() -> Dictionary:
	return {"rank": rank, "suit": suit, "nice_name": nice_name, "texture_path": texture_path, "backface_path": backface_path}

static func from_dict(d: Dictionary) -> CardData:
	return CardData.new(int(d.get("rank", 0)), int(d.get("suit", 0)), String(d.get("nice_name", "")), String(d.get("texture_path", "")), String(d.get("backface_path", "")))

func _to_string() -> String:
	return nice_name
```

- [ ] **Step 5: Run test to verify it passes**

Run: `godot --headless --path . --script res://tests/test_card_data.gd`
Expected: output ends with `RESULT: PASS  (7 passed, 0 failed)`.

- [ ] **Step 6: Commit**

```bash
git add tests/test_helper.gd tests/test_card_data.gd scenes/cards/card_data.gd
git commit -m "feat(mp): add CardData network unit + test harness"
```

---

## Task 2: `DeckEngine`

**Files:**
- Create: `scenes/engine/deck_engine.gd`
- Test: `tests/test_deck_engine.gd`

**Interfaces:**
- Consumes: `CardData` (Task 1).
- Produces: `DeckEngine` with `load_from_json(database_path, collection_path) -> void`, `shuffle() -> void`, `deck_size() -> int`, `discard_size() -> int`, `draw() -> CardData` (null if truly empty), `discard(cards: Array) -> void`, `recycle() -> void`, `return_to_deck(cards: Array) -> void`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_deck_engine.gd`:
```gdscript
extends SceneTree

func _initialize() -> void:
	var t := TestHelper.new()
	var d := DeckEngine.new()
	d.load_from_json("res://assets/database/card_database.json", "res://assets/database/card_collection.json")
	t.eq(d.deck_size(), 52, "full deck loaded")

	var first := d.draw()
	t.check(first != null, "draw returns a card")
	t.eq(d.deck_size(), 51, "draw removes from deck")

	# Discard the drawn card, then recycle it back.
	d.discard([first])
	t.eq(d.discard_size(), 1, "discard holds the card")
	d.recycle()
	t.eq(d.discard_size(), 0, "recycle empties discard")
	t.eq(d.deck_size(), 52, "recycle returns card to deck")

	# Draw the whole deck; no duplicates by nice_name.
	var seen := {}
	var dupes := 0
	for i in range(52):
		var c := d.draw()
		if seen.has(c.nice_name):
			dupes += 1
		seen[c.nice_name] = true
	t.eq(dupes, 0, "no duplicate cards in a full draw")
	t.eq(d.draw(), null, "draw on empty deck returns null")
	t.finish()
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . --script res://tests/test_deck_engine.gd`
Expected: `Could not find type "DeckEngine"`.

- [ ] **Step 3: Implement `DeckEngine`**

Create `scenes/engine/deck_engine.gd`:
```gdscript
extends RefCounted
class_name DeckEngine
## Pure card storage + RNG. No scene nodes, no textures loaded. Server-safe.

var _deck: Array[CardData] = []
var _discard: Array[CardData] = []

func load_from_json(database_path: String, collection_path: String) -> void:
	_deck.clear()
	_discard.clear()
	var database: Array = _read_json_array(database_path)
	var collection: Array = _read_json_array(collection_path)
	for card_name in collection:
		var info := _find_by_name(database, String(card_name))
		if info.is_empty():
			push_warning("DeckEngine: no card data for %s" % card_name)
			continue
		_deck.append(CardData.new(
			int(info.get("rank", 0)),
			_suit_from_string(String(info.get("suit", ""))),
			String(info.get("nice_name", "")),
			String(info.get("texture_path", "")),
			String(info.get("backface_texture_path", ""))))
	shuffle()

func shuffle() -> void:
	_deck.shuffle()

func deck_size() -> int:
	return _deck.size()

func discard_size() -> int:
	return _discard.size()

func draw() -> CardData:
	if _deck.is_empty():
		recycle()
	if _deck.is_empty():
		return null
	return _deck.pop_back()

func discard(cards: Array) -> void:
	for c in cards:
		_discard.append(c)

func recycle() -> void:
	_deck.append_array(_discard)
	_discard.clear()
	shuffle()

func return_to_deck(cards: Array) -> void:
	for c in cards:
		_deck.append(c)
	shuffle()

func _read_json_array(path: String) -> Array:
	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	return parsed if parsed is Array else []

func _find_by_name(database: Array, card_name: String) -> Dictionary:
	for entry in database:
		if entry is Dictionary and String(entry.get("nice_name", "")) == card_name:
			return entry
	return {}

func _suit_from_string(s: String) -> int:
	match s.to_lower():
		"h", "hearts": return Globals.SUITS.HEARTS
		"s", "spades": return Globals.SUITS.SPADES
		"d", "diamonds": return Globals.SUITS.DIAMONDS
		"c", "clubs": return Globals.SUITS.CLUBS
	return Globals.SUITS.HEARTS
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless --path . --script res://tests/test_deck_engine.gd`
Expected: `RESULT: PASS  (8 passed, 0 failed)`.

- [ ] **Step 5: Commit**

```bash
git add scenes/engine/deck_engine.gd tests/test_deck_engine.gd
git commit -m "feat(mp): add pure DeckEngine (JSON load, shuffle, draw, recycle)"
```

---

## Task 3: `GameEngine` (rules port)

**Files:**
- Create: `scenes/engine/game_engine.gd`
- Test: `tests/test_game_engine.gd`

**Interfaces:**
- Consumes: `CardData` (Task 1), `DeckEngine` (Task 2).
- Produces: `GameEngine` (Node) with enum `Move { HIGHER, LOWER, RED, BLACK, PURPLE, POST }`; `setup(deck: DeckEngine, seats: int) -> void`; `submit_move(seat: int, move: int) -> bool`; `request_pass(seat: int) -> bool`; `request_ride(seat: int) -> bool`; `active_card() -> CardData`; `drink_pool() -> int`; properties `current_seat:int`, `current_streak:int`, `seat_count:int`, `count_drawn_card_in_penalty:bool`; signals `card_revealed(card)`, `table_cleared()`, `streak_changed(streak)`, `pool_changed(pool)`, `penalty_triggered(seat, amount)`, `pass_available(is_available)`, `turn_changed(seat)`, `round_log(text)`.

- [ ] **Step 1: Write the failing test (deterministic, seeded)**

Create `tests/test_game_engine.gd`:
```gdscript
extends SceneTree

func _initialize() -> void:
	var t := TestHelper.new()
	seed(12345)
	var deck := DeckEngine.new()
	deck.load_from_json("res://assets/database/card_database.json", "res://assets/database/card_collection.json")
	var engine := GameEngine.new()
	get_root().add_child(engine)  # Node, so it can emit signals in-tree
	engine.setup(deck, 2)

	# After setup there is exactly one active card and pool == 1.
	t.check(engine.active_card() != null, "active card seeded")
	t.eq(engine.drink_pool(), 1, "pool starts at 1")
	t.eq(engine.current_seat, 0, "starts on seat 0")

	# Authority: a move from the wrong seat is rejected (no state change).
	var pool_before := engine.drink_pool()
	t.check(not engine.submit_move(1, GameEngine.Move.HIGHER), "out-of-turn move rejected")
	t.eq(engine.drink_pool(), pool_before, "rejected move did not change state")

	# A move from the correct seat is accepted.
	t.check(engine.submit_move(0, GameEngine.Move.HIGHER), "in-turn move accepted")

	# Drive many moves; assert invariants never break.
	var penalties := {"n": 0}
	engine.penalty_triggered.connect(func(_s, _a): penalties.n += 1)
	for i in range(60):
		if engine.current_streak >= 3:
			# Resolve the pass gate so play can continue.
			engine.request_ride(engine.current_seat)
		var ok := engine.submit_move(engine.current_seat, (i % 6))
		t.check(engine.drink_pool() >= 1, "pool never below 1 (i=%d)" % i)
		t.check(engine.current_seat >= 0 and engine.current_seat < 2, "seat in range (i=%d)" % i)
	t.check(penalties.n > 0, "some penalties fired over 60 moves")
	t.finish()
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . --script res://tests/test_game_engine.gd`
Expected: `Could not find type "GameEngine"`.

- [ ] **Step 3: Implement `GameEngine` (logic ported verbatim from `game_manager.gd`, retyped onto `CardData`)**

Create `scenes/engine/game_engine.gd`:
```gdscript
extends Node
class_name GameEngine
## Authoritative "Purple & Post" rules. Pure data (CardData) — no visuals.
## Identical logic runs on the server, in offline mode, and in tests.

enum Move { HIGHER, LOWER, RED, BLACK, PURPLE, POST }

signal card_revealed(card: CardData)
signal table_cleared()
signal streak_changed(streak: int)
signal pool_changed(pool: int)
signal penalty_triggered(seat: int, amount: int)
signal pass_available(is_available: bool)
signal turn_changed(seat: int)
signal round_log(text: String)

var seat_count: int = 2
var streak_to_pass: int = 3
var count_drawn_card_in_penalty: bool = true

var table_cards: Array[CardData] = []
var current_streak: int = 0
var current_seat: int = 0

var _deck: DeckEngine
var _awaiting_pass: bool = false

func setup(deck: DeckEngine, seats: int) -> void:
	_deck = deck
	seat_count = max(1, seats)
	current_seat = 0
	current_streak = 0
	_awaiting_pass = false
	_seed_active_card()
	streak_changed.emit(current_streak)
	pass_available.emit(false)
	turn_changed.emit(current_seat)
	round_log.emit("Game start — seat %d's turn." % current_seat)

func active_card() -> CardData:
	return table_cards.back()

func drink_pool() -> int:
	return table_cards.size()

# --- authority-gated entry points (server passes the caller's seat) ---

func submit_move(seat: int, move: int) -> bool:
	if not _can_act(seat):
		return false
	var reference: CardData = active_card()
	var pool_before: int = table_cards.size()
	match move:
		Move.HIGHER:
			var c := _draw_one()
			if c.rank > reference.rank:
				_win(1, "Higher — %s beats %s" % [c, reference])
			elif c.rank == reference.rank:
				_lose(true, pool_before, "Accidental Post! %s ties %s" % [c, reference])
			else:
				_lose(false, pool_before, "Higher missed — %s under %s" % [c, reference])
		Move.LOWER:
			var c := _draw_one()
			if c.rank < reference.rank:
				_win(1, "Lower — %s under %s" % [c, reference])
			elif c.rank == reference.rank:
				_lose(true, pool_before, "Accidental Post! %s ties %s" % [c, reference])
			else:
				_lose(false, pool_before, "Lower missed — %s over %s" % [c, reference])
		Move.RED:
			var c := _draw_one()
			if c.is_red():
				_win(1, "Red — %s" % c)
			else:
				_lose(false, pool_before, "Red missed — %s is black" % c)
		Move.BLACK:
			var c := _draw_one()
			if c.is_black():
				_win(1, "Black — %s" % c)
			else:
				_lose(false, pool_before, "Black missed — %s is red" % c)
		Move.PURPLE:
			var first := _draw_one()
			var second := _draw_one()
			if first.is_red() != second.is_red():
				_win(2, "Purple! %s + %s split colors" % [first, second])
			else:
				_lose(false, pool_before, "Purple busted — %s + %s match color" % [first, second])
		Move.POST:
			var c := _draw_one()
			if c.rank == reference.rank:
				_win(1, "Post hit! %s matches %s" % [c, reference])
			else:
				_lose(true, pool_before, "Failed Post — %s misses %s" % [c, reference])
		_:
			return false
	return true

func request_pass(seat: int) -> bool:
	if not _awaiting_pass or seat != current_seat:
		return false
	round_log.emit("Seat %d passes the turn." % current_seat)
	_clear_table_and_reseed()
	_advance_seat()
	return true

func request_ride(seat: int) -> bool:
	if not _awaiting_pass or seat != current_seat:
		return false
	_awaiting_pass = false
	pass_available.emit(false)
	round_log.emit("Seat %d rides — pool now %d." % [current_seat, drink_pool()])
	return true

# --- internals ---

func _can_act(seat: int) -> bool:
	if _awaiting_pass:
		return false
	if seat != current_seat:
		return false
	if table_cards.is_empty():
		return false
	return true

func _win(streak_gain: int, reason: String) -> void:
	current_streak += streak_gain
	streak_changed.emit(current_streak)
	pool_changed.emit(drink_pool())
	round_log.emit("%s  (streak %d, pool %d)" % [reason, current_streak, drink_pool()])
	if current_streak >= streak_to_pass:
		_awaiting_pass = true
		pass_available.emit(true)
		round_log.emit("Streak %d — Pass to bank it, or Ride to push the pool." % current_streak)

func _lose(double_penalty: bool, pool_before_draw: int, reason: String) -> void:
	var base_pool: int = drink_pool() if count_drawn_card_in_penalty else pool_before_draw
	var amount: int = base_pool * (2 if double_penalty else 1)
	round_log.emit("%s  ->  seat %d drinks %d." % [reason, current_seat, amount])
	penalty_triggered.emit(current_seat, amount)
	_clear_table_and_reseed()
	_advance_seat()

func _draw_one() -> CardData:
	_ensure_cards(1)
	var card: CardData = _deck.draw()
	table_cards.append(card)
	card_revealed.emit(card)
	pool_changed.emit(drink_pool())
	return card

func _seed_active_card() -> void:
	table_cards.clear()
	table_cleared.emit()
	_draw_one()

func _clear_table_and_reseed() -> void:
	_deck.discard(table_cards)
	table_cards.clear()
	table_cleared.emit()
	current_streak = 0
	_awaiting_pass = false
	streak_changed.emit(current_streak)
	pass_available.emit(false)
	_draw_one()

func _ensure_cards(needed: int) -> void:
	# DeckEngine.draw() already recycles discard when empty. Last resort: if the
	# discard is also dry, recycle all table cards except the active one.
	if _deck.deck_size() + _deck.discard_size() >= needed:
		return
	if table_cards.size() > 1:
		var keep: CardData = table_cards.back()
		var recycled := table_cards.slice(0, table_cards.size() - 1)
		_deck.return_to_deck(recycled)
		table_cards = [keep]
		round_log.emit("Deck recycled mid-ride to keep play going.")

func _advance_seat() -> void:
	current_seat = (current_seat + 1) % seat_count
	turn_changed.emit(current_seat)
	round_log.emit("Seat %d's turn — pool starts at %d." % [current_seat, drink_pool()])
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless --path . --script res://tests/test_game_engine.gd`
Expected: final line `RESULT: PASS` (0 failed).

- [ ] **Step 5: Commit**

```bash
git add scenes/engine/game_engine.gd tests/test_game_engine.gd
git commit -m "feat(mp): port rules into authoritative seat-aware GameEngine"
```

---

## Task 4: Offline mode — rewire `game_manager.gd` + `ui.gd` onto `GameEngine`

**Files:**
- Modify: `scenes/game_manager.gd` (becomes offline presenter that owns a `GameEngine`)
- Modify: `scenes/ui.gd` (bind to a generic presenter; render `card_revealed`/`table_cleared`)
- Test: `tests/test_offline_mode.gd`

**Interfaces:**
- Consumes: `GameEngine` (Task 3), `DeckEngine` (Task 2), `CardData` (Task 1), existing visual `Card` scene (`res://scenes/card.tscn`).
- Produces: `GameManager` (presenter) implementing the shared contract — signals `card_revealed/table_cleared/streak_changed/pool_changed/penalty_triggered/pass_available/turn_changed/round_log`; methods `act_move(move:int)`, `act_pass()`, `act_ride()`, `can_act()->bool`, `local_seat()->int`.

- [ ] **Step 1: Write the failing test (offline play via the presenter API)**

Create `tests/test_offline_mode.gd`:
```gdscript
extends SceneTree

var _game: Node
var _done := false

func _initialize() -> void:
	seed(7)
	_game = load("res://scenes/game.tscn").instantiate()
	get_root().add_child(_game)

func _process(_d: float) -> bool:
	if _done:
		return true
	if _game == null or not _game.is_node_ready():
		return false
	var t := TestHelper.new()
	# Offline presenter is always actionable (hotseat).
	t.check(_game.can_act(), "offline can_act true")
	t.check(_game.drink_pool() >= 1, "pool seeded")
	var seat0 := _game.local_seat()
	# Drive 20 moves through the presenter API; never crash, pool stays >= 1.
	for i in range(20):
		if _game.current_streak() >= 3:
			_game.act_ride()
		_game.act_move(i % 6)
		t.check(_game.drink_pool() >= 1, "pool >= 1 (i=%d)" % i)
	t.finish()
	_done = true
	return false
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . --script res://tests/test_offline_mode.gd`
Expected: FAIL — `can_act`/`act_move`/`local_seat`/`current_streak` not defined on `GameManager` yet.

- [ ] **Step 3: Rewrite `scenes/game_manager.gd` as the offline presenter**

Replace the entire file with:
```gdscript
extends Node2D
class_name GameManager
## OFFLINE single-device presenter. Owns a GameEngine and renders it locally.
## In hotseat play, whoever's turn it is acts on the shared screen, so can_act()
## is always true and we forward moves under the engine's own current_seat.

const CARD_SCENE := preload("res://scenes/card.tscn")

signal card_revealed(card: CardData)
signal table_cleared()
signal streak_changed(streak: int)
signal pool_changed(pool: int)
signal penalty_triggered(seat: int, amount: int)
signal pass_available(is_available: bool)
signal turn_changed(seat: int)
signal round_log(text: String)

@export var table_zone_path: NodePath = ^"UI/Stack"

var _engine: GameEngine
@onready var _table_zone: Node = get_node(table_zone_path)

func _ready() -> void:
	var deck := DeckEngine.new()
	deck.load_from_json("res://assets/database/card_database.json", "res://assets/database/card_collection.json")
	_engine = GameEngine.new()
	add_child(_engine)
	# Forward engine signals to the view, instantiating visuals on reveal.
	_engine.card_revealed.connect(_on_card_revealed)
	_engine.table_cleared.connect(_on_table_cleared)
	_engine.streak_changed.connect(func(s): streak_changed.emit(s))
	_engine.pool_changed.connect(func(p):
		Globals.cards_in_stack = p
		pool_changed.emit(p))
	_engine.penalty_triggered.connect(func(seat, amt): penalty_triggered.emit(seat, amt))
	_engine.pass_available.connect(func(on): pass_available.emit(on))
	_engine.turn_changed.connect(func(seat): turn_changed.emit(seat))
	_engine.round_log.connect(func(txt): round_log.emit(txt))
	_engine.setup(deck, 2)

# --- presenter contract ---

func act_move(move: int) -> void:
	_engine.submit_move(_engine.current_seat, move)

func act_pass() -> void:
	_engine.request_pass(_engine.current_seat)

func act_ride() -> void:
	_engine.request_ride(_engine.current_seat)

func can_act() -> bool:
	return true

func local_seat() -> int:
	return _engine.current_seat

func current_streak() -> int:
	return _engine.current_streak

func drink_pool() -> int:
	return _engine.drink_pool()

# --- rendering ---

func _on_card_revealed(card: CardData) -> void:
	var node: Card = CARD_SCENE.instantiate()
	node.setup_card(card.nice_name, card.rank, _suit_name(card.suit), card.texture_path, card.backface_path)
	node.is_facedown = false
	_table_zone.add_child(node)
	card_revealed.emit(card)

func _on_table_cleared() -> void:
	for child in _table_zone.get_children():
		_table_zone.remove_child(child)
		child.queue_free()
	table_cleared.emit()

func _suit_name(suit: int) -> String:
	return Globals.SUITS.keys()[suit].to_lower()
```

- [ ] **Step 4: Update `scenes/ui.gd` to bind to the presenter and render reveals**

Replace `scenes/ui.gd` with:
```gdscript
extends CanvasLayer
class_name UI
## View layer. Binds to a presenter (offline GameManager today; online Net
## later — both expose the same signals/methods). Holds no game rules.

@onready var presenter: Node = get_parent()

@onready var streak_label: Label = $InfoPanel/StreakLabel
@onready var pool_label: Label = $InfoPanel/DrinkPoolLabel
@onready var deck_label: Label = $InfoPanel/DeckLabel
@onready var stack_label: Label = $InfoPanel/StackLabel
@onready var turn_log: Label = $TurnLogLabel
@onready var action_buttons: GridContainer = $ActionButtons
@onready var pass_buttons: HBoxContainer = $PassButtons
@onready var win_particles: CPUParticles2D = $ParticleHolder/WinParticles

var _last_streak: int = 0

func _ready() -> void:
	Globals.update_ui.connect(_update_counters)
	presenter.streak_changed.connect(_on_streak_changed)
	presenter.pool_changed.connect(_on_pool_changed)
	presenter.penalty_triggered.connect(_on_penalty)
	presenter.pass_available.connect(_on_pass_available)
	presenter.round_log.connect(_on_log)

	$ActionButtons/HigherButton.pressed.connect(_select.bind(GameEngine.Move.HIGHER))
	$ActionButtons/LowerButton.pressed.connect(_select.bind(GameEngine.Move.LOWER))
	$ActionButtons/RedButton.pressed.connect(_select.bind(GameEngine.Move.RED))
	$ActionButtons/BlackButton.pressed.connect(_select.bind(GameEngine.Move.BLACK))
	$ActionButtons/PurpleButton.pressed.connect(_select.bind(GameEngine.Move.PURPLE))
	$ActionButtons/PostButton.pressed.connect(_select.bind(GameEngine.Move.POST))
	$PassButtons/PassButton.pressed.connect(_on_pass_pressed)
	$PassButtons/RideButton.pressed.connect(_on_ride_pressed)
	pass_buttons.visible = false

func _select(move: int) -> void:
	if presenter.can_act():
		presenter.act_move(move)

func _on_pass_pressed() -> void:
	if presenter.can_act():
		presenter.act_pass()

func _on_ride_pressed() -> void:
	if presenter.can_act():
		presenter.act_ride()

func _update_counters() -> void:
	deck_label.text = "Deck Size: %d" % Globals.cards_in_deck
	stack_label.text = "Stack Size: %d" % Globals.cards_in_stack

func _on_streak_changed(streak: int) -> void:
	streak_label.text = "Streak: %d" % streak
	if streak > _last_streak:
		win_particles.restart()
	_last_streak = streak

func _on_pool_changed(pool: int) -> void:
	pool_label.text = "Drink Pool: %d" % pool

func _on_penalty(_seat: int, _amount: int) -> void:
	win_particles.emitting = false
	_last_streak = 0

func _on_pass_available(is_available: bool) -> void:
	pass_buttons.visible = is_available
	for child in action_buttons.get_children():
		if child is Button:
			child.disabled = is_available
```

- [ ] **Step 5: Run test to verify it passes**

Run: `godot --headless --path . --script res://tests/test_offline_mode.gd`
Expected: `RESULT: PASS`.

- [ ] **Step 6: Smoke-test the scene still loads (no parse/path errors)**

Run: `godot --headless --path . scenes/game.tscn --quit-after 60 2>&1 | grep -iE 'error|RESULT'`
Expected: no `SCRIPT ERROR`/parse errors; cards seed and play-by-play prints.

- [ ] **Step 7: Commit**

```bash
git add scenes/game_manager.gd scenes/ui.gd tests/test_offline_mode.gd
git commit -m "refactor(mp): offline mode now drives GameEngine via presenter contract"
```

---

## Task 5: `Room` + `RoomManager`

**Files:**
- Create: `server/room.gd`
- Create: `server/room_manager.gd`
- Test: `tests/test_room_manager.gd`

**Interfaces:**
- Consumes: `GameEngine`, `DeckEngine`.
- Produces:
  - `Seat` (RefCounted): `peer_id:int`, `player_name:String`, `seat_index:int`.
  - `Room` (Node): `id:String`, `room_name:String`, `is_public:bool`, `join_code:String`, `max_seats:int=12`, `seats:Array`, `add_seat(peer_id, name)->int` (returns seat_index or -1 if full), `remove_seat(peer_id)->bool`, `is_full()->bool`, `player_count()->int`, `peer_ids()->Array[int]`, `seat_of(peer_id)->int`.
  - `RoomManager` (Node): `create_room(name, is_public)->Room`, `join(peer_id, room_id_or_code, name)->Room` (null if not found/full/already-seated), `leave(peer_id)->Room` (room left, or null), `list_public()->Array` (`{id,name,count,max}`), `room_of(peer_id)->Room`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_room_manager.gd`:
```gdscript
extends SceneTree

func _initialize() -> void:
	var t := TestHelper.new()
	seed(1)
	var rm := RoomManager.new()
	get_root().add_child(rm)

	var pub := rm.create_room("Lobby", true)
	t.check(pub.is_public, "public room flagged public")
	t.eq(pub.max_seats, 12, "max seats 12")

	# Fill 12 seats; the 13th is rejected.
	for i in range(12):
		var r := rm.join(1000 + i, pub.id, "P%d" % i)
		t.check(r != null, "seat %d joined" % i)
	t.eq(pub.player_count(), 12, "room full at 12")
	t.check(rm.join(9999, pub.id, "Overflow") == null, "13th join rejected")

	# Leaving frees a seat.
	t.check(rm.leave(1000) != null, "peer leaves")
	t.eq(pub.player_count(), 11, "seat freed on leave")

	# Private room joins by code, not by id-as-public.
	var prv := rm.create_room("Secret", false)
	t.check(prv.join_code != "", "private room has a code")
	t.check(rm.join(2000, prv.join_code, "CodeJoiner") != null, "join by code works")
	t.eq(prv.seat_of(2000), 0, "first private seat is index 0")

	# Public listing shows only public rooms.
	var listing := rm.list_public()
	var ids := []
	for entry in listing:
		ids.append(entry.id)
	t.check(ids.has(pub.id), "public room listed")
	t.check(not ids.has(prv.id), "private room not listed")
	t.finish()
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . --script res://tests/test_room_manager.gd`
Expected: `Could not find type "RoomManager"`.

- [ ] **Step 3: Implement `server/room.gd`**

```gdscript
extends Node
class_name Room

class Seat extends RefCounted:
	var peer_id: int
	var player_name: String
	var seat_index: int
	func _init(p_peer: int, p_name: String, p_index: int) -> void:
		peer_id = p_peer
		player_name = p_name
		seat_index = p_index

var id: String = ""
var room_name: String = ""
var is_public: bool = true
var join_code: String = ""
var max_seats: int = 12
var seats: Array = []  # Array[Seat]

func is_full() -> bool:
	return seats.size() >= max_seats

func player_count() -> int:
	return seats.size()

func add_seat(peer_id: int, player_name: String) -> int:
	if is_full() or seat_of(peer_id) != -1:
		return -1
	var index := seats.size()
	seats.append(Seat.new(peer_id, player_name, index))
	return index

func remove_seat(peer_id: int) -> bool:
	for i in range(seats.size()):
		if seats[i].peer_id == peer_id:
			seats.remove_at(i)
			# Re-pack seat indices so turn order stays contiguous.
			for j in range(seats.size()):
				seats[j].seat_index = j
			return true
	return false

func seat_of(peer_id: int) -> int:
	for s in seats:
		if s.peer_id == peer_id:
			return s.seat_index
	return -1

func peer_ids() -> Array:
	var ids := []
	for s in seats:
		ids.append(s.peer_id)
	return ids
```

- [ ] **Step 4: Implement `server/room_manager.gd`**

```gdscript
extends Node
class_name RoomManager

const ROOM_SCRIPT := preload("res://server/room.gd")

var _rooms: Dictionary = {}        # id -> Room
var _peer_to_room: Dictionary = {} # peer_id -> room id
var _counter: int = 0

func create_room(name: String, is_public: bool) -> Room:
	_counter += 1
	var room: Room = ROOM_SCRIPT.new()
	room.id = "room_%d" % _counter
	room.room_name = name
	room.is_public = is_public
	room.join_code = "" if is_public else _make_code()
	add_child(room)
	_rooms[room.id] = room
	return room

func join(peer_id: int, room_id_or_code: String, player_name: String) -> Room:
	if _peer_to_room.has(peer_id):
		return null  # one room per peer
	var room := _resolve(room_id_or_code)
	if room == null or room.is_full():
		return null
	if room.add_seat(peer_id, player_name) == -1:
		return null
	_peer_to_room[peer_id] = room.id
	return room

func leave(peer_id: int) -> Room:
	if not _peer_to_room.has(peer_id):
		return null
	var room: Room = _rooms.get(_peer_to_room[peer_id])
	_peer_to_room.erase(peer_id)
	if room != null:
		room.remove_seat(peer_id)
		if room.player_count() == 0:
			_rooms.erase(room.id)
			room.queue_free()
	return room

func room_of(peer_id: int) -> Room:
	if not _peer_to_room.has(peer_id):
		return null
	return _rooms.get(_peer_to_room[peer_id])

func list_public() -> Array:
	var out := []
	for room in _rooms.values():
		if room.is_public:
			out.append({"id": room.id, "name": room.room_name, "count": room.player_count(), "max": room.max_seats})
	return out

func _resolve(room_id_or_code: String) -> Room:
	if _rooms.has(room_id_or_code):
		return _rooms[room_id_or_code]
	for room in _rooms.values():
		if not room.is_public and room.join_code == room_id_or_code:
			return room
	return null

func _make_code() -> String:
	var alphabet := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	var code := ""
	for i in range(5):
		code += alphabet[randi() % alphabet.length()]
	return code
```

- [ ] **Step 5: Run test to verify it passes**

Run: `godot --headless --path . --script res://tests/test_room_manager.gd`
Expected: `RESULT: PASS`.

- [ ] **Step 6: Commit**

```bash
git add server/room.gd server/room_manager.gd tests/test_room_manager.gd
git commit -m "feat(mp): Room + RoomManager with 12-seat cap, public list, private codes"
```

---

## Task 6: `Net` autoload — ENet boot + room RPCs (connection slice)

**Files:**
- Create: `scenes/net/net.gd`
- Create: `server/server_main.gd`, `server/server.tscn`
- Modify: `project.godot` (register `Net` autoload)
- Test: `tests/net_server_boot.gd`, `tests/net_client_probe.gd`, `tests/run_net_integration.sh`

**Interfaces:**
- Consumes: `RoomManager` (Task 5), `GameEngine` (Task 3), `DeckEngine` (Task 2), `CardData` (Task 1).
- Produces: autoload `Net` (`/root/Net`) with `start_server(port:int) -> void`, `start_client(ip:String, port:int) -> void`, RPCs `rpc_join_room(room_or_code:String, player_name:String)`, `rpc_create_room(name:String, is_public:bool)`, `rpc_list_public_rooms()`; client signals `connected()`, `seated(seat:int, room_name:String)`, `join_failed(reason:String)`, `public_rooms(list:Array)`. Const `Net.DEFAULT_PORT := 9000`.

- [ ] **Step 1: Register the autoload in `project.godot`**

In `project.godot`, under `[autoload]`, add `Net` after the existing entries:
```
[autoload]

LevelTransition="*res://globals/level_transition.tscn"
Globals="*res://globals/globals.gd"
Net="*res://scenes/net/net.gd"
```

- [ ] **Step 2: Write the integration harness scripts**

Create `tests/net_server_boot.gd` (runs as the server process, stays alive briefly):
```gdscript
extends SceneTree

func _initialize() -> void:
	seed(42)
	Net.start_server(Net.DEFAULT_PORT)
	print("SERVER: listening")

func _process(_d: float) -> bool:
	return false  # keep running; the shell script kills us
```

Create `tests/net_client_probe.gd` (connects, joins the auto public room, asserts a seat):
```gdscript
extends SceneTree

var _t := TestHelper.new()
var _elapsed := 0.0
var _seated := false

func _initialize() -> void:
	Net.connected.connect(func(): Net.rpc_join_room("auto", "Probe"))
	Net.seated.connect(func(seat, room_name):
		_seated = true
		_t.check(seat >= 0, "probe received a seat (%d) in %s" % [seat, room_name]))
	Net.start_client("127.0.0.1", Net.DEFAULT_PORT)

func _process(delta: float) -> bool:
	_elapsed += delta
	if _seated or _elapsed > 5.0:
		_t.check(_seated, "client got seated within timeout")
		_t.finish()
		return true
	return false
```

Create `tests/run_net_integration.sh`:
```bash
#!/usr/bin/env bash
set -u
cd "$(dirname "$0")/.."
godot --headless --path . --script res://tests/net_server_boot.gd >/tmp/pp_server.log 2>&1 &
SERVER_PID=$!
sleep 2
godot --headless --path . --script res://tests/net_client_probe.gd 2>&1 | tee /tmp/pp_client.log
RESULT=$?
kill "$SERVER_PID" 2>/dev/null
grep -q "RESULT: PASS" /tmp/pp_client.log && echo "INTEGRATION: PASS" || echo "INTEGRATION: FAIL"
```

- [ ] **Step 3: Run the harness to verify it fails**

Run: `bash tests/run_net_integration.sh`
Expected: `INTEGRATION: FAIL` (the `Net` autoload / methods don't exist yet).

- [ ] **Step 4: Implement `scenes/net/net.gd` (connection + rooms half)**

```gdscript
extends Node
## Shared network node present in BOTH server and client (autoload => same path
## `/root/Net`, which Godot RPC requires). Branches on multiplayer.is_server().

const DEFAULT_PORT := 9000
const ROOM_MANAGER := preload("res://server/room_manager.gd")
const DECK_ENGINE := preload("res://scenes/engine/deck_engine.gd")
const DB_PATH := "res://assets/database/card_database.json"
const COLLECTION_PATH := "res://assets/database/card_collection.json"

# Client-facing signals
signal connected()
signal seated(seat: int, room_name: String)
signal join_failed(reason: String)
signal public_rooms(list: Array)

var _rooms: RoomManager      # server only
var _auto_room: Room         # server only — the iteration-1 default public room

func start_server(port: int) -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, 64)
	assert(err == OK, "server failed to start on port %d" % port)
	multiplayer.multiplayer_peer = peer
	_rooms = ROOM_MANAGER.new()
	add_child(_rooms)
	_auto_room = _rooms.create_room("Auto Public Room", true)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

func start_client(ip: String, port: int) -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	assert(err == OK, "client failed to connect to %s:%d" % [ip, port])
	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(func(): connected.emit())

# ---- client -> server ----

@rpc("any_peer", "call_remote", "reliable")
func rpc_join_room(room_or_code: String, player_name: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	# Iteration 1: "auto" routes to the default public room.
	var target := _auto_room.id if room_or_code == "auto" else room_or_code
	var room := _rooms.join(sender, target, player_name)
	if room == null:
		rpc_id(sender, "_client_join_failed", "room full or not found")
		return
	rpc_id(sender, "_client_seated", room.seat_of(sender), room.room_name)
	_ensure_engine(room)

@rpc("any_peer", "call_remote", "reliable")
func rpc_create_room(name: String, is_public: bool) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var room := _rooms.create_room(name, is_public)
	var seat := _rooms.join(sender, room.id, "Host")
	rpc_id(sender, "_client_seated", room.seat_of(sender), room.room_name)
	_ensure_engine(room)

@rpc("any_peer", "call_remote", "reliable")
func rpc_list_public_rooms() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	rpc_id(sender, "_client_public_rooms", _rooms.list_public())

# ---- server -> client ----

@rpc("authority", "call_remote", "reliable")
func _client_seated(seat: int, room_name: String) -> void:
	seated.emit(seat, room_name)

@rpc("authority", "call_remote", "reliable")
func _client_join_failed(reason: String) -> void:
	join_failed.emit(reason)

@rpc("authority", "call_remote", "reliable")
func _client_public_rooms(list: Array) -> void:
	public_rooms.emit(list)

# ---- server internals ----

func _ensure_engine(room: Room) -> void:
	# Game RPC wiring is added in Task 7; for the connection slice we only need
	# a room with seats. Engine creation is idempotent there.
	pass

func _on_peer_disconnected(peer_id: int) -> void:
	if _rooms != null:
		_rooms.leave(peer_id)
```

- [ ] **Step 5: Create the server entry scene**

Create `server/server_main.gd`:
```gdscript
extends Node

func _ready() -> void:
	var port := Net.DEFAULT_PORT
	Net.start_server(port)
	print("SERVER: Purple & Post listening on %d" % port)
```

Create `server/server.tscn`:
```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://server/server_main.gd" id="1_srv"]

[node name="Server" type="Node"]
script = ExtResource("1_srv")
```

- [ ] **Step 6: Run the harness to verify it passes**

Run: `bash tests/run_net_integration.sh`
Expected: client log ends with `RESULT: PASS` and the script prints `INTEGRATION: PASS`.

- [ ] **Step 7: Commit**

```bash
git add scenes/net/net.gd server/server_main.gd server/server.tscn project.godot tests/net_server_boot.gd tests/net_client_probe.gd tests/run_net_integration.sh
git commit -m "feat(mp): Net autoload + ENet server boot, room join over the wire"
```

---

## Task 7: Game RPCs + authority + client presenter + online UI

**Files:**
- Modify: `scenes/net/net.gd` (add per-room `GameEngine`, move/pass/ride RPCs, event fan-out, client presenter API)
- Test: extend `tests/net_client_probe.gd` is replaced by `tests/net_client_play.gd` (used in Task 8)

**Interfaces:**
- Consumes: everything above.
- Produces on `Net` the **presenter contract** (so `ui.gd` can bind to `Net` exactly like the offline `GameManager`): signals `card_revealed(card:CardData)`, `table_cleared()`, `streak_changed(streak:int)`, `pool_changed(pool:int)`, `penalty_triggered(seat:int, amount:int)`, `pass_available(is_available:bool)`, `turn_changed(seat:int)`, `round_log(text:String)`; methods `act_move(move:int)`, `act_pass()`, `act_ride()`, `can_act()->bool`, `local_seat()->int`. Plus server RPCs `rpc_request_move(move:int)`, `rpc_request_pass()`, `rpc_request_ride()`.

- [ ] **Step 1: Add presenter state + game RPCs to `Net` (append/extend `scenes/net/net.gd`)**

Add these members near the top (after the existing signals):
```gdscript
# Presenter contract (mirrors GameManager so ui.gd binds to Net unchanged)
signal card_revealed(card: CardData)
signal table_cleared()
signal streak_changed(streak: int)
signal pool_changed(pool: int)
signal penalty_triggered(seat: int, amount: int)
signal pass_available(is_available: bool)
signal turn_changed(seat: int)
signal round_log(text: String)

const GAME_ENGINE := preload("res://scenes/engine/game_engine.gd")

var _my_seat: int = -1          # client only
var _current_turn_seat: int = 0 # client only (mirror of server turn)
```

- [ ] **Step 2: Replace the stub `_ensure_engine` with real engine creation + fan-out**

In `scenes/net/net.gd`, replace the `_ensure_engine` function body:
```gdscript
func _ensure_engine(room: Room) -> void:
	if room.has_meta("engine"):
		return
	var deck := DECK_ENGINE.new()
	deck.load_from_json(DB_PATH, COLLECTION_PATH)
	var engine: GameEngine = GAME_ENGINE.new()
	add_child(engine)
	room.set_meta("engine", engine)
	# Fan out every engine event to all peers in THIS room.
	engine.card_revealed.connect(func(card): _broadcast(room, "_client_card_revealed", card.to_dict()))
	engine.table_cleared.connect(func(): _broadcast(room, "_client_table_cleared"))
	engine.streak_changed.connect(func(s): _broadcast(room, "_client_streak", s))
	engine.pool_changed.connect(func(p): _broadcast(room, "_client_pool", p))
	engine.penalty_triggered.connect(func(seat, amt): _broadcast(room, "_client_penalty", seat, amt))
	engine.pass_available.connect(func(on): _broadcast(room, "_client_pass_available", on))
	engine.turn_changed.connect(func(seat): _broadcast(room, "_client_turn", seat))
	engine.round_log.connect(func(txt): _broadcast(room, "_client_log", txt))
	engine.setup(deck, max(1, room.player_count()))

func _broadcast(room: Room, method: String, a = null, b = null) -> void:
	for pid in room.peer_ids():
		if a == null:
			rpc_id(pid, method)
		elif b == null:
			rpc_id(pid, method, a)
		else:
			rpc_id(pid, method, a, b)
```

- [ ] **Step 3: Add the move/pass/ride server RPCs (authority-gated via the engine)**

Append to `scenes/net/net.gd`:
```gdscript
@rpc("any_peer", "call_remote", "reliable")
func rpc_request_move(move: int) -> void:
	if not multiplayer.is_server():
		return
	_route_action(multiplayer.get_remote_sender_id(), "move", move)

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_pass() -> void:
	if not multiplayer.is_server():
		return
	_route_action(multiplayer.get_remote_sender_id(), "pass", 0)

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_ride() -> void:
	if not multiplayer.is_server():
		return
	_route_action(multiplayer.get_remote_sender_id(), "ride", 0)

func _route_action(sender: int, kind: String, move: int) -> void:
	var room := _rooms.room_of(sender)
	if room == null or not room.has_meta("engine"):
		return
	var engine: GameEngine = room.get_meta("engine")
	var seat := room.seat_of(sender)  # the engine itself rejects wrong-seat calls
	match kind:
		"move": engine.submit_move(seat, move)
		"pass": engine.request_pass(seat)
		"ride": engine.request_ride(seat)
```

- [ ] **Step 4: Add the client-side receivers + presenter methods**

Append to `scenes/net/net.gd`:
```gdscript
# ---- server -> client: game events ----

@rpc("authority", "call_remote", "reliable")
func _client_card_revealed(card_dict: Dictionary) -> void:
	card_revealed.emit(CardData.from_dict(card_dict))

@rpc("authority", "call_remote", "reliable")
func _client_table_cleared() -> void:
	table_cleared.emit()

@rpc("authority", "call_remote", "reliable")
func _client_streak(s: int) -> void:
	streak_changed.emit(s)

@rpc("authority", "call_remote", "reliable")
func _client_pool(p: int) -> void:
	pool_changed.emit(p)

@rpc("authority", "call_remote", "reliable")
func _client_penalty(seat: int, amount: int) -> void:
	penalty_triggered.emit(seat, amount)

@rpc("authority", "call_remote", "reliable")
func _client_pass_available(on: bool) -> void:
	pass_available.emit(on)

@rpc("authority", "call_remote", "reliable")
func _client_turn(seat: int) -> void:
	_current_turn_seat = seat
	turn_changed.emit(seat)

@rpc("authority", "call_remote", "reliable")
func _client_log(txt: String) -> void:
	round_log.emit(txt)

# ---- presenter contract (client) ----

func act_move(move: int) -> void:
	rpc_id(1, "rpc_request_move", move)

func act_pass() -> void:
	rpc_id(1, "rpc_request_pass")

func act_ride() -> void:
	rpc_id(1, "rpc_request_ride")

func can_act() -> bool:
	return _my_seat == _current_turn_seat

func local_seat() -> int:
	return _my_seat
```

- [ ] **Step 5: Record the client's own seat when seated**

In `scenes/net/net.gd`, update `_client_seated` to remember the seat:
```gdscript
@rpc("authority", "call_remote", "reliable")
func _client_seated(seat: int, room_name: String) -> void:
	_my_seat = seat
	seated.emit(seat, room_name)
```

- [ ] **Step 6: Verify the file still parses**

Run: `godot --headless --path . --script res://tests/test_card_data.gd`
Expected: `RESULT: PASS` (this proves the project — including the extended `Net` — still parses cleanly; an unrelated passing test is a fast whole-project parse check).

- [ ] **Step 7: Commit**

```bash
git add scenes/net/net.gd
git commit -m "feat(mp): authoritative move/pass/ride RPCs + client presenter on Net"
```

---

## Task 8: Networked gameplay integration test + run docs

**Files:**
- Create: `tests/net_client_play.gd`
- Modify: `tests/run_net_integration.sh` (add the 2-client gameplay scenario)
- Create: `docs/superpowers/RUN_MULTIPLAYER.md`

**Interfaces:**
- Consumes: the full `Net` API (Tasks 6–7).

- [ ] **Step 1: Write the 2-client gameplay probe**

Create `tests/net_client_play.gd` (a client that joins, and — only when it is its turn — makes a move; logs seat + turn events so the shell can assert sync and rejection):
```gdscript
extends SceneTree

var _t := TestHelper.new()
var _elapsed := 0.0
var _my_seat := -1
var _moves_made := 0
var _saw_turn := false

func _initialize() -> void:
	Net.connected.connect(func(): Net.rpc_join_room("auto", "Player"))
	Net.seated.connect(func(seat, _rn):
		_my_seat = seat
		print("CLIENT seated seat=%d" % seat))
	Net.turn_changed.connect(_on_turn)
	Net.pass_available.connect(func(on):
		if on and Net.can_act():
			Net.act_ride())
	Net.start_client("127.0.0.1", Net.DEFAULT_PORT)

func _on_turn(seat: int) -> void:
	_saw_turn = true
	print("CLIENT turn=%d mine=%d" % [seat, _my_seat])
	if seat == _my_seat and _moves_made < 8:
		_moves_made += 1
		Net.act_move(_moves_made % 6)

func _process(delta: float) -> bool:
	_elapsed += delta
	if _elapsed > 8.0:
		_t.check(_my_seat >= 0, "client seated")
		_t.check(_saw_turn, "client saw turn events from server")
		_t.finish()
		return true
	return false
```

- [ ] **Step 2: Extend the shell harness with the 2-client scenario**

Append to `tests/run_net_integration.sh` (before the final grep), a second scenario:
```bash
echo "--- 2-client gameplay scenario ---"
godot --headless --path . --script res://tests/net_server_boot.gd >/tmp/pp_server2.log 2>&1 &
SERVER2=$!
sleep 2
godot --headless --path . --script res://tests/net_client_play.gd >/tmp/pp_c1.log 2>&1 &
C1=$!
godot --headless --path . --script res://tests/net_client_play.gd >/tmp/pp_c2.log 2>&1 &
C2=$!
wait "$C1" "$C2"
kill "$SERVER2" 2>/dev/null
echo "client1:"; grep -E "seated|RESULT" /tmp/pp_c1.log
echo "client2:"; grep -E "seated|RESULT" /tmp/pp_c2.log
if grep -q "RESULT: PASS" /tmp/pp_c1.log && grep -q "RESULT: PASS" /tmp/pp_c2.log; then
  echo "GAMEPLAY: PASS"
else
  echo "GAMEPLAY: FAIL"
fi
```

- [ ] **Step 3: Run the full integration harness**

Run: `bash tests/run_net_integration.sh`
Expected: `INTEGRATION: PASS` and `GAMEPLAY: PASS`; both client logs show distinct seats (0 and 1) and `RESULT: PASS`. Server log shows no errors and no deck contents in client logs (grep `/tmp/pp_c1.log` for `texture_path` should only show revealed cards, never a full 52-card list).

- [ ] **Step 4: Write the run instructions**

Create `docs/superpowers/RUN_MULTIPLAYER.md`:
```markdown
# Running Purple & Post multiplayer (Iteration 1, local)

## Start the server (one terminal)
godot --headless --path . server/server.tscn
# prints: SERVER: Purple & Post listening on 9000

## Start each client (one terminal per player)
godot --path . scenes/game.tscn
# Iteration 1 connects to 127.0.0.1:9000 automatically and joins the auto room.

## Automated test
bash tests/run_net_integration.sh
# expect: INTEGRATION: PASS  and  GAMEPLAY: PASS

## Notes
- Transport is ENet (UDP) on port 9000 (Net.DEFAULT_PORT).
- The server is authoritative: the deck and undrawn cards never leave it.
- Public room browser, private-code entry UI, and remote hosting are Iteration 2.
```

- [ ] **Step 5: Commit**

```bash
git add tests/net_client_play.gd tests/run_net_integration.sh docs/superpowers/RUN_MULTIPLAYER.md
git commit -m "test(mp): 2-client authoritative gameplay integration + run docs"
```

---

## Self-Review (completed by plan author)

**1. Spec coverage**
- §2 topology → Tasks 6–8 (Net server/client, authority). ✔
- §3 CardData seam → Task 1. ✔
- §4 GameEngine + DeckEngine refactor → Tasks 2–3. ✔
- §5 Rooms & seats (12 cap, public/private) → Task 5. ✔
- §6 RPC protocol → Tasks 6–7 (room + game RPCs). ✔
- §7 client integration / `_can_act` by seat → Tasks 4 (presenter contract) + 7 (`can_act`). ✔
- §8 Iteration 1 scope (one auto public room, localhost 2 clients) → Tasks 6 + 8. ✔
- §9 verification (engine parity, out-of-turn rejection, disconnect, no deck leakage) → Task 3 (rejection), Task 8 (sync/leakage), Task 6 (`_on_peer_disconnected` frees seat). ✔
- §10 keep offline mode → Task 4. ✔

**2. Placeholder scan:** `_ensure_engine` is a deliberate stub in Task 6 and is replaced with full code in Task 7 Step 2 (called out explicitly). No "TBD/handle errors/similar to" placeholders remain.

**3. Type consistency:** presenter contract (`act_move/act_pass/act_ride/can_act/local_seat` + the 8 signals) is identical on `GameManager` (Task 4) and `Net` (Task 7); `GameEngine.Move`, `submit_move(seat, move)`, `request_pass/ride(seat)`, `RoomManager.join/leave/list_public/room_of`, `Room.seat_of/peer_ids/add_seat` all match across tasks.

**Known follow-ups (Iteration 2, intentionally out of scope):** lobby/create/join UI, private-code entry screen, deployment/hosting, reconnection, spectators, seat-count change mid-game (engine reads `room.player_count()` at `setup` time only).
```
