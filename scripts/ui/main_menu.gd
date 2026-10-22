extends Control
## Title screen: pick a name, then host, join, or run a dedicated server.

var _name: LineEdit
var _address: LineEdit
var _port: SpinBox
var _team_fill: SpinBox


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.1, 0.15)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(380, 0)
	col.add_theme_constant_override("separation", 10)
	center.add_child(col)

	var title := Label.new()
	title.text = "REGICIDE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color(1.0, 0.8, 0.25))
	col.add_child(title)
	var sub := Label.new()
	sub.text = "Steal their crown. Defend your own."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)

	_name = _field(col, "Name", Net.player_name)
	_address = _field(col, "Server address", Net.address)
	var port_row := HBoxContainer.new()
	col.add_child(port_row)
	var port_label := Label.new()
	port_label.text = "Port"
	port_label.custom_minimum_size.x = 130
	port_row.add_child(port_label)
	_port = SpinBox.new()
	_port.min_value = 1024
	_port.max_value = 65535
	_port.value = Net.port
	_port.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	port_row.add_child(_port)

	var fill_row := HBoxContainer.new()
	col.add_child(fill_row)
	var fill_label := Label.new()
	fill_label.text = "Team size"
	fill_label.custom_minimum_size.x = 130
	fill_label.tooltip_text = "When hosting: bots fill each team up to this many players."
	fill_row.add_child(fill_label)
	_team_fill = SpinBox.new()
	_team_fill.min_value = 0
	_team_fill.max_value = GameData.TEAM_SIZE
	_team_fill.value = Net.team_fill
	_team_fill.suffix = "(bots fill)"
	_team_fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fill_row.add_child(_team_fill)

	_button(col, "Host & Play", Net.Mode.HOST)
	_button(col, "Join", Net.Mode.JOIN)
	_button(col, "Dedicated Server (no player)", Net.Mode.DEDICATED)
	var quit := Button.new()
	quit.text = "Quit"
	quit.pressed.connect(get_tree().quit)
	col.add_child(quit)

	if Net.last_error != "":
		var err := Label.new()
		err.text = Net.last_error
		err.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		err.add_theme_color_override("font_color", Color(1, 0.45, 0.4))
		col.add_child(err)


func _field(parent: Control, label_text: String, value: String) -> LineEdit:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var l := Label.new()
	l.text = label_text
	l.custom_minimum_size.x = 130
	row.add_child(l)
	var edit := LineEdit.new()
	edit.text = value
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(edit)
	return edit


func _button(parent: Control, text: String, mode: Net.Mode) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(func() -> void:
		Net.player_name = _name.text.strip_edges()
		Net.address = _address.text.strip_edges()
		Net.port = int(_port.value)
		Net.team_fill = int(_team_fill.value)
		Net.play(mode))
	parent.add_child(b)
