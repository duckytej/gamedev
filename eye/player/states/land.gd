class_name PlayerLandState
extends PlayerState

## Short recovery after touching down: applies the landing dip and a brief
## window before full control returns.
##
## Landing is also the only non-slam way to start a slide: if the player arrives
## above the engagement speed (which is lower on a downhill ramp), the recovery
## is skipped and the slide takes over. A slam always chains into a slide.

var _time_left := 0.0
var _slammed := false


func enter(msg: Dictionary = {}) -> void:
	player.register_landing()
	_slammed = bool(msg.get("slam", false))
	_time_left = player.config.land_time


func physics_update(delta: float) -> void:
	if _slammed and player.config.slam_to_slide:
		machine.transition_to(&"Slide", {"slam": true})
		return
	if player.can_slide():
		machine.transition_to(&"Slide")
		return

	_time_left -= delta

	if player.wants_jump():
		machine.transition_to(&"Jump")
		return
	if player.input.dash_just_pressed and player.can_dash():
		machine.transition_to(&"Dash")
		return

	player.apply_ground_movement(delta, player.config.sprint_speed)

	if _time_left <= 0.0:
		if player.accel_dir.is_zero_approx():
			machine.transition_to(&"Idle")
		else:
			machine.transition_to(&"Run")
