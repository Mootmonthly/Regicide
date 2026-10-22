extends Node
## Registers the input map in code so it stays readable and diffable.

const KEYS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"jump": [KEY_SPACE],
	"sprint": [KEY_SHIFT],
	"toggle_menu": [KEY_C, KEY_B],
	"scoreboard": [KEY_TAB],
	"build_mode": [KEY_Q],
	"interact": [KEY_E],
	"rotate_piece": [KEY_R],
	"repair": [KEY_F],
	"upgrade": [KEY_G],
	"release_mouse": [KEY_ESCAPE],
}


func _ready() -> void:
	for action in KEYS:
		_ensure(action)
		for key in KEYS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
	for i in 10:
		var action := "hotbar_%d" % (i + 1)
		_ensure(action)
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_1 + i if i < 9 else KEY_0
		InputMap.action_add_event(action, ev)
	_mouse("primary", MOUSE_BUTTON_LEFT)
	_mouse("next_slot", MOUSE_BUTTON_WHEEL_DOWN)
	_mouse("prev_slot", MOUSE_BUTTON_WHEEL_UP)


func _ensure(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)


func _mouse(action: String, button: MouseButton) -> void:
	_ensure(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)
