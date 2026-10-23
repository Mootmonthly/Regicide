class_name CharacterVisual
extends Node3D
## How a player looks: the KayKit Knight (everyone wears the same armour; the cape,
## chest rose and shield faces take the team's colour). Weapons sit in the knight's
## hand-slot bones, and an animation is picked from what the player is doing and holding:
## idle / walk / run / jump / block / ride, sword slices, axe chops, pickaxe swings,
## bow and crossbow shots, spellcasting, potion drinking, hit reactions and death.

const MODEL := "res://assets/kaykit/Knight.glb"
const ANIMATION_FILES := ["General", "MovementBasic", "MovementAdvanced", "CombatMelee", "CombatRanged", "Tools"]
const HEIGHT := 1.8
const LOOPING := ["Idle_A", "Idle_B", "Walking_A", "Walking_B", "Running_A", "Running_B", "Jump_Idle",
	"Melee_Blocking", "Ranged_Bow_Idle", "Ranged_Bow_Aiming_Idle", "Ranged_1H_Aiming", "Crouching",
	"Melee_Unarmed_Idle", "Running_HoldingBow", "Walking_Backwards"]
## Items carried upright in the right hand (see ArmHold).
const HELD_UPRIGHT := ["iron_sword", "stone_axe", "pickaxe", "wooden_club", "war_hammer"]
## (The horizontal slice is left out: it turns the wrist so the flat of the blade leads.)
const SWORD_SWINGS := ["Melee_1H_Attack_Slice_Diagonal", "Melee_1H_Attack_Chop"]

## How each item is held. KayKit models are made for the hand slot as they are; other
## models stand upright (+Y) with the grip a little above their bottom. "fp_base" then
## "fp" (degrees) are the extra rotation that makes the item look right in first person,
## where +Y is up and -Z is straight ahead.
## First person: at rest a blade shows its face to the camera; the swing pitches the
## hand forward, so the wrist turns the item this far about its handle as it swings, and
## the edge (the axe's cutting side) leads instead of the flat.
const FP_EDGE_SPIN := -90.0
const HELD := {
	"iron_sword": {"kaykit": "sword_1handed"},
	"stone_axe": {"kaykit": "axe_1handed"},
	# The bow model lies along Z with its belly toward -X: stand it up, belly forward.
	# In first person it is also turned and canted so its curve shows.
	"shortbow": {"kaykit": "bow_withString", "fp_base": Basis(Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)), "fp": Vector3(0, 60, 25)},
	"crossbow": {"kaykit": "crossbow_1handed", "fp": Vector3(0, 165, 0)},
	"wooden_shield": {"kaykit": "shield_round_color"},
	"iron_shield": {"kaykit": "shield_badge_color"},
	"pickaxe": {"model": "res://assets/survival/tool-pickaxe.glb", "length": 0.95},
	"wooden_club": {"model": "res://assets/survival/tool-hammer.glb", "length": 0.9},
	"war_hammer": {"model": "res://assets/survival/tool-hammer-upgraded.glb", "length": 1.05},
}

## Bones of the right arm that hold a weapon upright while walking, running and idling.
const HOLD_BONES := ["upperarm.r", "lowerarm.r", "wrist.r", "hand.r"]
const HOLD_POSE := "Holding_A"

static var _library: AnimationLibrary
static var _team_materials: Dictionary = {}  ## (team, tinted steel) -> recoloured material
static var _merged: Array = []  ## [ArrayMesh, Skin]: the knight's parts as one mesh, built once

## Level of detail by distance from the camera. Far characters animate less often, stop
## casting shadows and hide what they hold; off-screen ones animate rarely.
const LOD_FULL := 22.0  ## closer than this: animate every frame
const LOD_STEPS := [[45.0, 1.0 / 30.0], [90.0, 1.0 / 15.0], [INF, 1.0 / 8.0]]
const OFFSCREEN_STEP := 1.0 / 5.0
const SHADOW_RANGE := 40.0
const HELD_RANGE := 70.0
const DRAW_RANGE := 220.0

var anim: AnimationPlayer
var right_hand: Node3D  ## held item goes here (meters, KayKit hand-slot orientation)
var left_hand: Node3D  ## shield goes here
var held_item := ""  ## what's in the right hand, for picking animations
var team := 0
var _model: Node3D
var _meshes: Array[MeshInstance3D] = []
var _one_shot_until := 0.0
var _current := ""
var _swing := 0
var _hold: ArmHold
var _anim_wait := 0.0  ## time since the animation last advanced
var _lod_check := 0.0
var _anim_step := 0.0
var _casting := true


## Poses the right arm like the Holding_A animation (weapon upright in front of the
## chest) on top of whatever the legs and body are doing. Its influence is faded to 0
## during attacks and other actions, so those play exactly as animated.
class ArmHold extends SkeletonModifier3D:
	var targets: Dictionary = {}  ## bone index -> Quaternion

	func setup(skeleton: Skeleton3D, animation: Animation) -> void:
		for t in animation.get_track_count():
			if animation.track_get_type(t) != Animation.TYPE_ROTATION_3D:
				continue
			var bone := String(animation.track_get_path(t)).get_slice(":", 1)
			if bone in CharacterVisual.HOLD_BONES:
				targets[skeleton.find_bone(bone)] = animation.rotation_track_interpolate(t, 0.0)

	func _process_modification() -> void:
		var skeleton := get_skeleton()
		if skeleton == null:
			return
		for bone: int in targets:
			skeleton.set_bone_pose_rotation(bone, targets[bone])


## Meters per KayKit unit (the knight model is about 2.4 units tall).
static func unit_scale() -> float:
	return HEIGHT / maxf((Models.info(MODEL)["aabb"] as AABB).size.y, 0.001)


func setup(_peer_id: int, p_team: int) -> void:
	team = p_team
	_model = _instantiate()
	add_child(_model)
	anim = _model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	anim.play("Idle_A")
	_lod_check = randf() * 0.25  # spread the checks over frames
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		_meshes.append(mi as MeshInstance3D)
	var skeleton := _model.find_child("Skeleton3D", true, false) as Skeleton3D
	_hold = ArmHold.new()
	skeleton.add_child(_hold)
	_hold.setup(skeleton, animation_library().get_animation(HOLD_POSE))
	_hold.influence = 0.0
	_hold.active = false
	right_hand = _attach(skeleton, "handslot.r")
	left_hand = _attach(skeleton, "handslot.l")


func _instantiate() -> Node3D:
	var node := (load(MODEL) as PackedScene).instantiate() as Node3D
	node.scale = Vector3.ONE * unit_scale()
	node.rotation.y = PI  # KayKit characters face +Z; ours face -Z
	# The visor hides the face; leave the helmet open.
	var visor := node.find_child("Knight_HelmetVisor", true, false) as Node3D
	if visor:
		visor.visible = false
	if not Net.is_dedicated():
		_merge_parts(node)
	apply_team_colors(node, team)
	var ap := AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	node.add_child(ap)
	ap.add_animation_library("", animation_library())
	return node


func _process(delta: float) -> void:
	if anim == null:
		return
	_lod_check -= delta
	if _lod_check <= 0.0:
		_lod_check = 0.25
		_update_lod()
	_anim_wait += delta
	if _anim_wait >= _anim_step:
		anim.advance(_anim_wait)
		_anim_wait = 0.0


func _update_lod() -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		_anim_step = 0.0
		return
	var at := global_position + Vector3(0, 1.0, 0)
	var dist := cam.global_position.distance_to(at)
	if dist < LOD_FULL:
		_anim_step = 0.0
	elif not cam.is_position_in_frustum(at):
		_anim_step = OFFSCREEN_STEP
	else:
		for step: Array in LOD_STEPS:
			if dist < step[0]:
				_anim_step = step[1]
				break
	var cast := dist < SHADOW_RANGE
	if cast != _casting:
		_casting = cast
		for mi in _meshes:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var near := dist < HELD_RANGE
	if right_hand and right_hand.visible != near:
		right_hand.visible = near
		left_hand.visible = near


## Replace the knight's separate body-part meshes with one mesh (one draw call instead
## of eight). The merged mesh and its skin are built once and shared.
static func _merge_parts(node: Node3D) -> void:
	var parts: Array[MeshInstance3D] = []
	for n in node.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.visible and mi.mesh and mi.skin:
			parts.append(mi)
	if parts.size() < 2:
		return
	if _merged.is_empty():
		_merged = _build_merged(parts)
		if _merged.is_empty():
			_merged = [null]
	if _merged[0] == null:
		return  # parts didn't line up; keep them separate
	var first := parts[0]
	var merged := MeshInstance3D.new()
	merged.name = "KnightMerged"
	merged.mesh = _merged[0]
	merged.skin = _merged[1]
	first.get_parent().add_child(merged)
	merged.transform = first.transform
	merged.skeleton = merged.get_path_to(first.get_node(first.skeleton))
	merged.visibility_range_end = DRAW_RANGE
	for mi in parts:
		mi.get_parent().remove_child(mi)
		mi.free()


static func _build_merged(parts: Array[MeshInstance3D]) -> Array:
	var skin := Skin.new()
	var bind_index := {}  ## "bone|pose" -> merged bind index
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	var keys: Array[int] = []
	var flags := 0
	var material: Material = null
	var base := 0
	for mi in parts:
		var mesh := mi.mesh
		if mesh.get_surface_count() != 1 or not mi.transform.is_equal_approx(parts[0].transform):
			return []
		var arrays := mesh.surface_get_arrays(0)
		var surf_flags: int = mesh.surface_get_format(0) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		if keys.is_empty():
			flags = surf_flags
			material = mesh.surface_get_material(0)
			for k in Mesh.ARRAY_MAX:
				if arrays[k] != null:
					keys.append(k)
		elif surf_flags != flags:
			return []
		for k in Mesh.ARRAY_MAX:
			if (arrays[k] != null) != keys.has(k):
				return []
		# Bone indices point at this part's skin binds: remap them to the merged skin.
		var remap := PackedInt32Array()
		for b in mi.skin.get_bind_count():
			var bone := mi.skin.get_bind_bone(b)
			var bname := mi.skin.get_bind_name(b)
			var pose := mi.skin.get_bind_pose(b)
			var key := "%d|%s|%s" % [bone, bname, var_to_str(pose)]
			if not bind_index.has(key):
				bind_index[key] = skin.get_bind_count()
				if bname != &"":
					skin.add_named_bind(bname, pose)
				else:
					skin.add_bind(bone, pose)
			remap.append(bind_index[key])
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		for i in bones.size():
			bones[i] = remap[bones[i]] if bones[i] < remap.size() else 0
		arrays[Mesh.ARRAY_BONES] = bones
		var vcount: int = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		if arrays[Mesh.ARRAY_INDEX] != null:
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for i in idx.size():
				idx[i] += base
			arrays[Mesh.ARRAY_INDEX] = idx
		for k in keys:
			if out[k] == null:
				out[k] = arrays[k]
			else:
				out[k].append_array(arrays[k])
		base += vcount
	# Build through ImporterMesh so distant knights get simplified versions (LODs), like
	# the imported parts had.
	var importer := ImporterMesh.new()
	importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, out, [], {}, material, "", flags)
	importer.generate_lods(25.0, 60.0, [])
	var mesh := importer.get_mesh()
	return [mesh, skin]


## A node riding on a bone, in meters and in the bone's orientation.
func _attach(skeleton: Skeleton3D, bone: String) -> Node3D:
	var att := BoneAttachment3D.new()
	att.bone_name = bone
	skeleton.add_child(att)
	var holder := Node3D.new()
	holder.scale = Vector3.ONE / unit_scale()
	att.add_child(holder)
	return holder


## Every KayKit animation, shared by all characters.
static func animation_library() -> AnimationLibrary:
	if _library:
		return _library
	_library = AnimationLibrary.new()
	for file: String in ANIMATION_FILES:
		var scene := load("res://assets/kaykit/anims/Rig_Medium_%s.glb" % file) as PackedScene
		var root := scene.instantiate()
		var ap := root.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if ap:
			for n in ap.get_animation_list():
				if not _library.has_animation(n):
					var a := ap.get_animation(n).duplicate() as Animation
					a.loop_mode = Animation.LOOP_LINEAR if n in LOOPING else Animation.LOOP_NONE
					_library.add_animation(n, a)
		root.free()
	return _library


## The knight's texture with its red parts (cape, rose, shield faces) in the team colour
## and its steel lightly tinted, so teams can be told apart from any side.
static func team_material(p_team: int, tint_steel := true) -> StandardMaterial3D:
	var key := Vector2i(p_team, int(tint_steel))
	if _team_materials.has(key):
		return _team_materials[key]
	var src := (load("res://assets/kaykit/knight_texture.png") as Texture2D).get_image()
	if src.is_compressed():
		src.decompress()
	var target := GameData.team_color(p_team)
	var img := src.duplicate() as Image
	if img.has_mipmaps():
		img.clear_mipmaps()
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.s > 0.45 and (c.h < 0.04 or c.h > 0.94):
				img.set_pixel(x, y, Color.from_hsv(target.h, clampf(c.s * target.s / 0.75, 0.0, 1.0), c.v, c.a))
			elif tint_steel and c.s < 0.15 and c.v > 0.25:  # grey steel: a light wash of the team colour
				img.set_pixel(x, y, Color.from_hsv(target.h, 0.22, c.v, c.a))
	img.generate_mipmaps()
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.roughness = 1.0
	mat.metallic_specular = 0.3
	_team_materials[key] = mat
	return mat


## Swap the knight texture for the team-coloured one on every mesh under `node`.
static func apply_team_colors(node: Node, p_team: int, tint_steel := true) -> void:
	if Net.is_dedicated():
		return
	var mat := team_material(p_team, tint_steel)
	for n in node.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s) as BaseMaterial3D
			if m and m.albedo_texture and m.albedo_texture.resource_path.contains("knight_texture"):
				mi.set_surface_override_material(s, mat)


## Pick the looping animation for the current movement.
func update_motion(horizontal_speed: float, vertical_speed: float, on_ground: bool, mounted: bool, blocking: bool) -> void:
	if anim == null:
		return
	var acting := Time.get_ticks_msec() / 1000.0 < _one_shot_until
	if _hold:
		var hold := not acting and not blocking and held_item in HELD_UPRIGHT
		_hold.influence = move_toward(_hold.influence, 1.0 if hold else 0.0, get_process_delta_time() * 6.0)
		_hold.active = _hold.influence > 0.0
	if acting:
		return
	var bow := held_item == "shortbow"
	var want := "Ranged_Bow_Idle" if bow else ("Ranged_1H_Aiming" if held_item == "crossbow" else "Idle_A")
	if mounted:
		want = "Crouching"
	elif not on_ground and absf(vertical_speed) > 1.5:
		want = "Jump_Idle"
	elif blocking:
		want = "Melee_Blocking"
	elif horizontal_speed > 7.0:
		want = "Running_HoldingBow" if bow else "Running_A"
	elif horizontal_speed > 0.6:
		want = "Walking_A"
	if want != _current:
		_current = want
		anim.play(want, 0.15)
	if want == "Walking_A":
		anim.speed_scale = clampf(horizontal_speed / 3.0, 0.6, 1.8)
	elif want.begins_with("Running"):
		anim.speed_scale = clampf(horizontal_speed / 7.5, 0.8, 1.5)
	else:
		anim.speed_scale = 1.0


## One-shot action animation: "melee", "shoot", "cast", "use", "hit" or "build".
func play_action(kind: String) -> void:
	if anim == null or (kind == "hit" and Time.get_ticks_msec() / 1000.0 < _one_shot_until):
		return
	var name := _action_animation(kind)
	if name == "" or not anim.has_animation(name):
		return
	var speed := 1.0 if kind == "hit" else 1.7
	anim.speed_scale = speed
	if _hold:
		_hold.influence = 0.0
		_hold.active = false
	anim.play(name, 0.05)
	anim.seek(0.0, true)
	_current = name
	_one_shot_until = Time.get_ticks_msec() / 1000.0 + anim.get_animation(name).length / speed * 0.85


func _action_animation(kind: String) -> String:
	match kind:
		"melee":
			match held_item:
				"", "fists":
					return "Melee_Unarmed_Attack_Punch_A"
				"stone_axe":
					return "Chop"
				"pickaxe":
					return "Pickaxe"
				"wooden_club", "war_hammer":
					return "Melee_1H_Attack_Chop"
			_swing += 1
			return SWORD_SWINGS[_swing % SWORD_SWINGS.size()]
		"shoot":
			return "Ranged_Bow_Release" if held_item == "shortbow" else "Ranged_1H_Shoot"
		"cast":
			return "Ranged_Magic_Shoot"
		"use":
			return "Use_Item"
		"hit":
			return "Hit_A"
		"build":
			return "Interact"
	return ""


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
	if ap and ap.has_animation("Death_A"):
		ap.play("Death_A")
	var t := holder.create_tween()
	t.tween_interval(3.0)
	t.tween_property(holder, "position:y", holder.position.y - 1.0, 1.2)
	t.tween_callback(holder.queue_free)


# --- Held items ----------------------------------------------------------------------

## A model of an item as held, in meters. Oriented for the knight's hand slot (+Y runs
## from the grip toward the blade / head), or, with `first_person`, for the camera.
static func make_held(item_id: String, p_team: int, first_person := false) -> Node3D:
	var root := Node3D.new()
	var def := GameData.item(item_id)
	var kind: String = def.get("kind", "fists")
	var color: Color = def.get("color", Color.WHITE)
	var wood := Color(0.45, 0.3, 0.16)
	var spec: Dictionary = HELD.get(item_id, {})
	if first_person and spec.has("fp"):
		var euler: Vector3 = spec["fp"]
		root.basis = Basis.from_euler(euler * PI / 180.0) * (spec.get("fp_base", Basis()) as Basis)

	if spec.has("kaykit"):
		var node := (load("res://assets/kaykit/items/%s.gltf" % spec["kaykit"]) as PackedScene).instantiate() as Node3D
		node.scale = Vector3.ONE * unit_scale()
		apply_team_colors(node, p_team, false)
		root.add_child(node)
		return root
	if spec.has("model"):
		var pivot := Node3D.new()
		pivot.position = Vector3(0, -0.15, 0)
		pivot.add_child(Models.standing(spec["model"], spec.get("length", 0.9)))
		root.add_child(pivot)
		return root
	match kind:
		"spell":  # a glowing orb on a short wand
			root.add_child(Visuals.box(Vector3(0.04, 0.4, 0.04), wood, Vector3(0, 0.1, 0)))
			var orb := SphereMesh.new()
			orb.radius = 0.08
			orb.height = 0.16
			root.add_child(Visuals.mesh_instance(orb, color, Vector3(0, 0.35, 0), 1.5))
		"consumable":
			var bottle := CylinderMesh.new()
			bottle.top_radius = 0.035
			bottle.bottom_radius = 0.07
			bottle.height = 0.2
			root.add_child(Visuals.mesh_instance(bottle, color, Vector3(0, 0.1, 0)))
			root.add_child(Visuals.box(Vector3(0.04, 0.05, 0.04), wood, Vector3(0, 0.22, 0)))
		"structure":
			var crate := Visuals.box(Vector3(0.28, 0.28, 0.28), color, Vector3(0, 0.1, 0))
			crate.material_override = Visuals.textured(def.get("material", "wood"), color)
			root.add_child(crate)
		"weapon":  # any sword without its own model
			root.add_child(Visuals.box(Vector3(0.05, 0.2, 0.05), wood, Vector3(0, 0.0, 0)))
			root.add_child(Visuals.box(Vector3(0.3, 0.05, 0.06), Color(0.55, 0.45, 0.2), Vector3(0, 0.12, 0)))
			root.add_child(Visuals.box(Vector3(0.11, 0.85, 0.035), color, Vector3(0, 0.57, 0)))
	return root
