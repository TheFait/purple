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
