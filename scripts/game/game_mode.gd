class_name GameMode
extends Node
## Server-authoritative match rules: teams, combat, gathering, crafting, the gold shop,
## building, and the crown capture-the-flag loop.
##
## Clients never change game state directly. They call request(...), the server
## validates it, then pushes results back: shared state (scores, crowns) to everyone,
## private state (inventory, gold, unlocks) only to the owning player.

signal private_updated
signal scores_updated
signal crowns_updated
signal message_received(text: String)
signal match_over_changed

var world: World

# --- Replicated to every peer -------------------------------------------------
var scores: Array = [0, 0]
var crowns: Array[CrownState] = []
var match_over := false
var winner := -1

# --- This client's private state (copied from the server) ---------------------
var my_inventory: Dictionary = {}
var my_gold := 0
var my_unlocks: Array = []
var my_stats: Dictionary = {}

# --- Server only ----------------------------------------------------------------
var server_running := false
var records: Dictionary = {}  ## peer id -> PlayerRecord
var _generation := 0  ## bumps on match reset, so stale timers do nothing
var _next_structure_uid := 1


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
	elif multiplayer.get_peers().has(peer):  # skip peers that already left
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


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


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
	print("[server] Match started with map seed %d" % world.map_seed)
	if not Net.is_dedicated():
		_register(1, Net.player_name)


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
	var team := _pick_team()
	if team < 0:
		_send_to(peer, &"_rejected", ["The match is full."])
		return
	var rec := PlayerRecord.new(peer, player_name, team)
	records[peer] = rec
	if peer != multiplayer.get_unique_id():
		_send_to(peer, &"_welcome", [world.map_seed, _snapshot()])
	world.player_spawner.spawn({
		"peer_id": peer, "team": team, "name": player_name, "pos": GameData.spawn_point(team),
	})
	_push_private(peer)
	_announce("%s joined the %s." % [player_name, GameData.team_name(team)])


func _pick_team() -> int:
	var counts := []
	counts.resize(GameData.TEAM_COUNT)
	counts.fill(0)
	for rec: PlayerRecord in records.values():
		counts[rec.team] += 1
	var best := -1
	for t in GameData.TEAM_COUNT:
		if counts[t] < GameData.TEAM_SIZE and (best == -1 or counts[t] < counts[best]):
			best = t
	return best


func _on_peer_disconnected(peer: int) -> void:
	if not server_running or not records.has(peer):
		return
	var rec: PlayerRecord = records[peer]
	var p := world.get_player(peer)
	if p:
		if p.carrying_crown >= 0:
			_drop_crown(crowns[p.carrying_crown], p.sync_pos)
		p.queue_free()
	records.erase(peer)
	_announce("%s left." % rec.name)


func _snapshot() -> Dictionary:
	return {
		"scores": scores,
		"crowns": _crown_dicts(),
		"resources": world.resource_snapshot(),
		"match_over": match_over,
		"winner": winner,
	}


func _push_private(peer: int) -> void:
	var rec: PlayerRecord = records.get(peer)
	if rec:
		_send_to(peer, &"_private", [rec.inventory.to_dict(), rec.gold, rec.unlocks.keys(), rec.stats()])


# =============================================================================
# Client-side receivers
# =============================================================================

@rpc("authority", "call_local", "reliable")
func _welcome(seed_value: int, snapshot: Dictionary) -> void:
	world.generate(seed_value)
	scores = snapshot["scores"]
	_apply_crowns(snapshot["crowns"])
	world.apply_resource_snapshot(snapshot["resources"])
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
func _message(text: String) -> void:
	message_received.emit(text)


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
		crowns[d["team"]].apply_dict(d, _now())
	crowns_updated.emit()


## Hotbar contents for the local player: fists, then every owned non-resource item.
func hotbar_items() -> Array[String]:
	var out: Array[String] = [""]
	for id: String in GameData.ITEMS:
		if int(my_inventory.get(id, 0)) > 0:
			out.append(id)
			if out.size() >= 9:
				break
	return out


func is_unlocked_locally(id: String) -> bool:
	return int(GameData.item(id).get("unlock_cost", 0)) <= 0 or my_unlocks.has(id)


# =============================================================================
# Requests (client -> server)
# =============================================================================

@rpc("any_peer", "call_local", "reliable")
func request_craft(item_id: String) -> void:
	if not server_running:
		return
	var rec: PlayerRecord = records.get(_sender())
	var def := GameData.item(item_id)
	if rec == null or not GameData.is_item(item_id):
		return
	if not rec.is_unlocked(item_id):
		_tell(rec.peer_id, "Buy the %s blueprint first." % def["name"])
		return
	if not rec.inventory.pay(def["recipe"]):
		_tell(rec.peer_id, "Not enough resources for %s." % def["name"])
		return
	rec.inventory.add(item_id, 1)
	_push_private(rec.peer_id)


@rpc("any_peer", "call_local", "reliable")
func request_unlock(item_id: String) -> void:
	if not server_running:
		return
	var rec: PlayerRecord = records.get(_sender())
	if rec == null or not GameData.is_item(item_id) or rec.is_unlocked(item_id):
		return
	var cost: int = GameData.item(item_id)["unlock_cost"]
	if rec.gold < cost:
		_tell(rec.peer_id, "You need %d gold." % cost)
		return
	rec.gold -= cost
	rec.unlocks[item_id] = true
	_tell(rec.peer_id, "Unlocked %s!" % GameData.display_name(item_id))
	_push_private(rec.peer_id)


## Left click: swing, place, or use whatever is equipped.
@rpc("any_peer", "call_local", "reliable")
func request_primary(item_id: String, aim_dir: Vector3, target: Vector3) -> void:
	if not server_running or match_over:
		return
	var rec: PlayerRecord = records.get(_sender())
	if rec == null:
		return
	var p := world.get_player(rec.peer_id)
	if p == null or not p.alive:
		return
	if item_id != "" and rec.inventory.count(item_id) <= 0:
		return
	var def := GameData.item(item_id)
	if def.is_empty():
		return
	var now := _now()
	if now < rec.next_action_time:
		return
	# Small tolerance for network jitter.
	rec.next_action_time = now + float(def.get("cooldown", 1.0)) * 0.85
	if aim_dir.length_squared() < 0.0001:
		aim_dir = -p.global_basis.z
	aim_dir = aim_dir.normalized()

	var kind: String = def["kind"]
	if kind in GameData.MELEE_KINDS:
		_melee(rec, p, def, aim_dir)
	elif kind == "structure":
		_place_structure(rec, p, item_id, def, target, aim_dir)
	elif kind == "consumable":
		_use_consumable(rec, p, item_id, def, aim_dir)


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
	for s in world.get_structures():
		if s.team == rec.team:
			continue
		var cp := s.closest_point(origin)
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
		damage_player(best.peer_id, def["damage"], rec.peer_id)
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
	var amount := mini(node.amount, roundi(power * rec.gather_mult))
	rec.inventory.add(node.res_type, amount)
	world.set_resource_amount(node.index, node.amount - amount)
	_push_private(rec.peer_id)
	if node.amount - amount <= 0:
		var gen := _generation
		var respawn: float = GameData.RESOURCES[node.res_type]["respawn"]
		get_tree().create_timer(respawn).timeout.connect(func() -> void:
			if gen == _generation:
				world.set_resource_amount(node.index, node.max_amount))


func damage_player(victim_peer: int, amount: float, attacker_peer: int, cause := "") -> void:
	var victim := world.get_player(victim_peer)
	if victim == null or not victim.alive or match_over:
		return
	victim.health = maxf(victim.health - amount, 0.0)
	if victim.health <= 0.0:
		_kill(victim, attacker_peer, cause)


func damage_structure(s: Structure, amount: float) -> void:
	if s.is_queued_for_deletion():
		return
	s.health -= amount
	if s.health <= 0.0:
		s.queue_free()  # the spawner removes it on every client


func _kill(victim: Player, killer_peer: int, cause: String) -> void:
	victim.alive = false
	victim.mounted = false
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
		_push_private(killer_peer)
		var how := ("'s %s" % cause) if cause != "" else ""
		_announce("%s%s slew %s. (+%dg)" % [krec.name, how, victim.display_name, GameData.GOLD_PER_KILL])
	else:
		_announce("%s died." % victim.display_name)
	var gen := _generation
	var peer := victim.peer_id
	get_tree().create_timer(GameData.RESPAWN_TIME).timeout.connect(func() -> void:
		if gen == _generation:
			_respawn(peer))


func _respawn(peer: int) -> void:
	var rec: PlayerRecord = records.get(peer)
	var p := world.get_player(peer)
	if rec == null or p == null:
		return
	p.max_health = GameData.PLAYER_MAX_HEALTH + rec.bonus_health
	p.health = p.max_health
	p.carrying_crown = -1
	p.alive = true
	_send_to(peer, &"_teleport", [GameData.spawn_point(rec.team)])


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
	var from := s.global_position + Vector3(0, s.size.y + 0.3, 0)
	world.fx_bolt.rpc(from, target.sync_pos + Vector3(0, 1.0, 0))
	damage_player(target.peer_id, turret["damage"], s.owner_peer, "ballista")


# =============================================================================
# Building & consumables
# =============================================================================

func _place_structure(rec: PlayerRecord, p: Player, item_id: String, def: Dictionary, target: Vector3, aim_dir: Vector3) -> void:
	target.y = 0.0
	if GameData.flat_distance(target, p.sync_pos) > 9.0:
		return
	if not GameData.can_build_at(target):
		_tell(rec.peer_id, "You can't build there.")
		return
	for s in world.get_structures():
		if s.distance_to_point(target) < 0.5:
			_tell(rec.peer_id, "Something is already built there.")
			return
	if not rec.inventory.remove(item_id, 1):
		return
	var yaw := GameData.snap_yaw(atan2(-aim_dir.x, -aim_dir.z))
	world.structure_spawner.spawn({
		"uid": _next_structure_uid, "item": item_id, "team": rec.team,
		"owner": rec.peer_id, "pos": target, "yaw": yaw,
	})
	_next_structure_uid += 1
	_push_private(rec.peer_id)


func _use_consumable(rec: PlayerRecord, p: Player, item_id: String, def: Dictionary, aim_dir: Vector3) -> void:
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
		_:
			used = false
	if used:
		rec.inventory.remove(item_id, 1)
		_push_private(rec.peer_id)
	else:
		_tell(rec.peer_id, "You can't use that right now.")


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
		if point.y <= 0.0:
			impact = Vector3(point.x, 0.0, point.z)
			break
		if _fireball_blocked(point, rec.team):
			impact = point
			break
	var radius: float = def["radius"]
	world.fx_fireball.rpc(start, impact, radius)
	for p in world.get_players():
		if p.team != rec.team and p.alive and (p.sync_pos + Vector3(0, 0.9, 0)).distance_to(impact) <= radius:
			damage_player(p.peer_id, def["damage"], rec.peer_id, "fireball")
	for s in world.get_structures():
		if s.team != rec.team and s.distance_to_point(impact) <= radius:
			damage_structure(s, def["structure_damage"])


func _fireball_blocked(point: Vector3, team: int) -> bool:
	for p in world.get_players():
		if p.team != team and p.alive and (p.sync_pos + Vector3(0, 0.9, 0)).distance_to(point) < 1.2:
			return true
	for s in world.get_structures():
		if point.y < s.size.y and s.distance_to_point(point) < 0.3:
			return true
	return false


# =============================================================================
# Crowns
# =============================================================================

func _physics_process(_delta: float) -> void:
	if not server_running or match_over:
		return
	var now := _now()
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
		elif crown.state == CrownRules.State.DROPPED and now - crown.dropped_at >= GameData.CROWN_AUTO_RETURN:
			_return_crown(crown, null)
		else:
			_check_crown_touch(crown)


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
		crown.position = Vector3(pos.x, 0.0, pos.z)
		crown.dropped_at = _now()
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
			_push_private(rec.peer_id)
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
	get_tree().create_timer(GameData.MATCH_RESTART_DELAY).timeout.connect(func() -> void:
		if gen == _generation:
			_reset_match())


func _reset_match() -> void:
	_generation += 1
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
			p.mounted = false
			p.carrying_crown = -1
			p.alive = true
			_send_to(rec.peer_id, &"_teleport", [GameData.spawn_point(rec.team)])
		_push_private(rec.peer_id)
	_broadcast(&"_scores", [scores])
	_sync_crowns()
	_broadcast(&"_match_state", [false, -1])
	_announce("A new match begins!")
