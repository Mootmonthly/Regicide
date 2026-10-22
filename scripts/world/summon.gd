class_name Summon
extends CharacterBody3D
## A spectral warrior from the Spectral Warriors spell: a ghostly, team-coloured knight
## with a sword. The server runs it: it charges the nearest enemy (player or enemy
## warrior) within its hunting range, follows its summoner when there's nothing to
## fight, and fades away when its time is up. Enemies can cut it down.
## Spawned on every peer by World's summon spawner; position and health replicate.

const SPEED := 6.2
const GRAVITY := 18.0
const REACH := 2.0
const FOLLOW_DISTANCE := 4.0
const RETARGET_INTERVAL := 0.5

var uid := 0
var team := 0
var owner_peer := 0  ## who summoned it (gets the credit for its kills)
var spell := "spectral_warriors"
var max_health := 60.0
var health := 60.0
var expires_at := 0.0  ## GameMode clock
var sync_yaw := 0.0
var sync_pos := Vector3.ZERO  ## replicated; clients glide toward it

var _def: Dictionary
var _target: Node3D
var _retarget := 0.0
var _next_attack := 0.0
var _look: CharacterVisual
var _last_pos := Vector3.ZERO
var _anim_speed := 0.0
var _game_mode: GameMode


func setup(data: Dictionary) -> void:
	uid = data["uid"]
	name = "Summon%d" % uid
	team = data["team"]
	owner_peer = data["owner"]
	expires_at = data["expires"]
	position = data["pos"]
	sync_pos = position
	_def = GameData.item(spell)
	max_health = float(_def["warrior_health"])
	health = max_health
	collision_layer = 0  # nothing needs to collide with it
	collision_mask = 1 | 4 | 8 | GameData.gate_layer(1 - team)
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.7
	shape.shape = capsule
	shape.position.y = 0.85
	add_child(shape)
	# Replicate where it is and how hurt it is (the server simulates it).
	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	var config := SceneReplicationConfig.new()
	for prop in [":sync_pos", ":sync_yaw", ":health"]:
		config.add_property(NodePath(prop))
		config.property_set_replication_mode(NodePath(prop), SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	sync.replication_config = config
	sync.replication_interval = 0.05
	add_child(sync)


func _ready() -> void:
	_game_mode = (get_parent().get_parent() as World).game_mode
	_last_pos = position
	if not Net.is_dedicated():
		_build_visual()


func _build_visual() -> void:
	_look = CharacterVisual.new()
	add_child(_look)
	_look.setup(owner_peer, team)
	_look.held_item = "iron_sword"
	_look.right_hand.add_child(CharacterVisual.make_held("iron_sword", team))
	# Ghostly: see-through, glowing in the team colour.
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow.albedo_color = GameData.team_color(team).lightened(0.3) * Color(1, 1, 1, 0.45)
	for n in _look.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		g.transparency = 0.45
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if g is MeshInstance3D:
			(g as MeshInstance3D).material_overlay = glow
	var light := OmniLight3D.new()
	light.light_color = GameData.team_color(team).lightened(0.4)
	light.light_energy = 0.8
	light.omni_range = 3.5
	light.position.y = 1.2
	add_child(light)
	# Rise out of the ground.
	_look.scale = Vector3(1, 0.05, 1)
	_look.create_tween().tween_property(_look, "scale", Vector3.ONE, 0.5)


func _physics_process(delta: float) -> void:
	if _look:
		var moved := (position - _last_pos) / maxf(delta, 0.0001)
		_last_pos = position
		_anim_speed = lerpf(_anim_speed, Vector2(moved.x, moved.z).length(), 0.3)
		_look.update_motion(_anim_speed, 0.0, true, false, false)
	if not multiplayer.is_server():
		var t := clampf(delta * 12.0, 0.0, 1.0)
		position = sync_pos if position.distance_to(sync_pos) > 6.0 else position.lerp(sync_pos, t)
		rotation.y = lerp_angle(rotation.y, sync_yaw, t)
		return
	if _game_mode == null:
		return
	var gm := _game_mode
	if gm.clock >= expires_at or gm.match_over:
		gm.remove_summon(self)
		return
	_retarget -= delta
	if _retarget <= 0.0 or not _valid_target(_target):
		_retarget = RETARGET_INTERVAL
		_target = gm.summon_target(self, float(_def["hunt_range"]))
	var goal := Vector3.INF
	var stop := 0.0
	if _target:
		goal = _target.global_position
		stop = REACH * 0.8
	else:
		var summoner := gm.world.get_player(owner_peer)
		if summoner and summoner.alive:
			goal = summoner.sync_pos
			stop = FOLLOW_DISTANCE
	var to := Vector3.ZERO if goal == Vector3.INF else Vector3(goal.x - position.x, 0, goal.z - position.z)
	var dir := Vector3.ZERO
	if to.length() > stop:
		dir = to.normalized()
	if to.length() > 0.1:
		sync_yaw = atan2(-to.x, -to.z)
		rotation.y = sync_yaw
	velocity.x = dir.x * SPEED
	velocity.z = dir.z * SPEED
	if is_on_floor():
		velocity.y = -1.0
		if dir != Vector3.ZERO and is_on_wall():
			velocity.y = 7.0  # hop over small obstacles
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()
	if position.y < Terrain.height(position.x, position.z) - 1.0:
		position.y = Terrain.height(position.x, position.z) + 0.2
	sync_pos = position
	if _target and gm.clock >= _next_attack and GameData.flat_distance(position, _target.global_position) <= REACH \
			and absf(position.y - _target.global_position.y) < 1.8:
		_next_attack = gm.clock + float(_def["warrior_attack_interval"])
		swing.rpc()
		gm.summon_hit(self, _target)


func _valid_target(t: Node3D) -> bool:
	if t == null or not is_instance_valid(t) or t.is_queued_for_deletion():
		return false
	if t is Player:
		return (t as Player).alive
	return true


## Everyone sees the sword swing.
@rpc("authority", "call_local", "unreliable")
func swing() -> void:
	if _look:
		_look.play_action("melee")
		Sfx.play_at("swing", global_position, -8.0)


func chest() -> Vector3:
	return global_position + Vector3(0, 1.0, 0)


## Fade into the ground (clients), called just before the spawner removes it.
@rpc("authority", "call_local", "reliable")
func vanish_fx() -> void:
	var world := get_parent().get_parent() as World
	if world and not Net.is_dedicated():
		world.debris(chest(), GameData.team_color(team).lightened(0.4), 10)
