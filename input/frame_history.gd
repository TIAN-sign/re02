extends RefCounted
## Bounded in-memory frames for training display and repeatable local tests.
## No disk recording, networking, or ownership of combat state.

var capacity: int
var _frames: Array[Dictionary] = []
var _next: int = 0


func _init(max_frames: int = 120) -> void:
	capacity = maxi(1, max_frames)


func record(frame: Dictionary) -> bool:
	if not frame.has("tick") or int(frame["tick"]) < 0:
		return false
	if not _frames.is_empty():
		var newest_index := (_next - 1 + _frames.size()) % _frames.size()
		if int(frame["tick"]) <= int(_frames[newest_index]["tick"]):
			return false
	if _frames.size() < capacity:
		_frames.append(frame.duplicate(true))
	else:
		_frames[_next] = frame.duplicate(true)
	_next = (_next + 1) % capacity
	return true


func recent(limit: int = -1) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var count := _frames.size() if limit < 0 else mini(limit, _frames.size())
	var start := (_next - count + _frames.size()) % maxi(1, _frames.size())
	for offset in range(count):
		result.append(_frames[(start + offset) % _frames.size()].duplicate(true))
	return result


func frame_at(tick: int) -> Dictionary:
	for frame in _frames:
		if int(frame["tick"]) == tick:
			return frame.duplicate(true)
	return {}


func clear() -> void:
	_frames.clear()
	_next = 0
