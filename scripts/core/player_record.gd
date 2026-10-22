class_name PlayerRecord
extends RefCounted
## Server-side bookkeeping for one connected player: inventory, gold, unlocks, stats.

var peer_id := 0
var name := ""
var team := 0
var inventory := Inventory.new()
var gold := GameData.START_GOLD
var unlocks: Dictionary = {}  ## item id -> true
var kills := 0
var deaths := 0
var captures := 0
var gather_mult := 1.0
var bonus_health := 0.0
var next_action_time := 0.0
var protected_until := 0.0
## Server speed check: last position we accepted and when.
var last_valid_pos := Vector3.ZERO
var last_move_check := 0.0


var is_bot: bool:
	get:
		return peer_id < 0


func _init(p_peer := 0, p_name := "", p_team := 0) -> void:
	peer_id = p_peer
	name = p_name
	team = p_team


func is_unlocked(id: String) -> bool:
	return int(GameData.item(id).get("unlock_cost", 0)) <= 0 or unlocks.has(id)


func reset_progress() -> void:
	inventory = Inventory.new()
	gold = GameData.START_GOLD
	unlocks.clear()
	kills = 0
	deaths = 0
	captures = 0
	gather_mult = 1.0
	bonus_health = 0.0


func stats() -> Dictionary:
	return {"kills": kills, "deaths": deaths, "captures": captures, "gather_mult": gather_mult}
