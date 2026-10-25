class_name PlayerLandState
extends PlayerState

## Short recovery after touching down: applies the landing dip and a brief
## window before full control returns.

var _time_left := 0.0


func enter(_msg: Dictionary = {}) -> void:
	player.register_landing()
	_time_left = player.config.land_time


func physics_update(delta: float) -> void:
	_time_left -= delta

	if player.wants_jump():
		machine.transition_to(&"Jump")
		return

	var speed: float = locomotion_speed(
		player.config.sprint_speed if player.input.sprint_pressed else player.config.walk_speed
	)
	player.apply_ground_movement(delta, speed)

	if _time_left <= 0.0:
		if player.accel_dir.is_zero_approx():
			machine.transition_to(&"Idle")
		elif player.input.sprint_pressed:
			machine.transition_to(&"Run")
		else:
			machine.transition_to(&"Walk")
