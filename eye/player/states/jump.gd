class_name PlayerJumpState
extends PlayerState

## Ascending after a jump (normal, coyote, air-jump or wall jump).
##
## Applies reduced control and supports variable jump height: releasing the jump
## key while still rising cuts the upward velocity. A wall jump passes an
## explicit `vertical` impulse through `enter()` so it is not overwritten by the
## default jump velocity.

func enter(msg: Dictionary = {}) -> void:
	player.velocity.y = float(msg.get("vertical", player.config.jump_velocity))
	player.consume_jump()
	player.set_slide_pose(0.0)
	# Time the hold from the actual jump impulse, not from whenever the key was
	# first pressed (which may have been a buffered press or a wall jump).
	player.jump_hold_timer = 0.0


func physics_update(delta: float) -> void:
	player.apply_gravity(delta)
	player.apply_air_movement(delta, player.config.air_speed, player.config.air_accel)
	player.apply_surf_clip()

	# Holding jump while rising extends the jump. Releasing early still cuts it,
	# so tap = short hop and hold = full height.
	if player.input.jump_pressed \
			and player.velocity.y > 0.0 \
			and player.jump_hold_timer < player.config.jump_hold_max_time:
		player.velocity.y += player.config.jump_hold_accel * delta

	if player.input.jump_just_released and player.velocity.y > 0.0:
		player.velocity.y *= player.config.jump_cut_multiplier

	if try_start_grapple():
		return
	if player.input.dash_just_pressed and player.can_dash():
		machine.transition_to(&"Dash")
		return
	if player.can_wall_run():
		machine.transition_to(&"WallRun")
		return
	if player.is_on_floor():
		machine.transition_to(&"Land")
		return
	if player.velocity.y <= 0.0:
		machine.transition_to(&"Fall")
