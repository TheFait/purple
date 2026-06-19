# Purple & Post — Authoritative Multiplayer (Public/Private Rooms)

**Date:** 2026-06-18
**Status:** Design — awaiting review
**Scope of this spec:** Architecture for online multiplayer + **Iteration 1** (local vertical slice). Public-room directory UI and hosting/deployment are Iteration 2 and only sketched here.

---

## 1. Decisions (locked)

| Decision | Choice | Consequence |
|---|---|---|
| Platforms | Mobile + Desktop, **no web** | Transport = **ENet** (`ENetMultiplayerPeer`, UDP) |
| Hosting / matchmaking | **Dedicated authoritative server** (headless Godot) | Server owns truth; clients are thin views; real public rooms; anti-cheat |
| First iteration | **Design + local vertical slice** | Build the core over localhost/LAN; defer public directory + deploy |
| Rules vs visuals | **Split** into pure `CardData` + `GameEngine` | Server runs rules without UI; client renders |

Max players per room: **12**.

---

## 2. Architecture overview

```
[ Client ]  [ Client ]  ... ≤ 12 per room        (mobile / desktop)
  renders CardData, sends move INTENTS via RPC
        \___________________ ENet ______________________/
                     [ Headless Godot SERVER ]   peer id 1, authoritative
                     ├─ RoomManager  (public list + private join codes)
                     └─ Room × N { GameEngine, seats[] }
                          GameEngine owns deck + RNG  (NEVER serialized to clients)
```

- **Authority:** the server is the multiplayer authority for all game state. Clients send *intents*; the server validates, mutates the authoritative `GameEngine`, and broadcasts results.
- **Hidden information:** deck order and undrawn cards are never sent to clients. Only revealed cards cross the wire. This makes "peek at the next card" impossible.
- **Client role:** render revealed `CardData` into the existing visual `Card` scene; show streak/pool/turn; enable input only on the local player's turn.

---

## 3. Data model — the rules/visuals seam

### 3.1 `CardData` (new, `scenes/cards/card_data.gd`)
`RefCounted`. The network-serializable unit of card information.

```
class_name CardData
rank: int           # 2..14 (J=11, Q=12, K=13, A=14)  — matches existing JSON
suit: int           # Globals.SUITS (HEARTS/SPADES/DIAMONDS/CLUBS)
nice_name: String   # "Ace of Hearts"
texture_path: String
backface_path: String

func is_red() -> bool
func is_black() -> bool
func to_dict() -> Dictionary      # for RPC
static func from_dict(d) -> CardData
```

Rationale: the existing rules only ever read `.rank` / `.suit`, so moving them onto a plain data object changes no logic. This is the `Card`-as-`Resource` idea from the original blueprint, now justified by the server boundary.

### 3.2 Existing `Card` (Control) — unchanged, **client-only**
Still the visual node (`FrontFace`/`BackFace`, `flip()`). The client builds one from a received `CardData` to display it. The server never instantiates it.

---

## 4. `GameEngine` (refactor of the verified `game_manager.gd`)

New `scenes/engine/game_engine.gd` (`Node`, server-side, owned by its `Room` — `Node` so it can hold child state and emit signals naturally; `DeckEngine` below stays a lightweight `RefCounted`). The **proven** logic from `game_manager.gd` moves here almost verbatim, retyped onto `CardData`:

| Stays identical | Changes |
|---|---|
| `Move` enum; `_on_move_selected` routing | `table_cards: Array[CardData]` (was Control `Card`) |
| `_win` / `_lose`, `count_drawn_card_in_penalty` toggle | Drawing via a pure `DeckEngine` (below), not the visual `Deck` node |
| streak / pool / pass-ride / accidental-Post + double-penalty | No `add_child` / `flip` / `update_display` — engine emits *events* instead |
| `_advance_player`, `_ensure_cards` recycle logic | Emits `CardData` (or dicts) in its signals so the client can render |

**Engine signals (consumed by the server's RPC layer, then forwarded to clients):**
`card_revealed(card)`, `move_resolved(correct, streak, pool)`, `penalty_triggered(seat, amount)`, `pass_available(is_available)`, `turn_changed(seat)`, `round_log(text)`.

### 4.1 `DeckEngine` (new, `scenes/engine/deck_engine.gd`)
Pure refactor of `Deck.gd`'s data half: load JSON → `Array[CardData]`, `shuffle`, `draw() -> CardData`, `clear_table()` (table→discard), discard recycle. No `Control`, no scene tree. The existing visual `Deck` node is retired from the server path (still usable for any single-device/offline mode if kept).

---

## 5. Rooms & seats

### 5.1 Model (`server/room.gd`)
```
Room:
  id: String              # short unique id
  name: String
  is_public: bool
  join_code: String       # 4–6 chars, private rooms only
  max_seats: int = 12
  seats: Array[Seat]      # Seat { peer_id, player_name, seat_index }
  engine: GameEngine
  state: enum { LOBBY, IN_GAME }
```

### 5.2 `RoomManager` (`server/room_manager.gd`)
- `create_room(name, is_public) -> Room` (generates id; join_code if private)
- `join_room(peer_id, room_id_or_code, name) -> Result` (rejects if full / not found)
- `leave_room(peer_id)` (free seat; advance turn if needed; close room if empty)
- `list_public_rooms() -> Array` (id, name, player_count/max)
- Enforces the 12-seat cap and one-room-per-peer.

### 5.3 Turn order
Seat order = turn order. `GameEngine.current_player` is a **seat index**. On disconnect of the active seat, the engine advances to the next occupied seat.

---

## 6. RPC protocol (ENet, Godot high-level multiplayer)

**Client → Server** (`@rpc("any_peer")` on server nodes):
- `rpc_create_room(name, is_public)`
- `rpc_join_room(room_id_or_code, player_name)`
- `rpc_leave_room()`
- `rpc_request_move(move: int)`
- `rpc_request_pass()` / `rpc_request_ride()`
- `rpc_list_public_rooms()`

**Server → Client** (`@rpc` targeted to a room's peers):
- `rpc_room_updated(seats, state)`
- `rpc_public_rooms(list)`
- `rpc_card_revealed(card_dict)`
- `rpc_move_resolved(correct, streak, pool)`
- `rpc_penalty(seat, amount)`
- `rpc_turn_changed(seat)`
- `rpc_pass_available(is_available)`
- `rpc_round_log(text)`

**Validation (server-side, every move):**
1. Peer is seated in a room. 2. It is that peer's seat's turn. 3. The seat does not currently owe a Pass/Ride decision (unless the call *is* pass/ride). Reject otherwise (no state change; optional `rpc_rejected(reason)`).

---

## 7. Client integration

- New `ClientNet` (`scenes/net/client_net.gd`): connects via ENet, sends intents, receives server events.
- The existing `ui.gd` is repointed: button presses call `ClientNet.rpc_request_move(...)` instead of a local manager; server events drive the same label/particle handlers already written.
- `_can_act()` (already stubbed in `ui.gd`) becomes: `my_seat == current_turn_seat`.
- Revealed `CardData` → instantiate the visual `Card` scene into the `Stack` zone (reusing today's presentation code).

A thin **offline/single-device mode** can remain by keeping a local `GameEngine` the UI talks to directly — same engine, no network. (Optional; not required for Iteration 1.)

---

## 8. Iteration 1 — vertical slice (what we build after this spec is approved)

**In scope**
- `CardData`, `DeckEngine`, `GameEngine` (rules ported + unit-checked against today's verified behavior).
- `RoomManager` with **one auto-created public room** (no lobby UI yet).
- Seat join on connect; authoritative `move` / `pass` / `ride`; server→client events.
- Client renders engine events into the existing UI; input gated to the local seat.
- Run target: **server on localhost/LAN + 2 client instances.**

**Deferred to Iteration 2**
- Public-room browser UI + create/join screens; private join-code entry UI.
- Deployment/hosting (Fly.io / Railway / VPS), TLS/auth, server lifecycle.
- Reconnection / seat-reservation; spectators; persistence.

---

## 9. Verification strategy

- **Engine parity:** headless harness drives `GameEngine` through the same move sequences used to verify `game_manager.gd`; assert identical streak/pool/penalty outcomes (rules unchanged).
- **Networked slice:** launch 1 server + 2 client processes headless; script seat A and seat B alternating; assert:
  - revealed cards and streak/pool match across both clients,
  - an out-of-turn `rpc_request_move` from the non-active seat is **rejected** (no state change),
  - a disconnect frees the seat and advances the turn,
  - deck contents are never present in any client-bound message.

---

## 10. File plan

**New**
- `scenes/cards/card_data.gd` — `CardData`
- `scenes/engine/deck_engine.gd` — pure deck
- `scenes/engine/game_engine.gd` — ported rules
- `server/room.gd`, `server/room_manager.gd`, `server/server_main.gd` (+ `server.tscn`)
- `scenes/net/client_net.gd`

**Changed**
- `scenes/ui.gd` — talk to `ClientNet`; `_can_act()` uses seat
- `scenes/game.tscn` / start flow — connect-to-server entry (Iteration 1: hardcode localhost)
- `scenes/Deck.gd`, `scenes/game_manager.gd` — retained for optional offline mode, or thinned to presentation; not used on the server path

**Resolved (2026-06-19):** **Keep** `game_manager.gd` as a thin **offline single-device mode** that drives the new `GameEngine` locally (no network). It's a free local-play mode and a useful test surface for the engine. Once `GameEngine` exists, `game_manager.gd` is rewired to delegate rules to it rather than own them.
