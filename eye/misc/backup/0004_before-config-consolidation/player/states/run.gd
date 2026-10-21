class_name PlayerRunState
extends GroundedState

## Sprinting on the floor at [member PlayerConfig.sprint_speed].

func physics_update(delta: float) -> void:
	if ground_common(delta, player.sprint_speed):
		return
	transition_to_locomotion()
