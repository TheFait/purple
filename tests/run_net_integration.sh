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
