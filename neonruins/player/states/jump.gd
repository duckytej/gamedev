extends State


func enter() -> void:
	player.velocity.y = player.jump_velocity
	player.gravity_scale = 1.0
	player.coyote_timer = 0.0
	player.jump_buffer_timer = 0.0
	player._variable_jump_cut_applied = false


func physics_process(delta: float) -> void:
	player.apply_gravity(delta)
	var wish_dir := player.get_input_direction()
	if wish_dir.length() > 0.1:
		player.apply_air_acceleration(wish_dir, player.run_speed, delta)

	player.clamp_horizontal_speed(player.max_air_speed)

	if player.velocity.y < 0.0:
		player.transition_to("InAir")
		return

	if player.is_on_floor():
		player.transition_to("Walk")
		return

	if Input.is_action_just_pressed("grapple") and player.grapple_raycast.is_colliding() \
			and player.grapple_cooldown_timer <= 0.0:
		player.transition_to("Grapple")
		return
