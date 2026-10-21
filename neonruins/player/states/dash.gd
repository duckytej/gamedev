extends State

var _timer: float = 0.0
var _direction: Vector3 = Vector3.ZERO


func enter() -> void:
	# try_dash() already gated on the cooldown and stamped it; every caller
	# transitions here only after that succeeds.
	_timer = player.dash_duration

	var input_dir := player.get_input_direction()
	_direction = input_dir if input_dir.length() > 0.1 else -player.camera_pivot.basis.z.normalized()
	_direction.y = 0.0
	_direction = _direction.normalized()

	# Dash velocity, preserving any upward motion for dash-jumps
	player.velocity.x = _direction.x * player.dash_speed
	player.velocity.z = _direction.z * player.dash_speed

	player.gravity_scale = 0.0

	SignalBus.player_dash_started.emit(player)


func physics_process(delta: float) -> void:
	_timer -= delta

	if _timer <= 0.0:
		_end_dash()
		return

	# Maintain dash velocity (no drag during the burst)
	player.velocity.x = _direction.x * player.dash_speed
	player.velocity.z = _direction.z * player.dash_speed

	# Cancel into jump (dash-jump keeps momentum)
	if Input.is_action_just_pressed("jump"):
		_end_dash()
		player.velocity.y = player.jump_velocity
		return

	# Cancel into grapple
	if Input.is_action_just_pressed("grapple") and player.grapple_raycast.is_colliding() \
			and player.grapple_cooldown_timer <= 0.0:
		_end_dash()
		player.transition_to("Grapple")
		return


func _end_dash() -> void:
	player.gravity_scale = 1.0
	# Momentum preservation multiplier on exit
	player.clamp_horizontal_speed(player.max_air_speed * player.dash_end_speed_mult)
	if player.is_on_floor():
		player.transition_to("Walk")
	else:
		player.transition_to("InAir")


func exit() -> void:
	player.gravity_scale = 1.0
