# Regicide

A medieval multiplayer arena battler built on **Godot 4.4**. Two teams of up to 50
spawn with nothing, gather wood, stone, iron and magic ore, build defenses, craft
weapons, and fight to steal the enemy's crown and carry it back to their own.
Players build real forts on a snap grid: walls, doors, arrow slits, floors, stairs,
roofs, and ladders for scaling the enemy's walls.

![A player-built fort](docs/screenshots/build_fort.png)

## Running it

1. Install [Godot 4.4](https://godotengine.org/download) (standard build, not .NET).
2. Open the folder in Godot (`Import` → pick `project.godot`) and press **F5**.
3. **Host & Play**, or **Join** a host's IP. (**Test bots** fills empty slots with bots
   for solo testing; leave it at 0 for real matches.)

To test with several players on one machine: *Debug → Customize Run Instances*, enable
multiple instances, then host in one window and join `127.0.0.1` from the others.

Command line (arguments after `--`):

```sh
godot --headless --path . -- --server --port 24565          # dedicated server
godot --path . -- --host --bots 25                           # solo test vs bots
godot --path . -- --host --name Arthur                       # host and play
godot --path . -- --join 203.0.113.5 --port 24565 --name Bors
```

The default port is **24565** (UDP). Open it on the host's router to play over the internet.

## Controls

| Key | Action |
| --- | --- |
| WASD / Shift / Space | Move / sprint / jump |
| Mouse | Look |
| Left click | Swing, shoot, gather, place a structure, or use an item (whatever is equipped) |
| 1–9, 0, mouse wheel | Pick a hotbar slot |
| Q | Build mode (hotbar switches to building pieces) |
| W / S on a ladder | Climb up / down |
| C (or B) | Crafting & blueprint shop |
| Tab (hold) | Scoreboard |
| Esc | Free the mouse |

## How a match works

- **Gather.** Hit trees and rocks. Fists get wood and stone slowly; an axe or pickaxe is
  faster, and a pickaxe is required for iron and magic ore. Magic ore only grows in the
  contested middle of the map.
- **Craft.** Tools, melee weapons, bows and arrows, and consumables cost resources (C menu).
- **Build.** Press Q. Pieces snap to a 4 m grid with 3 m levels and are paid for straight
  from your resources as you place them: wood/stone walls, arrow-slit walls, team-only
  doors, floors, stairs, roofs, ladders, spike traps and ballistas. Everything must be
  supported down to the ground: knock out the walls holding up a floor and it collapses.
- **Scale walls.** Lean a ladder on any wall, including the enemy's, and climb over.
- **Earn gold.** Kills pay 50g; capturing a crown pays 250g to the carrier and 75g to
  every teammate; returning your own dropped crown pays 25g.
- **Unlock.** Spend gold on blueprints: war hammer, crossbow, ballista, spike trap,
  horse saddle, health potion, fireball scroll, and skillbooks.
- **Steal the crown.** Touch the enemy crown to grab it. You move slower while carrying it,
  and drop it if you die. Bring it to your own pedestal **while your crown is home** to
  score. First to 3 captures wins, then a fresh match starts.
- **Bots are a testing tool.** Real matches are people. For solo testing, bots fill empty
  slots: they gather, craft, build wall rings, throw ladders on enemy walls, and attack.

## Project layout

```
autoload/      Net (connections, command line), Controls (input map), Sfx (synthesized sounds)
scenes/        main_menu, world, player (.tscn)
scripts/core/  Pure rules & data: GameData (all tuning/content), BuildGrid, Inventory, CrownRules, ...
scripts/game/  GameMode (server-authoritative match logic), BotBrain (test bots)
scripts/world/ World, map generator, resource nodes, structures, crowns
scripts/player Player controller
scripts/ui/    HUD, minimap, main menu
tests/         Unit tests, gameplay integration test, multiplayer smoke test
docs/          Design document and architecture notes
```

All items, costs and balance numbers live in `scripts/core/game_data.gd`.

## Tests

```sh
godot --headless --path . --import                         # first run only
godot --headless --path . res://tests/run_tests.tscn      # unit tests
godot --headless --path . res://tests/gameplay_test.tscn   # full rules on a live world
GODOT=godot tests/smoke.sh                                 # server w/ bots + 2 clients over ENet
godot --headless --path . --fixed-fps 60 res://tests/bot_soak.tscn -- --minutes 8 --bots 50
                                                           # full bot match, fast-forwarded
```

CI runs all four on every push (`.github/workflows/tests.yml`). The soak prints a
per-minute report (kills, steals, captures, structures, items, server frame time).

See [docs/DESIGN.md](docs/DESIGN.md) for the game design and roadmap, and
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how the networking fits together.
