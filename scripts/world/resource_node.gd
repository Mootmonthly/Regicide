class_name ResourceNode
extends StaticBody3D
## A tree, rock, iron vein or magic crystal. Created identically on every peer by the
## MapGenerator; the server owns `amount` and broadcasts changes by index.

static var _meshes: Dictionary = {}

var index := 0
var res_type := "wood"
var amount := 0
var max_amount := 0
var radius := 0.6
## Trees: total height in meters (real-tree sized, 12-20 m).
var tree_height := 0.0

var _visual: Node3D
var _shape: CollisionShape3D


func setup(p_index: int, p_type: String, pos: Vector3) -> void:
	index = p_index
	res_type = p_type
	name = "R%d" % p_index
	position = pos
	rotation.y = fmod(p_index * 2.39996, TAU)
	max_amount = GameData.RESOURCES[p_type]["node_amount"]
	amount = max_amount


func _ready() -> void:
	collision_layer = 8  # layer 4: resources
	collision_mask = 0
	_visual = Node3D.new()
	add_child(_visual)
	_shape = CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	match res_type:
		"wood":
			# Trees are drawn in batches by World (MultiMesh); this node is just the
			# trunk collider and the gameplay state.
			tree_height = tree_size(index)
			radius = 0.45 * tree_height / 16.0
			cyl.height = tree_height
		"stone":
			radius = 1.0
			cyl.height = 1.4
			_visual.add_child(Visuals.mesh_instance(_mesh("rock"), Color(0.55, 0.55, 0.57), Vector3(0, 0.55, 0)))
		"iron":
			radius = 0.9
			cyl.height = 1.4
			_visual.add_child(Visuals.mesh_instance(_mesh("rock"), Color(0.32, 0.3, 0.3), Vector3(0, 0.55, 0)))
			_visual.add_child(Visuals.mesh_instance(_mesh("vein"), Color(0.75, 0.42, 0.2), Vector3(0.2, 0.9, 0.1)))
		"magic_ore":
			radius = 0.7
			cyl.height = 2.2
			_visual.add_child(Visuals.mesh_instance(_mesh("crystal"), Color(0.6, 0.25, 0.95), Vector3(0, 1.1, 0), 1.5))
	cyl.radius = radius
	_shape.shape = cyl
	_shape.position.y = cyl.height * 0.5
	add_child(_shape)
	set_amount(amount)


func set_amount(value: int) -> void:
	var old := amount
	amount = clampi(value, 0, max_amount)
	if amount < old and is_inside_tree() and not Net.is_dedicated():
		_hit_feedback()
	var alive := amount > 0
	if _shape:
		_shape.set_deferred("disabled", not alive)
	if res_type == "wood":
		# Trees stay full size until felled, then leave a stump.
		var world := get_parent().get_parent() as World if get_parent() else null
		if world:
			world.set_tree_standing(index, alive)
	else:
		visible = alive
		if _visual and max_amount > 0:
			_visual.scale = Vector3.ONE * lerpf(0.6, 1.0, float(amount) / max_amount)


func _hit_feedback() -> void:
	var colors := {"wood": Color(0.5, 0.34, 0.18), "stone": Color(0.55, 0.55, 0.57), "iron": Color(0.75, 0.42, 0.2), "magic_ore": Color(0.7, 0.35, 1.0)}
	var world := get_parent().get_parent() as World
	if world:
		world.debris(global_position + Vector3(0, 1.0, 0), colors.get(res_type, Color.GRAY))
	Sfx.play_at("chop" if res_type == "wood" else "mine", global_position, -3.0)
	# Wobble.
	if _visual:
		var t := create_tween()
		t.tween_property(_visual, "rotation:z", 0.08, 0.05)
		t.tween_property(_visual, "rotation:z", 0.0, 0.12)


## Tree height (12-20 m), deterministic from the node index.
static func tree_size(i: int) -> float:
	return lerpf(12.0, 20.0, fmod(absf(sin(i * 91.17) * 4375.85), 1.0))


static func is_oak(i: int) -> bool:
	return fmod(absf(sin(i * 13.31) * 9123.4), 1.0) < 0.3


## The pieces a tree is drawn from: [mesh key, color, local transform], plus its stump.
static func tree_parts(i: int) -> Dictionary:
	var sc := tree_size(i) / 16.0
	var bark := Color(0.4, 0.27, 0.15)
	var parts := []
	if is_oak(i):
		var leaf := Color(0.27, 0.5, 0.2)
		parts.append(["oak_trunk", bark, Vector3(0, 5.5, 0)])
		parts.append(["oak_crown", leaf, Vector3(0, 11.5, 0)])
		parts.append(["oak_lobe", leaf.darkened(0.08), Vector3(2.4, 10.0, 0.8)])
		parts.append(["oak_lobe", leaf.lightened(0.05), Vector3(-1.8, 10.6, -1.6)])
	else:
		var needle := Color(0.16, 0.42, 0.22)
		parts.append(["pine_trunk", bark, Vector3(0, 8.0, 0)])
		parts.append(["pine_low", needle, Vector3(0, 6.5, 0)])
		parts.append(["pine_mid", needle.lightened(0.04), Vector3(0, 10.0, 0)])
		parts.append(["pine_top", needle.lightened(0.08), Vector3(0, 13.5, 0)])
	var out := []
	for p: Array in parts:
		out.append([p[0], p[1], Transform3D(Basis().scaled(Vector3.ONE * sc), (p[2] as Vector3) * sc)])
	return {"parts": out, "stump": ["stump", bark.darkened(0.1), Transform3D(Basis().scaled(Vector3.ONE * sc), Vector3(0, 0.35 * sc, 0))]}


static func mesh_for(kind: String) -> Mesh:
	return _mesh(kind)


static func _mesh(kind: String) -> Mesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var m: Mesh
	match kind:
		# Meshes are sized for a 16 m tree and scaled per tree.
		"pine_trunk":
			m = _cyl(0.18, 0.42, 16.0, 8)
		"pine_low":
			m = _cyl(0.0, 3.4, 6.5, 9)
		"pine_mid":
			m = _cyl(0.0, 2.6, 5.5, 9)
		"pine_top":
			m = _cyl(0.0, 1.6, 4.5, 8)
		"oak_trunk":
			m = _cyl(0.3, 0.55, 11.0, 8)
		"oak_crown":
			var sp := SphereMesh.new()
			sp.radius = 4.2
			sp.height = 7.0
			sp.radial_segments = 10
			sp.rings = 6
			m = sp
		"oak_lobe":
			var sp := SphereMesh.new()
			sp.radius = 2.6
			sp.height = 4.4
			sp.radial_segments = 8
			sp.rings = 5
			m = sp
		"stump":
			m = _cyl(0.4, 0.48, 0.7, 8)
		"rock":
			var s := SphereMesh.new()
			s.radius = 1.0
			s.height = 1.3
			s.radial_segments = 7
			s.rings = 4
			m = s
		"vein":
			var b := BoxMesh.new()
			b.size = Vector3(0.6, 0.3, 0.5)
			m = b
		"crystal":
			var p := PrismMesh.new()
			p.size = Vector3(0.9, 2.2, 0.9)
			m = p
	_meshes[kind] = m
	return m


static func _cyl(top: float, bottom: float, h: float, segments: int) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = segments
	return c
