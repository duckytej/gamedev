extends State


func enter() -> void:
	player.set_crouched(true)
	player.gravity_scale = 1.0
	player.reset_air_jumps()


func physics_process(delta: float) -> void:
	player.apply_gravity(delta)
	var wish_dir := player.get_input_direction()

	if wish_dir.length() > 0.1:
		# Crouch-walk
		var target := wish_dir * player.crouch_speed
		player.velocity.x = move_toward(player.velocity.x, target.x, player.ground_accel * delta)
		player.velocity.z = move_toward(player.velocity.z, target.z, player.ground_accel * delta)
	else:
		player.apply_friction(player.ground_friction * 2.0, delta)

	if not player.is_on_floor():
		player.transition_to("InAir")
		return

	if player.try_buffered_ground_jump():
		player.transition_to("Jump")
		return

	# Stand up when the key is released (player.set_crouched guards headroom)
	if not Input.is_action_pressed("crouch"):
		player.set_crouched(false)
		if player.is_standing():
			player.transition_to("Idle")
		return

	if Input.is_action_just_pressed("melee_attack"):
		player.transition_to("MeleeAttack")
		return

	if Input.is_action_pressed("ranged_attack"):
		player.transition_to("RangedAttack")
		return

	if player.try_dash():
		player.transition_to("Dash")
		return
