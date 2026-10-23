class_name SettingsPanel
extends PanelContainer
## The settings window (main menu and in-game pause menu): Controls, Audio, Graphics.
## Every change applies and saves immediately.

signal closed

var _rebinding := ""  ## action waiting for a key press, or ""
var _bind_buttons: Dictionary = {}  ## action -> Button
var _bind_notes: Dictionary = {}  ## action -> Label (conflict warning)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	custom_minimum_size = Vector2(640, 520)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.08, 0.07, 0.96)
	style.border_color = Color(0.75, 0.6, 0.3)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(16)
	add_theme_stylebox_override("panel", style)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	add_child(col)
	var header := HBoxContainer.new()
	col.add_child(header)
	var title := Label.new()
	title.text = "Settings"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(1.0, 0.82, 0.4))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var done := Button.new()
	done.text = "Done"
	done.pressed.connect(close)
	header.add_child(done)

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(tabs)
	tabs.add_child(_controls_tab())
	tabs.add_child(_audio_tab())
	tabs.add_child(_graphics_tab())
	Settings.changed.connect(_refresh_bindings)


func close() -> void:
	_rebinding = ""
	closed.emit()
	queue_free()


func _scroll(tab_name: String) -> Array:
	var scroll := ScrollContainer.new()
	scroll.name = tab_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	scroll.add_child(box)
	return [scroll, box]


func _row(parent: Control, text: String, control: Control, hint := "") -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var l := Label.new()
	l.text = text
	l.tooltip_text = hint
	l.custom_minimum_size.x = 230
	row.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)


func _slider(section: String, key: String, lo: float, hi: float, step: float, fmt := "%.2f", shown := 1.0) -> HBoxContainer:
	var box := HBoxContainer.new()
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = float(Settings.get_value(section, key))
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size.x = 200
	var v := Label.new()
	v.custom_minimum_size.x = 56
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.text = fmt % (s.value * shown)
	s.value_changed.connect(func(x: float) -> void:
		v.text = fmt % (x * shown)
		Settings.set_value(section, key, x))
	box.add_child(s)
	box.add_child(v)
	return box


func _check(section: String, key: String) -> CheckButton:
	var c := CheckButton.new()
	c.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	c.button_pressed = bool(Settings.get_value(section, key))
	c.toggled.connect(func(on: bool) -> void: Settings.set_value(section, key, on))
	return c


func _controls_tab() -> Control:
	var parts := _scroll("Controls")
	var box: VBoxContainer = parts[1]
	_row(box, "Mouse sensitivity", _slider("controls", "sensitivity", 0.2, 3.0, 0.05, "%.2f×"))
	_row(box, "Invert mouse Y", _check("controls", "invert_y"))
	_row(box, "Field of view", _slider("controls", "fov", 65.0, 105.0, 1.0, "%d°"))
	var head := HBoxContainer.new()
	box.add_child(head)
	var keys := Label.new()
	keys.text = "Keys (click one, then press the new key or mouse button)"
	keys.add_theme_color_override("font_color", Color(1.0, 0.82, 0.4))
	keys.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(keys)
	var reset := Button.new()
	reset.text = "Reset keys"
	reset.pressed.connect(func() -> void: Settings.reset_bindings())
	head.add_child(reset)
	for entry: Array in Settings.REBINDABLE:
		var action: String = entry[0]
		var row := HBoxContainer.new()
		box.add_child(row)
		var l := Label.new()
		l.text = entry[1]
		l.custom_minimum_size.x = 230
		row.add_child(l)
		var b := Button.new()
		b.custom_minimum_size.x = 160
		b.pressed.connect(func() -> void: _start_rebind(action))
		row.add_child(b)
		var note := Label.new()
		note.add_theme_color_override("font_color", Color(1.0, 0.6, 0.35))
		note.add_theme_font_size_override("font_size", 13)
		row.add_child(note)
		_bind_buttons[action] = b
		_bind_notes[action] = note
	_refresh_bindings()
	return parts[0]


func _audio_tab() -> Control:
	var parts := _scroll("Audio")
	var box: VBoxContainer = parts[1]
	_row(box, "Master volume", _slider("audio", "master", 0.0, 1.0, 0.05, "%d%%", 100.0))
	_row(box, "Sound effects", _slider("audio", "effects", 0.0, 1.0, 0.05, "%d%%", 100.0))
	_row(box, "Voice chat (other players)", _slider("audio", "voice", 0.0, 1.0, 0.05, "%d%%", 100.0))
	var tip := Label.new()
	tip.text = "Hold T to talk to players near you, or Y to talk to your whole team."
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.modulate = Color(1, 1, 1, 0.7)
	box.add_child(tip)
	return parts[0]


func _graphics_tab() -> Control:
	var parts := _scroll("Graphics")
	var box: VBoxContainer = parts[1]
	var q := OptionButton.new()
	for i in Settings.QUALITY_NAMES.size():
		q.add_item(Settings.QUALITY_NAMES[i], i)
	q.selected = Settings.quality()
	q.item_selected.connect(func(i: int) -> void: Settings.set_value("graphics", "quality", i))
	_row(box, "Quality", q, "Low: no shadows or grass. Medium: shadows, nearby grass. High: everything.")
	_row(box, "Render scale", _slider("graphics", "render_scale", 0.5, 1.0, 0.05, "%.2f"), "Lower renders the 3D view at a smaller size, for more frames per second.")
	_row(box, "Fullscreen", _check("graphics", "fullscreen"))
	_row(box, "V-Sync", _check("graphics", "vsync"))
	var fps := OptionButton.new()
	for cap: int in Settings.FPS_CAPS:
		fps.add_item("Unlimited" if cap == 0 else "%d FPS" % cap, cap)
	fps.selected = maxi(0, Settings.FPS_CAPS.find(int(Settings.get_value("graphics", "fps_cap"))))
	fps.item_selected.connect(func(i: int) -> void: Settings.set_value("graphics", "fps_cap", Settings.FPS_CAPS[i]))
	_row(box, "Frame rate cap", fps)
	return parts[0]


func _start_rebind(action: String) -> void:
	_rebinding = action
	_refresh_bindings()


func _input(event: InputEvent) -> void:
	if _rebinding == "":
		return
	var usable: bool = (event is InputEventKey and event.pressed and not event.echo) \
		or (event is InputEventMouseButton and event.pressed)
	if not usable:
		return
	get_viewport().set_input_as_handled()
	if event is InputEventKey and (event as InputEventKey).keycode == KEY_ESCAPE:
		_rebinding = ""  # Esc cancels
		_refresh_bindings()
		return
	var action := _rebinding
	_rebinding = ""
	Settings.bind(action, event)


func _refresh_bindings() -> void:
	for action: String in _bind_buttons:
		var b: Button = _bind_buttons[action]
		if not is_instance_valid(b):
			continue
		b.text = "Press a key… (Esc cancels)" if action == _rebinding else Settings.binding_text(action)
		var clash := Settings.conflicts(action)
		(_bind_notes[action] as Label).text = ("Also: " + ", ".join(clash)) if not clash.is_empty() else ""
