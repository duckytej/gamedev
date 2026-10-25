class_name PlayerFallState
extends PlayerState

## Descending in the air. Also the entry point for coyote-time jumps, optional
## air jumps, slam, grapples, air dashes and wall runs.

func physics_update(delta: float) -> void:
	player.apply_gravity(delta)
	player.apply_air_movement(delta, player.config.air_speed, player.config.air_accel)
	player.apply_surf_clip()

	if player.wants_slam():
		machine.transition_to(&"Slam")
		return
	if player.wants_jump():
		machine.transition_to(&"Jump")
		return
	if player.wants_air_jump():
		player.consume_air_jump()
		machine.transition_to(&"Jump")
		return
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
