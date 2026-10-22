class_name GameData
extends RefCounted
## All tuning numbers and content definitions live here, so balance changes never
## require touching game logic. Later this can move to data files / Resources.

# --- Match ---------------------------------------------------------------
const TEAM_COUNT := 2
const TEAM_SIZE := 50
const CAPTURES_TO_WIN := 3
const RESPAWN_TIME := 6.0
const SPAWN_PROTECTION := 3.0
const MATCH_RESTART_DELAY := 15.0
## Default number of players per team (bots fill the empty slots).
## Bots are a testing tool; real matches are all people, so none by default.
const DEFAULT_TEAM_FILL := 0

# --- Crown (capture-the-flag) --------------------------------------------
const CROWN_TOUCH_RADIUS := 2.0
const CAPTURE_RADIUS := 3.0
const CROWN_AUTO_RETURN := 45.0
## Nobody may build this close to a crown pedestal, so a crown can't be sealed in.
const NO_BUILD_RADIUS := 6.0

# --- Players -------------------------------------------------------------
const PLAYER_MAX_HEALTH := 100.0
const PLAYER_MAX_MANA := 100.0
const MANA_REGEN := 2.5  ## per second
const MAX_STAMINA := 100.0
const SPRINT_STAMINA_COST := 18.0  ## per second
const STAMINA_REGEN := 22.0  ## per second, after a short pause
## Raise your shield this soon before a melee hit lands to parry it.
const PARRY_WINDOW := 0.35
const PARRY_STUN := 1.2
const BLOCK_ARC := 1.3  ## radians either side of where you face
const SLOW_MULT := 0.5
## Skill points earned.
const SKILL_POINTS_PER_KILL := 1
const SKILL_POINTS_PER_CAPTURE := 3
## Fastest legit ground speed (sprinting on a horse), used by the server's speed check.
const MAX_PLAYER_SPEED := 9.0 * 1.7
const ARROW_GRAVITY := 9.8

# --- Economy (gold) ------------------------------------------------------
const START_GOLD := 0
const GOLD_PER_KILL := 50
const GOLD_PER_CAPTURE := 250
const GOLD_TEAM_CAPTURE := 75
const GOLD_PER_RETURN := 25

# --- Map: team 0 lives at +Z, team 1 at -Z, mirrored through the origin ----
## Sized for 100 players: ~600 m between crowns (a minute's sprint, 40 s on a horse).
const MAP_WIDTH := 400.0
const MAP_LENGTH := 720.0
const BASE_Z := 300.0
const SPAWN_Z := 336.0
const BASE_CLEAR_RADIUS := 22.0

const TEAM_NAMES := ["Azure", "Crimson"]
const TEAM_COLORS := [Color(0.25, 0.45, 0.95), Color(0.9, 0.22, 0.2)]

# --- Raw resources gathered from the map ------------------------------------
const RESOURCES := {
	"wood": {"name": "Wood", "node_amount": 60, "respawn": 90.0},
	"stone": {"name": "Stone", "node_amount": 40, "respawn": 75.0},
	"iron": {"name": "Iron", "node_amount": 25, "respawn": 90.0},
	"magic_ore": {"name": "Magic Ore", "node_amount": 12, "respawn": 120.0},
}

## What an empty hand does. Not an inventory item.
const FISTS := {
	"name": "Fists", "kind": "fists",
	"damage": 8.0, "range": 2.0, "cooldown": 0.5, "structure_damage": 2.0,
	"gather": {"wood": 1, "stone": 1},
}

## Every craftable thing. kind is one of: tool, weapon, structure, consumable.
## unlock_cost > 0 means the blueprint must be bought with gold before crafting.
## Dictionary order is the hotbar / crafting menu order.
const ITEMS := {
	# Tools
	"stone_axe": {
		"name": "Stone Axe", "kind": "tool", "unlock_cost": 0,
		"recipe": {"wood": 6, "stone": 3},
		"damage": 14.0, "range": 2.4, "cooldown": 0.6, "structure_damage": 8.0,
		"gather": {"wood": 4, "stone": 1},
		"color": Color(0.55, 0.5, 0.45),
		"desc": "Chops wood fast. A poor weapon.",
	},
	"pickaxe": {
		"name": "Pickaxe", "kind": "tool", "unlock_cost": 0,
		"recipe": {"wood": 5, "stone": 5},
		"damage": 12.0, "range": 2.4, "cooldown": 0.7, "structure_damage": 10.0,
		"gather": {"wood": 1, "stone": 4, "iron": 3, "magic_ore": 2},
		"color": Color(0.4, 0.4, 0.45),
		"desc": "Required to mine iron and magic ore.",
	},
	# Weapons
	"wooden_club": {
		"name": "Wooden Club", "kind": "weapon", "unlock_cost": 0,
		"recipe": {"wood": 8},
		"damage": 18.0, "range": 2.3, "cooldown": 0.6, "structure_damage": 6.0,
		"gather": {"wood": 1},
		"color": Color(0.5, 0.33, 0.18),
		"desc": "Better than fists.",
	},
	"iron_sword": {
		"name": "Iron Sword", "kind": "weapon", "unlock_cost": 0,
		"recipe": {"wood": 3, "iron": 8},
		"damage": 30.0, "range": 2.7, "cooldown": 0.55, "structure_damage": 6.0,
		"gather": {"wood": 1},
		"color": Color(0.8, 0.82, 0.88),
		"desc": "The knight's standard.",
	},
	"war_hammer": {
		"name": "War Hammer", "kind": "weapon", "unlock_cost": 150,
		"recipe": {"wood": 4, "iron": 12},
		"damage": 45.0, "range": 2.6, "cooldown": 1.1, "structure_damage": 45.0,
		"gather": {"stone": 2},
		"color": Color(0.35, 0.35, 0.4),
		"desc": "Slow, brutal, and wrecks walls.",
	},
	"shortbow": {
		"name": "Shortbow", "kind": "ranged", "unlock_cost": 0,
		"recipe": {"wood": 10, "stone": 2},
		"damage": 20.0, "cooldown": 0.9, "speed": 55.0, "range": 60.0, "ammo": "arrow",
		"structure_damage": 2.0,
		"color": Color(0.6, 0.42, 0.2),
		"desc": "Shoots arrows. Needs arrows.",
	},
	"crossbow": {
		"name": "Crossbow", "kind": "ranged", "unlock_cost": 175,
		"recipe": {"wood": 6, "iron": 6},
		"damage": 42.0, "cooldown": 1.8, "speed": 85.0, "range": 80.0, "ammo": "arrow",
		"structure_damage": 6.0,
		"color": Color(0.3, 0.25, 0.22),
		"desc": "Slow to reload, hits hard and flat. Needs arrows.",
	},
	"wooden_shield": {
		"name": "Wooden Shield", "kind": "shield", "unlock_cost": 0,
		"recipe": {"wood": 10},
		"block": 0.6,
		"color": Color(0.55, 0.38, 0.2),
		"desc": "Hold right click to block 60% of a hit from the front. Raise it just as a sword lands to parry.",
	},
	"iron_shield": {
		"name": "Iron Shield", "kind": "shield", "unlock_cost": 0,
		"recipe": {"wood": 4, "iron": 8},
		"block": 0.85,
		"color": Color(0.62, 0.64, 0.7),
		"desc": "Blocks 85% of a hit from the front. Your best shield is used automatically.",
	},
	"arrow": {
		"name": "Arrows", "kind": "ammo", "unlock_cost": 0,
		"recipe": {"wood": 2, "stone": 1}, "yield": 5,
		"color": Color(0.7, 0.6, 0.45),
		"desc": "5 arrows for bows and crossbows.",
	},
	# Building pieces. "piece" picks the grid slot type (see BuildGrid); "category" picks
	# the build-mode page (Q cycles pages). Pieces are paid from resources on placement.
	# "upgrade" names the stone version a wood piece can be upgraded to in place.
	"wood_wall": {
		"name": "Wood Wall", "kind": "structure", "piece": "wall", "category": "walls", "unlock_cost": 0,
		"material": "wood", "model": "res://assets/survival/fence-fortified.glb", "model_tiles": Vector3i(4, 1, 1),
		"recipe": {"wood": 8}, "health": 300.0, "thickness": 0.4, "upgrade": "stone_wall",
		"color": Color(0.55, 0.38, 0.2),
		"desc": "Cheap palisade wall.",
	},
	"stone_wall": {
		"name": "Stone Wall", "kind": "structure", "piece": "wall", "category": "walls", "unlock_cost": 0,
		"material": "stone", "model": "res://assets/castle/wall.glb", "model_tiles": Vector3i(4, 1, 1),
		"recipe": {"stone": 10}, "health": 800.0, "thickness": 0.6,
		"color": Color(0.6, 0.6, 0.62),
		"desc": "Sturdy masonry wall.",
	},
	"wood_half_wall": {
		"name": "Wood Half Wall", "kind": "structure", "piece": "half", "category": "walls", "unlock_cost": 0,
		"material": "wood", "model": "res://assets/survival/fence.glb", "model_tiles": Vector3i(4, 1, 1),
		"recipe": {"wood": 4}, "health": 160.0, "thickness": 0.4, "upgrade": "stone_half_wall",
		"color": Color(0.58, 0.4, 0.22),
		"desc": "Waist-high cover you can shoot over. Can't hold anything up.",
	},
	"stone_half_wall": {
		"name": "Stone Half Wall", "kind": "structure", "piece": "half", "category": "walls", "unlock_cost": 0,
		"material": "stone", "model": "res://assets/castle/wall-half.glb", "model_tiles": Vector3i(4, 1, 1),
		"recipe": {"stone": 5}, "health": 420.0, "thickness": 0.6,
		"color": Color(0.62, 0.62, 0.64),
		"desc": "Sturdy waist-high cover.",
	},
	"battlement": {
		"name": "Battlement", "kind": "structure", "piece": "half", "category": "walls", "unlock_cost": 0,
		"material": "stone", "model": "res://assets/castle/wall-half-modular.glb", "model_tiles": Vector3i(4, 1, 1),
		"recipe": {"stone": 8}, "health": 550.0, "thickness": 0.6, "battlement": true,
		"color": Color(0.58, 0.58, 0.6),
		"desc": "Crenellated parapet for wall-tops: duck behind the merlons, shoot through the gaps.",
	},
	"wood_window": {
		"name": "Wood Window Wall", "kind": "structure", "piece": "wall", "category": "walls", "unlock_cost": 0,
		"material": "wood",
		"recipe": {"wood": 7}, "health": 240.0, "thickness": 0.4, "window": true, "upgrade": "stone_window",
		"color": Color(0.55, 0.38, 0.2),
		"desc": "Wall with a big window to see and shoot through.",
	},
	"stone_window": {
		"name": "Stone Window Wall", "kind": "structure", "piece": "wall", "category": "walls", "unlock_cost": 0,
		"material": "stone",
		"recipe": {"stone": 9}, "health": 600.0, "thickness": 0.6, "window": true,
		"color": Color(0.6, 0.6, 0.62),
		"desc": "Stone wall with a big window.",
	},
	"arrow_slit": {
		"name": "Arrow Slit Wall", "kind": "structure", "piece": "wall", "category": "walls", "unlock_cost": 0,
		"material": "stone",
		"recipe": {"stone": 12}, "health": 650.0, "thickness": 0.6, "slit": true,
		"color": Color(0.55, 0.55, 0.58),
		"desc": "Stone wall with a chest-high gap to shoot arrows through.",
	},
	"wood_door": {
		"name": "Wood Door", "kind": "structure", "piece": "door", "category": "walls", "unlock_cost": 0,
		"material": "wood", "model": "res://assets/survival/fence-doorway.glb", "model_tiles": Vector3i(2, 1, 1),
		"recipe": {"wood": 12}, "health": 350.0, "thickness": 0.4,
		"color": Color(0.62, 0.45, 0.25),
		"desc": "A wall your own team can walk through.",
	},
	"drawbridge": {
		"name": "Drawbridge", "kind": "structure", "piece": "drawbridge", "category": "walls", "unlock_cost": 0,
		"material": "wood", "model": "res://assets/castle/bridge-draw.glb", "model_rot": Vector3(-90, 0, 0), "model_leaf": true,
		"recipe": {"wood": 20, "iron": 4}, "health": 700.0,
		"color": Color(0.5, 0.36, 0.2),
		"desc": "Raised, it blocks everyone. Your team lowers it (E) into a 6 m bridge across the river's narrows.",
	},
	"wood_floor": {
		"name": "Wood Floor", "kind": "structure", "piece": "floor", "category": "floors", "unlock_cost": 0,
		"material": "wood", "model": "res://assets/survival/floor.glb", "model_tiles": Vector3i(2, 1, 2),
		"recipe": {"wood": 6}, "health": 250.0, "upgrade": "stone_floor",
		"color": Color(0.6, 0.45, 0.28),
		"desc": "Floor, foundation or bridge deck. Rests on walls or the ground, reaches one cell out.",
	},
	"stone_floor": {
		"name": "Stone Floor", "kind": "structure", "piece": "floor", "category": "floors", "unlock_cost": 0,
		"material": "stone",
		"recipe": {"stone": 8}, "health": 600.0,
		"color": Color(0.5, 0.5, 0.52),
		"desc": "Sturdy floor or foundation.",
	},
	"wood_stairs": {
		"name": "Wood Stairs", "kind": "structure", "piece": "stairs", "category": "floors", "unlock_cost": 0,
		"material": "wood",
		"recipe": {"wood": 8}, "health": 250.0,
		"color": Color(0.58, 0.42, 0.24),
		"desc": "Climbs one level (3 m). Build them on the ground or on a floor.",
	},
	"wood_roof": {
		"name": "Wood Roof", "kind": "structure", "piece": "roof", "category": "floors", "unlock_cost": 0,
		"material": "roof",
		"recipe": {"wood": 6}, "health": 250.0,
		"color": Color(0.5, 0.22, 0.16),
		"desc": "Sloped roof. Rests on walls. Shelters you from arrows and fireballs.",
	},
	"ladder": {
		"name": "Ladder", "kind": "structure", "piece": "ladder", "category": "floors", "unlock_cost": 0,
		"material": "wood",
		"recipe": {"wood": 4}, "health": 120.0,
		"color": Color(0.65, 0.5, 0.3),
		"desc": "Lean it on any wall, even the enemy's, and climb with W. Stack them to go higher.",
	},
	"spike_trap": {
		"name": "Spike Trap", "kind": "structure", "piece": "free", "category": "siege", "unlock_cost": 100,
		"material": "stone",
		"recipe": {"wood": 6, "iron": 3}, "health": 120.0,
		"trap": {"damage": 12.0, "interval": 0.75},
		"color": Color(0.5, 0.5, 0.52),
		"desc": "Hurts enemies standing on it. Doesn't block movement.",
	},
	"ballista": {
		"name": "Ballista", "kind": "structure", "piece": "free", "category": "siege", "unlock_cost": 300,
		"material": "wood", "model": "res://assets/castle/siege-ballista.glb", "model_box": AABB(Vector3(-1.2, 0, -1.2), Vector3(2.4, 1.9, 2.4)),
		"recipe": {"wood": 25, "iron": 10}, "health": 400.0,
		"turret": {"range": 32.0, "damage": 22.0, "cooldown": 2.5},
		"color": Color(0.45, 0.3, 0.15),
		"desc": "Automatically fires bolts at nearby enemies. Put it on a tower.",
	},
	"catapult": {
		"name": "Catapult", "kind": "structure", "piece": "free", "category": "siege", "unlock_cost": 250,
		"material": "wood", "model": "res://assets/castle/siege-catapult.glb", "model_box": AABB(Vector3(-1.3, 0, -1.6), Vector3(2.6, 2.6, 3.2)),
		"recipe": {"wood": 30, "stone": 10, "iron": 5}, "health": 500.0,
		"catapult": {"cooldown": 6.0, "speed": 24.0, "damage": 35.0, "structure_damage": 260.0, "radius": 3.2, "ammo": {"stone": 5}},
		"color": Color(0.48, 0.33, 0.18),
		"desc": "Stand next to it and press E to hurl a boulder where you aim (5 stone a shot). Wrecks walls.",
	},
	"battering_ram": {
		"name": "Battering Ram", "kind": "structure", "piece": "vehicle", "category": "siege", "unlock_cost": 200,
		"material": "wood", "model": "res://assets/castle/siege-ram.glb", "model_rot": Vector3(0, 90, 0), "model_box": AABB(Vector3(-1.1, 0, -2.6), Vector3(2.2, 2.2, 5.2)),
		"recipe": {"wood": 30, "iron": 10}, "health": 750.0,
		"ram": {"speed": 2.4, "damage": 240.0, "interval": 2.0, "turn_rate": 0.7},
		"color": Color(0.42, 0.3, 0.18),
		"desc": "Push it from behind (walk into it) to roll it forward; it batters enemy structures in front.",
	},
	# Consumables
	"health_potion": {
		"name": "Health Potion", "kind": "consumable", "unlock_cost": 75,
		"recipe": {"magic_ore": 1, "wood": 2},
		"effect": "heal", "amount": 50.0,
		"color": Color(0.9, 0.2, 0.35),
		"desc": "Restores 50 health.",
	},
	"horse_saddle": {
		"name": "Horse Saddle", "kind": "consumable", "unlock_cost": 150,
		"recipe": {"wood": 6, "iron": 3},
		"effect": "mount",
		"color": Color(0.45, 0.28, 0.12),
		"desc": "Summon a horse: much faster until you die. No bonus while carrying a crown.",
	},
	"mana_potion": {
		"name": "Mana Potion", "kind": "consumable", "unlock_cost": 0,
		"recipe": {"magic_ore": 2, "wood": 1},
		"effect": "mana", "amount": 60.0,
		"color": Color(0.25, 0.45, 1.0),
		"desc": "Restores 60 mana.",
	},
	"skillbook_vigor": {
		"name": "Skillbook: Vigor", "kind": "consumable", "unlock_cost": 250,
		"recipe": {"magic_ore": 4, "stone": 6},
		"effect": "max_health", "amount": 25.0,
		"color": Color(0.2, 0.75, 0.35),
		"desc": "+25 max health for the rest of the match.",
	},
	"skillbook_gatherer": {
		"name": "Skillbook: Gatherer", "kind": "consumable", "unlock_cost": 150,
		"recipe": {"magic_ore": 2, "wood": 10},
		"effect": "gather_mult", "amount": 0.5,
		"color": Color(0.85, 0.75, 0.25),
		"desc": "+50% resources from every hit for the rest of the match.",
	},
	# Spells: learned once (gold + magic ore, from the C menu), then cast with mana.
	# They sit on your hotbar like items. "learn" is the magic ore paid to learn.
	"fireball": {
		"name": "Fireball", "kind": "spell", "unlock_cost": 150, "learn": {"magic_ore": 3}, "recipe": {},
		"mana": 35.0, "cooldown": 1.2,
		"damage": 45.0, "radius": 4.0, "structure_damage": 80.0, "range": 40.0,
		"color": Color(1.0, 0.5, 0.1),
		"desc": "An exploding fireball where you aim. Hurts structures too.",
	},
	"frost_bolt": {
		"name": "Frost Bolt", "kind": "spell", "unlock_cost": 100, "learn": {"magic_ore": 2}, "recipe": {},
		"mana": 20.0, "cooldown": 0.8,
		"damage": 18.0, "range": 45.0, "slow": 3.0,
		"color": Color(0.55, 0.85, 1.0),
		"desc": "Chills the first enemy it hits: damage, and half speed for 3 s.",
	},
	"lightning": {
		"name": "Lightning", "kind": "spell", "unlock_cost": 200, "learn": {"magic_ore": 4}, "recipe": {},
		"mana": 40.0, "cooldown": 2.0,
		"damage": 32.0, "range": 40.0, "chain_damage": 16.0, "chain_range": 8.0, "chains": 2,
		"color": Color(0.85, 0.85, 1.0),
		"desc": "Instant strike on the enemy you aim at, arcing to two more nearby.",
	},
	"heal_aura": {
		"name": "Heal Aura", "kind": "spell", "unlock_cost": 150, "learn": {"magic_ore": 3}, "recipe": {},
		"mana": 45.0, "cooldown": 4.0,
		"heal": 35.0, "radius": 9.0,
		"color": Color(0.4, 1.0, 0.5),
		"desc": "Heals you and every teammate within 9 m by 35.",
	},
	"blink": {
		"name": "Blink", "kind": "spell", "unlock_cost": 120, "learn": {"magic_ore": 2}, "recipe": {},
		"mana": 30.0, "cooldown": 3.0, "range": 14.0,
		"color": Color(0.75, 0.45, 1.0),
		"desc": "Teleport up to 14 m the way you're looking (not through walls).",
	},
	"earth_wall": {
		"name": "Earth Wall", "kind": "spell", "unlock_cost": 180, "learn": {"magic_ore": 4}, "recipe": {},
		"mana": 50.0, "cooldown": 6.0, "lifetime": 15.0,
		"color": Color(0.5, 0.4, 0.28),
		"desc": "Raise a temporary stone wall in front of you for 15 s.",
	},
	# What Earth Wall summons (not buildable directly).
	"earth_wall_piece": {
		"name": "Earth Wall", "kind": "structure", "piece": "wall", "category": "", "unlock_cost": 0,
		"material": "stone",
		"recipe": {}, "health": 500.0, "thickness": 0.7,
		"color": Color(0.5, 0.4, 0.28),
		"desc": "Summoned by the Earth Wall spell. Crumbles after 15 s.",
	},
}

## Perks bought with skill points (earned from kills and captures). Rank n costs n points.
const SKILLS := {
	"toughness": {"name": "Toughness", "max_rank": 3, "desc": "+15 max health per rank."},
	"swiftness": {"name": "Swiftness", "max_rank": 3, "desc": "+6% move speed per rank."},
	"arcane": {"name": "Arcane", "max_rank": 3, "desc": "+25 max mana and +1 mana/s per rank."},
	"lumberjack": {"name": "Lumberjack", "max_rank": 3, "desc": "+25% resources from every hit per rank."},
	"mason": {"name": "Mason", "max_rank": 3, "desc": "Building pieces cost 15% less per rank."},
	"marksman": {"name": "Marksman", "max_rank": 3, "desc": "+15% bow and crossbow damage per rank."},
}

const ITEM_KINDS := ["tool", "weapon", "ranged", "ammo", "shield", "structure", "consumable", "spell"]
const MELEE_KINDS := ["fists", "tool", "weapon"]
## Build-mode pages, cycled with Q.
const BUILD_CATEGORIES := ["walls", "floors", "siege"]
const BUILD_CATEGORY_NAMES := {"walls": "Walls & gates", "floors": "Floors, stairs & roofs", "siege": "Defenses & siege"}


const BOT_NAMES := [
	"Aldric", "Beatrix", "Cedric", "Daria", "Edmund", "Fenna", "Godfrey", "Hilde", "Ivo",
	"Jocelyn", "Kenric", "Leofa", "Merek", "Nell", "Osric", "Petra", "Quentin", "Rowena",
	"Sigmund", "Tamsin", "Ulric", "Vala", "Wystan", "Ysolde", "Alaric", "Brunhild",
	"Conrad", "Dunstan", "Elric", "Freya", "Gunnar", "Helga", "Isolde", "Jorund", "Kara",
	"Lothar", "Maud", "Njal", "Odo", "Perrin", "Ragna", "Sven", "Thora", "Uther", "Viggo",
	"Wulfric", "Yrsa", "Bertram", "Cuthbert", "Eadric",
]


## Physics layer bit for a team's gates (layers 5 and 6). Enemies collide with them.
static func gate_layer(team: int) -> int:
	return 16 if team == 0 else 32


## Learning cost for a spell / unlock cost for a blueprint: gold plus any materials.
static func learn_materials(id: String) -> Dictionary:
	return item(id).get("learn", {})


static func skill_cost(rank_now: int) -> int:
	return rank_now + 1


## A building piece's price after the Mason skill discount.
static func build_cost(recipe: Dictionary, mason_rank: int) -> Dictionary:
	var out := {}
	for res: String in recipe:
		out[res] = maxi(1, ceili(int(recipe[res]) * (1.0 - 0.15 * mason_rank)))
	return out


static func item(id: String) -> Dictionary:
	if id == "":
		return FISTS
	return ITEMS.get(id, {})


static func is_item(id: String) -> bool:
	return ITEMS.has(id)


static func is_resource(id: String) -> bool:
	return RESOURCES.has(id)


static func display_name(id: String) -> String:
	if RESOURCES.has(id):
		return RESOURCES[id]["name"]
	return item(id).get("name", id)


static func team_name(team: int) -> String:
	return TEAM_NAMES[team] if team >= 0 and team < TEAM_COUNT else "?"


static func team_color(team: int) -> Color:
	return TEAM_COLORS[team] if team >= 0 and team < TEAM_COUNT else Color.WHITE


static func team_sign(team: int) -> float:
	return 1.0 if team == 0 else -1.0


## Top of the crown pedestal.
static func crown_pos(team: int) -> Vector3:
	return Vector3(0.0, 1.0, BASE_Z * team_sign(team))


static func spawn_point(team: int) -> Vector3:
	return Vector3(randf_range(-14.0, 14.0), 1.0, team_sign(team) * SPAWN_Z + randf_range(-3.0, 3.0))


static func flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


static func in_bounds(p: Vector3, margin := 1.0) -> bool:
	return absf(p.x) <= MAP_WIDTH * 0.5 - margin and absf(p.z) <= MAP_LENGTH * 0.5 - margin


static func can_build_at(p: Vector3) -> bool:
	if not in_bounds(p, 3.0):
		return false
	for t in TEAM_COUNT:
		if flat_distance(p, crown_pos(t)) < NO_BUILD_RADIUS:
			return false
	return true


static func cost_text(cost: Dictionary) -> String:
	var parts: PackedStringArray = []
	for id in cost:
		parts.append("%d %s" % [cost[id], display_name(id)])
	return ", ".join(parts)
