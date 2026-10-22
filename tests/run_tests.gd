extends SceneTree
## Headless unit tests for the pure game-rule classes.
## Run: godot --headless --path . -s res://tests/run_tests.gd

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_test_inventory()
	_test_game_data()
	_test_crown_rules()
	_test_map_generator()
	_test_build_zones()
	print("%d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func check(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		printerr("FAIL: " + what)


func _test_inventory() -> void:
	var inv := Inventory.new()
	check(inv.count("wood") == 0, "empty inventory counts zero")
	inv.add("wood", 5)
	inv.add("wood", 3)
	check(inv.count("wood") == 8, "add accumulates")
	check(not inv.remove("wood", 9), "can't remove more than you have")
	check(inv.count("wood") == 8, "failed remove changes nothing")
	check(inv.remove("wood", 8) and not inv.to_dict().has("wood"), "removing all erases the entry")
	inv.add("wood", 6)
	inv.add("stone", 2)
	check(not inv.pay({"wood": 6, "stone": 3}), "pay fails when short")
	check(inv.count("wood") == 6 and inv.count("stone") == 2, "failed pay is atomic")
	check(inv.pay({"wood": 6, "stone": 2}), "exact pay succeeds")
	check(inv.to_dict().is_empty(), "paid inventory is empty")


func _test_game_data() -> void:
	for id: String in GameData.ITEMS:
		var def := GameData.item(id)
		var kind: String = def.get("kind", "")
		check(kind in GameData.ITEM_KINDS, "%s has a valid kind" % id)
		check(def.has("name") and def.has("recipe") and def.has("unlock_cost"), "%s has name/recipe/unlock_cost" % id)
		for ingredient: String in def.get("recipe", {}):
			check(GameData.is_resource(ingredient) or GameData.is_item(ingredient), "%s ingredient %s exists" % [id, ingredient])
		match kind:
			"tool", "weapon":
				for key in ["damage", "range", "cooldown", "gather"]:
					check(def.has(key), "%s has %s" % [id, key])
			"ranged":
				for key in ["damage", "cooldown", "speed", "range", "ammo"]:
					check(def.has(key), "%s has %s" % [id, key])
				check(GameData.is_item(def.get("ammo", "")), "%s ammo exists" % id)
			"structure":
				check(def.get("size") is Vector3 and float(def.get("health", 0)) > 0, "%s has size and health" % id)
			"consumable":
				check(def.has("effect"), "%s has an effect" % id)
	check(GameData.item("").get("kind") == "fists", "empty id means fists")
	check(GameData.item("nonsense").is_empty(), "unknown items are empty")
	check(GameData.crown_pos(0).z > 0 and GameData.crown_pos(1).z < 0, "teams are on opposite ends")
	var rec := PlayerRecord.new(5, "Test", 0)
	check(rec.is_unlocked("stone_axe"), "free items start unlocked")
	check(not rec.is_unlocked("ballista"), "paid items start locked")


func _test_crown_rules() -> void:
	var S := CrownRules.State
	var A := CrownRules.Action
	check(CrownRules.touch_action(0, S.HOME, 1) == A.PICK_UP, "enemy picks up a home crown")
	check(CrownRules.touch_action(0, S.DROPPED, 1) == A.PICK_UP, "enemy picks up a dropped crown")
	check(CrownRules.touch_action(0, S.HOME, 0) == A.NONE, "owner touching a home crown does nothing")
	check(CrownRules.touch_action(0, S.DROPPED, 0) == A.RETURN, "owner returns a dropped crown")
	check(CrownRules.touch_action(0, S.CARRIED, 0) == A.NONE, "carried crowns can't be touched")
	check(CrownRules.can_capture(1, 0, S.HOME, 1.0), "capture at own pedestal with crown home")
	check(not CrownRules.can_capture(1, 0, S.CARRIED, 1.0), "no capture while own crown is stolen")
	check(not CrownRules.can_capture(1, 0, S.HOME, 10.0), "no capture away from pedestal")
	check(not CrownRules.can_capture(1, 1, S.HOME, 1.0), "can't capture your own crown")
	var c := CrownState.new(1)
	c.apply_dict({"team": 1, "state": S.DROPPED, "carrier": 0, "position": Vector3(5, 0, 5)}, 42.0)
	check(c.state == S.DROPPED and is_equal_approx(c.dropped_at, 42.0), "dropping stamps local time")
	c.send_home()
	check(c.position == GameData.crown_pos(1) and c.state == S.HOME, "send_home resets")


func _test_map_generator() -> void:
	var a := MapGenerator.generate(1234)
	var b := MapGenerator.generate(1234)
	var c := MapGenerator.generate(999)
	check(a.size() > 300, "map has plenty of resource nodes (%d)" % a.size())
	check(a.size() % 2 == 0, "map node count is even (mirrored)")
	check(str(a) == str(b), "same seed gives the same map")
	check(str(a) != str(c), "different seeds give different maps")
	var half := a.size() / 2
	var mirrored := true
	var counts := {}
	for i in half:
		var p: Vector3 = a[i]["pos"]
		var q: Vector3 = a[i + half]["pos"]
		if a[i]["type"] != a[i + half]["type"] or not p.is_equal_approx(Vector3(-q.x, 0, -q.z)):
			mirrored = false
		counts[a[i]["type"]] = counts.get(a[i]["type"], 0) + 1
	check(mirrored, "map is point-mirrored between teams")
	for type: String in GameData.RESOURCES:
		check(counts.get(type, 0) > 0, "map contains %s" % type)
	for e in a:
		var p: Vector3 = e["pos"]
		check(GameData.in_bounds(p), "node inside map: %s" % p)
		for t in GameData.TEAM_COUNT:
			if GameData.flat_distance(p, GameData.crown_pos(t)) < GameData.BASE_CLEAR_RADIUS:
				check(false, "node too close to a crown: %s" % p)


func _test_build_zones() -> void:
	check(not GameData.can_build_at(GameData.crown_pos(0)), "can't build on a pedestal")
	check(GameData.can_build_at(GameData.crown_pos(0) + Vector3(0, 0, -12)), "can build near the base")
	check(not GameData.can_build_at(Vector3(GameData.MAP_WIDTH, 0, 0)), "can't build outside the map")
