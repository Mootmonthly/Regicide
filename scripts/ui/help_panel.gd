class_name HelpPanel
extends PanelContainer
## "How to play": the goal, the match loop, and the controls (showing the player's own
## key bindings). Shown the first time someone enters a match, and from the pause menu
## and main menu.

signal closed


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	custom_minimum_size = Vector2(760, 560)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.08, 0.07, 0.96)
	style.border_color = Color(0.75, 0.6, 0.3)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(18)
	add_theme_stylebox_override("panel", style)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	add_child(col)
	var title := Label.new()
	title.text = "How to play Regicide"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(1.0, 0.82, 0.4))
	col.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 6)
	scroll.add_child(body)

	_heading(body, "The goal")
	_para(body, "Steal the enemy crown from their base and carry it to your own crown's pedestal, while your crown is still at home. "
		+ "First team to %d captures wins, or the team with more captures after %d minutes. A tie goes to overtime: next capture wins."
		% [GameData.CAPTURES_TO_WIN, int(GameData.MATCH_TIME_LIMIT / 60.0)])
	_para(body, "Carrying a crown slows you down, and you drop it if you die. If your own crown is stolen, chase the thief: touch your dropped crown to send it home.")

	_heading(body, "How a match goes")
	_para(body, "1. Gather: everyone starts with nothing. Hit trees and rocks for wood and stone; craft a pickaxe for iron and magic ore.")
	_para(body, "2. Craft (%s): weapons, shields, bows and potions. Kills earn gold to unlock blueprints and learn spells, and skill points for skills."
		% Settings.binding_text("toggle_menu"))
	_para(body, "3. Build (%s): walls, gates, floors, stairs, ladders, ballistas and siege engines. Defend your crown and break into theirs."
		% Settings.binding_text("build_mode"))
	_para(body, "4. Fight: block with a shield (raise it right as a blow lands to parry and stun the attacker), shoot, cast spells, ride horses.")
	_para(body, "Dying costs you nothing but a carried crown and your horse; you're back at your spawn in %d seconds." % int(GameData.RESPAWN_TIME))

	_heading(body, "Controls")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	body.add_child(grid)
	var rows := [
		["Move / jump / sprint", "%s %s %s %s / %s / %s" % [Settings.binding_text("move_forward"), Settings.binding_text("move_left"),
			Settings.binding_text("move_back"), Settings.binding_text("move_right"), Settings.binding_text("jump"), Settings.binding_text("sprint")]],
		["Use what you're holding (attack, cast, gather, place)", Settings.binding_text("primary")],
		["Block with a shield", Settings.binding_text("block")],
		["Pick hotbar slot", "1–9, 0, mouse wheel"],
		["Build mode (press again for next page)", Settings.binding_text("build_mode")],
		["Rotate / repair / upgrade a piece", "%s / %s / %s" % [Settings.binding_text("rotate_piece"), Settings.binding_text("repair"), Settings.binding_text("upgrade")]],
		["Drawbridge, catapult", Settings.binding_text("interact")],
		["Crafting, spells & skills", Settings.binding_text("toggle_menu")],
		["Take the selected item or spell off the hotbar", Settings.binding_text("hide_slot")],
		["Dash (once you've learned the skill)", Settings.binding_text("dash")],
		["Talk nearby / to your team (hold)", "%s / %s" % [Settings.binding_text("voice_proximity"), Settings.binding_text("voice_team")]],
		["First / third person", Settings.binding_text("camera_toggle")],
		["Scoreboard (hold)", Settings.binding_text("scoreboard")],
		["Pause menu: settings, this help, leave", "Esc"],
	]
	for r: Array in rows:
		var a := Label.new()
		a.text = r[0]
		grid.add_child(a)
		var b := Label.new()
		b.text = r[1]
		b.add_theme_color_override("font_color", Color(1.0, 0.85, 0.55))
		grid.add_child(b)
	_para(body, "Keys can be changed in Settings.")

	var go := Button.new()
	go.text = "Got it"
	go.custom_minimum_size = Vector2(160, 40)
	go.size_flags_horizontal = Control.SIZE_SHRINK_END
	go.pressed.connect(close)
	col.add_child(go)
	go.grab_focus.call_deferred()


func close() -> void:
	Settings.set_value("general", "seen_help", true)
	closed.emit()
	queue_free()


func _heading(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", Color(1.0, 0.82, 0.4))
	parent.add_child(l)


func _para(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 680
	parent.add_child(l)
