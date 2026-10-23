#!/usr/bin/env bash
# Start the Regicide dedicated server. Settings live in server.cfg next to this script
# (or pass another file: ./run-server.sh --config /path/to/server.cfg).
cd "$(dirname "$0")"
CONFIG="./server.cfg"
if [ "${1:-}" = "--config" ] && [ -n "${2:-}" ]; then CONFIG="$2"; shift 2; fi
exec ./Regicide.x86_64 --headless -- --server --config "$CONFIG" "$@"
