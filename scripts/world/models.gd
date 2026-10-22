class_name Models
extends RefCounted
## Loads 3D models (Kenney CC0 packs under res://assets), measures them once, and
## builds copies scaled to fit a target box - so a 1 m Kenney wall tile can fill a
## 4 x 3 m wall slot, or a 1.5 m tree model can stand 18 m tall.

static var _cache: Dictionary = {}


## {scene, aabb (with rotation applied), meshes: [[Mesh, Transform3D]]} for a model.
static func info(path: String, rot_deg := Vector3.ZERO) -> Dictionary:
	var key := "%s|%s" % [path, rot_deg]
	if _cache.has(key):
		return _cache[key]
	var scene := load(path) as PackedScene
	if scene == null:
		push_warning("Missing model " + path)
		_cache[key] = {}
		return {}
	var root := Node3D.new()
	var inst := scene.instantiate() as Node3D
	inst.rotation_degrees = rot_deg
	root.add_child(inst)
	var aabb := AABB()
	var first := true
	var meshes := []
	for node in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		_fix_materials(mi.mesh, path)
		var xf := _relative_transform(mi, root)
		meshes.append([mi.mesh, xf])
		var b := xf * mi.get_aabb()
		aabb = b if first else aabb.merge(b)
		first = false
	root.free()
	var out := {"scene": scene, "aabb": aabb, "rot": rot_deg, "meshes": meshes}
	_cache[key] = out
	return out


static var _fixed: Dictionary = {}


## Some packs export materials as fully metallic, which makes them mirror the sky
## (teal trees). Make everything matte, and fix Nature Kit's washed-out colors.
static func _fix_materials(mesh: Mesh, path: String) -> void:
	if mesh == null or _fixed.has(mesh):
		return
	_fixed[mesh] = true
	for i in mesh.get_surface_count():
		var m := mesh.surface_get_material(i) as BaseMaterial3D
		if m == null:
			continue
		m.metallic = 0.0
		m.metallic_specular = 0.25
		m.roughness = 1.0
		if path.contains("/nature/") and m.albedo_texture == null:
			m.albedo_color = _natural(m.albedo_color)


## Nature Kit colors are pastel; map them onto an earthier palette, keeping each
## material's brightness so models still read as lit / shaded parts.
static func _natural(c: Color) -> Color:
	var v := clampf(c.v, 0.2, 1.0)
	if c.s < 0.2:  # rocks
		return Color(0.4, 0.4, 0.38) * (0.6 + 0.5 * v)
	if c.g > c.r * 1.3:  # foliage, grass (some are teal)
		return Color(0.16, 0.36, 0.12).lerp(Color(0.3, 0.5, 0.18), c.s) * (0.7 + 0.5 * v)
	if c.r > c.g and c.r > c.b and c.s > 0.15:  # bark, wood, autumn leaves
		if c.s > 0.5:
			return c.srgb_to_linear()  # flowers / autumn: keep, just less washed out
		return Color(0.3, 0.19, 0.11) * (0.6 + 0.6 * v)
	return c.srgb_to_linear()  # rocks, mushrooms, etc.


static func _relative_transform(node: Node3D, root: Node3D) -> Transform3D:
	var xf := Transform3D()
	var n: Node = node
	while n != root and n is Node3D:
		xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


## A node holding `tiles` copies of the model laid out to exactly fill `target`
## (local space). Non-uniform scaling stretches each tile to fit.
static func fitted(path: String, target: AABB, tiles := Vector3i.ONE, rot_deg := Vector3.ZERO) -> Node3D:
	var holder := Node3D.new()
	var m := info(path, rot_deg)
	if m.is_empty():
		return holder
	var src: AABB = m["aabb"]
	var tile_size := Vector3(target.size.x / tiles.x, target.size.y / tiles.y, target.size.z / tiles.z)
	var s := Vector3(tile_size.x / maxf(src.size.x, 0.001), tile_size.y / maxf(src.size.y, 0.001), tile_size.z / maxf(src.size.z, 0.001))
	for tx in tiles.x:
		for ty in tiles.y:
			for tz in tiles.z:
				var inst := (m["scene"] as PackedScene).instantiate() as Node3D
				inst.rotation_degrees = rot_deg
				var tile_origin := target.position + Vector3(tx * tile_size.x, ty * tile_size.y, tz * tile_size.z)
				var pivot := Node3D.new()
				pivot.scale = s
				pivot.position = tile_origin - src.position * s
				pivot.add_child(inst)
				holder.add_child(pivot)
	return holder


## Uniformly scaled copy whose height is `height`, standing on y = 0, centered.
static func standing(path: String, height: float, rot_deg := Vector3.ZERO) -> Node3D:
	var m := info(path, rot_deg)
	var holder := Node3D.new()
	if m.is_empty():
		return holder
	var src: AABB = m["aabb"]
	var s := height / maxf(src.size.y, 0.001)
	var inst := (m["scene"] as PackedScene).instantiate() as Node3D
	inst.rotation_degrees = rot_deg
	var pivot := Node3D.new()
	pivot.scale = Vector3.ONE * s
	var c := src.get_center()
	pivot.position = -Vector3(c.x, src.position.y, c.z) * s
	pivot.add_child(inst)
	holder.add_child(pivot)
	return holder


## For MultiMesh drawing: each mesh of the model with the transform that makes the
## whole model `height` tall, standing on y = 0 and centered.
static func meshes_for_height(path: String, height: float) -> Array:
	var m := info(path)
	if m.is_empty():
		return []
	var src: AABB = m["aabb"]
	var s := height / maxf(src.size.y, 0.001)
	var c := src.get_center()
	var base := Transform3D(Basis().scaled(Vector3.ONE * s), -Vector3(c.x, src.position.y, c.z) * s)
	var out := []
	for entry: Array in m["meshes"]:
		out.append([entry[0], base * (entry[1] as Transform3D)])
	return out


static func height_of(path: String) -> float:
	var m := info(path)
	return (m["aabb"] as AABB).size.y if not m.is_empty() else 1.0
