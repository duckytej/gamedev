class_name PlayerWallRunState
extends PlayerState

## Titanfall-style wall run.
##
## The state commits to a side using proactive [WallSense] probes, then:
## - projects movement onto the wall tangent (speed is preserved, not reset),
## - applies reduced gravity and a small vault impulse on entry,
## - sticks inward so the capsule never chatters off the surface,
## - tilts the camera toward the wall,
## - restores full tangential speed on a wall jump.
##
## It ends on timeout, when the wall disappears, or when the player lands. A
## per-wall cooldown prevents instantly re-grabbing the same surface.

var _wall_normal := Vector3.ZERO
var _wall_side := 0
var _tangent := Vector3.ZERO
var _time_left := 0.0


func enter(_msg: Dictionary = {}) -> void:
	var side := player.preferred_wall_side()
	var wall := player.get_wall(side) if side != 0 else {}
	if wall.is_empty():
		# The preferred side may be blocked; try the opposite side before giving
		# up, which makes glancing wall contact forgiving.
		side = -side if side != 0 else 1
		wall = player.get_wall(side)
	if wall.is_empty() and player.is_touching_wall():
		wall = player.get_wall(-side)
		side = -side
	if wall.is_empty():
		machine.transition_to(&"Fall")
		return

	_wall_side = side
	_wall_normal = wall["normal"]
	_time_left = player.config.wall_run_max_time

	# Remove velocity into the wall and add a small vault impulse.
	var into_wall := player.velocity.dot(_wall_normal)
	if into_wall < 0.0:
		player.velocity -= _wall_normal * into_wall
	player.velocity.y = maxf(player.velocity.y, -2.0) + player.config.wall_run_entry_boost

	_update_tangent()
	player.wall_roll_target = -float(_wall_side) * deg_to_rad(
		player.config.wall_run_tilt_degrees
	)


func physics_update(delta: float) -> void:
	_time_left -= delta

	if player.is_on_floor():
		machine.transition_to(&"Land")
		return

	var wall := player.get_wall(_wall_side)
	if wall.is_empty():
		machine.transition_to(&"Fall")
		return
	var normal: Vector3 = wall["normal"]
	if normal.dot(_wall_normal) < 0.65:
		machine.transition_to(&"Fall")
		return
	_wall_normal = normal
	_update_tangent()

	if player.jump_buffer_timer > 0.0:
		_wall_jump()
		return
	if try_start_grapple():
		return
	if player.input.dash_just_pressed and player.can_dash():
		machine.transition_to(&"Dash")
		return
	if _time_left <= 0.0 \
			or player.get_horizontal_speed() < player.config.wall_run_min_speed * 0.5:
		machine.transition_to(&"Fall")
		return

	player.apply_gravity(delta, player.config.wall_run_gravity_scale)

	# Maintain speed along the wall rather than resetting it to a fixed value.
	player.accelerate(
		_tangent, player.config.wall_run_speed, player.config.ground_accel * 0.65, delta
	)

	# Cancel motion away from the wall, then stick inward. The collision solver
	# removes the inward part, so the player hugs the surface without jitter.
	var outward := player.velocity.dot(_wall_normal)
	if outward > 0.0:
		player.velocity -= _wall_normal * outward
	player.velocity -= _wall_normal * player.config.wall_run_stick_force * delta

	player.wall_roll_target = -float(_wall_side) * deg_to_rad(
		player.config.wall_run_tilt_degrees
	)


func exit() -> void:
	player.wall_roll_target = 0.0
	player.wall_run_cooldown_timer = player.config.wall_run_cooldown


func _update_tangent() -> void:
	var tangent := Vector3.UP.cross(_wall_normal)
	if tangent.length_squared() < 1e-6:
		tangent = Vector3.FORWARD
	else:
		tangent = tangent.normalized()

	var velocity_along := player.velocity.dot(tangent)
	var input_along := player.accel_dir.dot(tangent)
	var sign := 1.0
	if absf(velocity_along) > 0.6:
		sign = signf(velocity_along)
	elif absf(input_along) > 0.1:
		sign = signf(input_along)
	_tangent = tangent * sign


func _wall_jump() -> void:
	var tangent_speed := maxf(player.velocity.dot(_tangent), 0.0) \
		* player.config.wall_jump_tangent_keep
	player.velocity = _wall_normal * player.config.wall_jump_push \
		+ _tangent * tangent_speed
	player.air_jumps_left = player.config.air_jumps
	machine.transition_to(&"Jump", {"vertical": player.config.wall_jump_up})
