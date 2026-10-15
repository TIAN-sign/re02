extends SceneTree
## Exercises the real production scene and modules. No combat or input substitutes.

const Contract = preload("res://shared/fighter_contract.gd")
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)


func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var game: Node = scene.instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	await process_frame
	_check(game.modules_ready, "Production modules must all be integrated")
	if not game.modules_ready:
		game.queue_free()
		quit(1)
		return
	_check(Engine.physics_ticks_per_second == 60, "Physics driver must use 60 Hz")
	_check(game.match_state["players"].size() == 2, "Match has two fighters")
	var initial_p1: Vector2 = game.match_state["players"][0]["pos"]
	for tick in range(20):
		var input := Contract.neutral_pair()
		input[0]["move_x"] = 1
		game.advance_frame(input)
	_check(game.match_state["players"][0]["pos"].x > initial_p1.x, "Driver forwards movement to combat")
	var prior_frame: int = game.match_state["frame"]
	game.paused = true
	game.advance_frame(Contract.neutral_pair())
	_check(game.match_state["frame"] == prior_frame, "Pause freezes combat ticks")
	game.paused = false
	game.reset_round()
	var attack_result: Dictionary = _attack_until_ko(game)
	_check(attack_result["damage"] and attack_result["event"], "Real attacks produce damage and events through the driver")
	_check(game.match_state["round_over"], "Real attacks reach KO")
	_check(game.match_state["winner"] == 0, "Attacking P1 wins")
	game.reset_round()
	_check(not game.match_state["round_over"], "Rematch clears KO")
	_check(game.match_state["players"][1]["hp"] == Contract.MAX_HEALTH, "Rematch restores health")
	_check(game.match_state["frame"] == 0, "Rematch resets the simulation clock")
	game.set_training_mode(true)
	_check(game.training_enabled, "Training switch enabled")
	_check(not str(game.training.label()).is_empty(), "Training has a HUD label")
	for tick in range(4):
		game.training.cycle_dummy_mode()
	_attack_until_ko(game)
	_check(game.match_state["round_over"], "Training can reach a real KO")
	for tick in range(90):
		game.advance_frame(Contract.neutral_pair())
	_check(not game.match_state["round_over"], "Training automatically restarts after KO")
	_check(game.match_state["players"][1]["hp"] == Contract.MAX_HEALTH, "Training restart refills health")
	game.input_source.sample_frame()
	_check(not game.input_source.history(0).is_empty(), "Input history is supplied by the real module")
	for key in [KEY_F2, KEY_F3]:
		var event := InputEventKey.new()
		event.physical_keycode = key
		event.pressed = true
		game._unhandled_input(event)
	_check(game.show_boxes and game.show_history, "Debug overlays can be toggled")
	game.set_training_mode(false)
	_check(not game.training_enabled and not game.match_state["round_over"], "Mode change starts a clean versus round")
	game.queue_free()
	await process_frame
	if failures.is_empty():
		print("PASS: real scene integration, 60 Hz, movement, pause, attacks, KO, rematch, training auto-reset, history and overlays")
	quit(0 if failures.is_empty() else 1)


func _attack_until_ko(game: Node) -> Dictionary:
	var saw_damage: bool = false
	var saw_event: bool = false
	for tick in range(3600):
		var input := Contract.neutral_pair()
		var players: Array = game.match_state["players"]
		var gap: float = players[1]["pos"].x - players[0]["pos"].x
		input[0]["move_x"] = 1 if gap > 65 else 0
		input[0]["light"] = tick % 48 == 0
		input[0]["heavy"] = tick % 48 == 10
		input[0]["throw"] = tick % 96 == 40
		game.advance_frame(input)
		saw_damage = saw_damage or int(game.match_state["players"][1]["hp"]) < Contract.MAX_HEALTH
		saw_event = saw_event or not game.match_state["events"].is_empty()
		if game.match_state["round_over"]:
			break
	return {"damage": saw_damage, "event": saw_event}
