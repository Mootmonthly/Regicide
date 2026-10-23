extends Node
## Runs an all-bot match on a dedicated server and reports what happened.
## Run fast-forwarded: godot --headless --path . --fixed-fps 60 res://tests/bot_soak.tscn -- --minutes 6 --bots 50
## Fails if nothing happens (no kills / no crown steals) or on script errors.

var world: World
var gm: GameMode
var stats := {"kills": 0, "steals": 0, "captures": 0, "returns": 0, "wins": 0}
var max_structures := 0
var built := {}  ## item id -> pieces ever placed
var _physics_us := 0
var _frames := 0
## peer -> seconds spent in the river without a break; the worst stretch per minute.
var _wet := {}
var _stuck_in_river := 0  ## bots that spent 30+ s in a row in the river this minute


func _ready() -> void:
	var minutes := 6.0
	var bots := 50
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--minutes":
			minutes = float(args[i + 1])
		if args[i] == "--bots":
			bots = int(args[i + 1])
		if args[i] == "--flat":
			Terrain.force_flat = true
	Net.mode = Net.Mode.DEDICATED
	Net.port = 27500 + randi() % 1000
	Net.team_fill = bots
	Net.min_players = 0  # bots only: no lobby
	world = load("res://scenes/world.tscn").instantiate()
	add_child(world)
	gm = world.game_mode
	gm.message_received.connect(_on_message)
	world.structures_root.child_entered_tree.connect(func(n: Node) -> void:
		if n is Structure:
			built[n.item_id] = built.get(n.item_id, 0) + 1)
	var total := int(minutes * 60.0 * 60.0)
	var next_report := 60.0
	while _frames < total:
		var t0 := Time.get_ticks_usec()
		await get_tree().physics_frame
		_physics_us += Time.get_ticks_usec() - t0
		_frames += 1
		max_structures = maxi(max_structures, world.get_structures().size())
		if _frames % 30 == 0:
			_track_river(0.5)
		if gm.clock >= next_report:
			next_report += 60.0
			_report()
	_report()
	var ok: bool = stats["kills"] > 0 and stats["steals"] > 0
	var why := "bots never fought or never stole a crown"
	if ok and _stuck_in_river > 5:
		ok = false
		why = "%d times a bot spent 30+ s stuck in the river" % _stuck_in_river
	print("SOAK %s" % ("PASSED" if ok else "FAILED: " + why))
	get_tree().quit(0 if ok else 1)


func _on_message(text: String) -> void:
	if " slew " in text:
		stats["kills"] += 1
	elif "has stolen" in text:
		stats["steals"] += 1
	elif " captured " in text:
		stats["captures"] += 1
	elif " returned the " in text:
		stats["returns"] += 1
	elif "victorious" in text:
		stats["wins"] += 1


func _track_river(dt: float) -> void:
	for p in world.get_players():
		if p.alive and p.in_water():
			_wet[p.peer_id] = float(_wet.get(p.peer_id, 0.0)) + dt
			if is_equal_approx(_wet[p.peer_id], 30.0):
				_stuck_in_river += 1
		else:
			_wet[p.peer_id] = 0.0


func _report() -> void:
	var items := {}
	var gold := 0
	for rec: PlayerRecord in gm.records.values():
		gold += rec.gold
		for id: String in rec.inventory.to_dict():
			if GameData.is_item(id):
				items[id] = items.get(id, 0) + rec.inventory.count(id)
	print("[%3ds] players=%d score=%s kills=%d steals=%d captures=%d returns=%d wins=%d structures=%d (max %d) gold=%d avg_frame=%.2fms" % [
		gm.clock, gm.records.size(), str(gm.scores), stats["kills"], stats["steals"], stats["captures"],
		stats["returns"], stats["wins"], world.get_structures().size(), max_structures, gold,
		_physics_us / 1000.0 / maxi(_frames, 1)])
	print("       items held: %s" % str(items))
	print("       pieces built: %s" % str(built))
	var wet_now := 0
	for v: float in _wet.values():
		if v > 0.0:
			wet_now += 1
	print("       in the river now: %d · stuck 30+ s in the river (total): %d" % [wet_now, _stuck_in_river])
