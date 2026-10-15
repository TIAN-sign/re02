extends SceneTree
## Exercises Godot's actual InputMap/InputEvent API on real physics ticks.
## Synthetic joypad events are NOT evidence of physical controller support.

const InputSource = preload("res://input/input_source.gd")
const DeviceReader = preload("res://input/device_reader.gd")

class SyntheticPadReader extends DeviceReader:
	var connected: bool = false

	func joypad_ids() -> Array[int]:
		if connected:
			_register_pad(5)
			return [5]
		return []

class PhysicsProbe extends Node:
	var runner: SceneTree

	func _physics_process(_delta: float) -> void:
		runner.advance_test()

var _reader: RefCounted
var _source: RefCounted
var _tick: int = 0
var _checks: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	Engine.physics_ticks_per_second = 60
	_reader = SyntheticPadReader.new()
	_source = InputSource.new(_reader)
	var probe := PhysicsProbe.new()
	probe.runner = self
	root.add_child.call_deferred(probe)
	_prepare_tick(0)


func _prepare_tick(tick: int) -> void:
	# Input arrives before the consuming physics tick, as OS events normally do.
	match tick:
		0:
			_key(KEY_J, true)
			_key(KEY_D, true)
			_key(KEY_KP_2, true)
		2:
			_key(KEY_J, false)
			_key(KEY_D, false)
			_key(KEY_KP_2, false)
		3:
			_key(KEY_K, true)
			_key(KEY_K, false)
		4:
			_key(KEY_A, true)
			_key(KEY_D, true)
			_key(KEY_W, true)
			_key(KEY_S, true)
		5:
			_key(KEY_A, false)
			_key(KEY_D, false)
			_key(KEY_W, false)
			_key(KEY_S, false)
			_reader.connected = true
			_reader.joypad_ids()
			_pad_button(JOY_BUTTON_A, true)
			_pad_button(JOY_BUTTON_X, true)
			_pad_button(JOY_BUTTON_LEFT_SHOULDER, true)
			_pad_axis(JOY_AXIS_LEFT_X, 0.8)
		6:
			_pad_axis(JOY_AXIS_LEFT_X, 0.1)
		7:
			_pad_button(JOY_BUTTON_A, false)
			_pad_button(JOY_BUTTON_X, false)
			_pad_button(JOY_BUTTON_LEFT_SHOULDER, false)
			_pad_button(JOY_BUTTON_B, true)
			_pad_button(JOY_BUTTON_B, false)
		8:
			_pad_button(JOY_BUTTON_LEFT_SHOULDER, true)
			_pad_axis(JOY_AXIS_LEFT_X, -0.9)
		9:
			_reader.connected = false
		10:
			_key(KEY_J, true)
		11:
			_key(KEY_J, true, true)
		12:
			_key(KEY_J, false)
	Input.flush_buffered_events()


func advance_test() -> void:
	var pair: Array[Dictionary] = _source.sample_frame()
	match _tick:
		0:
			_expect(pair[0].light and pair[0].move_x == 1, "physical P1 keyboard mapping")
			_expect(pair[1].heavy and not pair[1].light, "physical P2 numpad mapping")
		1:
			_expect(not pair[0].light and not pair[1].heavy and pair[0].move_x == 1, "held keys do not repeat combat edges")
		2:
			_expect(pair[0].move_x == 0 and _source.raw_history(0).back().released & DeviceReader.LIGHT != 0, "keyboard release reaches raw history")
		3:
			_expect(pair[0].heavy, "engine retains press-release between sampling ticks")
		4:
			_expect(pair[0].move_x == 0 and not pair[0].jump and not pair[0].crouch, "engine keyboard SOCD")
		5:
			_expect(pair[0].jump and pair[0].light and pair[0].guard and pair[0].move_x == 1, "synthetic controller buttons and stick")
		6:
			_expect(not pair[0].jump and not pair[0].light and pair[0].guard, "controller holds do not repeat edges")
			_expect(pair[0].move_x == 0, "stick dead zone")
		7:
			_expect(pair[0].throw and not pair[0].guard, "controller short tap and guard release")
		8:
			_expect(pair[0].move_x == -1 and pair[0].guard, "controller live state before disconnect")
		9:
			_expect(pair[0].move_x == 0 and not pair[0].guard, "disconnected controller cannot retain held state")
		10:
			_expect(pair[0].light, "keyboard press after disconnect")
		11:
			_expect(not pair[0].light, "keyboard OS echo is not a new attack")
		12:
			_finish()
	_tick += 1
	_prepare_tick(_tick)


func _key(code: Key, pressed: bool, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	event.echo = echo
	Input.parse_input_event(event)


func _pad_button(button: JoyButton, pressed: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.device = 5
	event.button_index = button
	event.pressed = pressed
	Input.parse_input_event(event)


func _pad_axis(axis: JoyAxis, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = 5
	event.axis = axis
	event.axis_value = value
	Input.parse_input_event(event)


func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(description)


func _finish() -> void:
	if _failures.is_empty():
		print("ENGINE_INPUT_TESTS_PASS ticks=%d checks=%d (synthetic devices only)" % [_tick + 1, _checks])
		quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: " + failure)
		printerr("ENGINE_INPUT_TESTS_FAIL checks=%d failures=%d" % [_checks, _failures.size()])
		quit(1)
