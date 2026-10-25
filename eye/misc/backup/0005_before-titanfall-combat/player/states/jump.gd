class_name PlayerJumpState
extends PlayerState

## Ascending after a jump (or a coyote / wall jump).
##
## Applies reduced control and supports variable jump height: releasing the jump
## key while still rising cuts the upward velocity.

func enter(_msg: Dictionary = {}) -> void:
	player.velocity.y = player.config.jump_velocity
	player.consume_jump()


func physics_update(delta: float) -> void:
	player.apply_gravity(delta)
	player.apply_air_movement(delta, player.config.air_speed, player.config.air_accel)

	if player.input.jump_just_released and player.velocity.y > 0.0:
		player.velocity.y *= player.config.jump_cut_multiplier

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
