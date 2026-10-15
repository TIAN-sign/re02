extends RefCounted
## Call sample_frame exactly once per 60 Hz physics tick, before combat.step.
## An optional reader supplies raw frames for deterministic local tests.

const Contract = preload("res://shared/fighter_contract.gd")
const DeviceReader = preload("res://input/device_reader.gd")
const ButtonLatch = preload("res://input/button_latch.gd")
const FrameHistory = preload("res://input/frame_history.gd")
const REPLAY_LIMIT: int = 600

var _reader: RefCounted
var _latches: Array = [ButtonLatch.new(), ButtonLatch.new()]
var _history: Array = [FrameHistory.new(Contract.HISTORY_LIMIT), FrameHistory.new(Contract.HISTORY_LIMIT)]
var _raw_history: Array = [FrameHistory.new(Contract.HISTORY_LIMIT), FrameHistory.new(Contract.HISTORY_LIMIT)]
var _frame: int = 0
var _devices: Array[int] = [-1, -1]
var _replay: Array[Dictionary] = []
var _previous_keyboard: Array[int] = [0, 0]
var _previous_pad: Array[int] = [0, 0]


func _init(reader: RefCounted = null) -> void:
	_reader = DeviceReader.new() if reader == null else reader


func sample_frame() -> Array[Dictionary]:
	var connected: Array[int] = _reader.joypad_ids()
	connected.sort()
	var result: Array[Dictionary] = []
	for player in range(2):
		var device: int = connected[player] if player < connected.size() else -1
		var keyboard: Dictionary = _reader.read_keyboard(player)
		var pad: Dictionary = _reader.read_gamepad(device) if device >= 0 else {"held": 0, "pressed": 0, "released": 0}
		# Read each connected device afresh, so disconnects cannot retain a hold.
		var reassigned: bool = device != _devices[player]
		var previous_pad: int = 0 if reassigned else _previous_pad[player]
		_devices[player] = device
		var held: int = int(keyboard.held) | int(pad.held)
		# Treat keyboard and pad as one logical control. A second source pressing
		# an already-held button must not create another attack or reset duration.
		var continuous_before: int = (_previous_keyboard[player] & ~int(keyboard.released)) | (previous_pad & ~int(pad.released))
		var continuous_after: int = (int(keyboard.held) & ~int(keyboard.pressed)) | (int(pad.held) & ~int(pad.pressed))
		var pressed: int = (int(keyboard.pressed) | int(pad.pressed)) & ~continuous_before
		var released: int = (int(keyboard.released) | int(pad.released)) & ~continuous_after
		_latches[player].set_bits(held)
		_latches[player].add_edges(pressed, released)
		var raw: Dictionary = _latches[player].capture(_frame)
		if reassigned:
			# A button already held on a newly assigned pad is not a fresh press.
			var preheld_pad: int = int(pad.held) & ~int(pad.pressed) & ~int(keyboard.held)
			raw.pressed = int(raw.pressed) & ~preheld_pad
		_previous_keyboard[player] = int(keyboard.held)
		_previous_pad[player] = int(pad.held)
		var normalized := _normalize(raw)
		result.append(normalized)
		var historical := normalized.duplicate(true)
		historical["tick"] = _frame
		historical["frame"] = _frame
		_history[player].record(historical)
		_raw_history[player].record(raw)
	# Preserve a bounded clip FROM reset, rather than evicting its initial state.
	if _replay.size() < REPLAY_LIMIT:
		_replay.append({"frame": _frame, "inputs": result.duplicate(true)})
	_frame += 1
	return result


func history(player: int) -> Array[Dictionary]:
	if player < 0 or player > 1:
		return []
	var frames: Array[Dictionary] = _history[player].recent()
	for frame in frames:
		frame.erase("tick")
	return frames


func raw_history(player: int) -> Array[Dictionary]:
	if player < 0 or player > 1:
		return []
	return _raw_history[player].recent()


func assigned_devices() -> Array[int]:
	return _devices.duplicate()


func replay_frames() -> Array[Dictionary]:
	return _replay.duplicate(true)


func reset() -> void:
	_frame = 0
	_replay.clear()
	for player in range(2):
		_previous_keyboard[player] = 0
		_previous_pad[player] = 0
		_latches[player].reset()
		_history[player].clear()
		_raw_history[player].clear()


static func _normalize(raw: Dictionary) -> Dictionary:
	var held := ButtonLatch.neutralize_opposites(int(raw.held), DeviceReader.LEFT, DeviceReader.RIGHT, DeviceReader.UP, DeviceReader.DOWN)
	var pressed: int = int(raw.pressed)
	var keyboard_jump: bool = (pressed & DeviceReader.UP) != 0 and ((int(raw.held) | pressed) & DeviceReader.DOWN) == 0
	var output := Contract.neutral_input()
	output.move_x = int((held & DeviceReader.RIGHT) != 0) - int((held & DeviceReader.LEFT) != 0)
	output.crouch = (held & DeviceReader.DOWN) != 0
	output.guard = (held & DeviceReader.GUARD) != 0
	output.jump = keyboard_jump or (pressed & DeviceReader.PAD_JUMP) != 0
	output.light = (pressed & DeviceReader.LIGHT) != 0
	output.heavy = (pressed & DeviceReader.HEAVY) != 0
	output.throw = (pressed & DeviceReader.THROW) != 0
	return output
