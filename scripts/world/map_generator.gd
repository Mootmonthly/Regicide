class_name MapGenerator
extends RefCounted
## Deterministic resource layout from a seed. Every peer runs this with the seed the
## server picks, so the ~500 resource nodes never need to be sent over the network.
## One half is generated and point-mirrored so both teams get an identical map.

## [resource type, count per half, min z, max z, max |x|]
const ZONES := [
	["wood", 160, 8.0, 178.0, 96.0],
	["stone", 60, 15.0, 150.0, 92.0],
	["iron", 26, 20.0, 95.0, 85.0],
	["magic_ore", 8, 3.0, 28.0, 40.0],  # contested middle
]
const MIN_SPACING := 3.0


static func generate(map_seed: int) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = map_seed
	var half: Array[Dictionary] = []
	for zone in ZONES:
		var type: String = zone[0]
		var wanted: int = zone[1]
		var placed := 0
		var attempts := 0
		while placed < wanted and attempts < wanted * 40:
			attempts += 1
			var p := Vector3(rng.randf_range(-zone[4], zone[4]), 0.0, rng.randf_range(zone[2], zone[3]))
			if _is_free(p, half):
				half.append({"type": type, "pos": p})
				placed += 1
	var out: Array[Dictionary] = []
	out.append_array(half)
	for e in half:
		var p: Vector3 = e["pos"]
		out.append({"type": e["type"], "pos": Vector3(-p.x, 0.0, -p.z)})
	return out


static func _is_free(p: Vector3, existing: Array[Dictionary]) -> bool:
	if GameData.flat_distance(p, GameData.crown_pos(0)) < GameData.BASE_CLEAR_RADIUS:
		return false
	# Keep the spawn area clear.
	if absf(p.x) < 22.0 and p.z > GameData.SPAWN_Z - 10.0:
		return false
	for e in existing:
		if (e["pos"] as Vector3).distance_to(p) < MIN_SPACING:
			return false
	return true
