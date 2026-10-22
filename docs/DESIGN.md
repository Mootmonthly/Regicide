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

**Free to craft:** Stone Axe, Pickaxe, Wooden Club, Iron Sword, Wooden Wall, Stone Wall.

**Blueprints (gold):**

| Blueprint | Gold | What it does |
| --- | --- | --- |
| Health Potion | 75 | Heal 50 |
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

## Open questions

- Should dying drop some carried resources (loot to fight over)?
- Team-wide vs per-player unlocks? (Per-player today.)
- Gates that only your team can walk through.
- Repairing structures; showing structure health.
- Ranged weapons (bows, crossbows) and blocking/parrying for melee depth.
- Should a stolen crown ping its location on the enemy's map?
- Classes / roles, or keep it fully sandbox?

## Roadmap

**Next up (playable prototype → fun prototype)**
- Bots to fill empty slots, so 50v50 can be tested without 100 people.
- Hit feedback: damage numbers, hit flash, death animation, sounds.
- Scoreboard (Tab-hold) and minimap with crown markers.
- Gates, ramps/watchtowers, spike traps.
- Bows and blocking.

**Later**
- Server-side movement validation (speed / teleport checks) — movement is currently
  client-authoritative.
- Interest management (only replicate nearby players) for full 100-player matches.
- MultiMesh rendering for resource nodes.
- Lobby / server browser, persistent progression, cosmetics.
- Real art pass (still low-poly and readable).
