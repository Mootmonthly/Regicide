class_name Inventory
extends RefCounted
## Item/resource counts for one player. Server-owned; clients get a copy via to_dict().

var _counts: Dictionary = {}


func count(id: String) -> int:
	return int(_counts.get(id, 0))


func add(id: String, amount := 1) -> void:
	if amount <= 0:
		return
	_counts[id] = count(id) + amount


func remove(id: String, amount := 1) -> bool:
	if amount <= 0:
		return true
	var have := count(id)
	if have < amount:
		return false
	if have == amount:
		_counts.erase(id)
	else:
		_counts[id] = have - amount
	return true


func has_all(cost: Dictionary) -> bool:
	for id in cost:
		if count(id) < int(cost[id]):
			return false
	return true


## Removes every entry in cost, or nothing at all if anything is missing.
func pay(cost: Dictionary) -> bool:
	if not has_all(cost):
		return false
	for id in cost:
		remove(id, int(cost[id]))
	return true


func clear() -> void:
	_counts.clear()


func to_dict() -> Dictionary:
	return _counts.duplicate()
