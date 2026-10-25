class_name PlayerWalkState
extends GroundedState

## Moving on the floor at [member GameConfig.walk_speed].

func physics_update(delta: float) -> void:
	if ground_common(delta, locomotion_speed(player.config.walk_speed)):
		return
	transition_to_locomotion()
