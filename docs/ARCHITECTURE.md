# Architecture

## Networking model

Godot's high-level multiplayer over ENet. Peer 1 is the server: either a dedicated
headless server or a host who also plays.

| State | Owner | How it reaches others |
| --- | --- | --- |
| Player position, facing, equipped item | The player's own peer (server for bots) | `OwnerSync` (MultiplayerSynchronizer, 20 Hz) |
| Health, alive, crown carried, mounted | Server | `ServerSync` (on change) |
| Inventory, gold, unlocks | Server | `GameMode._private` RPC to that player only |
| Scores, crown states, scoreboard, match over | Server | `GameMode` broadcast RPCs |
| Hit effects, arrows, structure damage | Server | Unreliable `World` RPCs; damage numbers come from the synced health change |
| Players, structures exist | Server | `MultiplayerSpawner` with custom spawn functions |
| Resource nodes | Generated locally from a seed | Only `(index, amount)` changes are sent |

Movement is client-authoritative for responsiveness. **Everything else is a request**:
clients call `GameMode.request(...)` (`request_primary`, `request_craft`,
`request_unlock`), and the server checks ownership, cooldowns, range and cost before
changing anything. The host's own requests take the same path, run as local calls.

## Building

`BuildGrid` (pure, unit tested) turns a crosshair hit into a slot `{i, j, level, axis,
rot, side}`, gives each slot a key, a transform, and the support rules. The client sends
`request_build(item, slot)`; the server sanitizes the slot, checks reach, support,
occupancy, crown zone and players in the way, charges resources, then spawns a
`Structure`. Every peer keeps `World.pieces` (slot key → piece) for ghost previews and
validation. When a piece is destroyed the server recomputes which pieces are still
connected to the ground (`BuildGrid.supported_keys`) and drops the rest.

`Structure.piece_boxes()` defines each piece as boxes (solid and/or visual), used for
collision, the ghost, arrow/fireball blocking (`blocks_point`), and melee reach.

## Terrain

`Terrain` (pure, unit tested) builds a 2 m heightmap from the map seed with
`FastNoiseLite`, averaged with its own mirror image so the map is point-symmetric, then
flattens the bases and carves the river. Every peer builds the same samples; the
collider (`HeightMapShape3D`), the vertex-colored mesh, gameplay checks (`Terrain.height`
for arrows, boulders, crowns, resource placement, building support) and the minimap all
read those samples.

Trees are drawn with one `MultiMesh` per part across the whole map (~1,200 trees in a
handful of draw calls); each `ResourceNode` keeps only a trunk collider and its state.

Physics uses **Jolt** (built into Godot 4.4): with 100 character bodies on a heightmap it
halves server frame time versus Godot Physics (~12 ms vs ~24 ms per tick in the 50v50
soak).

## Moving and stateful pieces

Drawbridges (open/closed) and battering rams (position) have state beyond their spawn
data. Changes are broadcast (`World.piece_open`, `World.vehicle_pose`), and the welcome
snapshot carries `World.piece_states()` for late joiners. Moving parts (drawbridge plank,
catapult arm) live in a rotating "leaf" node whose collision moves with it.

## Bots

Bots are ordinary `Player` nodes with negative peer ids, owned by the server. A
`BotBrain` child (server only) writes the same movement intent (`move_input`,
`wants_sprint`, `wants_jump`) a keyboard would and acts through `GameMode.perform_*()` —
the same functions the human RPC wrappers call. Messages to negative peer ids are
silently dropped.

## Time

`GameMode.clock` is game time advanced every physics tick on every peer. All cooldowns,
crown timers and bot waves use it (not wall-clock time), which is what lets the soak test
fast-forward a 10-minute match with `--fixed-fps`.

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
- `scripts/game/bot_brain.gd` — bot roles, decisions, steering, actions.
- `autoload/sfx.gd` — sound effects synthesized at startup (no audio files).
- `scripts/core/crown_rules.gd`, `inventory.gd` — pure logic, unit tested.

## Physics layers

1 world · 2 players · 3 structures · 4 resources · 5 Azure doors · 6 Crimson doors.
Players collide with the *enemy* team's door layer only. Ladders and traps have no
collision (ladders are detected by position for climbing). Players don't collide with each
other (100 bodies in chokepoints would gridlock). Spike traps have no collision.

## Scaling notes for 100 players

- Synchronizers broadcast to everyone; add visibility filters (interest management)
  before running full matches over the internet.
- Server hit detection is a linear scan over players/structures/resources per swing,
  which is fine at this size; switch to a spatial grid if profiling says so.
