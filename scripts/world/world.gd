class_name World
extends Node3D
## Root of a match. Builds the static arena, owns the spawners, generates resource
## nodes from the server's seed, and relays resource changes and visual effects.

## Loaded at runtime (not preloaded) because player.gd refers back to World.
const PLAYER_SCENE_PATH := "res://scenes/player.tscn"

var map_seed := 0
var resource_nodes: Array[ResourceNode] = []
var crown_nodes: Array[Crown] = []
var hud: Hud
var _player_scene: PackedScene

@onready var game_mode: GameMode = $GameMode
@onready var player_spawner: MultiplayerSpawner = $PlayerSpawner
@onready var structure_spawner: MultiplayerSpawner = $StructureSpawner
@onready var players_root: Node3D = $Players
@onready var structures_root: Node3D = $Structures
@onready var resources_root: Node3D = $Resources
@onready var fx_root: Node3D = $Fx


func _ready() -> void:
	_build_arena()
	for t in GameData.TEAM_COUNT:
		var crown := Crown.new()
		crown.team = t
		crown.state = game_mode.crowns[t]
		crown.world = self
		$Crowns.add_child(crown)
		crown_nodes.append(crown)

	player_spawner.spawn_function = _spawn_player
	structure_spawner.spawn_function = _spawn_structure

	if not Net.is_dedicated():
		hud = Hud.new()
		add_child(hud)

	var err := Net.start()
	if err != OK:
		Net.leave("Could not start networking: %s" % error_string(err))
		return
	if Net.is_server_mode():
		map_seed = randi_range(1, 999_999)
		generate(map_seed)
		game_mode.server_start()


# --- Lookups ---------------------------------------------------------------

func get_player(peer_id: int) -> Player:
	return players_root.get_node_or_null(str(peer_id)) as Player


func get_players() -> Array[Player]:
	var out: Array[Player] = []
	for c in players_root.get_children():
		if c is Player and not c.is_queued_for_deletion():
			out.append(c)
	return out


func get_structures() -> Array[Structure]:
	var out: Array[Structure] = []
	for c in structures_root.get_children():
		if c is Structure and not c.is_queued_for_deletion():
			out.append(c)
	return out


func local_player() -> Player:
	return get_player(multiplayer.get_unique_id())


# --- Spawning (runs on every peer with the same data) ---------------------

func _spawn_player(data: Dictionary) -> Node:
	if _player_scene == null:
		_player_scene = load(PLAYER_SCENE_PATH)
	var p: Player = _player_scene.instantiate()
	p.peer_id = data["peer_id"]
	p.team = data["team"]
	p.display_name = data["name"]
	p.is_bot = data.get("bot", false)
	p.name = str(p.peer_id)
	p.position = data["pos"]
	return p


func _spawn_structure(data: Dictionary) -> Node:
	var s := Structure.new()
	s.setup(data)
	return s


# --- Resource nodes ----------------------------------------------------------

func generate(seed_value: int) -> void:
	if not resource_nodes.is_empty():
		return
	map_seed = seed_value
	var entries := MapGenerator.generate(seed_value)
	for i in entries.size():
		var node := ResourceNode.new()
		node.setup(i, entries[i]["type"], entries[i]["pos"])
		resources_root.add_child(node)
		resource_nodes.append(node)


## Server only: change a node's remaining amount on every peer.
func set_resource_amount(idx: int, value: int) -> void:
	_res_amount.rpc(idx, value)


func reset_resources() -> void:
	_res_reset.rpc()


func resource_snapshot() -> Dictionary:
	var out := {}
	for n in resource_nodes:
		if n.amount != n.max_amount:
			out[n.index] = n.amount
	return out


func apply_resource_snapshot(snapshot: Dictionary) -> void:
	for idx in snapshot:
		if idx >= 0 and idx < resource_nodes.size():
			resource_nodes[idx].set_amount(snapshot[idx])


@rpc("authority", "call_local", "reliable")
func _res_amount(idx: int, value: int) -> void:
	# Updates that arrive before this client has generated the map are covered by
	# the snapshot in the welcome message.
	if idx >= 0 and idx < resource_nodes.size():
		resource_nodes[idx].set_amount(value)


@rpc("authority", "call_local", "reliable")
func _res_reset() -> void:
	for n in resource_nodes:
		n.set_amount(n.max_amount)


# --- Effects (cosmetic, fire-and-forget) -------------------------------------

@rpc("authority", "call_local", "unreliable")
func structure_health(structure_name: String, fraction: float) -> void:
	var s := structures_root.get_node_or_null(structure_name) as Structure
	if s:
		s.set_health_fraction(fraction)


## An arrow following the same arc the server simulated.
@rpc("authority", "call_local", "unreliable")
func fx_arrow(from: Vector3, velocity: Vector3, duration: float) -> void:
	if Net.is_dedicated():
		return
	var m := BoxMesh.new()
	m.size = Vector3(0.05, 0.05, 0.8)
	var arrow := Visuals.mesh_instance(m, Color(0.85, 0.8, 0.65))
	fx_root.add_child(arrow)
	arrow.global_position = from
	var g := Vector3(0, -GameData.ARROW_GRAVITY, 0)
	var t := arrow.create_tween()
	t.tween_method(func(time: float) -> void:
		var pos := from + velocity * time + 0.5 * g * time * time
		var vel := velocity + g * time
		arrow.global_position = pos
		if vel.length_squared() > 0.01:
			arrow.look_at(pos + vel), 0.0, duration, duration)
	t.tween_interval(1.5)  # leave it stuck in the ground for a moment
	t.tween_callback(arrow.queue_free)


## Little flying chips when something is hit.
func debris(pos: Vector3, color: Color, count := 4) -> void:
	if Net.is_dedicated():
		return
	for i in count:
		var chip := Visuals.box(Vector3.ONE * randf_range(0.1, 0.2), color)
		fx_root.add_child(chip)
		chip.global_position = pos
		var dir := Vector3(randf_range(-1, 1), randf_range(0.6, 1.4), randf_range(-1, 1))
		var t := chip.create_tween().set_parallel()
		t.tween_property(chip, "global_position", pos + dir * 1.2, 0.35).set_ease(Tween.EASE_OUT)
		t.tween_property(chip, "rotation", Vector3(randf() * 6, randf() * 6, 0), 0.35)
		t.chain().tween_property(chip, "global_position:y", 0.05, 0.25).set_ease(Tween.EASE_IN)
		t.chain().tween_interval(0.6)
		t.chain().tween_callback(chip.queue_free)

@rpc("authority", "call_local", "unreliable")
func fx_bolt(from: Vector3, to: Vector3) -> void:
	if Net.is_dedicated():
		return
	var m := BoxMesh.new()
	m.size = Vector3(0.08, 0.08, 1.2)
	_projectile(Visuals.mesh_instance(m, Color(0.35, 0.25, 0.15)), from, to, 60.0)
	Sfx.play_at("bolt", from)


@rpc("authority", "call_local", "unreliable")
func fx_fireball(from: Vector3, to: Vector3, radius: float) -> void:
	if Net.is_dedicated():
		return
	var s := SphereMesh.new()
	s.radius = 0.35
	s.height = 0.7
	var travel := _projectile(Visuals.mesh_instance(s, Color(1.0, 0.5, 0.1), Vector3.ZERO, 3.0), from, to, 35.0)
	Sfx.play_at("fireball", from)
	await get_tree().create_timer(travel).timeout
	Sfx.play_at("boom", to, 4.0)
	var boom_mesh := SphereMesh.new()
	boom_mesh.radius = 1.0
	boom_mesh.height = 2.0
	var boom := MeshInstance3D.new()
	boom.mesh = boom_mesh
	var mat := Visuals.mat(Color(1.0, 0.45, 0.1, 0.6), 2.0).duplicate() as StandardMaterial3D
	boom.material_override = mat
	fx_root.add_child(boom)
	boom.global_position = to
	boom.scale = Vector3.ONE * 0.3
	var t := boom.create_tween().set_parallel()
	t.tween_property(boom, "scale", Vector3.ONE * radius, 0.35)
	t.tween_property(mat, "albedo_color:a", 0.0, 0.35)
	t.chain().tween_callback(boom.queue_free)


## Moves a mesh from -> to and frees it. Returns the travel time.
func _projectile(mi: MeshInstance3D, from: Vector3, to: Vector3, speed: float) -> float:
	fx_root.add_child(mi)
	mi.global_position = from
	if from.distance_to(to) > 0.01:
		mi.look_at(to)
	var duration := maxf(from.distance_to(to) / speed, 0.05)
	var t := mi.create_tween()
	t.tween_property(mi, "global_position", to, duration)
	t.tween_callback(mi.queue_free)
	return duration


# --- Static arena --------------------------------------------------------------

func _build_arena() -> void:
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.35, 0.55, 0.85)
	sky_mat.sky_horizon_color = Color(0.75, 0.82, 0.9)
	sky_mat.ground_horizon_color = Color(0.5, 0.55, 0.45)
	sky.sky_material = sky_mat
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.6
	env.environment = environment
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 80.0
	add_child(sun)

	var w := GameData.MAP_WIDTH
	var l := GameData.MAP_LENGTH
	# Ground (extends past the walls so the edge never shows).
	add_child(Visuals.static_box(Vector3(w + 60, 1, l + 60), Color(0.36, 0.55, 0.27), Vector3(0, -0.5, 0)))
	# Boundary palisade.
	var wall_color := Color(0.4, 0.3, 0.2)
	add_child(Visuals.static_box(Vector3(w, 6, 1), wall_color, Vector3(0, 3, l * 0.5 + 0.5)))
	add_child(Visuals.static_box(Vector3(w, 6, 1), wall_color, Vector3(0, 3, -l * 0.5 - 0.5)))
	add_child(Visuals.static_box(Vector3(1, 6, l), wall_color, Vector3(w * 0.5 + 0.5, 3, 0)))
	add_child(Visuals.static_box(Vector3(1, 6, l), wall_color, Vector3(-w * 0.5 - 0.5, 3, 0)))
	# Center line.
	add_child(Visuals.box(Vector3(w, 0.02, 0.6), Color(0.85, 0.8, 0.6), Vector3(0, 0.01, 0)))

	for t in GameData.TEAM_COUNT:
		var tc := GameData.team_color(t)
		var side := GameData.team_sign(t)
		var crown_pos := GameData.crown_pos(t)
		# Tinted base courtyard.
		add_child(Visuals.box(Vector3(GameData.BASE_CLEAR_RADIUS * 2, 0.02, 60), tc.lerp(Color(0.36, 0.55, 0.27), 0.82), Vector3(0, 0.01, side * (GameData.BASE_Z + 10))))
		# No-build ring around the pedestal.
		var ring := CylinderMesh.new()
		ring.top_radius = GameData.NO_BUILD_RADIUS
		ring.bottom_radius = GameData.NO_BUILD_RADIUS
		ring.height = 0.03
		add_child(Visuals.mesh_instance(ring, tc.lerp(Color.WHITE, 0.5), Vector3(crown_pos.x, 0.02, crown_pos.z)))
		# Pedestal.
		var ped := CylinderMesh.new()
		ped.top_radius = 0.9
		ped.bottom_radius = 1.2
		ped.height = crown_pos.y
		add_child(Visuals.mesh_instance(ped, Color(0.75, 0.72, 0.65), Vector3(crown_pos.x, crown_pos.y * 0.5, crown_pos.z)))
		# Banner poles at the spawn.
		for x in [-18.0, 18.0]:
			add_child(Visuals.box(Vector3(0.2, 7, 0.2), Color(0.3, 0.25, 0.2), Vector3(x, 3.5, side * GameData.SPAWN_Z)))
			add_child(Visuals.box(Vector3(0.05, 2.5, 1.6), tc, Vector3(x, 5.5, side * GameData.SPAWN_Z + 0.9)))
