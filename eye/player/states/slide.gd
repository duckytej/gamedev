class_name PlayerSlideState
extends GroundedState

## Crouch-slide: preserves and slightly boosts momentum with low friction, then
## hands back to normal locomotion when it runs out.

var _time_left := 0.0


func enter(_msg: Dictionary = {}) -> void:
	_time_left = player.config.slide_max_time
	player.velocity.x *= player.config.slide_boost
	player.velocity.z *= player.config.slide_boost


func physics_update(delta: float) -> void:
	_time_left -= delta

	if player.wants_jump():
		machine.transition_to(&"Jump")
		return
	if not player.is_on_floor():
		machine.transition_to(&"Fall")
		return

	var speed := Vector3(player.velocity.x, 0.0, player.velocity.z).length()
	if not player.input.crouch_pressed or speed < player.config.slide_min_speed or _time_left <= 0.0:
		transition_to_locomotion()
		return

	player.apply_ground_movement(
		delta, player.config.sprint_speed, player.config.slide_friction, player.config.ground_accel * 0.5
	)
