class_name PlayerGrappleState
extends PlayerState

## Rope physics for [GrappleAbility].
##
## A one-sided distance constraint keeps the rope inextensible: motion away from
## the anchor is cancelled when taut, while tangential (swing) momentum is kept.
## The rope reels in over time and the player can steer with normal air control.
## Jumping or releasing detaches and preserves momentum, with an optional small
## upward boost tuned in [GameConfig].

var _ability: GrappleAbility


func enter(_msg: Dictionary = {}) -> void:
	_ability = player.get_grapple()
	if _ability == null or not _ability.attach():
		machine.transition_to(&"Fall")
		return
	player.set_crouch_wanted(0.0)


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

	# Do not auto-detach at the minimum rope length. Once reeled in, the
	# constraint simply goes slack and the player can hang, swing or jump off.
	# Only an over-stretched rope breaks.
	if distance > player.config.grapple_max_distance:
		_release()
		machine.transition_to(&"Fall")
		return

	_ability.reel(delta)

	if distance > 0.001:
		var direction := to_anchor / distance

		# Pull toward the anchor. This is the "reel-in" force; the constraint
		# below handles the taut-rope case.
		player.velocity += direction * player.config.grapple_pull_accel * delta

		# One-sided constraint: once taut, remove outward radial velocity and add
		# a spring correction for overshoot. Tangential velocity is untouched, so
		# the player swings around the anchor.
		var rope_length := _ability.get_rope_length()
		if distance > rope_length:
			var overshoot := distance - rope_length
			player.velocity += direction * overshoot \
				* player.config.grapple_constraint_stiffness * delta
			var radial := player.velocity.dot(direction)
			if radial < 0.0:
				player.velocity -= direction * radial

	player.apply_air_movement(delta, player.config.air_speed, player.config.air_accel)

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
