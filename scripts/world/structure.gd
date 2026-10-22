class_name Structure
extends StaticBody3D
## One placed building piece: wall, door, floor, stairs, roof, ladder, trap or turret.
## Spawned by the server through StructureSpawner at a BuildGrid slot. Health lives on
## the server (clients get a fraction for the damage bar). Turrets and traps run on the
## server only.

const ROOF_RISE := 2.0

var uid := 0
var item_id := ""
var team := 0
var owner_peer := 0
var kind := ""
var slot: Dictionary = {}
var slot_key := ""
var health := 100.0
var max_health := 100.0
## Local bounds of the whole piece (origin at its base).
var bounds := AABB()

var _solid: Array = []  ## [Transform3D local, Vector3 half extents]
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
	slot = BuildGrid.sanitize(data["slot"])
	kind = BuildGrid.kind_of(item_id)
	slot_key = BuildGrid.key(kind, slot)
	name = "S%d" % uid
	transform = BuildGrid.transform_for(kind, slot)
	var def := GameData.item(item_id)
	max_health = def["health"]
	health = max_health
	_turret = def.get("turret", {})
	_trap = def.get("trap", {})


func is_door() -> bool:
	return kind == "door"


func is_ladder() -> bool:
	return kind == "ladder"


func is_trap() -> bool:
	return not _trap.is_empty()


func _enter_tree() -> void:
	var world := _world()
	if world:
		world.register_piece(self)


func _exit_tree() -> void:
	var world := _world()
	if world:
		world.unregister_piece(self)
	if not Net.is_dedicated() and is_queued_for_deletion() and world:
		Sfx.play_at("break", global_position + Vector3(0, 1, 0))
		world.debris(global_position + Vector3(0, 1.0, 0), GameData.item(item_id).get("color", Color.GRAY), 6)


func _world() -> World:
	return get_parent().get_parent() as World if get_parent() else null


func _ready() -> void:
	add_to_group("structures")
	_game_mode = get_tree().get_first_node_in_group("game_mode") as GameMode
	collision_mask = 0
	if is_trap() or is_ladder():
		collision_layer = 0  # walk through / climb
	elif is_door():
		collision_layer = GameData.gate_layer(team)  # only enemies collide
	else:
		collision_layer = 4  # layer 3: structures
	var first := true
	for b: Dictionary in piece_boxes(item_id, team):
		var xf: Transform3D = b["xf"]
		var size: Vector3 = b["size"]
		var box_bounds := xf * AABB(-size * 0.5, size)
		bounds = box_bounds if first else bounds.merge(box_bounds)
		first = false
		if b["solid"]:
			_solid.append([xf, size * 0.5])
			var shape := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = size
			shape.shape = bs
			shape.transform = xf
			add_child(shape)
		if b["visual"] and not Net.is_dedicated():
			var mi := Visuals.box(size, b["color"])
			mi.transform = xf
			add_child(mi)
	set_physics_process(not _turret.is_empty() or is_trap())
	set_process(false)
	if not Net.is_dedicated() and _game_mode and _game_mode.clock > 1.0:
		Sfx.play_at("build", global_position)


# --- Shape definitions (shared with the placement ghost) ------------------------------

## Boxes that make up a piece: {xf, size, color, solid, visual}. Origin is the base center.
static func piece_boxes(id: String, team: int) -> Array:
	var def := GameData.item(id)
	var c: Color = def.get("color", Color.GRAY)
	var tc := GameData.team_color(team)
	var out := []
	var t: float = def.get("thickness", 0.4)
	match def.get("piece", ""):
		"wall":
			if def.get("slit", false):
				_box(out, Vector3(3.9, 1.2, t), Vector3(0, 0.6, 0), c)
				_box(out, Vector3(3.9, 1.1, t), Vector3(0, 2.45, 0), c)
				_box(out, Vector3(1.4, 0.7, t), Vector3(-1.25, 1.55, 0), c)
				_box(out, Vector3(1.4, 0.7, t), Vector3(1.25, 1.55, 0), c)
			else:
				_box(out, Vector3(3.9, 3.0, t), Vector3(0, 1.5, 0), c)
			_box(out, Vector3(3.94, 0.16, t + 0.04), Vector3(0, 2.75, 0), tc, false)
		"door":
			_box(out, Vector3(3.9, 3.0, t), Vector3(0, 1.5, 0), c, true, false)
			for x in [-1.75, 1.75]:
				_box(out, Vector3(0.4, 3.2, t + 0.15), Vector3(x, 1.6, 0), c.darkened(0.25), false)
			for k in 5:
				_box(out, Vector3(0.2, 2.7, t * 0.6), Vector3(-1.1 + k * 0.55, 1.35, 0), c, false)
			_box(out, Vector3(3.9, 0.25, t * 0.8), Vector3(0, 2.6, 0), tc, false)
		"floor":
			_box(out, Vector3(3.98, 0.25, 3.98), Vector3(0, -0.125, 0), c)
			_box(out, Vector3(4.0, 0.05, 0.25), Vector3(0, -0.02, 1.85), tc, false)
		"stairs":
			var pitch := atan2(BuildGrid.LEVEL, BuildGrid.CELL)
			_box(out, Vector3(3.6, 0.25, Vector2(BuildGrid.CELL, BuildGrid.LEVEL).length()),
				Vector3(0, BuildGrid.LEVEL * 0.5, 0), c, true, false, Basis(Vector3.RIGHT, pitch))
			var steps := 6
			var depth := BuildGrid.CELL / steps
			for k in steps:
				var top := BuildGrid.LEVEL * (k + 1) / steps
				_box(out, Vector3(3.6, top, depth), Vector3(0, top * 0.5, BuildGrid.CELL * 0.5 - depth * (k + 0.5)), c.lightened(0.04 * (k % 2)), false)
			_box(out, Vector3(0.15, 0.15, 0.15), Vector3(1.8, BuildGrid.LEVEL, -1.9), tc, false)
		"roof":
			var pitch := atan2(ROOF_RISE, BuildGrid.CELL)
			_box(out, Vector3(4.0, 0.2, Vector2(BuildGrid.CELL, ROOF_RISE).length()),
				Vector3(0, ROOF_RISE * 0.5, 0), c, true, true, Basis(Vector3.RIGHT, pitch))
		"ladder":
			for x in [-0.45, 0.45]:
				_box(out, Vector3(0.09, 3.2, 0.09), Vector3(x, 1.6, 0), c, false)
			for k in 8:
				_box(out, Vector3(0.9, 0.06, 0.06), Vector3(0, 0.3 + k * 0.38, 0), c.darkened(0.15), false)
			_box(out, Vector3(0.95, 0.08, 0.1), Vector3(0, 0.1, 0), tc, false)
		"free":
			if def.has("trap"):
				_box(out, Vector3(2.0, 0.08, 2.0), Vector3(0, 0.04, 0), c.darkened(0.3), false)
				for x in 4:
					for z in 4:
						_box(out, Vector3(0.1, 0.3, 0.1), Vector3((x - 1.5) * 0.5, 0.2, (z - 1.5) * 0.5), c, false)
				_box(out, Vector3(2.0, 0.1, 0.1), Vector3(0, 0.05, 1.0), tc, false)
			else:
				_box(out, Vector3(1.6, 1.6, 1.6), Vector3(0, 0.8, 0), c)
				_box(out, Vector3(1.64, 0.15, 1.64), Vector3(0, 1.3, 0), tc, false)
				_box(out, Vector3(2.2, 0.15, 0.2), Vector3(0, 1.8, -0.3), Color(0.3, 0.2, 0.1), false)
				_box(out, Vector3(0.15, 0.15, 1.6), Vector3(0, 1.8, 0), Color(0.3, 0.2, 0.1), false)
	return out


static func _box(out: Array, size: Vector3, pos: Vector3, color: Color, solid := true, visual := true, basis := Basis()) -> void:
	out.append({"xf": Transform3D(basis, pos), "size": size, "color": color, "solid": solid, "visual": visual})


## A see-through copy of a piece for previewing placement.
static func make_ghost(id: String, team: int, material: Material) -> Node3D:
	var root := Node3D.new()
	for b: Dictionary in piece_boxes(id, team):
		var mi := Visuals.box(b["size"], Color.WHITE)
		mi.transform = b["xf"]
		mi.material_override = material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	return root


static func local_bounds(id: String) -> AABB:
	var result := AABB()
	var first := true
	for b: Dictionary in piece_boxes(id, 0):
		var size: Vector3 = b["size"]
		var bb: AABB = (b["xf"] as Transform3D) * AABB(-size * 0.5, size)
		result = bb if first else result.merge(bb)
		first = false
	return result


# --- Server logic ----------------------------------------------------------------------

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


func top() -> Vector3:
	return global_position + Vector3(0, bounds.end.y, 0)


## Closest point on this piece's footprint to p, at p's height clamped to the piece.
func closest_point(p: Vector3) -> Vector3:
	var local := global_transform.affine_inverse() * p
	var clamped := local.clamp(bounds.position, bounds.end)
	return global_transform * clamped


## Horizontal distance from p to the piece's footprint.
func distance_to_point(p: Vector3) -> float:
	return GameData.flat_distance(closest_point(p), p)


## World-space height range of the piece.
func y_range() -> Vector2:
	return Vector2(global_position.y + bounds.position.y, global_position.y + bounds.end.y)


## True if p is inside any solid part (used for arrows and fireballs).
func blocks_point(p: Vector3) -> bool:
	var local := global_transform.affine_inverse() * p
	for entry: Array in _solid:
		var lp: Vector3 = (entry[0] as Transform3D).affine_inverse() * local
		var half: Vector3 = entry[1]
		if absf(lp.x) <= half.x and absf(lp.y) <= half.y and absf(lp.z) <= half.z:
			return true
	return false


## Is a climber standing at p on this ladder?
func ladder_contains(p: Vector3) -> bool:
	var local := global_transform.affine_inverse() * p
	return absf(local.x) < 0.7 and local.z > -0.35 and local.z < 1.0 and local.y > -0.6 and local.y < BuildGrid.LEVEL + 0.25


# --- Client feedback ---------------------------------------------------------------------

## Shows a damage bar over the piece (client side).
func set_health_fraction(frac: float) -> void:
	if Net.is_dedicated():
		return
	if _health_bar == null:
		_health_bar = Node3D.new()
		_health_bar.position.y = bounds.end.y + 0.5
		add_child(_health_bar)
		_health_bar.add_child(Visuals.box(Vector3(2.0, 0.18, 0.05), Color(0.1, 0.1, 0.1)))
		_health_fill = Visuals.box(Vector3(1.0, 0.14, 0.06), Color(0.85, 0.25, 0.2))
		_health_bar.add_child(_health_fill)
		set_process(true)
	frac = clampf(frac, 0.0, 1.0)
	_health_fill.scale.x = maxf(frac * 1.95, 0.01)
	_health_fill.position.x = -0.975 + frac * 0.975
	Sfx.play_at("hit_wood", global_position + Vector3(0, 1, 0))


func _process(_delta: float) -> void:
	# Keep the damage bar facing the camera.
	var cam := get_viewport().get_camera_3d()
	if cam and _health_bar:
		_health_bar.global_rotation = Vector3(0, cam.global_rotation.y, 0)
