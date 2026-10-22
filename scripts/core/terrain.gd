class_name Terrain
extends RefCounted
## Deterministic heightmap shared by every peer: rolling hills and valleys, a river that
## winds across the middle (with narrow points and two shallow fords), and flat
## plateaus around both bases. The height function is point-symmetric through the map
## center, so both teams get an identical map.
##
## Heights are sampled on a 2 m grid; height() interpolates that grid, and the physics
## collider and mesh are built from the same samples, so gameplay checks and what
## players stand on agree.

const SPACING := 2.0
const WATER_LEVEL := -0.6
const RIVER_BED := -2.6
const FORD_BED := -0.35
const HILL_HEIGHT := 11.0
const BASE_FLAT_RADIUS := 40.0
const BASE_BLEND := 18.0
const EDGE_BLEND := 14.0
const FORD_X := 140.0
## Where the river is narrowest (a drawbridge spans it here), mirrored at -NARROWS_X.
const NARROWS_X := 78.5

## Set by tests that need perfectly flat ground.
static var force_flat := false
static var _seed := -1
static var _flat := false
static var _w := 0
static var _d := 0
static var _heights := PackedFloat32Array()


static func setup(map_seed: int) -> void:
	if map_seed == _seed and _flat == force_flat and not _heights.is_empty():
		return
	_seed = map_seed
	_flat = force_flat
	_w = int(GameData.MAP_WIDTH / SPACING) + 1
	_d = int(GameData.MAP_LENGTH / SPACING) + 1
	_heights.resize(_w * _d)
	var noise := FastNoiseLite.new()
	noise.seed = map_seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.0065
	noise.fractal_octaves = 3
	for iz in _d:
		for ix in _w:
			var x := -GameData.MAP_WIDTH * 0.5 + ix * SPACING
			var z := -GameData.MAP_LENGTH * 0.5 + iz * SPACING
			_heights[iz * _w + ix] = 0.0 if force_flat else _shape(noise, x, z)


static func is_ready() -> bool:
	return not _heights.is_empty()


static func sample_size() -> Vector2i:
	return Vector2i(_w, _d)


static func sample(ix: int, iz: int) -> float:
	return _heights[clampi(iz, 0, _d - 1) * _w + clampi(ix, 0, _w - 1)]


## Ground height at a world position (0 outside the map or before setup).
static func height(x: float, z: float) -> float:
	if _heights.is_empty():
		return 0.0
	var fx := (x + GameData.MAP_WIDTH * 0.5) / SPACING
	var fz := (z + GameData.MAP_LENGTH * 0.5) / SPACING
	if fx < 0.0 or fz < 0.0 or fx > _w - 1 or fz > _d - 1:
		return 0.0
	var ix := mini(int(fx), _w - 2)
	var iz := mini(int(fz), _d - 2)
	var tx := fx - ix
	var tz := fz - iz
	var a := lerpf(sample(ix, iz), sample(ix + 1, iz), tx)
	var b := lerpf(sample(ix, iz + 1), sample(ix + 1, iz + 1), tx)
	return lerpf(a, b, tz)


static func height_at(p: Vector3) -> float:
	return height(p.x, p.z)


static func is_water(x: float, z: float) -> bool:
	return height(x, z) < WATER_LEVEL - 0.1


## Center line of the river (an odd function of x, so the river is point-symmetric).
static func river_z(x: float) -> float:
	return 24.0 * sin(x * 0.0225) + 8.0 * sin(x * 0.055)


## River channel width: narrowest around x = +-NARROWS_X (about 5 m of open water,
## which a drawbridge spans) and up to ~18 m of water elsewhere.
static func river_width(x: float) -> float:
	return 9.5 + 7.0 * cos(x * PI / NARROWS_X)


static func _shape(noise: FastNoiseLite, x: float, z: float) -> float:
	# Average the noise with its mirror image so the map is point-symmetric.
	var n := 0.5 * (noise.get_noise_2d(x, z) + noise.get_noise_2d(-x, -z))
	var h := n * HILL_HEIGHT * 1.6 + 1.5
	h = maxf(h, 0.0)  # dry valley floors sit above the water line
	# Flat plateaus at both bases.
	for t in GameData.TEAM_COUNT:
		var base := Vector2(0.0, (GameData.BASE_Z + 8.0) * GameData.team_sign(t))
		var d := Vector2(x, z).distance_to(base)
		h = lerpf(0.0, h, smoothstep(BASE_FLAT_RADIUS, BASE_FLAT_RADIUS + BASE_BLEND, d))
	# Settle down near the boundary walls so nobody walks over them.
	var edge := minf(GameData.MAP_WIDTH * 0.5 - absf(x), GameData.MAP_LENGTH * 0.5 - absf(z))
	h = lerpf(0.0, h, smoothstep(2.0, EDGE_BLEND, edge))
	# Carve the river.
	var half := river_width(x) * 0.5
	var dz := absf(z - river_z(x))
	var ford := maxf(1.0 - absf(absf(x) - FORD_X) / 9.0, 0.0)
	var bed := lerpf(RIVER_BED, FORD_BED, smoothstep(0.0, 1.0, ford))
	var bank := smoothstep(half * 0.75, half + 1.8, dz)  # fairly steep banks
	var land := lerpf(minf(h, 1.5), h, smoothstep(half + 5.0, half + 16.0, dz))  # low banks
	return lerpf(bed, land, bank)
