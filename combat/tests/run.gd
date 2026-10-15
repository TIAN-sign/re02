extends SceneTree
## Headless gameplay tests through the public interface; no private state edits.

const Sim = preload("res://combat/combat_sim.gd")
const Contract = preload("res://shared/fighter_contract.gd")
var failures: Array[String] = []
var checks: int = 0


func _initialize() -> void:
	_test_reset_and_copy()
	_test_movement_jump_and_sides()
	_test_attack_frames_and_dedup()
	_test_guard_levels()
	_test_hitstop_and_cancel()
	_test_buffer_boundary()
	_test_cancel_window_boundary()
	_test_throw_rules()
	_test_trade_and_draw()
	_test_punish_and_ko()
	_test_replay()
	if failures.is_empty():
		print("Combat tests PASS: %d assertions across 11 gameplay scenarios" % checks)
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: " + failure)
		printerr("Combat tests FAILED: %d/%d assertions" % [failures.size(), checks])
		quit(1)


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func _pair(first: Dictionary = {}, second: Dictionary = {}) -> Array[Dictionary]:
	var pair: Array[Dictionary] = Contract.neutral_pair()
	pair[0].merge(first, true)
	pair[1].merge(second, true)
	return pair


func _frames(sim, count: int, first: Dictionary = {}, second: Dictionary = {}) -> Dictionary:
	var result: Dictionary = sim.snapshot()
	for tick in range(count):
		result = sim.step(_pair(first, second))
	return result


func _close(sim) -> void:
	for tick in range(100):
		var state: Dictionary = sim.snapshot()
		var distance: float = state.players[1].pos.x - state.players[0].pos.x
		if absf(distance) <= 55.0 or state.round_over:
			return
		var direction: int = 1 if distance > 0 else -1
		sim.step(_pair({"move_x": direction}, {"move_x": -direction}))
	_expect(false, "fighters can approach within 100 ticks")


func _until_event(sim, event_type: String, first: Dictionary = {}, second: Dictionary = {}, limit: int = 70) -> Dictionary:
	for tick in range(limit):
		var result: Dictionary = sim.step(_pair(first, second))
		for event in result.events:
			if event.type == event_type:
				return result
	return sim.snapshot()


func _has_event(state: Dictionary, event_type: String) -> bool:
	for event in state.events:
		if event.type == event_type:
			return true
	return false


func _skip_hitstop(sim) -> void:
	for tick in range(12):
		if sim.snapshot().hitstop == 0:
			return
		sim.step(_pair())
	_expect(false, "hitstop ends within expected maximum")


func _test_reset_and_copy() -> void:
	var sim = Sim.new()
	var initial: Dictionary = sim.snapshot()
	_expect(initial.frame == 0 and initial.players.size() == 2, "ready initial match")
	_expect(initial.players[0].hp == 1000 and initial.players[1].facing == -1, "contract health and facing")
	var edited: Dictionary = sim.snapshot()
	edited.players[0].hp = 0
	edited.hurtboxes[0].owner = 99
	edited.events.append({"type": "fake"})
	_expect(sim.snapshot() == initial, "snapshot is an independent deep copy")
	var input: Array[Dictionary] = _pair({"light": true})
	var saved: Array[Dictionary] = input.duplicate(true)
	sim.step(input)
	_expect(input == saved, "step does not mutate input")
	_frames(sim, 10)
	sim.reset()
	_expect(sim.snapshot() == initial, "reset clears frames, attack ids and pending state")
	_expect(sim.step(_pair()).players[0].state == "idle", "reset leaves no buffered attack")


func _test_movement_jump_and_sides() -> void:
	var sim = Sim.new()
	var state: Dictionary = _frames(sim, 12, {"move_x": 1})
	_expect(is_equal_approx(state.players[0].pos.x, 460.0), "walk covers 60 pixels in 12 ticks")
	_frames(sim, 300, {"move_x": -1}, {"move_x": 1})
	state = sim.snapshot()
	_expect(state.players[0].pos.x == 80.0 and state.players[1].pos.x == 1200.0, "stage boundaries clamp centers")
	sim.reset()
	_close(sim)
	state = _frames(sim, 120, {"move_x": 1}, {"move_x": -1})
	_expect(state.players[1].pos.x - state.players[0].pos.x >= 48.0, "ground pushboxes cannot cross")
	state = _frames(sim, 200, {"move_x": 1}, {"move_x": 1})
	_expect(state.players[1].pos.x == 1200.0 and state.players[1].pos.x - state.players[0].pos.x >= 48.0, "corner pushing preserves separation and bounds")
	sim.reset()
	_close(sim)
	sim.step(_pair({"jump": true, "move_x": 1}))
	state = _frames(sim, 60)
	_expect(state.players[0].grounded and state.players[0].pos.y == 600.0, "jump lands exactly on floor")
	_expect(state.players[0].pos.x > state.players[1].pos.x, "jump can pass over opponent")
	_expect(state.players[0].facing == -1 and state.players[1].facing == 1, "crossing swaps facing")
	_close(sim)
	sim.step(_pair({"light": true}, {"move_x": -1}))
	state = _until_event(sim, "block", {}, {"move_x": -1})
	_expect(_has_event(state, "block") and state.players[1].hp == 1000, "back guard follows side switch")
	sim.reset()
	state = sim.step(_pair({"crouch": true, "move_x": 1}))
	_expect(state.players[0].pos.x == 400.0 and state.players[0].state == "crouch", "crouch cannot walk")


func _test_attack_frames_and_dedup() -> void:
	var sim = Sim.new()
	_close(sim)
	var state: Dictionary = sim.step(_pair({"light": true}))
	_expect(state.players[0].state_frame == 0 and state.players[0].phase == "startup", "attack starts at frame zero")
	for frame in range(1, 5):
		state = sim.step(_pair())
		_expect(state.players[1].hp == 1000 and state.hitboxes.is_empty(), "light has no hitbox before frame 5")
	state = sim.step(_pair())
	_expect(state.players[1].hp == 920 and _has_event(state, "hit"), "light first active frame deals 80")
	_expect(state.hitboxes.size() == 1 and state.hurtboxes.size() == 2 and state.pushboxes.size() == 2, "box categories are separate")
	state = _frames(sim, 50)
	_expect(state.players[1].hp == 920, "active frames and hitstop never duplicate a hit")
	_expect(state.players[0].combo == 0, "combo expires after target recovers")
	_close(sim)
	sim.step(_pair({"light": true}))
	state = _until_event(sim, "hit")
	_expect(state.players[1].hp == 840, "new attack instance can hit same target")


func _test_guard_levels() -> void:
	for crouch in [false, true]:
		var sim = Sim.new()
		_close(sim)
		sim.step(_pair({"light": true}, {"guard": true, "crouch": crouch}))
		var state: Dictionary = _until_event(sim, "block", {}, {"guard": true, "crouch": crouch})
		_expect(state.players[1].hp == 1000 and _has_event(state, "block"), "mid is blocked standing or crouching")
		sim.reset()
		_close(sim)
		sim.step(_pair({"heavy": true, "crouch": true}, {"guard": true, "crouch": crouch}))
		state = _until_event(sim, "block" if crouch else "hit", {}, {"guard": true, "crouch": crouch})
		_expect(state.players[1].hp == (1000 if crouch else 900), "low requires crouch guard")
		sim.reset()
		_close(sim)
		sim.step(_pair({"jump": true, "heavy": true}, {"guard": true, "crouch": crouch}))
		state = _until_event(sim, "hit" if crouch else "block", {}, {"guard": true, "crouch": crouch})
		_expect(state.players[1].hp == (880 if crouch else 1000) and not state.events.is_empty(), "air overhead requires standing guard")
	var airborne = Sim.new()
	_close(airborne)
	airborne.step(_pair({"light": true}, {"jump": true, "guard": true}))
	var result: Dictionary = _until_event(airborne, "hit", {}, {"guard": true})
	_expect(result.players[1].hp == 920, "airborne target cannot block")


func _test_hitstop_and_cancel() -> void:
	var sim = Sim.new()
	_close(sim)
	sim.step(_pair({"light": true}))
	var hit: Dictionary = _until_event(sim, "hit")
	_expect(hit.hitstop == 4 and hit.players[1].stun_remaining == 16, "hitstop and stun have independent counters")
	for tick in range(4):
		var state: Dictionary = sim.step(_pair({"heavy": tick == 0}))
		_expect(state.players[0].pos == hit.players[0].pos and state.players[0].state_frame == hit.players[0].state_frame, "hitstop freezes position and move frame")
		_expect(state.players[1].stun_remaining == 16 and state.events.is_empty(), "hitstop freezes stun and events do not repeat")
	var cancelled: Dictionary = sim.step(_pair())
	_expect(cancelled.players[0].move == "heavy" and cancelled.players[0].state_frame == 0, "hitstop input survives and cancels into heavy")
	var combo: Dictionary = _until_event(sim, "hit")
	_expect(combo.players[1].hp == 760 and combo.players[0].combo == 2, "light-heavy is a true two-hit combo")
	for blocked in [false, true]:
		sim.reset()
		if blocked:
			_close(sim)
		sim.step(_pair({"light": true}, {"guard": blocked}))
		_frames(sim, 5, {}, {"guard": blocked})
		sim.step(_pair({"heavy": true}, {"guard": blocked}))
		var saw_heavy: bool = false
		for tick in range(30):
			var state: Dictionary = sim.step(_pair({}, {"guard": blocked}))
			saw_heavy = saw_heavy or state.players[0].move == "heavy"
		_expect(not saw_heavy, "blocked/whiffed light cannot hit-cancel or retain stale heavy")


func _test_buffer_boundary() -> void:
	for press_frame in [27, 28]:
		var sim = Sim.new()
		sim.step(_pair({"heavy": true}))
		_frames(sim, press_frame - 1)
		sim.step(_pair({"light": true}))
		var state: Dictionary = _frames(sim, 32 - press_frame)
		_expect((state.players[0].move == "light") == (press_frame == 28), "buffer age 4 accepted, age 5 expired")
		if press_frame == 28:
			_expect(state.players[0].state_frame == 0, "buffer fires at first legal tick")
		state = _frames(sim, 30)
		_expect(state.players[0].state == "idle", "consumed buffered edge does not repeat")


func _test_cancel_window_boundary() -> void:
	for after_hit in [6, 7]:
		var sim = Sim.new()
		_close(sim)
		sim.step(_pair({"light": true}))
		_until_event(sim, "hit")
		_skip_hitstop(sim)
		_frames(sim, after_hit - 1)
		var state: Dictionary = sim.step(_pair({"heavy": true}))
		_expect((state.players[0].move == "heavy") == (after_hit == 6), "cancel window permits tick 6 but rejects tick 7")


func _capture(sim) -> Dictionary:
	_close(sim)
	sim.step(_pair({"throw": true}))
	return _frames(sim, 5)


func _test_throw_rules() -> void:
	for tech_frame in [0, 7, 8, -1]:
		var sim = Sim.new()
		_close(sim)
		sim.step(_pair({"throw": true}))
		_frames(sim, 4)
		var state: Dictionary = sim.step(_pair({}, {"throw": tech_frame == 0, "guard": true}))
		if tech_frame != 0:
			_expect(state.players[0].state == "throwing" and state.players[1].state == "thrown", "grounded guard can be captured")
			for tick in range(1, 9):
				state = sim.step(_pair({}, {"throw": tick == tech_frame}))
				if _has_event(state, "throw"):
					break
		var teched: bool = tech_frame == 0 or tech_frame == 7
		_expect(state.players[1].hp == (1000 if teched else 850), "throw tech boundary 0..7; tick 8 is too late")
		_expect(_has_event(state, "throw") and state.events[0].tech == teched, "throw result event reports tech/damage")
		_expect(absf(state.players[0].pos.x - state.players[1].pos.x) > 76.0, "throw outcome separates fighters")
	var mutual = Sim.new()
	_close(mutual)
	mutual.step(_pair({"throw": true}, {"throw": true}))
	var state: Dictionary = _frames(mutual, 5)
	_expect(_has_event(state, "throw") and state.events[0].tech and state.players[0].hp == 1000, "simultaneous throws tech without player priority")
	var whiff = Sim.new()
	whiff.step(_pair({"throw": true}))
	state = _frames(whiff, 5)
	_expect(state.throwboxes.size() == 1 and state.hitboxes.is_empty(), "active throw box is separate from strike box")
	state = _frames(whiff, 12)
	_expect(state.players[0].move == "throw" and state.players[0].phase == "recovery", "out-of-range throw has punishable recovery")
	_expect(state.players[1].hp == 1000, "out-of-range throw cannot damage")
	var air = Sim.new()
	_close(air)
	air.step(_pair({"throw": true}, {"jump": true}))
	state = _frames(air, 30)
	_expect(state.players[1].hp == 1000, "throw cannot capture airborne target")
	var strike = Sim.new()
	_close(strike)
	strike.step(_pair({"throw": true}, {"light": true}))
	state = _frames(strike, 5)
	_expect(state.players[0].hp == 920 and state.players[1].hp == 1000 and state.players[0].state == "hitstun", "same-tick strike interrupts throw")
	var corner = Sim.new()
	_close(corner)
	_frames(corner, 200, {"move_x": 1}, {"move_x": 1})
	corner.step(_pair({"throw": true}))
	state = _until_event(corner, "throw")
	_expect(state.players[1].hp == 850 and state.players[1].pos.x - state.players[0].pos.x >= 100.0, "corner throw still separates outside throw range")


func _test_trade_and_draw() -> void:
	var sim = Sim.new()
	for exchange in range(13):
		_close(sim)
		sim.step(_pair({"light": true}, {"light": true}))
		var state: Dictionary = _frames(sim, 5)
		var hits: int = 0
		for event in state.events:
			if event.type == "hit":
				hits += 1
		_expect(hits == 2 and state.players[0].hp == state.players[1].hp, "same-tick strikes trade equally")
		_frames(sim, 30)
	var final: Dictionary = sim.snapshot()
	_expect(final.round_over and final.winner == -1 and final.players[0].hp == 0 and final.players[1].hp == 0, "simultaneous KO is a draw")
	var next: Dictionary = sim.step(_pair({"heavy": true}, {"throw": true}))
	_expect(next.frame == final.frame and next.players == final.players and next.events.is_empty(), "post-KO step preserves result without repeating events")


func _test_punish_and_ko() -> void:
	var sim = Sim.new()
	_close(sim)
	sim.step(_pair({"heavy": true}, {"guard": true}))
	var state: Dictionary = _until_event(sim, "block", {}, {"guard": true})
	_skip_hitstop(sim)
	# The defender's blockstun ends before the heavy attack's recovery.
	_frames(sim, 11, {}, {"guard": true})
	state = sim.step(_pair({}, {"light": true}))
	_expect(state.players[1].move == "light", "defender can act after blockstun")
	state = _until_event(sim, "hit")
	_expect(state.players[0].hp == 920, "light punishes blocked heavy recovery")
	sim.reset()
	for attack in range(7):
		_close(sim)
		sim.step(_pair({"heavy": true}))
		_until_event(sim, "hit")
		_frames(sim, 50)
	state = sim.snapshot()
	_expect(state.round_over and state.winner == 0 and state.players[1].hp == 0, "one-sided damage produces correct KO winner")
	sim.reset()
	_expect(sim.snapshot() == Sim.new().snapshot(), "rematch restores complete initial state")


func _test_replay() -> void:
	var first = Sim.new()
	var second = Sim.new()
	var rng = RandomNumberGenerator.new()
	rng.seed = 71983
	var same: bool = true
	for tick in range(1800):
		if tick % 600 == 0:
			first.reset()
			second.reset()
		var pair: Array[Dictionary] = Contract.neutral_pair()
		for id in range(2):
			pair[id].move_x = (1 if id == 0 else -1) if tick % 60 < 40 else rng.randi_range(-1, 1)
			pair[id].crouch = rng.randi_range(0, 8) == 0
			pair[id].guard = rng.randi_range(0, 5) == 0
			for action in ["jump", "light", "heavy", "throw"]:
				pair[id][action] = rng.randi_range(0, 25) == 0
		same = (first.step(pair) == second.step(pair)) and same
	_expect(same, "1800-tick replay produces identical full snapshots and events")
