# Running Purple & Post multiplayer (Iteration 1, local)

## Automated integration test (recommended — the only verified path in iteration 1)

```bash
bash tests/run_net_integration.sh
# expect: INTEGRATION: PASS  and  GAMEPLAY: PASS
```

This spins up a headless server and 2 headless clients, verifies both clients receive
distinct seats (0 and 1), confirms the second client sees the first client's moves (a wrong guess keeps the turn with the same player), and checks that no deck
contents ever reach the client logs (server is authoritative).

## Start the dedicated server (headless)

```bash
godot --headless --path . server/server.tscn
# prints: SERVER: Purple & Post listening on 9000
```

Transport: ENet (UDP), port 9000 (`Net.DEFAULT_PORT`).

## Not yet wired in Iteration 1 — GUI client

`scenes/game.tscn` currently runs in **offline mode** only. Nothing in the scene or
`GameManager` autoload connects it to the server. The game plays locally using the
same `GameEngine` that the server uses, but it does not join a room or talk to the
dedicated server.

Connecting the GUI client to the server is the **first task of Iteration 2**.

## Mid-game disconnect (implemented)

When a player disconnects mid-game, the server now reconciles the room automatically:

- `Net._on_peer_disconnected` tells the room who left (`left` event, shown as
  "<name> has disconnected") and calls `GameEngine.remove_seat(index)`, which closes the gap in
  the turn order: the same player stays up if someone ahead of them left, and if the leaver held
  the turn the stack passes to whoever takes their place (no drinks).
- Each remaining peer receives a fresh `_client_seated` RPC so their cached `_my_seat`
  reflects the re-packed indices after the leaver's slot is removed.

**Dropped connections (Iteration 2C):** in a running game a disconnect no longer removes the
player. Their seat is held for 60 seconds; if it is their turn the table waits 20 seconds and
then skips them (the stack passes on, no drinks). Everyone sees a greyed pulsing dot and a
countdown, and the dropped player's client keeps retrying and shows "Reconnecting..." until it
gets the seat back (the table is replayed from a snapshot) or is told it was removed. Lobbies
still remove a disconnected player immediately.

**Idle players:** a connected player who sits on their turn is skipped after 60 seconds, then
30, then 15, and is removed after the third skip ("removed for inactivity"). Any action clears
their strikes, and the last 10 seconds are shown to the whole table.

**Restarting the app:** the game you were in is remembered for about two minutes; the online
menu then offers REJOIN YOUR GAME.

**What the server never sends:** the deck. `tests/net_client_hidden.gd` proves no client is
shown a card before it is drawn (it fails against a server that leaks the next card). (The old `_awaiting_pass` edge case is gone: Ride
was removed, so passing never locks the game.)

## What is Iteration 2?

See `plans/2026-10-23-purple-post-multiplayer-iter2.md`: wire the GUI client to `Net`, batch
events per action, lobby with invite codes and names, late join and reconnect, remote hosting.

## Notes

- The server is authoritative: the deck and undrawn cards never leave it. Clients
  receive only individually revealed cards via `card_revealed` events.
- Seats are assigned in join order; first joiner gets seat 0.
- The auto public room accepts up to 12 players (Iteration 1 targets 2).
