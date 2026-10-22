extends Node
## End-to-end rules test on a real World running as host, with a fake enemy player.
## Run: godot --headless --path . res://tests/gameplay_test.tscn

const ENEMY := 1000

var _checks := 0
var _failures := 0
var world: World
var gm: GameMode


func check(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		printerr("FAIL: " + what)


func _ready() -> void:
	Net.mode = Net.Mode.HOST
	Net.port = 26000 + randi() % 2000
	Net.player_name = "Tester"
	Net.team_fill = 0
	world = load("res://scenes/world.tscn").instantiate()
	add_child(world)
	gm = world.game_mode
	await _frames(5)
	await _run()
	print("gameplay: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _ready_to_act(peer: int) -> void:
	gm.records[peer].next_action_time = 0.0


## Put a player at pos facing toward look_at (flat).
func _place(p: Player, pos: Vector3, look_at_pos: Vector3) -> Vector3:
	p.teleport(pos)
	var dir := (look_at_pos - pos)
	dir.y = 0
	dir = dir.normalized()
	p.rotation.y = atan2(-dir.x, -dir.z)
	p.sync_yaw = p.rotation.y
	return dir


func _run() -> void:
	var me := world.get_player(1)
	check(me != null and gm.records.has(1), "host player registered and spawned")
	check(world.resource_nodes.size() > 300, "map generated")
	var rec: PlayerRecord = gm.records[1]
	check(rec.team == 0, "first player joins team 0")

	# --- Gathering ---
	var tree: ResourceNode = null
	for r in world.resource_nodes:
		if r.res_type == "wood" and absf(r.position.x) < 80:
			tree = r
			break
	var dir := _place(me, tree.position + Vector3(1.5, 0, 0), tree.position)
	await _frames(2)
	gm.request_primary("", dir, Vector3.ZERO)
	check(gm.my_inventory.get("wood", 0) == 1, "fists gather 1 wood (got %s)" % gm.my_inventory)
	check(tree.amount == tree.max_amount - 1, "tree lost 1 wood")
	var ore: ResourceNode = null
	for r in world.resource_nodes:
		if r.res_type == "iron":
			ore = r
			break
	dir = _place(me, ore.position + Vector3(0, 0, 1.8), ore.position)
	await _frames(2)
	_ready_to_act(1)
	gm.request_primary("", dir, Vector3.ZERO)
	check(int(gm.my_inventory.get("iron", 0)) == 0, "fists can't mine iron")

	# --- Crafting ---
	gm.request_craft("iron_sword")
	check(rec.inventory.count("iron_sword") == 0, "can't craft without resources")
	rec.inventory.add("iron", 20)
	rec.inventory.add("wood", 40)
	gm.request_craft("iron_sword")
	check(rec.inventory.count("iron_sword") == 1, "crafted iron sword")
	check(rec.inventory.count("iron") == 12, "sword cost 8 iron")
	gm.request_craft("ballista")
	check(rec.inventory.count("ballista") == 0, "locked blueprint can't be crafted")
	check(gm.hotbar_items().has("iron_sword"), "sword shows in hotbar")

	# --- Combat & gold ---
	gm.records[ENEMY] = PlayerRecord.new(ENEMY, "Enemy", 1)
	world.player_spawner.spawn({"peer_id": ENEMY, "team": 1, "name": "Enemy", "pos": Vector3(0, 0, 20)})
	var enemy := world.get_player(ENEMY)
	check(enemy != null and enemy.team == 1, "enemy spawned")
	dir = _place(me, Vector3(0, 0, 22), Vector3(0, 0, 20))
	enemy.teleport(Vector3(0, 0, 20.5))
	await _frames(2)
	for i in 4:
		_ready_to_act(1)
		gm.request_primary("iron_sword", dir, Vector3.ZERO)
	check(not enemy.alive, "4 sword hits kill (health %s)" % enemy.health)
	check(rec.kills == 1 and rec.gold == GameData.GOLD_PER_KILL, "kill pays gold")
	check(gm.my_gold == GameData.GOLD_PER_KILL, "gold pushed to client")
	_ready_to_act(1)
	gm.request_primary("iron_sword", dir, Vector3.ZERO)
	check(gm.records[ENEMY].deaths == 1, "dead enemies can't be killed again")

	# --- Unlocks ---
	gm.request_unlock("ballista")
	check(not rec.unlocks.has("ballista"), "can't unlock without gold")
	rec.gold = 500
	gm.request_unlock("ballista")
	check(rec.unlocks.has("ballista") and rec.gold == 200, "unlock spends gold")
	rec.inventory.add("iron", 10)
	gm.request_craft("ballista")
	check(rec.inventory.count("ballista") == 1, "unlocked blueprint can be crafted")

	# --- Building ---
	rec.inventory.add("wooden_wall", 2)
	dir = _place(me, Vector3(30, 0, 60), Vector3(30, 0, 50))
	await _frames(2)
	_ready_to_act(1)
	gm.request_primary("wooden_wall", dir, Vector3(30, 0, 56))
	check(world.get_structures().size() == 1, "wall placed")
	_ready_to_act(1)
	gm.request_primary("wooden_wall", dir, Vector3(30, 0, 56))
	check(world.get_structures().size() == 1, "can't stack walls in one spot")
	check(rec.inventory.count("wooden_wall") == 1, "blocked placement keeps the item")
	dir = _place(me, GameData.crown_pos(0) + Vector3(0, -1, 5), GameData.crown_pos(0))
	await _frames(2)
	_ready_to_act(1)
	gm.request_primary("wooden_wall", dir, GameData.crown_pos(0))
	check(world.get_structures().size() == 1, "can't build on the crown")
	var wall := world.get_structures()[0]
	gm.damage_structure(wall, 1000.0)
	await _frames(1)
	check(world.get_structures().is_empty(), "destroyed wall is removed")

	# --- Consumables ---
	rec.inventory.add("health_potion", 1)
	me.health = 40.0
	_ready_to_act(1)
	gm.request_primary("health_potion", dir, Vector3.ZERO)
	check(is_equal_approx(me.health, 90.0) and rec.inventory.count("health_potion") == 0, "potion heals 50")
	rec.inventory.add("horse_saddle", 1)
	_ready_to_act(1)
	gm.request_primary("horse_saddle", dir, Vector3.ZERO)
	check(me.mounted, "saddle mounts")
	check(me.current_speed(false) > Player.WALK_SPEED, "mounted is faster")

	# --- Crown: steal, capture ---
	_place(me, Vector3(GameData.crown_pos(1).x, 0, GameData.crown_pos(1).z), Vector3.ZERO)
	await _frames(3)
	check(gm.crowns[1].state == CrownRules.State.CARRIED and gm.crowns[1].carrier == 1, "stole the enemy crown")
	check(me.carrying_crown == 1, "player marked as carrier")
	check(me.current_speed(false) < Player.WALK_SPEED, "carrier is slowed, even mounted")
	_place(me, Vector3(GameData.crown_pos(0).x, 0, GameData.crown_pos(0).z), Vector3.ZERO)
	await _frames(3)
	check(gm.scores[0] == 1, "capture scores a point")
	check(gm.crowns[1].state == CrownRules.State.HOME and me.carrying_crown == -1, "captured crown returns home")
	check(rec.captures == 1, "capture counted")

	# --- Crown: carrier dies, enemy returns it ---
	_place(me, Vector3(GameData.crown_pos(1).x, 0, GameData.crown_pos(1).z), Vector3.ZERO)
	await _frames(3)
	check(gm.crowns[1].state == CrownRules.State.CARRIED, "stole it again")
	_place(me, Vector3(10, 0, -100), Vector3.ZERO)
	await _frames(2)
	rec.protected_until = gm.clock + 5.0
	gm.damage_player(1, 999.0, ENEMY)
	check(me.alive, "spawn protection blocks damage")
	rec.protected_until = 0.0
	gm.damage_player(1, 999.0, ENEMY)
	check(not me.alive and gm.crowns[1].state == CrownRules.State.DROPPED, "dying drops the crown")
	check(gm.records[ENEMY].gold == GameData.GOLD_PER_KILL, "enemy got kill gold")
	gm._respawn(ENEMY)
	enemy.teleport(gm.crowns[1].position)
	await _frames(3)
	check(gm.crowns[1].state == CrownRules.State.HOME, "owner returns a dropped crown by touching it")

	# --- Bows ---
	gm._respawn(1)
	rec.protected_until = 0.0
	await _frames(2)
	gm._respawn(ENEMY)
	gm.records[ENEMY].protected_until = 0.0
	rec.inventory.add("shortbow", 1)
	_place(me, Vector3(-60, 0, 10), Vector3(-60, 0, 30))
	enemy.teleport(Vector3(-60, 0, 30))
	await _frames(3)
	_ready_to_act(1)
	gm.request_primary("shortbow", Vector3(0, 0.05, 1).normalized(), Vector3.ZERO)
	check(is_equal_approx(enemy.health, enemy.max_health), "bow without arrows does nothing")
	rec.inventory.add("arrow", 3)
	var from := me.sync_pos + Vector3(0, 1.5, 0)
	var flight := 20.0 / 55.0
	var aim := (enemy.chest() + Vector3(0, 0.5 * GameData.ARROW_GRAVITY * flight * flight, 0) - from).normalized()
	_ready_to_act(1)
	gm.request_primary("shortbow", aim, Vector3.ZERO)
	check(enemy.health < enemy.max_health, "arrow hits at 20m (health %s)" % enemy.health)
	check(rec.inventory.count("arrow") == 2, "shooting uses an arrow")
	_ready_to_act(1)
	gm.request_primary("shortbow", Vector3(0, 0, -1), Vector3.ZERO)
	check(rec.inventory.count("arrow") == 1, "missed shots still use arrows")
	rec.inventory.add("wood", 10)
	rec.inventory.add("stone", 10)
	gm.request_craft("arrow")
	check(rec.inventory.count("arrow") == 6, "arrow recipe yields 5")

	# --- Gates & traps ---
	rec.inventory.add("wooden_gate", 1)
	rec.inventory.add("spike_trap", 1)
	rec.unlocks["spike_trap"] = true
	dir = _place(me, Vector3(60, 0, 10), Vector3(60, 0, 0))
	await _frames(2)
	_ready_to_act(1)
	check(gm.perform_primary(1, "wooden_gate", dir, Vector3(60, 0, 5)), "gate placed")
	var gate: Structure = null
	for s in world.get_structures():
		if s.is_gate():
			gate = s
	check(gate != null and gate.collision_layer == GameData.gate_layer(0), "gate is on its team's gate layer")
	check(me.collision_mask & gate.collision_layer == 0, "own team passes through the gate")
	check(enemy.collision_mask & gate.collision_layer != 0, "enemies are blocked by the gate")
	_ready_to_act(1)
	check(gm.perform_primary(1, "spike_trap", dir, Vector3(66, 0, 5)), "trap placed")
	enemy.teleport(Vector3(66, 0, 5))
	var before := enemy.health
	for i in 60:
		await get_tree().physics_frame
	check(enemy.health < before, "spike trap hurts enemies standing on it")

	# --- Speed check ---
	_place(me, Vector3(0, 0, 0), Vector3(0, 0, 10))
	gm._teleport_player(1, Vector3(0, 0, 0))
	await _frames(40)
	me.teleport(Vector3(80, 0, -100))  # a cheater's "teleport"
	await _frames(40)
	check(GameData.flat_distance(me.position, Vector3.ZERO) < 5.0, "server snaps back impossible movement")

	# --- Scoreboard ---
	await _frames(70)
	check(gm.scoreboard.size() == 2, "scoreboard lists both players")

	# --- Bots ---
	gm.team_fill = 3
	gm._balance_bots()
	await _frames(5)
	var bots := 0
	for r: PlayerRecord in gm.records.values():
		if r.is_bot:
			bots += 1
	check(bots == 4, "bots fill each team to 3 (got %d)" % bots)
	check(world.get_players().size() == 6, "bot players spawned")
	var bot := world.get_player(-1)
	check(bot != null and bot.has_node("Brain"), "bots have brains")
	var start := bot.global_position
	for i in 120:
		await get_tree().physics_frame
	check(bot.global_position.distance_to(start) > 2.0, "bots move on their own")
	gm.team_fill = 0
	gm._balance_bots()
	await _frames(2)
	check(world.get_players().size() == 2, "removing bots never removes humans")

	# --- Sound synthesis (normally skipped headless) ---
	Sfx._build_sounds()
	check(Sfx._streams.size() >= 15, "sound effects synthesize")

	# --- Win & reset ---
	gm.scores[0] = GameData.CAPTURES_TO_WIN - 1
	gm._respawn(1)
	await _frames(2)
	_place(me, Vector3(GameData.crown_pos(1).x, 0, GameData.crown_pos(1).z), Vector3.ZERO)
	await _frames(3)
	_place(me, Vector3(GameData.crown_pos(0).x, 0, GameData.crown_pos(0).z), Vector3.ZERO)
	await _frames(3)
	check(gm.match_over and gm.winner == 0, "third capture wins the match")
	gm._reset_match()
	await _frames(2)
	check(not gm.match_over and gm.scores == [0, 0], "reset clears the match")
	check(rec.inventory.to_dict().is_empty() and rec.gold == 0, "reset clears progress")
	check(tree.amount == tree.max_amount, "reset restores resources")
