class_name CrownState
extends RefCounted
## Replicated state of one team's crown.

var team := 0
var state: int = CrownRules.State.HOME
var carrier := 0  ## peer id, valid while CARRIED
var position := Vector3.ZERO
## Local clock time it was dropped (each peer stamps its own on receipt).
var dropped_at := 0.0


func _init(p_team := 0) -> void:
	team = p_team
	send_home()


func send_home() -> void:
	state = CrownRules.State.HOME
	carrier = 0
	position = GameData.crown_pos(team)


func to_dict() -> Dictionary:
	return {"team": team, "state": state, "carrier": carrier, "position": position}


func apply_dict(d: Dictionary, now: float) -> void:
	var new_state: int = d.get("state", CrownRules.State.HOME)
	if new_state == CrownRules.State.DROPPED and state != CrownRules.State.DROPPED:
		dropped_at = now
	state = new_state
	carrier = d.get("carrier", 0)
	position = d.get("position", GameData.crown_pos(team))
