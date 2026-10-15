extends RefCounted
## Event-fed digital state. Edges survive even a press and release between ticks.
## capture() is called once per simulation tick; repeated reads return a copy.

var _held: int = 0
var _pressed: int = 0
var _released: int = 0
var _last_tick: int = -1
var _held_ticks: Dictionary = {}
var _last_frame: Dictionary = {}


func set_bits(bits: int) -> void:
	assert(bits >= 0, "Input masks must be non-negative")
	_pressed |= bits & ~_held
	_released |= _held & ~bits
	_held = bits


func add_edges(pressed: int, released: int) -> void:
	# The engine preserves short taps even if both transitions precede sampling.
	_pressed |= pressed
	_released |= released


func capture(tick: int) -> Dictionary:
	if tick == _last_tick and not _last_frame.is_empty():
		return _last_frame.duplicate(true)
	# A rewind must use a saved input frame or reset the sampler first.
	if tick < 0 or (_last_tick >= 0 and tick != _last_tick + 1):
		return {}
	var next_durations: Dictionary = {}
	var remaining := _held
	while remaining != 0:
		var bit := remaining & -remaining
		var previous: int = int(_held_ticks.get(bit, 0))
		next_durations[bit] = 1 if (_released & bit) != 0 else previous + 1
		remaining &= ~bit
	_held_ticks = next_durations
	_last_tick = tick
	_last_frame = {
		"tick": tick,
		"held": _held,
		"pressed": _pressed,
		"released": _released,
		"held_ticks": _held_ticks.duplicate(),
	}
	_pressed = 0
	_released = 0
	return _last_frame.duplicate(true)


func release_all() -> void:
	set_bits(0)


func reset() -> void:
	_held = 0
	_pressed = 0
	_released = 0
	_last_tick = -1
	_held_ticks.clear()
	_last_frame.clear()


static func neutralize_opposites(bits: int, left: int, right: int, up: int, down: int) -> int:
	var clean := bits
	if (clean & left) != 0 and (clean & right) != 0:
		clean &= ~(left | right)
	if (clean & up) != 0 and (clean & down) != 0:
		clean &= ~(up | down)
	return clean
