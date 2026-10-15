extends RefCounted
## Original prototype tuning. Durations are 60 Hz simulation ticks, not SF data.
## Boxes use local Godot coordinates: +x forward, +y down, origin at the feet.

const MOVES: Dictionary = {
	"light": {
		"startup": 5, "active": 2, "recovery": 10,
		"damage": 80, "hitstun": 16, "blockstun": 10, "hitstop": 4,
		"pushback": 18.0, "level": "mid",
		"box": Rect2(18, -88, 50, 30),
		"cancel_into": ["heavy"], "cancel_frames": 6,
	},
	"heavy": {
		"startup": 9, "active": 3, "recovery": 20,
		"damage": 160, "hitstun": 24, "blockstun": 12, "hitstop": 7,
		"pushback": 30.0, "level": "mid",
		"box": Rect2(18, -116, 74, 72),
		"cancel_into": [], "cancel_frames": 0,
	},
	"low": {
		"startup": 7, "active": 3, "recovery": 15,
		"damage": 100, "hitstun": 19, "blockstun": 11, "hitstop": 5,
		"pushback": 22.0, "level": "low",
		"box": Rect2(18, -34, 64, 26),
		"cancel_into": [], "cancel_frames": 0,
	},
	"air": {
		"startup": 6, "active": 5, "recovery": 12,
		"damage": 120, "hitstun": 20, "blockstun": 12, "hitstop": 5,
		"pushback": 24.0, "level": "overhead",
		"box": Rect2(12, -88, 66, 100),
		"cancel_into": [], "cancel_frames": 0,
	},
	"throw": {
		"startup": 5, "active": 2, "recovery": 24,
		"damage": 150, "hitstun": 0, "blockstun": 0, "hitstop": 5,
		"pushback": 76.0, "level": "throw",
		"box": Rect2(12, -80, 38, 80),
		"cancel_into": [], "cancel_frames": 0,
	},
}


static func get_move(move_id: String) -> Dictionary:
	return MOVES.get(move_id, {}).duplicate(true)


static func phase(move_id: String, frame: int) -> String:
	var move: Dictionary = MOVES.get(move_id, {})
	if move.is_empty() or frame < 0:
		return "none"
	if frame < int(move.startup):
		return "startup"
	if frame < int(move.startup) + int(move.active):
		return "active"
	if frame < total_frames(move_id):
		return "recovery"
	return "done"


static func total_frames(move_id: String) -> int:
	var move: Dictionary = MOVES.get(move_id, {})
	return int(move.get("startup", 0)) + int(move.get("active", 0)) + int(move.get("recovery", 0))
