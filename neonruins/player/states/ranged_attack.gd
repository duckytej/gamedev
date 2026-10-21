extends State

const AIM_MOVE_MULT: float = 0.7


func enter() -> void:
	player.gravity_scale = 1.0


func physics_process(delta: float) -> void:
	player.apply_gravity(delta)
	var rs := player.ranged_system
	if rs == null or rs.weapon == null:
		_finish()
		return

	if Input.is_action_just_pressed("reload"):
		rs.start_reload()

	if Input.is_action_pressed("ranged_attack"):
		rs.try_fire()

	# Exit when trigger released on semi-auto weapons, or ammo dry while idle
	var is_automatic := rs.weapon.fire_rate < 0.2
	if not Input.is_action_pressed("ranged_attack") and not is_automatic:
		_finish()
		return

	if Input.is_action_just_pressed("melee_attack"):
		_finish()
		player.transition_to("MeleeAttack")
		return

	# Movement while aiming is slower
	if player.is_on_floor():
		var wish_dir := player.get_input_direction()
		if wish_dir.length() > 0.1:
			var speed := player.walk_speed * AIM_MOVE_MULT
			player.velocity.x = lerpf(player.velocity.x, wish_dir.x * speed, 10.0 * delta)
			player.velocity.z = lerpf(player.velocity.z, wish_dir.z * speed, 10.0 * delta)
		else:
			player.apply_friction(player.ground_friction, delta)
	else:
		player.clamp_horizontal_speed(player.max_air_speed)

	# Jumping / dashing out of aim
	if player.try_buffered_ground_jump():
		_finish()
		player.transition_to("Jump")
		return

	if player.try_dash():
		_finish()
		player.transition_to("Dash")
		return


func _finish() -> void:
	if player.is_on_floor():
		player.transition_to("Walk")
	else:
		player.transition_to("InAir")
