# Purple & Post — Online Play (Iteration 2) Plan

**Goal:** Let any number of players (2 to 12) play one game from their own phones: one player hosts, the others join with an invite code (or pick a public room), and everyone sees the same table. The server stays authoritative. Offline hotseat keeps working.

**Where we are:** Iteration 1 shipped the authoritative `GameEngine`, the `Net` autoload (move, pass and event RPCs), rooms with seats (public room, private room with a 5-character code, 12-seat cap) and a 2-client headless test. The UI is now fully presenter-agnostic (`act_move`, `act_pass`, `can_act`, `local_seat`, `legal_moves`, `seat_count`, plus every engine signal, including `phantoms_added` and `diamonds_forever`), and `Net` implements all of it. What is missing is everything between the title screen and a running online game, and robustness once people drop in and out.

**Out of scope:** accounts and persistence, matchmaking by skill, chat, spectators beyond the late-join case below, web export (ENet is UDP, so no browser build in this iteration).

## Open decisions (answer these before building 2B and 2C)

1. **Minimum players to start.** The rules doc says 4 or more. Proposal: require 2 so it can be tested and played in a pair, and show "best with 4+" in the lobby.
2. **Joining a game already in progress.** Proposal: the joiner waits in the lobby as a spectator (sees the table, cannot act) and gets a seat when the next game starts. The alternative is to seat them at the end of the turn order immediately.
3. **Where the server runs.** Proposal: a dedicated headless server you deploy (a small VPS, UDP 9000). A host-on-your-own-phone mode (listen server, needs NAT traversal) would be a later add-on.
4. **Reconnect grace period.** Proposal: hold a dropped player's seat for 60 seconds. If it is their turn, the table waits for them for the first 20 seconds, then play skips to the next seat.
5. **A player who leaves for good mid-game.** Proposal: their seat is removed. If they were holding the stack, it passes to the next player as a pass would (no drinks), and everyone is told.
6. **Names.** Proposal: a name typed once on the join screen and kept on the device, shown in the lobby and the turn banner. Duplicate names get a number suffix.

## Design

**Room states.** A room is `LOBBY` (players gather, the host can start) or `PLAYING` (a `GameEngine` exists and seats are fixed) and returns to `LOBBY` when the host ends the game. Today the engine is created on the first join and `seat_count` follows joins; that changes so nobody is seated into a live game by accident.

**Event batching.** The server currently sends one RPC per engine signal, so the client cannot tell that Purple's two cards belong together, and a slow packet can split them. Instead the server collects all engine signals produced by one action (a move or a pass) into one ordered list and sends it as a single `_client_events` RPC. The client replays that list through the same signals the UI already listens to. This also removes any chance of events interleaving across actions, and the Purple pair reveal then works online without a special marker.

**Snapshot for late joiners and reconnects.** One `_client_snapshot` RPC carries: the roster (names, seat order), whose turn it is, the stack as revealed cards (phantom flag included), contribution count, pass availability and room state. It never contains the deck or the discard (the existing hidden-information rule, and the integration test that greps client logs for deck contents stays).

**Reconnect.** On join the server gives each player a random session token, which the client keeps in memory (and on disk for app restarts). If a connection drops mid-game the seat is held, not removed, and `peer_id` is re-bound when the same token reconnects. This is why seats become stable ids (the current "re-pack on leave" only happens when a seat is released for good).

**Client flow.**
```
start screen -> Play menu -> [Offline hotseat]            -> game (GameManager)
                          -> [Host a game]  -> lobby (shows code) -> game (Net)
                          -> [Join with code / Browse public] -> lobby -> game (Net)
```
`UI` currently takes its presenter from `get_parent()`. For online it is given a presenter explicitly (`bind(presenter)`), so one game scene serves both offline and online. The online scene wraps `/root/Net`, which already has the full presenter interface.

**Security and hardening.** Server derives the seat from the sender (already true), validates every argument, throttles join-code guesses (e.g. 5 wrong codes per minute per peer), caps name length and strips control characters, ignores RPCs from peers who are not in a room, and only the host may start or end a game.

## Steps

### 2A. Wire the client to the server (smallest vertical slice)
- [ ] Event batching in `Net`: collect engine signals per action, flush as one `_client_events` RPC; client replays them in order. Test: a Purple move arrives as one batch containing both cards.
- [ ] `UI.bind(presenter)` instead of `get_parent()`; offline scene passes `GameManager`.
- [ ] Online game scene that binds the UI to `Net`.
- [ ] A temporary "Play online (auto room)" button on the start screen: connect to an address from a text field, `join_room("auto", name)`.
- [ ] Verify: two real windows play a full game against a local server.

### 2B. Lobby, invite codes, names
- [ ] `Room.state`, `Room.host_peer`, names in the roster, host-only `rpc_start_game` / `rpc_end_game`, minimum-player check.
- [ ] Engine created at start with the final seat count; no `seat_count` changes from joins.
- [ ] RPCs: `rpc_create_room(name, is_public)` replies with room info and code; `rpc_join_room(code_or_id, name)`; `rpc_leave_room`; `_client_roster` broadcast on every change.
- [ ] Join-code throttling and name sanitising.
- [ ] Screens: Play menu, Host (shows the code and a copy/share button), Join (code entry), public room list, lobby (roster, Start for the host).
- [ ] Tests: `test_room_manager.gd` for states, host rules, throttling; integration test with 3 clients through create, join by code, start.

### 2C. Late join, reconnect, disconnect handling
- [ ] `_client_snapshot` and the spectator case from decision 2.
- [ ] Session tokens, seat holding, grace timers, turn skip, the forced-leave rule from decision 5.
- [ ] Remove the obsolete `_awaiting_pass` backlog item (Ride no longer exists, so pass is never a locked state).
- [ ] Tests: drop and reconnect a client mid-game and compare its snapshot with the server's table; late joiner sees the same stack; no deck contents in any client log.

### 2D. Remote hosting
- [ ] Server address and port in the join UI, with the last used address remembered.
- [ ] Linux headless export preset and a short deploy guide (`docs/superpowers/RUN_MULTIPLAYER.md`): open UDP 9000, run as a service, restart on crash.
- [ ] Optional: a health print and basic logging (room count, player count).
- [ ] Test the latency feel from a phone on mobile data; check that the pass and Purple animations hold with ~150 ms of lag.

### 2E. Polish
- [ ] Turn banner and "you're up" use names; show who is holding the stack.
- [ ] Connection lost / reconnecting overlay, kicked-for-inactivity message.
- [ ] Sound and haptic cue on your turn when the app is in the background.
- [ ] Update `CLAUDE.md` and `RUN_MULTIPLAYER.md` when each phase lands.

## Verification
- `bash tests/run_net_integration.sh` stays the gate: it must keep passing, and grows scenarios per phase (3 clients, code join, reconnect, late join).
- The existing rule that no deck contents may appear in client logs is checked in every scenario.
- Manual check each phase: two or three real windows, then a real phone against a remote server for 2D.

## Risks
- **Phone backgrounding:** mobile OSes suspend the app and drop UDP; reconnect with the session token has to be reliable before this is fun in practice (hence 2C before 2D).
- **UDP and NAT:** a dedicated public server avoids it; a host-on-device mode would need relay or hole punching and is deferred.
- **UI queue timing:** the batching in 2A is what makes the Purple pair and the in-order animations safe over the network, so it goes first.
