extends Node
## Player settings: controls, audio and graphics. Saved to user://settings.cfg and
## applied at startup and whenever something changes (the `changed` signal tells the
## world, player and HUD to pick up new values).

signal changed

const PATH := "user://settings.cfg"
const QUALITY_NAMES := ["Low", "Medium", "High"]
const FPS_CAPS := [0, 60, 120, 144, 240]
## Actions shown on the key-binding list, in order, with the names players see.
const REBINDABLE := [
	["move_forward", "Move forward"], ["move_back", "Move back"], ["move_left", "Move left"],
	["move_right", "Move right"], ["jump", "Jump"], ["sprint", "Sprint"], ["dash", "Dash (skill)"],
	["primary", "Use / attack / cast"], ["block", "Block with shield"], ["interact", "Use drawbridge / catapult"],
	["build_mode", "Build mode"], ["rotate_piece", "Rotate piece"], ["repair", "Repair"], ["upgrade", "Upgrade to stone"],
	["toggle_menu", "Crafting, spells & skills"], ["hide_slot", "Remove item from hotbar"], ["scoreboard", "Scoreboard"], ["camera_toggle", "First / third person"],
	["voice_proximity", "Talk to players nearby"], ["voice_team", "Talk to your team"],
]

const DEFAULTS := {
	"controls": {"sensitivity": 1.0, "invert_y": false, "fov": 80.0},
	"audio": {"master": 0.8, "effects": 1.0, "voice": 1.0},
	"graphics": {"quality": 2, "render_scale": 1.0, "fullscreen": false, "vsync": true, "fps_cap": 0},
	"general": {"seen_help": false, "name": "", "address": "127.0.0.1", "port": 24565, "hidden_hotbar": []},
}

## Section -> key -> value, starting from DEFAULTS.
var values: Dictionary = {}
## action -> event description: {"key": physical keycode} or {"mouse": button index}.
var bindings: Dictionary = {}
var _default_events: Dictionary = {}


func _ready() -> void:
	values = DEFAULTS.duplicate(true)
	_ensure_bus("Effects")
	_ensure_bus("Voice")
	load_settings()
	# The input map is built by the Controls autoload; remember its defaults first.
	_capture_default_bindings.call_deferred()


func get_value(section: String, key: String) -> Variant:
	return values.get(section, {}).get(key, DEFAULTS[section][key])


func set_value(section: String, key: String, value: Variant) -> void:
	if not values.has(section):
		values[section] = {}
	values[section][key] = value
	apply()
	save_settings()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		for section: String in DEFAULTS:
			for key: String in DEFAULTS[section]:
				values[section][key] = cfg.get_value(section, key, DEFAULTS[section][key])
		for action in cfg.get_section_keys("bindings") if cfg.has_section("bindings") else []:
			bindings[action] = cfg.get_value("bindings", action)
	apply()


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for section: String in values:
		for key: String in values[section]:
			cfg.set_value(section, key, values[section][key])
	for action: String in bindings:
		cfg.set_value("bindings", action, bindings[action])
	cfg.save(PATH)


## Push every setting into the engine, then tell listeners.
func apply() -> void:
	_set_bus_volume("Master", get_value("audio", "master"))
	_set_bus_volume("Effects", get_value("audio", "effects"))
	_set_bus_volume("Voice", get_value("audio", "voice"))
	if DisplayServer.get_name() != "headless":
		var full: bool = get_value("graphics", "fullscreen")
		var now := DisplayServer.window_get_mode()
		if full and now != DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		elif not full and now == DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if get_value("graphics", "vsync") else DisplayServer.VSYNC_DISABLED)
		get_tree().root.scaling_3d_scale = clampf(float(get_value("graphics", "render_scale")), 0.5, 1.0)
	Engine.max_fps = int(get_value("graphics", "fps_cap"))
	_apply_bindings()
	changed.emit()


func mouse_sensitivity() -> float:
	return 0.0025 * float(get_value("controls", "sensitivity"))


func quality() -> int:
	return int(get_value("graphics", "quality"))


# --- Key bindings ---------------------------------------------------------------

func _capture_default_bindings() -> void:
	for entry: Array in REBINDABLE:
		var action: String = entry[0]
		if InputMap.has_action(action):
			_default_events[action] = InputMap.action_get_events(action).duplicate()
	_apply_bindings()


## Bind `action` to one key or mouse button (replacing its keyboard/mouse events).
func bind(action: String, event: InputEvent) -> void:
	if event is InputEventKey:
		var k := event as InputEventKey
		bindings[action] = {"key": k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode}
	elif event is InputEventMouseButton:
		bindings[action] = {"mouse": (event as InputEventMouseButton).button_index}
	else:
		return
	_apply_bindings()
	save_settings()
	changed.emit()


func reset_bindings() -> void:
	bindings.clear()
	_apply_bindings()
	save_settings()
	changed.emit()


func _apply_bindings() -> void:
	if _default_events.is_empty():
		return
	for entry: Array in REBINDABLE:
		var action: String = entry[0]
		if not InputMap.has_action(action) or not _default_events.has(action):
			continue
		InputMap.action_erase_events(action)
		if bindings.has(action):
			var ev := _event_from(bindings[action])
			if ev:
				InputMap.action_add_event(action, ev)
				continue
		for ev in _default_events[action]:
			InputMap.action_add_event(action, ev)


func _event_from(d: Dictionary) -> InputEvent:
	if d.has("key"):
		var k := InputEventKey.new()
		k.physical_keycode = int(d["key"])
		return k
	if d.has("mouse"):
		var m := InputEventMouseButton.new()
		m.button_index = int(d["mouse"])
		return m
	return null


## What a player presses for `action`, e.g. "W", "Left Mouse".
func binding_text(action: String) -> String:
	if not InputMap.has_action(action):
		return "?"
	var names: PackedStringArray = []
	for ev in InputMap.action_get_events(action):
		names.append(event_text(ev))
	return " / ".join(names) if not names.is_empty() else "Unbound"


static func event_text(ev: InputEvent) -> String:
	if ev is InputEventKey:
		var k := ev as InputEventKey
		var code := k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
		return OS.get_keycode_string(DisplayServer.keyboard_get_label_from_physical(code)) if DisplayServer.get_name() != "headless" else OS.get_keycode_string(code)
	if ev is InputEventMouseButton:
		match (ev as InputEventMouseButton).button_index:
			MOUSE_BUTTON_LEFT: return "Left Mouse"
			MOUSE_BUTTON_RIGHT: return "Right Mouse"
			MOUSE_BUTTON_MIDDLE: return "Middle Mouse"
			MOUSE_BUTTON_XBUTTON1: return "Mouse 4"
			MOUSE_BUTTON_XBUTTON2: return "Mouse 5"
			MOUSE_BUTTON_WHEEL_UP: return "Wheel Up"
			MOUSE_BUTTON_WHEEL_DOWN: return "Wheel Down"
		return "Mouse %d" % (ev as InputEventMouseButton).button_index
	return "?"


## Other actions already using the same key as `action`.
func conflicts(action: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var mine := InputMap.action_get_events(action) if InputMap.has_action(action) else []
	for entry: Array in REBINDABLE:
		var other: String = entry[0]
		if other == action or not InputMap.has_action(other):
			continue
		for a in mine:
			for b in InputMap.action_get_events(other):
				if event_text(a) == event_text(b):
					out.append(entry[1])
	return out


# --- Audio -------------------------------------------------------------------------

func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	AudioServer.add_bus()
	var idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")


func _set_bus_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(float(linear), 0.0001)))
	AudioServer.set_bus_mute(idx, float(linear) <= 0.001)
