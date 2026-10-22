# Architecture

## Networking model

Godot's high-level multiplayer over ENet. Peer 1 is the server: either a dedicated
headless server or a host who also plays.

| State | Owner | How it reaches others |
| --- | --- | --- |
| Player position, facing, equipped item | The player's own peer | `OwnerSync` (MultiplayerSynchronizer, 20 Hz) |
| Health, alive, crown carried, mounted | Server | `ServerSync` (on change) |
| Inventory, gold, unlocks | Server | `GameMode._private` RPC to that player only |
| Scores, crown states, match over | Server | `GameMode` broadcast RPCs |
| Players, structures exist | Server | `MultiplayerSpawner` with custom spawn functions |
| Resource nodes | Generated locally from a seed | Only `(index, amount)` changes are sent |

Movement is client-authoritative for responsiveness. **Everything else is a request**:
clients call `GameMode.request(...)` (`request_primary`, `request_craft`,
`request_unlock`), and the server checks ownership, cooldowns, range and cost before
changing anything. The host's own requests take the same path, run as local calls.

## Join flow

1. Menu sets `Net.mode`, loads `world.tscn`.
2. `World._ready` builds the arena, sets spawn functions, then calls `Net.start()`.
   Loading the world *before* connecting means spawner/synchronizer traffic always has a
   destination.
3. Client connects → `register_player(name)` → server picks the smaller team, sends
   `_welcome(seed, snapshot)`, spawns the player, and pushes private state.
4. Client generates the same map from the seed and applies the snapshot (scores, crowns,
   depleted resources).

## Key scripts

- `scripts/core/game_data.gd` — every number and item definition.
- `scripts/game/game_mode.gd` — all match rules (server) plus client-side mirrors of
  replicated state, with signals for the HUD.
- `scripts/world/world.gd` — arena, lookups, spawners, resource sync, effects.
- `scripts/player/player.gd` — movement, camera, input → requests, visuals.
- `scripts/core/crown_rules.gd`, `inventory.gd` — pure logic, unit tested.

## Physics layers

1 world · 2 players · 3 structures · 4 resources. Players don't collide with each other
(100 bodies in chokepoints would gridlock).

## Scaling notes for 100 players

- Synchronizers broadcast to everyone; add visibility filters (interest management)
  before running full matches over the internet.
- Server hit detection is a linear scan over players/structures/resources per swing,
  which is fine at this size; switch to a spatial grid if profiling says so.
