extends Node2D
## Presentation and fixed-tick orchestration. Combat is owned by combat/combat_sim.gd.

const Contract = preload("res://shared/fighter_contract.gd")
const CYAN := Color("65e4e1")
const GOLD := Color("ffbd69")
const INK := Color("0a111e")
const WHITE := Color("edf4fa")
const MUTED := Color("889bb2")

var combat: RefCounted
var input_source: RefCounted
var training: RefCounted
var match_state: Dictionary = {}
var training_enabled: bool = false
var show_boxes: bool = false
var show_history: bool = false
var paused: bool = false
var modules_ready: bool = false
var startup_error: String = ""
var displayed_events: Array[Dictionary] = []
var training_reset_ticks: int = 0
var presentation_time: float = 0.0
var font: Font


func _ready() -> void:
	Engine.max_fps = 120
	font = ThemeDB.fallback_font
	_bind_modules()
	queue_redraw()


func _bind_modules() -> void:
	var paths: Array[String] = [
		"res://combat/combat_sim.gd",
		"res://input/input_source.gd",
		"res://training/training_controller.gd",
	]
	for path in paths:
		if not FileAccess.file_exists(path):
			startup_error = "Module not integrated: " + path.get_file()
			return
	var combat_script: Script = load(paths[0])
	var input_script: Script = load(paths[1])
	var training_script: Script = load(paths[2])
	if not combat_script.can_instantiate() or not input_script.can_instantiate() or not training_script.can_instantiate():
		startup_error = "Module parse error. See the Godot output panel."
		return
	combat = combat_script.new()
	input_source = input_script.new()
	training = training_script.new()
	modules_ready = true
	training.call("set_enabled", training_enabled)
	reset_round()


func reset_round() -> void:
	if not modules_ready:
		return
	combat.call("reset")
	input_source.call("reset")
	training.call("reset")
	match_state = combat.call("snapshot")
	displayed_events.clear()
	training_reset_ticks = 0
	paused = false
	queue_redraw()


func set_training_mode(enabled: bool) -> void:
	training_enabled = enabled
	if modules_ready:
		training.call("set_enabled", enabled)
		reset_round()
	queue_redraw()


func advance_frame(inputs: Array[Dictionary]) -> Dictionary:
	if not modules_ready or paused:
		return match_state
	for index in range(displayed_events.size() - 1, -1, -1):
		displayed_events[index]["life"] -= 1
		if displayed_events[index]["life"] <= 0:
			displayed_events.remove_at(index)
	if bool(match_state.get("round_over", false)):
		if training_enabled:
			training_reset_ticks += 1
			if training_reset_ticks >= 90:
				reset_round()
		return match_state
	var effective_inputs: Array[Dictionary] = training.call("apply", inputs, match_state)
	match_state = combat.call("step", effective_inputs)
	for event in match_state.get("events", []):
		var visual_event: Dictionary = event.duplicate(true)
		visual_event["life"] = 18
		var target: int = int(event.get("target", 0))
		var players: Array = match_state.get("players", [])
		if target >= 0 and target < players.size():
			visual_event["pos"] = players[target].get("pos", Vector2(640, 600)) - Vector2(0, 85)
		displayed_events.append(visual_event)
	return match_state


func _physics_process(_delta: float) -> void:
	if not modules_ready or paused:
		return
	var inputs: Array[Dictionary] = input_source.call("sample_frame")
	advance_frame(inputs)


func _process(delta: float) -> void:
	presentation_time += delta
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_F1:
				set_training_mode(not training_enabled)
			KEY_F2:
				show_boxes = not show_boxes
			KEY_F3:
				show_history = not show_history
			KEY_F4:
				if modules_ready and training_enabled:
					training.call("cycle_dummy_mode")
			KEY_R:
				reset_round()
			KEY_ESCAPE:
				paused = not paused
	if event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_START:
			paused = not paused
		elif event.button_index == JOY_BUTTON_BACK:
			reset_round()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var pointer: Vector2 = get_global_mouse_position()
		if Rect2(28, 116, 202, 36).has_point(pointer):
			set_training_mode(not training_enabled)
		elif Rect2(242, 116, 136, 36).has_point(pointer):
			show_boxes = not show_boxes
		elif Rect2(390, 116, 136, 36).has_point(pointer):
			show_history = not show_history
		elif Rect2(1094, 116, 158, 36).has_point(pointer):
			reset_round()


func _draw() -> void:
	if font == null:
		return
	_draw_arena()
	var players: Array = match_state.get("players", [])
	for fighter in players:
		_draw_fighter(fighter)
	_draw_effects()
	if show_boxes:
		_draw_boxes()
	_draw_hud(players)
	if show_history and modules_ready:
		_draw_history(0, Vector2(28, 206), CYAN)
		_draw_history(1, Vector2(1052, 206), GOLD)
	_draw_footer()
	if not modules_ready:
		_draw_message("WAITING FOR MODULES", startup_error, "The scene is ready. Combat has not been substituted.")
	elif paused:
		_draw_message("PAUSED", "Escape / controller Start to resume", "R / controller Back to reset the round")
	elif bool(match_state.get("round_over", false)):
		var winner: int = int(match_state.get("winner", -1))
		var headline: String = "DRAW" if winner < 0 else "PLAYER %d WINS" % (winner + 1)
		var hint: String = "Training resets in a moment" if training_enabled else "R / controller Back / click Restart for a rematch"
		_draw_message("K.O.  /  " + headline, hint, "One arena. Equal tools. Better timing.")


func _draw_arena() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Color("0a111e"))
	for strip in range(12):
		var t: float = float(strip) / 12.0
		draw_rect(Rect2(0, 160 + strip * 37, 1280, 38), Color("101a2b").lerp(Color("293443"), t))
	# An original geometric arena, drawn entirely with Godot primitives.
	draw_circle(Vector2(640, 360), 165, Color("283348"))
	draw_circle(Vector2(640, 360), 142, Color("202d40"))
	draw_arc(Vector2(640, 360), 164, PI * 1.13, PI * 1.88, 64, Color("507078"), 3, true)
	draw_arc(Vector2(640, 360), 143, PI * 0.1, PI * 0.7, 48, Color("5e5259"), 2, true)
	for x in range(0, 1281, 80):
		draw_line(Vector2(x, 164), Vector2(x, 580), Color(0.27, 0.36, 0.46, 0.11), 1)
	for y in range(190, 580, 40):
		draw_line(Vector2(0, y), Vector2(1280, y), Color(0.27, 0.36, 0.46, 0.11), 1)
	_text("V / D", Vector2(518, 405), 82, Color("364355"))
	_text("THE TEST CHAMBER", Vector2(544, 440), 15, Color("5b7184"))
	draw_rect(Rect2(0, 579, 1280, 54), Color("151f2c"))
	draw_line(Vector2(0, 600), Vector2(1280, 600), CYAN.darkened(0.5), 3)
	for x in range(-320, 1601, 80):
		draw_line(Vector2(640 + (x - 640) * 0.75, 600), Vector2(x, 647), Color("324253"), 1)
	draw_line(Vector2(0, 625), Vector2(1280, 625), Color("314453"), 1)
	for x in [80, 320, 640, 960, 1200]:
		draw_line(Vector2(x, 601), Vector2(x, 610), Color("5c7385"), 2)


func _draw_fighter(fighter: Dictionary) -> void:
	var player: int = int(fighter.get("id", 0))
	var pos: Vector2 = fighter.get("pos", Vector2(400 + player * 480, 600))
	var facing: float = float(fighter.get("facing", 1))
	var state: String = str(fighter.get("state", "idle"))
	var frame: int = int(fighter.get("state_frame", 0))
	var accent: Color = CYAN if player == 0 else GOLD
	var is_crouched: bool = bool(fighter.get("crouching", state == "crouch"))
	var is_ko: bool = state == "ko" or state == "knockdown"
	var lean: float = 0.0
	if state in ["light", "heavy", "throw", "throwing", "low", "air"]:
		lean = 13.0
	elif state in ["hitstun", "blockstun", "thrown"]:
		lean = -8.0
	var stance: float = 0.0
	if state == "walk":
		stance = sin(float(frame) * 0.42) * 12.0
	var height: float = 88.0 if is_crouched else 140.0
	if is_ko:
		height = 48.0
	# Shadow remains on the floor while the fighter jumps.
	var shadow_width: float = clampf(45.0 - (Contract.FLOOR_Y - pos.y) * 0.06, 20.0, 45.0)
	draw_set_transform(Vector2(pos.x, Contract.FLOOR_Y + 5), 0, Vector2(shadow_width, 7))
	draw_circle(Vector2.ZERO, 1.0, Color(0, 0, 0, 0.45))
	draw_set_transform(pos, 0, Vector2(facing, 1))
	var hip := Vector2(0, -height * 0.42)
	var chest := Vector2(lean, -height * 0.78)
	var head := Vector2(lean + 3, -height + 14)
	var rear_foot := Vector2(-23 - stance, -5)
	var front_foot := Vector2(23 + stance, -5)
	_limb(hip + Vector2(-8, 0), Vector2(-20, -height * 0.23), rear_foot, accent.darkened(0.46), 15)
	_limb(hip + Vector2(8, 0), Vector2(22, -height * 0.23), front_foot, accent.darkened(0.18), 16)
	draw_line(rear_foot - Vector2(9, 0), rear_foot + Vector2(12, 0), INK, 9, true)
	draw_line(front_foot - Vector2(9, 0), front_foot + Vector2(14, 0), INK, 9, true)
	var torso := PackedVector2Array([
		chest + Vector2(-24, -1), chest + Vector2(21, -3), hip + Vector2(19, 9), hip + Vector2(-18, 9)
	])
	draw_colored_polygon(torso, accent.darkened(0.35))
	draw_line(chest + Vector2(-17, 6), hip + Vector2(-7, -1), accent.lightened(0.1), 5, true)
	draw_line(hip + Vector2(-18, 7), hip + Vector2(19, 7), INK, 9)
	var back_hand := chest + Vector2(-30, 29)
	var front_hand := chest + Vector2(38, -8)
	if state == "light":
		front_hand = chest + Vector2(86, 1)
	elif state in ["heavy", "air"]:
		front_hand = chest + Vector2(103, -15)
	elif state == "low":
		front_hand = chest + Vector2(86, 25)
	elif state in ["throw", "throwing"]:
		front_hand = chest + Vector2(67, 12)
		back_hand = chest + Vector2(60, -8)
	elif state in ["guard", "blockstun"]:
		front_hand = chest + Vector2(28, -20)
		back_hand = chest + Vector2(17, -4)
	elif state in ["hitstun", "thrown"]:
		front_hand = chest + Vector2(47, 35)
	_limb(chest + Vector2(-17, 4), chest + Vector2(-31, 19), back_hand, accent.darkened(0.5), 12)
	_limb(chest + Vector2(16, 4), (chest + front_hand) * 0.5 + Vector2(0, 17), front_hand, accent.darkened(0.08), 13)
	draw_circle(back_hand, 10, INK)
	draw_circle(front_hand, 11, accent)
	draw_circle(head, 19, Color("c2ced7"))
	draw_rect(Rect2(head + Vector2(-18, -4), Vector2(36, 12)), INK)
	draw_line(head + Vector2(4, 1), head + Vector2(20, 1), accent, 4, true)
	draw_line(head + Vector2(-19, -8), head + Vector2(15, -13), accent.darkened(0.15), 7, true)
	draw_set_transform(Vector2.ZERO)
	_text("P%d" % (player + 1), pos + Vector2(-12, -height - 15), 14, accent)


func _limb(a: Vector2, b: Vector2, c: Vector2, color: Color, width: float) -> void:
	draw_line(a, b, color, width, true)
	draw_line(b, c, color, width, true)
	draw_circle(b, width * 0.5, color)


func _draw_effects() -> void:
	for event in displayed_events:
		var point: Vector2 = event.get("pos", Vector2(640, 500))
		var life: float = float(event.get("life", 1)) / 18.0
		var event_type: String = str(event.get("type", "hit"))
		var color: Color = CYAN if event_type == "block" else GOLD
		color.a = life
		for ray in range(8):
			var direction := Vector2.from_angle(float(ray) * TAU / 8.0 + 0.2)
			draw_line(point + direction * (8 + (1 - life) * 18), point + direction * (20 + (1 - life) * 35), color, 3, true)
		if event_type in ["hit", "throw", "block"]:
			var label: String = "THROW TECH" if bool(event.get("tech", false)) else event_type.to_upper()
			_text(label, point + Vector2(-25, -42 - (1 - life) * 15), 15, color)


func _draw_boxes() -> void:
	var colors := {"pushboxes": Color(0.65, 0.55, 1, 0.7), "hurtboxes": Color(0.25, 1, 0.6, 0.8), "hitboxes": Color(1, 0.25, 0.35, 0.9), "throwboxes": Color(1, 0.75, 0.25, 0.9)}
	for group in ["pushboxes", "hurtboxes", "hitboxes", "throwboxes"]:
		var color: Color = colors[group]
		for box in match_state.get(group, []):
			var rect: Rect2 = box.get("rect", Rect2())
			draw_rect(rect, Color(color, 0.12), true)
			draw_rect(rect, color, false, 2)


func _draw_hud(players: Array) -> void:
	draw_rect(Rect2(0, 0, 1280, 104), INK)
	_text("VECTOR / DUEL", Vector2(28, 28), 18, WHITE)
	_text("ORIGINAL FIGHTING PROTOTYPE  /  01", Vector2(955, 26), 12, MUTED)
	for player in range(2):
		var x: float = 28.0 if player == 0 else 742.0
		var accent: Color = CYAN if player == 0 else GOLD
		var hp: int = 1000
		var max_hp: int = 1000
		var state: String = "--"
		var combo: int = 0
		if player < players.size():
			hp = int(players[player].get("hp", 1000))
			max_hp = maxi(1, int(players[player].get("max_hp", 1000)))
			state = str(players[player].get("state", "idle"))
			var phase: String = str(players[player].get("phase", "none"))
			if phase != "none":
				state += " / " + phase + " %df" % int(players[player].get("state_frame", 0))
			combo = int(players[player].get("combo", 0))
		var ratio: float = clampf(float(hp) / float(max_hp), 0, 1)
		_text("P%d   KITE" % (player + 1), Vector2(x, 52), 17, accent)
		_text("%04d / %04d" % [hp, max_hp], Vector2(x + 365, 50), 14, WHITE)
		draw_rect(Rect2(x, 62, 510, 17), Color("263243"))
		var fill_x: float = x if player == 0 else x + 510 * (1 - ratio)
		draw_rect(Rect2(fill_x, 62, 510 * ratio, 17), accent)
		for tick in range(1, 10):
			draw_line(Vector2(x + tick * 51, 62), Vector2(x + tick * 51, 79), Color(0.04, 0.07, 0.11, 0.4), 1)
		_text(state.to_upper(), Vector2(x, 98), 11, MUTED)
		if combo > 1:
			_text("%d HIT CHAIN" % combo, Vector2(x + 360, 98), 13, accent)
	_text("VS", Vector2(611, 74), 34, WHITE)
	_text("60 Hz", Vector2(615, 94), 11, MUTED)
	_button(Rect2(28, 116, 202, 36), "F1  TRAINING" if training_enabled else "F1  LOCAL VERSUS", training_enabled)
	_button(Rect2(242, 116, 136, 36), "F2  BOXES", show_boxes)
	_button(Rect2(390, 116, 136, 36), "F3  INPUTS", show_history)
	_button(Rect2(1094, 116, 158, 36), "R  RESTART", false)
	if training_enabled and modules_ready:
		_text("F4  DUMMY: " + str(training.call("label")).to_upper(), Vector2(28, 181), 15, CYAN)
	else:
		_text("LOCAL TWO PLAYER  /  MIRROR MATCH", Vector2(28, 181), 12, MUTED)
	_text("FRAME %06d" % int(match_state.get("frame", 0)), Vector2(1110, 181), 12, MUTED)
	if show_boxes:
		_text("BOXES: HURT / GREEN   HIT / RED   THROW / GOLD   PUSH / VIOLET", Vector2(425, 622), 11, MUTED)


func _button(rect: Rect2, label: String, active: bool) -> void:
	draw_rect(rect, Color("1c3b43") if active else Color("172332"))
	draw_rect(rect, CYAN.darkened(0.4) if active else Color("334353"), false, 1)
	_text(label, rect.position + Vector2(12, 24), 13, WHITE if active else MUTED)


func _draw_history(player: int, origin: Vector2, accent: Color) -> void:
	draw_rect(Rect2(origin, Vector2(200, 208)), Color(0.035, 0.06, 0.1, 0.92))
	_text("P%d  /  INPUT (PRE-DUMMY)" % (player + 1), origin + Vector2(12, 24), 11, accent)
	var history: Array = input_source.call("history", player)
	var rows: Array[Dictionary] = []
	for index in range(history.size() - 1, -1, -1):
		var item: Dictionary = history[index]
		var description: String = _input_label(item)
		if not rows.is_empty() and rows[-1]["text"] == description:
			rows[-1]["ticks"] += 1
		else:
			if rows.size() >= 8:
				break
			rows.append({"text": description, "ticks": 1})
	for index in range(rows.size()):
		var row: Dictionary = rows[index]
		_text(str(row["text"]), origin + Vector2(12, 49 + index * 20), 13, WHITE if index == 0 else MUTED)
		_text("%df" % int(row["ticks"]), origin + Vector2(160, 49 + index * 20), 12, MUTED)


func _input_label(input: Dictionary) -> String:
	var parts: PackedStringArray = []
	var move: int = int(input.get("move_x", 0))
	if move < 0:
		parts.append("<")
	elif move > 0:
		parts.append(">")
	for key in ["crouch", "jump", "light", "heavy", "throw", "guard"]:
		if bool(input.get(key, false)):
			parts.append({"crouch": "v", "jump": "^", "light": "L", "heavy": "H", "throw": "T", "guard": "G"}[key])
	return " ".join(parts) if not parts.is_empty() else "-"


func _draw_footer() -> void:
	draw_rect(Rect2(0, 649, 1280, 71), INK)
	draw_line(Vector2(28, 649), Vector2(1252, 649), Color("304253"), 1)
	_text("P1", Vector2(28, 675), 14, CYAN)
	_text("WASD MOVE   J LIGHT   K HEAVY   L THROW   U GUARD", Vector2(61, 675), 12, MUTED)
	_text("P2", Vector2(677, 675), 14, GOLD)
	_text("ARROWS MOVE   NUM 1 / 2 / 3 ATTACKS   NUM 0 GUARD", Vector2(710, 675), 12, MUTED)
	_text("PAD: STICK / D-PAD MOVE   A JUMP   X LIGHT   Y HEAVY   B THROW   LB GUARD", Vector2(28, 702), 11, MUTED)
	_text("ESC / START PAUSE     BACK RESET", Vector2(1020, 702), 11, MUTED)


func _draw_message(title: String, subtitle: String, detail: String) -> void:
	draw_rect(Rect2(0, 194, 1280, 430), Color(0.015, 0.025, 0.045, 0.78))
	draw_rect(Rect2(300, 296, 680, 166), Color("122131"))
	draw_line(Vector2(300, 296), Vector2(980, 296), CYAN, 3)
	_center_text(title, 352, 32, WHITE)
	_center_text(subtitle, 393, 17, CYAN)
	_center_text(detail, 429, 13, MUTED)


func _center_text(text: String, y: float, size: int, color: Color) -> void:
	var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	_text(text, Vector2((1280 - width) * 0.5, y), size, color)


func _text(text: String, position: Vector2, size: int, color: Color) -> void:
	draw_string(font, position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
