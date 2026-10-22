class_name Hud
extends CanvasLayer
## In-match UI, built in code: resources, gold, health, score, crown status, hotbar,
## message feed, and the Tab menu for crafting and buying blueprints.

const FEED_LINES := 7
const FEED_SECONDS := 8.0

var menu_open := false

var _world: World
var _game_mode: GameMode
var _label_settings: LabelSettings
var _resources: Label
var _score: Label
var _crowns: Label
var _center: Label
var _health: ProgressBar
var _health_label: Label
var _hotbar: HBoxContainer
var _feed: VBoxContainer
var _menu: PanelContainer
var _menu_gold: Label
var _menu_list: VBoxContainer
var _banner: Label


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

	_crowns = _label("", 16)
	_crowns.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_crowns.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_crowns.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_crowns.offset_top = 44
	root.add_child(_crowns)

	var crosshair := _label("+", 24)
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	crosshair.grow_horizontal = Control.GROW_DIRECTION_BOTH
	crosshair.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(crosshair)

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

	_hotbar = HBoxContainer.new()
	_hotbar.alignment = BoxContainer.ALIGNMENT_CENTER
	_hotbar.add_theme_constant_override("separation", 6)
	bottom.add_child(_hotbar)

	var help := _label("WASD move · Shift sprint · Space jump · LMB use · 1-9 / wheel select · Tab craft & shop · Esc free mouse", 13)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bottom.add_child(help)

	_build_menu(root)
	_rebuild_hotbar()


func _build_menu(root: Control) -> void:
	_menu = PanelContainer.new()
	_menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_menu.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_menu.grow_vertical = Control.GROW_DIRECTION_BOTH
	_menu.custom_minimum_size = Vector2(760, 520)
	_menu.visible = false
	root.add_child(_menu)
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


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_menu"):
		set_menu_open(not menu_open)
		get_viewport().set_input_as_handled()


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
	var crown_lines: PackedStringArray = []
	for c in _game_mode.crowns:
		crown_lines.append("%s crown: %s" % [GameData.team_name(c.team), _crown_status(c)])
	_crowns.text = "\n".join(crown_lines)

	if me:
		_health.max_value = me.max_health
		_health.value = me.health
		_health_label.text = "%d / %d" % [ceili(me.health), ceili(me.max_health)]
		if not me.alive:
			_center.text = "You have fallen. Respawning..."
		elif me.carrying_crown >= 0:
			_center.text = "You carry the %s crown! Bring it to your pedestal." % GameData.team_name(me.carrying_crown)
		else:
			_center.text = ""
		for i in _hotbar.get_child_count():
			_hotbar.get_child(i).modulate = Color.WHITE if i == me.hotbar_index else Color(1, 1, 1, 0.55)


func _crown_status(c: CrownState) -> String:
	match c.state:
		CrownRules.State.HOME:
			return "safe"
		CrownRules.State.CARRIED:
			var p := _world.get_player(c.carrier)
			return "STOLEN by %s" % (p.display_name if p else "?")
		_:
			var left := GameData.CROWN_AUTO_RETURN - (Time.get_ticks_msec() / 1000.0 - c.dropped_at)
			return "dropped (returns in %ds)" % maxi(ceili(left), 0)


func _on_private_updated() -> void:
	_rebuild_hotbar()
	if menu_open:
		_rebuild_menu()


func _rebuild_hotbar() -> void:
	for c in _hotbar.get_children():
		c.queue_free()
	var bar := _game_mode.hotbar_items()
	for i in bar.size():
		var id := bar[i]
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(92, 52)
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.08, 0.08, 0.1, 0.75)
		style.border_color = GameData.item(id).get("color", Color(0.8, 0.8, 0.8))
		style.set_border_width_all(2)
		style.set_corner_radius_all(4)
		panel.add_theme_stylebox_override("panel", style)
		var count := int(_game_mode.my_inventory.get(id, 0))
		var text := "%d\n%s" % [i + 1, GameData.display_name(id)]
		if count > 1:
			text += " x%d" % count
		var l := _label(text, 12)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		panel.add_child(l)
		_hotbar.add_child(panel)


func _rebuild_menu() -> void:
	_menu_gold.text = "Gold: %d   " % _game_mode.my_gold
	for c in _menu_list.get_children():
		c.queue_free()
	var last_kind := ""
	for id: String in GameData.ITEMS:
		var def := GameData.item(id)
		var kind: String = def["kind"]
		if kind != last_kind:
			last_kind = kind
			_menu_list.add_child(_label(kind.capitalize() + "s", 20))
		var row := HBoxContainer.new()
		_menu_list.add_child(row)
		var info := _label("%s  (have %d)\n%s\nCost: %s" % [def["name"], int(_game_mode.my_inventory.get(id, 0)), def.get("desc", ""), GameData.cost_text(def["recipe"])], 14)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		var button := Button.new()
		button.custom_minimum_size = Vector2(150, 0)
		if _game_mode.is_unlocked_locally(id):
			button.text = "Craft"
			button.disabled = not _can_afford(def["recipe"])
			button.pressed.connect(func() -> void: _game_mode.request(&"request_craft", [id]))
		else:
			var cost: int = def["unlock_cost"]
			button.text = "Unlock (%dg)" % cost
			button.disabled = _game_mode.my_gold < cost
			button.pressed.connect(func() -> void: _game_mode.request(&"request_unlock", [id]))
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


func _on_match_over_changed() -> void:
	if _game_mode.match_over:
		_banner.text = "The %s claim the throne!" % GameData.team_name(_game_mode.winner)
		_banner.label_settings.font_color = GameData.team_color(_game_mode.winner).lerp(Color.WHITE, 0.3)
	else:
		_banner.text = ""
