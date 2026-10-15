class_name FighterContract
extends RefCounted
## Stable module boundary for the first playable slice. See docs/interface-contract.md.

const API_VERSION: int = 1
const TICK_RATE: int = 60
const VIEW_SIZE: Vector2i = Vector2i(1280, 720)
const FLOOR_Y: float = 600.0
const LEFT_BOUND: float = 80.0
const RIGHT_BOUND: float = 1200.0
const MAX_HEALTH: int = 1000
const HISTORY_LIMIT: int = 120


static func neutral_input() -> Dictionary:
	return {
		"move_x": 0,
		"crouch": false,
		"guard": false,
		"jump": false,
		"light": false,
		"heavy": false,
		"throw": false,
	}


static func neutral_pair() -> Array[Dictionary]:
	return [neutral_input(), neutral_input()]
