extends State


func enter() -> void:
	player.set_crouched(false)
	player.gravity_scale = 1.0
	player.reset_air_jumps()


func physics_process(delta: float) -> void:
	player.apply_gravity(delta)
	var wish_dir := player.get_input_direction()

	# High friction when stationary
	player.apply_friction(player.ground_friction * 3.0, delta)

	if wish_dir.length() > 0.1:
		player.transition_to("Walk")
		return

	if not player.is_on_floor():
		player.transition_to("InAir")
		return

	if player.try_buffered_ground_jump():
		player.transition_to("Jump")
		return

	if Input.is_action_pressed("crouch"):
		player.transition_to("Crouch")
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


func handle_input(_event: InputEvent) -> void:
	pass
