class_name Structure
extends StaticBody3D
## One placed building piece: walls (full, half, window, slit, battlement), doors,
## drawbridges, floors, stairs, roofs, ladders, traps, ballistas, catapults and
## battering rams. Spawned by the server through StructureSpawner at a BuildGrid slot.
## Health lives on the server (clients get a fraction for the damage bar). Turrets,
## traps and rams run on the server only.
##
## Pieces with moving parts (drawbridge leaf, catapult arm) put those boxes in a "leaf"
## node, which rotates; its collision moves with it.

const ROOF_RISE := 2.0
const DRAWBRIDGE_LENGTH := 6.0
const POSE_INTERVAL := 0.1

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
## Drawbridge state: lowered (bridge) or raised (wall).
var opened := false

var _solid: Array = []  ## [Node3D holder, Transform3D local, Vector3 half extents]
var _leaf: Node3D
var _turret: Dictionary = {}
var _trap: Dictionary = {}
var _ram: Dictionary = {}
var _catapult: Dictionary = {}
var _cooldown := 0.0
var _game_mode: GameMode
var _health_bar: Node3D
var _health_fill: MeshInstance3D
var _pose_timer := 0.0
var _target_pos := Vector3.ZERO
var _target_yaw := 0.0
var _has_target := false
var _leaf_tween: Tween
## Seconds until a summoned piece (Earth Wall) crumbles; 0 = permanent.
var lifetime := 0.0


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
	if kind == "vehicle":
		position.y = Terrain.height(position.x, position.z)
	var def := GameData.item(item_id)
	max_health = def["health"]
	health = max_health
	_turret = def.get("turret", {})
	_trap = def.get("trap", {})
	_ram = def.get("ram", {})
	_catapult = def.get("catapult", {})
	lifetime = data.get("lifetime", 0.0)


func is_door() -> bool:
	return kind == "door"


func is_ladder() -> bool:
	return kind == "ladder"


func is_trap() -> bool:
	return not _trap.is_empty()


func is_vehicle() -> bool:
	return kind == "vehicle"


func is_catapult() -> bool:
	return not _catapult.is_empty()


func is_drawbridge() -> bool:
	return kind == "drawbridge"


## Can a teammate use this with the interact key?
func is_interactable() -> bool:
	return is_drawbridge() or is_catapult()


func catapult_config() -> Dictionary:
	return _catapult


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
		var holder: Node3D = self
		if b.get("leaf", false):
			if _leaf == null:
				_leaf = Node3D.new()
				_leaf.name = "Leaf"
				_leaf.position = b.get("pivot", Vector3.ZERO)
				add_child(_leaf)
			holder = _leaf
		var xf: Transform3D = b["xf"]
		var size: Vector3 = b["size"]
		var box_bounds := (holder.transform * xf if holder != self else xf) * AABB(-size * 0.5, size)
		bounds = box_bounds if first else bounds.merge(box_bounds)
		first = false
		if b["solid"]:
			_solid.append([holder, xf, size * 0.5])
			var shape := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = size
			shape.shape = bs
			shape.transform = xf
			holder.add_child(shape)
		if b["visual"] and not Net.is_dedicated():
			var mi := Visuals.box(size, b["color"])
			mi.transform = xf
			holder.add_child(mi)
	set_physics_process(not _turret.is_empty() or is_trap() or is_vehicle())
	set_process(is_vehicle() and not Net.is_dedicated())
	var world := _world()
	if world and world.pending_piece_states.has(String(name)):
		apply_state(world.pending_piece_states[String(name)])
		world.pending_piece_states.erase(String(name))
	if not Net.is_dedicated() and _game_mode and _game_mode.clock > 1.0:
		Sfx.play_at("build", global_position)
	if lifetime > 0.0:
		# Summoned: rise out of the ground, crumble when time's up (server decides).
		if not Net.is_dedicated():
			scale.y = 0.05
			create_tween().tween_property(self, "scale:y", 1.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if _game_mode and _game_mode.server_running:
			get_tree().create_timer(lifetime, false, true).timeout.connect(func() -> void:
				if is_instance_valid(self):
					_game_mode.expire_structure(self))


# --- Shape definitions (shared with the placement ghost) ------------------------------

## Boxes that make up a piece: {xf, size, color, solid, visual[, leaf, pivot]}.
## Origin is the base center; local -Z is the piece's front.
static func piece_boxes(id: String, team: int) -> Array:
	var def := GameData.item(id)
	var c: Color = def.get("color", Color.GRAY)
	var tc := GameData.team_color(team)
	var out := []
	var t: float = def.get("thickness", 0.4)
	var dark := Color(0.28, 0.2, 0.12)
	match def.get("piece", ""):
		"wall":
			if def.get("slit", false):
				_box(out, Vector3(3.9, 1.2, t), Vector3(0, 0.6, 0), c)
				_box(out, Vector3(3.9, 1.1, t), Vector3(0, 2.45, 0), c)
				_box(out, Vector3(1.4, 0.7, t), Vector3(-1.25, 1.55, 0), c)
				_box(out, Vector3(1.4, 0.7, t), Vector3(1.25, 1.55, 0), c)
			elif def.get("window", false):
				_box(out, Vector3(3.9, 1.0, t), Vector3(0, 0.5, 0), c)
				_box(out, Vector3(3.9, 0.8, t), Vector3(0, 2.6, 0), c)
				_box(out, Vector3(1.25, 1.2, t), Vector3(-1.325, 1.6, 0), c)
				_box(out, Vector3(1.25, 1.2, t), Vector3(1.325, 1.6, 0), c)
				_box(out, Vector3(1.4, 0.06, 0.06), Vector3(0, 1.6, 0), dark, false)
				_box(out, Vector3(0.06, 1.2, 0.06), Vector3(0, 1.6, 0), dark, false)
			else:
				_box(out, Vector3(3.9, 3.0, t), Vector3(0, 1.5, 0), c)
			_box(out, Vector3(3.94, 0.16, t + 0.04), Vector3(0, 2.75, 0), tc, false)
		"half":
			if def.get("battlement", false):
				_box(out, Vector3(3.9, 1.0, t), Vector3(0, 0.5, 0), c)
				for x in [-1.5, 0.0, 1.5]:
					_box(out, Vector3(0.9, 0.8, t), Vector3(x, 1.4, 0), c)
				_box(out, Vector3(3.94, 0.12, t + 0.04), Vector3(0, 0.95, 0), tc, false)
			else:
				_box(out, Vector3(3.9, 1.5, t), Vector3(0, 0.75, 0), c)
				_box(out, Vector3(3.94, 0.12, t + 0.04), Vector3(0, 1.38, 0), tc, false)
		"door":
			_box(out, Vector3(3.9, 3.0, t), Vector3(0, 1.5, 0), c, true, false)
			for x in [-1.75, 1.75]:
				_box(out, Vector3(0.4, 3.2, t + 0.15), Vector3(x, 1.6, 0), c.darkened(0.25), false)
			for k in 5:
				_box(out, Vector3(0.2, 2.7, t * 0.6), Vector3(-1.1 + k * 0.55, 1.35, 0), c, false)
			_box(out, Vector3(3.9, 0.25, t * 0.8), Vector3(0, 2.6, 0), tc, false)
		"drawbridge":
			# Side posts stay put; the plank is the leaf, hinged at the base.
			for x in [-1.85, 1.85]:
				_box(out, Vector3(0.3, DRAWBRIDGE_LENGTH + 0.4, 0.5), Vector3(x, (DRAWBRIDGE_LENGTH + 0.4) * 0.5, 0), c.darkened(0.3))
			var leaf := {"leaf": true}
			_box(out, Vector3(3.4, DRAWBRIDGE_LENGTH, 0.35), Vector3(0, DRAWBRIDGE_LENGTH * 0.5, 0), c, true, true, Basis(), leaf)
			for k in 4:
				_box(out, Vector3(3.42, 0.12, 0.37), Vector3(0, 0.5 + k * 1.0, 0), c.darkened(0.2), false, true, Basis(), leaf)
			_box(out, Vector3(3.44, 0.2, 0.38), Vector3(0, DRAWBRIDGE_LENGTH - 0.3, 0), tc, false, true, Basis(), leaf)
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
		"vehicle":
			_box(out, Vector3(2.0, 1.3, 4.2), Vector3(0, 0.95, 0), c, true, false)
			_box(out, Vector3(2.0, 0.25, 4.2), Vector3(0, 0.45, 0), c)
			for side in [-1.0, 1.0]:
				_box(out, Vector3(0.15, 1.9, 4.2), Vector3(side * 0.62, 1.55, 0), c.darkened(0.15), false, true, Basis(Vector3.BACK, side * 0.6))
				for z in [-1.4, 1.4]:
					_box(out, Vector3(0.25, 0.8, 0.8), Vector3(side * 1.1, 0.4, z), dark, false)
			_box(out, Vector3(0.45, 0.45, 4.8), Vector3(0, 1.0, -0.4), Color(0.35, 0.24, 0.13), false)
			_box(out, Vector3(0.65, 0.65, 0.5), Vector3(0, 1.0, -2.85), Color(0.35, 0.35, 0.38), false)
			_box(out, Vector3(2.04, 0.15, 0.5), Vector3(0, 2.2, 0), tc, false)
		"free":
			if def.has("trap"):
				_box(out, Vector3(2.0, 0.08, 2.0), Vector3(0, 0.04, 0), c.darkened(0.3), false)
				for x in 4:
					for z in 4:
						_box(out, Vector3(0.1, 0.3, 0.1), Vector3((x - 1.5) * 0.5, 0.2, (z - 1.5) * 0.5), c, false)
				_box(out, Vector3(2.0, 0.1, 0.1), Vector3(0, 0.05, 1.0), tc, false)
			elif def.has("catapult"):
				_box(out, Vector3(2.4, 0.7, 3.0), Vector3(0, 0.35, 0), c)
				for x in [-0.9, 0.9]:
					_box(out, Vector3(0.25, 1.8, 0.25), Vector3(x, 1.5, 0.3), c.darkened(0.2), false)
				_box(out, Vector3(2.0, 0.2, 0.2), Vector3(0, 2.3, 0.3), c.darkened(0.2), false)
				var arm := {"leaf": true, "pivot": Vector3(0, 1.2, 0.3)}
				_box(out, Vector3(0.22, 0.22, 3.4), Vector3(0, 0, 0.6), dark, false, true, Basis(), arm)
				_box(out, Vector3(0.75, 0.3, 0.75), Vector3(0, 0.1, 2.2), dark, false, true, Basis(), arm)
				_box(out, Vector3(0.5, 0.5, 0.5), Vector3(0, 0.4, 2.2), Color(0.55, 0.55, 0.57), false, true, Basis(), arm)
				_box(out, Vector3(2.44, 0.12, 0.3), Vector3(0, 0.7, -1.4), tc, false)
			else:
				_box(out, Vector3(1.6, 1.6, 1.6), Vector3(0, 0.8, 0), c)
				_box(out, Vector3(1.64, 0.15, 1.64), Vector3(0, 1.3, 0), tc, false)
				_box(out, Vector3(2.2, 0.15, 0.2), Vector3(0, 1.8, -0.3), Color(0.3, 0.2, 0.1), false)
				_box(out, Vector3(0.15, 0.15, 1.6), Vector3(0, 1.8, 0), Color(0.3, 0.2, 0.1), false)
	return out


static func _box(out: Array, size: Vector3, pos: Vector3, color: Color, solid := true, visual := true, basis := Basis(), extra := {}) -> void:
	var b := {"xf": Transform3D(basis, pos), "size": size, "color": color, "solid": solid, "visual": visual}
	b.merge(extra)
	out.append(b)


## A see-through copy of a piece for previewing placement.
static func make_ghost(id: String, team: int, material: Material) -> Node3D:
	var root := Node3D.new()
	for b: Dictionary in piece_boxes(id, team):
		var mi := Visuals.box(b["size"], Color.WHITE)
		mi.transform = b["xf"]
		if b.get("leaf", false):
			mi.transform = Transform3D(Basis(), b.get("pivot", Vector3.ZERO)) * mi.transform
		mi.material_override = material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	return root


static func local_bounds(id: String) -> AABB:
	var result := AABB()
	var first := true
	for b: Dictionary in piece_boxes(id, 0):
		var size: Vector3 = b["size"]
		var xf: Transform3D = b["xf"]
		if b.get("leaf", false):
			xf = Transform3D(Basis(), b.get("pivot", Vector3.ZERO)) * xf
		var bb: AABB = xf * AABB(-size * 0.5, size)
		result = bb if first else result.merge(bb)
		first = false
	return result


# --- State (drawbridge position, vehicle pose) -----------------------------------------

## Non-default state, for late joiners.
func get_state() -> Dictionary:
	if is_drawbridge() and opened:
		return {"open": true}
	if is_vehicle():
		return {"pos": position, "yaw": rotation.y}
	return {}


func apply_state(state: Dictionary) -> void:
	if state.has("open"):
		set_open(state["open"], false)
	if state.has("pos"):
		position = state["pos"]
		rotation.y = state["yaw"]
		_target_pos = position
		_target_yaw = rotation.y


## Lower (open) or raise the drawbridge. It falls toward its slot's side.
func set_open(value: bool, animate := true) -> void:
	opened = value
	if _leaf == null:
		return
	var angle: float = (PI * 0.5 * slot["side"]) if value else 0.0
	if _leaf_tween:
		_leaf_tween.kill()
	if animate and not Net.is_dedicated():
		_leaf_tween = create_tween()
		_leaf_tween.tween_property(_leaf, "rotation:x", angle, 1.2).set_trans(Tween.TRANS_BOUNCE if value else Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		Sfx.play_at("drawbridge", global_position + Vector3(0, 1, 0))
	else:
		_leaf.rotation.x = angle


## Swing the catapult arm (cosmetic).
func play_fire() -> void:
	if _leaf == null or Net.is_dedicated():
		return
	if _leaf_tween:
		_leaf_tween.kill()
	_leaf_tween = create_tween()
	_leaf_tween.tween_property(_leaf, "rotation:x", -1.6, 0.18).set_ease(Tween.EASE_OUT)
	_leaf_tween.tween_property(_leaf, "rotation:x", 0.0, 1.5).set_trans(Tween.TRANS_SINE)


## Clients: where the server says this vehicle is.
func set_pose_target(pos: Vector3, yaw: float) -> void:
	_target_pos = pos
	_target_yaw = yaw
	_has_target = true


# --- Server logic ----------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _game_mode == null or not _game_mode.server_running or _game_mode.match_over:
		return
	if is_vehicle():
		_drive(delta)
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


## Battering ram: teammates pushing from behind roll it forward and steer it toward the
## way they face; whatever enemy structure it runs into gets battered.
func _drive(delta: float) -> void:
	_cooldown -= delta
	var pushers := 0
	var steer := 0.0
	for p in _game_mode.world.get_players():
		if p.team != team or not p.alive:
			continue
		var local := global_transform.affine_inverse() * p.sync_pos
		if local.z > 1.6 and local.z < 4.2 and absf(local.x) < 1.6 and absf(local.y) < 2.0:
			var diff := angle_difference(rotation.y, p.sync_yaw)
			if absf(diff) < 1.2:
				pushers += 1
				steer += diff
	if pushers == 0:
		return
	rotation.y += clampf(steer / pushers, -1.0, 1.0) * float(_ram["turn_rate"]) * delta
	var forward := -global_basis.z
	var speed: float = _ram["speed"] * (0.6 if pushers == 1 else 1.0)
	var next := position + forward * speed * delta
	next.y = Terrain.height(next.x, next.z)
	var blocker: Structure = _front_blocker(next, forward)
	if blocker != null:
		if blocker.team != team and _cooldown <= 0.0:
			_cooldown = _ram["interval"]
			_game_mode.ram_hit(self, blocker)
	elif blocker == null and GameData.in_bounds(next, 3.0) and next.y > Terrain.WATER_LEVEL - 0.3 \
			and next.y - position.y < 0.6:
		position = next
	_pose_timer -= delta
	if _pose_timer <= 0.0:
		_pose_timer = POSE_INTERVAL
		_game_mode.world.vehicle_pose.rpc(name, position, rotation.y)


## The structure directly in front of the ram at `at`, or null.
func _front_blocker(at: Vector3, forward: Vector3) -> Structure:
	var right := forward.cross(Vector3.UP)
	for side in [-0.8, 0.0, 0.8]:
		var probe: Vector3 = at + forward * 3.0 + right * side + Vector3(0, 1.0, 0)
		for s in _game_mode.world.get_structures():
			if s == self or s.is_trap() or s.is_ladder():
				continue
			if s.blocks_point(probe):
				return s
	return null


func _process(delta: float) -> void:
	# Keep the damage bar facing the camera.
	var cam := get_viewport().get_camera_3d()
	if cam and _health_bar:
		_health_bar.global_rotation = Vector3(0, cam.global_rotation.y, 0)
	if _has_target and is_vehicle():
		var t := clampf(delta * 8.0, 0.0, 1.0)
		position = position.lerp(_target_pos, t)
		rotation.y = lerp_angle(rotation.y, _target_yaw, t)


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


## True if p is inside any solid part (used for arrows, fireballs, boulders and rams).
func blocks_point(p: Vector3) -> bool:
	for entry: Array in _solid:
		var holder: Node3D = entry[0]
		var lp: Vector3 = (holder.global_transform * (entry[1] as Transform3D)).affine_inverse() * p
		var half: Vector3 = entry[2]
		if absf(lp.x) <= half.x and absf(lp.y) <= half.y and absf(lp.z) <= half.z:
			return true
	return false


## Is a climber standing at p on this ladder?
func ladder_contains(p: Vector3) -> bool:
	var local := global_transform.affine_inverse() * p
	return absf(local.x) < 0.7 and local.z > -0.35 and local.z < 1.0 and local.y > -0.6 and local.y < BuildGrid.LEVEL + 0.25


# --- Client feedback ---------------------------------------------------------------------

## Shows a damage bar over the piece (client side). Hidden again at full health.
func set_health_fraction(frac: float) -> void:
	if Net.is_dedicated():
		return
	frac = clampf(frac, 0.0, 1.0)
	if frac >= 0.999:
		if _health_bar:
			_health_bar.visible = false
		return
	if _health_bar == null:
		_health_bar = Node3D.new()
		_health_bar.position.y = bounds.end.y + 0.5
		add_child(_health_bar)
		_health_bar.add_child(Visuals.box(Vector3(2.0, 0.18, 0.05), Color(0.1, 0.1, 0.1)))
		_health_fill = Visuals.box(Vector3(1.0, 0.14, 0.06), Color(0.85, 0.25, 0.2))
		_health_bar.add_child(_health_fill)
		set_process(true)
	_health_bar.visible = true
	_health_fill.scale.x = maxf(frac * 1.95, 0.01)
	_health_fill.position.x = -0.975 + frac * 0.975
	Sfx.play_at("hit_wood", global_position + Vector3(0, 1, 0))
