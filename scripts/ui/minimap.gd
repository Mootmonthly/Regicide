class_name Minimap
extends Control
## Top-down map: bases, crowns, your team, and enemies your team can see.
## Enemy crown carriers always show, so a theft can always be chased.

const SPOT_RANGE := 30.0

var world: World
var game_mode: GameMode
var _terrain_tex: ImageTexture
var _terrain_team := -1


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


## Shaded relief: green lowlands, lighter hills, blue water. Your base at the bottom.
func _render_terrain(my_team: int) -> ImageTexture:
	var w := 60
	var h := 108
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var flip := -1.0 if my_team == 1 else 1.0
	for py in h:
		for px in w:
			var x := ((px + 0.5) / w - 0.5) * GameData.MAP_WIDTH * flip
			var z := ((py + 0.5) / h - 0.5) * GameData.MAP_LENGTH * flip
			var ht := Terrain.height(x, z)
			var c: Color
			if ht < Terrain.WATER_LEVEL:
				c = Color(0.25, 0.45, 0.8)
			else:
				c = Color(0.22, 0.4, 0.18).lerp(Color(0.62, 0.68, 0.45), clampf(ht / 9.0, 0.0, 1.0))
			img.set_pixel(px, py, c)
	return ImageTexture.create_from_image(img)


func _draw() -> void:
	if world == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.15, 0.25, 0.12, 0.8))
	var me := world.local_player()
	var my_team := me.team if me else 0
	if world.terrain_ready and (_terrain_tex == null or _terrain_team != my_team):
		_terrain_tex = _render_terrain(my_team)
		_terrain_team = my_team
	if _terrain_tex:
		draw_texture_rect(_terrain_tex, Rect2(Vector2.ZERO, size), false, Color(1, 1, 1, 0.85))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.9), false, 2.0)

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
		if not visible_to_us and not p.cloaked:
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
