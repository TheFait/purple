# Purple & Post

Godot 4.6 (GDScript, Mobile renderer, portrait 720x1280) drinking-card game for a table of players. The stack starts empty. Each turn the active player guesses what the next flip will be; correct guesses join the stack, a wrong guess means they drink every card in it (the wrong flip included) and guess again on an empty stack. Once a player has contributed 3 or more cards they may pass, and the next player inherits the stack.

This is **not** a MapleStory Worlds project. Ignore any MSW/mLua guidance you may have seen elsewhere.

## The rules (as implemented in `GameEngine`)

- **Stack** (`table_cards`): correct guesses only, plus the flip currently being judged. Top Card is the last, Drop Card the one before. Ace is high (rank 14).
- **Guesses by stack size:** Red, Black and Purple are always allowed. Higher and Lower need 1 card (they compare to the Top Card only). Inside, Outside and Post need 2 cards. `GameEngine.legal_moves()` / `legal_moves_for(n)` is the single source of truth; the UI hides illegal guesses.
- **Red / Black:** correct = +1 card. **Purple:** two flips of different colours = +2 cards (counts as 2 contributions). **Inside / Outside:** compare to the range between Top and Drop; equal to either rank loses. **Post:** a called Post that matches the Top Card's rank wins +1 contribution and doubles the stack with *phantom* cards (copies flagged `CardData.phantom`, prepended so the real Top/Drop don't change; they count toward drinks but are never discarded back into the deck).
- **Drinks on a loss** = stack size including the wrong flip(s). If the wrong flip ties the Top Card's rank without Post having been called (and the guess was not Purple), the drinks double. A failed Post call is a plain loss.
- **After a loss** the stack clears and the **same player** guesses again. Turns only move on a pass.
- **Pass** (`request_pass`) needs `current_streak >= 3` contributions *this turn* (the inheritor starts at 0). There is no Ride: a player who doesn't pass just keeps guessing.
- **Diamonds are Forever:** a correct (non-Purple) guess where the flip, Top and Drop are all diamonds emits `diamonds_forever`.
- The dealer is the app. No minimum player count is enforced yet (the rules doc says 4+).

## Architecture: rules / presentation split

Authoritative multiplayer is the design goal. See [the design spec](docs/superpowers/specs/2026-06-18-purple-post-multiplayer-design.md), [RUN_MULTIPLAYER.md](docs/superpowers/RUN_MULTIPLAYER.md) and the [Iteration 2 plan](docs/superpowers/plans/2026-10-23-purple-post-multiplayer-iter2.md) for status.

- `scenes/cards/card_data.gd`: `CardData`, a RefCounted, network-serializable card (`to_dict`/`from_dict`, includes `phantom`). Rules only read `.rank` (2..14) and `.suit`.
- `scenes/engine/deck_engine.gd`: `DeckEngine`, a pure RefCounted deck (load JSON, shuffle, draw, discard recycle). No scene tree. `load_cards()` builds an unshuffled deck for tests.
- `scenes/engine/game_engine.gd`: `GameEngine`, a Node holding all the rules. It emits signals (`card_revealed`, `phantoms_added`, `streak_changed`, `pool_changed`, `penalty_triggered`, `pass_available`, `turn_changed`, `table_cleared`, `stack_passed(from, to, count)`, `diamonds_forever`, `round_log`) and has no visuals. Entry points are `submit_move(seat, move)`, `request_pass(seat)` and `remove_seat(index)` (a player left for good: the turn order closes up; if they held the turn the stack passes on with no drinks). The seat is passed in and the engine rejects out-of-turn or illegal calls. The same engine runs on the server, in offline mode and in tests.
- `scenes/net/net.gd`: the `Net` autoload, present on both server and client (RPCs need the same node path `/root/Net`). It branches on `multiplayer.is_server()`. Client intents are `rpc_request_move/pass`, `rpc_request_sync` and the room calls (`rpc_create_room`, `rpc_join_room`, `rpc_leave_room`, host-only `rpc_start_game`/`rpc_end_game`). A game is only dealt when the host starts it (`_start_game`); anyone joining a running game takes the last seat. The room announces its roster to everyone with `_client_lobby` (`Net.room_info`, `lobby_changed`) and re-sends each player their seat. `auto_start_open_table` (set by the test server) skips the lobby for the open table. **Dropped connections:** in a running game a disconnect keeps the seat (`Room.Seat.away_since_msec`, `RoomManager.mark_away`) for `hold_msec` (60 s); if it is the away player's turn the table waits `turn_wait_msec` (20 s) and then `GameEngine.skip_turn()` hands the stack on with no drinks; when the hold runs out `_release_seat` removes the seat for good. Every join gives a session token (`_client_session`); the client keeps trying to reconnect for 60 s (`Net.reconnecting/resumed/session_expired`) and `rpc_resume(token)` rebinds the seat and replays a snapshot. The room hears the away list every second (`away_changed`). In lobbies a disconnect removes the player at once. The test server uses a 4 s hold and 1.5 s turn wait. **Idle players:** a connected player on turn who does not act is skipped after 60 s, then 30 s, then 15 s, and the third skip removes them (`_client_kicked`, "removed for inactivity"); acting resets their strikes (`Room.Seat.idle_strikes`, `Room.activity_msec`), and the last 10 s are counted down to the table (`idle_warning`). Run the test server with `-- idle` for short limits. **Rejoining after a restart:** the session token is also saved to `user://online.cfg` (`OnlineSettings.save_session`, refreshed every 10 s, ignored after 2 minutes) and `Net.resume_saved()` rejoins from it; the online menu shows REJOIN YOUR GAME. Headless runs (tests) use `user://online_headless.cfg`. The server buffers every engine event of one action and sends them as ONE ordered `_client_events` batch per room (so Purple's two cards, or a win's card + pool + streak, arrive together); the client replays the batch through the presenter signals (`_apply_event`). The server also announces `seats` (player count, current seat and every name in seat order) on every join/leave and a `left` event with the leaver's name (the UI says "<name> has disconnected" and redraws the players row, which grows and shrinks with the room). A pass is announced by `stack_passed`: the passer's screen (or the shared hotseat screen) shows "Passed stack of N to <name>", every other screen "<name>, you're up!". Names are trimmed, capped at 16 characters and numbered when taken (`Room.unique_name`). `request_sync()` asks for a snapshot (`restore` of the stack, counters, turn, seat count) that a UI which appeared late replays; the deck is never in it. `start_client`/`stop_client` manage the connection (`connect_failed` signal). ENet on UDP port 9000 (`Net.DEFAULT_PORT`).
- `server/`: `room.gd` (seats re-packed on leave, `State` LOBBY/PLAYING, a host who passes to the longest-seated player, unique cleaned names, `lobby_info()`), `room_manager.gd`, `join_throttle.gd` (5 wrong codes a minute per peer), `seat_hold.gd` (pure timing for dropped players, driven by a passed-in clock), `idle_watch.gd` (the same for connected players who do nothing on their turn), `server_main.gd` + `server.tscn` (headless entry). The server keeps one always-open public room, "Open Table" (`join_room("auto", name)`); other rooms are created by players (private rooms get a five-character invite code).
- `scenes/game_manager.gd`: the **offline hotseat presenter**. It owns a local `GameEngine` and forwards its signals. It creates no visuals.
- `scenes/ui.gd` + `scenes/ui.tscn`: the view. Its presenter is its **parent node** when that has `act_move` (offline `GameManager` in `game.tscn`), otherwise the `Net` autoload (`online_game.tscn`, whose root is a plain node); it holds no rules and calls `request_sync()` on start when the presenter has it. It **queues** presenter signals and plays them in order (deal, suspense, flip, celebrate or chaos, settle, sweep), locking input until the queue drains. The queue starts at the end of the frame so a whole engine burst is queued first; two `card` events in a row (only pool/log between) are Purple's pair and play as one 1-2 reveal. The guess buttons are "chips" fanned out on the deck face (`_fan_chips`); only legal guesses show, each popping in when it becomes valid, and the pressed one rides with the dealt card. The players row shows the active player as a big numbered circle and the others as small dots. **F1** toggles the round log (debug text, hidden by default).
- `scenes/table.gd`: the felt. The deck is a card back lying landscape at the bottom, hanging off the screen, with a small pile of card backs under it. At rest the stack is zoomed (`REST_ZOOM`) and cropped by the top of the screen: the first card sits in the upper-right and each later card steps a little down-left, so every card's bottom-right corner shows (the rank/suit text tags are switched off by `SHOW_TAGS`). A dealt card is revealed fully visible mid-screen (`reveal`, or `reveal_pair` for Purple), then `settle()` folds it into the stack; `add_phantoms` (a Post: ghost cards burst out at every angle and fade) and `sweep` handle Post doubling and clearing. The deck cards use `Card.set_outline` (thin border, no halo) so the heap of cards stays readable. The chips are laid out on the visible part of the deck (`chips_global_center()`).
- `scenes/card.gd`: client-only card visual with `flip_animated()` and a neon `glow()`.
- `scenes/start_screen.tscn` + `.gd`: the title screen, with the same vaporwave backdrop as the game and the logo shine. START plays offline; PLAY ONLINE opens `scenes/online_menu.tscn`.
- Online screens (`scenes/net/online_screen.gd` is their shared base, `online_settings.gd` remembers the name and server in `user://online.cfg`): `online_menu` (name, server, host a game, join with code, public rooms; connects on demand), `lobby` (invite code with copy, roster, host-only START, LEAVE) and `online_game` (the shared table plus a MENU button: resume, host-only end game, leave, and the "Reconnecting..." / "You were removed" cover for a dropped player). The UI shows away players as a greyed pulsing dot plus a countdown banner under the players row, announces a skipped turn or a removal, and keeps a line under the active player's circle saying who is up and what stack they hold ("Ann is holding the stack of 3 cards", "Your turn - holding a stack of 3 cards"), which turns into the idle countdown in red. On this device's own turn it plays a distinct sound, buzzes and (if the window is not in front) flashes the taskbar icon; real background notifications would need a native plugin. `Net.room_info`/`lobby_changed` decide which screen shows (lobby while gathering, table once dealt).
- `scenes/fx/`: `neon_theme.gd` (palette, fonts, styles built in code), `screen_fx.gd` (shake, flash, aberration, confetti, slam text, post-process layer), `sfx.gd` (the `Sfx` autoload: sounds plus haptics), `guess_icon.gd` (chevron glyphs for the symbol-only guess buttons).
- `assets/shaders/`: `vapor_bg` (backdrop on the `Background` layer of `game.tscn` and the start screen: striped diamond, card-suit twinkles, grid road), `logo_shine` (a highlight sweep down the title, timed to the road's `scroll_speed`), `post_fx` (screen pass). `assets/fonts/` (Monoton, Orbitron, Rajdhani; Google Fonts, OFL). `assets/audio/*.wav` (generated by `python tools/gen_sfx.py`; edit the script, not the wavs).

### Presenter contract

`GameManager` (offline) and `Net` (online) expose the same interface, so `ui.gd` is agnostic: the signals above (plus `table_restored(cards)`, `seats_changed(count, current_seat)`, `player_left(name)`, `away_changed(list)`, `turn_skipped(from, to)`, `idle_warning(seat, seconds, strike)` and `player_kicked(name)`, which only `Net` emits), `player_name(seat)` and `is_hotseat()` plus `act_move(move)`, `act_pass()`, `can_act()`, `legal_moves()`, `local_seat()` and `seat_count()` (the players row; `Net` can only infer it until the server broadcasts the count). If you add an engine event or action, update **both** presenters, `Net`'s `_client_*` RPCs and `ui.gd`'s queue (`_enqueue` / `_play`).

### Invariants

- **Server authority and hidden info:** the deck and undrawn cards must never be sent to a client. Only revealed cards cross the wire (as `card_revealed` dicts, and phantom copies of cards already on the table). The HIDDEN-DECK integration scenario enforces it: the test server dumps the deck order (`Net.deck_dump_path`), and the client (via the `Net.raw_batch` test hook) checks that no event batch mentions a card before the batch that draws it. It was verified to catch a deliberate leak.
- Clients send intents only. Never trust a client-supplied seat. The server derives it from `get_remote_sender_id()` via `room.seat_of`.
- `Card` (`scenes/card.gd`, a Control) is client-only visuals. The server never instantiates it. Because the UI builds cards from `CardData`, an online presenter needs no card rendering of its own.
- `Globals` (autoload) holds shared enums (`SUITS`), the UI counters `cards_in_deck` / `cards_in_stack` (setting them emits `update_ui`) and `logo_seen`.
- `Net` is broken without its autoload path. Don't rename or move the autoload without updating `project.godot`.

### Current status

`game.tscn` is the offline hotseat game. Online play works end to end: PLAY ONLINE, then host a table (private with an invite code, or public) or join one by code or from the public list, then the host starts the game (Iteration 2 phases 2A, 2B and 2C are done, including reconnecting). Remote hosting and polish are the rest of [the Iteration 2 plan](docs/superpowers/plans/2026-10-23-purple-post-multiplayer-iter2.md), whose decisions are locked. Not yet built: player setup, game-over summary, pause/settings screens.

## Running and testing

`godot` must be on PATH. Tests are headless SceneTree scripts that print `OK:`/`FAIL:` lines and a final `RESULT: PASS|FAIL` via `tests/test_helper.gd`.

```bash
# unit tests (one per file)
godot --headless --path . --script res://tests/test_game_engine.gd
godot --headless --path . --script res://tests/test_deck_engine.gd
godot --headless --path . --script res://tests/test_card_data.gd
godot --headless --path . --script res://tests/test_room_manager.gd
godot --headless --path . --script res://tests/test_join_throttle.gd
godot --headless --path . --script res://tests/test_seat_hold.gd
godot --headless --path . --script res://tests/test_idle_watch.gd
godot --headless --path . --script res://tests/test_online_screens.gd
godot --headless --path . --script res://tests/test_offline_mode.gd

# networked: spawns headless servers + clients; expect INTEGRATION, GAMEPLAY, BATCH, SNAPSHOT, DISCONNECT, PASS-NOTICE, LOBBY, HOLD-resume, HOLD-turnskip, HIDDEN-DECK, IDLE and COLD-REJOIN: PASS
bash tests/run_net_integration.sh

# see the game: needs a window (not --headless); autoplays and saves PNGs to <out_dir>
godot --path . --script res://tools/screenshot_run.gd -- <out_dir> [seed] [max_seconds]

# dedicated server
godot --headless --path . server/server.tscn     # prints "SERVER: Purple & Post listening on 9000"
```

`run_net_integration.sh` writes logs to `/tmp/pp_*.log` and needs a POSIX shell (Git Bash on Windows). When adding rules, add a case to `tests/test_game_engine.gd` first. It is the parity suite for the rules; it rigs the deck (`DeckEngine.load_cards`) so each case is deterministic, plus a fuzz test that no real card is ever lost or duplicated.

## Conventions

- Tabs for indentation. Static typing: typed args and return values on functions, `:=` where the type is inferable (see CONTRIBUTING.md, which otherwise belongs to the vendored plugin).
- Card data lives in `assets/database/card_database.json` (rank, suit name, texture paths) and `card_collection.json`. Suits in JSON are strings matching `Globals.SUITS` keys.
- `.uid` files are Godot 4.4+ generated metadata. Commit them with their `.gd` files. `.godot/` is gitignored.
- `addons/Todo_Manager/` is a third-party plugin. Don't edit it, and its README and CONTRIBUTING are not about this game.
- Stray `scenes/decD69.tmp` and `scenes/ui.8DFC.tmp` are editor temp files that were committed by accident. Don't build on them.
- The theme is neon vaporwave casino. Colors live in `NeonTheme`. Prefer its constants and `panel_style()` over ad-hoc colors.
- Seat numbers shown to players are 1-based; the engine's internal `current_seat` is 0-based.
- Commit style: conventional commits with scope, e.g. `feat(mp): ...`, `fix(mp): ...`, `test(mp): ...`.
