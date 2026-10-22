class_name Structure
extends StaticBody3D
## A player-built wall or defense. Spawned by the server through StructureSpawner;
## health lives on the server only. Turret structures (ballista) shoot on the server.

var uid := 0
var item_id := ""
var team := 0
var owner_peer := 0
var health := 100.0
var max_health := 100.0
var size := Vector3.ONE

var _turret: Dictionary = {}
var _cooldown := 0.0
var _game_mode: GameMode


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


func _ready() -> void:
	add_to_group("structures")
	_game_mode = get_tree().get_first_node_in_group("game_mode") as GameMode
	collision_layer = 4  # layer 3: structures
	collision_mask = 0
	var def := GameData.item(item_id)
	var color: Color = def.get("color", Color.GRAY)
	var shape := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	shape.shape = b
	shape.position.y = size.y * 0.5
	add_child(shape)
	add_child(Visuals.box(size, color, Vector3(0, size.y * 0.5, 0)))
	# Team-colored band so you can tell whose wall it is at a glance.
	add_child(Visuals.box(Vector3(size.x + 0.04, 0.2, size.z + 0.04), GameData.team_color(team), Vector3(0, size.y - 0.35, 0)))
	if not _turret.is_empty():
		add_child(Visuals.box(Vector3(2.2, 0.15, 0.2), Color(0.3, 0.2, 0.1), Vector3(0, size.y + 0.2, -0.3)))
		add_child(Visuals.box(Vector3(0.15, 0.15, 1.6), Color(0.3, 0.2, 0.1), Vector3(0, size.y + 0.2, 0)))
	set_physics_process(not _turret.is_empty())


func _physics_process(delta: float) -> void:
	if _game_mode == null or not _game_mode.server_running or _game_mode.match_over:
		return
	_cooldown -= delta
	if _cooldown > 0.0:
		return
	var target := _game_mode.nearest_enemy(global_position, team, _turret["range"])
	if target == null:
		_cooldown = 0.25
		return
	_cooldown = _turret["cooldown"]
	_game_mode.fire_turret(self, target, _turret)


## Closest point on this structure's footprint to p (ignores height).
func closest_point(p: Vector3) -> Vector3:
	var local := global_transform.affine_inverse() * p
	var clamped := Vector3(clampf(local.x, -size.x * 0.5, size.x * 0.5), 0.0, clampf(local.z, -size.z * 0.5, size.z * 0.5))
	return global_transform * clamped


func distance_to_point(p: Vector3) -> float:
	return GameData.flat_distance(closest_point(p), p)
