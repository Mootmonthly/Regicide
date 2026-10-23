extends Node
## Dedicated-server lobby: waits for players, counts down, cancels if players leave,
## starts a fresh match, and goes back to the lobby when everyone leaves.

var world: World
var gm: GameMode
var _checks := 0
var _failures := 0


func check(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		print("FAIL: " + what)


func _ready() -> void:
	Net.mode = Net.Mode.DEDICATED
	Net.port = 29000 + randi() % 1000
	Net.team_fill = 0
	Net.min_players = 2
	Net.lobby_countdown = 2.0
	world = load("res://scenes/world.tscn").instantiate()
	add_child(world)
	gm = world.game_mode
	await _seconds(0.3)
	check(gm.lobby and gm.lobby_countdown < 0.0, "an empty server waits in the lobby")
	var full := GameData.MATCH_TIME_LIMIT
	await _seconds(1.0)
	check(is_equal_approx(gm.time_left, full), "the match clock doesn't run in the lobby")

	gm._add_player(101, "Alice", 0)
	await _seconds(0.5)
	check(gm.lobby and gm.lobby_countdown < 0.0, "one player isn't enough to start")
	# Crowns can't be taken during warm-up.
	var alice := world.get_player(101)
	alice.teleport(gm.crowns[1].position)
	await _seconds(0.3)
	check(gm.crowns[1].state == CrownRules.State.HOME, "crowns can't be stolen in the warm-up")

	gm._add_player(102, "Bob", 1)
	await _seconds(0.5)
	check(gm.lobby and gm.lobby_countdown > 0.0, "two players start the countdown")
	gm._remove_player(102)
	await _seconds(0.3)
	check(gm.lobby and gm.lobby_countdown < 0.0, "the countdown stops if players leave")

	gm._add_player(103, "Cara", 1)
	alice.teleport(gm.crowns[1].position)
	gm.records[101].last_valid_pos = gm.crowns[1].position
	await _seconds(2.6)
	check(not gm.lobby, "the match starts when the countdown ends")
	await _seconds(1.0)
	check(gm.time_left < full, "the match clock runs once the match starts")
	check((gm.records[101].last_valid_pos as Vector3).distance_to(gm.crowns[1].position) > 20.0, "players are sent to their spawn at the start")

	gm._remove_player(101)
	gm._remove_player(103)
	await _seconds(0.5)
	check(gm.lobby and gm.lobby_countdown < 0.0, "an emptied server goes back to the lobby")

	print("lobby: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _seconds(t: float) -> void:
	await get_tree().create_timer(t, true, true).timeout
