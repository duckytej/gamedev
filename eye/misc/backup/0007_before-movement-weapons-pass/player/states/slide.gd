class_name PlayerSlideState
extends GroundedState

## Titanfall-style crouch-slide: preserves momentum with low friction, keeps a
## low capsule/camera, and can be jumped out of at any point. Holding crouch
## after the slide ends transitions to crouched walking rather than re-sliding.

var _time_left := 0.0


func enter(_msg: Dictionary = {}) -> void:
	_time_left = player.config.slide_max_time
	player.set_crouch_wanted(1.0)

	var direction := Vector3(player.velocity.x, 0.0, player.velocity.z)
	if direction.length_squared() < 0.01:
		direction = player.accel_dir
	if direction.length_squared() > 0.01:
		var speed := maxf(
			player.get_horizontal_speed() * player.config.slide_boost,
			player.config.slide_min_speed
		)
		direction = direction.normalized()
		player.velocity.x = direction.x * speed
		player.velocity.z = direction.z * speed


func physics_update(delta: float) -> void:
	_time_left -= delta
	player.set_crouch_wanted(1.0)

	if player.wants_jump():
		machine.transition_to(&"Jump")
		return
	if try_start_grapple():
		return
	if player.input.dash_just_pressed and player.can_dash():
		machine.transition_to(&"Dash")
		return
	if not player.is_on_floor():
		machine.transition_to(&"Fall")
		return

	player.apply_friction(delta, player.config.slide_friction)

	# Low-grip steering: bend the trajectory without wiping momentum.
	var speed := player.get_horizontal_speed()
	if not player.accel_dir.is_zero_approx() and speed > 0.01:
		var target := player.accel_dir.normalized() * speed
		var steering := clampf(player.config.slide_steer * 8.0 * delta, 0.0, 1.0)
		player.velocity.x = lerpf(player.velocity.x, target.x, steering)
		player.velocity.z = lerpf(player.velocity.z, target.z, steering)

	if not player.input.crouch_pressed \
			or speed < player.config.slide_min_speed \
			or _time_left <= 0.0:
		transition_to_locomotion()


func exit() -> void:
	player.slide_cooldown_timer = player.config.slide_cooldown
