extends RefCounted
## Godot device boundary. Action edges are queried during the physics tick.

const LEFT: int = 1
const RIGHT: int = 2
const UP: int = 4
const DOWN: int = 8
const LIGHT: int = 16
const HEAVY: int = 32
const THROW: int = 64
const GUARD: int = 128
const PAD_JUMP: int = 256
const STICK_DEAD_ZONE: float = 0.35
const KEYBOARD_BINDINGS: Array[Dictionary] = [
	{LEFT: KEY_A, RIGHT: KEY_D, UP: KEY_W, DOWN: KEY_S,
	 LIGHT: KEY_J, HEAVY: KEY_K, THROW: KEY_L, GUARD: KEY_U},
	{LEFT: KEY_LEFT, RIGHT: KEY_RIGHT, UP: KEY_UP, DOWN: KEY_DOWN,
	 LIGHT: KEY_KP_1, HEAVY: KEY_KP_2, THROW: KEY_KP_3, GUARD: KEY_KP_0},
]
const PAD_BINDINGS: Dictionary = {
	LEFT: JOY_BUTTON_DPAD_LEFT, RIGHT: JOY_BUTTON_DPAD_RIGHT,
	DOWN: JOY_BUTTON_DPAD_DOWN, PAD_JUMP: JOY_BUTTON_A,
	LIGHT: JOY_BUTTON_X, HEAVY: JOY_BUTTON_Y,
	THROW: JOY_BUTTON_B, GUARD: JOY_BUTTON_LEFT_SHOULDER,
}

var _known_pads: Dictionary = {}


func _init() -> void:
	register_input_map()


func register_input_map() -> void:
	for player in range(2):
		for bit: int in KEYBOARD_BINDINGS[player]:
			var event := InputEventKey.new()
			event.physical_keycode = KEYBOARD_BINDINGS[player][bit]
			_register(_keyboard_action(player, bit), event)


func joypad_ids() -> Array[int]:
	var devices: Array[int] = []
	for device in Input.get_connected_joypads():
		devices.append(device)
	devices.sort()
	for device in devices:
		if not _known_pads.has(device):
			_register_pad(device)
	return devices


func read_keyboard(player: int) -> Dictionary:
	var result := {"held": 0, "pressed": 0, "released": 0}
	for bit: int in KEYBOARD_BINDINGS[player]:
		_read_action(result, bit, _keyboard_action(player, bit))
		if Input.is_physical_key_pressed(KEYBOARD_BINDINGS[player][bit]):
			result.held |= bit
	return result


func read_gamepad(device: int) -> Dictionary:
	var result := {"held": 0, "pressed": 0, "released": 0}
	for bit: int in PAD_BINDINGS:
		_read_action(result, bit, _pad_action(device, bit))
		if Input.is_joy_button_pressed(device, PAD_BINDINGS[bit]):
			result.held |= bit
	for bit: int in [LEFT, RIGHT, DOWN]:
		_read_action(result, bit, _axis_action(device, bit))
	var horizontal := Input.get_joy_axis(device, JOY_AXIS_LEFT_X)
	var vertical := Input.get_joy_axis(device, JOY_AXIS_LEFT_Y)
	if horizontal < -STICK_DEAD_ZONE:
		result.held |= LEFT
	if horizontal > STICK_DEAD_ZONE:
		result.held |= RIGHT
	if vertical > STICK_DEAD_ZONE:
		result.held |= DOWN
	return result


func _register_pad(device: int) -> void:
	for bit: int in PAD_BINDINGS:
		var event := InputEventJoypadButton.new()
		event.device = device
		event.button_index = PAD_BINDINGS[bit]
		_register(_pad_action(device, bit), event)
	for bit: int in [LEFT, RIGHT, DOWN]:
		var event := InputEventJoypadMotion.new()
		event.device = device
		event.axis = JOY_AXIS_LEFT_Y if bit == DOWN else JOY_AXIS_LEFT_X
		event.axis_value = -1.0 if bit == LEFT else 1.0
		_register(_axis_action(device, bit), event)
	_known_pads[device] = true


func _register(action: StringName, event: InputEvent) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, STICK_DEAD_ZONE)
	if not InputMap.action_has_event(action, event):
		InputMap.action_add_event(action, event)


func _read_action(result: Dictionary, bit: int, action: StringName) -> void:
	if Input.is_action_just_pressed(action):
		result.pressed |= bit
	if Input.is_action_just_released(action):
		result.released |= bit


func _keyboard_action(player: int, bit: int) -> StringName:
	return StringName("fighter_p%d_key_%d" % [player + 1, bit])


func _pad_action(device: int, bit: int) -> StringName:
	return StringName("fighter_pad_%d_button_%d" % [device, bit])


func _axis_action(device: int, bit: int) -> StringName:
	return StringName("fighter_pad_%d_axis_%d" % [device, bit])
