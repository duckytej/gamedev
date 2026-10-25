class_name PlayerRunState
extends GroundedState

## Sprinting on the floor at [member GameConfig.sprint_speed].

func physics_update(delta: float) -> void:
	if ground_common(delta, locomotion_speed(player.config.sprint_speed)):
		return
	transition_to_locomotion()
