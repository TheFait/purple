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

- `Net._on_peer_disconnected` calls `GameEngine.reconcile_seats(new_count)`, which
  clamps `seat_count` and `current_seat` so the turn rotation never lands on a vacated
  seat index — preventing the room from deadlocking.
- Each remaining peer receives a fresh `_client_seated` RPC so their cached `_my_seat`
  reflects the re-packed indices after the leaver's slot is removed.

**Not yet implemented (Iteration 2):** full reconnection flow and late-joiner state sync
(the stack, contributions and turn). What happens when the active player leaves for good is
an open decision in the Iteration 2 plan. (The old `_awaiting_pass` edge case is gone: Ride
was removed, so passing never locks the game.)

## What is Iteration 2?

See `plans/2026-10-23-purple-post-multiplayer-iter2.md`: wire the GUI client to `Net`, batch
events per action, lobby with invite codes and names, late join and reconnect, remote hosting.

## Notes

- The server is authoritative: the deck and undrawn cards never leave it. Clients
  receive only individually revealed cards via `card_revealed` events.
- Seats are assigned in join order; first joiner gets seat 0.
- The auto public room accepts up to 12 players (Iteration 1 targets 2).
