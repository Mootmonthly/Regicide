class_name MapGenerator
extends RefCounted
## Deterministic resource layout from a seed. Every peer runs this with the seed the
## server picks, so the ~1,700 resource nodes never need to be sent over the network.
## One half is generated and point-mirrored so both teams get an identical map.
## Trees grow in forests that get denser toward the middle of the map (the river valley
## is thick woodland) and thin out toward the bases, with open ground around each crown.
## Nothing spawns in the river.

## [resource type, count per half, min z, max z, max |x|]
const ZONES := [
	["wood", 950, 10.0, 356.0, 194.0],
	["stone", 200, 30.0, 300.0, 186.0],
	["iron", 90, 40.0, 190.0, 170.0],
	["magic_ore", 22, 6.0, 60.0, 80.0],  # contested middle, near the river
]
const MIN_SPACING := 3.2
## Forest noise cutoff and lone-tree chance, from the bases (first) to the middle (second).
const FOREST_THRESHOLD := [0.3, -0.3]
const STRAY_TREE_CHANCE := [0.02, 0.45]
## Open ground around each crown (no trees within this distance).
const CROWN_CLEARING := 75.0


static func generate(map_seed: int) -> Array[Dictionary]:
	Terrain.setup(map_seed)
	var rng := RandomNumberGenerator.new()
	rng.seed = map_seed
	var forest := FastNoiseLite.new()
	forest.seed = map_seed + 7
	forest.frequency = 0.022
	var half: Array[Dictionary] = []
	var grid := {}  # spatial hash: Vector2i cell -> positions, for fast spacing checks
	for zone in ZONES:
		var type: String = zone[0]
		var wanted: int = zone[1]
		var placed := 0
		var attempts := 0
		while placed < wanted and attempts < wanted * 60:
			attempts += 1
			var p := Vector3(rng.randf_range(-zone[4], zone[4]), 0.0, rng.randf_range(zone[2], zone[3]))
			if type == "wood":
				if GameData.flat_distance(p, GameData.crown_pos(0)) < CROWN_CLEARING:
					continue
				# 1 in the middle of the map, 0 out by the bases.
				var middle := 1.0 - clampf((p.z - 30.0) / 200.0, 0.0, 1.0)
				var cutoff := lerpf(FOREST_THRESHOLD[0], FOREST_THRESHOLD[1], middle)
				var stray := lerpf(STRAY_TREE_CHANCE[0], STRAY_TREE_CHANCE[1], middle)
				if forest.get_noise_2d(p.x, p.z) < cutoff and rng.randf() > stray:
					continue
			if not _is_free(p, grid):
				continue
			p.y = Terrain.height(p.x, p.z)
			half.append({"type": type, "pos": p})
			var cell := _cell(p)
			if not grid.has(cell):
				grid[cell] = []
			grid[cell].append(p)
			placed += 1
	var out: Array[Dictionary] = []
	out.append_array(half)
	for e in half:
		var p: Vector3 = e["pos"]
		out.append({"type": e["type"], "pos": Vector3(-p.x, Terrain.height(-p.x, -p.z), -p.z)})
	return out


static func _cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / MIN_SPACING), floori(p.z / MIN_SPACING))


static func _is_free(p: Vector3, grid: Dictionary) -> bool:
	if GameData.flat_distance(p, GameData.crown_pos(0)) < GameData.BASE_CLEAR_RADIUS:
		return false
	# Keep the spawn area clear.
	if absf(p.x) < 26.0 and p.z > GameData.SPAWN_Z - 14.0:
		return false
	# Nothing in the water, and a little space along the banks.
	for off in [Vector2.ZERO, Vector2(1.5, 0), Vector2(-1.5, 0), Vector2(0, 1.5), Vector2(0, -1.5)]:
		if Terrain.height(p.x + off.x, p.z + off.y) < Terrain.WATER_LEVEL + 0.2:
			return false
	var c := _cell(p)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for q: Vector3 in grid.get(Vector2i(c.x + dx, c.y + dz), []):
				if GameData.flat_distance(q, p) < MIN_SPACING:
					return false
	return true
