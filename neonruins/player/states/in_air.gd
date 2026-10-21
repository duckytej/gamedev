extends State


func enter() -> void:
	player.gravity_scale = 1.0


func physics_process(delta: float) -> void:
	player.apply_gravity(delta)
	var wish_dir := player.get_input_direction()
	if wish_dir.length() > 0.1:
		player.apply_air_acceleration(wish_dir, player.run_speed, delta)

	# Very light air drag
	if player.air_friction > 0.0:
		player.apply_friction(player.air_friction, delta)

	player.clamp_horizontal_speed(player.max_air_speed)

	# Landing
	if player.is_on_floor():
		SignalBus.player_landed.emit(player, -player.velocity.y)
		if Input.is_action_pressed("crouch"):
			var horiz_speed := Vector2(player.velocity.x, player.velocity.z).length()
			if horiz_speed > player.slide_min_entry_speed:
				player.transition_to("Slide")
				return
			player.transition_to("Crouch")
			return
		player.transition_to("Walk")
		return

	# Wall run attach (requires lateral speed against a wall)
	if player.is_on_wall_only() and player.wall_run_cooldown_timer <= 0.0 \
			and absf(player.last_wall_normal.dot(Vector3.UP)) < 0.5:
		var horiz_speed := Vector2(player.velocity.x, player.velocity.z).length()
		if horiz_speed >= player.wall_run_min_speed * 0.6:
			player.transition_to("WallRun")
			return

	# Double jump / coyote jump
	if Input.is_action_just_pressed("jump"):
		if player.coyote_timer > 0.0:
			player.jump_buffer_timer = 0.0  # consume so Jump doesn't double-fire
			player.transition_to("Jump")
			return
		if player.air_jumps_left > 0:
			player.air_jumps_left -= 1
			player.transition_to("Jump")
			return

	if Input.is_action_just_pressed("grapple") and player.grapple_raycast.is_colliding() \
			and player.grapple_cooldown_timer <= 0.0:
		player.transition_to("Grapple")
		return

	if player.try_dash():
		player.transition_to("Dash")
		return
