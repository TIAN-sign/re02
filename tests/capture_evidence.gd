extends SceneTree
## Captures the real Godot viewport after scripted keyboard input through production modules.
## Requires a rendering display; deliberately fails in headless mode.

var game: Node
var output_directory: String
var captures: Array[Dictionary] = []
var desired_keys: Dictionary = {}
var injected_keys: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("Evidence capture requires a rendering display, not the headless driver")
		quit(1)
		return
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	output_directory = arguments[0] if not arguments.is_empty() else "res://docs/evidence"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_directory))
	root.size = Vector2i(1280, 720)
	var scene: PackedScene = load("res://scenes/main.tscn")
	game = scene.instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	await process_frame
	if not game.modules_ready:
		printerr("Cannot capture playable evidence without the real modules")
		quit(1)
		return
	await _capture("versus.png")
	game.set_training_mode(true)
	game.show_boxes = true
	game.show_history = true
	await _approach()
	_key(KEY_J, true)
	await _tick()
	_key(KEY_J, false)
	for tick in range(30):
		await _tick()
		if not game.match_state["hitboxes"].is_empty():
			break
	await _capture("training-hitboxes.png")
	game.set_training_mode(false)
	game.show_boxes = false
	game.show_history = false
	await _approach()
	for tick in range(3600):
		var players: Array = game.match_state["players"]
		_key(KEY_D, players[1]["pos"].x - players[0]["pos"].x > 65)
		_key(KEY_J, tick % 48 == 0)
		_key(KEY_K, tick % 48 == 10)
		_key(KEY_L, tick % 96 == 40)
		await _tick()
		if game.match_state["round_over"]:
			break
	for key in [KEY_D, KEY_J, KEY_K, KEY_L]:
		_key(key, false)
	if not game.match_state["round_over"]:
		printerr("Scripted production input did not reach KO; no KO evidence produced")
		quit(1)
		return
	await _capture("ko.png")
	game.reset_round()
	await _capture("rematch.png")
	var metadata := {
		"engine": Engine.get_version_info()["string"],
		"os": OS.get_name(),
		"display": DisplayServer.get_name(),
		"method": "Real production viewport; scripted keyboard events; no replacement combat state",
		"captures": captures,
	}
	var file := FileAccess.open(output_directory.path_join("capture.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(metadata, "  ") + "\n")
	file.close()
	print("PASS: captured real versus, training, KO and rematch viewports")
	game.queue_free()
	await process_frame
	quit(0)


func _approach() -> void:
	_key(KEY_D, true)
	for tick in range(240):
		var players: Array = game.match_state["players"]
		if players[1]["pos"].x - players[0]["pos"].x < 80:
			break
		await _tick()
	_key(KEY_D, false)
	await _tick()


func _tick() -> void:
	# Inject before the consuming physics tick, matching the production InputMap contract.
	await process_frame
	for key in desired_keys:
		var pressed: bool = desired_keys[key]
		if pressed == bool(injected_keys.get(key, false)):
			continue
		var event := InputEventKey.new()
		event.keycode = key
		event.physical_keycode = key
		event.pressed = pressed
		Input.parse_input_event(event)
		injected_keys[key] = pressed
	Input.flush_buffered_events()
	await physics_frame
	var inputs: Array[Dictionary] = game.input_source.sample_frame()
	game.advance_frame(inputs)


func _key(key: Key, pressed: bool) -> void:
	desired_keys[key] = pressed


func _capture(filename: String) -> void:
	game.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var picture: Image = root.get_texture().get_image()
	var error: Error = picture.save_png(output_directory.path_join(filename))
	if error != OK:
		printerr("Failed to save viewport capture: ", error)
		quit(1)
		return
	captures.append({
		"file": filename,
		"frame": game.match_state["frame"],
		"training": game.training_enabled,
		"round_over": game.match_state["round_over"],
		"winner": game.match_state["winner"],
		"hp": [game.match_state["players"][0]["hp"], game.match_state["players"][1]["hp"]],
		"hitboxes": game.match_state["hitboxes"].size(),
	})
