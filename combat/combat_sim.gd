extends RefCounted
## Pure, fixed-tick combat. All tuning below is original prototype data.

const Contract = preload("res://shared/fighter_contract.gd")
const Fighter = preload("res://combat/fighter_state.gd")
const Moves = preload("res://combat/move_data.gd")
const WALK_SPEED: float = 300.0
const AIR_SPEED: float = 260.0
const JUMP_SPEED: float = 780.0
const GRAVITY: float = 2100.0
const BUFFER_FRAMES: int = 5
const TECH_FRAMES: int = 8
const THROW_PROTECTION: int = 10
const PUSH_WIDTH: float = 48.0
const DT: float = 1.0 / 60.0

var _fighters: Array = []
var _frame: int = 0
var _hitstop: int = 0
var _next_attack: int = 1
var _round_over: bool = false
var _winner: int = -1
var _events: Array[Dictionary] = []
var _inputs: Array[Dictionary] = []


func _init() -> void:
	reset()


func reset() -> void:
	_frame = 0
	_hitstop = 0
	_next_attack = 1
	_round_over = false
	_winner = -1
	_events.clear()
	_inputs = Contract.neutral_pair()
	_fighters.clear()
	for id in range(2):
		var fighter = Fighter.new()
		fighter.id = id
		fighter.hp = Contract.MAX_HEALTH
		fighter.position = Vector2(400.0 if id == 0 else 880.0, Contract.FLOOR_Y)
		fighter.facing = 1 if id == 0 else -1
		_fighters.append(fighter)


func step(inputs: Array[Dictionary]) -> Dictionary:
	_events.clear()
	if _round_over:
		return snapshot()
	_frame += 1
	_inputs = _normalize_inputs(inputs)
	for fighter in _fighters:
		_prune_buffer(fighter)
		_queue_edges(fighter, _inputs[fighter.id])
	if _hitstop > 0:
		_hitstop -= 1
		return snapshot()
	if _advance_throw():
		_age_buffers()
		_check_ko()
		return snapshot()
	for fighter in _fighters:
		_advance_state(fighter)
	_update_facing()
	for fighter in _fighters:
		_choose_action(fighter, _inputs[fighter.id])
		_move(fighter, _inputs[fighter.id])
	_resolve_push()
	_update_facing()
	# Collect every strike from the same world state before applying any damage.
	# Trades therefore do not depend on player iteration order.
	var contacts: Array[Dictionary] = _collect_strikes()
	for contact in contacts:
		_apply_strike(contact)
	# A strike that connects this tick interrupts a throw before its capture.
	_resolve_throws()
	_resolve_push()
	_check_ko()
	_age_buffers()
	return snapshot()


func snapshot() -> Dictionary:
	var players: Array[Dictionary] = []
	var hits: Array[Dictionary] = []
	var hurts: Array[Dictionary] = []
	var pushes: Array[Dictionary] = []
	var throws: Array[Dictionary] = []
	for fighter in _fighters:
		var phase: String = Moves.phase(fighter.move_id, fighter.move_frame)
		players.append({
			"id": fighter.id, "pos": fighter.position, "velocity": fighter.velocity,
			"hp": fighter.hp, "max_hp": Contract.MAX_HEALTH,
			"facing": fighter.facing, "state": fighter.state,
			"state_frame": fighter.move_frame if not fighter.move_id.is_empty() else fighter.state_frame,
			"grounded": fighter.grounded, "crouching": fighter.crouching,
			"combo": fighter.combo_count, "move": fighter.move_id, "phase": phase,
			"stun_remaining": fighter.stun_left, "attack_instance": fighter.attack_instance,
			"throw_age": fighter.throw_age,
		})
		hurts.append({"owner": fighter.id, "rect": _hurtbox(fighter)})
		pushes.append({"owner": fighter.id, "rect": _pushbox(fighter)})
		if not _round_over and phase == "active":
			var box: Dictionary = {"owner": fighter.id, "rect": _attack_box(fighter)}
			if fighter.move_id == "throw":
				throws.append(box)
			else:
				hits.append(box)
	return {
		"frame": _frame, "round_over": _round_over, "winner": _winner,
		"players": players, "events": _events.duplicate(true),
		"hitboxes": hits, "hurtboxes": hurts, "pushboxes": pushes,
		"throwboxes": throws, "hitstop": _hitstop,
	}


func _normalize_inputs(inputs: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = Contract.neutral_pair()
	for id in range(mini(inputs.size(), 2)):
		for key in result[id]:
			if key == "move_x":
				result[id][key] = clampi(int(inputs[id].get(key, 0)), -1, 1)
			else:
				result[id][key] = bool(inputs[id].get(key, false))
	return result


func _queue_edges(fighter, command: Dictionary) -> void:
	# One prioritized attack per tick: throw > heavy > light. Jump is separate.
	for action in ["throw", "heavy", "light"]:
		if command[action]:
			fighter.buffer.append({"action": action, "age": 0, "crouch": command.crouch})
			break
	if command.jump:
		fighter.buffer.append({"action": "jump", "age": 0, "crouch": false})
	# Bound repeated inputs during hitstop; newest intentions take precedence.
	while fighter.buffer.size() > 12:
		fighter.buffer.pop_front()


func _prune_buffer(fighter) -> void:
	for index in range(fighter.buffer.size() - 1, -1, -1):
		if int(fighter.buffer[index].age) >= BUFFER_FRAMES:
			fighter.buffer.remove_at(index)


func _age_buffers() -> void:
	for fighter in _fighters:
		for command in fighter.buffer:
			command.age = int(command.age) + 1


func _advance_state(fighter) -> void:
	fighter.state_frame += 1
	if fighter.throw_invulnerable > 0:
		fighter.throw_invulnerable -= 1
	if fighter.cancel_left > 0:
		fighter.cancel_left -= 1
	if fighter.state in ["throwing", "thrown"]:
		return
	if fighter.stun_left > 0:
		fighter.stun_left -= 1
		if fighter.stun_left == 0:
			if fighter.state == "hitstun":
				_fighters[1 - fighter.id].combo_count = 0
			fighter.clear_action()
			fighter.state_frame = 0
	if not fighter.move_id.is_empty():
		fighter.move_frame += 1
		if fighter.move_frame >= Moves.total_frames(fighter.move_id):
			fighter.clear_action()
			fighter.state_frame = 0


func _choose_action(fighter, command: Dictionary) -> void:
	if fighter.state == "blockstun":
		fighter.crouching = command.crouch
	if fighter.stun_left > 0 or fighter.state in ["throwing", "thrown", "ko"]:
		return
	if not fighter.move_id.is_empty():
		var allowed: Array = Moves.get_move(fighter.move_id).cancel_into
		if fighter.cancel_left > 0:
			for index in range(fighter.buffer.size() - 1, -1, -1):
				var action: String = fighter.buffer[index].action
				if allowed.has(action):
					fighter.buffer.remove_at(index)
					_start_attack(fighter, action)
					return
		return
	fighter.crouching = fighter.grounded and command.crouch
	# Jump first so simultaneous jump+attack produces the aerial normal.
	if fighter.grounded:
		for index in range(fighter.buffer.size() - 1, -1, -1):
			if fighter.buffer[index].action == "jump":
				fighter.buffer.remove_at(index)
				fighter.grounded = false
				fighter.crouching = false
				fighter.velocity = Vector2(float(command.move_x) * AIR_SPEED, -JUMP_SPEED)
				fighter.state = "jump"
				fighter.state_frame = 0
				break
	for index in range(fighter.buffer.size() - 1, -1, -1):
		var queued: Dictionary = fighter.buffer[index]
		var action: String = queued.action
		if action == "jump" or (action == "throw" and not fighter.grounded):
			continue
		fighter.buffer.remove_at(index)
		if action != "throw":
			if not fighter.grounded:
				action = "air"
			elif queued.crouch or fighter.crouching:
				action = "low"
		_start_attack(fighter, action)
		return
	if fighter.grounded:
		var next_state: String = "idle"
		if fighter.crouching:
			next_state = "crouch"
		elif command.guard:
			next_state = "guard"
		elif command.move_x != 0:
			next_state = "walk"
		if next_state != fighter.state:
			fighter.state = next_state
			fighter.state_frame = 0
	else:
		fighter.state = "jump"


func _start_attack(fighter, move_id: String) -> void:
	fighter.clear_attack()
	fighter.move_id = move_id
	fighter.move_frame = 0
	fighter.state_frame = 0
	fighter.attack_instance = _next_attack
	_next_attack += 1
	fighter.crouching = move_id == "low"
	fighter.state = move_id
	if fighter.grounded:
		fighter.velocity.x = 0.0


func _move(fighter, command: Dictionary) -> void:
	if fighter.state in ["throwing", "thrown", "ko"]:
		return
	if fighter.grounded:
		fighter.velocity = Vector2.ZERO
		if fighter.move_id.is_empty() and fighter.stun_left == 0 and not fighter.crouching and not command.guard:
			fighter.velocity.x = float(command.move_x) * WALK_SPEED
	else:
		fighter.velocity.y += GRAVITY * DT
	fighter.position += fighter.velocity * DT
	fighter.position.x = clampf(fighter.position.x, Contract.LEFT_BOUND, Contract.RIGHT_BOUND)
	if not fighter.grounded and fighter.position.y >= Contract.FLOOR_Y:
		fighter.position.y = Contract.FLOOR_Y
		fighter.velocity = Vector2.ZERO
		fighter.grounded = true
		if fighter.move_id == "air":
			fighter.clear_action()
			fighter.state = "landing"
			fighter.state_frame = 0
			fighter.stun_left = 4
		elif fighter.stun_left == 0:
			fighter.state = "idle"
			fighter.state_frame = 0


func _update_facing() -> void:
	for fighter in _fighters:
		if fighter.move_id.is_empty() and not fighter.state in ["throwing", "thrown"]:
			var distance: float = _fighters[1 - fighter.id].position.x - fighter.position.x
			if distance != 0.0:
				fighter.facing = 1 if distance > 0.0 else -1


func _hurtbox(fighter) -> Rect2:
	var height: float = 76.0 if fighter.crouching else 132.0
	return Rect2(fighter.position + Vector2(-26.0, -height), Vector2(52.0, height))


func _pushbox(fighter) -> Rect2:
	var height: float = 70.0 if fighter.crouching else 120.0
	return Rect2(fighter.position + Vector2(-PUSH_WIDTH / 2.0, -height), Vector2(PUSH_WIDTH, height))


func _attack_box(fighter) -> Rect2:
	var move: Dictionary = Moves.get_move(fighter.move_id)
	if move.is_empty():
		return Rect2()
	var box: Rect2 = move.box
	if fighter.facing < 0:
		box.position.x = -box.end.x
	box.position += fighter.position
	return box


func _resolve_push() -> void:
	var first = _fighters[0]
	var second = _fighters[1]
	if not _pushbox(first).intersects(_pushbox(second)):
		return
	var left = first if first.position.x <= second.position.x else second
	var right = second if left == first else first
	var overlap: float = PUSH_WIDTH - (right.position.x - left.position.x)
	if overlap <= 0.0:
		return
	var left_shift: float = minf(overlap / 2.0, left.position.x - Contract.LEFT_BOUND)
	var right_shift: float = minf(overlap - left_shift, Contract.RIGHT_BOUND - right.position.x)
	left_shift = minf(overlap - right_shift, left.position.x - Contract.LEFT_BOUND)
	left.position.x -= left_shift
	right.position.x += right_shift


func _can_block(fighter, level: String) -> bool:
	if not fighter.grounded or not fighter.move_id.is_empty():
		return false
	if fighter.state in ["hitstun", "throwing", "thrown", "ko", "landing"]:
		return false
	var command: Dictionary = _inputs[fighter.id]
	var other = _fighters[1 - fighter.id]
	var back: int = -1 if other.position.x > fighter.position.x else 1
	if not command.guard and command.move_x != back:
		return false
	if level == "low":
		return command.crouch
	if level == "overhead":
		return not command.crouch
	return true


func _collect_strikes() -> Array[Dictionary]:
	var contacts: Array[Dictionary] = []
	for actor in _fighters:
		if actor.move_id.is_empty() or actor.move_id == "throw":
			continue
		if Moves.phase(actor.move_id, actor.move_frame) != "active":
			continue
		var target = _fighters[1 - actor.id]
		if target.state in ["throwing", "thrown", "ko"] or actor.struck_targets.has(target.id):
			continue
		if not _attack_box(actor).intersects(_hurtbox(target)):
			continue
		var move: Dictionary = Moves.get_move(actor.move_id)
		contacts.append({
			"actor": actor.id, "target": target.id, "move": actor.move_id,
			"data": move, "blocked": _can_block(target, move.level),
			"instance": actor.attack_instance, "facing": actor.facing,
		})
		actor.struck_targets[target.id] = true
	return contacts


func _apply_strike(contact: Dictionary) -> void:
	var actor = _fighters[contact.actor]
	var target = _fighters[contact.target]
	var move: Dictionary = contact.data
	var blocked: bool = contact.blocked
	target.clear_attack()
	target.state = "blockstun" if blocked else "hitstun"
	target.state_frame = 0
	target.stun_left = int(move.blockstun if blocked else move.hitstun)
	target.position.x = clampf(target.position.x + float(move.pushback) * int(contact.facing), Contract.LEFT_BOUND, Contract.RIGHT_BOUND)
	if target.grounded:
		target.velocity.x = 0.0
	if blocked:
		actor.combo_count = 0
	else:
		target.hp = maxi(0, target.hp - int(move.damage))
		actor.combo_count += 1
		if actor.attack_instance == int(contact.instance) and actor.move_id == contact.move:
			# The hit tick has already made its action choice. Open N following ticks.
			actor.cancel_left = int(move.cancel_frames) + 1 if not move.cancel_into.is_empty() else 0
	_hitstop = maxi(_hitstop, int(move.hitstop))
	_events.append({
		"type": "block" if blocked else "hit", "actor": actor.id, "target": target.id,
		"damage": 0 if blocked else int(move.damage), "move": contact.move,
		"attack_instance": contact.instance, "combo": actor.combo_count,
	})


func _can_throw(actor, target) -> bool:
	if not actor.grounded or not target.grounded or target.throw_invulnerable > 0:
		return false
	if target.stun_left > 0 or target.state in ["throwing", "thrown", "ko"]:
		return false
	return _attack_box(actor).intersects(_hurtbox(target))


func _resolve_throws() -> void:
	var candidates: Array[int] = []
	for actor in _fighters:
		if actor.move_id == "throw" and Moves.phase("throw", actor.move_frame) == "active":
			if _can_throw(actor, _fighters[1 - actor.id]):
				candidates.append(actor.id)
	if candidates.size() == 2:
		_finish_throw(_fighters[0], _fighters[1], true)
	elif candidates.size() == 1:
		var actor = _fighters[candidates[0]]
		var target = _fighters[1 - actor.id]
		actor.clear_attack()
		target.clear_attack()
		actor.state = "throwing"
		target.state = "thrown"
		actor.state_frame = 0
		target.state_frame = 0
		actor.throw_partner = target.id
		target.throw_partner = actor.id
		actor.throw_age = 0
		target.throw_age = 0
		actor.velocity = Vector2.ZERO
		target.velocity = Vector2.ZERO
		if _inputs[target.id].throw or _consume_tech(target):
			_finish_throw(actor, target, true)


func _consume_tech(fighter) -> bool:
	for index in range(fighter.buffer.size() - 1, -1, -1):
		if fighter.buffer[index].action == "throw":
			fighter.buffer.remove_at(index)
			return true
	return false


func _advance_throw() -> bool:
	for actor in _fighters:
		if actor.state != "throwing":
			continue
		var target = _fighters[actor.throw_partner]
		actor.throw_age += 1
		target.throw_age = actor.throw_age
		if actor.throw_age < TECH_FRAMES and _consume_tech(target):
			_finish_throw(actor, target, true)
			return true
		if actor.throw_age >= TECH_FRAMES:
			_finish_throw(actor, target, false)
			return true
	return false


func _finish_throw(actor, target, teched: bool) -> void:
	var move: Dictionary = Moves.get_move("throw")
	var direction: int = 1 if target.position.x >= actor.position.x else -1
	actor.clear_action()
	target.clear_action()
	actor.buffer.clear()
	target.buffer.clear()
	actor.combo_count = 0
	target.combo_count = 0
	actor.throw_invulnerable = THROW_PROTECTION
	target.throw_invulnerable = THROW_PROTECTION
	actor.crouching = false
	target.crouching = false
	actor.state_frame = 0
	target.state_frame = 0
	actor.position.x = clampf(actor.position.x - 24.0 * direction, Contract.LEFT_BOUND, Contract.RIGHT_BOUND)
	target.position.x = clampf(target.position.x + float(move.pushback) * direction, Contract.LEFT_BOUND, Contract.RIGHT_BOUND)
	# At a wall, transfer the unavailable separation to the other fighter.
	if absf(target.position.x - actor.position.x) < 100.0:
		actor.position.x = clampf(target.position.x - 100.0 * direction, Contract.LEFT_BOUND, Contract.RIGHT_BOUND)
		if absf(target.position.x - actor.position.x) < 100.0:
			target.position.x = clampf(actor.position.x + 100.0 * direction, Contract.LEFT_BOUND, Contract.RIGHT_BOUND)
	if not teched:
		target.hp = maxi(0, target.hp - int(move.damage))
		_hitstop = int(move.hitstop)
	_resolve_push()
	_update_facing()
	_events.append({"type": "throw", "actor": actor.id, "target": target.id,
		"damage": 0 if teched else int(move.damage), "tech": teched})


func _check_ko() -> void:
	if _fighters[0].hp > 0 and _fighters[1].hp > 0:
		return
	_round_over = true
	_winner = -1
	if _fighters[0].hp > 0:
		_winner = 0
	elif _fighters[1].hp > 0:
		_winner = 1
	for fighter in _fighters:
		fighter.buffer.clear()
		fighter.clear_attack()
		fighter.velocity = Vector2.ZERO
		if fighter.hp == 0:
			fighter.state = "ko"
			fighter.state_frame = 0
			_events.append({"type": "ko", "actor": 1 - fighter.id, "target": fighter.id, "damage": 0})
