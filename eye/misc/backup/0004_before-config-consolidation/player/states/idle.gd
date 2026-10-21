class_name PlayerIdleState
extends GroundedState

## Standing still on the floor. Decays any residual speed via friction.

func physics_update(delta: float) -> void:
	if ground_common(delta, 0.0):
		return
	transition_to_locomotion()
