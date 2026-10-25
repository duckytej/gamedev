class_name PlayerGrappleState
extends PlayerState

## Rope physics for [GrappleAbility].
##
## This is a winch, not a hard constraint: a slow reel and a spring add velocity
## toward the anchor, but no radial velocity is cancelled. Whatever direction the
## player was already moving is preserved, and stronger-than-normal air steering
## lets them rotate around the anchor like a swing. Jumping or releasing detaches
## and keeps the resulting momentum, with an optional small upward boost.

var _ability: GrappleAbility


func enter(_msg: Dictionary = {}) -> void:
	_ability = player.get_grapple()
	if _ability == null or not _ability.attach():
		machine.transition_to(&"Fall")
		return
	player.set_slide_pose(0.0)


func physics_update(delta: float) -> void:
	if _ability == null or not is_instance_valid(_ability) or not _ability.is_attached():
		machine.transition_to(&"Fall")
		return

	if not player.input.grapple_pressed:
		_release()
		machine.transition_to(&"Fall")
		return

	if player.jump_buffer_timer > 0.0:
		player.consume_jump()
		_release(false)
		player.velocity.y = maxf(player.velocity.y, player.config.jump_velocity)
		machine.transition_to(&"Jump", {"vertical": player.velocity.y})
		return

	player.apply_gravity(delta, player.config.grapple_gravity_scale)

	var origin := _ability.get_origin()
	var to_anchor := _ability.get_anchor() - origin
	var distance := to_anchor.length()

	# Do not auto-detach at the minimum rope length. Once reeled in, the rope
	# simply goes slack and the player can hang, swing or jump off. Only an
	# over-stretched rope breaks.
	if distance > player.config.grapple_max_distance:
		_release()
		machine.transition_to(&"Fall")
		return

	_ability.reel(delta)

	if distance > 0.001:
		var direction := to_anchor / distance

		# Pull toward the anchor without cancelling the player's own motion. The
		# constant pull is the slow winch; the spring only adds force when the
		# rope is over-stretched. Tangential momentum is deliberately untouched,
		# so the player keeps their direction and can swing/rotate around it.
		var overshoot := maxf(distance - _ability.get_rope_length(), 0.0)
		var pull := player.config.grapple_pull_accel \
			+ overshoot * player.config.grapple_constraint_stiffness
		pull = minf(pull, player.config.grapple_max_pull_accel)
		player.velocity += direction * pull * delta

	# Strong air control while attached lets the player steer the swing and
	# rotate around the anchor instead of being passively dragged in.
	player.apply_air_movement(
		delta, player.config.grapple_air_speed, player.config.grapple_air_accel
	)

	var speed := player.velocity.length()
	if speed > player.config.grapple_max_speed:
		player.velocity = player.velocity / speed * player.config.grapple_max_speed


func exit() -> void:
	if _ability != null and is_instance_valid(_ability) and _ability.is_attached():
		_ability.detach()


func _release(boost: bool = true) -> void:
	if boost:
		player.velocity += Vector3.UP * player.config.grapple_release_boost
	if _ability != null and is_instance_valid(_ability):
		_ability.detach()
