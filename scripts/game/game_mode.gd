class_name GameMode
extends Node
## Server-authoritative match rules: teams, bots, combat, gathering, crafting, the gold
## shop, building, and the crown capture-the-flag loop.
##
## Clients never change game state directly. They call request(...), the server
## validates it, then pushes results back: shared state (scores, crowns, scoreboard) to
## everyone, private state (inventory, gold, unlocks) only to the owning player.
## Bots are server-side players with negative peer ids that use the same perform_*()
## entry points as humans.

signal private_updated
signal scores_updated
signal crowns_updated
signal scoreboard_updated
signal message_received(text: String)
signal match_over_changed
signal hit_confirmed(killed: bool)

const SCOREBOARD_INTERVAL := 1.0
const MOVE_CHECK_INTERVAL := 0.5
const BUILD_COOLDOWN := 0.2

var world: World
## Game time in seconds, advanced on every peer. Used for cooldowns and timers.
var clock := 0.0

# --- Replicated to every peer -------------------------------------------------
var scores: Array = [0, 0]
var crowns: Array[CrownState] = []
var match_over := false
var winner := -1
## Rows of [name, team, kills, deaths, captures, is_bot].
var scoreboard: Array = []

# --- This client's private state (copied from the server) ---------------------
var my_inventory: Dictionary = {}
var my_gold := 0
var my_unlocks: Array = []
var my_stats: Dictionary = {}

# --- Server only ----------------------------------------------------------------
var server_running := false
var match_started_at := 0.0
var records: Dictionary = {}  ## peer id -> PlayerRecord
var team_fill := 0
var _generation := 0  ## bumps on match reset, so stale timers do nothing
var _next_structure_uid := 1
var _next_bot_id := -1
var _bot_name_index := 0
var _scoreboard_dirty := true
var _scoreboard_timer := 0.0
var _collapse_pending := false


func _ready() -> void:
	add_to_group("game_mode")
	world = get_parent() as World
	for t in GameData.TEAM_COUNT:
		crowns.append(CrownState.new(t))
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


# =============================================================================
# Messaging helpers
# =============================================================================

## Send a request to the server. Works for the host's own player too.
func request(method: StringName, args: Array = []) -> void:
	_send_to(1, method, args)


func _send_to(peer: int, method: StringName, args: Array = []) -> void:
	if peer == multiplayer.get_unique_id():
		callv(method, args)
	elif peer > 0 and multiplayer.get_peers().has(peer):  # bots and departed peers get nothing
		var call_args: Array = [peer, method]
		call_args.append_array(args)
		callv("rpc_id", call_args)


func _broadcast(method: StringName, args: Array = []) -> void:
	var call_args: Array = [method]
	call_args.append_array(args)
	callv("rpc", call_args)


## Peer that sent the current request (the host's local calls report 0).
func _sender() -> int:
	var id := multiplayer.get_remote_sender_id()
	return id if id != 0 else multiplayer.get_unique_id()


func _tell(peer: int, text: String) -> void:
	_send_to(peer, &"_message", [text])


func _announce(text: String) -> void:
	print("[match] " + text)
	_broadcast(&"_message", [text])


# =============================================================================
# Connection lifecycle
# =============================================================================

func server_start() -> void:
	server_running = true
	match_started_at = clock
	team_fill = Net.team_fill
	print("[server] Match started with map seed %d, teams filled to %d with bots" % [world.map_seed, team_fill])
	if not Net.is_dedicated():
		_register(1, Net.player_name)
	_balance_bots()


func _on_connected_to_server() -> void:
	request(&"register_player", [Net.player_name])


func _on_connection_failed() -> void:
	Net.leave("Could not connect to %s:%d." % [Net.address, Net.port])


func _on_server_disconnected() -> void:
	Net.leave("Lost connection to the server.")


@rpc("any_peer", "call_local", "reliable")
func register_player(player_name: String) -> void:
	if not server_running:
		return
	var peer := _sender()
	if not records.has(peer):
		_register(peer, player_name)


func _register(peer: int, player_name: String) -> void:
	player_name = player_name.strip_edges().substr(0, 20)
	if player_name == "":
		player_name = "Peasant %d" % (records.size() + 1)
	var team := _pick_team_for_human()
	if team < 0:
		_send_to(peer, &"_rejected", ["The match is full."])
		return
	_add_player(peer, player_name, team)
	_balance_bots()


func _add_player(peer: int, player_name: String, team: int) -> PlayerRecord:
	var rec := PlayerRecord.new(peer, player_name, team)
	records[peer] = rec
	if peer > 0 and peer != multiplayer.get_unique_id():
		_send_to(peer, &"_welcome", [world.map_seed, _snapshot()])
	var pos := GameData.spawn_point(team)
	rec.last_valid_pos = pos
	rec.last_move_check = clock
	rec.protected_until = clock + GameData.SPAWN_PROTECTION
	world.player_spawner.spawn({
		"peer_id": peer, "team": team, "name": player_name, "pos": pos, "bot": peer < 0,
	})
	if peer < 0:
		var brain := BotBrain.new()
		brain.name = "Brain"
		world.get_player(peer).add_child(brain)
	_push_private(peer)
	_scoreboard_dirty = true
	if peer > 0:
		_announce("%s joined the %s." % [player_name, GameData.team_name(team)])
	return rec


func _team_counts(humans_only: bool) -> Array:
	var counts := []
	counts.resize(GameData.TEAM_COUNT)
	counts.fill(0)
	for rec: PlayerRecord in records.values():
		if not humans_only or not rec.is_bot:
			counts[rec.team] += 1
	return counts


## Humans go to the team with fewer humans, bumping a bot if that team is full.
func _pick_team_for_human() -> int:
	var humans := _team_counts(true)
	var totals := _team_counts(false)
	var order := range(GameData.TEAM_COUNT)
	order.sort_custom(func(a: int, b: int) -> bool:
		return humans[a] < humans[b] or (humans[a] == humans[b] and totals[a] < totals[b]))
	for t: int in order:
		if totals[t] < GameData.TEAM_SIZE:
			return t
		if _remove_bot(t):
			return t
	return -1


## Add or remove bots so each team has `team_fill` players (never removing humans).
func _balance_bots() -> void:
	if not server_running:
		return
	for t in GameData.TEAM_COUNT:
		var total: int = _team_counts(false)[t]
		while total < team_fill:
			_add_bot(t)
			total += 1
		while total > team_fill and _remove_bot(t):
			total -= 1


func _add_bot(team: int) -> void:
	var bot_name: String = GameData.BOT_NAMES[_bot_name_index % GameData.BOT_NAMES.size()]
	if _bot_name_index >= GameData.BOT_NAMES.size():
		bot_name += " %d" % (_bot_name_index / GameData.BOT_NAMES.size() + 1)
	_bot_name_index += 1
	_add_player(_next_bot_id, bot_name, team)
	_next_bot_id -= 1


func _remove_bot(team: int) -> bool:
	for rec: PlayerRecord in records.values():
		if rec.is_bot and rec.team == team:
			_remove_player(rec.peer_id)
			return true
	return false


func _remove_player(peer: int) -> void:
	var p := world.get_player(peer)
	if p:
		if p.carrying_crown >= 0:
			_drop_crown(crowns[p.carrying_crown], p.sync_pos)
		p.queue_free()
	records.erase(peer)
	_scoreboard_dirty = true


func _on_peer_disconnected(peer: int) -> void:
	if not server_running or not records.has(peer):
		return
	var player_name: String = records[peer].name
	_remove_player(peer)
	_announce("%s left." % player_name)
	_balance_bots.call_deferred()


func _snapshot() -> Dictionary:
	return {
		"scores": scores,
		"crowns": _crown_dicts(),
		"resources": world.resource_snapshot(),
		"match_over": match_over,
		"winner": winner,
		"pieces": world.piece_states(),
	}


func _push_private(peer: int) -> void:
	var rec: PlayerRecord = records.get(peer)
	if rec and not rec.is_bot:
		_send_to(peer, &"_private", [rec.inventory.to_dict(), rec.gold, rec.unlocks.keys(), rec.stats()])


func _teleport_player(peer: int, pos: Vector3) -> void:
	var rec: PlayerRecord = records.get(peer)
	if rec:
		rec.last_valid_pos = pos
		rec.last_move_check = clock
	if peer < 0:
		var p := world.get_player(peer)
		if p:
			p.teleport(pos)
	else:
		_send_to(peer, &"_teleport", [pos])


# =============================================================================
# Client-side receivers
# =============================================================================

@rpc("authority", "call_local", "reliable")
func _welcome(seed_value: int, snapshot: Dictionary) -> void:
	world.generate(seed_value)
	scores = snapshot["scores"]
	_apply_crowns(snapshot["crowns"])
	world.apply_resource_snapshot(snapshot["resources"])
	world.apply_piece_states(snapshot.get("pieces", {}))
	match_over = snapshot["match_over"]
	winner = snapshot["winner"]
	scores_updated.emit()
	match_over_changed.emit()


@rpc("authority", "call_local", "reliable")
func _rejected(reason: String) -> void:
	Net.leave(reason)


@rpc("authority", "call_local", "reliable")
func _private(inventory: Dictionary, gold: int, unlocks: Array, stats: Dictionary) -> void:
	my_inventory = inventory
	my_gold = gold
	my_unlocks = unlocks
	my_stats = stats
	private_updated.emit()


@rpc("authority", "call_local", "reliable")
func _scores(new_scores: Array) -> void:
	scores = new_scores
	scores_updated.emit()


@rpc("authority", "call_local", "reliable")
func _crowns(data: Array) -> void:
	_apply_crowns(data)


@rpc("authority", "call_local", "reliable")
func _scoreboard(rows: Array) -> void:
	scoreboard = rows
	scoreboard_updated.emit()


@rpc("authority", "call_local", "reliable")
func _message(text: String) -> void:
	message_received.emit(text)


@rpc("authority", "call_local", "unreliable")
func _hit_marker(killed: bool) -> void:
	hit_confirmed.emit(killed)


@rpc("authority", "call_local", "reliable")
func _match_state(over: bool, winning_team: int) -> void:
	match_over = over
	winner = winning_team
	match_over_changed.emit()


@rpc("authority", "call_local", "reliable")
func _teleport(pos: Vector3) -> void:
	var p := world.local_player()
	if p:
		p.teleport(pos)


func _apply_crowns(data: Array) -> void:
	for d: Dictionary in data:
		crowns[d["team"]].apply_dict(d, clock)
	crowns_updated.emit()


## Hotbar contents for the local player. Page 0 is normal play: fists, then owned
## items. Pages 1+ are build mode: the unlocked building pieces of that category
## (paid for when placed).
func hotbar_items(build_page := 0) -> Array[String]:
	return hotbar_for(my_inventory, my_unlocks, build_page)


static func hotbar_for(inventory: Dictionary, unlocks: Array, build_page := 0) -> Array[String]:
	var out: Array[String] = []
	if build_page <= 0:
		out.append("")
	var category: String = GameData.BUILD_CATEGORIES[build_page - 1] if build_page > 0 else ""
	for id: String in GameData.ITEMS:
		var def: Dictionary = GameData.ITEMS[id]
		if build_page > 0:
			if def["kind"] == "structure" and def.get("category", "") == category \
					and (int(def["unlock_cost"]) <= 0 or unlocks.has(id)):
				out.append(id)
		elif def["kind"] == "spell":
			if unlocks.has(id):
				out.append(id)
		elif not def["kind"] in ["ammo", "structure", "shield"] and int(inventory.get(id, 0)) > 0:
			out.append(id)
	return out


func is_unlocked_locally(id: String) -> bool:
	return int(GameData.item(id).get("unlock_cost", 0)) <= 0 or my_unlocks.has(id)


# =============================================================================
# Requests (client -> server). Each is a thin wrapper around perform_*().
# =============================================================================

@rpc("any_peer", "call_local", "reliable")
func request_craft(item_id: String) -> void:
	if server_running:
		perform_craft(_sender(), item_id)


@rpc("any_peer", "call_local", "reliable")
func request_unlock(item_id: String) -> void:
	if server_running:
		perform_unlock(_sender(), item_id)


## Left click: swing, shoot, place, or use whatever is equipped.
@rpc("any_peer", "call_local", "reliable")
func request_primary(item_id: String, aim_dir: Vector3, target: Vector3) -> void:
	if server_running:
		perform_primary(_sender(), item_id, aim_dir, target)


## Place a building piece in a grid slot, paying its recipe from resources.
@rpc("any_peer", "call_local", "reliable")
func request_build(item_id: String, slot: Dictionary) -> void:
	if server_running:
		perform_build(_sender(), item_id, slot)


func perform_build(peer: int, item_id: String, slot: Dictionary) -> bool:
	if match_over:
		return false
	var rec: PlayerRecord = records.get(peer)
	var p := world.get_player(peer)
	if rec == null or p == null or not p.alive or clock < rec.next_action_time:
		return false
	var def := GameData.item(item_id)
	if def.get("kind", "") != "structure":
		return false
	if not rec.is_unlocked(item_id):
		_tell(peer, "Buy the %s blueprint first." % def["name"])
		return false
	slot = BuildGrid.sanitize(slot)
	var kind := BuildGrid.kind_of(item_id)
	if p.chest().distance_to(BuildGrid.center_of(kind, slot)) > BuildGrid.REACH + 1.0:
		return false
	var problem := world.placement_problem(item_id, slot)
	if problem != "":
		_tell(peer, problem)
		return false
	var price := GameData.build_cost(def["recipe"], rec.rank("mason"))
	if not rec.inventory.pay(price):
		_tell(peer, "Not enough resources: %s needs %s." % [def["name"], GameData.cost_text(price)])
		return false
	rec.next_action_time = clock + BUILD_COOLDOWN
	world.structure_spawner.spawn({
		"uid": _next_structure_uid, "item": item_id, "team": rec.team, "owner": peer, "slot": slot,
	})
	_next_structure_uid += 1
	_push_private(peer)
	return true


## E key: lower/raise your team's drawbridge, or fire your team's catapult.
@rpc("any_peer", "call_local", "reliable")
func request_interact(aim_dir: Vector3) -> void:
	if server_running:
		perform_interact(_sender(), aim_dir)


func perform_interact(peer: int, aim_dir: Vector3) -> bool:
	if match_over:
		return false
	var rec: PlayerRecord = records.get(peer)
	var p := world.get_player(peer)
	if rec == null or p == null or not p.alive:
		return false
	var s := world.interactable_near(p.sync_pos, rec.team)
	if s == null:
		return false
	if s.is_drawbridge():
		if clock < rec.next_action_time:
			return false
		rec.next_action_time = clock + 1.0
		s.opened = not s.opened
		world.piece_open.rpc(s.name, s.opened)
		return true
	if s.is_catapult():
		return _fire_catapult(rec, s, aim_dir)
	return false


## F key in build mode: patch up one of your team's damaged pieces.
@rpc("any_peer", "call_local", "reliable")
func request_repair(structure_name: String) -> void:
	if server_running:
		perform_repair(_sender(), structure_name)


func perform_repair(peer: int, structure_name: String) -> bool:
	var rec: PlayerRecord = records.get(peer)
	var s := _own_piece_in_reach(peer, structure_name)
	if s == null or s.health >= s.max_health:
		return false
	var cost := repair_cost(s)
	if not rec.inventory.pay(cost):
		_tell(peer, "Repairing needs %s." % GameData.cost_text(cost))
		return false
	s.health = s.max_health
	world.structure_health.rpc(s.name, 1.0)
	world.fx_repair.rpc(s.global_position + Vector3(0, 1.5, 0))
	_push_private(peer)
	return true


## Half the piece's price, scaled by how damaged it is (at least 1 of each).
static func repair_cost(s: Structure) -> Dictionary:
	var missing := 1.0 - s.health / s.max_health
	var cost := {}
	var recipe: Dictionary = GameData.item(s.item_id)["recipe"]
	for res: String in recipe:
		cost[res] = maxi(1, ceili(int(recipe[res]) * missing * 0.5))
	return cost


## G key in build mode: rebuild a wood piece in stone, in place.
@rpc("any_peer", "call_local", "reliable")
func request_upgrade(structure_name: String) -> void:
	if server_running:
		perform_upgrade(_sender(), structure_name)


func perform_upgrade(peer: int, structure_name: String) -> bool:
	var rec: PlayerRecord = records.get(peer)
	var s := _own_piece_in_reach(peer, structure_name)
	if s == null:
		return false
	var target: String = GameData.item(s.item_id).get("upgrade", "")
	if target == "" or not rec.is_unlocked(target):
		return false
	var recipe: Dictionary = GameData.item(target)["recipe"]
	if not rec.inventory.pay(recipe):
		_tell(peer, "Upgrading needs %s." % GameData.cost_text(recipe))
		return false
	var slot := s.slot.duplicate()
	var piece_team := s.team
	world.unregister_piece(s)
	s.queue_free()
	world.structure_spawner.spawn({
		"uid": _next_structure_uid, "item": target, "team": piece_team, "owner": peer, "slot": slot,
	})
	_next_structure_uid += 1
	_push_private(peer)
	return true


func _own_piece_in_reach(peer: int, structure_name: String) -> Structure:
	var rec: PlayerRecord = records.get(peer)
	var p := world.get_player(peer)
	if rec == null or p == null or not p.alive or match_over:
		return null
	var s := world.structures_root.get_node_or_null(structure_name) as Structure
	if s == null or s.is_queued_for_deletion() or s.team != rec.team:
		return null
	if s.closest_point(p.chest()).distance_to(p.chest()) > BuildGrid.REACH:
		return null
	return s


func perform_craft(peer: int, item_id: String) -> bool:
	var rec: PlayerRecord = records.get(peer)
	if rec == null or not GameData.is_item(item_id):
		return false
	var def := GameData.item(item_id)
	if def["kind"] == "structure":
		return false  # placed directly in build mode, never crafted
	if not rec.is_unlocked(item_id):
		_tell(peer, "Buy the %s blueprint first." % def["name"])
		return false
	if not rec.inventory.pay(def["recipe"]):
		_tell(peer, "Not enough resources for %s." % def["name"])
		return false
	rec.inventory.add(item_id, int(def.get("yield", 1)))
	_push_private(peer)
	return true


func perform_unlock(peer: int, item_id: String) -> bool:
	var rec: PlayerRecord = records.get(peer)
	if rec == null or not GameData.is_item(item_id) or rec.is_unlocked(item_id):
		return false
	var cost: int = GameData.item(item_id)["unlock_cost"]
	var materials := GameData.learn_materials(item_id)
	if rec.gold < cost:
		_tell(peer, "You need %d gold." % cost)
		return false
	if not rec.inventory.has_all(materials):
		_tell(peer, "Learning that also needs %s." % GameData.cost_text(materials))
		return false
	rec.inventory.pay(materials)
	rec.gold -= cost
	rec.unlocks[item_id] = true
	var verb := "Learned" if GameData.item(item_id)["kind"] == "spell" else "Unlocked"
	_tell(peer, "%s %s!" % [verb, GameData.display_name(item_id)])
	_push_private(peer)
	return true


func perform_primary(peer: int, item_id: String, aim_dir: Vector3, target: Vector3) -> bool:
	if match_over:
		return false
	var rec: PlayerRecord = records.get(peer)
	if rec == null:
		return false
	var p := world.get_player(peer)
	if p == null or not p.alive or p.stunned or p.blocking:
		return false
	var def := GameData.item(item_id)
	if def.is_empty():
		return false
	if def["kind"] == "spell":
		if not rec.unlocks.has(item_id):
			return false
	elif item_id != "" and rec.inventory.count(item_id) <= 0:
		return false
	if clock < rec.next_action_time:
		return false
	# Small tolerance for network jitter.
	rec.next_action_time = clock + float(def.get("cooldown", 1.0)) * 0.85
	if aim_dir.length_squared() < 0.0001:
		aim_dir = -p.global_basis.z
	aim_dir = aim_dir.normalized()

	var kind: String = def["kind"]
	if kind in GameData.MELEE_KINDS:
		_melee(rec, p, def, aim_dir)
	elif kind == "ranged":
		return _shoot(rec, p, def, aim_dir)
	elif kind == "consumable":
		return _use_consumable(rec, p, item_id, def, aim_dir)
	elif kind == "spell":
		return _cast_spell(rec, p, item_id, def, aim_dir)
	return true


## Spend a skill point (rank n costs n points).
@rpc("any_peer", "call_local", "reliable")
func request_skill(skill: String) -> void:
	if server_running:
		perform_skill(_sender(), skill)


func perform_skill(peer: int, skill: String) -> bool:
	var rec: PlayerRecord = records.get(peer)
	if rec == null or not GameData.SKILLS.has(skill):
		return false
	var now := rec.rank(skill)
	var cost := GameData.skill_cost(now)
	if now >= int(GameData.SKILLS[skill]["max_rank"]) or rec.skill_points < cost:
		return false
	rec.skill_points -= cost
	rec.skills[skill] = now + 1
	var p := world.get_player(peer)
	if p:
		var gained := rec.max_health() - p.max_health
		p.max_health = rec.max_health()
		if p.alive and gained > 0.0:
			p.health += gained
		p.max_mana = rec.max_mana()
	_tell(peer, "%s is now rank %d." % [GameData.SKILLS[skill]["name"], now + 1])
	_push_private(peer)
	return true


# =============================================================================
# Spells
# =============================================================================

func _cast_spell(rec: PlayerRecord, p: Player, id: String, def: Dictionary, aim_dir: Vector3) -> bool:
	if clock < float(rec.spell_ready.get(id, 0.0)):
		return false
	var cost: float = def["mana"]
	if p.mana < cost:
		_tell(rec.peer_id, "Not enough mana.")
		return false
	var ok := true
	match id:
		"fireball":
			_cast_fireball(rec, p, def, aim_dir)
		"frost_bolt":
			_cast_frost(rec, p, def, aim_dir)
		"lightning":
			_cast_lightning(rec, p, def, aim_dir)
		"heal_aura":
			_cast_heal(rec, p, def)
		"blink":
			ok = _cast_blink(rec, p, def, aim_dir)
		"earth_wall":
			ok = _cast_earth_wall(rec, p, def, aim_dir)
		_:
			ok = false
	if ok:
		p.mana = maxf(p.mana - cost, 0.0)
		rec.spell_ready[id] = clock + float(def["cooldown"])
	return ok


## Walks a straight ray from start until it hits the ground, a solid piece, or (if
## enemy_team >= 0) an enemy. Returns [end point, Player hit or null].
func _trace(start: Vector3, dir: Vector3, max_range: float, enemy_team: int) -> Array:
	var point := start
	var travelled := 0.0
	var structures: Array[Structure] = []
	for s in world.get_structures():
		if not s.is_trap() and not s.is_ladder() and _near_segment(s.global_position, start, start + dir * max_range, 6.0):
			structures.append(s)
	while travelled < max_range:
		point += dir * 0.5
		travelled += 0.5
		if point.y <= Terrain.height(point.x, point.z):
			return [point, null]
		for p in world.get_players():
			if p.team == enemy_team and p.alive and p.chest().distance_to(point) < 1.0:
				return [point, p]
		for s in structures:
			if s.blocks_point(point):
				return [point, null]
	return [point, null]


func _cast_frost(rec: PlayerRecord, caster: Player, def: Dictionary, aim_dir: Vector3) -> void:
	var start := caster.sync_pos + Vector3(0, 1.5, 0)
	var hit := _trace(start, aim_dir, def["range"], 1 - rec.team)
	world.fx_spell.rpc("frost", start, hit[0])
	var victim: Player = hit[1]
	if victim:
		damage_player(victim.peer_id, def["damage"], rec.peer_id, "frost bolt", start)
		var vrec: PlayerRecord = records.get(victim.peer_id)
		if vrec and victim.alive:
			vrec.slow_until = clock + float(def["slow"])
			victim.slowed = true


func _cast_lightning(rec: PlayerRecord, caster: Player, def: Dictionary, aim_dir: Vector3) -> void:
	var start := caster.sync_pos + Vector3(0, 1.5, 0)
	var hit := _trace(start, aim_dir, def["range"], 1 - rec.team)
	var points: Array = [start, hit[0]]
	var victim: Player = hit[1]
	if victim:
		var struck: Array[Player] = [victim]
		var last := victim
		damage_player(victim.peer_id, def["damage"], rec.peer_id, "lightning", start)
		for k in int(def["chains"]):
			var next: Player = null
			var best := float(def["chain_range"])
			for p in world.get_players():
				if p.team != rec.team and p.alive and not struck.has(p) and p.chest().distance_to(last.chest()) <= best:
					next = p
					best = p.chest().distance_to(last.chest())
			if next == null:
				break
			struck.append(next)
			points.append(next.chest())
			damage_player(next.peer_id, def["chain_damage"], rec.peer_id, "lightning", last.chest())
			last = next
	world.fx_lightning.rpc(points)


func _cast_heal(rec: PlayerRecord, caster: Player, def: Dictionary) -> void:
	var radius: float = def["radius"]
	for p in world.get_players():
		if p.team == rec.team and p.alive and p.sync_pos.distance_to(caster.sync_pos) <= radius:
			p.health = minf(p.max_health, p.health + float(def["heal"]))
	world.fx_spell.rpc("heal", caster.sync_pos, caster.sync_pos + Vector3(radius, 0, 0))


func _cast_blink(rec: PlayerRecord, p: Player, def: Dictionary, aim_dir: Vector3) -> bool:
	if p.carrying_crown >= 0:
		_tell(rec.peer_id, "The crown is too heavy to blink with.")
		return false
	var flat := Vector3(aim_dir.x, 0, aim_dir.z).normalized()
	var from := p.sync_pos
	var dest := from
	var step := 0.5
	var travelled := 0.0
	while travelled < float(def["range"]):
		var next := dest + flat * step
		next.y = Terrain.height(next.x, next.z)
		if not GameData.in_bounds(next, 1.0) or next.y - dest.y > 1.5:
			break
		var blocked := false
		for s in world.get_structures():
			if not s.is_trap() and not s.is_ladder() and (s.blocks_point(next + Vector3(0, 1.0, 0)) or s.blocks_point(next + Vector3(0, 1.7, 0))):
				blocked = true
				break
		if blocked:
			break
		dest = next
		travelled += step
	if travelled < 1.0:
		return false
	_teleport_player(rec.peer_id, dest + Vector3(0, 0.1, 0))
	world.fx_spell.rpc("blink", from + Vector3(0, 1, 0), dest + Vector3(0, 1, 0))
	return true


func _cast_earth_wall(rec: PlayerRecord, p: Player, def: Dictionary, aim_dir: Vector3) -> bool:
	var flat := Vector3(aim_dir.x, 0, aim_dir.z).normalized()
	var spot := p.sync_pos + flat * 3.5
	spot.y = Terrain.height(spot.x, spot.z)
	var slot := BuildGrid.slot_for("earth_wall_piece", spot, aim_dir, p.sync_pos)
	var problem := world.placement_problem("earth_wall_piece", slot)
	if problem != "" and not problem.begins_with("That needs support"):
		_tell(rec.peer_id, problem)
		return false
	world.structure_spawner.spawn({
		"uid": _next_structure_uid, "item": "earth_wall_piece", "team": rec.team, "owner": rec.peer_id,
		"slot": slot, "lifetime": def["lifetime"],
	})
	_next_structure_uid += 1
	return true


## A summoned piece's time is up.
func expire_structure(s: Structure) -> void:
	if not s.is_queued_for_deletion():
		s.queue_free()
		_collapse_pending = true


# =============================================================================
# Combat & gathering
# =============================================================================

func _melee(rec: PlayerRecord, attacker: Player, def: Dictionary, aim_dir: Vector3) -> void:
	var origin := attacker.sync_pos
	var forward := Vector3(aim_dir.x, 0.0, aim_dir.z).normalized()
	if forward == Vector3.ZERO:
		forward = -attacker.global_basis.z
	var reach: float = def["range"]
	var best: Node = null
	var best_d := INF

	for p in world.get_players():
		if p.team == rec.team or not p.alive:
			continue
		var d := GameData.flat_distance(origin, p.sync_pos) - 0.4
		if d <= reach and d < best_d and _in_cone(origin, p.sync_pos, forward):
			best = p
			best_d = d
	var eye_y := origin.y + 1.2
	for s in world.get_structures():
		if s.team == rec.team:
			continue
		var yr := s.y_range()
		if eye_y < yr.x - 1.6 or eye_y > yr.y + 1.6:
			continue  # out of reach above or below
		var cp := s.closest_point(origin + Vector3(0, 1.2, 0))
		var d := GameData.flat_distance(origin, cp)
		if d <= reach and d < best_d and _in_cone(origin, cp, forward):
			best = s
			best_d = d
	for r in world.resource_nodes:
		if r.amount <= 0:
			continue
		var d := GameData.flat_distance(origin, r.global_position) - r.radius
		if d <= reach and d < best_d and _in_cone(origin, r.global_position, forward):
			best = r
			best_d = d

	if best is Player:
		damage_player(best.peer_id, def["damage"], rec.peer_id, "", attacker.sync_pos, true)
	elif best is Structure:
		damage_structure(best, def.get("structure_damage", 1.0))
	elif best is ResourceNode:
		_gather(rec, best, def)


func _in_cone(origin: Vector3, point: Vector3, forward: Vector3) -> bool:
	var to := Vector3(point.x - origin.x, 0.0, point.z - origin.z)
	if to.length() < 1.0:
		return true
	return forward.dot(to.normalized()) >= 0.5  # 60 degrees either side


func _gather(rec: PlayerRecord, node: ResourceNode, def: Dictionary) -> void:
	var gather: Dictionary = def.get("gather", {})
	var power := int(gather.get(node.res_type, 0))
	if power <= 0:
		_tell(rec.peer_id, "You need a pickaxe to mine %s." % GameData.display_name(node.res_type))
		return
	var amount := mini(node.amount, roundi(power * (rec.gather_mult + 0.25 * rec.rank("lumberjack"))))
	rec.inventory.add(node.res_type, amount)
	world.set_resource_amount(node.index, node.amount - amount)
	_push_private(rec.peer_id)
	if node.amount - amount <= 0:
		var gen := _generation
		var respawn: float = GameData.RESOURCES[node.res_type]["respawn"]
		get_tree().create_timer(respawn, false, true).timeout.connect(func() -> void:
			if gen == _generation:
				world.set_resource_amount(node.index, node.max_amount))


## Simulates an arrow's arc instantly and applies its hit. Returns false if no ammo.
func _shoot(rec: PlayerRecord, shooter: Player, def: Dictionary, aim_dir: Vector3) -> bool:
	var ammo: String = def["ammo"]
	if not rec.inventory.remove(ammo, 1):
		_tell(rec.peer_id, "Out of %s." % GameData.display_name(ammo).to_lower())
		return false
	_push_private(rec.peer_id)
	var start := shooter.sync_pos + Vector3(0, 1.5, 0) + Vector3(aim_dir.x, 0, aim_dir.z).normalized() * 0.6
	var velocity := aim_dir * float(def["speed"])
	var max_time := float(def["range"]) / float(def["speed"]) * 1.5
	var corridor_end := start + aim_dir * float(def["range"])

	# Only test things near the flight path.
	var players: Array[Player] = []
	for p in world.get_players():
		if p.team != rec.team and p.alive and _near_segment(p.sync_pos, start, corridor_end, 4.0):
			players.append(p)
	var structures: Array[Structure] = []
	for s in world.get_structures():
		if not s.is_trap() and not s.is_ladder() and _near_segment(s.global_position, start, corridor_end, 6.0):
			structures.append(s)
	var nodes: Array[ResourceNode] = []
	for r in world.resource_nodes:
		if r.amount > 0 and r.res_type == "wood" and _near_segment(r.global_position, start, corridor_end, 3.0):
			nodes.append(r)

	var dt := 1.0 / 60.0
	var t := 0.0
	var pos := start
	var hit_player: Player = null
	var hit_structure: Structure = null
	while t < max_time:
		t += dt
		velocity.y -= GameData.ARROW_GRAVITY * dt
		pos += velocity * dt
		var ground := Terrain.height(pos.x, pos.z)
		if pos.y <= ground:
			pos.y = ground
			break
		var done := false
		for p in players:
			var body := p.sync_pos + Vector3(0, 0.9, 0)
			if GameData.flat_distance(pos, body) < 0.55 and absf(pos.y - body.y) < 1.0:
				hit_player = p
				done = true
				break
		if done:
			break
		for s in structures:
			if s.blocks_point(pos):
				hit_structure = s
				done = true
				break
		if done:
			break
		for r in nodes:
			if pos.y < r.global_position.y + r.tree_height and GameData.flat_distance(pos, r.global_position) < r.radius:
				done = true
				break
		if done:
			break
	world.fx_arrow.rpc(start, aim_dir * float(def["speed"]), t)
	if hit_player:
		var dmg := float(def["damage"]) * (1.0 + 0.15 * rec.rank("marksman"))
		damage_player(hit_player.peer_id, dmg, rec.peer_id, "", start)
	elif hit_structure and hit_structure.team != rec.team:
		damage_structure(hit_structure, def.get("structure_damage", 1.0))
	return true


func _near_segment(p: Vector3, a: Vector3, b: Vector3, radius: float) -> bool:
	var p2 := Vector2(p.x, p.z)
	var closest := Geometry2D.get_closest_point_to_segment(p2, Vector2(a.x, a.z), Vector2(b.x, b.z))
	return p2.distance_to(closest) <= radius


## `from` is where the hit came from (for shield blocking; Vector3.INF = unblockable).
## Melee hits caught right as the shield goes up are parried: no damage, and the
## attacker is stunned.
func damage_player(victim_peer: int, amount: float, attacker_peer: int, cause := "", from := Vector3.INF, melee := false) -> void:
	var victim := world.get_player(victim_peer)
	if victim == null or not victim.alive or match_over:
		return
	var vrec: PlayerRecord = records.get(victim_peer)
	if vrec and clock < vrec.protected_until:
		return
	if from != Vector3.INF and victim.blocking and vrec and vrec.shield() != "" and _facing(victim, from):
		if melee and clock - victim.block_started <= GameData.PARRY_WINDOW:
			_parry(victim, attacker_peer)
			return
		amount *= 1.0 - float(GameData.item(vrec.shield())["block"])
		world.fx_block.rpc(victim.chest(), false)
	victim.health = maxf(victim.health - amount, 0.0)
	var killed := victim.health <= 0.0
	if attacker_peer != victim_peer:
		_send_to(attacker_peer, &"_hit_marker", [killed])
	if victim.has_node("Brain"):
		(victim.get_node("Brain") as BotBrain).on_damaged(attacker_peer)
	if killed:
		_kill(victim, attacker_peer, cause)


## Is `from` in front of the victim (within the shield's arc)?
func _facing(victim: Player, from: Vector3) -> bool:
	var to := Vector3(from.x - victim.sync_pos.x, 0, from.z - victim.sync_pos.z)
	if to.length_squared() < 0.01:
		return true
	var forward := Vector3(-sin(victim.sync_yaw), 0, -cos(victim.sync_yaw))
	return forward.angle_to(to.normalized()) <= GameData.BLOCK_ARC


func _parry(victim: Player, attacker_peer: int) -> void:
	world.fx_block.rpc(victim.chest(), true)
	var attacker := world.get_player(attacker_peer)
	var arec: PlayerRecord = records.get(attacker_peer)
	if attacker and arec:
		attacker.stunned = true
		arec.stun_until = clock + GameData.PARRY_STUN
		arec.next_action_time = maxf(arec.next_action_time, arec.stun_until)
	_tell(victim.peer_id, "Parried!")
	_tell(attacker_peer, "Your attack was parried!")


func damage_structure(s: Structure, amount: float) -> void:
	if s.is_queued_for_deletion():
		return
	s.health -= amount
	if s.health <= 0.0:
		s.queue_free()  # the spawner removes it on every client
		_collapse_pending = true
	else:
		world.structure_health.rpc(s.name, s.health / s.max_health)


func _kill(victim: Player, killer_peer: int, cause: String) -> void:
	victim.alive = false
	victim.mounted = false
	victim.slowed = false
	victim.stunned = false
	if victim.carrying_crown >= 0:
		_drop_crown(crowns[victim.carrying_crown], victim.sync_pos)
	var vrec: PlayerRecord = records.get(victim.peer_id)
	if vrec:
		vrec.deaths += 1
		_push_private(vrec.peer_id)
	var krec: PlayerRecord = records.get(killer_peer)
	if krec and killer_peer != victim.peer_id:
		krec.kills += 1
		krec.gold += GameData.GOLD_PER_KILL
		krec.skill_points += GameData.SKILL_POINTS_PER_KILL
		_push_private(killer_peer)
		var how := ("'s %s" % cause) if cause != "" else ""
		_announce("%s%s slew %s." % [krec.name, how, victim.display_name])
	else:
		_announce("%s died." % victim.display_name)
	_scoreboard_dirty = true
	var gen := _generation
	var peer := victim.peer_id
	get_tree().create_timer(GameData.RESPAWN_TIME, false, true).timeout.connect(func() -> void:
		if gen == _generation:
			_respawn(peer))


func _respawn(peer: int) -> void:
	var rec: PlayerRecord = records.get(peer)
	var p := world.get_player(peer)
	if rec == null or p == null or p.alive:
		return
	p.max_health = rec.max_health()
	p.health = p.max_health
	p.max_mana = rec.max_mana()
	p.mana = p.max_mana
	p.carrying_crown = -1
	p.alive = true
	rec.protected_until = clock + GameData.SPAWN_PROTECTION
	_teleport_player(peer, GameData.spawn_point(rec.team))


## Server: closest living enemy of `team` within range of pos, or null.
func nearest_enemy(pos: Vector3, team: int, max_range: float) -> Player:
	var best: Player = null
	var best_d := max_range
	for p in world.get_players():
		if p.team == team or not p.alive:
			continue
		var d := pos.distance_to(p.sync_pos)
		if d <= best_d:
			best = p
			best_d = d
	return best


func fire_turret(s: Structure, target: Player, turret: Dictionary) -> void:
	var from := s.top() + Vector3(0, 0.3, 0)
	world.fx_bolt.rpc(from, target.sync_pos + Vector3(0, 1.0, 0))
	damage_player(target.peer_id, turret["damage"], s.owner_peer, "ballista", from)


func ram_hit(ram: Structure, target: Structure) -> void:
	world.fx_ram.rpc(ram.global_position + -ram.global_basis.z * 3.0 + Vector3(0, 1, 0))
	damage_structure(target, ram._ram["damage"])


## Lob a boulder: the player's aim picks the direction, and how high they aim sets the
## launch angle (and so the range). Costs stone from the firer.
func _fire_catapult(rec: PlayerRecord, cat: Structure, aim_dir: Vector3) -> bool:
	var cfg := cat.catapult_config()
	if clock < cat._cooldown:
		_tell(rec.peer_id, "The catapult is reloading.")
		return false
	var ammo: Dictionary = cfg["ammo"]
	if not rec.inventory.pay(ammo):
		_tell(rec.peer_id, "The catapult needs %s per shot." % GameData.cost_text(ammo))
		return false
	_push_private(rec.peer_id)
	cat._cooldown = clock + float(cfg["cooldown"])
	var flat := Vector3(aim_dir.x, 0, aim_dir.z).normalized()
	if flat == Vector3.ZERO:
		flat = -cat.global_basis.z
	# Aiming level throws at ~40 degrees; aim down for a flatter, shorter throw.
	var angle := clampf(asin(clampf(aim_dir.y, -1.0, 1.0)) + 0.7, 0.15, 0.8)
	var speed: float = cfg["speed"]
	var velocity := flat * cos(angle) * speed + Vector3.UP * sin(angle) * speed
	var start := cat.global_position + Vector3(0, 3.2, 0)
	var pos := start
	var vel := velocity
	var dt := 1.0 / 30.0
	var t := 0.0
	while t < 10.0:
		t += dt
		vel.y -= GameData.ARROW_GRAVITY * dt
		pos += vel * dt
		if pos.y <= Terrain.height(pos.x, pos.z) or not GameData.in_bounds(pos, 0.0):
			break
		if t > 0.3 and _boulder_blocked(pos, cat):
			break
	var radius: float = cfg["radius"]
	world.fx_boulder.rpc(cat.name, start, velocity, t, radius)
	for p in world.get_players():
		if p.team != rec.team and p.alive and (p.sync_pos + Vector3(0, 0.9, 0)).distance_to(pos) <= radius:
			damage_player(p.peer_id, cfg["damage"], rec.peer_id, "catapult")
	for s in world.get_structures():
		if s.team != rec.team and s.closest_point(pos).distance_to(pos) <= radius:
			damage_structure(s, cfg["structure_damage"])
	return true


func _boulder_blocked(point: Vector3, cat: Structure) -> bool:
	for s in world.get_structures():
		if s != cat and not s.is_trap() and not s.is_ladder() and s.blocks_point(point):
			return true
	for p in world.get_players():
		if p.alive and (p.sync_pos + Vector3(0, 0.9, 0)).distance_to(point) < 1.0:
			return true
	return false


func trigger_trap(s: Structure, trap: Dictionary) -> void:
	for p in world.get_players():
		var yr := s.y_range()
		if p.team != s.team and p.alive and absf(p.sync_pos.y - yr.x) < 1.0 and s.distance_to_point(p.sync_pos) < 0.3:
			damage_player(p.peer_id, trap["damage"], s.owner_peer, "spike trap")


# =============================================================================
# Building & consumables
# =============================================================================

func _use_consumable(rec: PlayerRecord, p: Player, item_id: String, def: Dictionary, aim_dir: Vector3) -> bool:
	var used := true
	match String(def.get("effect", "")):
		"heal":
			if p.health >= p.max_health:
				used = false
			else:
				p.health = minf(p.max_health, p.health + float(def["amount"]))
		"mount":
			if p.mounted:
				used = false
			else:
				p.mounted = true
		"fireball":
			_cast_fireball(rec, p, def, aim_dir)
		"max_health":
			var bonus: float = def["amount"]
			rec.bonus_health += bonus
			p.max_health += bonus
			p.health += bonus
		"gather_mult":
			rec.gather_mult += float(def["amount"])
		"mana":
			if p.mana >= p.max_mana:
				used = false
			else:
				p.mana = minf(p.max_mana, p.mana + float(def["amount"]))
		_:
			used = false
	if used:
		rec.inventory.remove(item_id, 1)
		_push_private(rec.peer_id)
	else:
		_tell(rec.peer_id, "You can't use that right now.")
	return used


func _cast_fireball(rec: PlayerRecord, caster: Player, def: Dictionary, aim_dir: Vector3) -> void:
	var start := caster.sync_pos + Vector3(0, 1.5, 0)
	var max_range: float = def["range"]
	var impact := start + aim_dir * max_range
	var step := 0.5
	var travelled := 0.0
	var point := start
	while travelled < max_range:
		point += aim_dir * step
		travelled += step
		var ground := Terrain.height(point.x, point.z)
		if point.y <= ground:
			impact = Vector3(point.x, ground, point.z)
			break
		if _fireball_blocked(point, rec.team):
			impact = point
			break
	var radius: float = def["radius"]
	world.fx_fireball.rpc(start, impact, radius)
	for p in world.get_players():
		if p.team != rec.team and p.alive and (p.sync_pos + Vector3(0, 0.9, 0)).distance_to(impact) <= radius:
			damage_player(p.peer_id, def["damage"], rec.peer_id, "fireball", impact)
	for s in world.get_structures():
		if s.team != rec.team and s.closest_point(impact).distance_to(impact) <= radius:
			damage_structure(s, def["structure_damage"])


func _fireball_blocked(point: Vector3, team: int) -> bool:
	for p in world.get_players():
		if p.team != team and p.alive and (p.sync_pos + Vector3(0, 0.9, 0)).distance_to(point) < 1.2:
			return true
	for s in world.get_structures():
		if not s.is_trap() and not s.is_ladder() and s.blocks_point(point):
			return true
	return false


# =============================================================================
# Per-tick server work: crowns, speed checks, scoreboard
# =============================================================================

func _physics_process(delta: float) -> void:
	clock += delta
	if not server_running:
		return
	_scoreboard_timer -= delta
	if _scoreboard_dirty and _scoreboard_timer <= 0.0:
		_scoreboard_timer = SCOREBOARD_INTERVAL
		_scoreboard_dirty = false
		_broadcast(&"_scoreboard", [_scoreboard_rows()])
	if _collapse_pending:
		_collapse_pending = false
		_collapse_unsupported()
	if match_over:
		return
	_check_movement()
	_tick_status(delta)
	for crown in crowns:
		if crown.state == CrownRules.State.CARRIED:
			var carrier := world.get_player(crown.carrier)
			if carrier == null or not carrier.alive:
				_drop_crown(crown, crown.position)
				continue
			crown.position = carrier.sync_pos
			var own_dist := GameData.flat_distance(carrier.sync_pos, GameData.crown_pos(carrier.team))
			if CrownRules.can_capture(carrier.team, crown.team, crowns[carrier.team].state, own_dist):
				_capture(carrier, crown)
		elif crown.state == CrownRules.State.DROPPED and clock - crown.dropped_at >= GameData.CROWN_AUTO_RETURN:
			_return_crown(crown, null)
		else:
			_check_crown_touch(crown)


## After a piece is destroyed, anything no longer connected to the ground falls down.
func _collapse_unsupported() -> void:
	var standing := {}
	for s in world.get_structures():
		if not s.is_vehicle():
			standing[s.slot_key] = [s.kind, s.slot]
	var supported := BuildGrid.supported_keys(standing)
	for s in world.get_structures():
		if not s.is_vehicle() and not supported.has(s.slot_key):
			s.health = 0.0
			s.queue_free()
			_collapse_pending = true


var _mana_timer := 0.0


## Mana regenerates in half-second steps (fewer network updates); slows and stuns wear off.
var _status_timer := 0.0


func _tick_status(delta: float) -> void:
	_status_timer -= delta
	if _status_timer > 0.0:
		return
	_status_timer = 0.1
	_mana_timer -= 0.1
	var regen_tick := _mana_timer <= 0.0
	if regen_tick:
		_mana_timer = 0.5
	for rec: PlayerRecord in records.values():
		var p := world.get_player(rec.peer_id)
		if p == null:
			continue
		if p.slowed and clock >= rec.slow_until:
			p.slowed = false
		if p.stunned and clock >= rec.stun_until:
			p.stunned = false
		if regen_tick and p.alive and p.mana < p.max_mana:
			p.mana = minf(p.max_mana, p.mana + rec.mana_regen() * 0.5)


## Movement is client-owned, so the server rejects anything faster than a horse.
func _check_movement() -> void:
	for rec: PlayerRecord in records.values():
		if rec.is_bot or clock - rec.last_move_check < MOVE_CHECK_INTERVAL:
			continue
		var p := world.get_player(rec.peer_id)
		if p == null or not p.alive:
			continue
		var elapsed := clock - rec.last_move_check
		var allowed := GameData.MAX_PLAYER_SPEED * 1.5 * elapsed + 1.5  # headroom for Swiftness
		rec.last_move_check = clock
		if GameData.flat_distance(p.sync_pos, rec.last_valid_pos) > allowed:
			_send_to(rec.peer_id, &"_teleport", [rec.last_valid_pos])
		else:
			rec.last_valid_pos = p.sync_pos


func _scoreboard_rows() -> Array:
	var rows := []
	for rec: PlayerRecord in records.values():
		rows.append([rec.name, rec.team, rec.kills, rec.deaths, rec.captures, rec.is_bot])
	return rows


func _check_crown_touch(crown: CrownState) -> void:
	for p in world.get_players():
		if not p.alive:
			continue
		if GameData.flat_distance(p.sync_pos, crown.position) > GameData.CROWN_TOUCH_RADIUS:
			continue
		if absf(p.sync_pos.y - crown.position.y) > 3.0:
			continue
		var action := CrownRules.touch_action(crown.team, crown.state, p.team)
		if action == CrownRules.Action.PICK_UP and p.carrying_crown == -1:
			crown.state = CrownRules.State.CARRIED
			crown.carrier = p.peer_id
			p.carrying_crown = crown.team
			_sync_crowns()
			_announce("%s has stolen the %s crown!" % [p.display_name, GameData.team_name(crown.team)])
			return
		if action == CrownRules.Action.RETURN:
			_return_crown(crown, p)
			return


func _drop_crown(crown: CrownState, pos: Vector3) -> void:
	var carrier := world.get_player(crown.carrier)
	if carrier:
		carrier.carrying_crown = -1
	crown.carrier = 0
	if not GameData.in_bounds(pos) or pos.y < -5.0:
		crown.send_home()
		_announce("The %s crown returned home." % GameData.team_name(crown.team))
	else:
		crown.state = CrownRules.State.DROPPED
		crown.position = Vector3(pos.x, maxf(Terrain.height(pos.x, pos.z), Terrain.WATER_LEVEL), pos.z)
		crown.dropped_at = clock
		_announce("The %s crown was dropped!" % GameData.team_name(crown.team))
	_sync_crowns()


func _return_crown(crown: CrownState, returner: Player) -> void:
	crown.send_home()
	if returner:
		var rec: PlayerRecord = records.get(returner.peer_id)
		if rec:
			rec.gold += GameData.GOLD_PER_RETURN
			_push_private(rec.peer_id)
		_announce("%s returned the %s crown." % [returner.display_name, GameData.team_name(crown.team)])
	else:
		_announce("The %s crown returned home." % GameData.team_name(crown.team))
	_sync_crowns()


func _capture(carrier: Player, crown: CrownState) -> void:
	var team := carrier.team
	carrier.carrying_crown = -1
	crown.send_home()
	scores[team] += 1
	for rec: PlayerRecord in records.values():
		if rec.team == team:
			rec.gold += GameData.GOLD_TEAM_CAPTURE
			if rec.peer_id == carrier.peer_id:
				rec.gold += GameData.GOLD_PER_CAPTURE
				rec.captures += 1
				rec.skill_points += GameData.SKILL_POINTS_PER_CAPTURE
			_push_private(rec.peer_id)
	_scoreboard_dirty = true
	_sync_crowns()
	_broadcast(&"_scores", [scores])
	_announce("%s captured the %s crown for the %s!" % [carrier.display_name, GameData.team_name(crown.team), GameData.team_name(team)])
	if scores[team] >= GameData.CAPTURES_TO_WIN:
		_end_match(team)


func _sync_crowns() -> void:
	_broadcast(&"_crowns", [_crown_dicts()])


func _crown_dicts() -> Array:
	var out := []
	for c in crowns:
		out.append(c.to_dict())
	return out


# =============================================================================
# Match flow
# =============================================================================

func _end_match(winning_team: int) -> void:
	_broadcast(&"_match_state", [true, winning_team])
	_announce("The %s are victorious! New match in %d seconds." % [GameData.team_name(winning_team), int(GameData.MATCH_RESTART_DELAY)])
	var gen := _generation
	get_tree().create_timer(GameData.MATCH_RESTART_DELAY, false, true).timeout.connect(func() -> void:
		if gen == _generation:
			_reset_match())


func _reset_match() -> void:
	_generation += 1
	match_started_at = clock
	scores = [0, 0]
	for c in crowns:
		c.send_home()
	for s in world.get_structures():
		s.queue_free()
	world.reset_resources()
	for rec: PlayerRecord in records.values():
		rec.reset_progress()
		var p := world.get_player(rec.peer_id)
		if p:
			p.max_health = GameData.PLAYER_MAX_HEALTH
			p.health = p.max_health
			p.max_mana = GameData.PLAYER_MAX_MANA
			p.mana = p.max_mana
			p.slowed = false
			p.stunned = false
			p.mounted = false
			p.carrying_crown = -1
			p.alive = true
			rec.protected_until = clock + GameData.SPAWN_PROTECTION
			_teleport_player(rec.peer_id, GameData.spawn_point(rec.team))
			if p.has_node("Brain"):
				(p.get_node("Brain") as BotBrain).reset()
		_push_private(rec.peer_id)
	_scoreboard_dirty = true
	_broadcast(&"_scores", [scores])
	_sync_crowns()
	_broadcast(&"_match_state", [false, -1])
	_announce("A new match begins!")
