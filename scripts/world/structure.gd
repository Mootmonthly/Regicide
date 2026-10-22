class_name Structure
extends StaticBody3D
## A player-built wall, gate, trap or turret. Spawned by the server through
## StructureSpawner; health lives on the server (clients get a health fraction for the
## damage bar). Turrets and traps run their logic on the server only.

var uid := 0
var item_id := ""
var team := 0
var owner_peer := 0
var health := 100.0
var max_health := 100.0
var size := Vector3.ONE

var _turret: Dictionary = {}
var _trap: Dictionary = {}
var _cooldown := 0.0
var _game_mode: GameMode
var _health_bar: Node3D
var _health_fill: MeshInstance3D


func setup(data: Dictionary) -> void:
	uid = data["uid"]
	item_id = data["item"]
	team = data["team"]
	owner_peer = data["owner"]
	name = "S%d" % uid
	position = data["pos"]
	rotation.y = data["yaw"]
	var def := GameData.item(item_id)
	size = def["size"]
	max_health = def["health"]
	health = max_health
	_turret = def.get("turret", {})
	_trap = def.get("trap", {})


func is_gate() -> bool:
	return GameData.item(item_id).get("gate", false)


func is_trap() -> bool:
	return not _trap.is_empty()


func _ready() -> void:
	add_to_group("structures")
	_game_mode = get_tree().get_first_node_in_group("game_mode") as GameMode
	collision_mask = 0
	if is_trap():
		collision_layer = 0  # walk over it
	elif is_gate():
		collision_layer = GameData.gate_layer(team)  # only enemies collide
	else:
		collision_layer = 4  # layer 3: structures
	var def := GameData.item(item_id)
	var color: Color = def.get("color", Color.GRAY)
	var tc := GameData.team_color(team)
	var shape := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	shape.shape = b
	shape.position.y = size.y * 0.5
	add_child(shape)

	if is_trap():
		add_child(Visuals.box(Vector3(size.x, 0.08, size.z), color.darkened(0.3), Vector3(0, 0.04, 0)))
		var spike := CylinderMesh.new()
		spike.top_radius = 0.0
		spike.bottom_radius = 0.09
		spike.height = 0.35
		for x in 4:
			for z in 4:
				var pos := Vector3((x - 1.5) * size.x / 4.0, 0.2, (z - 1.5) * size.z / 4.0)
				add_child(Visuals.mesh_instance(spike, color, pos))
		add_child(Visuals.box(Vector3(size.x, 0.1, 0.1), tc, Vector3(0, 0.05, size.z * 0.5)))
	elif is_gate():
		for x in [-size.x * 0.5 + 0.2, size.x * 0.5 - 0.2]:
			add_child(Visuals.box(Vector3(0.4, size.y + 0.4, size.z + 0.2), color.darkened(0.25), Vector3(x, (size.y + 0.4) * 0.5, 0)))
		for i in 5:
			add_child(Visuals.box(Vector3(0.18, size.y - 0.3, size.z * 0.6), color, Vector3(-1.2 + i * 0.6, (size.y - 0.3) * 0.5, 0)))
		add_child(Visuals.box(Vector3(size.x, 0.25, size.z * 0.8), tc, Vector3(0, size.y - 0.4, 0)))
	else:
		add_child(Visuals.box(size, color, Vector3(0, size.y * 0.5, 0)))
		# Team-colored band so you can tell whose wall it is at a glance.
		add_child(Visuals.box(Vector3(size.x + 0.04, 0.2, size.z + 0.04), tc, Vector3(0, size.y - 0.35, 0)))
	if not _turret.is_empty():
		add_child(Visuals.box(Vector3(2.2, 0.15, 0.2), Color(0.3, 0.2, 0.1), Vector3(0, size.y + 0.2, -0.3)))
		add_child(Visuals.box(Vector3(0.15, 0.15, 1.6), Color(0.3, 0.2, 0.1), Vector3(0, size.y + 0.2, 0)))
	set_physics_process(not _turret.is_empty() or is_trap())
	if not Net.is_dedicated() and _game_mode and _game_mode.clock > 1.0:
		Sfx.play_at("build", global_position)


func _exit_tree() -> void:
	if not Net.is_dedicated() and is_queued_for_deletion():
		Sfx.play_at("break", global_position)


func _physics_process(delta: float) -> void:
	if _game_mode == null or not _game_mode.server_running or _game_mode.match_over:
		return
	_cooldown -= delta
	if _cooldown > 0.0:
		return
	if is_trap():
		_cooldown = _trap["interval"]
		_game_mode.trigger_trap(self, _trap)
		return
	var target := _game_mode.nearest_enemy(global_position, team, _turret["range"])
	if target == null:
		_cooldown = 0.25
		return
	_cooldown = _turret["cooldown"]
	_game_mode.fire_turret(self, target, _turret)


## Shows a damage bar over the structure (client side).
func set_health_fraction(frac: float) -> void:
	if Net.is_dedicated():
		return
	if _health_bar == null:
		_health_bar = Node3D.new()
		_health_bar.position.y = size.y + 0.6
		add_child(_health_bar)
		_health_bar.add_child(Visuals.box(Vector3(2.0, 0.18, 0.05), Color(0.1, 0.1, 0.1)))
		_health_fill = Visuals.box(Vector3(1.0, 0.14, 0.06), Color(0.85, 0.25, 0.2))
		_health_bar.add_child(_health_fill)
	frac = clampf(frac, 0.0, 1.0)
	_health_fill.scale.x = maxf(frac * 1.95, 0.01)
	_health_fill.position.x = -0.975 + frac * 0.975
	Sfx.play_at("hit_wood", global_position)


func _process(_delta: float) -> void:
	# Keep the damage bar facing the camera.
	if _health_bar:
		var cam := get_viewport().get_camera_3d()
		if cam:
			_health_bar.global_rotation = Vector3(0, cam.global_rotation.y, 0)


## Closest point on this structure's footprint to p (ignores height).
func closest_point(p: Vector3) -> Vector3:
	var local := global_transform.affine_inverse() * p
	var clamped := Vector3(clampf(local.x, -size.x * 0.5, size.x * 0.5), 0.0, clampf(local.z, -size.z * 0.5, size.z * 0.5))
	return global_transform * clamped


func distance_to_point(p: Vector3) -> float:
	return GameData.flat_distance(closest_point(p), p)
