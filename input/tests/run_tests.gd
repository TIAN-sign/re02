extends SceneTree

const ButtonLatch = preload("res://input/button_latch.gd")
const FrameHistory = preload("res://input/frame_history.gd")
const InputSource = preload("res://input/input_source.gd")
const DeviceReader = preload("res://input/device_reader.gd")
const TrainingController = preload("res://training/training_controller.gd")
const Contract = preload("res://shared/fighter_contract.gd")

class ScriptedReader extends RefCounted:
	var devices: Array[int] = []
	var keyboards: Array[Dictionary] = [{"held": 0, "pressed": 0, "released": 0}, {"held": 0, "pressed": 0, "released": 0}]
	var pads: Dictionary = {}

	func joypad_ids() -> Array[int]:
		return devices.duplicate()

	func read_keyboard(player: int) -> Dictionary:
		return keyboards[player].duplicate(true)

	func read_gamepad(device: int) -> Dictionary:
		return pads.get(device, {"held": 0, "pressed": 0, "released": 0}).duplicate(true)

	func clear_edges() -> void:
		for keyboard in keyboards:
			keyboard.pressed = 0
			keyboard.released = 0
		for pad: Dictionary in pads.values():
			pad.pressed = 0
			pad.released = 0

var _checks: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	_test_latch()
	_test_opposites()
	_test_history()
	_test_source()
	_test_shared_controls()
	_test_training()
	_test_repeatable_frames()
	if _failures.is_empty():
		print("INPUT_TESTS_PASS checks=%d" % _checks)
		quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: " + failure)
		printerr("INPUT_TESTS_FAIL checks=%d failures=%d" % [_checks, _failures.size()])
		quit(1)


func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(description)


func _test_latch() -> void:
	var latch = ButtonLatch.new()
	latch.set_bits(16)
	var first: Dictionary = latch.capture(0)
	_expect(first.held == 16 and first.pressed == 16 and first.released == 0, "press on first tick")
	_expect(first.held_ticks[16] == 1, "first held duration")
	first.held_ticks[16] = 999
	_expect(latch.capture(0).held_ticks[16] == 1, "capture returns an isolated copy")
	latch.set_bits(0)
	_expect(latch.capture(0).held == 16, "same tick stays immutable after later events")
	var second: Dictionary = latch.capture(1)
	_expect(second.held == 0 and second.pressed == 0 and second.released == 16, "release on next tick")
	latch.set_bits(32)
	latch.set_bits(0)
	var tap: Dictionary = latch.capture(2)
	_expect(tap.held == 0 and tap.pressed == 32 and tap.released == 32, "short tap retains both edges")
	latch.set_bits(16)
	latch.capture(3)
	var sustained: Dictionary = latch.capture(4)
	_expect(sustained.pressed == 0 and sustained.held_ticks[16] == 2, "hold increments without repeating press")
	latch.set_bits(0)
	latch.set_bits(16)
	var repress: Dictionary = latch.capture(5)
	_expect(repress.pressed == 16 and repress.released == 16 and repress.held_ticks[16] == 1, "repress restarts held duration")
	latch.release_all()
	_expect(latch.capture(6).released == 16, "release all emits release edge")
	_expect(latch.capture(5).is_empty(), "sampler does not read live input for past ticks")
	_expect(latch.capture(8).is_empty(), "skipping an unrecorded tick is rejected")
	latch.reset()
	var reset: Dictionary = latch.capture(0)
	_expect(reset.held == 0 and reset.pressed == 0 and reset.released == 0, "new round reset clears edges and tick")


func _test_opposites() -> void:
	_expect(ButtonLatch.neutralize_opposites(1 | 2 | 16, 1, 2, 4, 8) == 16, "left plus right is neutral without dropping attack")
	_expect(ButtonLatch.neutralize_opposites(4 | 8, 1, 2, 4, 8) == 0, "up plus down is neutral")
	_expect(ButtonLatch.neutralize_opposites(2 | 4, 1, 2, 4, 8) == 6, "diagonal is preserved")


func _test_history() -> void:
	var history = FrameHistory.new(3)
	_expect(history.recent().is_empty(), "empty history can be displayed")
	var input := {"tick": 0, "held": 16, "held_ticks": {16: 1}}
	_expect(history.record(input), "history accepts first input")
	input.held_ticks[16] = 777
	_expect(history.frame_at(0).held_ticks[16] == 1, "history copies caller data")
	_expect(not history.record({"tick": 0}), "duplicate tick is not recorded")
	for tick in range(1, 5):
		history.record({"tick": tick, "held": tick})
	var frames: Array[Dictionary] = history.recent()
	_expect(frames.size() == 3 and frames[0].tick == 2 and frames[2].tick == 4, "history wraps in chronological order")
	_expect(history.frame_at(0).is_empty(), "old input is evicted")
	var last_two: Array[Dictionary] = history.recent(2)
	_expect(last_two[0].tick == 3 and last_two[1].tick == 4, "limited history returns newest frames")
	last_two[0].held = 888
	_expect(history.frame_at(3).held == 3, "history read does not mutate replay source")
	_expect(history.recent(0).is_empty(), "zero history limit is valid")
	history.clear()
	_expect(history.recent().is_empty() and history.record({"tick": 0}), "round reset clears history and tick range")


func _test_source() -> void:
	var reader := ScriptedReader.new()
	var source = InputSource.new(reader)
	reader.keyboards[0] = {"held": DeviceReader.RIGHT | DeviceReader.LIGHT | DeviceReader.GUARD, "pressed": DeviceReader.LIGHT, "released": 0}
	reader.keyboards[1] = {"held": DeviceReader.LEFT | DeviceReader.DOWN, "pressed": 0, "released": 0}
	var pair: Array[Dictionary] = source.sample_frame()
	_expect(pair.size() == 2 and pair[0].keys().size() == 7, "public pair follows contract schema")
	_expect(pair[0].move_x == 1 and pair[0].light and pair[0].guard, "P1 move, attack, guard")
	_expect(pair[1].move_x == -1 and pair[1].crouch and not pair[1].light, "P2 stays independent")
	reader.clear_edges()
	pair = source.sample_frame()
	_expect(not pair[0].light and pair[0].guard, "attack is edge, guard is held")
	reader.keyboards[0] = {"held": DeviceReader.LEFT | DeviceReader.RIGHT | DeviceReader.UP | DeviceReader.DOWN, "pressed": DeviceReader.UP, "released": 0}
	pair = source.sample_frame()
	_expect(pair[0].move_x == 0 and not pair[0].crouch and not pair[0].jump, "opposing keyboard axes are neutral")
	reader.keyboards[0] = {"held": 0, "pressed": DeviceReader.HEAVY, "released": DeviceReader.HEAVY}
	pair = source.sample_frame()
	_expect(pair[0].heavy, "short tap reaches combat even without a held sample")
	_expect(source.raw_history(0).back().released & DeviceReader.HEAVY != 0, "release is retained in raw history")
	reader.keyboards[0] = {"held": 0, "pressed": 0, "released": 0}
	reader.devices = [9, 4, 12]
	reader.pads[4] = {"held": DeviceReader.RIGHT | DeviceReader.GUARD, "pressed": DeviceReader.PAD_JUMP, "released": 0}
	reader.pads[9] = {"held": DeviceReader.THROW, "pressed": DeviceReader.THROW, "released": 0}
	pair = source.sample_frame()
	_expect(source.assigned_devices() == [4, 9], "first two sorted devices assigned to players")
	_expect(pair[0].guard and pair[0].jump and pair[1].throw, "gamepad channels and south jump")
	reader.devices = []
	reader.clear_edges()
	pair = source.sample_frame()
	_expect(not pair[0].guard and pair[0].move_x == 0 and not pair[1].throw, "disconnect releases gamepad actions")
	_expect(source.raw_history(0).back().released & DeviceReader.GUARD != 0, "disconnect records a release")
	var saved: Array[Dictionary] = source.history(0)
	saved[0].light = false
	_expect(source.history(0)[0].light, "normalized history is isolated from consumer mutation")
	_expect(source.history(-1).is_empty() and source.raw_history(2).is_empty(), "invalid history player is harmless")
	for tick in range(130):
		source.sample_frame()
	_expect(source.history(0).size() == Contract.HISTORY_LIMIT, "public history is bounded")
	for tick in range(InputSource.REPLAY_LIMIT):
		source.sample_frame()
	var replay: Array[Dictionary] = source.replay_frames()
	_expect(replay.size() == InputSource.REPLAY_LIMIT and replay[0].frame == 0, "replay retains a bounded clip from reset")
	replay[0].inputs[0].light = false
	_expect(source.replay_frames()[0].inputs[0].light, "replay is isolated from caller mutation")
	source.reset()
	_expect(source.history(0).is_empty() and source.replay_frames().is_empty(), "source reset clears history and replay")
	source.sample_frame()
	_expect(source.history(0)[0].frame == 0, "source reset restarts local frame numbering")


func _test_training() -> void:
	var trainer = TrainingController.new()
	var pair := Contract.neutral_pair()
	pair[0].light = true
	pair[1].heavy = true
	var state := {"frame": 3, "players": [{"grounded": true}, {"grounded": true}], "hitboxes": [{"owner": 0, "rect": Rect2(1, 2, 3, 4)}], "hurtboxes": [], "round_over": false}
	var original := state.duplicate(true)
	var output: Array[Dictionary] = trainer.apply(pair, state)
	_expect(output == pair, "disabled training preserves both inputs")
	output[0].light = false
	_expect(pair[0].light, "disabled training returns copies")
	trainer.set_enabled(true)
	output = trainer.apply(pair, state)
	_expect(output[0] == pair[0] and output[1] == Contract.neutral_input(), "idle dummy replaces only P2")
	_expect(trainer.cycle_dummy_mode() == "guard", "dummy cycles idle to guard")
	output = trainer.apply(pair, state)
	_expect(output[1].guard and not output[1].heavy, "guard dummy requests explicit guard")
	_expect(trainer.cycle_dummy_mode() == "jump", "dummy cycles guard to jump")
	_expect(trainer.apply(pair, state)[1].jump, "grounded dummy requests jump")
	_expect(not trainer.apply(pair, state)[1].jump, "dummy jump releases on following tick")
	_expect(trainer.apply(pair, state)[1].jump, "blocked grounded jump can retry with a fresh edge")
	state.players[1].grounded = false
	_expect(not trainer.apply(pair, state)[1].jump, "dummy does not request airborne jumps")
	state.players[1].grounded = true
	_expect(trainer.apply(pair, state)[1].jump, "landing produces a fresh jump")
	trainer.reset()
	_expect(trainer.apply(pair, state)[1].jump, "training reset clears transient jump state")
	_expect(trainer.cycle_dummy_mode() == "manual", "dummy cycles jump to manual")
	_expect(trainer.apply(pair, state) == pair, "manual training preserves P2 controls")
	_expect(trainer.cycle_dummy_mode() == "idle", "dummy cycles manual to idle")
	_expect(state == original and pair[1].heavy, "training never mutates snapshot or caller inputs")
	var view: Dictionary = trainer.debug_view(state)
	view.hitboxes[0].owner = 1
	_expect(state.hitboxes[0].owner == 0, "debug geometry is a deep copy")
	trainer.set_enabled(false)
	_expect(not trainer.label().is_empty(), "training label can be displayed")


func _test_shared_controls() -> void:
	var reader := ScriptedReader.new()
	var source = InputSource.new(reader)
	reader.devices = [4]
	reader.keyboards[0] = {"held": DeviceReader.LIGHT, "pressed": DeviceReader.LIGHT, "released": 0}
	reader.pads[4] = {"held": 0, "pressed": 0, "released": 0}
	_expect(source.sample_frame()[0].light, "keyboard begins shared action")
	reader.clear_edges()
	reader.pads[4] = {"held": DeviceReader.LIGHT, "pressed": DeviceReader.LIGHT, "released": 0}
	_expect(not source.sample_frame()[0].light, "second source does not repress an already-held action")
	reader.clear_edges()
	reader.keyboards[0] = {"held": 0, "pressed": 0, "released": DeviceReader.LIGHT}
	source.sample_frame()
	var raw: Dictionary = source.raw_history(0).back()
	_expect(raw.held == DeviceReader.LIGHT and raw.released == 0 and raw.held_ticks[DeviceReader.LIGHT] == 3, "one source release keeps the other source held continuously")
	reader.clear_edges()
	reader.devices = [9]
	reader.pads[9] = {"held": DeviceReader.HEAVY, "pressed": 0, "released": 0}
	_expect(not source.sample_frame()[0].heavy, "preheld action on reassigned controller does not fire")
	reader.pads[9] = {"held": 0, "pressed": 0, "released": DeviceReader.HEAVY}
	source.sample_frame()
	reader.pads[9] = {"held": DeviceReader.HEAVY, "pressed": DeviceReader.HEAVY, "released": 0}
	_expect(source.sample_frame()[0].heavy, "reassigned controller can release and press normally")


func _test_repeatable_frames() -> void:
	var first_reader := ScriptedReader.new()
	var second_reader := ScriptedReader.new()
	var first = InputSource.new(first_reader)
	var second = InputSource.new(second_reader)
	var same: bool = true
	var emitted: Array[Dictionary] = []
	for tick in range(240):
		var bits: int = DeviceReader.LEFT if tick % 9 < 4 else DeviceReader.RIGHT
		if tick % 7 == 0:
			bits |= DeviceReader.LIGHT
		var raw := {"held": bits, "pressed": 0, "released": 0}
		first_reader.keyboards[0] = raw.duplicate()
		second_reader.keyboards[0] = raw.duplicate()
		var pair: Array[Dictionary] = first.sample_frame()
		emitted.append({"frame": tick, "inputs": pair.duplicate(true)})
		if pair != second.sample_frame():
			same = false
	_expect(same and first.history(0) == second.history(0), "same raw stream yields repeatable normalized frames")
	_expect(emitted == first.replay_frames(), "saved clip exactly reproduces emitted frame inputs")
