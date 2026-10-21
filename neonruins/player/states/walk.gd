extends State


func enter() -> void:
	player.set_crouched(false)
	player.gravity_scale = 1.0
	player.reset_air_jumps()


func physics_process(delta: float) -> void:
	player.apply_gravity(delta)
	var wish_dir := player.get_input_direction()

	if wish_dir.length() < 0.1:
		player.transition_to("Idle")
		return

	# Source order: friction first, then accelerate
	player.apply_friction(player.ground_friction, delta)

	var is_sprinting := Input.is_action_pressed("run")
	var wish_speed := player.run_speed if is_sprinting else player.walk_speed
	wish_speed = minf(wish_speed, player.max_ground_speed)

	player.accelerate(wish_dir, wish_speed, player.ground_accel, delta)
	player.clamp_horizontal_speed(player.max_ground_speed)

	if not player.is_on_floor():
		player.transition_to("InAir")
		return

	if player.try_buffered_ground_jump():
		player.transition_to("Jump")
		return

	if Input.is_action_pressed("crouch"):
		var horiz_speed := Vector2(player.velocity.x, player.velocity.z).length()
		if horiz_speed > player.slide_min_entry_speed:
			player.transition_to("Slide")
			return
		player.transition_to("Crouch")
		return

	if player.try_dash():
		player.transition_to("Dash")
		return

	if Input.is_action_just_pressed("melee_attack"):
		player.transition_to("MeleeAttack")
		return

	if Input.is_action_pressed("ranged_attack"):
		player.transition_to("RangedAttack")
		return

	if Input.is_action_just_pressed("grapple") and player.grapple_raycast.is_colliding() \
			and player.grapple_cooldown_timer <= 0.0:
		player.transition_to("Grapple")
		return
