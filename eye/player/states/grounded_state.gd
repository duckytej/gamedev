class_name GroundedState
extends PlayerState

## Shared behaviour for states where the player is on the floor.
##
## Handles the transitions every grounded state can make (jump, dash, walking
## off a ledge) and applies ground movement. Subclasses pick their target speed
## and any extra rules, so Idle / Run stay tiny.
##
## Sliding is deliberately *not* a button. Landing fast or chaining a slam into
## the floor starts it from [PlayerLandState].

## Runs the shared grounded logic at `speed`. Returns true if this state changed
## to another state (the caller must stop processing this frame).
func ground_common(delta: float, speed: float) -> bool:
	if player.wants_jump():
		machine.transition_to(&"Jump")
		return true
	if try_start_grapple():
		return true
	if player.input.dash_just_pressed and player.can_dash():
		machine.transition_to(&"Dash")
		return true
	if not player.is_on_floor():
		machine.transition_to(&"Fall")
		return true
	player.apply_ground_movement(delta, speed)
	return false


## Hand off to whichever grounded state matches the current input. Normal
## movement always runs at sprint speed; there is no crouch/walk mode.
func transition_to_locomotion() -> void:
	if player.accel_dir.is_zero_approx():
		machine.transition_to(&"Idle")
	else:
		machine.transition_to(&"Run")
