class_name PlayerDashState
extends PlayerState

## Short, high-speed burst in the current steering (or facing) direction.
## Ignores gravity for its duration, then drops back to Fall / ground states.

var _time_left := 0.0
var _direction := Vector3.ZERO


func enter(_msg: Dictionary = {}) -> void:
	_time_left = player.config.dash_time
	_direction = player.accel_dir
	if _direction.is_zero_approx():
		_direction = -player.camera.global_transform.basis.z
	_direction.y = 0.0
	_direction = _direction.normalized()

	player.velocity = _direction * player.config.dash_speed
	player.dash_cooldown_timer = player.config.dash_cooldown


func physics_update(delta: float) -> void:
	_time_left -= delta

	if _time_left <= 0.0:
		if player.is_on_floor():
			machine.transition_to(&"Run" if player.input.sprint_pressed else &"Walk")
		else:
			machine.transition_to(&"Fall")
		return

	player.velocity.x = _direction.x * player.config.dash_speed
	player.velocity.z = _direction.z * player.config.dash_speed
	player.velocity.y = lerpf(player.velocity.y, 0.0, 10.0 * delta)
