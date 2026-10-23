# Hosting a Regicide dedicated server

A dedicated server runs the match on its own (no player window) so friends or the public
can join any time. It runs on Linux. Players connect with the normal game: **Server
address** = the server's IP, then **Join**.

## Quickest: a cloud server that sets itself up

1. Make an account with a VPS provider, e.g. [Hetzner Cloud](https://www.hetzner.com/cloud)
   (roughly €7–15/month for 4 vCPU / 8 GB) or DigitalOcean.
2. Create a server: **Ubuntu 24.04**, 4 vCPU / 8 GB, in a region near your players.
3. Find the **Cloud config / User data** box (under advanced options) and paste the
   contents of [`server/cloud-init.yaml`](../server/cloud-init.yaml).
4. Create it. A couple of minutes later the Regicide server is running. Players join with
   the server's public IP shown in the provider's dashboard.
5. The script turns on the server's own firewall (ufw) with SSH and UDP 24565 open. If
   you also add a provider firewall, allow inbound **UDP 24565** there too.

To change settings later, SSH in and edit `/opt/regicide/server.cfg` (see below).

## 1. Get a machine

Any always-on Linux box works: a VPS (Hetzner, DigitalOcean, Vultr, OVH, Linode…), a home
server, or a spare PC. Ubuntu 22.04/24.04 or Debian 12 are what the install script expects.

Rough sizing:

| Players | CPU | RAM |
| --- | --- | --- |
| up to ~20 | 2 vCPU | 2 GB |
| full 50 v 50 | 4 vCPU (fast cores) | 4 GB |

Bandwidth matters more than disk; pick a region close to your players.

## 2. Download and unpack

From the [Releases page](https://github.com/Mootmonthly/Regicide/releases), get
`Regicide-server-linux.tar.gz`. On the server:

```sh
wget https://github.com/Mootmonthly/Regicide/releases/latest/download/Regicide-server-linux.tar.gz
tar -xzf Regicide-server-linux.tar.gz
cd regicide-server
```

The folder holds the game (`Regicide.x86_64`), `server.cfg`, `run-server.sh`,
`install.sh`, a systemd unit and Docker files.

**Players must run the same version as the server.** When you update the server, tell
players to download the matching release (they get a clear "version mismatch" message
otherwise).

## 3. Pick one way to run it

### A. Install as a service (recommended)

```sh
sudo ./install.sh
```

This copies the server to `/opt/regicide`, runs it as a `regicide` user under systemd
(starts on boot, restarts if it crashes), and opens the UDP port in `ufw` if it's active.

- Settings: `sudo nano /opt/regicide/server.cfg`, then `sudo systemctl restart regicide`
- Log: `journalctl -u regicide -f`
- Stop / start: `sudo systemctl stop regicide` / `sudo systemctl start regicide`

### B. Docker

```sh
docker compose up -d
```

Settings are in `./config/server.cfg` (written on first start); after editing,
`docker compose restart`. Log: `docker compose logs -f`.

### C. Just run it

```sh
./run-server.sh
```

Stops when you close the terminal (use `tmux` or `screen` to keep it going).

## 4. Open the port

Players connect over **UDP 24565** (or whatever `port` you set).

- **VPS:** allow inbound UDP 24565 in the provider's firewall / security group if it has
  one, and in `ufw` (`sudo ufw allow 24565/udp`; the install script does this for you).
- **Home server:** forward UDP 24565 on your router to the server's local IP. Players use
  your public IP (search "what is my IP" from that network).

## 5. Settings (`server.cfg`)

| Key | Default | What it does |
| --- | --- | --- |
| `name` | `Regicide server` | Server name, shown in the log and to players on join |
| `motd` | welcome text | Message players see when they join |
| `port` | `24565` | UDP port |
| `password` | empty | Set one to make the server private; players type it on the main menu |
| `max_players` | `100` | Most human players at once (two teams of 50 = 100) |
| `min_players` | `2` | Players needed before a match starts; until then it's a warm-up lobby. `0` = no lobby |
| `lobby_countdown` | `60` | Seconds of countdown once enough players are on |
| `bots_per_team` | `0` | Test bots that fill empty slots (0 for real matches) |

Restart the server after changing anything. Command-line flags (`--port`, `--password`,
`--bots`) override the file.

## How the server behaves

- The server waits in a **warm-up lobby** until `min_players` people are on: you can roam,
  gather and fight, but the clock doesn't run and crowns can't be taken. Then a countdown
  starts (it stops again if players leave), and the match begins on a fresh map.
- Matches run on their own: first to the capture limit, or most crowns after 30 minutes
  (ties go to overtime). Afterwards the server goes back to the lobby.
- When the last player leaves, the server resets and waits in the lobby again.
- Every 5 minutes the log prints a status line (players, score, time left).

## Updating

Download the new release, unpack it, and run `sudo ./install.sh` again (your
`server.cfg` is kept). With Docker: replace the files, then `docker compose up -d --build`.
