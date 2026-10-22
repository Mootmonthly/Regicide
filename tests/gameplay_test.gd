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


func _make_walker(team: int, pos: Vector3) -> Player:
	gm._add_bot(team)
	var id := gm._next_bot_id + 1
	var w := world.get_player(id)
	w.get_node("Brain").free()
	gm.records[id].protected_until = 0.0
	w.teleport(pos)
	return w


## Put a player at pos facing toward look_at (flat).
func _place(p: Player, pos: Vector3, look_at_pos: Vector3) -> Vector3:
	p.teleport(pos)
	if gm.records.has(p.peer_id):
		gm.records[p.peer_id].last_valid_pos = pos
		gm.records[p.peer_id].last_move_check = gm.clock
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
	gm.request_craft("crossbow")
	check(rec.inventory.count("crossbow") == 0, "locked blueprint can't be crafted")
	gm.request_craft("wood_wall")
	check(rec.inventory.count("wood_wall") == 0, "building pieces aren't crafted")
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
	gm.request_unlock("crossbow")
	check(not rec.unlocks.has("crossbow"), "can't unlock without gold")
	rec.gold = 500
	gm.request_unlock("crossbow")
	check(rec.unlocks.has("crossbow") and rec.gold == 325, "unlock spends gold")
	rec.inventory.add("iron", 10)
	gm.request_craft("crossbow")
	check(rec.inventory.count("crossbow") == 1, "unlocked blueprint can be crafted")

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

	# --- Building: a small tower you can walk up ---
	var S := BuildGrid
	var walker := _make_walker(0, Vector3(52, 0, 0))
	var wrec: PlayerRecord = gm.records[walker.peer_id]
	rec.inventory.add("wood", 200)
	rec.inventory.add("stone", 100)
	_place(me, Vector3(46, 0, 7), Vector3(40, 0, 0))
	await _frames(2)
	check(not gm.perform_build(1, "wood_floor", S.make_slot(10, 0, 1)), "can't build a floating floor")
	check(not gm.perform_build(1, "wood_wall", S.make_slot(10, 0, 1, 0)), "can't build a floating wall")
	var wood_before := rec.inventory.count("wood")
	var tower_walls := [S.make_slot(10, 0, 0, 0), S.make_slot(10, -1, 0, 0), S.make_slot(9, 0, 0, 1)]
	for slot: Dictionary in tower_walls:
		_ready_to_act(1)
		check(gm.perform_build(1, "wood_wall", slot), "wall placed at %s" % slot)
	_ready_to_act(1)
	check(not gm.perform_build(1, "stone_wall", tower_walls[0]), "a slot can't hold two walls")
	_ready_to_act(1)
	check(gm.perform_build(1, "wood_floor", S.make_slot(10, 0, 1)), "floor rests on the walls")
	_ready_to_act(1)
	check(gm.perform_build(1, "wood_stairs", S.make_slot(11, 0, 0, 0, 1)), "stairs placed")
	check(rec.inventory.count("wood") == wood_before - 3 * 8 - 6 - 8, "pieces are paid from resources")
	_ready_to_act(1)
	check(not gm.perform_build(1, "wood_floor", S.make_slot(-20, 0, 0)), "can't build out of reach")
	check(world.placement_problem("wood_wall", S.make_slot(0, 37, 0, 0)) != "", "can't build on a crown")
	var crowd := S.make_slot(roundi(walker.position.x / 4.0), roundi(walker.position.z / 4.0), 0)
	check(world.placement_problem("wood_floor", crowd) == "Someone is in the way.", "can't build on top of someone")
	# Walk up the stairs (they rise toward -X) and onto the floor.
	walker.teleport(Vector3(48, 0, 0))
	walker.rotation.y = PI / 2.0
	walker.move_input = Vector2(0, -1)
	await _frames(85)
	walker.move_input = Vector2.ZERO
	await _frames(10)
	check(walker.position.y > 2.7 and walker.position.x > 38.0 and walker.position.x < 42.0, "walked up the stairs onto the floor (%s)" % walker.position)
	# Knock out the walls: the floor comes down with them.
	gm.damage_structure(world.pieces[S.key("wall", tower_walls[0])], 9999.0)
	gm.damage_structure(world.pieces[S.key("wall", tower_walls[1])], 9999.0)
	await _frames(3)
	check(world.pieces.has(S.floor_key(10, 0, 1)), "the floor stands while one wall holds it")
	gm.damage_structure(world.pieces[S.key("wall", tower_walls[2])], 9999.0)
	await _frames(3)
	check(not world.pieces.has(S.floor_key(10, 0, 1)), "the floor collapses when its last wall falls")
	check(world.pieces.has(S.key("stairs", S.make_slot(11, 0, 0))), "ground-level pieces stay up")
	await _frames(60)
	check(walker.position.y < 0.5, "whoever stood on it falls")

	# --- Ladders: over an enemy wall ---
	world.structure_spawner.spawn({"uid": 9000, "item": "stone_wall", "team": 1, "owner": ENEMY, "slot": S.make_slot(15, 5, 0, 0)})
	walker.teleport(Vector3(60, 0, 25))
	walker.rotation.y = 0.0  # facing -Z, toward the wall at z=22
	walker.move_input = Vector2(0, -1)
	await _frames(40)
	check(walker.position.z > 22.3, "the enemy wall blocks the way (%s)" % walker.position)
	wrec.inventory.add("wood", 4)
	wrec.next_action_time = 0.0
	check(gm.perform_build(walker.peer_id, "ladder", S.make_slot(15, 5, 0, 0, 0, 1)), "ladder placed against the enemy wall")
	check(world.ladders.size() == 1, "ladder registered")
	var max_y := 0.0
	for i in 150:
		await get_tree().physics_frame
		max_y = maxf(max_y, walker.position.y)
	walker.move_input = Vector2.ZERO
	check(max_y > 2.9, "climbed the ladder (max height %.2f)" % max_y)
	check(walker.position.z < 21.5, "and dropped over the wall (%s)" % walker.position)
	gm._remove_player(walker.peer_id)

	# --- Doors, arrow slits, traps ---
	world.structure_spawner.spawn({"uid": 9001, "item": "wood_door", "team": 0, "owner": 1, "slot": S.make_slot(15, 10, 0, 0)})
	world.structure_spawner.spawn({"uid": 9002, "item": "arrow_slit", "team": 0, "owner": 1, "slot": S.make_slot(15, 12, 0, 0)})
	await _frames(1)
	var door: Structure = world.pieces[S.edge_key(0, 15, 10, 0)]
	check(door.collision_layer == GameData.gate_layer(0), "door is on its team's gate layer")
	check(me.collision_mask & door.collision_layer == 0, "own team walks through doors")
	check(enemy.collision_mask & door.collision_layer != 0, "enemies are blocked by doors")
	var slit: Structure = world.pieces[S.edge_key(0, 15, 12, 0)]
	check(not slit.blocks_point(slit.global_position + Vector3(0, 1.55, 0)), "arrows fit through the slit")
	check(slit.blocks_point(slit.global_position + Vector3(0, 0.6, 0)), "the rest of the slit wall is solid")
	check(slit.blocks_point(slit.global_position + Vector3(1.4, 1.55, 0)), "beside the slit is solid")
	rec.unlocks["spike_trap"] = true
	rec.inventory.add("iron", 5)
	_place(me, Vector3(60, 0, 6), Vector3(64, 0, 8))
	await _frames(2)
	_ready_to_act(1)
	check(gm.perform_build(1, "spike_trap", S.make_slot(16, 2, 0)), "trap placed")
	enemy.teleport(Vector3(64, 0, 8))
	var trap: Structure = world.pieces[S.key("free", S.make_slot(16, 2, 0))]
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
	var bot: Player = null
	for p in world.get_players():
		if p.is_bot:
			bot = p
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
