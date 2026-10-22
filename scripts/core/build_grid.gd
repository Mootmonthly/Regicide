class_name BuildGrid
extends RefCounted
## The snap grid for modular building. Pure math, no nodes, so it's easy to test.
##
## Cells are 4 x 4 m and levels are 3 m tall. Cell (i, j) is centered at (4i, 4j).
## Grid lines run at x = 4i + 2 and z = 4j + 2.
##   - Floors sit in a cell, with their top at the level's height.
##   - Stairs, roofs and free-standing pieces (ballista, traps) fill a cell's space.
##   - Walls, doors and ladders sit on a cell edge:
##       axis 0 runs along X at z = 4j + 2 (between cells (i, j) and (i, j+1))
##       axis 1 runs along Z at x = 4i + 2 (between cells (i, j) and (i+1, j))
##     A ladder also has a side (+1/-1): which side of the edge it leans on.
##
## A slot is a Dictionary of ints {i, j, level, axis, rot, side}. That's what a client
## sends the server when it builds.
##
## Support: everything must connect to the ground. Walls stand on the ground, on a wall
## below, or on a floor. Floors rest on walls below them, or reach one cell out from a
## floor that does. Stairs and free pieces need a floor (or the ground). Ladders lean on
## a wall, stand on a ladder below, or stand on a floor. Remove a support and whatever
## it held up collapses.

const CELL := 4.0
const LEVEL := 3.0
const MAX_LEVEL := 5
const FOUNDATION_TOP := 0.25
const LADDER_OFFSET := 0.5
const REACH := 10.0


static func kind_of(item_id: String) -> String:
	return GameData.item(item_id).get("piece", "")


static func make_slot(i: int, j: int, level: int, axis := 0, rot := 0, side := 1) -> Dictionary:
	return {"i": i, "j": j, "level": level, "axis": axis, "rot": rot, "side": side}


## Coerce untrusted network input into a clean slot.
static func sanitize(slot: Dictionary) -> Dictionary:
	return make_slot(int(slot.get("i", 0)), int(slot.get("j", 0)), int(slot.get("level", 0)),
		clampi(int(slot.get("axis", 0)), 0, 1), posmod(int(slot.get("rot", 0)), 4),
		1 if int(slot.get("side", 1)) >= 0 else -1)


static func key(kind: String, s: Dictionary) -> String:
	match kind:
		"floor":
			return floor_key(s["i"], s["j"], s["level"])
		"wall", "door":
			return edge_key(s["axis"], s["i"], s["j"], s["level"])
		"ladder":
			return "L:%d:%d:%d:%d:%d" % [s["axis"], s["i"], s["j"], s["level"], s["side"]]
		_:
			return "C:%d:%d:%d" % [s["i"], s["j"], s["level"]]


static func floor_key(i: int, j: int, level: int) -> String:
	return "F:%d:%d:%d" % [i, j, level]


static func edge_key(axis: int, i: int, j: int, level: int) -> String:
	return "E:%d:%d:%d:%d" % [axis, i, j, level]


static func level_y(level: int) -> float:
	return level * LEVEL


## World transform of a piece's origin (base center, local -Z is "forward").
static func transform_for(kind: String, s: Dictionary) -> Transform3D:
	var i: int = s["i"]
	var j: int = s["j"]
	var y := level_y(s["level"])
	match kind:
		"floor":
			return Transform3D(Basis(), Vector3(i * CELL, y if s["level"] > 0 else FOUNDATION_TOP, j * CELL))
		"wall", "door", "ladder":
			var origin: Vector3
			var basis: Basis
			if s["axis"] == 0:
				origin = Vector3(i * CELL, y, j * CELL + CELL * 0.5)
				basis = Basis()
			else:
				origin = Vector3(i * CELL + CELL * 0.5, y, j * CELL)
				basis = Basis(Vector3.UP, PI * 0.5)
			if kind == "ladder":
				# Local +Z of the ladder faces the climber.
				var normal := Vector3(0, 0, 1) if s["axis"] == 0 else Vector3(1, 0, 0)
				origin += normal * LADDER_OFFSET * s["side"]
				if s["side"] < 0:
					basis = basis.rotated(Vector3.UP, PI)
			return Transform3D(basis, origin)
		_:
			return Transform3D(Basis(Vector3.UP, s["rot"] * PI * 0.5), Vector3(i * CELL, y, j * CELL))


## Roughly the middle of the piece, for reach checks.
static func center_of(kind: String, s: Dictionary) -> Vector3:
	var origin := transform_for(kind, s).origin
	return origin if kind == "floor" else origin + Vector3(0, LEVEL * 0.5, 0)


## Which slot a player means, from where their crosshair hits (q, nudged just off the
## surface), the way they're looking, and where they stand.
static func slot_for(item_id: String, q: Vector3, look: Vector3, player_pos: Vector3) -> Dictionary:
	var kind := kind_of(item_id)
	var rot := posmod(roundi(atan2(-look.x, -look.z) / (PI * 0.5)), 4)
	var ci := roundi(q.x / CELL)
	var cj := roundi(q.z / CELL)
	var stand_level := clampi(floori(q.y / LEVEL + 0.02), 0, MAX_LEVEL)
	var nearest_level := clampi(roundi(q.y / LEVEL), 0, MAX_LEVEL)
	match kind:
		"floor", "roof":
			return make_slot(ci, cj, nearest_level, 0, rot)
		"wall", "door", "ladder":
			# The wall faces you: it runs across your line of sight.
			if absf(look.x) > absf(look.z):
				var i := roundi((q.x - CELL * 0.5) / CELL)
				var side := 1 if player_pos.x > i * CELL + CELL * 0.5 else -1
				return make_slot(i, cj, stand_level, 1, rot, side)
			var j := roundi((q.z - CELL * 0.5) / CELL)
			var side := 1 if player_pos.z > j * CELL + CELL * 0.5 else -1
			return make_slot(ci, j, stand_level, 0, rot, side)
		_:
			return make_slot(ci, cj, stand_level, 0, rot)


# --- Support ------------------------------------------------------------------------

## Is a piece in this slot held up? `has` answers whether a supporting piece exists at
## a key (callers decide what counts: everything placed, or only what's still standing).
static func is_supported(kind: String, s: Dictionary, has: Callable) -> bool:
	var i: int = s["i"]
	var j: int = s["j"]
	var l: int = s["level"]
	if l <= 0:
		return true
	match kind:
		"floor":
			if _floor_direct(i, j, l, has):
				return true
			for n in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if has.call(floor_key(i + n.x, j + n.y, l)) and _floor_direct(i + n.x, j + n.y, l, has):
					return true
			return false
		"wall", "door":
			var a: int = s["axis"]
			if has.call(edge_key(a, i, j, l - 1)):
				return true
			var other := Vector2i(i, j + 1) if a == 0 else Vector2i(i + 1, j)
			return has.call(floor_key(i, j, l)) or has.call(floor_key(other.x, other.y, l))
		"ladder":
			var a: int = s["axis"]
			var side: int = s["side"]
			if has.call("L:%d:%d:%d:%d:%d" % [a, i, j, l - 1, side]) or has.call(edge_key(a, i, j, l)):
				return true
			var cell := Vector2i(i, j)
			if side > 0:
				cell = Vector2i(i, j + 1) if a == 0 else Vector2i(i + 1, j)
			return has.call(floor_key(cell.x, cell.y, l))
		"roof":
			return has.call(floor_key(i, j, l)) or _walls_below(i, j, l, has)
		_:
			return has.call(floor_key(i, j, l))


## A floor resting directly on walls below it.
static func _floor_direct(i: int, j: int, l: int, has: Callable) -> bool:
	return l <= 0 or _walls_below(i, j, l, has)


static func _walls_below(i: int, j: int, l: int, has: Callable) -> bool:
	return has.call(edge_key(0, i, j, l - 1)) or has.call(edge_key(0, i, j - 1, l - 1)) \
		or has.call(edge_key(1, i, j, l - 1)) or has.call(edge_key(1, i - 1, j, l - 1))


## Given every placed piece as key -> [kind, slot], returns the keys still held up.
static func supported_keys(pieces: Dictionary) -> Dictionary:
	var supported := {}
	var has := func(k: String) -> bool: return supported.has(k)
	var changed := true
	while changed:
		changed = false
		for k: String in pieces:
			if supported.has(k):
				continue
			var entry: Array = pieces[k]
			if is_supported(entry[0], entry[1], has):
				supported[k] = true
				changed = true
	return supported
