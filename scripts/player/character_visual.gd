class_name CharacterVisual
extends Node3D
## How a player looks: an animated Kenney Mini Character (picked from the player's id)
## with a team-colored cape and plume, the equipped item in the right hand and a shield
## on the left arm. Plays idle / walk / sprint / jump / fall / attack / shoot / cast /
## block / ride animations from what the player is doing.

const MODELS := [
	"character-male-a", "character-female-a", "character-male-b", "character-female-b",
	"character-male-c", "character-female-c", "character-male-d", "character-female-d",
	"character-male-e", "character-female-e", "character-male-f", "character-female-f",
]
const HEIGHT := 1.75
const LOOPING := ["idle", "walk", "sprint", "holding-left", "holding-right", "holding-both", "sit", "fall", "crouch"]

var anim: AnimationPlayer
var right_hand: Node3D  ## held item goes here (meters, pointing forward along -Z)
var left_hand: Node3D  ## shield goes here
var model_path := ""
var _model: Node3D
var _scale := 1.0
var _meshes: Array[MeshInstance3D] = []
var _one_shot_until := 0.0
var _current := ""


func setup(peer_id: int, team: int) -> void:
	model_path = "res://assets/characters/%s.glb" % MODELS[absi(peer_id) % MODELS.size()]
	_model = _instantiate()
	add_child(_model)
	anim = _model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim:
		for n: String in LOOPING:
			if anim.has_animation(n):
				anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
		anim.play("idle")
	var skeleton := _model.find_child("Skeleton3D", true, false) as Skeleton3D
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		_meshes.append(mi as MeshInstance3D)
	if skeleton == null:
		return
	right_hand = _attach(skeleton, "arm-right", Vector3(-0.01, -0.1, 0.02))
	left_hand = _attach(skeleton, "arm-left", Vector3(0.02, -0.08, 0.03))
	# Team colors: a cape on the back and a plume on top of the head.
	var tc := GameData.team_color(team)
	var back := _attach(skeleton, "torso", Vector3(0, 0.07, -0.075))
	var cape := Visuals.box(Vector3(0.36, 0.42, 0.03), tc, Vector3(0, -0.1, 0))
	cape.rotation.x = 0.12
	back.add_child(cape)
	var head := _attach(skeleton, "head", Vector3(0, 0.0, 0))
	head.add_child(Visuals.box(Vector3(0.07, 0.22, 0.3), tc.lightened(0.15), Vector3(0, 0.55, -0.02)))


func _instantiate() -> Node3D:
	var m := Models.info(model_path)
	var node := (m["scene"] as PackedScene).instantiate() as Node3D
	_scale = HEIGHT / maxf((m["aabb"] as AABB).size.y, 0.001)
	node.scale = Vector3.ONE * _scale
	node.rotation.y = PI  # Kenney characters face +Z; ours face -Z
	return node


## A node riding on a bone, in meters (undoes the model's scale).
func _attach(skeleton: Skeleton3D, bone: String, offset_model_units: Vector3) -> Node3D:
	var att := BoneAttachment3D.new()
	att.bone_name = bone
	skeleton.add_child(att)
	var holder := Node3D.new()
	holder.position = offset_model_units
	holder.scale = Vector3.ONE / _scale
	# Undo the model's 180 degree turn so held items point the way the player faces.
	holder.rotation.y = PI
	att.add_child(holder)
	return holder


## Pick the looping animation for the current movement.
func update_motion(horizontal_speed: float, vertical_speed: float, on_ground: bool, mounted: bool, blocking: bool) -> void:
	if anim == null or Time.get_ticks_msec() / 1000.0 < _one_shot_until:
		return
	var want := "idle"
	if mounted:
		want = "sit"
	elif not on_ground and vertical_speed < -3.0:
		want = "fall"
	elif not on_ground and vertical_speed > 1.0:
		want = "jump"
	elif blocking:
		want = "holding-left"
	elif horizontal_speed > 7.0:
		want = "sprint"
	elif horizontal_speed > 0.6:
		want = "walk"
	if want != _current:
		_current = want
		anim.play(want, 0.15)
	if want == "walk":
		anim.speed_scale = clampf(horizontal_speed / 4.0, 0.6, 1.6)
	else:
		anim.speed_scale = 1.0


## One-shot action animation: "melee", "shoot" or "cast".
func play_action(kind: String) -> void:
	if anim == null:
		return
	var name: String = {"melee": "attack-melee-right", "shoot": "holding-right-shoot", "cast": "interact-right"}.get(kind, "")
	if name == "" or not anim.has_animation(name):
		return
	anim.speed_scale = 1.6
	anim.play(name, 0.05)
	_current = name
	_one_shot_until = Time.get_ticks_msec() / 1000.0 + anim.get_animation(name).length / 1.6


func flash(material: Material) -> void:
	for mi in _meshes:
		mi.material_overlay = material


## A copy of this character that plays its death animation, then sinks away.
func spawn_corpse(parent: Node, at: Transform3D) -> void:
	var holder := Node3D.new()
	parent.add_child(holder)
	holder.global_transform = at
	var body := _instantiate()
	holder.add_child(body)
	var ap := body.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap and ap.has_animation("die"):
		ap.play("die")
	var t := holder.create_tween()
	t.tween_interval(2.5)
	t.tween_property(holder, "position:y", holder.position.y - 1.0, 1.2)
	t.tween_callback(holder.queue_free)


# --- Held items ----------------------------------------------------------------------

## A model of an item as held in the hand: grip at the origin, pointing along -Z.
static func make_held(item_id: String, team: int) -> Node3D:
	var root := Node3D.new()
	var def := GameData.item(item_id)
	var kind: String = def.get("kind", "fists")
	var color: Color = def.get("color", Color.WHITE)
	var steel := Color(0.78, 0.8, 0.85)
	var wood := Color(0.45, 0.3, 0.16)
	if def.has("model"):
		var pivot := Node3D.new()
		pivot.rotation_degrees = Vector3(-90, 0, 0)  # model's up -> forward
		pivot.position = Vector3(0, 0, 0.15)
		pivot.add_child(Models.standing(def["model"], 0.85))
		root.add_child(pivot)
		return root
	match kind:
		"weapon":  # sword
			root.add_child(Visuals.box(Vector3(0.05, 0.05, 0.2), wood, Vector3(0, 0, 0.02)))
			root.add_child(Visuals.box(Vector3(0.3, 0.05, 0.06), Color(0.55, 0.45, 0.2), Vector3(0, 0, -0.1)))
			root.add_child(Visuals.box(Vector3(0.08, 0.02, 0.85), color, Vector3(0, 0, -0.55)))
			root.add_child(Visuals.box(Vector3(0.07, 0.07, 0.07), Color(0.55, 0.45, 0.2), Vector3(0, 0, 0.14)))
		"ranged":
			if item_id == "crossbow":
				root.add_child(Visuals.box(Vector3(0.08, 0.1, 0.7), wood, Vector3(0, 0, -0.25)))
				for side in [-1.0, 1.0]:
					var arm := Visuals.box(Vector3(0.35, 0.04, 0.05), color, Vector3(side * 0.17, 0, -0.52))
					arm.rotation.y = side * 0.25
					root.add_child(arm)
				root.add_child(Visuals.box(Vector3(0.62, 0.01, 0.01), Color(0.9, 0.9, 0.85), Vector3(0, 0, -0.45)))
			else:
				# A curved stave held upright, string toward the archer.
				for k in 7:
					var t := (k - 3) / 3.0
					var seg := Visuals.box(Vector3(0.035, 0.2, 0.035), color, Vector3(0, t * 0.55, -0.08 - 0.12 * (1.0 - t * t)))
					seg.rotation.x = t * 0.5
					root.add_child(seg)
				root.add_child(Visuals.box(Vector3(0.008, 1.1, 0.008), Color(0.92, 0.92, 0.88), Vector3(0, 0, 0.03)))
		"shield":
			var disc := CylinderMesh.new()
			disc.top_radius = 0.36
			disc.bottom_radius = 0.36
			disc.height = 0.05
			disc.radial_segments = 16
			var face := Visuals.mesh_instance(disc, color, Vector3.ZERO)
			face.rotation.x = PI * 0.5
			root.add_child(face)
			var rim := CylinderMesh.new()
			rim.top_radius = 0.39
			rim.bottom_radius = 0.39
			rim.height = 0.03
			rim.radial_segments = 16
			var rim_mi := Visuals.mesh_instance(rim, GameData.team_color(team), Vector3(0, 0, 0.02))
			rim_mi.rotation.x = PI * 0.5
			root.add_child(rim_mi)
			var boss := SphereMesh.new()
			boss.radius = 0.08
			boss.height = 0.1
			root.add_child(Visuals.mesh_instance(boss, steel, Vector3(0, 0, -0.04)))
		"spell":
			var orb := SphereMesh.new()
			orb.radius = 0.09
			orb.height = 0.18
			root.add_child(Visuals.mesh_instance(orb, color, Vector3(0, 0, -0.15), 1.5))
		"consumable":
			var bottle := CylinderMesh.new()
			bottle.top_radius = 0.035
			bottle.bottom_radius = 0.07
			bottle.height = 0.2
			root.add_child(Visuals.mesh_instance(bottle, color, Vector3(0, 0, -0.1)))
			root.add_child(Visuals.box(Vector3(0.04, 0.05, 0.04), wood, Vector3(0, 0.12, -0.1)))
		"structure":
			var crate := Visuals.box(Vector3(0.28, 0.28, 0.28), color, Vector3(0, 0, -0.15))
			crate.material_override = Visuals.textured(def.get("material", "wood"), color)
			root.add_child(crate)
	return root
