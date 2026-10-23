#!/usr/bin/env bash
# One-step install on Ubuntu/Debian: copies the server to /opt/regicide, runs it as the
# "regicide" user under systemd (starts on boot, restarts if it stops), and opens the port.
# Run from the unpacked server folder:  sudo ./install.sh
set -euo pipefail
if [ "$(id -u)" -ne 0 ]; then echo "Run with sudo: sudo ./install.sh"; exit 1; fi
cd "$(dirname "$0")"
id regicide >/dev/null 2>&1 || useradd --system --create-home --shell /usr/sbin/nologin regicide
mkdir -p /opt/regicide
cp Regicide.x86_64 run-server.sh /opt/regicide/
[ -f /opt/regicide/server.cfg ] || cp server.cfg /opt/regicide/   # keep an existing config on updates
chmod +x /opt/regicide/Regicide.x86_64 /opt/regicide/run-server.sh
chown -R regicide:regicide /opt/regicide
cp regicide.service /etc/systemd/system/regicide.service
systemctl daemon-reload
systemctl enable regicide >/dev/null
systemctl restart regicide
PORT=$(grep -E '^port=' /opt/regicide/server.cfg | cut -d= -f2 | tr -d ' "')
if command -v ufw >/dev/null && ufw status | grep -q active; then ufw allow "${PORT:-24565}/udp" >/dev/null; echo "Opened UDP ${PORT:-24565} in ufw."; fi
echo "Regicide server installed and running on UDP port ${PORT:-24565}."
echo "  Settings:  /opt/regicide/server.cfg   (then: sudo systemctl restart regicide)"
echo "  Logs:      journalctl -u regicide -f"
echo "  Stop:      sudo systemctl stop regicide"
