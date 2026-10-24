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
- `scenes/engine/game_engine.gd`: `GameEngine`, a Node holding all the rules. It emits signals (`card_revealed`, `phantoms_added`, `streak_changed`, `pool_changed`, `penalty_triggered`, `pass_available`, `turn_changed`, `table_cleared`, `diamonds_forever`, `round_log`) and has no visuals. Entry points are `submit_move(seat, move)` and `request_pass(seat)`. The seat is passed in and the engine rejects out-of-turn or illegal calls. The same engine runs on the server, in offline mode and in tests.
- `scenes/net/net.gd`: the `Net` autoload, present on both server and client (RPCs need the same node path `/root/Net`). It branches on `multiplayer.is_server()`. Client intents are `rpc_request_move/pass`. Server events are `_client_*` RPCs, broadcast per room. ENet on UDP port 9000 (`Net.DEFAULT_PORT`). Each event is its own RPC for now; the Iteration 2 plan batches them per action.
- `server/`: `room.gd` (seats, re-packed on leave), `room_manager.gd`, `server_main.gd` + `server.tscn` (headless entry). Iteration 1 auto-creates one public room, and `join_room("auto", name)` joins it.
- `scenes/game_manager.gd`: the **offline hotseat presenter**. It owns a local `GameEngine` and forwards its signals. It creates no visuals.
- `scenes/ui.gd` + `scenes/ui.tscn`: the view. It binds to its **parent node** as the presenter and holds no rules. It **queues** presenter signals and plays them in order (deal, suspense, flip, celebrate or chaos, settle, sweep), locking input until the queue drains. The queue starts at the end of the frame so a whole engine burst is queued first; two `card` events in a row (only pool/log between) are Purple's pair and play as one 1-2 reveal. The guess buttons are "chips" fanned out on the deck face (`_fan_chips`); only legal guesses show, each popping in when it becomes valid, and the pressed one rides with the dealt card. The players row shows the active player as a big numbered circle and the others as small dots. **F1** toggles the round log (debug text, hidden by default).
- `scenes/table.gd`: the felt. The deck is a card back lying landscape at the bottom, hanging off the screen, with a small pile of card backs under it. At rest the stack is zoomed (`REST_ZOOM`) and cropped by the top of the screen: the first card sits in the upper-right and each later card steps a little down-left, so every card's bottom-right corner shows (the rank/suit text tags are switched off by `SHOW_TAGS`). A dealt card is revealed fully visible mid-screen (`reveal`, or `reveal_pair` for Purple), then `settle()` folds it into the stack; `add_phantoms` and `sweep` handle Post doubling and clearing. The chips are laid out on the visible part of the deck (`chips_global_center()`).
- `scenes/card.gd`: client-only card visual with `flip_animated()` and a neon `glow()`.
- `scenes/start_screen.tscn` + `.gd`: the title screen, with the same vaporwave backdrop as the game and the logo shine.
- `scenes/fx/`: `neon_theme.gd` (palette, fonts, styles built in code), `screen_fx.gd` (shake, flash, aberration, confetti, slam text, post-process layer), `sfx.gd` (the `Sfx` autoload: sounds plus haptics), `guess_icon.gd` (chevron glyphs for the symbol-only guess buttons).
- `assets/shaders/`: `vapor_bg` (backdrop on the `Background` layer of `game.tscn` and the start screen: striped diamond, card-suit twinkles, grid road), `logo_shine` (a highlight sweep down the title, timed to the road's `scroll_speed`), `post_fx` (screen pass). `assets/fonts/` (Monoton, Orbitron, Rajdhani; Google Fonts, OFL). `assets/audio/*.wav` (generated by `python tools/gen_sfx.py`; edit the script, not the wavs).

### Presenter contract

`GameManager` (offline) and `Net` (online) expose the same interface, so `ui.gd` is agnostic: the signals above plus `act_move(move)`, `act_pass()`, `can_act()`, `legal_moves()`, `local_seat()` and `seat_count()` (the players row; `Net` can only infer it until the server broadcasts the count). If you add an engine event or action, update **both** presenters, `Net`'s `_client_*` RPCs and `ui.gd`'s queue (`_enqueue` / `_play`).

### Invariants

- **Server authority and hidden info:** the deck and undrawn cards must never be sent to a client. Only revealed cards cross the wire (as `card_revealed` dicts, and phantom copies of cards already on the table). Integration tests check that no deck contents appear in client logs.
- Clients send intents only. Never trust a client-supplied seat. The server derives it from `get_remote_sender_id()` via `room.seat_of`.
- `Card` (`scenes/card.gd`, a Control) is client-only visuals. The server never instantiates it. Because the UI builds cards from `CardData`, an online presenter needs no card rendering of its own.
- `Globals` (autoload) holds shared enums (`SUITS`), the UI counters `cards_in_deck` / `cards_in_stack` (setting them emits `update_ui`) and `logo_seen`.
- `Net` is broken without its autoload path. Don't rename or move the autoload without updating `project.godot`.

### Current status

`scenes/game.tscn` is **offline only**: it does not connect to the server. The online client, lobby and invite codes, event batching, reconnection and remote hosting are planned in [the Iteration 2 plan](docs/superpowers/plans/2026-10-23-purple-post-multiplayer-iter2.md) (it also lists the open decisions). Because events are not batched yet, Purple's pair reveal over the network only works when both cards arrive in the same frame. Not yet built: player setup, game-over summary, pause/settings screens.

## Running and testing

`godot` must be on PATH. Tests are headless SceneTree scripts that print `OK:`/`FAIL:` lines and a final `RESULT: PASS|FAIL` via `tests/test_helper.gd`.

```bash
# unit tests (one per file)
godot --headless --path . --script res://tests/test_game_engine.gd
godot --headless --path . --script res://tests/test_deck_engine.gd
godot --headless --path . --script res://tests/test_card_data.gd
godot --headless --path . --script res://tests/test_room_manager.gd
godot --headless --path . --script res://tests/test_offline_mode.gd

# networked: spawns a headless server + 2 clients; expect INTEGRATION: PASS and GAMEPLAY: PASS
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
