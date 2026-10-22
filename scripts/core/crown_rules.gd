class_name CrownRules
extends RefCounted
## Pure capture-the-flag rules, kept free of nodes so they're easy to test.

enum State { HOME, CARRIED, DROPPED }
enum Action { NONE, PICK_UP, RETURN }


## What happens when a living player of toucher_team touches a crown.
static func touch_action(crown_team: int, crown_state: int, toucher_team: int) -> Action:
	if crown_state == State.CARRIED:
		return Action.NONE
	if toucher_team != crown_team:
		return Action.PICK_UP
	if crown_state == State.DROPPED:
		return Action.RETURN
	return Action.NONE


## A capture needs: an enemy crown in hand, your own crown safely at home,
## and standing at your own pedestal.
static func can_capture(carrier_team: int, carried_crown_team: int, own_crown_state: int, distance_to_own_pedestal: float) -> bool:
	return carried_crown_team != carrier_team \
		and own_crown_state == State.HOME \
		and distance_to_own_pedestal <= GameData.CAPTURE_RADIUS
