class_name Minimap
extends Control
## Top-down map: bases, crowns, your team, and enemies your team can see.
## Enemy crown carriers always show, so a theft can always be chased.

const SPOT_RANGE := 30.0

var world: World
var game_mode: GameMode


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _to_map(p: Vector3) -> Vector2:
	# Your own base is always at the bottom.
	var me := world.local_player()
	var flip := -1.0 if me and me.team == 1 else 1.0
	var nx := (p.x * flip) / GameData.MAP_WIDTH + 0.5
	var ny := (p.z * flip) / GameData.MAP_LENGTH + 0.5
	return Vector2(nx * size.x, ny * size.y)


func _draw() -> void:
	if world == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.15, 0.25, 0.12, 0.8))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.9), false, 2.0)
	draw_line(_to_map(Vector3(-100, 0, 0)), _to_map(Vector3(100, 0, 0)), Color(1, 1, 1, 0.25), 1.0)
	var me := world.local_player()
	var my_team := me.team if me else 0

	for s in world.get_structures():
		if s.team == my_team:
			draw_rect(Rect2(_to_map(s.global_position) - Vector2(1.5, 1.5), Vector2(3, 3)), Color(0.75, 0.7, 0.6))

	var players := world.get_players()
	var allies: Array[Player] = []
	for p in players:
		if p.team == my_team and p.alive:
			allies.append(p)
	for p in players:
		if not p.alive or p == me:
			continue
		var visible_to_us := p.team == my_team or p.carrying_crown >= 0
		if not visible_to_us:
			for a in allies:
				if a.sync_pos.distance_to(p.sync_pos) < SPOT_RANGE:
					visible_to_us = true
					break
		if visible_to_us:
			draw_circle(_to_map(p.sync_pos), 2.5, GameData.team_color(p.team).lightened(0.2))

	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 150.0)
	for c in game_mode.crowns:
		var pos := c.position
		if c.state == CrownRules.State.CARRIED:
			var carrier := world.get_player(c.carrier)
			if carrier:
				pos = carrier.sync_pos
		var mp := _to_map(pos)
		draw_circle(mp, 6.0 + (pulse * 2.0 if c.state != CrownRules.State.HOME else 0.0), GameData.team_color(c.team))
		draw_circle(mp, 4.0, Color(1, 0.82, 0.2))

	if me and me.alive:
		var mp := _to_map(me.sync_pos)
		var flip := -1.0 if me.team == 1 else 1.0
		var fwd3 := -me.global_basis.z * flip
		var fwd := Vector2(fwd3.x, fwd3.z).normalized()
		var side := Vector2(-fwd.y, fwd.x)
		draw_colored_polygon(PackedVector2Array([mp + fwd * 7, mp - fwd * 4 + side * 4, mp - fwd * 4 - side * 4]), Color.WHITE)
