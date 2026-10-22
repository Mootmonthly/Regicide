class_name World
extends Node3D
## Root of a match. Builds the static arena, owns the spawners, generates resource
## nodes from the server's seed, and relays resource changes and visual effects.

## Loaded at runtime (not preloaded) because player.gd refers back to World.
const PLAYER_SCENE_PATH := "res://scenes/player.tscn"

var map_seed := 0
var resource_nodes: Array[ResourceNode] = []
## Batched tree drawing: node index -> [[MultiMesh, instance, Transform3D], ...]
var _tree_instances: Dictionary = {}
var _stump_instances: Dictionary = {}
var crown_nodes: Array[Crown] = []
var hud: Hud
## Every standing building piece by its BuildGrid slot key (kept on every peer).
var pieces: Dictionary = {}
var ladders: Array[Structure] = []
## False on clients until the server's map seed arrives and the terrain exists.
var terrain_ready := false
## Piece states from the welcome snapshot whose pieces haven't spawned here yet.
var pending_piece_states: Dictionary = {}
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


# --- Building ----------------------------------------------------------------

func register_piece(s: Structure) -> void:
	if s.is_vehicle():
		return  # vehicles move; they don't hold a grid slot
	pieces[s.slot_key] = s
	if s.is_ladder():
		ladders.append(s)


func unregister_piece(s: Structure) -> void:
	if pieces.get(s.slot_key) == s:
		pieces.erase(s.slot_key)
	ladders.erase(s)


## Siege engines sit on dry, fairly level ground with nothing in the way.
func _vehicle_problem(item_id: String, slot: Dictionary, check_players: bool) -> String:
	var xf := BuildGrid.transform_for("vehicle", slot)
	xf.origin.y = Terrain.height(xf.origin.x, xf.origin.z)
	if xf.origin.y < Terrain.WATER_LEVEL:
		return "Siege engines can't go in water."
	if absf(BuildGrid.level_y(slot["level"]) - xf.origin.y) > 2.5:
		return "Put it on the ground."
	var box := xf * Structure.local_bounds(item_id)
	box = box.grow(-0.15)
	for s in get_structures():
		if s.is_trap() or s.is_ladder():
			continue
		if box.intersects(s.global_transform * s.bounds):
			return "Something is in the way."
	if check_players:
		for p in get_players():
			if p.alive and box.intersects(AABB(p.sync_pos + Vector3(-0.35, 0.1, -0.35), Vector3(0.7, 1.7, 0.7))):
				return "Someone is in the way."
	return ""


## Nearest drawbridge or catapult of `team` within reach of p, or null.
func interactable_near(p: Vector3, team: int, reach := 3.5) -> Structure:
	var best: Structure = null
	var best_d := reach
	for s in get_structures():
		if s.team != team or not s.is_interactable():
			continue
		var d := s.closest_point(p + Vector3(0, 1, 0)).distance_to(p + Vector3(0, 1, 0))
		if d <= best_d:
			best = s
			best_d = d
	return best


## Non-default piece states (lowered drawbridges, moved rams) for late joiners.
func piece_states() -> Dictionary:
	var out := {}
	for s in get_structures():
		var st := s.get_state()
		if not st.is_empty():
			out[String(s.name)] = st
	return out


func apply_piece_states(states: Dictionary) -> void:
	for n: String in states:
		var s := structures_root.get_node_or_null(n) as Structure
		if s:
			s.apply_state(states[n])
		else:
			pending_piece_states[n] = states[n]


@rpc("authority", "call_local", "reliable")
func piece_open(structure_name: String, value: bool) -> void:
	var s := structures_root.get_node_or_null(structure_name) as Structure
	if s:
		s.set_open(value)


@rpc("authority", "call_remote", "unreliable_ordered")
func vehicle_pose(structure_name: String, pos: Vector3, yaw: float) -> void:
	var s := structures_root.get_node_or_null(structure_name) as Structure
	if s:
		s.set_pose_target(pos, yaw)


func ladder_at(p: Vector3) -> Structure:
	for l in ladders:
		if not l.is_queued_for_deletion() and l.ladder_contains(p):
			return l
	return null


## Why a piece can't go in a slot, or "" if it can. Checks bounds, the crown no-build
## zone, occupancy, structural support, and (optionally) players standing in the way.
func placement_problem(item_id: String, slot: Dictionary, check_players := true) -> String:
	var kind := BuildGrid.kind_of(item_id)
	if kind == "":
		return "That can't be built."
	if slot["level"] < BuildGrid.MIN_LEVEL or slot["level"] > BuildGrid.MAX_LEVEL:
		return "Too high to build."
	var center := BuildGrid.center_of(kind, slot)
	if not GameData.can_build_at(center):
		return "You can't build there."
	var key := BuildGrid.key(kind, slot)
	var existing: Structure = pieces.get(key)
	if existing and not existing.is_queued_for_deletion():
		return "Something is already built there."
	if BuildGrid.is_buried(kind, slot):
		return "That would be underground."
	if kind == "vehicle":
		return _vehicle_problem(item_id, slot, check_players)
	var has := func(k: String) -> bool:
		var p: Structure = pieces.get(k)
		return p != null and not p.is_queued_for_deletion() and BuildGrid.supports(p.kind)
	if not BuildGrid.is_supported(kind, slot, has):
		return "That needs support: build it on the ground, a floor, or a wall."
	if check_players and kind != "ladder" and kind != "free":
		var box := BuildGrid.transform_for(kind, slot) * Structure.local_bounds(item_id)
		box = box.grow(-0.1)
		for p in get_players():
			if p.alive and box.intersects(AABB(p.sync_pos + Vector3(-0.35, 0.1, -0.35), Vector3(0.7, 1.7, 0.7))):
				return "Someone is in the way."
	return ""


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
	Terrain.setup(seed_value)
	_build_terrain()
	terrain_ready = true
	var entries := MapGenerator.generate(seed_value)
	for i in entries.size():
		var node := ResourceNode.new()
		node.setup(i, entries[i]["type"], entries[i]["pos"])
		resources_root.add_child(node)
		resource_nodes.append(node)
	_build_forest()


## Draws every tree with one MultiMesh per part (trunks, pine tiers, oak crowns...)
## instead of thousands of separate meshes.
func _build_forest() -> void:
	if Net.is_dedicated():
		return
	var groups := {}  # "mesh|color" -> {mesh, color, xfs: [], owners: [[index, is_stump]]}
	for n in resource_nodes:
		if n.res_type != "wood":
			continue
		var info := ResourceNode.tree_parts(n.index)
		var base := Transform3D(Basis(Vector3.UP, n.rotation.y), n.position)
		var entries: Array = info["parts"].duplicate()
		entries.append(info["stump"])
		for k in entries.size():
			var part: Array = entries[k]
			var key := "%s|%s" % [part[0], (part[1] as Color).to_html()]
			if not groups.has(key):
				groups[key] = {"mesh": part[0], "color": part[1], "xfs": [], "owners": []}
			groups[key]["xfs"].append(base * (part[2] as Transform3D))
			groups[key]["owners"].append([n.index, k == entries.size() - 1])
	for key: String in groups:
		var g: Dictionary = groups[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = ResourceNode.mesh_for(g["mesh"])
		mm.instance_count = g["xfs"].size()
		for i in mm.instance_count:
			var xf: Transform3D = g["xfs"][i]
			var owner: Array = g["owners"][i]
			var stump: bool = owner[1]
			var record := [mm, i, xf]
			var table := _stump_instances if stump else _tree_instances
			if not table.has(owner[0]):
				table[owner[0]] = []
			table[owner[0]].append(record)
			mm.set_instance_transform(i, _hidden(xf) if stump else xf)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = Visuals.mat(g["color"])
		resources_root.add_child(mmi)


static func _hidden(xf: Transform3D) -> Transform3D:
	return Transform3D(Basis().scaled(Vector3.ZERO), xf.origin)


## Show a tree standing, or felled (stump only).
func set_tree_standing(index: int, standing: bool) -> void:
	for r: Array in _tree_instances.get(index, []):
		(r[0] as MultiMesh).set_instance_transform(r[1], r[2] if standing else _hidden(r[2]))
	for r: Array in _stump_instances.get(index, []):
		(r[0] as MultiMesh).set_instance_transform(r[1], _hidden(r[2]) if standing else r[2])


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


@rpc("authority", "call_local", "unreliable")
func fx_repair(pos: Vector3) -> void:
	if Net.is_dedicated():
		return
	Sfx.play_at("repair", pos)
	debris(pos, Color(0.95, 0.85, 0.4), 5)


@rpc("authority", "call_local", "unreliable")
func fx_ram(pos: Vector3) -> void:
	if Net.is_dedicated():
		return
	Sfx.play_at("ram", pos, 4.0)
	debris(pos, Color(0.5, 0.4, 0.3), 8)


## A catapult boulder flying the arc the server simulated, then smashing.
@rpc("authority", "call_local", "unreliable")
func fx_boulder(catapult_name: String, from: Vector3, velocity: Vector3, duration: float, radius: float) -> void:
	if Net.is_dedicated():
		return
	var cat := structures_root.get_node_or_null(catapult_name) as Structure
	if cat:
		cat.play_fire()
	Sfx.play_at("catapult", from)
	var s := SphereMesh.new()
	s.radius = 0.45
	s.height = 0.9
	s.radial_segments = 8
	s.rings = 4
	var rock := Visuals.mesh_instance(s, Color(0.5, 0.5, 0.52))
	fx_root.add_child(rock)
	rock.global_position = from
	var g := Vector3(0, -GameData.ARROW_GRAVITY, 0)
	var t := rock.create_tween()
	t.tween_method(func(time: float) -> void:
		rock.global_position = from + velocity * time + 0.5 * g * time * time, 0.0, duration, duration)
	t.tween_callback(func() -> void:
		var hit := rock.global_position
		rock.queue_free()
		Sfx.play_at("boom", hit, 6.0)
		debris(hit + Vector3(0, 0.5, 0), Color(0.5, 0.5, 0.52), 10))


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


# --- Terrain ---------------------------------------------------------------------

func _build_terrain() -> void:
	var size := Terrain.sample_size()
	var body := StaticBody3D.new()
	body.name = "Terrain"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var hm := HeightMapShape3D.new()
	hm.map_width = size.x
	hm.map_depth = size.y
	# The shape is scaled 2x to match the 2 m sample spacing, so heights are halved.
	var data := PackedFloat32Array()
	data.resize(size.x * size.y)
	for iz in size.y:
		for ix in size.x:
			data[iz * size.x + ix] = Terrain.sample(ix, iz) / Terrain.SPACING
	hm.map_data = data
	shape.shape = hm
	shape.scale = Vector3.ONE * Terrain.SPACING
	body.add_child(shape)
	add_child(body)
	if Net.is_dedicated():
		return

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var x0 := -GameData.MAP_WIDTH * 0.5
	var z0 := -GameData.MAP_LENGTH * 0.5
	for iz in size.y - 1:
		for ix in size.x - 1:
			var quad := [Vector2i(ix, iz), Vector2i(ix + 1, iz), Vector2i(ix + 1, iz + 1), Vector2i(ix, iz + 1)]
			for k in [0, 1, 2, 0, 2, 3]:
				var g: Vector2i = quad[k]
				var v := Vector3(x0 + g.x * Terrain.SPACING, Terrain.sample(g.x, g.y), z0 + g.y * Terrain.SPACING)
				st.set_color(_ground_color(g.x, g.y, v))
				st.add_vertex(v)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mi.material_override = mat
	add_child(mi)

	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(GameData.MAP_WIDTH, GameData.MAP_LENGTH)
	water.mesh = plane
	var water_mat := StandardMaterial3D.new()
	water_mat.albedo_color = Color(0.2, 0.45, 0.75, 0.75)
	water_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water_mat.roughness = 0.15
	water_mat.metallic_specular = 0.8
	water.material_override = water_mat
	water.position.y = Terrain.WATER_LEVEL
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)


func _ground_color(ix: int, iz: int, v: Vector3) -> Color:
	var slope := maxf(absf(Terrain.sample(ix + 1, iz) - Terrain.sample(ix - 1, iz)),
		absf(Terrain.sample(ix, iz + 1) - Terrain.sample(ix, iz - 1))) / (2.0 * Terrain.SPACING)
	var grass := Color(0.27, 0.45, 0.2).lerp(Color(0.4, 0.52, 0.27), clampf(v.y / 12.0, 0.0, 1.0))
	var c := grass
	if v.y < Terrain.WATER_LEVEL + 0.3:
		c = Color(0.58, 0.52, 0.38)  # muddy banks and riverbed
	elif slope > 0.55:
		c = grass.lerp(Color(0.5, 0.48, 0.44), clampf((slope - 0.55) * 3.0, 0.0, 1.0))  # rock
	for t in GameData.TEAM_COUNT:
		var base := Vector2(0, (GameData.BASE_Z + 8.0) * GameData.team_sign(t))
		var d := Vector2(v.x, v.z).distance_to(base)
		if d < Terrain.BASE_FLAT_RADIUS:
			c = c.lerp(GameData.team_color(t), 0.15 * (1.0 - d / Terrain.BASE_FLAT_RADIUS))
	# A little per-vertex variation so slopes read clearly.
	var jitter := fmod(absf(sin(ix * 12.9898 + iz * 78.233) * 43758.5453), 1.0) * 0.06 - 0.03
	return Color(c.r + jitter, c.g + jitter, c.b + jitter)


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
	# Distance haze: depth on a big map, and hides the far edge.
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.72, 0.8, 0.88)
	environment.fog_density = 0.0007
	environment.fog_sky_affect = 0.0
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
	# Flat ground outside the walls (the playable terrain is built once the seed is known).
	var outside := Color(0.33, 0.5, 0.25)
	add_child(Visuals.box(Vector3(w + 200, 1, 100), outside, Vector3(0, -0.5, l * 0.5 + 50.5)))
	add_child(Visuals.box(Vector3(w + 200, 1, 100), outside, Vector3(0, -0.5, -l * 0.5 - 50.5)))
	add_child(Visuals.box(Vector3(100, 1, l), outside, Vector3(w * 0.5 + 50.5, -0.5, 0)))
	add_child(Visuals.box(Vector3(100, 1, l), outside, Vector3(-w * 0.5 - 50.5, -0.5, 0)))
	# Boundary palisade.
	var wall_color := Color(0.4, 0.3, 0.2)
	add_child(Visuals.static_box(Vector3(w, 6, 1), wall_color, Vector3(0, 3, l * 0.5 + 0.5)))
	add_child(Visuals.static_box(Vector3(w, 6, 1), wall_color, Vector3(0, 3, -l * 0.5 - 0.5)))
	add_child(Visuals.static_box(Vector3(1, 6, l), wall_color, Vector3(w * 0.5 + 0.5, 3, 0)))
	add_child(Visuals.static_box(Vector3(1, 6, l), wall_color, Vector3(-w * 0.5 - 0.5, 3, 0)))

	for t in GameData.TEAM_COUNT:
		var tc := GameData.team_color(t)
		var side := GameData.team_sign(t)
		var crown_pos := GameData.crown_pos(t)
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
