extends RefCounted
## Mutable state owned only by the simulation; presentation uses a snapshot.

var id: int = 0
var position: Vector2 = Vector2.ZERO
var velocity: Vector2 = Vector2.ZERO
var facing: int = 1
var hp: int = 1000
var state: String = "idle"
var state_frame: int = 0
var crouching: bool = false
var grounded: bool = true
var stun_left: int = 0
var move_id: String = ""
var move_frame: int = 0
var attack_instance: int = 0
var struck_targets: Dictionary = {}
var cancel_left: int = 0
var buffer: Array[Dictionary] = []
var combo_count: int = 0
var throw_partner: int = -1
var throw_age: int = 0
var throw_invulnerable: int = 0


func clear_attack() -> void:
	move_id = ""
	move_frame = 0
	struck_targets.clear()
	cancel_left = 0


func clear_action() -> void:
	clear_attack()
	stun_left = 0
	throw_partner = -1
	throw_age = 0
	state = "idle" if grounded else "jump"
