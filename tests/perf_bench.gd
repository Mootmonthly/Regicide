extends Node
## Client performance benchmark: hosts a match with 50 bots per team, gathers everyone in
## front of the camera running in circles, and reports frame time and render stats.
## Run with a display (e.g. xvfb-run): godot --path . res://tests/perf_bench.tscn -- --frames 600

var world: World
var gm: GameMode


func _ready() -> void:
	var frames := 600
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--frames":
			frames = int(args[i + 1])
	Net.mode = Net.Mode.HOST
	Net.port = 28500 + randi() % 1000
	Net.player_name = "Bench"
	Net.team_fill = GameData.TEAM_SIZE
	Settings.set_value("general", "seen_help", true)
	world = load("res://scenes/world.tscn").instantiate()
	add_child(world)
	gm = world.game_mode
	for i in 120:
		await get_tree().process_frame
	var me := world.local_player()
	var origin := Vector3(0, 0, GameData.SPAWN_Z * GameData.team_sign(me.team) + 10.0 * GameData.team_sign(me.team))
	_put(me, origin)
	me.rotation.y = 0.0 if GameData.team_sign(me.team) > 0 else PI  # look toward the middle
	var k := 0
	var spots := {}
	for p in world.get_players():
		if p == me:
			continue
		var brain := p.get_node_or_null("Brain")
		if brain:
			brain.process_mode = Node.PROCESS_MODE_DISABLED
		var row := k / 10
		var col := k % 10
		_put(p, origin + Vector3((col - 4.5) * 4.0, 0, (-8.0 - row * 5.0) * GameData.team_sign(me.team)))
		p.rotation.y = randf() * TAU
		p.move_input = Vector2.ZERO
		spots[p] = p.position
		k += 1
	if "--no-anim" in args:
		for p in world.get_players():
			if p._look:
				p._look.anim.active = false
				p._look._hold.active = false
	if "--no-players" in args:
		for p in world.get_players():
			if p != me:
				p.visible = false
	if "--no-labels" in args:
		for l in world.find_children("*", "Label3D", true, false):
			l.visible = false
	if "--no-minimap" in args:
		for n in world.find_children("*", "Minimap", true, false):
			n.process_mode = Node.PROCESS_MODE_DISABLED
	if "--no-hud" in args and world.hud:
		world.hud.process_mode = Node.PROCESS_MODE_DISABLED
	for i in 60:
		await get_tree().process_frame
	var t0 := Time.get_ticks_usec()
	var proc := 0.0
	var phys := 0.0
	var draws := 0.0
	var prims := 0.0
	var worst := 0
	var last := t0
	for i in frames:
		for p: Player in spots:
			p.position = spots[p]  # hold the crowd in view
			p.rotation.y += 0.02
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		worst = maxi(worst, now - last)
		last = now
		proc += Performance.get_monitor(Performance.TIME_PROCESS)
		phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	var total := (Time.get_ticks_usec() - t0) / 1000.0 / frames
	print("BENCH players=%d frame=%.2fms (%.0f fps) worst=%.1fms process=%.2fms physics=%.2fms draw_calls=%.0f primitives=%.0fk" % [
		world.get_players().size(), total, 1000.0 / total, worst / 1000.0, proc / frames * 1000.0, phys / frames * 1000.0,
		draws / frames, prims / frames / 1000.0])
	var shot := args.find("--shot")
	if shot != -1 and DisplayServer.get_name() != "headless":
		get_viewport().get_texture().get_image().save_png(args[shot + 1])
	get_tree().quit()


func _put(p: Player, pos: Vector3) -> void:
	pos.y = Terrain.height(pos.x, pos.z) + 0.2
	p.teleport(pos)
	var rec: PlayerRecord = gm.records.get(p.peer_id)
	if rec:
		rec.last_valid_pos = pos
		rec.last_move_check = gm.clock
