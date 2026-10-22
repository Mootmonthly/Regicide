class_name Visuals
extends RefCounted
## Tiny helpers for the deliberately simple, primitive-shape art style.

static var _materials: Dictionary = {}


## Shared material per color (and glow), so hundreds of nodes don't each allocate one.
static func mat(color: Color, emission := 0.0) -> StandardMaterial3D:
	var key := "%s|%s" % [color.to_html(), emission]
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	if color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	_materials[key] = m
	return m


static func mesh_instance(mesh: Mesh, color: Color, pos := Vector3.ZERO, emission := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat(color, emission)
	mi.position = pos
	return mi


static func box(size: Vector3, color: Color, pos := Vector3.ZERO) -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = size
	return mesh_instance(m, color, pos)


static func static_box(size: Vector3, color: Color, pos: Vector3, layer := 1) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	body.position = pos
	var shape := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	shape.shape = b
	body.add_child(shape)
	body.add_child(box(size, color))
	return body
