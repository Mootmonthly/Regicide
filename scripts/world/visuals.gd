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


## Procedurally textured material: "stone" (blocky cells), "wood" (grain), "roof"
## (tile rows) or "grass" (speckle, used as terrain detail). Triplanar, so any box
## size gets the same texture density.
static func textured(kind: String, color: Color) -> StandardMaterial3D:
	var key := "tex|%s|%s" % [kind, color.to_html()]
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.albedo_texture = _noise_texture(kind)
	m.uv1_triplanar = true
	m.roughness = 0.95
	match kind:
		"stone":
			m.uv1_scale = Vector3(0.6, 0.6, 0.6)
		"wood":
			m.uv1_scale = Vector3(0.25, 1.6, 0.25)
		"roof":
			m.uv1_scale = Vector3(0.8, 1.6, 0.8)
		_:
			m.uv1_scale = Vector3(0.12, 0.12, 0.12)
	_materials[key] = m
	return m


static var _noise_textures: Dictionary = {}


static func _noise_texture(kind: String) -> NoiseTexture2D:
	if _noise_textures.has(kind):
		return _noise_textures[kind]
	var noise := FastNoiseLite.new()
	var ramp := Gradient.new()
	match kind:
		"stone":
			noise.noise_type = FastNoiseLite.TYPE_CELLULAR
			noise.frequency = 0.035
			noise.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
			ramp.set_color(0, Color(0.62, 0.62, 0.62))
			ramp.set_color(1, Color(1.08, 1.08, 1.08))
		"wood":
			noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
			noise.frequency = 0.05
			noise.fractal_octaves = 4
			ramp.set_color(0, Color(0.7, 0.7, 0.7))
			ramp.set_color(1, Color(1.1, 1.1, 1.1))
		"roof":
			noise.noise_type = FastNoiseLite.TYPE_CELLULAR
			noise.frequency = 0.06
			ramp.set_color(0, Color(0.65, 0.65, 0.65))
			ramp.set_color(1, Color(1.05, 1.05, 1.05))
		_:
			noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
			noise.frequency = 0.08
			noise.fractal_octaves = 3
			ramp.set_color(0, Color(0.82, 0.86, 0.8))
			ramp.set_color(1, Color(1.08, 1.06, 1.02))
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.noise = noise
	tex.color_ramp = ramp
	_noise_textures[kind] = tex
	return tex


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
