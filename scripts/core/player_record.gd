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
var skills: Dictionary = {}  ## skill id -> rank
var skill_points := 0
var spell_ready: Dictionary = {}  ## spell id -> game time it can be cast again
var slow_until := 0.0
var stun_until := 0.0
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
	skills.clear()
	skill_points = 0
	spell_ready.clear()
	rally_until = 0.0
	cloak_until = 0.0
	ward_amount = 0.0
	ward_until = 0.0


## Timed effects from spells (GameMode clock).
var rally_until := 0.0
var cloak_until := 0.0
var ward_amount := 0.0
var ward_until := 0.0


## How long a stun or slow lasts on this player, after Iron Will.
func status_duration(seconds: float) -> float:
	return seconds * (1.0 - 0.25 * rank("iron_will"))


func rank(skill: String) -> int:
	return int(skills.get(skill, 0))


func max_health() -> float:
	return GameData.PLAYER_MAX_HEALTH + bonus_health + 15.0 * rank("toughness")


func max_mana() -> float:
	return GameData.PLAYER_MAX_MANA + 25.0 * rank("arcane")


func mana_regen() -> float:
	return GameData.MANA_REGEN + 1.0 * rank("arcane")


## Best shield in the inventory, or "".
func shield() -> String:
	for id in ["iron_shield", "wooden_shield"]:
		if inventory.count(id) > 0:
			return id
	return ""


func stats() -> Dictionary:
	return {"kills": kills, "deaths": deaths, "captures": captures, "gather_mult": gather_mult,
		"skills": skills.duplicate(), "skill_points": skill_points}
