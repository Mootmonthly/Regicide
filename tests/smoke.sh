#!/usr/bin/env bash
# Multiplayer smoke test: boots a headless dedicated server, connects two headless
# clients, and fails on any script error. Usage: GODOT=/path/to/godot tests/smoke.sh
set -u
GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/.."
LOG_DIR="$(mktemp -d)"
PORT=$((25000 + RANDOM % 5000))

"$GODOT" --headless --path . --quit-after 600 -- --server --port "$PORT" >"$LOG_DIR/server.log" 2>&1 &
SERVER=$!
sleep 2
"$GODOT" --headless --path . --quit-after 300 -- --join 127.0.0.1 --port "$PORT" --name Alice >"$LOG_DIR/alice.log" 2>&1 &
A=$!
"$GODOT" --headless --path . --quit-after 300 -- --join 127.0.0.1 --port "$PORT" --name Bob >"$LOG_DIR/bob.log" 2>&1 &
B=$!
wait $A $B
wait $SERVER

status=0
for f in "$LOG_DIR"/*.log; do
	if grep -qE "SCRIPT ERROR|Parse Error|ERROR:" "$f"; then
		echo "== errors in $(basename "$f") =="
		grep -E -A3 "SCRIPT ERROR|Parse Error|ERROR:" "$f" | head -40
		status=1
	fi
done
for name in Alice Bob; do
	if ! grep -q "$name joined" "$LOG_DIR/server.log"; then
		echo "Server never saw $name join"
		status=1
	fi
done
if [ $status -eq 0 ]; then
	echo "Smoke test passed (logs in $LOG_DIR)"
else
	echo "--- server log ---"; cat "$LOG_DIR/server.log"
fi
exit $status
