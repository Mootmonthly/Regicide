class_name BotBrain
extends Node
## Server-side AI for one bot. Thinks a few times per second, steers its Player through
## the same movement intent humans use, and acts only through GameMode.perform_*(), so
## bots follow exactly the same rules (cooldowns, costs, range) as people.
##
## Each bot has a role:
##   GATHERER  - builds up the economy, then joins the attack
##   ATTACKER  - arms up, then goes for the enemy crown and escorts carriers
##   DEFENDER  - fortifies around the home crown and guards it

enum Role { GATHERER, ATTACKER, DEFENDER }
enum Task { IDLE, GATHER, FIGHT, SIEGE, STEAL, CARRY, RETURN_CROWN, ESCORT, BUILD, GUARD }

const THINK_INTERVAL := 0.3
## How close an enemy must be before this role stops what it's doing to fight.
## Attackers mostly ignore fights and push for the crown.
const AGGRO := {Role.GATHERER: 12.0, Role.ATTACKER: 7.0, Role.DEFENDER: 22.0}

const ATTACK_AFTER := 120.0  ## attackers go for the crown by now even if poorly armed
const GATHERERS_JOIN_AFTER := 300.0
## Attackers rally near the middle, then charge together for WAVE_CHARGE seconds
## out of every WAVE_PERIOD, so they hit the enemy base as a group.
const WAVE_PERIOD := 110.0
const WAVE_CHARGE := 75.0
## Distances along the attack axis: + is our half, - is theirs.
const RALLY_DEPTH := 110.0
const FLANK_DEPTH := -210.0
const LANE_X := 140.0  # the river fords

## [item, how many to keep] in priority order.
const WISHLIST := {
	Role.GATHERER: [["pickaxe", 1], ["stone_axe", 1], ["iron_sword", 1], ["wooden_shield", 1], ["skillbook_gatherer", 1],
		["shortbow", 1], ["arrow", 10], ["health_potion", 1], ["skillbook_vigor", 1]],
	Role.ATTACKER: [["pickaxe", 1], ["iron_sword", 1], ["wooden_shield", 1], ["horse_saddle", 1],
		["health_potion", 2], ["war_hammer", 1]],
	Role.DEFENDER: [["pickaxe", 1], ["shortbow", 1], ["arrow", 20], ["iron_sword", 1], ["crossbow", 1]],
}
const SHOPPING := {
	Role.GATHERER: ["skillbook_gatherer", "health_potion", "skillbook_vigor"],
	Role.ATTACKER: ["horse_saddle", "health_potion", "war_hammer"],
	Role.DEFENDER: ["ballista", "spike_trap", "health_potion", "crossbow"],
}
## Spells each role learns when it has the gold and magic ore, in order.
const SPELLS := {
	Role.GATHERER: ["magic_missiles", "heal_aura", "arcane_ward", "spectral_warriors", "meteor"],
	Role.ATTACKER: ["magic_missiles", "gust", "shadow_cloak", "battle_cry", "spectral_warriors", "fireball"],
	Role.DEFENDER: ["chain_hook", "meteor", "thunderclap", "frost_bolt", "siphon_life", "lightning", "gust"],
}
const MELEE_PREFERENCE := ["war_hammer", "iron_sword", "wooden_club", "stone_axe", "pickaxe"]
## Resources a role keeps on hand once its wishlist is done (building is paid on placement).
const RESERVES := {
	Role.GATHERER: {"magic_ore": 6},  # for spells
	Role.ATTACKER: {"wood": 8},  # two ladders
	Role.DEFENDER: {"stone": 30, "wood": 30},
}
const RING := 3  ## defensive wall ring half-size, in cells

var player: Player
var gm: GameMode
var world: World
var role: Role = Role.GATHERER
var task: Task = Task.IDLE
var goal := Vector3.ZERO
var stop_distance := 1.0
var target: Node = null

var _build_item := ""
var _build_slot: Dictionary = {}
var _climb_timer := 0.0
var _think_timer := 0.0
var _stuck_timer := 0.0
var _last_pos := Vector3.ZERO
var _detour := Vector3.ZERO
var _detour_timer := 0.0
var _last_attacked := -100.0
var _last_attacker := 0
var _ray := PhysicsRayQueryParameters3D.new()
var _task_started := 0.0


func _ready() -> void:
	player = get_parent() as Player
	gm = player.get_tree().get_first_node_in_group("game_mode") as GameMode
	world = gm.world
	var idx := absi(player.peer_id)
	# Per 10 bots: 4 gatherers, 4 attackers, 2 defenders.
	role = [Role.GATHERER, Role.ATTACKER, Role.DEFENDER, Role.GATHERER, Role.ATTACKER,
		Role.GATHERER, Role.ATTACKER, Role.GATHERER, Role.ATTACKER, Role.DEFENDER][idx % 10]
	_think_timer = randf() * THINK_INTERVAL
	_ray.collision_mask = 1 | 4 | 8 | GameData.gate_layer(1 - player.team)
	_ray.exclude = [player.get_rid()]


func reset() -> void:
	task = Task.IDLE
	target = null


func on_damaged(attacker_peer: int) -> void:
	_last_attacked = gm.clock
	_last_attacker = attacker_peer


func _rec() -> PlayerRecord:
	return gm.records.get(player.peer_id)


func _match_time() -> float:
	return gm.clock - gm.match_started_at


func _physics_process(delta: float) -> void:
	player.wants_jump = false
	if task != Task.FIGHT and player.blocking:
		player.blocking = false
	if not player.alive or gm.match_over:
		player.move_input = Vector2.ZERO
		task = Task.IDLE
		return
	_think_timer -= delta
	if _think_timer <= 0.0:
		_think_timer = THINK_INTERVAL
		_think()
	_steer(delta)
	_act()


# =============================================================================
# Decisions
# =============================================================================

func _think() -> void:
	var rec := _rec()
	if rec == null:
		return
	_manage_inventory(rec)
	# Give up on jobs that are taking too long (unreachable spot, endless wall).
	if (task == Task.BUILD or task == Task.SIEGE) and gm.clock - _task_started > 15.0:
		task = Task.IDLE
	var me := player.sync_pos
	var own: CrownState = gm.crowns[player.team]
	var theirs: CrownState = gm.crowns[1 - player.team]

	if player.carrying_crown >= 0:
		# Run home along the flank first, away from the crowd in the middle.
		var depth := me.z * GameData.team_sign(player.team)
		if depth < -120.0 and absf(me.x) < LANE_X - 25.0:
			var lane := signf(me.x) if absf(me.x) > 1.0 else _lane()
			_go(Task.CARRY, Vector3(lane * LANE_X, 0, -80.0 * GameData.team_sign(player.team)), 8.0)
		else:
			_go(Task.CARRY, GameData.crown_pos(player.team), 0.5)
		return
	if own.state == CrownRules.State.CARRIED:
		var thief := world.get_player(own.carrier)
		# Attackers hunt the thief anywhere (this also breaks standoffs where both
		# crowns are stolen); everyone else only if it's close.
		if thief and (role == Role.ATTACKER or me.distance_to(thief.sync_pos) < 120.0):
			_engage(thief)
			return
	if own.state == CrownRules.State.DROPPED and me.distance_to(own.position) < 160.0:
		_go(Task.RETURN_CROWN, own.position, 0.3)
		return

	var aggro: float = AGGRO[role]
	var committed := role == Role.ATTACKER and task == Task.STEAL and _charging()
	if committed:
		aggro = 3.5  # mid-charge: only fight what's right on top of us
	elif gm.clock - _last_attacked < 4.0:
		aggro = maxf(aggro, 15.0)
	var foe := _nearest_enemy(aggro)
	if foe:
		_engage(foe)
		return
	if theirs.state == CrownRules.State.DROPPED and me.distance_to(theirs.position) < 100.0:
		_go(Task.STEAL, theirs.position, 0.3)
		return
	if task == Task.SIEGE and target != null and is_instance_valid(target) and not target.is_queued_for_deletion():
		return  # keep breaking the wall in our way

	var acting_role := role
	if role == Role.GATHERER and (_wishlist_done(rec) or _match_time() > GATHERERS_JOIN_AFTER):
		acting_role = Role.ATTACKER
	match acting_role:
		Role.ATTACKER:
			var deep := player.sync_pos.z * GameData.team_sign(player.team) < 0.0
			if rec.inventory.count("wood") < 8 and not deep and not _charging():
				_plan_gather(rec, "wood")  # wood for ladders before heading out
			elif _armed(rec) or _match_time() > ATTACK_AFTER:
				_plan_attack(theirs)
			else:
				_plan_gather(rec)
		Role.DEFENDER:
			if _plan_build(rec):
				return
			if _wishlist_done(rec) or rec.inventory.count("shortbow") > 0 and _match_time() > 60.0:
				_plan_guard()
			else:
				_plan_gather(rec)
		_:
			_plan_gather(rec)


func _go(new_task: Task, pos: Vector3, stop: float, new_target: Node = null) -> void:
	if new_task != task:
		_task_started = gm.clock
	task = new_task
	goal = pos
	stop_distance = stop
	target = new_target


func _engage(foe: Node3D) -> void:
	var rec := _rec()
	var ranged := _ranged_weapon(rec)
	var pos := _foe_pos(foe)
	var dist := GameData.flat_distance(player.sync_pos, pos)
	if ranged != "" and dist > 7.0:
		var reach := float(GameData.item(ranged)["range"]) * 0.5
		_go(Task.FIGHT, pos, reach, foe)
	else:
		var weapon := GameData.item(_melee_weapon(rec))
		_go(Task.FIGHT, pos, float(weapon["range"]) - 0.5, foe)


func _plan_attack(theirs: CrownState) -> void:
	if theirs.state == CrownRules.State.CARRIED:
		var carrier := world.get_player(theirs.carrier)
		if carrier:
			_go(Task.ESCORT, carrier.sync_pos, 4.0, carrier)
			return
	var side := GameData.team_sign(player.team)
	var depth := player.sync_pos.z * side  # how far toward our own end we are
	var lane := _lane() * LANE_X
	if theirs.state == CrownRules.State.DROPPED or depth < FLANK_DEPTH + 5.0:
		_go(Task.STEAL, theirs.position, 0.3)
	elif _charging():
		# Go around the side of the map, then turn in toward the crown.
		_go(Task.STEAL, Vector3(lane, 0, FLANK_DEPTH * side), 6.0)
	elif depth < RALLY_DEPTH - 40.0:
		_go(Task.STEAL, theirs.position, 0.3)  # already committed, don't walk back
	else:
		var spread := float(absi(player.peer_id) % 5 - 2) * 3.0
		_go(Task.ESCORT, Vector3(lane + spread, 0, RALLY_DEPTH * side), 4.0)


## True while this team's attack wave is on. Teams are offset by half a period.
func _charging() -> bool:
	var t := _match_time() - ATTACK_AFTER + (WAVE_PERIOD * 0.5 if player.team == 1 else 0.0)
	return t >= 0.0 and fmod(t, WAVE_PERIOD) < WAVE_CHARGE


## Which flank (-1 or 1) this team's current wave uses; alternates every wave.
func _lane() -> float:
	var wave := int(floor((_match_time() - ATTACK_AFTER) / WAVE_PERIOD))
	return 1.0 if (wave + player.team) % 2 == 0 else -1.0


func _plan_guard() -> void:
	var home := GameData.crown_pos(player.team)
	var toward_middle := Vector3(0, 0, -GameData.team_sign(player.team))
	var angle := float(absi(player.peer_id) % 7 - 3) * 0.35
	var spot := home + toward_middle.rotated(Vector3.UP, angle) * 10.0
	_go(Task.GUARD, Vector3(spot.x, 0, spot.z), 1.5)


func _plan_gather(rec: PlayerRecord, wanted := "") -> void:
	if wanted == "":
		wanted = _needed_resource(rec)
	var best: ResourceNode = null
	var best_d := INF
	var me := player.sync_pos
	for r in world.resource_nodes:
		if r.amount <= 0 or r.res_type != wanted:
			continue
		var d := me.distance_squared_to(r.global_position)
		if d < best_d:
			best = r
			best_d = d
	if best == null and wanted != "wood":
		wanted = "wood"
		for r in world.resource_nodes:
			if r.amount > 0 and r.res_type == "wood":
				var d := me.distance_squared_to(r.global_position)
				if d < best_d:
					best = r
					best_d = d
	if best:
		_go(Task.GATHER, best.global_position, best.radius + 1.0, best)
	else:
		_plan_guard()


## Picks the nearest buildable piece of the team's defensive layout that we can afford.
func _plan_build(rec: PlayerRecord) -> bool:
	if task == Task.BUILD:
		return true
	var best_d := INF
	for entry: Array in build_plan(player.team, rec):
		var item: String = entry[0]
		var slot: Dictionary = entry[1]
		if not rec.is_unlocked(item) or not rec.inventory.has_all(GameData.item(item)["recipe"]):
			continue
		if world.placement_problem(item, slot, false) != "":
			continue
		var d := player.sync_pos.distance_to(BuildGrid.center_of(BuildGrid.kind_of(item), slot))
		if d < best_d:
			best_d = d
			_build_item = item
			_build_slot = slot
	if best_d == INF:
		return false
	var center := BuildGrid.center_of(BuildGrid.kind_of(_build_item), _build_slot)
	var home := GameData.crown_pos(player.team)
	var inward := Vector3(home.x - center.x, 0, home.z - center.z).normalized()
	_go(Task.BUILD, center + inward * 2.5, 1.0)
	return true


## A square ring of walls (with walking gaps) around the crown, ballistas inside the
## front corners, and spike traps outside the front gaps. [item, slot] pairs.
static func build_plan(team: int, rec: PlayerRecord) -> Array:
	var home := GameData.crown_pos(team)
	var ci := roundi(home.x / BuildGrid.CELL)
	var cj := roundi(home.z / BuildGrid.CELL)
	var s := int(GameData.team_sign(team))
	var front_j := cj - RING - 1 if s > 0 else cj + RING
	var back_j := cj + RING if s > 0 else cj - RING - 1
	var wall := "stone_wall" if rec == null or rec.inventory.count("stone") >= 10 else "wood_wall"
	var out := []
	for i in range(ci - RING, ci + RING + 1):
		if absi(i - ci) != 2:  # gaps to walk through
			out.append([wall, BuildGrid.make_slot(i, front_j, 0, 0)])
	for j in range(cj - RING, cj + RING + 1):
		if j != cj:
			out.append([wall, BuildGrid.make_slot(ci + RING, j, 0, 1)])
			out.append([wall, BuildGrid.make_slot(ci - RING - 1, j, 0, 1)])
	for i in range(ci - RING, ci + RING + 1):
		if i != ci:
			out.append([wall, BuildGrid.make_slot(i, back_j, 0, 0)])
	var inside_front := cj - s * 2
	out.append(["ballista", BuildGrid.make_slot(ci - 2, inside_front, 0)])
	out.append(["ballista", BuildGrid.make_slot(ci + 2, inside_front, 0)])
	var outside_front := cj - s * (RING + 1)
	out.append(["spike_trap", BuildGrid.make_slot(ci - 2, outside_front, 0)])
	out.append(["spike_trap", BuildGrid.make_slot(ci + 2, outside_front, 0)])
	return out


# =============================================================================
# Inventory: crafting, shopping, consumables
# =============================================================================

func _manage_inventory(rec: PlayerRecord) -> void:
	player.shield_item = rec.shield()
	# Use consumables that should be used right away.
	if gm.clock >= rec.next_action_time:
		for id in ["skillbook_gatherer", "skillbook_vigor"]:
			if rec.inventory.count(id) > 0:
				gm.perform_primary(player.peer_id, id, Vector3.FORWARD, Vector3.ZERO)
				return
		if rec.inventory.count("horse_saddle") > 0 and not player.mounted:
			gm.perform_primary(player.peer_id, "horse_saddle", Vector3.FORWARD, Vector3.ZERO)
			return
		if rec.inventory.count("health_potion") > 0 and player.health < player.max_health * 0.45:
			gm.perform_primary(player.peer_id, "health_potion", Vector3.FORWARD, Vector3.ZERO)
			return
	# Learn the next spell on our list once we can pay for it.
	for id: String in SPELLS[role]:
		if rec.unlocks.has(id):
			continue
		if rec.gold >= int(GameData.item(id)["unlock_cost"]) and rec.inventory.has_all(GameData.learn_materials(id)):
			gm.perform_unlock(player.peer_id, id)
		break
	# Buy one blueprint we can afford.
	for id: String in SHOPPING[role]:
		if not rec.is_unlocked(id):
			if rec.gold >= int(GameData.item(id)["unlock_cost"]):
				gm.perform_unlock(player.peer_id, id)
			break
	# Craft the first wishlist item we can.
	for entry: Array in WISHLIST[role]:
		var id: String = entry[0]
		if rec.inventory.count(id) >= int(entry[1]) or not rec.is_unlocked(id):
			continue
		if rec.inventory.has_all(GameData.item(id)["recipe"]):
			gm.perform_craft(player.peer_id, id)
			return


func _wishlist_done(rec: PlayerRecord) -> bool:
	for entry: Array in WISHLIST[role]:
		var id: String = entry[0]
		if rec.is_unlocked(id) and rec.inventory.count(id) < int(entry[1]):
			return false
	return true


## The resource most needed for the next wishlist item.
func _needed_resource(rec: PlayerRecord) -> String:
	var has_pick := rec.inventory.count("pickaxe") > 0
	for entry: Array in WISHLIST[role]:
		var id: String = entry[0]
		if rec.inventory.count(id) >= int(entry[1]) or not rec.is_unlocked(id):
			continue
		var recipe: Dictionary = GameData.item(id)["recipe"]
		var worst := ""
		var worst_gap := 0
		for res: String in recipe:
			var gap := int(recipe[res]) - rec.inventory.count(res)
			if gap > worst_gap and (has_pick or res in ["wood", "stone"]):
				worst = res
				worst_gap = gap
		if worst != "":
			return worst
	var reserves: Dictionary = RESERVES[role]
	for res: String in reserves:
		if rec.inventory.count(res) < int(reserves[res]) and (has_pick or res in ["wood", "stone"]):
			return res
	return "stone" if rec.inventory.count("stone") < rec.inventory.count("wood") else "wood"


func _armed(rec: PlayerRecord) -> bool:
	return _melee_weapon(rec) in ["war_hammer", "iron_sword", "wooden_club"] or _ranged_weapon(rec) != ""


func _melee_weapon(rec: PlayerRecord) -> String:
	for id: String in MELEE_PREFERENCE:
		if rec.inventory.count(id) > 0:
			return id
	return ""


func _ranged_weapon(rec: PlayerRecord) -> String:
	if rec.inventory.count("arrow") <= 0:
		return ""
	for id in ["crossbow", "shortbow"]:
		if rec.inventory.count(id) > 0:
			return id
	return ""


func _best_tool(rec: PlayerRecord, res_type: String) -> String:
	var best := ""
	var best_power := int(GameData.FISTS["gather"].get(res_type, 0))
	for id: String in GameData.ITEMS:
		var def: Dictionary = GameData.ITEMS[id]
		if def["kind"] in GameData.MELEE_KINDS and rec.inventory.count(id) > 0:
			var power := int(def.get("gather", {}).get(res_type, 0))
			if power > best_power:
				best = id
				best_power = power
	return best


func _siege_weapon(rec: PlayerRecord) -> String:
	var best := ""
	var best_dmg := float(GameData.FISTS["structure_damage"])
	for id: String in MELEE_PREFERENCE:
		if rec.inventory.count(id) > 0 and float(GameData.item(id)["structure_damage"]) > best_dmg:
			best = id
			best_dmg = float(GameData.item(id)["structure_damage"])
	return best


## The closest enemy to fight: a player, or an enemy spectral warrior.
func _nearest_enemy(max_range: float) -> Node3D:
	var best: Node3D = gm.nearest_enemy(player.sync_pos, player.team, max_range)
	var best_d := player.sync_pos.distance_to(best.sync_pos) if best else max_range
	for w in world.get_summons():
		if w.team != player.team:
			var d := player.sync_pos.distance_to(w.global_position)
			if d <= best_d:
				best = w
				best_d = d
	return best


# Foes are players or spectral warriors; these treat both alike.
static func _foe_alive(foe: Node) -> bool:
	if foe == null or not is_instance_valid(foe) or foe.is_queued_for_deletion():
		return false
	if foe is Player:
		return (foe as Player).alive and not (foe as Player).cloaked  # can't fight what you can't see
	return foe is Summon


static func _foe_pos(foe: Node3D) -> Vector3:
	return (foe as Player).sync_pos if foe is Player else foe.global_position


static func _foe_chest(foe: Node3D) -> Vector3:
	return (foe as Player).chest() if foe is Player else (foe as Summon).chest()


# =============================================================================
# Movement
# =============================================================================

func _steer(delta: float) -> void:
	var me := player.global_position
	if task == Task.FIGHT or (task == Task.ESCORT and target != null):
		if _foe_alive(target):
			goal = _foe_pos(target as Node3D)
		else:
			task = Task.IDLE
			target = null
	var to_goal := Vector3(goal.x - me.x, 0, goal.z - me.z)
	var dist := to_goal.length()
	var moving := task != Task.IDLE and dist > stop_distance
	var move_dir := to_goal.normalized() if moving else Vector3.ZERO

	_climb_timer -= delta
	if _detour_timer > 0.0:
		_detour_timer -= delta
		move_dir = _detour
	elif moving and _climb_timer <= 0.0:
		var blocker := _probe(move_dir)
		if blocker is Structure and (blocker as Structure).team != player.team:
			var wall := blocker as Structure
			if _try_ladder(wall):
				_climb_timer = 4.0  # keep pushing forward: up the ladder and over
			else:
				_go(Task.SIEGE, wall.closest_point(me), 1.5, blocker)
				moving = false
				move_dir = Vector3.ZERO
		elif blocker != null:
			var side := 1.0 if (absi(player.peer_id) + int(gm.clock)) % 2 == 0 else -1.0
			_detour = move_dir.rotated(Vector3.UP, side * deg_to_rad(75.0))
			_detour_timer = 0.5

	_stuck_timer += delta
	if _stuck_timer > 0.8:
		if moving and me.distance_to(_last_pos) < 0.5:
			_detour = move_dir.rotated(Vector3.UP, randf_range(-2.2, 2.2)).normalized()
			_detour_timer = 0.9
			player.wants_jump = true
		_stuck_timer = 0.0
		_last_pos = me

	# Face the target when working on something, otherwise the way we're walking.
	var face := move_dir
	if is_instance_valid(target) and not moving:
		var tp := _target_point()
		face = Vector3(tp.x - me.x, 0, tp.z - me.z).normalized()
	if face.length_squared() > 0.01:
		player.rotation.y = lerp_angle(player.rotation.y, atan2(-face.x, -face.z), clampf(delta * 12.0, 0.0, 1.0))
	var local := player.global_basis.inverse() * move_dir
	player.move_input = Vector2(local.x, local.z)
	player.wants_sprint = moving and dist > 5.0


## Throw a ladder against an enemy wall in our way. Attackers only.
func _try_ladder(wall: Structure) -> bool:
	if role != Role.ATTACKER or wall.kind != "wall" and wall.kind != "door":
		return false
	var rec := _rec()
	var me := player.sync_pos
	var slot := wall.slot.duplicate()
	var line := wall.global_position
	if slot["axis"] == 0:
		slot["side"] = 1 if me.z > line.z else -1
	else:
		slot["side"] = 1 if me.x > line.x else -1
	var key := BuildGrid.key("ladder", slot)
	if world.pieces.has(key):
		return true  # already a ladder here: climb it
	if rec == null or rec.inventory.count("wood") < 4:
		return false
	return gm.perform_build(player.peer_id, "ladder", slot)


func _probe(dir: Vector3) -> Object:
	var space := player.get_world_3d().direct_space_state
	var from := player.global_position + Vector3(0, 0.9, 0)
	_ray.from = from
	_ray.to = from + dir * 1.4
	var hit := space.intersect_ray(_ray)
	return hit.get("collider") if not hit.is_empty() else null


func _target_point() -> Vector3:
	if not is_instance_valid(target):
		return goal
	if target is Player:
		return (target as Player).sync_pos
	if target is Structure:
		return (target as Structure).closest_point(player.sync_pos)
	if target is Node3D:
		return (target as Node3D).global_position
	return goal


# =============================================================================
# Actions
# =============================================================================

func _act() -> void:
	var rec := _rec()
	if rec == null:
		return
	if gm.clock < rec.next_action_time:
		# Between swings in a melee, hold the shield up.
		var fighting := task == Task.FIGHT and _foe_alive(target)
		player.blocking = player.shield_item != "" and fighting \
			and GameData.flat_distance(player.sync_pos, _foe_pos(target as Node3D)) < 4.0
		return
	# Sneaking in for the crown: go invisible on the approach.
	if task == Task.STEAL and rec.unlocks.has("shadow_cloak") and not player.cloaked \
			and player.carrying_crown < 0 and gm.clock >= float(rec.spell_ready.get("shadow_cloak", 0.0)) \
			and player.sync_pos.distance_to(goal) < 90.0 \
			and player.mana >= GameData.spell_mana(GameData.item("shadow_cloak"), rec.rank("spellweaver")):
		player.equipped = "shadow_cloak"
		if gm.perform_primary(player.peer_id, "shadow_cloak", Vector3.FORWARD, Vector3.ZERO):
			player.play_action_anim("spell")
			return
	match task:
		Task.GATHER:
			var node := target as ResourceNode
			if node == null or node.amount <= 0:
				task = Task.IDLE
				return
			if GameData.flat_distance(player.sync_pos, node.global_position) - node.radius <= 2.0:
				_use(_best_tool(rec, node.res_type), node.global_position - player.sync_pos)
		Task.FIGHT:
			_fight(rec)
		Task.SIEGE:
			if not is_instance_valid(target) or target.is_queued_for_deletion():
				task = Task.IDLE
				target = null
				return
			var s := target as Structure
			var weapon := _siege_weapon(rec)
			var cp := s.closest_point(player.sync_pos)
			if GameData.flat_distance(player.sync_pos, cp) <= float(GameData.item(weapon)["range"]):
				_use(weapon, cp - player.sync_pos)
			else:
				goal = cp
		Task.BUILD:
			var center := BuildGrid.center_of(BuildGrid.kind_of(_build_item), _build_slot)
			if player.chest().distance_to(center) <= BuildGrid.REACH - 1.0:
				player.equipped = _build_item
				if not gm.perform_build(player.peer_id, _build_item, _build_slot):
					rec.next_action_time = gm.clock + 0.3
				task = Task.IDLE
		_:
			# On the move: still hit anyone right next to us.
			var foe := _nearest_enemy(2.5)
			if foe:
				_use(_melee_weapon(rec), _foe_pos(foe) - player.sync_pos)


func _fight(rec: PlayerRecord) -> void:
	if not is_instance_valid(target):
		task = Task.IDLE
		target = null
		return
	if not _foe_alive(target):
		task = Task.IDLE
		target = null
		return
	var foe := target as Node3D
	var foe_pos := _foe_pos(foe)
	var dist := GameData.flat_distance(player.sync_pos, foe_pos)
	if _try_spell(rec, foe, dist):
		return
	var ranged := _ranged_weapon(rec)
	if ranged != "" and dist > 5.0:
		var def := GameData.item(ranged)
		if dist > float(def["range"]) * 0.8:
			return
		var from := player.sync_pos + Vector3(0, 1.5, 0)
		var to := _foe_chest(foe)
		var flight := dist / float(def["speed"])
		to.y += 0.5 * GameData.ARROW_GRAVITY * flight * flight
		var aim := (to - from).normalized()
		var spread := 0.02 + dist * 0.0015  # bots get worse at range
		aim = aim.rotated(Vector3.UP, randf_range(-spread, spread))
		aim.y += randf_range(-spread, spread) * 0.5
		player.equipped = ranged
		if gm.perform_primary(player.peer_id, ranged, aim, Vector3.ZERO):
			player.play_action_anim("ranged")
		return
	var weapon := _melee_weapon(rec)
	player.blocking = false
	if dist <= float(GameData.item(weapon)["range"]) + 0.3:
		_use(weapon, foe_pos - player.sync_pos)


## Cast a learned spell if the moment is right. True if one was cast.
func _try_spell(rec: PlayerRecord, foe: Node3D, dist: float) -> bool:
	var carrier := foe is Player and (foe as Player).carrying_crown >= 0
	if gm.clock < rec.next_action_time:
		return false
	var weave := rec.rank("spellweaver")
	for id: String in SPELLS[role]:
		if not rec.unlocks.has(id) or gm.clock < float(rec.spell_ready.get(id, 0.0)):
			continue
		var def := GameData.item(id)
		if player.mana < GameData.spell_mana(def, weave):
			continue
		var want := false
		match id:
			"spectral_warriors":
				want = dist < 30.0
			"gust":
				want = dist < 6.0 or (carrier and dist < 8.5)
			"meteor":
				want = dist > 8.0 and dist < float(def["range"]) * 0.8
			"heal_aura":
				want = player.health < player.max_health * 0.6
			"thunderclap":
				want = dist < 4.0
			"magic_missiles":
				want = dist > 3.0 and dist < float(def["range"]) * 0.9
			"chain_hook":
				want = (carrier and dist < float(def["range"]) * 0.9) or (dist > 7.0 and dist < 16.0)
			"siphon_life":
				want = dist < float(def["range"]) * 0.8 and player.health < player.max_health * 0.85
			"battle_cry":
				want = dist < 25.0
			"arcane_ward":
				want = dist < 15.0 and not player.warded
			"fireball", "frost_bolt", "lightning":
				want = dist > 4.0 and dist < float(def["range"]) * 0.8
		if not want:
			continue
		var aim := (_foe_chest(foe) - (player.sync_pos + Vector3(0, 1.5, 0))).normalized()
		if id == "meteor":
			aim = (_foe_pos(foe) - (player.sync_pos + Vector3(0, 1.5, 0))).normalized()
		player.equipped = id
		if gm.perform_primary(player.peer_id, id, aim, Vector3.ZERO):
			player.play_action_anim("spell")
			return true
	return false


func _use(item_id: String, direction: Vector3) -> void:
	player.equipped = item_id
	direction.y = 0.0
	if gm.perform_primary(player.peer_id, item_id, direction.normalized(), Vector3.ZERO):
		player.play_action_anim(GameData.item(item_id)["kind"])
