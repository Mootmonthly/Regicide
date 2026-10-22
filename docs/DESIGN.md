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
- Map 400 × 720 m (~600 m crown to crown: a minute's sprint, 40 s on a horse),
  point-mirrored so both sides are identical. Each base sits on a flat plateau with the
  crown pedestal near the back and the spawn behind it.
- **Terrain:** rolling hills and dry valleys (up to ~10 m relief), ~1,900 real-size
  trees (12–20 m pines and oaks) that thicken into dense woodland toward the middle of the
  map and thin out toward the bases, with open ground within 75 m of each crown (room to
  build, and attackers have to cross it in the open), and a river winding across
  the middle. The river is up to ~18 m of water but narrows to ~5 m at x = ±78 (drawbridge
  territory); two shallow fords at x = ±140 can be walked across. Wading is slow (45%
  speed, no sprint, no horse bonus).
- Resource bands: trees in forests everywhere, stone across each half, iron toward the
  middle, **magic ore only along the river** — the contested zone.
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

**Grid:** 4 × 4 m cells, 3 m levels (absolute heights, from -6 m in the riverbed up to
18 m). Walls, doors and ladders sit on cell edges and face you (R rotates); floors,
stairs, roofs and free-standing pieces fill cells. Q cycles three pages: walls & gates,
floors/stairs/roofs, and defenses & siege.

| Piece | Cost | Notes |
| --- | --- | --- |
| Wood Wall | 8 wood | 300 hp. Upgrades to stone |
| Stone Wall | 10 stone | 800 hp |
| Wood / Stone Half Wall | 4 wood / 5 stone | Waist-high cover; holds nothing up |
| Battlement | 8 stone | Crenellated parapet for wall-tops: merlons and gaps |
| Wood / Stone Window Wall | 7 wood / 9 stone | Big window to see and shoot through |
| Arrow Slit Wall | 12 stone | Chest-high gap: shoot out, hard to shoot in |
| Wood Door | 12 wood | Your team walks through; enemies can't |
| Drawbridge | 20 wood, 4 iron | Raised: a 6 m wall nobody passes. E lowers it into a 6 m bridge |
| Wood / Stone Floor | 6 wood / 8 stone | Foundations on the ground, floors up high |
| Wood Stairs | 8 wood | Climb one level |
| Wood Roof | 6 wood | Sloped; blocks arrows and fireballs from above |
| Ladder | 4 wood | Lean on any wall — including the enemy's — and climb over |
| Spike Trap | 6 wood, 3 iron | Blueprint (100g). Hurts enemies standing on it |
| Ballista | 25 wood, 10 iron | Blueprint (300g). Auto-turret; put it on a tower |
| Catapult | 30 wood, 10 stone, 5 iron | Blueprint (250g). E fires a boulder where you aim (5 stone/shot, 6 s reload, 17–60 m). 260 structure damage |
| Battering Ram | 30 wood, 10 iron | Blueprint (200g). Walk into it from behind to push and steer; batters enemy structures in front (240 every 2 s) |

**Repair (F):** restores a damaged piece for half its price, scaled by the damage.
**Upgrade (G):** rebuilds a wood wall, half wall, window wall or floor in stone, in place
(pays the stone version's price); whatever rests on it stays up.

**Support:** everything must connect to the ground — anything touching the terrain
counts, so you can build down a hillside or sink pillar walls into the riverbed and
deck a bridge across. Walls stand on the ground, a wall below, or a floor. Floors rest on walls beneath them, or reach one cell out from a floor
that does. Stairs and ballistas need a floor or the ground. Ladders lean on a wall, stand
on a ladder, or stand on a floor. Destroy a support and whatever it held collapses —
siege the base of a tower to bring it down.

**Limits:** no building within 6 m of a crown pedestal, nor on top of a player.
Melee can only hit pieces at your height (you can't chop a second-storey wall from the
ground — bring a ladder or stairs).

## Combat

- **First person** by default (V toggles an over-the-shoulder view, handy for building).
- **Stamina:** sprinting drains it; it refills after a short rest.
- **Shields:** Wooden (blocks 60%) and Iron (85%) — worn automatically, hold right click
  to raise. Blocking halves your speed and stops you attacking, and only covers hits from
  the front. **Parry:** raise the shield within 0.35 s of a melee blow — no damage, and
  the attacker is stunned for 1.2 s (can't move or act).

## Magic

Spells are learned once per match (gold + magic ore, in the C menu) and sit on the hotbar.
Casting costs mana (100 max, +2.5/s; mana potions restore 60).

| Spell | Learn | Mana | Effect |
| --- | --- | --- | --- |
| Frost Bolt | 100g + 2 ore | 20 | 18 damage and half speed for 3 s |
| Blink | 120g + 2 ore | 30 | Teleport up to 14 m (not through walls, not with a crown) |
| Fireball | 150g + 3 ore | 35 | 45 damage explosion, hurts structures |
| Heal Aura | 150g + 3 ore | 45 | Heals you and teammates within 9 m by 35 |
| Earth Wall | 180g + 4 ore | 50 | Raises a stone wall in front of you for 15 s |
| Lightning | 200g + 4 ore | 40 | 32 damage, arcs to 2 more enemies for 16 |
| Gust | 120g + 2 ore | 30 | Throws enemies in front of you 7 m back (6 damage); knocks a stolen crown out of the carrier's hands. 8 s recharge |
| Meteor | 260g + 5 ore | 70 | Lands where you aim after a 1.5 s warning ring: 65 damage in 6 m, 350 to structures. 20 s recharge |
| Spectral Warriors | 300g + 6 ore | 60 | 5 ghostly sword-knights for 60 s. They hunt any enemy (players or enemy warriors) within 50 m, follow you otherwise, and can be killed (60 health, 10 damage per hit; shields block them). Test bots fight them too. 60 s recharge |

| Thunderclap | 180g + 3 ore | 40 | Enemies within 5 m take 10 damage and are stunned for 1.5 s. 12 s recharge |
| Siphon Life | 160g + 3 ore | 35 | 22 damage to the enemy you aim at; you heal as much as they lost. 5 s recharge |
| Battle Cry | 220g + 4 ore | 50 | You and teammates within 12 m: +25% speed, +20% damage for 8 s. 30 s recharge |
| Shadow Cloak | 200g + 4 ore | 45 | Invisible to enemies (and their bots, ballistas and warriors) for 10 s; allies see a faint shape. Attacking, casting or grabbing a crown reveals you; can't be cast while carrying one. 25 s recharge |
| Arcane Ward | 150g + 3 ore | 40 | A bubble soaks up the next 40 damage (lasts 12 s). 20 s recharge |

Each spell has its own recharge; casting only keeps your hands busy for up to 1 s.

## Skills

Kills give 1 skill point, captures 3. Rank n of a skill costs n points (max rank 3).
Toughness (+15 health), Swiftness (+6% speed), Arcane (+25 mana, +1 mana/s), Lumberjack
(+25% gathering), Mason (-15% building cost), Marksman (+15% bow damage), Spellweaver
(-10% spell mana and recharge), Bloodlust (melee hits heal 10% of the damage), Iron Will
(stuns and slows on you 25% shorter), Bounty Hunter (+15 gold per kill), Horsemanship
(+8% riding speed), per rank. **Dash** is an active skill: press X to burst the way
you're facing for 25 stamina — 8 m every 5 s at rank 1, +1.5 m and 1 s faster recharge
per rank. Walls stop it; no dashing while stunned, riding, climbing, wading or
carrying a crown. The server's speed check allows one dash's worth of extra distance
per recharge.
Skills reset with the match.

## Voice chat

Push-to-talk. **T**: proximity — everyone within 45 m hears you from your position in 3D,
fading with distance (so you can hear enemies sneaking up, and they can hear you).
**Y**: team radio — your whole team, anywhere. A "talking" marker shows over speakers.

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
- Moats you can dig; trenches; more siege (siege tower, trebuchet).
- Blocking, sprint stamina, a few more spells (heal aura, frost bolt).
- Death drops some resources; respawn wave timer.

**Later**
- Interest management (only replicate nearby players) for 100 humans over the internet.
- Server-side hit validation against lag-compensated positions.
- MultiMesh rendering for resource nodes.
- Lobby / server browser, persistent progression, cosmetics.
- Real art and audio pass (still low-poly and readable).
