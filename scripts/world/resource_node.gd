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
			radius = 0.45
			cyl.height = 4.0
			_visual.add_child(Visuals.mesh_instance(_mesh("trunk"), Color(0.42, 0.28, 0.15), Vector3(0, 1.0, 0)))
			_visual.add_child(Visuals.mesh_instance(_mesh("canopy"), Color(0.2, 0.5, 0.22), Vector3(0, 3.2, 0)))
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
	visible = alive
	if _shape:
		_shape.set_deferred("disabled", not alive)
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


static func _mesh(kind: String) -> Mesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var m: Mesh
	match kind:
		"trunk":
			var c := CylinderMesh.new()
			c.top_radius = 0.22
			c.bottom_radius = 0.3
			c.height = 2.0
			m = c
		"canopy":
			var c := CylinderMesh.new()
			c.top_radius = 0.0
			c.bottom_radius = 1.4
			c.height = 3.2
			c.radial_segments = 8
			m = c
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
