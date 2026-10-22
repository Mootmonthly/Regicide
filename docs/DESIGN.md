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

**Free to craft:** Stone Axe, Pickaxe, Wooden Club, Iron Sword, Shortbow, Arrows (×5),
Wooden Wall, Stone Wall, Wooden Gate (your team walks through it, enemies can't).

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

## Bots

Empty slots are filled with server-side bots ("Team size" in the menu, `--bots N` on the
command line). Humans joining replace bots. Bots use exactly the same server requests as
players, so they obey every cooldown, cost and range rule. Per 10 bots:

| Role | Count | Behavior |
| --- | --- | --- |
| Gatherer | 4 | Builds the economy (tools, sword, bow, skillbooks), joins the attack later |
| Attacker | 4 | Arms up, rallies, then charges in waves around a flank; escorts carriers |
| Defender | 2 | Builds a wall ring (with gaps), ballistas and traps around the crown; guards it |

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
- Ramps / watchtowers (height advantage for archers), repairing structures.
- Blocking, sprint stamina, a few more spells (heal aura, frost bolt).
- Death drops some resources; respawn wave timer.

**Later**
- Interest management (only replicate nearby players) for 100 humans over the internet.
- Server-side hit validation against lag-compensated positions.
- MultiMesh rendering for resource nodes.
- Lobby / server browser, persistent progression, cosmetics.
- Real art and audio pass (still low-poly and readable).
