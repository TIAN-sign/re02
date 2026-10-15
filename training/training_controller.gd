extends RefCounted
## Transforms a copied input pair only. The integrator owns UI and round resets.

const Contract = preload("res://shared/fighter_contract.gd")
const MODES: Array[String] = ["manual", "idle", "guard", "jump"]
const LABELS: Dictionary = {"manual": "手动", "idle": "静止", "guard": "防御", "jump": "跳跃"}

var _enabled: bool = false
var _mode_index: int = 1
var _jump_last_tick: bool = false


func set_enabled(enabled: bool) -> void:
	if _enabled != enabled:
		reset()
	_enabled = enabled


func apply(inputs: Array[Dictionary], snapshot: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in inputs:
		result.append(entry.duplicate(true))
	if not _enabled or MODES[_mode_index] == "manual" or result.size() != 2:
		return result
	var dummy := Contract.neutral_input()
	match MODES[_mode_index]:
		"guard":
			dummy.guard = true
		"jump":
			var players: Array = snapshot.get("players", [])
			var grounded: bool = players.size() > 1 and bool(players[1].get("grounded", false))
			dummy.jump = grounded and not _jump_last_tick and not bool(snapshot.get("round_over", false))
			_jump_last_tick = dummy.jump
	result[1] = dummy
	return result


func cycle_dummy_mode() -> String:
	_mode_index = (_mode_index + 1) % MODES.size()
	reset()
	return MODES[_mode_index]


func label() -> String:
	return "训练：" + str(LABELS[MODES[_mode_index]]) if _enabled else "本地双人"


func reset() -> void:
	_jump_last_tick = false


func debug_view(snapshot: Dictionary) -> Dictionary:
	# Return geometry in the contract's world coordinates without mutating state.
	return {
		"frame": int(snapshot.get("frame", 0)),
		"hitboxes": snapshot.get("hitboxes", []).duplicate(true),
		"hurtboxes": snapshot.get("hurtboxes", []).duplicate(true),
	}
