class_name Player
extends CharacterBody3D
## One combatant. Movement and aim are owned by the controlling peer (OwnerSync) for
## responsiveness; health, death, crown carrying and mounts are owned by the server
## (ServerSync). Gameplay actions are requests the server validates.

const WALK_SPEED := 6.0
const SPRINT_SPEED := 9.0
const MOUNT_MULT := 1.7
const CROWN_CARRY_MULT := 0.8
const JUMP_VELOCITY := 6.0
const GRAVITY := 18.0
const MOUSE_SENSITIVITY := 0.0025
const REMOTE_SMOOTHING := 15.0

var peer_id := 1
var team := 0
var display_name := "Peasant"

# Replicated from the owning peer.
var sync_pos := Vector3.ZERO
var sync_yaw := 0.0
var equipped := "":
	set(value):
		equipped = value
		if is_node_ready():
			_refresh_weapon()

# Replicated from the server.
var health := GameData.PLAYER_MAX_HEALTH
var max_health := GameData.PLAYER_MAX_HEALTH
var alive := true:
	set(value):
		alive = value
		visible = value
var carrying_crown := -1
var mounted := false:
	set(value):
		mounted = value
		if is_node_ready():
			_refresh_mount()

var hotbar_index := 0

var _game_mode: GameMode
var _pivot: Node3D
var _camera: Camera3D
var _body: Node3D
var _hand: Node3D
var _weapon: MeshInstance3D
var _horse: Node3D
var _ghost: MeshInstance3D
var _ghost_mesh: BoxMesh
var _ghost_ok: StandardMaterial3D
var _ghost_bad: StandardMaterial3D
var _next_action_time := 0.0
var _swing_tween: Tween


func _enter_tree() -> void:
	set_multiplayer_authority(peer_id)
	$ServerSync.set_multiplayer_authority(1)


func _ready() -> void:
	_game_mode = get_tree().get_first_node_in_group("game_mode") as GameMode
	collision_layer = 2  # players
	collision_mask = 1 | 4 | 8  # world, structures, resources (players pass through each other)
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	shape.shape = capsule
	shape.position.y = 0.9
	add_child(shape)
	_build_visuals()
	sync_pos = position
	sync_yaw = rotation.y
	if is_multiplayer_authority():
		_build_camera()
		_build_ghost()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func is_local() -> bool:
	return is_multiplayer_authority()


func teleport(pos: Vector3) -> void:
	position = pos
	sync_pos = pos
	velocity = Vector3.ZERO


func current_speed(sprinting: bool) -> float:
	var speed := SPRINT_SPEED if sprinting else WALK_SPEED
	if carrying_crown >= 0:
		return speed * CROWN_CARRY_MULT
	if mounted:
		return speed * MOUNT_MULT
	return speed


# --- Simulation ------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if is_multiplayer_authority():
		_owner_physics(delta)
		return
	# Remote copy: smooth toward the last replicated transform.
	var t := clampf(delta * REMOTE_SMOOTHING, 0.0, 1.0)
	if position.distance_to(sync_pos) > 8.0:
		position = sync_pos
	else:
		position = position.lerp(sync_pos, t)
	rotation.y = lerp_angle(rotation.y, sync_yaw, t)


func _owner_physics(delta: float) -> void:
	if not alive:
		velocity = Vector3.ZERO
		_update_ghost()
		return
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	var controlling := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var input := Vector2.ZERO
	if controlling:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		if Input.is_action_just_pressed("jump") and is_on_floor():
			velocity.y = JUMP_VELOCITY
	var dir := (transform.basis * Vector3(input.x, 0.0, input.y)).normalized()
	var speed := current_speed(controlling and Input.is_action_pressed("sprint"))
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	move_and_slide()

	position.x = clampf(position.x, -GameData.MAP_WIDTH * 0.5 + 0.5, GameData.MAP_WIDTH * 0.5 - 0.5)
	position.z = clampf(position.z, -GameData.MAP_LENGTH * 0.5 + 0.5, GameData.MAP_LENGTH * 0.5 - 0.5)
	if position.y < -30.0:
		teleport(GameData.spawn_point(team))
	sync_pos = position
	sync_yaw = rotation.y

	if controlling and Input.is_action_pressed("primary"):
		_try_primary()
	_update_ghost()


func _process(_delta: float) -> void:
	if not is_multiplayer_authority() or _game_mode == null:
		return
	# Keep the equipped item valid as the inventory changes.
	var bar := _game_mode.hotbar_items()
	if hotbar_index < bar.size() and bar[hotbar_index] == equipped:
		return
	var idx := bar.find(equipped)
	if idx == -1:
		hotbar_index = 0
		equipped = ""
	else:
		hotbar_index = idx


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseMotion and captured:
		rotation.y -= event.relative.x * MOUSE_SENSITIVITY
		_pivot.rotation.x = clampf(_pivot.rotation.x - event.relative.y * MOUSE_SENSITIVITY, -1.2, 0.9)
		return
	if event.is_action_pressed("release_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	if event is InputEventMouseButton and event.pressed and not captured:
		var hud := (get_parent().get_parent() as World).hud
		if hud == null or not hud.menu_open:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()
		return
	for i in 9:
		if event.is_action_pressed("hotbar_%d" % (i + 1)):
			select_slot(i)
			return
	if captured and event.is_action_pressed("next_slot"):
		select_slot(wrapi(hotbar_index + 1, 0, _game_mode.hotbar_items().size()))
	elif captured and event.is_action_pressed("prev_slot"):
		select_slot(wrapi(hotbar_index - 1, 0, _game_mode.hotbar_items().size()))


func select_slot(i: int) -> void:
	var bar := _game_mode.hotbar_items()
	if i >= 0 and i < bar.size():
		hotbar_index = i
		equipped = bar[i]


# --- Actions ---------------------------------------------------------------------

func _try_primary() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now < _next_action_time:
		return
	var def := GameData.item(equipped)
	if def.is_empty():
		equipped = ""
		return
	var kind: String = def["kind"]
	var target := build_target()
	if kind == "structure" and not GameData.can_build_at(target):
		return
	_next_action_time = now + float(def.get("cooldown", 1.0))
	_game_mode.request(&"request_primary", [equipped, aim_direction(), target])
	if kind in GameData.MELEE_KINDS:
		_swing()
		_remote_swing.rpc()


func aim_direction() -> Vector3:
	if _camera:
		return -_camera.global_basis.z
	return -global_basis.z


## Where a structure would be placed: where the crosshair meets the ground, 2.5-8m ahead.
func build_target() -> Vector3:
	var forward := -global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var dist := 4.0
	if _camera:
		var origin := _camera.global_position
		var dir := aim_direction()
		if dir.y < -0.05:
			var hit := origin + dir * (-origin.y / dir.y)
			dist = clampf(GameData.flat_distance(hit, global_position), 2.5, 8.0)
	var p := global_position + forward * dist
	p.y = 0.0
	return p


@rpc("authority", "call_remote", "unreliable")
func _remote_swing() -> void:
	if not Net.is_dedicated():
		_swing()


func _swing() -> void:
	if _swing_tween:
		_swing_tween.kill()
	_hand.rotation.x = 0.0
	_swing_tween = create_tween()
	_swing_tween.tween_property(_hand, "rotation:x", -1.5, 0.08)
	_swing_tween.tween_property(_hand, "rotation:x", 0.0, 0.18)


# --- Visuals ---------------------------------------------------------------------

func _build_visuals() -> void:
	var tc := GameData.team_color(team)
	_body = Node3D.new()
	add_child(_body)
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	_body.add_child(Visuals.mesh_instance(capsule, tc, Vector3(0, 0.9, 0)))
	# Visor shows which way they face.
	_body.add_child(Visuals.box(Vector3(0.5, 0.12, 0.2), Color(0.15, 0.15, 0.18), Vector3(0, 1.5, -0.33)))

	_hand = Node3D.new()
	_hand.position = Vector3(0.45, 1.1, -0.15)
	_body.add_child(_hand)
	_weapon = MeshInstance3D.new()
	_hand.add_child(_weapon)

	var label := Label3D.new()
	label.text = display_name
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 40
	label.pixel_size = 0.006
	label.outline_size = 8
	label.modulate = tc.lerp(Color.WHITE, 0.5)
	label.position.y = 2.25
	_body.add_child(label)

	_horse = Node3D.new()
	_horse.add_child(Visuals.box(Vector3(0.9, 0.9, 2.0), Color(0.45, 0.3, 0.18), Vector3(0, 0.75, 0)))
	_horse.add_child(Visuals.box(Vector3(0.5, 0.8, 0.7), Color(0.42, 0.28, 0.16), Vector3(0, 1.3, -1.1)))
	add_child(_horse)

	_refresh_weapon()
	_refresh_mount()
	visible = alive


func _refresh_weapon() -> void:
	var def := GameData.item(equipped)
	var kind: String = def.get("kind", "fists")
	if kind == "fists":
		_weapon.visible = false
		return
	_weapon.visible = true
	var m := BoxMesh.new()
	match kind:
		"weapon", "tool":
			m.size = Vector3(0.1, 0.1, 1.0)
			_weapon.position = Vector3(0, 0, -0.45)
		"structure":
			m.size = Vector3(0.35, 0.35, 0.35)
			_weapon.position = Vector3(0, 0, -0.2)
		_:
			m.size = Vector3(0.18, 0.28, 0.18)
			_weapon.position = Vector3(0, 0, -0.2)
	_weapon.mesh = m
	_weapon.material_override = Visuals.mat(def.get("color", Color.WHITE))


func _refresh_mount() -> void:
	_horse.visible = mounted
	_body.position.y = 0.7 if mounted else 0.0


func _build_camera() -> void:
	_pivot = Node3D.new()
	_pivot.position = Vector3(0, 1.6, 0)
	add_child(_pivot)
	var arm := SpringArm3D.new()
	arm.spring_length = 4.0
	arm.position = Vector3(0.7, 0.3, 0)
	arm.collision_mask = 1 | 4
	arm.add_excluded_object(get_rid())
	_pivot.add_child(arm)
	_camera = Camera3D.new()
	_camera.fov = 75.0
	_camera.far = 400.0
	arm.add_child(_camera)
	_camera.current = true


func _build_ghost() -> void:
	_ghost_mesh = BoxMesh.new()
	_ghost = MeshInstance3D.new()
	_ghost.mesh = _ghost_mesh
	_ghost.top_level = true
	_ghost.visible = false
	_ghost_ok = Visuals.mat(Color(0.3, 1.0, 0.4, 0.35))
	_ghost_bad = Visuals.mat(Color(1.0, 0.3, 0.3, 0.35))
	add_child(_ghost)


func _update_ghost() -> void:
	if _ghost == null:
		return
	var def := GameData.item(equipped)
	_ghost.visible = alive and def.get("kind", "") == "structure"
	if not _ghost.visible:
		return
	var size: Vector3 = def["size"]
	if _ghost_mesh.size != size:
		_ghost_mesh.size = size
	var target := build_target()
	_ghost.global_position = target + Vector3(0, size.y * 0.5, 0)
	_ghost.global_rotation = Vector3(0, GameData.snap_yaw(rotation.y), 0)
	_ghost.material_override = _ghost_ok if GameData.can_build_at(target) else _ghost_bad
