class_name PlayerWallRunState
extends PlayerState

## Running along a vertical wall while airborne, with reduced gravity and a
## wall-jump launch. Ended by leaving the wall, timing out or landing.

var _wall_normal := Vector3.ZERO
var _time_left := 0.0


func enter(_msg: Dictionary = {}) -> void:
	_wall_normal = player.get_wall_normal()
	_time_left = player.config.wall_run_max_time
	if player.velocity.y < 0.0:
		player.velocity.y *= 0.5


func physics_update(delta: float) -> void:
	_time_left -= delta

	if player.is_on_floor():
		machine.transition_to(&"Land")
		return
	if not player.is_touching_wall():
		machine.transition_to(&"Fall")
		return
	if player.wants_jump():
		player.velocity = _wall_normal * player.config.wall_jump_push
		player.velocity.y = player.config.jump_velocity
		player.consume_jump()
		machine.transition_to(&"Jump")
		return
	if player.input.dash_just_pressed and player.can_dash():
		machine.transition_to(&"Dash")
		return
	if _time_left <= 0.0:
		machine.transition_to(&"Fall")
		return

	player.apply_gravity(delta, player.config.wall_run_gravity_scale)

	var tangent := Vector3.UP.cross(_wall_normal)
	if tangent.length_squared() < 1e-6:
		machine.transition_to(&"Fall")
		return
	tangent = tangent.normalized()

	var steer := player.accel_dir
	if steer.is_zero_approx():
		steer = -player.global_transform.basis.z
	var direction := tangent * signf(steer.dot(tangent))
	if direction.is_zero_approx():
		direction = tangent

	player.accelerate(direction, player.config.wall_run_speed, player.config.ground_accel * 0.5, delta)
	player.velocity.y = maxf(player.velocity.y, -1.5)
