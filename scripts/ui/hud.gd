class_name Hud
extends CanvasLayer
## In-match UI, built in code: resources, gold, health, score, crown status, hotbar,
## message feed, and the Tab menu for crafting and buying blueprints.

const FEED_LINES := 7
const FEED_SECONDS := 8.0

var menu_open := false
var _pause: PanelContainer  ## Esc menu
var _overlay: Control  ## settings or help window over the game, if any

var _world: World
var _game_mode: GameMode
var _label_settings: LabelSettings
var _resources: Label
var _score: Label
var _clock: Label  ## time left in the match
var _crowns: Label
var _center: Label
var _health: ProgressBar
var _health_label: Label
var _mana_bar: ProgressBar
var _stamina_bar: ProgressBar
var _voice_label: Label
var _hotbar: HBoxContainer
var _feed: VBoxContainer
var _menu: PanelContainer
var _menu_gold: Label
var _menu_list: VBoxContainer
var _banner: Label
var _crosshair: Label
var _vignette: ColorRect
var _scoreboard: PanelContainer
var _scoreboard_cols: Array[VBoxContainer] = []
var _minimap: Minimap
var _last_health := -1.0
var _last_crown_states: Array = []
var _crosshair_tween: Tween
var _hotbar_build_mode := false
var _hotbar_page := 0
var _mode_label: Label


func _ready() -> void:
	_world = get_parent() as World
	_game_mode = _world.game_mode
	_label_settings = LabelSettings.new()
	_label_settings.font_size = 18
	_label_settings.outline_size = 6
	_label_settings.outline_color = Color(0, 0, 0, 0.85)
	_build()
	_game_mode.private_updated.connect(_on_private_updated)
	_game_mode.message_received.connect(_add_message)
	_game_mode.match_over_changed.connect(_on_match_over_changed)
	_game_mode.hit_confirmed.connect(_on_hit_confirmed)
	_game_mode.crowns_updated.connect(_on_crowns_updated)
	_game_mode.scoreboard_updated.connect(_rebuild_scoreboard)
	for c in _game_mode.crowns:
		_last_crown_states.append(c.state)
	if not bool(Settings.get_value("general", "seen_help")):
		show_help.call_deferred()


func _label(text := "", size := 18) -> Label:
	var l := Label.new()
	l.text = text
	if size == 18:
		l.label_settings = _label_settings
	else:
		var s := _label_settings.duplicate() as LabelSettings
		s.font_size = size
		l.label_settings = s
	return l


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_resources = _label()
	_resources.position = Vector2(16, 12)
	root.add_child(_resources)

	_score = _label("", 26)
	_score.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_score.offset_top = 8
	root.add_child(_score)

	_clock = _label("", 18)
	_clock.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_clock.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_clock.offset_top = 42
	root.add_child(_clock)

	_crowns = _label("", 16)
	_crowns.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_crowns.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_crowns.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_crowns.offset_top = 68
	root.add_child(_crowns)

	_vignette = ColorRect.new()
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.color = Color(0.8, 0.0, 0.0, 0.0)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_vignette)
	root.move_child(_vignette, 0)

	_crosshair = _label("+", 24)
	_crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_crosshair.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_crosshair.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_crosshair.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(_crosshair)

	_minimap = Minimap.new()
	_minimap.world = _world
	_minimap.game_mode = _game_mode
	_minimap.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_minimap.offset_left = -136
	_minimap.offset_top = -232
	_minimap.offset_right = -16
	_minimap.offset_bottom = -16
	root.add_child(_minimap)

	_center = _label("", 30)
	_center.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_center.offset_top = 60
	root.add_child(_center)

	_banner = _label("", 44)
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.offset_top = -140
	root.add_child(_banner)

	_feed = VBoxContainer.new()
	_feed.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_feed.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_feed.offset_top = 12
	_feed.offset_right = -16
	_feed.alignment = BoxContainer.ALIGNMENT_BEGIN
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_feed)

	var bottom := VBoxContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.offset_bottom = -12
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bottom)

	var health_row := Control.new()
	health_row.custom_minimum_size = Vector2(360, 22)
	health_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bottom.add_child(health_row)
	_health = ProgressBar.new()
	_health.set_anchors_preset(Control.PRESET_FULL_RECT)
	_health.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.75, 0.15, 0.15)
	_health.add_theme_stylebox_override("fill", fill)
	health_row.add_child(_health)
	_health_label = _label("", 14)
	_health_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_health_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_health_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	health_row.add_child(_health_label)

	_mana_bar = _thin_bar(bottom, Color(0.25, 0.45, 1.0))
	_stamina_bar = _thin_bar(bottom, Color(0.95, 0.8, 0.25))

	_voice_label = _label("", 15)
	_voice_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	_voice_label.offset_left = 16
	_voice_label.offset_top = 40
	root.add_child(_voice_label)

	_hotbar = HBoxContainer.new()
	_hotbar.alignment = BoxContainer.ALIGNMENT_CENTER
	_hotbar.add_theme_constant_override("separation", 4)
	bottom.add_child(_hotbar)

	_mode_label = _label("", 16)
	_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bottom.add_child(_mode_label)
	bottom.move_child(_mode_label, 1)

	var help := _label("WASD move · Shift sprint · LMB use · RMB block · 1-0 select · Q build · E use · X dash (skill) · C craft, spells & skills · T talk nearby · Y talk team · V camera · Tab scores · Esc menu", 13)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bottom.add_child(help)

	_build_menu(root)
	_build_scoreboard(root)
	_rebuild_hotbar()


func _thin_bar(parent: Control, color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(360, 7)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	bar.add_theme_stylebox_override("fill", fill)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.5)
	bar.add_theme_stylebox_override("background", bg)
	parent.add_child(bar)
	return bar


func _build_menu(root: Control) -> void:
	_menu = PanelContainer.new()
	_menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_menu.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_menu.grow_vertical = Control.GROW_DIRECTION_BOTH
	_menu.custom_minimum_size = Vector2(760, 520)
	_menu.visible = false
	root.add_child(_menu)
	_build_pause_menu(root)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	_menu.add_child(margin)
	var col := VBoxContainer.new()
	margin.add_child(col)
	var header := HBoxContainer.new()
	col.add_child(header)
	var title := _label("Crafting & Blueprints", 24)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_menu_gold = _label("", 20)
	header.add_child(_menu_gold)
	var leave := Button.new()
	leave.text = "Leave match"
	leave.pressed.connect(func() -> void: Net.leave())
	header.add_child(leave)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_menu_list = VBoxContainer.new()
	_menu_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_menu_list)


func _build_scoreboard(root: Control) -> void:
	_scoreboard = PanelContainer.new()
	_scoreboard.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_scoreboard.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_scoreboard.grow_vertical = Control.GROW_DIRECTION_BOTH
	_scoreboard.custom_minimum_size = Vector2(820, 0)
	_scoreboard.visible = false
	_scoreboard.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_scoreboard)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	_scoreboard.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	margin.add_child(row)
	for t in GameData.TEAM_COUNT:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 0)
		row.add_child(col)
		_scoreboard_cols.append(col)


func _rebuild_scoreboard() -> void:
	if not _scoreboard.visible:
		return
	for t in GameData.TEAM_COUNT:
		var col := _scoreboard_cols[t]
		for c in col.get_children():
			c.queue_free()
		var rows: Array = []
		for r: Array in _game_mode.scoreboard:
			if r[1] == t:
				rows.append(r)
		rows.sort_custom(func(a: Array, b: Array) -> bool: return a[4] * 10 + a[2] > b[4] * 10 + b[2])
		var header := _label("%s — %d captures   (%d players)" % [GameData.team_name(t), _game_mode.scores[t], rows.size()], 20)
		header.label_settings.font_color = GameData.team_color(t).lerp(Color.WHITE, 0.35)
		col.add_child(header)
		col.add_child(_score_row("Name", "K", "D", "Cap", Color(0.8, 0.8, 0.8)))
		var me := _world.local_player()
		for r: Array in rows.slice(0, 26):
			var nm: String = r[0] + (" (bot)" if r[5] else "")
			var is_me: bool = me != null and r[0] == me.display_name and not r[5]
			col.add_child(_score_row(nm, str(r[2]), str(r[3]), str(r[4]), Color(1, 0.9, 0.4) if is_me else Color.WHITE))
		if rows.size() > 26:
			col.add_child(_label("... and %d more" % (rows.size() - 26), 13))


func _score_row(nm: String, k: String, d: String, cap: String, color: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	var widths := [220, 44, 44, 44]
	var texts := [nm, k, d, cap]
	for i in 4:
		var l := _label(texts[i], 13)
		l.custom_minimum_size.x = widths[i]
		l.clip_text = true
		l.label_settings.font_color = color
		if i > 0:
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(l)
	return row


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("release_mouse"):
		# Esc closes whatever is open, or opens the pause menu.
		if is_instance_valid(_overlay):
			_overlay.queue_free()
			_overlay = null
			_pause.visible = true
		elif menu_open:
			set_menu_open(false)
		else:
			set_paused(not _pause.visible)
		get_viewport().set_input_as_handled()
		return
	if ui_open() and not menu_open:
		return
	if event.is_action_pressed("toggle_menu"):
		set_menu_open(not menu_open)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("scoreboard"):
		_scoreboard.visible = true
		_rebuild_scoreboard()
		get_viewport().set_input_as_handled()
	elif event.is_action_released("scoreboard"):
		_scoreboard.visible = false
		get_viewport().set_input_as_handled()


## True while any menu or window is up (the game shouldn't grab the mouse).
func ui_open() -> bool:
	return menu_open or _pause.visible or is_instance_valid(_overlay)


func set_paused(open: bool) -> void:
	_pause.visible = open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED


func show_help() -> void:
	_open_overlay(HelpPanel.new())


func _open_overlay(panel: Control) -> void:
	if is_instance_valid(_overlay):
		_overlay.queue_free()
	_pause.visible = false
	if menu_open:
		set_menu_open(false)
	_overlay = panel
	add_child(panel)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	panel.connect("closed", func() -> void:
		_overlay = null
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED)


func _build_pause_menu(root: Control) -> void:
	_pause = PanelContainer.new()
	_pause.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_pause.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_pause.grow_vertical = Control.GROW_DIRECTION_BOTH
	_pause.custom_minimum_size = Vector2(320, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.08, 0.07, 0.94)
	style.border_color = Color(0.75, 0.6, 0.3)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(18)
	_pause.add_theme_stylebox_override("panel", style)
	_pause.visible = false
	root.add_child(_pause)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	_pause.add_child(col)
	var title := _label("Paused", 26)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var note := _label("The match keeps going while this is open.", 14)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(note)
	for entry: Array in [["Resume", func() -> void: set_paused(false)],
			["How to play", show_help],
			["Settings", func() -> void: _open_overlay(SettingsPanel.new())],
			["Leave match", func() -> void: Net.leave()]]:
		var b := Button.new()
		b.text = entry[0]
		b.custom_minimum_size.y = 40
		b.pressed.connect(entry[1])
		col.add_child(b)


func set_menu_open(open: bool) -> void:
	menu_open = open
	_menu.visible = open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED
	if open:
		_rebuild_menu()


func _process(_delta: float) -> void:
	var lines: PackedStringArray = []
	var me := _world.local_player()
	if me:
		lines.append("%s · %s" % [me.display_name, GameData.team_name(me.team)])
	lines.append("Gold: %d" % _game_mode.my_gold)
	for id: String in GameData.RESOURCES:
		lines.append("%s: %d" % [GameData.display_name(id), int(_game_mode.my_inventory.get(id, 0))])
	if not _game_mode.my_stats.is_empty():
		lines.append("K/D: %d / %d" % [_game_mode.my_stats.get("kills", 0), _game_mode.my_stats.get("deaths", 0)])
	_resources.text = "\n".join(lines)

	var s := _game_mode.scores
	_score.text = "%s  %d  —  %d  %s" % [GameData.team_name(0), s[0], s[1], GameData.team_name(1)]
	_clock.text = _clock_text()
	_clock.modulate = Color(0.6, 0.9, 1.0) if _game_mode.lobby else (Color(1.0, 0.75, 0.3) if _game_mode.overtime or (_game_mode.time_left < 60.0 and not _game_mode.match_over) else Color.WHITE)
	var crown_lines: PackedStringArray = []
	for c in _game_mode.crowns:
		crown_lines.append("%s crown: %s" % [GameData.team_name(c.team), _crown_status(c)])
	_crowns.text = "\n".join(crown_lines)

	if me:
		if _last_health >= 0.0 and me.health < _last_health - 0.01:
			_vignette.color.a = clampf((_last_health - me.health) / 60.0, 0.15, 0.45)
		_last_health = me.health
		_vignette.color.a = maxf(_vignette.color.a - _delta_time() * 0.8, 0.0)
		_health.max_value = me.max_health
		_health.value = me.health
		_health_label.text = "%d / %d" % [ceili(me.health), ceili(me.max_health)]
		_mana_bar.max_value = me.max_mana
		_mana_bar.value = me.mana
		_stamina_bar.max_value = GameData.MAX_STAMINA
		_stamina_bar.value = me.stamina
		_voice_label.text = _voice_text()
		if not me.alive:
			_center.text = "You have fallen. Respawning..."
		elif me.stunned:
			_center.text = "Stunned!"
		elif me.carrying_crown >= 0:
			_center.text = "You carry the %s crown! Bring it to your pedestal." % GameData.team_name(me.carrying_crown)
		else:
			var tags: Array[String] = []
			if me.slowed:
				tags.append("Slowed")
			if me.cloaked:
				tags.append("Cloaked: enemies can't see you")
			if me.rallied:
				tags.append("Battle Cry!")
			if me.warded:
				tags.append("Warded")
			_center.text = "  ·  ".join(tags)
		if me.build_page != _hotbar_page:
			_rebuild_hotbar()
		_mode_label.text = _mode_text(me)
		for i in _hotbar.get_child_count():
			_hotbar.get_child(i).modulate = Color.WHITE if i == me.hotbar_index else Color(1, 1, 1, 0.55)


func _voice_text() -> String:
	var voice := _world.voice
	if voice == null:
		return ""
	var lines: PackedStringArray = []
	if voice.talking == VoiceChat.Channel.PROXIMITY:
		lines.append("● TALKING (nearby)")
	elif voice.talking == VoiceChat.Channel.TEAM:
		lines.append("● TALKING (team)")
	for peer: int in voice.speaking:
		var p := _world.get_player(peer)
		if p:
			var team_radio: bool = voice.speaking[peer][1] == VoiceChat.Channel.TEAM
			lines.append("%s %s" % [p.display_name, "(team)" if team_radio else ""])
	return "\n".join(lines)


func _delta_time() -> float:
	return get_process_delta_time()


func _on_hit_confirmed(killed: bool) -> void:
	Sfx.play("hitmarker", -4.0 if killed else -10.0)
	_crosshair.text = "X" if killed else "x"
	_crosshair.modulate = Color(1, 0.25, 0.2) if killed else Color(1, 1, 1)
	if _crosshair_tween:
		_crosshair_tween.kill()
	_crosshair_tween = create_tween()
	_crosshair_tween.tween_interval(0.15 if not killed else 0.4)
	_crosshair_tween.tween_callback(func() -> void:
		_crosshair.text = "+"
		_crosshair.modulate = Color.WHITE)


## Jingles for crown events, from this player's point of view.
func _on_crowns_updated() -> void:
	var me := _world.local_player()
	var my_team := me.team if me else 0
	for c in _game_mode.crowns:
		var before: int = _last_crown_states[c.team]
		if before == c.state:
			continue
		if c.state == CrownRules.State.CARRIED:
			Sfx.play("alarm" if c.team == my_team else "steal")
		elif c.state == CrownRules.State.HOME and before == CrownRules.State.CARRIED:
			Sfx.play("capture" if c.team != my_team else "alarm")
		elif c.state == CrownRules.State.HOME:
			Sfx.play("return")
		_last_crown_states[c.team] = c.state


func _crown_status(c: CrownState) -> String:
	match c.state:
		CrownRules.State.HOME:
			return "safe"
		CrownRules.State.CARRIED:
			var p := _world.get_player(c.carrier)
			return "STOLEN by %s" % (p.display_name if p else "?")
		_:
			var left := GameData.CROWN_AUTO_RETURN - (_game_mode.clock - c.dropped_at)
			return "dropped (returns in %ds)" % maxi(ceili(left), 0)


func _on_private_updated() -> void:
	_rebuild_hotbar()
	if menu_open:
		_rebuild_menu()


func _rebuild_hotbar() -> void:
	for c in _hotbar.get_children():
		c.queue_free()
	var me := _world.local_player()
	_hotbar_page = me.build_page if me else 0
	_hotbar_build_mode = _hotbar_page > 0
	var bar := _game_mode.hotbar_items(_hotbar_page)
	for i in bar.size():
		var id := bar[i]
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(78, 52) if _hotbar_build_mode else Vector2(92, 52)
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.08, 0.08, 0.1, 0.75)
		style.border_color = GameData.item(id).get("color", Color(0.8, 0.8, 0.8))
		style.set_border_width_all(2)
		style.set_corner_radius_all(4)
		panel.add_theme_stylebox_override("panel", style)
		var count := int(_game_mode.my_inventory.get(id, 0))
		var key := str((i + 1) % 10) if i < 10 else ""
		var text := "%s\n%s" % [key, GameData.display_name(id)]
		var def := GameData.item(id)
		if _hotbar_build_mode:
			var recipe := GameData.build_cost(def["recipe"], _skill_rank("mason"))
			text += "\n" + _short_cost(recipe)
			if not _can_afford(recipe):
				style.bg_color = Color(0.3, 0.05, 0.05, 0.75)
		elif def.get("kind", "") == "spell":
			text += "\n%d mana" % int(GameData.spell_mana(def, _skill_rank("spellweaver")))
			style.bg_color = Color(0.08, 0.08, 0.2, 0.8)
		elif count > 1:
			text += " x%d" % count
		var l := _label(text, 11 if _hotbar_build_mode else 12)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		panel.add_child(l)
		_hotbar.add_child(panel)


## The line above the hotbar: build-mode controls, repair/upgrade costs, interactions.
func _mode_text(me: Player) -> String:
	if me.on_ladder:
		return "On a ladder: W to climb, S to climb down"
	var lines: PackedStringArray = []
	if me.build_mode:
		var page: String = GameData.BUILD_CATEGORIES[me.build_page - 1]
		lines.append("BUILD: %s  ·  click place · R rotate · Q next page" % GameData.BUILD_CATEGORY_NAMES[page])
		var piece := me.aimed_piece
		if piece and is_instance_valid(piece):
			var parts: PackedStringArray = []
			if piece.health < piece.max_health:
				parts.append("F repair (%s)" % _short_cost(GameMode.repair_cost(piece)))
			var upgrade: String = GameData.item(piece.item_id).get("upgrade", "")
			if upgrade != "":
				parts.append("G upgrade to %s (%s)" % [GameData.display_name(upgrade), _short_cost(GameData.item(upgrade)["recipe"])])
			if not parts.is_empty():
				lines.append("%s: %s" % [GameData.display_name(piece.item_id), "  ·  ".join(parts)])
	var target := me.interact_target
	if target and is_instance_valid(target):
		if target.is_drawbridge():
			lines.append("E: %s the drawbridge" % ("raise" if target.opened else "lower"))
		elif target.is_catapult():
			lines.append("E: fire the catapult where you aim (aim higher to throw farther; 5 stone)")
	return "\n".join(lines)


func _short_cost(recipe: Dictionary) -> String:
	var parts: PackedStringArray = []
	for res: String in recipe:
		parts.append("%d %s" % [recipe[res], GameData.display_name(res).split(" ")[0].to_lower()])
	return " ".join(parts)


const MENU_HEADINGS := {
	"tool": "Tools", "weapon": "Weapons", "ranged": "Bows", "shield": "Shields (hold right click to block)",
	"ammo": "Ammunition", "structure": "Building (Q to build; Q again for the next page)",
	"consumable": "Potions & items", "spell": "Spells (learn once, cast with mana)",
}


func _skill_rank(skill: String) -> int:
	return int(_game_mode.my_stats.get("skills", {}).get(skill, 0))


func _rebuild_menu() -> void:
	_menu_gold.text = "Gold: %d   " % _game_mode.my_gold
	for c in _menu_list.get_children():
		c.queue_free()
	_add_skill_rows()
	var last_kind := ""
	for id: String in GameData.ITEMS:
		var def := GameData.item(id)
		var kind: String = def["kind"]
		if kind == "structure" and def.get("category", "") == "":
			continue  # summoned, not buildable
		if kind != last_kind:
			last_kind = kind
			_menu_list.add_child(_label(MENU_HEADINGS.get(kind, kind.capitalize()), 20))
		var row := HBoxContainer.new()
		_menu_list.add_child(row)
		var makes := (" (makes %d)" % def["yield"]) if def.has("yield") else ""
		var have := ("  (have %d)" % int(_game_mode.my_inventory.get(id, 0))) if not kind in ["structure", "spell"] else ""
		var cost_line := "Cost: %s%s" % [GameData.cost_text(def["recipe"]), makes]
		if kind == "spell":
			cost_line = "%d mana · %s s cooldown" % [int(GameData.spell_mana(def, _skill_rank("spellweaver"))), str(snappedf(GameData.spell_cooldown(def, _skill_rank("spellweaver")), 0.1))]
		elif kind == "structure":
			cost_line = "Cost: %s" % GameData.cost_text(GameData.build_cost(def["recipe"], _skill_rank("mason")))
		var info := _label("%s%s\n%s\n%s" % [def["name"], have, def.get("desc", ""), cost_line], 14)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		var button := Button.new()
		button.custom_minimum_size = Vector2(170, 0)
		if kind == "structure" and _game_mode.is_unlocked_locally(id):
			button.text = "Build mode (Q)"
			button.disabled = true
			button.tooltip_text = "Building pieces are placed from build mode and cost resources when placed."
		elif kind == "spell" and _game_mode.my_unlocks.has(id):
			button.text = "Learned"
			button.disabled = true
		elif _game_mode.is_unlocked_locally(id) and kind != "spell":
			button.text = "Craft"
			button.disabled = not _can_afford(def["recipe"])
			button.pressed.connect(func() -> void:
				Sfx.play("click")
				_game_mode.request(&"request_craft", [id]))
		else:
			var cost: int = def["unlock_cost"]
			var materials := GameData.learn_materials(id)
			var extra := (" + %s" % _short_cost(materials)) if not materials.is_empty() else ""
			button.text = "%s (%dg%s)" % ["Learn" if kind == "spell" else "Unlock", cost, extra]
			button.disabled = _game_mode.my_gold < cost or not _can_afford(materials)
			button.pressed.connect(func() -> void:
				Sfx.play("click")
				_game_mode.request(&"request_unlock", [id]))
		row.add_child(button)
		var on_bar_kind := kind == "spell" or not kind in ["ammo", "structure", "shield"]
		var owned := _game_mode.my_unlocks.has(id) if kind == "spell" else int(_game_mode.my_inventory.get(id, 0)) > 0
		if on_bar_kind and owned:
			var shown := not _game_mode.is_hidden_on_hotbar(id)
			var toggle := Button.new()
			toggle.custom_minimum_size = Vector2(130, 0)
			toggle.text = "On hotbar ✓" if shown else "Add to hotbar"
			toggle.tooltip_text = "Click to take it off your hotbar (you keep it). You can also press %s on the hotbar." % Settings.binding_text("hide_slot") \
				if shown else "Put it back on your hotbar."
			toggle.pressed.connect(func() -> void:
				Sfx.play("click")
				_game_mode.set_hidden_on_hotbar(id, shown))
			row.add_child(toggle)


## Skills: spend points earned from kills (1) and captures (3). Rank n costs n points.
func _add_skill_rows() -> void:
	var points := int(_game_mode.my_stats.get("skill_points", 0))
	var head := HBoxContainer.new()
	_menu_list.add_child(head)
	var title := _label("Skills — %d point%s to spend (kills give 1, captures 3)" % [points, "" if points == 1 else "s"], 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var reset := Button.new()
	reset.text = "Reset skills"
	reset.tooltip_text = "Take back all your skill ranks and get the points back to spend differently."
	reset.disabled = (_game_mode.my_stats.get("skills", {}) as Dictionary).is_empty()
	reset.pressed.connect(func() -> void:
		Sfx.play("click")
		_game_mode.request(&"request_reset_skills", []))
	head.add_child(reset)
	for skill: String in GameData.SKILLS:
		var def: Dictionary = GameData.SKILLS[skill]
		var rank := _skill_rank(skill)
		var row := HBoxContainer.new()
		_menu_list.add_child(row)
		var info := _label("%s  (rank %d/%d)\n%s" % [def["name"], rank, def["max_rank"], def["desc"]], 14)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		var button := Button.new()
		button.custom_minimum_size = Vector2(170, 0)
		if rank >= int(def["max_rank"]):
			button.text = "Maxed"
			button.disabled = true
		else:
			var cost := GameData.skill_cost(rank)
			button.text = "Rank up (%d pt%s)" % [cost, "" if cost == 1 else "s"]
			button.disabled = points < cost
			button.pressed.connect(func() -> void:
				Sfx.play("click")
				_game_mode.request(&"request_skill", [skill]))
		row.add_child(button)


func _can_afford(recipe: Dictionary) -> bool:
	for id in recipe:
		if int(_game_mode.my_inventory.get(id, 0)) < int(recipe[id]):
			return false
	return true


func _add_message(text: String) -> void:
	var l := _label(text, 15)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_feed.add_child(l)
	while _feed.get_child_count() > FEED_LINES:
		_feed.get_child(0).free()
	var t := l.create_tween()
	t.tween_interval(FEED_SECONDS)
	t.tween_property(l, "modulate:a", 0.0, 1.0)
	t.tween_callback(l.queue_free)


## "24:13" left in the match, or OVERTIME once time ran out with the scores tied.
func _clock_text() -> String:
	if _game_mode.match_over:
		return ""
	if _game_mode.lobby:
		if _game_mode.lobby_countdown >= 0.0:
			return "WARM-UP · match starts in %d" % ceili(_game_mode.lobby_countdown)
		return "WARM-UP · waiting for players (%d/%d)" % [_game_mode.lobby_players, _game_mode.lobby_needed]
	if _game_mode.overtime:
		return "OVERTIME · next capture wins"
	var t := ceili(_game_mode.time_left)
	return "%d:%02d" % [t / 60, t % 60]


func _on_match_over_changed() -> void:
	if _game_mode.match_over:
		Sfx.play("victory")
		_banner.text = "The %s claim the throne!" % GameData.team_name(_game_mode.winner)
		_banner.label_settings.font_color = GameData.team_color(_game_mode.winner).lerp(Color.WHITE, 0.3)
	else:
		_banner.text = ""
