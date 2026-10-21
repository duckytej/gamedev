class_name PlayerWalkState
extends GroundedState

## Moving on the floor at [member PlayerConfig.walk_speed].

func physics_update(delta: float) -> void:
	if ground_common(delta, player.walk_speed):
		return
	transition_to_locomotion()
