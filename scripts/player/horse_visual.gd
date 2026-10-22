class_name HorseVisual
extends Node3D
## A rider's horse: Quaternius' animated low-poly horse (CC0) with a coat colour picked
## from the rider's id, and a saddle and team-coloured blanket strapped to its back.
## Walks, trots and gallops with the rider's speed.

const MODEL := "res://assets/horse/Horse.fbx"
const HEIGHT := 2.6  ## to the top of the head
## Height of the model's back, in model units (the model is 6.9 units to the head).
const BACK_UNITS := 4.4
## Height of the saddle seat above the ground, where the rider sits.
const SEAT_HEIGHT := HEIGHT * BACK_UNITS / 6.9
const COATS := [Color(0.42, 0.26, 0.15), Color(0.22, 0.14, 0.09), Color(0.62, 0.45, 0.28),
	Color(0.75, 0.72, 0.66), Color(0.16, 0.15, 0.15), Color(0.55, 0.32, 0.18)]

var anim: AnimationPlayer
var _current := ""


func setup(peer_id: int, team: int) -> void:
	var model := (load(MODEL) as PackedScene).instantiate() as Node3D
	var aabb: AABB = Models.info(MODEL)["aabb"]
	var s := HEIGHT / maxf(aabb.size.y, 0.001)
	model.scale = Vector3.ONE * s
	model.rotation.y = PI  # the model faces +Z; ours face -Z
	model.position.z = -0.05  # the saddle (torso bone) right under the rider
	add_child(model)
	_paint(model, COATS[absi(peer_id * 7) % COATS.size()])
	anim = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim:
		for n in anim.get_animation_list():
			anim.get_animation(n).loop_mode = Animation.LOOP_NONE if n.ends_with("Death") or n.ends_with("Jump") else Animation.LOOP_LINEAR
		_play("Idle")
	# Saddle and blanket ride on the torso bone, so they move with the gait.
	var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton:
		var att := BoneAttachment3D.new()
		att.bone_name = "Torso"
		skeleton.add_child(att)
		# Bone (at rest) -> this node, so the tack can be built here in meters, facing -Z.
		var bone_rest := skeleton.get_bone_global_rest(skeleton.find_bone("Torso"))
		var tack := Node3D.new()
		tack.transform = (_path_transform(skeleton, self) * bone_rest).affine_inverse()
		att.add_child(tack)
		_build_tack(tack, team)


## Transform of `node` relative to its ancestor `root` (works before entering the tree).
static func _path_transform(node: Node3D, root: Node) -> Transform3D:
	var xf := Transform3D()
	var n: Node = node
	while n != root and n is Node3D:
		xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


## The coat is the model's first material; manes, hooves and eyes keep their colour.
func _paint(model: Node3D, coat: Color) -> void:
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i) as BaseMaterial3D
			if m == null:
				continue
			var mat := m.duplicate() as BaseMaterial3D
			mat.metallic = 0.0
			mat.roughness = 1.0
			if i == 0:
				mat.albedo_color = coat
			mi.set_surface_override_material(i, mat)


func _build_tack(tack: Node3D, team: int) -> void:
	var y := SEAT_HEIGHT
	var tc := GameData.team_color(team)
	var leather := Color(0.36, 0.22, 0.12)
	# A thin cloth over the back, hanging down both flanks.
	tack.add_child(Visuals.box(Vector3(0.62, 0.03, 0.8), tc, Vector3(0, y - 0.06, 0)))
	for side in [-1.0, 1.0]:
		var flap := Visuals.box(Vector3(0.025, 0.3, 0.76), tc, Vector3(side * 0.33, y - 0.2, 0))
		flap.rotation.z = side * 0.18
		tack.add_child(flap)
		tack.add_child(Visuals.box(Vector3(0.03, 0.035, 0.78), Color(0.85, 0.7, 0.25), Vector3(side * 0.36, y - 0.35, 0)))  # trim
	tack.add_child(Visuals.box(Vector3(0.42, 0.08, 0.5), leather, Vector3(0, y - 0.02, 0)))  # saddle
	tack.add_child(Visuals.box(Vector3(0.3, 0.12, 0.06), leather.darkened(0.25), Vector3(0, y + 0.06, -0.24)))  # pommel
	tack.add_child(Visuals.box(Vector3(0.38, 0.1, 0.06), leather.darkened(0.25), Vector3(0, y + 0.04, 0.24)))  # cantle


## Walk, trot or gallop to match `speed` (m/s).
func update_motion(speed: float) -> void:
	if anim == null:
		return
	var want := "Idle"
	if speed > 9.0:
		want = "Run"
	elif speed > 4.0:
		want = "Walk"
	elif speed > 0.5:
		want = "WalkSlow"
	_play(want)
	match want:
		"Run":
			anim.speed_scale = clampf(speed / 13.0, 0.7, 1.4)
		"Walk":
			anim.speed_scale = clampf(speed / 6.0, 0.7, 1.5)
		"WalkSlow":
			anim.speed_scale = clampf(speed / 2.5, 0.6, 1.6)
		_:
			anim.speed_scale = 1.0


func _play(name: String) -> void:
	if name == _current:
		return
	for n in anim.get_animation_list():
		if n.ends_with("|" + name) or n == name:
			anim.play(n, 0.25)
			_current = name
			return
