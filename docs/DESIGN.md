# Regicide — Design Document

*Living document. Numbers referenced here live in `scripts/core/game_data.gd`.*

## Pitch

Fifty against fifty. Everyone starts with empty hands. Chop, mine, build, arm up, and
steal the other team's crown from the heart of their base. A capture-the-flag match where
the "flag" is defended by whatever the enemy managed to build.

## Pillars

1. **Start from nothing.** Every match is a fresh build-up; nobody spawns with gear.
2. **Readable chaos.** 100 players needs a simple, legible look: flat colors, team-colored
   bodies and structures, big silhouettes.
3. **Combat pays.** Fighting earns gold; gold buys the interesting stuff. Turtling only
   gets you so far.
4. **The crown is everything.** All systems feed into attacking or defending one object.

## Core loop

```
gather → craft basics → fight / defend → earn gold → unlock blueprints → craft advanced
   ↑                                                                        │
   └──────────────── push for the enemy crown, protect your own ←───────────┘
```

## Teams & map

- 2 teams, up to 50 each, auto-balanced on join.
- Map 200 × 360 m, point-mirrored so both sides are identical. Each base has a crown
  pedestal near the back and a spawn behind it.
- Resource bands: trees everywhere, stone across each half, iron toward the middle,
  **magic ore only in the center strip** — the contested zone.
- No building within 6 m of a pedestal, so a crown can be fortified but never sealed in.

## Resources

| Resource | Where | Gathered with |
| --- | --- | --- |
| Wood | Everywhere | Anything (axe is fastest) |
| Stone | Each half | Anything (pickaxe is fastest) |
| Iron | Toward the middle | Pickaxe |
| Magic ore | Center only | Pickaxe |

Nodes shrink as they're harvested, vanish when empty, and regrow after 60–120 s.

## Items

**Free to craft:** Stone Axe, Pickaxe, Wooden Club, Iron Sword, Shortbow, Arrows (×5).

Arrows fly in a real arc (the server simulates the flight), are blocked by enemy walls
and trees, and are used up even on a miss.

**Blueprints (gold):**

| Blueprint | Gold | What it does |
| --- | --- | --- |
| Health Potion | 75 | Heal 50 |
| Spike Trap | 100 | Hurts enemies standing on it; doesn't block movement |
| Crossbow | 175 | 42 damage, flat and fast, slow reload |
| War Hammer | 150 | 45 damage, slow, wrecks walls |
| Horse Saddle | 150 | Mounted: 1.7× speed until death (no bonus while carrying a crown) |
| Skillbook: Gatherer | 150 | +50% gather yield for the match |
| Scroll of Fireball | 200 | Aimed exploding projectile; hurts players and structures |
| Skillbook: Vigor | 250 | +25 max health for the match |
| Ballista | 300 | Auto-turret: shoots the nearest enemy in 32 m |

Unlocks are per player and last until the match ends.

## Crown rules

- Touch the enemy crown (home or dropped) to pick it up. One crown per carrier.
- Carriers move at 0.8× speed and get no mount bonus.
- Carrier dies or disconnects → crown drops where they stood.
- Owners touching their dropped crown return it instantly (+25g). Dropped crowns
  auto-return after 45 s.
- **Capture:** carry the enemy crown to your own pedestal *while your own crown is home*.
- First to **3** captures wins. Match resets after 15 s: scores, inventories, gold,
  unlocks, structures and resources all reset.

## Economy

| Event | Gold |
| --- | --- |
| Kill | 50 to the killer (ballista kills credit its builder) |
| Capture | 250 to the carrier, 75 to every teammate |
| Return own crown | 25 |

## Building

Press **Q** for build mode: the hotbar switches to building pieces, a see-through ghost
snaps to the grid where you aim (green = OK, red = not), and left click places it.
Pieces are paid for straight from your resources, with no crafting step.

**Grid:** 4 × 4 m cells, 3 m levels, up to 6 levels high. Walls, doors and ladders sit on
cell edges and always face you; floors, stairs, roofs and free-standing pieces fill cells.

| Piece | Cost | Notes |
| --- | --- | --- |
| Wood Wall | 8 wood | 300 hp |
| Stone Wall | 10 stone | 800 hp |
| Arrow Slit Wall | 12 stone | Chest-high gap: shoot out, hard to shoot in |
| Wood Door | 12 wood | Your team walks through; enemies can't |
| Wood / Stone Floor | 6 wood / 8 stone | Foundations on the ground, floors up high |
| Wood Stairs | 8 wood | Climb one level |
| Wood Roof | 6 wood | Sloped; blocks arrows and fireballs from above |
| Ladder | 4 wood | Lean on any wall — including the enemy's — and climb over |
| Spike Trap | 6 wood, 3 iron | Blueprint (100g). Hurts enemies standing on it |
| Ballista | 25 wood, 10 iron | Blueprint (300g). Auto-turret; put it on a tower |

**Support:** everything must connect to the ground. Walls stand on the ground, a wall
below, or a floor. Floors rest on walls beneath them, or reach one cell out from a floor
that does. Stairs and ballistas need a floor or the ground. Ladders lean on a wall, stand
on a ladder, or stand on a floor. Destroy a support and whatever it held collapses —
siege the base of a tower to bring it down.

**Limits:** no building within 6 m of a crown pedestal, nor on top of a player.
Melee can only hit pieces at your height (you can't chop a second-storey wall from the
ground — bring a ladder or stairs).

## Test bots

Bots are a **testing tool** — real matches are people. They're off by default; "Test
bots" on the menu (or `--bots N`) fills empty slots for solo testing and for the
automated match soak test.

Humans joining replace bots. Bots use exactly the same server requests as players, so
they obey every cooldown, cost and range rule. Per 10 bots:

| Role | Count | Behavior |
| --- | --- | --- |
| Gatherer | 4 | Builds the economy (tools, sword, bow, skillbooks), joins the attack later |
| Attacker | 4 | Arms up, rallies, charges in waves around a flank, ladders over walls |
| Defender | 2 | Builds a grid wall ring (with gaps), ballistas and traps around the crown |

Everyone chases a thief who gets close; attackers hunt thieves anywhere (this breaks
"both crowns stolen" standoffs). A 50v50 bot match typically ends 3–1 in 8–10 minutes.

## Combat feel

Hit flash and floating damage numbers, death topple, hit markers on the crosshair, a red
screen flash when hurt, debris and wobble when gathering, damage bars on structures,
arrow arcs, and synthesized sound effects for every action plus crown jingles.

## Fair play

Movement is client-owned for responsiveness; the server snaps back anyone moving faster
than a horse can. Players get 3 s of spawn protection.

## Open questions

- Should dying drop some carried resources (loot to fight over)?
- Team-wide vs per-player unlocks? (Per-player today.)
- Repairing structures; showing structure health.
- Blocking/parrying for melee depth.
- Should a stolen crown ping its location on the enemy's map?
- Classes / roles, or keep it fully sandbox?

## Roadmap

**Next up**
- Playtest with real people and tune: gather speed, prices, crown carry speed, bot skill.
- Bot difficulty setting; smarter bot pathing around walls.
- Repairing pieces, upgrading wood to stone in place, rotating pieces manually.
- More pieces: half walls, windows, battlements, drawbridge, siege ram, catapult.
- Blocking, sprint stamina, a few more spells (heal aura, frost bolt).
- Death drops some resources; respawn wave timer.

**Later**
- Interest management (only replicate nearby players) for 100 humans over the internet.
- Server-side hit validation against lag-compensated positions.
- MultiMesh rendering for resource nodes.
- Lobby / server browser, persistent progression, cosmetics.
- Real art and audio pass (still low-poly and readable).
