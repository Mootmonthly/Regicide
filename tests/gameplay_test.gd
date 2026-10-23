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
	Terrain.force_flat = true  # mechanics tests want level ground
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

	# Clear the woods so trees don't get in the way of the mechanics tests below.
	for r in world.resource_nodes:
		if r.res_type == "wood":
			r.set_amount(0)

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
	for r in world.resource_nodes:  # clear any trees off the firing line
		if absf(r.position.x + 60.0) < 4.0 and r.position.z > 5.0 and r.position.z < 35.0:
			r.set_amount(0)
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
		var why := world.placement_problem("wood_wall", slot)
		check(gm.perform_build(1, "wood_wall", slot), "wall placed at %s %s" % [slot, why])
	_ready_to_act(1)
	check(not gm.perform_build(1, "stone_wall", tower_walls[0]), "a slot can't hold two walls")
	_ready_to_act(1)
	check(gm.perform_build(1, "wood_floor", S.make_slot(10, 0, 1)), "floor rests on the walls")
	_ready_to_act(1)
	check(gm.perform_build(1, "wood_stairs", S.make_slot(11, 0, 0, 0, 1)), "stairs placed")
	check(rec.inventory.count("wood") == wood_before - 3 * 8 - 6 - 8, "pieces are paid from resources")
	_ready_to_act(1)
	check(not gm.perform_build(1, "wood_floor", S.make_slot(-20, 0, 0)), "can't build out of reach")
	var crown_j := roundi((GameData.crown_pos(0).z - 2.0) / 4.0)
	check(world.placement_problem("wood_wall", S.make_slot(0, crown_j, 0, 0)) != "", "can't build on a crown")
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

	# --- Half walls, windows, battlements ---
	_place(me, Vector3(-42, 0, 40), Vector3(-42, 0, 30))
	await _frames(2)
	_ready_to_act(1)
	check(gm.perform_build(1, "wood_half_wall", S.make_slot(-10, 8, 0, 0)), "half wall placed")
	_ready_to_act(1)
	check(not gm.perform_build(1, "wood_floor", S.make_slot(-10, 8, 1)), "half walls hold nothing up")
	world.structure_spawner.spawn({"uid": 9100, "item": "wood_window", "team": 0, "owner": 1, "slot": S.make_slot(-11, 8, 0, 0)})
	await _frames(1)
	var window: Structure = world.pieces[S.edge_key(0, -11, 8, 0)]
	check(not window.blocks_point(window.global_position + Vector3(0, 1.6, 0)), "you can see and shoot through a window")
	check(window.blocks_point(window.global_position + Vector3(0, 0.5, 0)), "below the window is solid")
	_ready_to_act(1)
	check(gm.perform_build(1, "wood_wall", S.make_slot(-12, 8, 0, 0)), "wall for the battlement")
	_ready_to_act(1)
	check(gm.perform_build(1, "battlement", S.make_slot(-12, 8, 1, 0)), "battlement sits on top of a wall")
	var bat: Structure = world.pieces[S.edge_key(0, -12, 8, 1)]
	check(bat.blocks_point(bat.global_position + Vector3(0, 1.4, 0)) and not bat.blocks_point(bat.global_position + Vector3(0.75, 1.4, 0)), "battlements have merlons and gaps")

	# --- Repair & upgrade ---
	var plain: Structure = world.pieces[S.edge_key(0, -12, 8, 0)]
	plain.health = 100.0
	var wood_now := rec.inventory.count("wood")
	check(gm.perform_repair(1, plain.name), "repair a damaged wall")
	check(is_equal_approx(plain.health, plain.max_health) and rec.inventory.count("wood") < wood_now, "repair restores health and costs wood")
	check(not gm.perform_repair(1, plain.name), "nothing to repair at full health")
	check(not gm.perform_repair(ENEMY, plain.name), "enemies can't repair your walls")
	var stone_now := rec.inventory.count("stone")
	check(gm.perform_upgrade(1, plain.name), "upgrade wood wall to stone")
	await _frames(3)
	var upgraded: Structure = world.pieces.get(S.edge_key(0, -12, 8, 0))
	check(upgraded != null and upgraded.item_id == "stone_wall", "the slot now holds a stone wall")
	check(rec.inventory.count("stone") == stone_now - 10, "upgrading costs the stone wall's price")
	check(world.pieces.has(S.edge_key(0, -12, 8, 1)), "the battlement on top survived the upgrade")
	check(not gm.perform_upgrade(1, upgraded.name), "stone can't be upgraded further")

	# --- Rotation ---
	var straight := S.slot_for("wood_wall", Vector3(1, 0.05, 5.7), Vector3(0, -0.2, -1), Vector3(0, 0, 12), 0)
	var turned := S.slot_for("wood_wall", Vector3(1, 0.05, 5.7), Vector3(0, -0.2, -1), Vector3(0, 0, 12), 1)
	check(straight["axis"] != turned["axis"], "R turns a wall to run the other way")
	var stairs_turned := S.slot_for("wood_stairs", Vector3(0, 0.05, -4), Vector3(0, 0, -1), Vector3.ZERO, 2)
	check(stairs_turned["rot"] == 2, "R turns stairs")

	# --- Drawbridge ---
	_place(me, Vector3(-56, 0, 38), Vector3(-56, 0, 30))
	await _frames(2)
	_ready_to_act(1)
	var db_slot := S.slot_for("drawbridge", Vector3(-56, 0.05, 34.2), Vector3(0, -0.3, -1), me.position)
	check(db_slot["side"] == -1, "a drawbridge lowers away from its builder")
	check(gm.perform_build(1, "drawbridge", db_slot), "drawbridge built")
	var bridge: Structure = world.pieces[S.key("drawbridge", db_slot)]
	var line := bridge.global_position
	check(bridge.blocks_point(line + Vector3(0, 2.0, 0)), "raised drawbridge blocks the way")
	_place(me, Vector3(-56, 0, 36.2), Vector3(-56, 0, 30))
	await _frames(2)
	check(not gm.perform_interact(ENEMY, Vector3.FORWARD), "enemies can't work your drawbridge")
	_ready_to_act(1)
	check(gm.perform_interact(1, Vector3.FORWARD), "lower the drawbridge (E)")
	await _frames(90)
	check(bridge.opened and not bridge.blocks_point(line + Vector3(0, 2.0, 0)), "lowered drawbridge opens the way")
	check(bridge.blocks_point(line + Vector3(0, 0.0, -2.0)), "and lies flat as a bridge on the far side")
	var snap := world.piece_states()
	check(snap.get(String(bridge.name), {}).get("open", false), "late joiners learn it's lowered")

	# --- Catapult ---
	rec.unlocks["catapult"] = true
	rec.inventory.add("stone", 100)
	rec.inventory.add("iron", 20)
	_place(me, Vector3(-32, 0, 60), Vector3(-32, 0, 50))
	await _frames(2)
	_ready_to_act(1)
	check(gm.perform_build(1, "catapult", S.make_slot(-8, 14, 0)), "catapult built")
	var cat: Structure = world.pieces[S.key("free", S.make_slot(-8, 14, 0))]
	world.structure_spawner.spawn({"uid": 9200, "item": "stone_wall", "team": 1, "owner": ENEMY, "slot": S.make_slot(-8, 6, 0, 0)})
	await _frames(1)
	var target_wall: Structure = world.pieces[S.edge_key(0, -8, 6, 0)]
	var hit := false
	var stone_before := rec.inventory.count("stone")
	var shots := 0
	for k in 30:
		var pitch := -0.6 + k * 0.04
		cat._cooldown = 0.0
		if gm.perform_interact(1, Vector3(0, sin(pitch), -cos(pitch))):
			shots += 1
		if not is_instance_valid(target_wall) or target_wall.health < target_wall.max_health:
			hit = true
			break
	check(hit, "the catapult can lob a boulder onto a wall 30 m away")
	check(rec.inventory.count("stone") == stone_before - 5 * shots, "each shot costs 5 stone")
	cat._cooldown = gm.clock + 10.0
	check(not gm.perform_interact(1, Vector3.FORWARD), "the catapult has to reload")

	# --- Battering ram ---
	rec.unlocks["battering_ram"] = true
	rec.inventory.add("wood", 60)
	_place(me, Vector3(-72, 0, 42), Vector3(-72, 0, 32))
	await _frames(2)
	_ready_to_act(1)
	check(gm.perform_build(1, "battering_ram", S.make_slot(-18, 8, 0, 0, 0)), "battering ram built")
	var ram: Structure = null
	for st in world.get_structures():
		if st.is_vehicle():
			ram = st
	world.structure_spawner.spawn({"uid": 9300, "item": "stone_wall", "team": 1, "owner": ENEMY, "slot": S.make_slot(-18, 4, 0, 0)})
	await _frames(1)
	var gate_wall: Structure = world.pieces[S.edge_key(0, -18, 4, 0)]
	var start_z := ram.position.z
	await _frames(60)
	check(is_equal_approx(ram.position.z, start_z), "a ram doesn't move by itself")
	var pusher := _make_walker(0, Vector3(-72, 0, 35.2))
	pusher.rotation.y = 0.0
	pusher.move_input = Vector2(0, -1)
	await _frames(240)
	check(ram.position.z < start_z - 3.0, "pushing from behind rolls the ram forward (moved %.1f m)" % (start_z - ram.position.z))
	await _frames(420)
	pusher.move_input = Vector2.ZERO
	check(not is_instance_valid(gate_wall) or gate_wall.health < gate_wall.max_health, "the ram batters the enemy wall in front of it")
	gm._remove_player(pusher.peer_id)

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

	# --- Spells & mana ---
	gm._respawn(ENEMY)
	var erec: PlayerRecord = gm.records[ENEMY]
	erec.protected_until = 0.0
	me.health = me.max_health
	_place(me, Vector3(-120, 0, 60), Vector3(-120, 0, 40))
	enemy.teleport(Vector3(-120, 0, 45))
	enemy.health = enemy.max_health
	await _frames(3)
	rec.gold = 1000
	rec.inventory.add("magic_ore", 30)
	gm.request_unlock("frost_bolt")
	check(rec.unlocks.has("frost_bolt") and rec.gold == 900, "learn a spell with gold")
	check(rec.inventory.count("magic_ore") == 28, "learning a spell costs magic ore too")
	check(gm.hotbar_items().has("frost_bolt"), "learned spells show on the hotbar")
	for sp in ["fireball", "lightning", "heal_aura", "blink", "earth_wall"]:
		gm.request_unlock(sp)
	var mana_before := me.mana
	var to_enemy := (enemy.chest() - (me.sync_pos + Vector3(0, 1.5, 0))).normalized()
	_ready_to_act(1)
	check(gm.perform_primary(1, "frost_bolt", to_enemy, Vector3.ZERO), "cast frost bolt")
	check(enemy.health < enemy.max_health and enemy.slowed, "frost bolt hurts and slows")
	check(is_equal_approx(me.mana, mana_before - 20.0), "spells cost mana")
	check(enemy.current_speed(false) < Player.WALK_SPEED, "slowed players move slower")
	_ready_to_act(1)
	check(not gm.perform_primary(1, "frost_bolt", to_enemy, Vector3.ZERO), "spells have their own cooldown")
	me.mana = 5.0
	rec.spell_ready.clear()
	_ready_to_act(1)
	check(not gm.perform_primary(1, "lightning", to_enemy, Vector3.ZERO), "can't cast without mana")
	await _frames(70)
	check(me.mana > 5.0, "mana regenerates")
	await _frames(130)
	check(not enemy.slowed, "the slow wears off")
	# Lightning chains to a second enemy.
	gm.records[ENEMY + 1] = PlayerRecord.new(ENEMY + 1, "Enemy2", 1)
	world.player_spawner.spawn({"peer_id": ENEMY + 1, "team": 1, "name": "Enemy2", "pos": Vector3(-116, 0, 45)})
	var enemy2 := world.get_player(ENEMY + 1)
	await _frames(2)
	me.mana = me.max_mana
	var h1 := enemy.health
	_ready_to_act(1)
	check(gm.perform_primary(1, "lightning", (enemy.chest() - (me.sync_pos + Vector3(0, 1.5, 0))).normalized(), Vector3.ZERO), "cast lightning")
	check(enemy.health < h1 and enemy2.health < enemy2.max_health, "lightning chains to a nearby enemy")
	gm._remove_player(ENEMY + 1)
	# Heal aura.
	me.health = 30.0
	rec.spell_ready.clear()
	_ready_to_act(1)
	gm.perform_primary(1, "heal_aura", Vector3.FORWARD, Vector3.ZERO)
	check(is_equal_approx(me.health, 65.0), "heal aura heals 35")
	# Blink.
	me.mana = me.max_mana
	var blink_from := me.position
	_ready_to_act(1)
	check(gm.perform_primary(1, "blink", Vector3(1, 0, 0), Vector3.ZERO), "cast blink")
	await _frames(2)
	check(me.position.x - blink_from.x > 10.0, "blink moves you about 14 m (%.1f)" % (me.position.x - blink_from.x))
	# Earth wall rises, then crumbles.
	_ready_to_act(1)
	var walls_before := world.get_structures().size()
	check(gm.perform_primary(1, "earth_wall", Vector3(0, 0, -1), Vector3.ZERO), "cast earth wall")
	await _frames(2)
	check(world.get_structures().size() == walls_before + 1, "an earth wall appears")
	var summoned: Structure = world.get_structures()[-1]
	check(summoned.item_id == "earth_wall_piece" and summoned.lifetime > 0.0, "it's a temporary wall")
	gm.expire_structure(summoned)
	await _frames(2)
	check(world.get_structures().size() == walls_before, "and crumbles when its time is up")
	# Gust throws enemies back and knocks a stolen crown loose.
	for sp in ["gust", "meteor", "spectral_warriors"]:
		rec.gold += 400
		rec.inventory.add("magic_ore", 6)
		gm.request_unlock(sp)
		check(rec.unlocks.has(sp), "learn %s" % sp)
	_place(me, Vector3(-120, 0, 60), Vector3(-120, 0, 40))
	enemy.teleport(Vector3(-120, 0, 56))
	enemy.health = enemy.max_health
	var our_crown: CrownState = gm.crowns[0]
	our_crown.state = CrownRules.State.CARRIED
	our_crown.carrier = ENEMY
	enemy.carrying_crown = 0
	await _frames(3)
	me.mana = me.max_mana
	_ready_to_act(1)
	check(gm.perform_primary(1, "gust", Vector3(0, 0, -1), Vector3.ZERO), "cast gust")
	check(enemy.carrying_crown == -1 and our_crown.state == CrownRules.State.DROPPED, "gust knocks the crown out of the carrier's hands")
	# (The enemy here is a stand-in for a remote player, so check where the server sent them.)
	check(erec.last_valid_pos.z < 51.0, "gust throws the enemy back (to %.1f m away)" % (60.0 - erec.last_valid_pos.z))
	check(enemy.health < enemy.max_health, "gust stings a little")
	our_crown.send_home()
	gm._sync_crowns()
	# Casting a long-cooldown spell doesn't lock your other actions for its whole cooldown.
	check(rec.next_action_time - gm.clock < 1.0, "spells only keep your hands busy briefly")
	# Meteor: warning first, then the blast.
	enemy.health = enemy.max_health
	enemy.teleport(Vector3(-120, 0, 40))
	await _frames(3)
	me.mana = me.max_mana
	_ready_to_act(1)
	var to_spot := (Vector3(-120, 0, 40) - (me.sync_pos + Vector3(0, 1.5, 0))).normalized()
	check(gm.perform_primary(1, "meteor", to_spot, Vector3.ZERO), "cast meteor")
	await _frames(30)
	check(enemy.health == enemy.max_health, "the meteor hasn't landed yet (time to dodge)")
	await _frames(80)
	check(enemy.health < enemy.max_health - 50.0, "the meteor hits hard (took %.0f)" % (enemy.max_health - enemy.health))
	# Spectral warriors: five of them, hunting enemies.
	await _frames(400)  # let the enemy respawn if the meteor killed them
	gm._respawn(ENEMY)
	enemy.health = enemy.max_health
	erec.protected_until = 0.0
	_place(me, Vector3(-120, 0, 60), Vector3(-120, 0, 40))
	enemy.teleport(Vector3(-120, 0, 35))
	await _frames(3)
	me.mana = me.max_mana
	_ready_to_act(1)
	check(gm.perform_primary(1, "spectral_warriors", Vector3(0, 0, -1), Vector3.ZERO), "cast spectral warriors")
	await _frames(3)
	var warriors := world.get_summons()
	check(warriors.size() == 5, "five spectral warriors rise (%d)" % warriors.size())
	check(warriors.size() > 0 and warriors[0].team == 0 and warriors[0].owner_peer == 1, "they fight for the caster")
	var spectral_ready := float(rec.spell_ready.get("spectral_warriors", 0.0)) - gm.clock
	check(spectral_ready > 55.0 and spectral_ready <= 60.0, "spectral warriors recharge for 60 s")
	var hp_before := enemy.health
	for i in 240:
		await get_tree().physics_frame
		if enemy.health < hp_before:
			break
	check(enemy.health < hp_before, "the warriors charge and strike an enemy 25 m away")
	# Enemies can fight back.
	var w0: Summon = world.get_summons()[0]
	var w_hp := w0.health
	gm.damage_summon(w0, 25.0)
	check(is_equal_approx(w0.health, w_hp - 25.0), "warriors can be hurt")
	gm.damage_summon(w0, 100.0)
	await _frames(2)
	check(world.get_summons().size() == 4, "and cut down")
	for w in world.get_summons():
		w.expires_at = gm.clock
	await _frames(3)
	check(world.get_summons().is_empty(), "they fade when their time is up")
	# Bots fight enemy warriors too.
	rec.spell_ready.clear()
	me.mana = me.max_mana
	_place(me, Vector3(-150, 0, 60), Vector3(-150, 0, 40))
	await _frames(2)
	_ready_to_act(1)
	gm.perform_primary(1, "spectral_warriors", Vector3(0, 0, -1), Vector3.ZERO)
	await _frames(2)
	me.alive = false  # out of the picture: the warriors are the only enemies around
	gm._add_bot(1)
	var bot_id := gm._next_bot_id + 1
	var fighter := world.get_player(bot_id)
	var brec: PlayerRecord = gm.records[bot_id]
	brec.inventory.add("iron_sword", 1)
	brec.protected_until = gm.clock + 100.0  # so the warriors can't kill it first
	fighter.teleport(Vector3(-150, 0, 57))
	var pack_hp := 0.0
	for w in world.get_summons():
		pack_hp += w.health
	var pack_hit := false
	for i in 360:
		await get_tree().physics_frame
		var now_hp := 0.0
		for w in world.get_summons():
			now_hp += w.health
		if now_hp < pack_hp or world.get_summons().size() < 5:
			pack_hit = true
			break
	check(pack_hit, "a bot fights enemy spectral warriors")
	for w in world.get_summons():
		gm.remove_summon(w)
	gm._remove_player(bot_id)
	me.alive = true
	me.health = me.max_health
	await _frames(2)
	# Skills: Spellweaver and Bloodlust.
	rec.skill_points = 10
	check(gm.perform_skill(1, "spellweaver"), "learn Spellweaver")
	rec.spell_ready.clear()
	me.mana = me.max_mana
	_ready_to_act(1)
	gm.perform_primary(1, "frost_bolt", Vector3(0, 0, -1), Vector3.ZERO)
	check(is_equal_approx(me.max_mana - me.mana, 18.0), "Spellweaver: frost bolt costs 18 mana instead of 20")
	check(gm.perform_skill(1, "bloodlust"), "learn Bloodlust")
	enemy.health = enemy.max_health
	_place(me, Vector3(-120, 0, 50), Vector3(-120, 0, 48))
	enemy.teleport(Vector3(-120, 0, 48))
	rec.inventory.add("iron_sword", 1)
	me.health = 50.0
	await _frames(3)
	_ready_to_act(1)
	gm.perform_primary(1, "iron_sword", Vector3(0, 0, -1), Vector3.ZERO)
	check(is_equal_approx(me.health, 53.0), "Bloodlust: a 30-damage hit heals 3 (now %.1f)" % me.health)
	# --- More spells ---
	for sp in ["thunderclap", "siphon_life", "battle_cry", "shadow_cloak", "arcane_ward"]:
		rec.gold += 300
		rec.inventory.add("magic_ore", 6)
		gm.request_unlock(sp)
		check(rec.unlocks.has(sp), "learn %s" % sp)
	# Thunderclap stuns enemies close by (Iron Will shortens it).
	erec.skills["iron_will"] = 2
	enemy.health = enemy.max_health
	_place(me, Vector3(-120, 0, 50), Vector3(-120, 0, 47))
	enemy.teleport(Vector3(-120, 0, 47))
	await _frames(3)
	me.mana = me.max_mana
	rec.spell_ready.clear()
	_ready_to_act(1)
	check(gm.perform_primary(1, "thunderclap", Vector3(0, 0, -1), Vector3.ZERO), "cast thunderclap")
	check(enemy.stunned and enemy.health < enemy.max_health, "thunderclap hurts and stuns enemies nearby")
	check(absf(erec.stun_until - gm.clock - 0.75) < 0.05, "Iron Will rank 2 halves the stun (%.2f s)" % (erec.stun_until - gm.clock))
	erec.skills.clear()
	await _frames(60)
	check(not enemy.stunned, "the stun wears off")
	# Siphon Life drains and heals.
	enemy.health = enemy.max_health
	enemy.teleport(Vector3(-120, 0, 35))
	await _frames(3)
	me.health = 50.0
	_ready_to_act(1)
	check(gm.perform_primary(1, "siphon_life", (enemy.chest() - (me.sync_pos + Vector3(0, 1.5, 0))).normalized(), Vector3.ZERO), "cast siphon life")
	check(is_equal_approx(enemy.health, enemy.max_health - 22.0) and is_equal_approx(me.health, 72.0), "siphon life takes 22 and heals you 22 (you %.0f)" % me.health)
	# Battle Cry: faster, and hits harder.
	me.mana = me.max_mana
	var walk := me.current_speed(false)
	_ready_to_act(1)
	check(gm.perform_primary(1, "battle_cry", Vector3(0, 0, -1), Vector3.ZERO), "cast battle cry")
	check(me.rallied and me.current_speed(false) > walk * 1.2, "battle cry makes you faster")
	enemy.health = enemy.max_health
	enemy.teleport(Vector3(-120, 0, 48))
	await _frames(3)
	_ready_to_act(1)
	gm.perform_primary(1, "iron_sword", Vector3(0, 0, -1), Vector3.ZERO)
	check(is_equal_approx(enemy.max_health - enemy.health, 36.0), "battle cry: +20%% damage (took %.0f)" % (enemy.max_health - enemy.health))
	rec.rally_until = gm.clock
	await _frames(10)
	check(not me.rallied, "battle cry wears off")
	# Arcane Ward soaks damage.
	me.health = me.max_health
	me.mana = me.max_mana
	_ready_to_act(1)
	check(gm.perform_primary(1, "arcane_ward", Vector3(0, 0, -1), Vector3.ZERO), "cast arcane ward")
	gm.damage_player(1, 30.0, ENEMY)
	check(me.health == me.max_health and me.warded, "the ward soaks a 30-damage hit")
	gm.damage_player(1, 30.0, ENEMY)
	check(is_equal_approx(me.health, me.max_health - 20.0) and not me.warded, "then breaks, letting the rest through")
	# Shadow Cloak hides you from bots, turrets and warriors until you act.
	me.health = me.max_health
	me.mana = me.max_mana
	_ready_to_act(1)
	check(gm.perform_primary(1, "shadow_cloak", Vector3(0, 0, -1), Vector3.ZERO), "cast shadow cloak")
	check(me.cloaked and gm.nearest_enemy(enemy.sync_pos, 1, 50.0) != me, "cloaked players are hidden from enemy targeting")
	_ready_to_act(1)
	gm.perform_primary(1, "iron_sword", Vector3(0, 0, -1), Vector3.ZERO)
	check(not me.cloaked, "attacking reveals you")
	gm.crowns[1].state = CrownRules.State.CARRIED
	gm.crowns[1].carrier = 1
	me.carrying_crown = 1
	rec.spell_ready.clear()
	me.mana = me.max_mana
	_ready_to_act(1)
	check(not gm.perform_primary(1, "shadow_cloak", Vector3(0, 0, -1), Vector3.ZERO), "you can't cloak while carrying a crown")
	gm.crowns[1].send_home()
	me.carrying_crown = -1
	gm._sync_crowns()
	# --- Spell Forge spells ---
	for sp in ["magic_missiles", "chain_hook"]:
		rec.gold += 300
		rec.inventory.add("magic_ore", 6)
		gm.request_unlock(sp)
		check(rec.unlocks.has(sp), "learn %s" % sp)
	# Magic Missiles curve onto an enemy even when the aim is a little off.
	enemy.health = enemy.max_health
	_place(me, Vector3(-120, 0, 60), Vector3(-120, 0, 40))
	enemy.teleport(Vector3(-120, 0, 45))
	await _frames(3)
	me.mana = me.max_mana
	rec.spell_ready.clear()
	_ready_to_act(1)
	var off_aim := (enemy.chest() - (me.sync_pos + Vector3(0, 1.5, 0))).normalized().rotated(Vector3.UP, 0.1)
	check(gm.perform_primary(1, "magic_missiles", off_aim, Vector3.ZERO), "cast magic missiles")
	check(enemy.health == enemy.max_health, "missiles take time to fly")
	await _frames(75)
	var mm_damage := enemy.max_health - enemy.health
	check(mm_damage >= 24.0 and mm_damage <= 36.0, "at least two of the three missiles home in (took %.0f)" % mm_damage)
	# Chain Hook damages and drags the enemy toward you.
	enemy.health = enemy.max_health
	enemy.teleport(Vector3(-120, 0, 42))
	erec.last_valid_pos = Vector3(-120, 0, 42)
	await _frames(3)
	me.mana = me.max_mana
	_ready_to_act(1)
	check(gm.perform_primary(1, "chain_hook", (enemy.chest() - (me.sync_pos + Vector3(0, 1.5, 0))).normalized(), Vector3.ZERO), "cast chain hook")
	check(is_equal_approx(enemy.max_health - enemy.health, 12.0), "chain hook does 12 damage")
	# (The enemy stands in for a remote player, so check where the server sent them.)
	check(absf(erec.last_valid_pos.z - 48.0) < 0.6, "and pulls them 6 m toward you (now at z %.1f)" % erec.last_valid_pos.z)
	enemy.teleport(erec.last_valid_pos)
	# A hook at arm's length doesn't pull them past you.
	enemy.teleport(Vector3(-120, 0, 58))
	erec.last_valid_pos = Vector3(-120, 0, 58)
	await _frames(3)
	rec.spell_ready.clear()
	me.mana = me.max_mana
	_ready_to_act(1)
	gm.perform_primary(1, "chain_hook", (enemy.chest() - (me.sync_pos + Vector3(0, 1.5, 0))).normalized(), Vector3.ZERO)
	check(erec.last_valid_pos.z < 60.0, "the hook never drags anyone behind you")
	enemy.health = enemy.max_health

	# --- More skills ---
	rec.skill_points = 10
	check(gm.perform_skill(1, "bounty_hunter"), "learn Bounty Hunter")
	var gold_before := rec.gold
	enemy.health = 1.0
	_ready_to_act(1)
	gm.perform_primary(1, "iron_sword", Vector3(0, 0, -1), Vector3.ZERO)
	check(rec.gold - gold_before == GameData.GOLD_PER_KILL + 15, "Bounty Hunter: +15 gold per kill (got %d)" % (rec.gold - gold_before))
	check(gm.perform_skill(1, "horsemanship"), "learn Horsemanship")
	await _frames(2)
	me.mounted = true
	var ride := me.current_speed(false)
	rec.skills.erase("horsemanship")
	gm._push_private(1)
	await _frames(2)
	check(ride > me.current_speed(false) * 1.07, "Horsemanship: riding is faster")
	me.mounted = false
	# Dash: a burst the way you face; the server's speed check lets it through.
	check(not me.try_dash(), "no dashing without the Dash skill")
	check(gm.perform_skill(1, "dash"), "learn Dash")
	await _frames(2)
	var dash_from := _place(me, Vector3(-60, 0, 60), Vector3(-60, 0, 0))
	dash_from = me.position
	me.stamina = GameData.MAX_STAMINA
	await _frames(2)
	check(me.try_dash(), "dash")
	check(is_equal_approx(me.stamina, GameData.MAX_STAMINA - GameData.DASH_STAMINA), "dashing costs stamina")
	check(not me.try_dash(), "dash has to recharge")
	await _frames(20)
	var dashed := dash_from.z - me.position.z
	check(dashed > 7.0 and dashed < 9.5, "dash covers about 8 m forward (%.1f m)" % dashed)
	await _frames(45)  # past a server movement check
	check(dash_from.z - me.position.z > 7.0, "the server accepts the dash (no snap back)")
	# A move a bit beyond normal speed is accepted once per recharge, as a dash.
	var over := GameData.MAX_PLAYER_SPEED * 1.5 * 0.5 + 1.5 + 5.0
	rec.dash_ready = 0.0
	rec.last_move_check = gm.clock - 0.5
	rec.last_valid_pos = me.sync_pos + Vector3(0, 0, over)
	gm._check_movement()
	check(rec.last_valid_pos.distance_to(me.sync_pos) < 0.01, "the speed check allows one dash's worth of extra distance")
	var stay := me.sync_pos
	rec.last_move_check = gm.clock - 0.5
	rec.last_valid_pos = me.sync_pos + Vector3(0, 0, over)
	gm._check_movement()
	await _frames(2)
	check(me.sync_pos.distance_to(stay) > over - 1.0, "but not again until it recharges (snapped back)")
	_place(me, stay, stay + Vector3(0, 0, -10))
	gm.crowns[1].state = CrownRules.State.CARRIED
	gm.crowns[1].carrier = 1
	me.carrying_crown = 1
	me._dash_ready = 0.0
	check(not me.try_dash(), "no dashing with a crown")
	gm.crowns[1].send_home()
	me.carrying_crown = -1
	gm._sync_crowns()
	gm._respawn(ENEMY)
	erec.protected_until = 0.0
	enemy.health = enemy.max_health
	await _frames(2)
	me.health = me.max_health
	rec.skills.clear()
	rec.skill_points = 0

	# --- Shields: block and parry ---
	erec.inventory.add("wooden_shield")
	enemy.health = enemy.max_health
	_place(me, Vector3(-120, 0, 50), Vector3(-120, 0, 48))
	enemy.teleport(Vector3(-120, 0, 48))
	enemy.sync_yaw = 0.0  # facing +Z? no: yaw 0 faces -Z; turn to face me (+Z)
	enemy.sync_yaw = PI
	enemy.rotation.y = PI
	rec.inventory.add("iron_sword", 1)
	enemy.blocking = true
	await _frames(40)  # past the parry window
	_ready_to_act(1)
	gm.perform_primary(1, "iron_sword", Vector3(0, 0, -1), Vector3.ZERO)
	var blocked_damage := enemy.max_health - enemy.health
	check(is_equal_approx(blocked_damage, 30.0 * 0.4), "a wooden shield blocks 60%% from the front (took %.1f)" % blocked_damage)
	enemy.blocking = false
	await _frames(1)
	enemy.blocking = true  # raised just as the blow lands
	_ready_to_act(1)
	var hp := enemy.health
	gm.perform_primary(1, "iron_sword", Vector3(0, 0, -1), Vector3.ZERO)
	check(is_equal_approx(enemy.health, hp), "a well-timed block parries all damage")
	check(me.stunned, "parrying stuns the attacker")
	_ready_to_act(1)
	rec.next_action_time = 0.0
	check(not gm.perform_primary(1, "iron_sword", Vector3(0, 0, -1), Vector3.ZERO), "stunned players can't attack")
	check(me.current_speed(true) == 0.0, "stunned players can't move")
	await _frames(80)
	check(not me.stunned, "the stun wears off")
	enemy.blocking = false
	enemy.sync_yaw = 0.0  # back turned
	enemy.rotation.y = 0.0
	enemy.blocking = true
	await _frames(40)
	hp = enemy.health
	_ready_to_act(1)
	gm.perform_primary(1, "iron_sword", Vector3(0, 0, -1), Vector3.ZERO)
	check(is_equal_approx(hp - enemy.health, 30.0), "shields don't help against hits from behind")
	enemy.blocking = false

	# --- Skills ---
	rec.skill_points = 0
	check(not gm.perform_skill(1, "toughness"), "skills cost points")
	rec.skill_points = 3
	var max_before := me.max_health
	check(gm.perform_skill(1, "toughness"), "spend a point on Toughness")
	check(is_equal_approx(me.max_health, max_before + 15.0), "Toughness raises max health right away")
	check(gm.perform_skill(1, "toughness") and rec.skill_points == 0, "rank 2 costs 2 points")
	var kills_points := rec.skill_points
	enemy.health = 1.0
	erec.protected_until = 0.0
	_ready_to_act(1)
	gm.perform_primary(1, "iron_sword", Vector3(0, 0, -1), Vector3.ZERO)
	check(rec.skill_points == kills_points + GameData.SKILL_POINTS_PER_KILL, "kills earn skill points")

	# --- Voice chat routing ---
	gm._respawn(ENEMY)
	enemy.teleport(me.position + Vector3(0, 0, -10))
	await _frames(2)
	var near := world.voice.recipients(1, VoiceChat.Channel.PROXIMITY)
	check(near.has(ENEMY), "proximity chat reaches players nearby (even enemies)")
	enemy.teleport(me.position + Vector3(0, 0, -120))
	await _frames(2)
	check(not world.voice.recipients(1, VoiceChat.Channel.PROXIMITY).has(ENEMY), "but not players far away")
	check(not world.voice.recipients(1, VoiceChat.Channel.TEAM).has(ENEMY), "team radio skips the other team")
	check(not world.voice.recipients(1, VoiceChat.Channel.PROXIMITY).has(1), "you don't hear yourself")
	world.voice._voice_down(ENEMY, VoiceChat.encode(PackedFloat32Array([0.1, 0.2])), VoiceChat.Channel.PROXIMITY)
	check(world.voice.speaking.has(ENEMY), "incoming voice marks the speaker as talking")

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
	check(GameData.MATCH_TIME_LIMIT - gm.time_left < 1.0, "reset restarts the 30-minute clock")
	check(rec.inventory.to_dict().is_empty() and rec.gold == 0, "reset clears progress")
	check(tree.amount == tree.max_amount, "reset restores resources")

	# --- Settings: key rebinding ---
	var jump_default := Settings.binding_text("jump")
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_J
	Settings.bind("jump", ev)
	check(Settings.binding_text("jump") == "J" and InputMap.action_has_event("jump", ev), "rebinding a key changes the input map (%s)" % Settings.binding_text("jump"))
	Settings.bind("sprint", ev)
	check(Settings.conflicts("jump").size() == 1, "binding two actions to one key is flagged")
	Settings.reset_bindings()
	check(Settings.binding_text("jump") == jump_default, "reset puts the default keys back")
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_XBUTTON1
	Settings.bind("dash", mb)
	check(Settings.binding_text("dash") == "Mouse 4", "actions can be bound to mouse buttons")
	Settings.reset_bindings()

	# --- Time limit ---
	gm.match_started_at = gm.clock - (GameData.MATCH_TIME_LIMIT - 120.0)
	await _frames(2)
	check(absf(gm.time_left - 120.0) < 0.5, "the clock counts down (%.1f s left)" % gm.time_left)
	gm.scores = [1, 0]
	gm.match_started_at = gm.clock - GameData.MATCH_TIME_LIMIT
	await _frames(2)
	check(gm.match_over and gm.winner == 0, "when time runs out, the team with more captures wins")
	gm._reset_match()
	await _frames(2)
	gm.scores = [1, 1]
	gm.match_started_at = gm.clock - GameData.MATCH_TIME_LIMIT
	await _frames(2)
	check(not gm.match_over and gm.overtime, "a tie at the time limit goes to overtime")
	gm.scores[1] = 1
	var ot_crown: CrownState = gm.crowns[0]
	ot_crown.state = CrownRules.State.CARRIED
	ot_crown.carrier = ENEMY
	enemy.carrying_crown = 0
	gm._respawn(ENEMY)
	enemy.alive = true
	erec.protected_until = 0.0
	gm._capture(enemy, ot_crown)
	await _frames(2)
	check(gm.match_over and gm.winner == 1, "in overtime the next capture wins")
	gm._reset_match()
	await _frames(2)
	check(not gm.overtime and not gm.match_over, "reset ends overtime")
