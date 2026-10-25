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

echo "--- Purple arrives as one batch ---"
godot --headless --path . --script res://tests/net_server_boot.gd >/tmp/pp_server3.log 2>&1 &
SERVER3=$!
sleep 2
godot --headless --path . --script res://tests/net_client_purple.gd >/tmp/pp_purple.log 2>&1
kill "$SERVER3" 2>/dev/null
grep -E "OK:|FAIL:|RESULT" /tmp/pp_purple.log
grep -q "RESULT: PASS" /tmp/pp_purple.log && echo "BATCH: PASS" || echo "BATCH: FAIL"

echo "--- late joiner gets a snapshot ---"
godot --headless --path . --script res://tests/net_server_boot.gd >/tmp/pp_server4.log 2>&1 &
SERVER4=$!
sleep 2
godot --headless --path . --script res://tests/net_client_late.gd -- first >/tmp/pp_late1.log 2>&1 &
FIRST=$!
sleep 3
godot --headless --path . --script res://tests/net_client_late.gd -- late >/tmp/pp_late2.log 2>&1
wait "$FIRST"
kill "$SERVER4" 2>/dev/null
grep -E "OK:|FAIL:|RESULT" /tmp/pp_late2.log
if grep -q "RESULT: PASS" /tmp/pp_late1.log && grep -q "RESULT: PASS" /tmp/pp_late2.log; then
  echo "SNAPSHOT: PASS"
else
  echo "SNAPSHOT: FAIL"
fi

echo "--- a player disconnects ---"
godot --headless --path . --script res://tests/net_server_boot.gd >/tmp/pp_server5.log 2>&1 &
SERVER5=$!
sleep 2
godot --headless --path . --script res://tests/net_client_leave.gd -- stay >/tmp/pp_stay.log 2>&1 &
STAY=$!
sleep 1.5
godot --headless --path . --script res://tests/net_client_leave.gd -- leave >/tmp/pp_leave.log 2>&1
wait "$STAY"
kill "$SERVER5" 2>/dev/null
grep -E "OK:|FAIL:|RESULT" /tmp/pp_stay.log
if grep -q "RESULT: PASS" /tmp/pp_stay.log && grep -q "RESULT: PASS" /tmp/pp_leave.log; then
  echo "DISCONNECT: PASS"
else
  echo "DISCONNECT: FAIL"
fi

echo "--- a pass reaches the other player ---"
godot --headless --path . --script res://tests/net_server_boot.gd >/tmp/pp_server6.log 2>&1 &
SERVER6=$!
sleep 2
godot --headless --path . --script res://tests/net_client_pass.gd -- passer >/tmp/pp_passer.log 2>&1 &
PASSER=$!
sleep 1
godot --headless --path . --script res://tests/net_client_pass.gd -- other >/tmp/pp_other.log 2>&1 &
OTHER=$!
wait "$PASSER" "$OTHER"
kill "$SERVER6" 2>/dev/null
grep -E "OK:|FAIL:|RESULT" /tmp/pp_passer.log /tmp/pp_other.log
if grep -q "RESULT: PASS" /tmp/pp_passer.log && grep -q "RESULT: PASS" /tmp/pp_other.log; then
  echo "PASS-NOTICE: PASS"
else
  echo "PASS-NOTICE: FAIL"
fi

echo "--- lobby: private room, invite code, host rules, throttle ---"
godot --headless --path . --script res://tests/net_server_boot.gd >/tmp/pp_server7.log 2>&1 &
SERVER7=$!
sleep 2
godot --headless --path . --script res://tests/net_client_lobby.gd -- host >/tmp/pp_lhost.log 2>&1 &
LHOST=$!
sleep 1
godot --headless --path . --script res://tests/net_client_lobby.gd -- guest >/tmp/pp_lguest.log 2>&1 &
LGUEST=$!
godot --headless --path . --script res://tests/net_client_lobby.gd -- intruder >/tmp/pp_lintr.log 2>&1
wait "$LHOST" "$LGUEST"
kill "$SERVER7" 2>/dev/null
grep -E "OK:|FAIL:|RESULT" /tmp/pp_lhost.log /tmp/pp_lguest.log /tmp/pp_lintr.log
if grep -q "RESULT: PASS" /tmp/pp_lhost.log && grep -q "RESULT: PASS" /tmp/pp_lguest.log && grep -q "RESULT: PASS" /tmp/pp_lintr.log; then
  echo "LOBBY: PASS"
else
  echo "LOBBY: FAIL"
fi

for MODE in resume turnskip; do
  echo "--- dropped connection: $MODE ---"
  godot --headless --path . --script res://tests/net_server_boot.gd >/tmp/pp_server8.log 2>&1 &
  SERVER8=$!
  sleep 2
  godot --headless --path . --script res://tests/net_client_hold.gd -- host $MODE >/tmp/pp_hhost.log 2>&1 &
  HHOST=$!
  sleep 1
  godot --headless --path . --script res://tests/net_client_hold.gd -- guest $MODE >/tmp/pp_hguest.log 2>&1
  wait "$HHOST"
  kill "$SERVER8" 2>/dev/null
  grep -E "OK:|FAIL:|RESULT" /tmp/pp_hhost.log /tmp/pp_hguest.log
  if grep -q "RESULT: PASS" /tmp/pp_hhost.log && grep -q "RESULT: PASS" /tmp/pp_hguest.log; then
    echo "HOLD-$MODE: PASS"
  else
    echo "HOLD-$MODE: FAIL"
  fi
done

echo "--- the server never reveals an undrawn card ---"
godot --headless --path . --script res://tests/net_server_boot.gd >/tmp/pp_server9.log 2>&1 &
SERVER9=$!
sleep 2
godot --headless --path . --script res://tests/net_client_hidden.gd >/tmp/pp_hidden.log 2>&1
kill "$SERVER9" 2>/dev/null
grep -E "OK:|FAIL:|RESULT" /tmp/pp_hidden.log
grep -q "RESULT: PASS" /tmp/pp_hidden.log && echo "HIDDEN-DECK: PASS" || echo "HIDDEN-DECK: FAIL"

echo "--- idle players are skipped, then removed ---"
godot --headless --path . --script res://tests/net_server_boot.gd -- idle >/tmp/pp_server10.log 2>&1 &
SERVER10=$!
sleep 2
godot --headless --path . --script res://tests/net_client_idle.gd -- first >/tmp/pp_idle1.log 2>&1 &
IDLE1=$!
sleep 1
godot --headless --path . --script res://tests/net_client_idle.gd -- second >/tmp/pp_idle2.log 2>&1 &
IDLE2=$!
wait "$IDLE1" "$IDLE2"
kill "$SERVER10" 2>/dev/null
grep -E "OK:|FAIL:|RESULT" /tmp/pp_idle1.log /tmp/pp_idle2.log
if grep -q "RESULT: PASS" /tmp/pp_idle1.log && grep -q "RESULT: PASS" /tmp/pp_idle2.log; then
  echo "IDLE: PASS"
else
  echo "IDLE: FAIL"
fi

echo "--- a restarted app rejoins from its saved session ---"
godot --headless --path . --script res://tests/net_server_boot.gd >/tmp/pp_server11.log 2>&1 &
SERVER11=$!
sleep 2
godot --headless --path . --script res://tests/net_client_cold.gd >/tmp/pp_cold.log 2>&1
kill "$SERVER11" 2>/dev/null
grep -E "OK:|FAIL:|RESULT" /tmp/pp_cold.log
grep -q "RESULT: PASS" /tmp/pp_cold.log && echo "COLD-REJOIN: PASS" || echo "COLD-REJOIN: FAIL"
