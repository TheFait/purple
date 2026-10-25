# Purple & Post — Online Play (Iteration 2) Plan

**Goal:** Let any number of players (2 to 12) play one game from their own phones: one player hosts, the others join with an invite code (or pick a public room), and everyone sees the same table. The server stays authoritative. Offline hotseat keeps working.

**Where we are:** Iteration 1 shipped the authoritative `GameEngine`, the `Net` autoload (move, pass and event RPCs), rooms with seats (public room, private room with a 5-character code, 12-seat cap) and a 2-client headless test. The UI is now fully presenter-agnostic (`act_move`, `act_pass`, `can_act`, `local_seat`, `legal_moves`, `seat_count`, plus every engine signal, including `phantoms_added` and `diamonds_forever`), and `Net` implements all of it. What is missing is everything between the title screen and a running online game, and robustness once people drop in and out.

**Out of scope:** accounts and persistence, matchmaking by skill, chat, spectators (a mid-game joiner is seated, not watching), web export (ENet is UDP, so no browser build in this iteration).

## Decisions (locked)

1. **Minimum players: 2.** The lobby shows "best with 4+". No upper change: the cap stays 12.
2. **Joining a game in progress: seat at the end of the turn order.** The joiner gets a snapshot and takes the last seat immediately; turn order and the current player are unaffected, and their contribution count starts at 0. (There are no spectators.)
3. **Server: dedicated headless server now; a same-Wi-Fi host mode later.** The later mode would use LAN broadcast discovery (no server needed) with the invite code finding the host; it is not part of this iteration. Player-hosted play over the internet is rejected (carrier NAT would need a relay server anyway).
4. **Reconnect: hold a dropped seat for 60 seconds.** If it is their turn, the table waits 20 seconds, then play skips to the next seat. **The UI must show this wait clearly** (see "Waiting-for-player UI" below).
5. **A player who leaves for good (quits, or the 60 seconds run out): their seat is removed and, if they held the stack, it passes to the next player like a pass, with no drinks.** Everyone sees who left.
6. **Names: typed once and remembered on the device.** Duplicates get a number suffix ("Sam", "Sam 2"). Shown in the lobby and the turn banner.

## Design

**Room states.** A room is `LOBBY` (players gather, the host can start) or `PLAYING` (a `GameEngine` exists and seats are fixed) and returns to `LOBBY` when the host ends the game. Today the engine is created on the first join and `seat_count` follows joins; that changes so nobody is seated into a live game by accident.

**Event batching.** The server currently sends one RPC per engine signal, so the client cannot tell that Purple's two cards belong together, and a slow packet can split them. Instead the server collects all engine signals produced by one action (a move or a pass) into one ordered list and sends it as a single `_client_events` RPC. The client replays that list through the same signals the UI already listens to. This also removes any chance of events interleaving across actions, and the Purple pair reveal then works online without a special marker.

**Waiting-for-player UI (decision 4).** When a connection drops, the server tells the room with a `_client_player_status(seat, state, seconds_left)` message (`connected`, `away`, `gone`) and keeps sending the remaining time once a second. The clients show:
- **Everyone else:** the dropped player's dot in the players row turns grey and pulses; a banner under the row reads "Sam lost connection, holding the seat... 0:47". If it is their turn, a second line counts the 20-second turn wait ("waiting for Sam... 0:14"); when it expires a slam text announces "Skipping Sam" and play moves on.
- **The dropped player, once back on the line:** a "Reconnecting..." overlay with the same countdown, then the snapshot restores the table. If the 60 seconds ran out they see "You were removed from the game" and a button back to the menu.
- **When the seat is released for good:** a message "Sam left, the stack passes to Alex" (decision 5), the players row re-packs, and the dot is removed.
- Countdowns come from the server's clock (seconds left), not a client timer, so every device agrees.

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
- [x] Event batching in `Net`: collect engine signals per action, flush as one `_client_events` RPC; client replays them in order. Test: a Purple move arrives as one batch containing both cards.
- [x] The UI picks its presenter (parent if it has `act_move`, else `Net`) instead of always using `get_parent()`.
- [x] Online game scene (`scenes/online_game.tscn`) that binds the UI to `Net`; the UI asks the server for a snapshot (`request_sync`) when it appears.
- [x] A temporary "Play online (auto room)" button on the start screen: connect to an address from a text field, `join_room("auto", name)`.
- [x] Verified: a windowed client joined a real server, received the snapshot, sent a guess and got the card and penalty back. Still to do by hand: two real windows playing a full game.

### 2B. Lobby, invite codes, names
- [x] `Room.state`, `Room.host_peer`, names in the roster, host-only `rpc_start_game` / `rpc_end_game`, minimum-player check.
- [x] Engine created at start with the final seat count; no `seat_count` changes from joins.
- [x] Names: typed once and saved on the device (`user://`), duplicates get a number suffix.
- [x] RPCs: `rpc_create_room(name, is_public)` replies with room info and code; `rpc_join_room(code_or_id, name)`; `rpc_leave_room`; `_client_lobby` roster broadcast on every change.
- [x] Join-code throttling and name sanitising.
- [x] Screens: Play menu, Host (shows the code and a copy/share button), Join (code entry), public room list, lobby (roster, Start for the host).
- [x] Tests: `test_room_manager.gd` for states, host rules, throttling; integration test with 3 clients through create, join by code, start.

### 2C. Late join, reconnect, disconnect handling
- [x] `_client_snapshot`; a mid-game joiner is seated at the end of the turn order (decision 2), so the engine must be able to grow `seat_count` without disturbing the current seat or stack.
- [x] Session tokens (kept in memory while the app runs, not saved to disk, so an app restart cannot rejoin), seat holding (60 s), the 20 s turn wait and skip, and the leaves-for-good rule (decision 5).
- [x] The waiting-for-player UI: `_client_player_status` message, greyed pulsing dot, countdown banner, "Reconnecting..." overlay, "removed" screen (see the section above).
- [x] Remove the obsolete `_awaiting_pass` backlog item (Ride no longer exists, so pass is never a locked state).
- [x] Tests: drop and reconnect a client mid-game and compare its snapshot with the server's table; a late joiner is seated last and sees the same stack; the 20 s skip and 60 s release fire on time (use a test clock, not real waiting); the status messages carry decreasing seconds (unit test). The hidden-deck check is its own scenario (HIDDEN-DECK).

### 2D. Remote hosting
- [ ] Port from a command-line argument (`-- --port 9000`) and a small startup log (address, port, room count, player count).
- [ ] Server address and port in the join UI, with the last used address remembered.
- [ ] Run on a Linux VPS with the Godot binary and the project folder (no export needed); optionally a Linux export preset. A short deploy guide (`docs/superpowers/RUN_MULTIPLAYER.md`): open UDP 9000, run as a service, restart on crash.
- [ ] Optional: a health print and basic logging (room count, player count).
- [ ] Test the latency feel from a phone on mobile data; check that the pass and Purple animations hold with ~150 ms of lag.

### 2E. Polish
- [x] Turn banner and "you're up" use names; show who is holding the stack.
- [ ] Later add-on, not this iteration: same-Wi-Fi hosting with LAN discovery (decision 3).
- [x] Connection lost / reconnecting overlay (2C), and the idle rule with its removal message (skip after 60 s, 30 s, 15 s, then remove).
- [x] Sound, buzz and taskbar flash on your turn. A fully sleeping phone cannot be woken without a native push-notification plugin, so that part is not done.
- [x] Update `CLAUDE.md` and `RUN_MULTIPLAYER.md` when each phase lands.
- [x] Also done: the hidden-deck integration check, and saving the session so a restarted app can rejoin.

## Verification
- `bash tests/run_net_integration.sh` stays the gate: it must keep passing, and grows scenarios per phase (3 clients, code join, reconnect, late join).
- The existing rule that no deck contents may appear in client logs is checked in every scenario.
- Manual check each phase: two or three real windows, then a real phone against a remote server for 2D.

## Risks
- **Phone backgrounding:** mobile OSes suspend the app and drop UDP; reconnect with the session token has to be reliable before this is fun in practice (hence 2C before 2D). The 60-second hold and the visible countdown exist for exactly this.
- **UDP and NAT:** a dedicated public server avoids it. A same-Wi-Fi host mode (later) works without a server; hosting over the internet from a phone is not planned.
- **UI queue timing:** the batching in 2A is what makes the Purple pair and the in-order animations safe over the network, so it goes first.
