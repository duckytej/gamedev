extends State

var _timer: float = 0.0


func enter() -> void:
	_timer = player.slide_duration

	var direction := player.velocity
	direction.y = 0.0
	if direction.length() < 0.1:
		direction = player.get_input_direction()
	direction = direction.normalized()

	# Momentum boost on entry (slide-hopping preserves speed)
	var boost_speed := maxf(Vector2(player.velocity.x, player.velocity.z).length() * player.slide_boost,
			player.slide_min_entry_speed)
	player.velocity.x = direction.x * boost_speed
	player.velocity.z = direction.z * boost_speed

	player.set_crouched(true)
	player.gravity_scale = 1.0

	SignalBus.player_slide_started.emit(player)


func physics_process(delta: float) -> void:
	player.apply_gravity(delta)
	_timer -= delta

	# Very low friction preserves momentum
	player.apply_friction(player.slide_friction, delta)

	# Slight steering
	var input_dir := player.get_input_direction()
	if input_dir.length() > 0.1:
		var steer := 0.8 * delta
		var speed := Vector2(player.velocity.x, player.velocity.z).length()
		player.velocity.x = lerpf(player.velocity.x, input_dir.x * speed, steer)
		player.velocity.z = lerpf(player.velocity.z, input_dir.z * speed, steer)

	# Exit conditions
	var horiz_speed := Vector2(player.velocity.x, player.velocity.z).length()
	if _timer <= 0.0 or horiz_speed < player.slide_min_entry_speed * 0.5 \
			or (not player.is_on_floor() and player.slide_grace_timer <= 0.0):
		if Input.is_action_pressed("crouch"):
			player.transition_to("Crouch")
		else:
			player.transition_to("Walk")
		return

	if Input.is_action_just_pressed("jump"):
		player.transition_to("Jump")
		return

	if player.try_dash():
		player.transition_to("Dash")
		return


func exit() -> void:
	pass
