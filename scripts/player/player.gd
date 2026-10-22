class_name Player
extends CharacterBody3D
## One combatant, human or bot. Movement and aim are owned by the controlling peer
## (OwnerSync): the human's own machine, or the server for bots. Health, death, crown
## carrying and mounts are owned by the server (ServerSync). Gameplay actions are
## requests the server validates.

const WALK_SPEED := 6.0
const SPRINT_SPEED := 9.0
const MOUNT_MULT := 1.7
const CROWN_CARRY_MULT := 0.8
const JUMP_VELOCITY := 6.0
const GRAVITY := 18.0
const MOUSE_SENSITIVITY := 0.0025
const REMOTE_SMOOTHING := 15.0
const CLIMB_SPEED := 4.0
const WADE_MULT := 0.45
const EYE_HEIGHT := 1.65
const BODY_LAYER := 2  ## render layer for your own body, hidden from your first-person camera

var peer_id := 1
var team := 0
var display_name := "Peasant"
var is_bot := false

# Replicated from the owning peer.
var sync_pos := Vector3.ZERO
var sync_yaw := 0.0
var equipped := "":
	set(value):
		equipped = value
		if is_node_ready():
			_refresh_weapon()

# Replicated from the server.
var health := GameData.PLAYER_MAX_HEALTH:
	set(value):
		var old := health
		health = value
		if is_node_ready() and value < old - 0.01:
			_on_damaged(old - value)
var max_health := GameData.PLAYER_MAX_HEALTH
var alive := true:
	set(value):
		var was_alive := alive
		alive = value
		visible = value
		if is_node_ready() and was_alive and not value:
			_on_death()
var max_mana := GameData.PLAYER_MAX_MANA
var mana := GameData.PLAYER_MAX_MANA
var slowed := false
var stunned := false
var carrying_crown := -1
var mounted := false:
	set(value):
		mounted = value
		if is_node_ready():
			_refresh_mount()

# Replicated from the owning peer: shield raised (right mouse) and which shield.
var blocking := false:
	set(value):
		if value and not blocking and _game_mode:
			block_started = _game_mode.clock  # parry timing (used on the server)
		blocking = value
		if is_node_ready():
			_refresh_shield()
var shield_item := "":
	set(value):
		shield_item = value
		if is_node_ready():
			_refresh_shield()
var block_started := -100.0

## Sprint stamina (owner side).
var stamina := GameData.MAX_STAMINA
var _stamina_pause := 0.0
## First person by default; V toggles an over-the-shoulder view.
var third_person := false

# Movement intent: read from the keyboard for humans, written by BotBrain for bots.
var move_input := Vector2.ZERO
var wants_sprint := false
var wants_jump := false

var hotbar_index := 0
## Build mode swaps the hotbar for building pieces (toggle with Q).
## 0 = normal play; 1+ = build mode on that page of building pieces (Q cycles).
var build_page := 0
var build_mode: bool:
	get:
		return build_page > 0
## Manual rotation for the next piece (R).
var build_turn := 0
## In build mode: your team's piece under the crosshair (for repair / upgrade).
var aimed_piece: Structure
## Your team's drawbridge or catapult within reach (E to use).
var interact_target: Structure
var on_ladder := false

var _game_mode: GameMode
var _pivot: Node3D
var _camera: Camera3D
var _body: Node3D
var _look: CharacterVisual
var _hand: Node3D
var _weapon: Node3D
var _last_anim_pos := Vector3.ZERO
var _anim_speed := 0.0
var _anim_vy := 0.0
var _horse: Node3D
var _world: World
var _ghost: Node3D
var _ghost_item := ""
var _ghost_slot: Dictionary = {}
var _ghost_ok: StandardMaterial3D
var _ghost_bad: StandardMaterial3D
var _ghost_valid := false
var _ghost_problem := ""
var _saved_weapon_index := 0
var _next_hint_time := 0.0
var _next_action_time := 0.0
var _swing_tween: Tween
var _flash_tween: Tween
var _arm: SpringArm3D
var _viewmodel: Node3D
## Where the first-person weapon rests (camera space).
const VM_HAND_POS := Vector3(0.3, -0.34, -0.52)
## Upright, leaning forward and a little in toward the middle of the screen.
const VM_HAND_ROT := Vector3(-0.1, -0.5, 0.25)
var _vm_hand: Node3D
var _vm_weapon: Node3D
var _vm_shield: Node3D
var _shield_mesh: Node3D
var _spell_ready: Dictionary = {}
var _speaking_label: Label3D

static var _flash_material: StandardMaterial3D


func _enter_tree() -> void:
	set_multiplayer_authority(1 if is_bot else peer_id)
	$ServerSync.set_multiplayer_authority(1)


func _ready() -> void:
	_game_mode = get_tree().get_first_node_in_group("game_mode") as GameMode
	_world = get_parent().get_parent() as World
	floor_constant_speed = true  # same pace up stairs and ramps
	collision_layer = 2  # players
	# World, structures, resources, and the enemy team's gates. Players pass through each other.
	collision_mask = 1 | 4 | 8 | GameData.gate_layer(1 - team)
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	shape.shape = capsule
	shape.position.y = 0.9
	add_child(shape)
	if not Net.is_dedicated():
		_build_visuals()
	else:
		_hand = Node3D.new()
		add_child(_hand)
	sync_pos = position
	sync_yaw = rotation.y
	if is_local():
		_build_camera()
		_ghost_ok = Visuals.mat(Color(0.3, 1.0, 0.4, 0.35))
		_ghost_bad = Visuals.mat(Color(1.0, 0.3, 0.3, 0.35))
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## True only for the human player sitting at this machine.
func is_local() -> bool:
	return not is_bot and is_multiplayer_authority()


func teleport(pos: Vector3) -> void:
	position = pos
	sync_pos = pos
	velocity = Vector3.ZERO


func in_water() -> bool:
	return position.y < Terrain.WATER_LEVEL - 0.35


func current_speed(sprinting: bool) -> float:
	if stunned:
		return 0.0
	var speed := SPRINT_SPEED if sprinting else WALK_SPEED
	var mult := 1.0
	if blocking:
		mult *= 0.5
	if slowed:
		mult *= GameData.SLOW_MULT
	if is_local() and _game_mode:
		var skills: Dictionary = _game_mode.my_stats.get("skills", {})
		mult *= 1.0 + 0.06 * int(skills.get("swiftness", 0))
	if in_water():
		# Wading: no sprinting, and horses don't help.
		return WALK_SPEED * WADE_MULT * (CROWN_CARRY_MULT if carrying_crown >= 0 else 1.0) * mult
	if carrying_crown >= 0:
		return speed * CROWN_CARRY_MULT * mult
	if mounted:
		return speed * MOUNT_MULT * mult
	return speed * mult


## Show the "talking" marker over this player (voice chat).
func set_speaking(on: bool) -> void:
	if _speaking_label:
		_speaking_label.visible = on


func chest() -> Vector3:
	return sync_pos + Vector3(0, 1.1, 0)


# --- Simulation ------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _look and delta > 0.0:
		# Animate from how fast we're actually moving (works for remote players too).
		var moved := (position - _last_anim_pos) / delta
		_last_anim_pos = position
		_anim_speed = lerpf(_anim_speed, Vector2(moved.x, moved.z).length(), 0.3)
		_anim_vy = lerpf(_anim_vy, moved.y, 0.3)
		var grounded := is_on_floor() if is_multiplayer_authority() else absf(_anim_vy) < 1.5
		_look.update_motion(_anim_speed, _anim_vy, grounded or on_ladder, mounted, blocking)
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
	if _world and not _world.terrain_ready:
		return  # wait for the map before falling onto it
	if not alive:
		velocity = Vector3.ZERO
		_update_ghost()
		return
	var controlling := is_bot or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if not is_bot:
		move_input = Vector2.ZERO
		wants_jump = false
		wants_sprint = false
		if controlling and not stunned:
			move_input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
			wants_jump = Input.is_action_just_pressed("jump")
			wants_sprint = Input.is_action_pressed("sprint")
		shield_item = _best_shield()
		blocking = controlling and alive and not stunned and not build_mode and shield_item != "" \
			and Input.is_action_pressed("block")
	# Stamina: sprinting drains it; it refills after a short rest.
	var sprinting := wants_sprint and move_input.length() > 0.1 and not blocking and not in_water()
	if sprinting and stamina > 0.0:
		stamina = maxf(stamina - GameData.SPRINT_STAMINA_COST * delta, 0.0)
		_stamina_pause = 0.8
	else:
		sprinting = false
		_stamina_pause -= delta
		if _stamina_pause <= 0.0:
			stamina = minf(stamina + GameData.STAMINA_REGEN * delta, GameData.MAX_STAMINA)
	if stunned:
		wants_jump = false
	# Ladders: hold forward to climb, back to climb down.
	on_ladder = _world != null and _world.ladder_at(position) != null
	if on_ladder and (move_input.y < -0.1 or not is_on_floor()):
		velocity.y = -move_input.y * CLIMB_SPEED
		if wants_jump:
			velocity.y = JUMP_VELOCITY * 0.6
	elif not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif wants_jump:
		velocity.y = JUMP_VELOCITY
	var dir := (transform.basis * Vector3(move_input.x, 0.0, move_input.y)).normalized()
	var speed := current_speed(sprinting)
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	move_and_slide()

	position.x = clampf(position.x, -GameData.MAP_WIDTH * 0.5 + 0.5, GameData.MAP_WIDTH * 0.5 - 0.5)
	position.z = clampf(position.z, -GameData.MAP_LENGTH * 0.5 + 0.5, GameData.MAP_LENGTH * 0.5 - 0.5)
	if position.y < -30.0:
		teleport(GameData.spawn_point(team))
	sync_pos = position
	sync_yaw = rotation.y

	if not is_bot:
		if controlling and Input.is_action_pressed("primary"):
			_try_primary()
		_update_ghost()


func _process(_delta: float) -> void:
	if not is_local() or _game_mode == null:
		return
	interact_target = _world.interactable_near(position, team) if alive and _world else null
	# Keep the equipped item valid as the inventory changes.
	var bar := _game_mode.hotbar_items(build_page)
	if hotbar_index < bar.size() and bar[hotbar_index] == equipped:
		return
	var idx := bar.find(equipped)
	if idx == -1:
		hotbar_index = 0
		equipped = bar[0] if not bar.is_empty() else ""
	else:
		hotbar_index = idx


func _unhandled_input(event: InputEvent) -> void:
	if not is_local():
		return
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseMotion and captured:
		rotation.y -= event.relative.x * MOUSE_SENSITIVITY
		_pivot.rotation.x = clampf(_pivot.rotation.x - event.relative.y * MOUSE_SENSITIVITY, -1.45, 1.4)
		return
	if event.is_action_pressed("camera_toggle"):
		set_third_person(not third_person)
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
	if event.is_action_pressed("build_mode"):
		set_build_page((build_page + 1) % (GameData.BUILD_CATEGORIES.size() + 1))
		return
	if event.is_action_pressed("interact") and interact_target:
		_game_mode.request(&"request_interact", [aim_direction()])
		return
	if build_mode:
		if event.is_action_pressed("rotate_piece"):
			build_turn = (build_turn + 1) % 4
			Sfx.play("click", -10.0)
			return
		if event.is_action_pressed("repair") and aimed_piece:
			_game_mode.request(&"request_repair", [String(aimed_piece.name)])
			Sfx.play("repair", -4.0)
			return
		if event.is_action_pressed("upgrade") and aimed_piece:
			_game_mode.request(&"request_upgrade", [String(aimed_piece.name)])
			return
	for i in 10:
		if event.is_action_pressed("hotbar_%d" % (i + 1)):
			select_slot(i)
			return
	var count := maxi(_game_mode.hotbar_items(build_page).size(), 1)
	if captured and event.is_action_pressed("next_slot"):
		select_slot(wrapi(hotbar_index + 1, 0, count))
	elif captured and event.is_action_pressed("prev_slot"):
		select_slot(wrapi(hotbar_index - 1, 0, count))


func set_build_mode(on: bool) -> void:
	set_build_page(1 if on else 0)


func set_build_page(page: int) -> void:
	if page == build_page:
		return
	if build_page == 0:
		_saved_weapon_index = hotbar_index
	build_page = page
	select_slot(_saved_weapon_index if page == 0 else 0)
	if hotbar_index >= _game_mode.hotbar_items(build_page).size():
		select_slot(0)
	Sfx.play("click", -8.0)


func select_slot(i: int) -> void:
	var bar := _game_mode.hotbar_items(build_page)
	if i >= 0 and i < bar.size():
		hotbar_index = i
		equipped = bar[i]
		Sfx.play("click", -12.0)


# --- Actions ---------------------------------------------------------------------

func _try_primary() -> void:
	if _game_mode.clock < _next_action_time or blocking or stunned:
		return
	var def := GameData.item(equipped)
	if def.is_empty():
		equipped = ""
		return
	var kind: String = def["kind"]
	if kind == "structure":
		_try_build(def)
		return
	if kind == "spell":
		if _game_mode.clock < float(_spell_ready.get(equipped, 0.0)):
			return
		if mana < float(def["mana"]):
			_hint("Not enough mana (%d needed)." % int(def["mana"]))
			return
		_spell_ready[equipped] = _game_mode.clock + float(def["cooldown"])
	if kind == "ranged" and int(_game_mode.my_inventory.get(def["ammo"], 0)) <= 0:
		_game_mode.message_received.emit("Out of arrows! Craft more in the menu (C).")
		_next_action_time = _game_mode.clock + 1.0
		return
	_next_action_time = _game_mode.clock + float(def.get("cooldown", 1.0))
	_game_mode.request(&"request_primary", [equipped, aim_direction(), Vector3.ZERO])
	play_action_anim(kind)


## Plays the swing/shoot animation here and on every other peer.
func play_action_anim(kind: String) -> void:
	if kind in GameData.MELEE_KINDS or kind == "ranged" or kind == "spell":
		var push := kind != "fists" and not kind in GameData.MELEE_KINDS
		_swing(push, kind == "spell")
		_remote_swing.rpc(push, kind == "spell")


func aim_direction() -> Vector3:
	if _camera:
		return -_camera.global_basis.z
	return -global_basis.z


func _try_build(def: Dictionary) -> void:
	if _ghost_slot.is_empty():
		return
	if not _ghost_valid:
		_hint(_ghost_problem)
		return
	_next_action_time = _game_mode.clock + 0.25
	_game_mode.request(&"request_build", [equipped, _ghost_slot])


func _hint(text: String) -> void:
	if text != "" and _game_mode.clock >= _next_hint_time:
		_next_hint_time = _game_mode.clock + 1.5
		_game_mode.message_received.emit(text)


## The grid slot under the crosshair for the equipped piece.
func current_build_slot() -> Dictionary:
	if _camera == null or BuildGrid.kind_of(equipped) == "":
		return {}
	var from := _camera.global_position
	var dir := aim_direction()
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * (BuildGrid.REACH + 4.0), 1 | 4 | 16 | 32)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var point: Vector3
	aimed_piece = null
	if hit.is_empty():
		var flat := Vector3(dir.x, 0, dir.z).normalized()
		point = global_position + flat * 5.0
		point.y = Terrain.height(point.x, point.z)
	else:
		point = hit["position"] + hit["normal"] * 0.05
		var collider: Object = hit["collider"]
		if collider is Structure and (collider as Structure).team == team \
				and chest().distance_to(hit["position"]) <= BuildGrid.REACH:
			aimed_piece = collider
	return BuildGrid.slot_for(equipped, point, dir, global_position, build_turn)


@rpc("authority", "call_remote", "unreliable")
func _remote_swing(push: bool, spell := false) -> void:
	_swing(push, spell)


## Swing (melee) or push forward (bow, spell). Animates the body's hand for everyone
## and, for you, the first-person viewmodel.
func _swing(push: bool, spell := false) -> void:
	if Net.is_dedicated() or _body == null:
		return
	# The character's attack animation moves the arm (and the item in its hand).
	if _look:
		_look.play_action("cast" if spell else ("shoot" if push else "melee"))
	if push:
		if not spell:
			Sfx.play_at("bow", global_position, -4.0)
	else:
		Sfx.play_at("swing", global_position, -6.0)
	if _vm_hand:
		var vm := create_tween()
		if push:
			vm.tween_property(_vm_hand, "position:z", VM_HAND_POS.z - 0.25, 0.06)
			vm.tween_property(_vm_hand, "position:z", VM_HAND_POS.z, 0.2)
		else:
			vm.tween_property(_vm_hand, "rotation:x", -1.5, 0.08)
			vm.tween_property(_vm_hand, "rotation:x", VM_HAND_ROT.x, 0.2)


# --- Feedback ----------------------------------------------------------------------

func _on_damaged(amount: float) -> void:
	if Net.is_dedicated() or _body == null:
		return
	Sfx.play_at("hit", global_position)
	if _flash_material == null:
		_flash_material = Visuals.mat(Color(1, 1, 1, 0.75), 2.0)
	_look.flash(_flash_material)
	_look.play_action("hit")
	if _flash_tween:
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_interval(0.09)
	_flash_tween.tween_callback(func() -> void: _look.flash(null))
	# Floating damage number.
	var label := Label3D.new()
	label.text = str(roundi(amount))
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 56
	label.pixel_size = 0.006
	label.outline_size = 10
	label.modulate = Color(1, 0.85, 0.3) if not is_local() else Color(1, 0.3, 0.3)
	label.no_depth_test = true
	label.top_level = true
	add_child(label)
	label.global_position = global_position + Vector3(randf_range(-0.4, 0.4), 2.4, 0)
	var t := label.create_tween().set_parallel()
	t.tween_property(label, "global_position:y", label.global_position.y + 1.2, 0.8)
	t.tween_property(label, "modulate:a", 0.0, 0.8).set_delay(0.3)
	t.chain().tween_callback(label.queue_free)


func _on_death() -> void:
	if Net.is_dedicated() or _body == null:
		return
	Sfx.play_at("death", global_position)
	# A copy of the character plays its death animation where we fell.
	_look.spawn_corpse((get_parent().get_parent() as World).fx_root, _look.global_transform)


# --- Visuals ---------------------------------------------------------------------

func _build_visuals() -> void:
	var tc := GameData.team_color(team)
	_body = Node3D.new()
	add_child(_body)
	_look = CharacterVisual.new()
	_body.add_child(_look)
	_look.setup(peer_id, team)
	_hand = Node3D.new()
	(_look.right_hand if _look.right_hand else _body).add_child(_hand)
	_shield_mesh = Node3D.new()
	(_look.left_hand if _look.left_hand else _body).add_child(_shield_mesh)

	var label := Label3D.new()
	label.text = display_name
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 40
	label.pixel_size = 0.006
	label.outline_size = 8
	label.modulate = tc.lerp(Color.WHITE, 0.5)
	label.position.y = 2.4
	label.visible = not is_local()  # your own name would float in front of the camera
	_body.add_child(label)
	_speaking_label = Label3D.new()
	_speaking_label.text = "((( talking )))"
	_speaking_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_speaking_label.font_size = 28
	_speaking_label.pixel_size = 0.006
	_speaking_label.outline_size = 6
	_speaking_label.modulate = Color(0.6, 1.0, 0.6)
	_speaking_label.position.y = 2.7
	_speaking_label.visible = false
	_body.add_child(_speaking_label)

	_horse = _make_horse(tc)
	add_child(_horse)

	_refresh_weapon()
	_refresh_mount()
	_refresh_shield()
	visible = alive
	if is_local():
		_set_layer(_body, BODY_LAYER)  # your own body is hidden in first person


func _refresh_weapon() -> void:
	if _hand == null or Net.is_dedicated():
		return
	var kind: String = GameData.item(equipped).get("kind", "fists")
	if _look:
		_look.held_item = equipped
	if _weapon:
		_weapon.queue_free()
		_weapon = null
	if kind != "fists":
		_weapon = CharacterVisual.make_held(equipped, team)
		_hand.add_child(_weapon)
		if is_local():
			_set_layer(_weapon, BODY_LAYER)
	if _vm_hand:
		if _vm_weapon:
			_vm_weapon.queue_free()
			_vm_weapon = null
		if kind != "fists":
			_vm_weapon = CharacterVisual.make_held(equipped, team, true)
			_vm_hand.add_child(_vm_weapon)


## A simple low-poly horse with a team-colored saddle blanket.
func _make_horse(tc: Color) -> Node3D:
	var horse := Node3D.new()
	var coat := Color(0.42, 0.28, 0.16)
	var dark := Color(0.2, 0.14, 0.09)
	horse.add_child(Visuals.box(Vector3(0.7, 0.75, 1.7), coat, Vector3(0, 1.15, 0)))
	var neck := Visuals.box(Vector3(0.38, 0.85, 0.4), coat, Vector3(0, 1.6, -0.85))
	neck.rotation.x = -0.6
	horse.add_child(neck)
	horse.add_child(Visuals.box(Vector3(0.32, 0.32, 0.65), coat, Vector3(0, 1.95, -1.25)))
	horse.add_child(Visuals.box(Vector3(0.1, 0.5, 0.42), dark, Vector3(0, 1.85, -0.85)))  # mane
	for x in [-0.25, 0.25]:
		for z in [-0.65, 0.65]:
			horse.add_child(Visuals.box(Vector3(0.16, 0.85, 0.16), coat, Vector3(x, 0.42, z)))
			horse.add_child(Visuals.box(Vector3(0.18, 0.12, 0.18), dark, Vector3(x, 0.06, z)))
	var tail := Visuals.box(Vector3(0.1, 0.6, 0.1), dark, Vector3(0, 1.1, 0.95))
	tail.rotation.x = 0.4
	horse.add_child(tail)
	horse.add_child(Visuals.box(Vector3(0.76, 0.06, 0.7), tc, Vector3(0, 1.54, 0.05)))
	return horse


func _refresh_mount() -> void:
	if _horse == null:
		return
	_horse.visible = mounted
	_body.position.y = 1.3 if mounted else 0.0  # sitting on the horse's back


func _build_camera() -> void:
	_pivot = Node3D.new()
	_pivot.position = Vector3(0, EYE_HEIGHT, 0)
	add_child(_pivot)
	_arm = SpringArm3D.new()
	_arm.collision_mask = 1 | 4
	_arm.add_excluded_object(get_rid())
	_pivot.add_child(_arm)
	_camera = Camera3D.new()
	_camera.fov = 80.0
	_camera.near = 0.05
	_camera.far = 700.0
	_arm.add_child(_camera)
	_camera.current = true
	# First-person hands: weapon on the right, shield on the left.
	_viewmodel = Node3D.new()
	_camera.add_child(_viewmodel)
	_vm_hand = Node3D.new()
	_vm_hand.position = VM_HAND_POS
	_vm_hand.rotation = VM_HAND_ROT
	_vm_hand.scale = Vector3.ONE * 0.27
	_viewmodel.add_child(_vm_hand)
	_vm_shield = Node3D.new()
	_viewmodel.add_child(_vm_shield)
	_refresh_weapon()
	_refresh_shield()
	set_third_person(false)


func set_third_person(on: bool) -> void:
	third_person = on
	if _arm == null:
		return
	_arm.spring_length = 4.0 if on else 0.0
	_arm.position = Vector3(0.7, 0.3, 0) if on else Vector3.ZERO
	_viewmodel.visible = not on
	if on:
		_camera.cull_mask |= BODY_LAYER
	else:
		_camera.cull_mask &= ~BODY_LAYER


func _set_layer(node: Node, layer: int) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = layer
	for c in node.get_children():
		_set_layer(c, layer)


func _best_shield() -> String:
	if _game_mode == null:
		return ""
	for id in ["iron_shield", "wooden_shield"]:
		if int(_game_mode.my_inventory.get(id, 0)) > 0:
			return id
	return ""


## Shield on the left arm (the "holding-left" animation raises it when blocking), and
## in first person on the left of the view.
func _refresh_shield() -> void:
	if _shield_mesh:
		for c in _shield_mesh.get_children():
			c.queue_free()
		if shield_item != "":
			var model := CharacterVisual.make_held(shield_item, team)
			_shield_mesh.add_child(model)
			if is_local():
				_set_layer(model, BODY_LAYER)
	if _vm_shield:
		for c in _vm_shield.get_children():
			c.queue_free()
		_vm_shield.visible = shield_item != ""
		if shield_item != "":
			_vm_shield.add_child(CharacterVisual.make_held(shield_item, team, true))
		_vm_shield.position = Vector3(-0.1, -0.12, -0.5) if blocking else Vector3(-0.4, -0.34, -0.6)
		_vm_shield.rotation = Vector3.ZERO if blocking else Vector3(0.25, 0.7, 0.1)
		_vm_shield.scale = Vector3.ONE * (0.4 if blocking else 0.26)


func _update_ghost() -> void:
	if not is_local():
		return
	var showing := alive and build_mode and BuildGrid.kind_of(equipped) != ""
	if not showing:
		if _ghost:
			_ghost.visible = false
		_ghost_slot = {}
		aimed_piece = null
		return
	if _ghost == null or _ghost_item != equipped:
		if _ghost:
			_ghost.queue_free()
		_ghost_item = equipped
		_ghost = Structure.make_ghost(equipped, team, _ghost_ok)
		_ghost.top_level = true
		add_child(_ghost)
	_ghost_slot = current_build_slot()
	var kind := BuildGrid.kind_of(equipped)
	_ghost.visible = true
	var ghost_xf := BuildGrid.transform_for(kind, _ghost_slot)
	if kind == "vehicle":
		ghost_xf.origin.y = Terrain.height(ghost_xf.origin.x, ghost_xf.origin.z)
	_ghost.global_transform = ghost_xf
	_ghost_problem = _world.placement_problem(equipped, _ghost_slot)
	if _ghost_problem == "" and chest().distance_to(BuildGrid.center_of(kind, _ghost_slot)) > BuildGrid.REACH:
		_ghost_problem = "Too far away."
	if _ghost_problem == "":
		var skills: Dictionary = _game_mode.my_stats.get("skills", {})
		var recipe := GameData.build_cost(GameData.item(equipped)["recipe"], int(skills.get("mason", 0)))
		for res: String in recipe:
			if int(_game_mode.my_inventory.get(res, 0)) < int(recipe[res]):
				_ghost_problem = "Not enough resources: needs %s." % GameData.cost_text(recipe)
				break
	var valid := _ghost_problem == ""
	if valid != _ghost_valid or _ghost.get_child(0).material_override != (_ghost_ok if valid else _ghost_bad):
		for c in _ghost.get_children():
			(c as MeshInstance3D).material_override = _ghost_ok if valid else _ghost_bad
	_ghost_valid = valid
