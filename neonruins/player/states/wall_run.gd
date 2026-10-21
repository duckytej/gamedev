extends State

var _wall_normal: Vector3 = Vector3.ZERO
var _timer: float = 0.0


func enter() -> void:
	_wall_normal = player.get_wall_normal()
	if _wall_normal.length() < 0.1:
		player.transition_to("InAir")
		return

	_timer = 0.0
	player.wall_run_cooldown_timer = player.wall_run_cooldown

	# Which side is the wall on, relative to camera facing?
	var right := player.camera_pivot.basis.x
	var wall_side := signf(_wall_normal.dot(right))
	player.set_meta("wall_side", wall_side)

	# Clamp entry velocity so the run starts controlled
	player.velocity.y = clampf(player.velocity.y, -6.0, 8.0)
	# Kill velocity into the wall so we hug it
	player.velocity -= _wall_normal * minf(player.velocity.dot(-_wall_normal), 0.0)
	player.gravity_scale = player.wall_run_gravity_mult

	SignalBus.player_wall_run.emit(player, _wall_normal)


func physics_process(delta: float) -> void:
	_timer += delta

	var current_wall := player.get_wall_normal()
	if current_wall.length() < 0.1 or player.is_on_floor() or current_wall.dot(_wall_normal) < 0.7:
		_detach()
		return

	player.gravity_scale = player.wall_run_gravity_mult
	player.apply_friction(player.wall_friction, delta)

	# Reduced gravity + slight upward assist keeps the run afloat
	player.velocity.y += player.wall_run_force * delta * (1.0 - player.wall_run_gravity_mult)

	# Direction along the wall, chosen by which side we attached to
	var along_wall := _wall_normal.cross(Vector3.UP).normalized()
	if player.get_meta("wall_side", 1.0) > 0.0:
		along_wall = -along_wall

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var wish_dir := (player.camera_pivot.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	var alignment := wish_dir.dot(along_wall)

	# Reward looking/pressing along the wall with lateral boost
	if alignment > 0.15:
		player.velocity += along_wall * player.wall_run_lateral_boost * delta

	# Gentle stick force into the wall for reliable surface contact
	player.velocity -= current_wall * 2.0

	player.clamp_horizontal_speed(player.max_ground_speed)

	# Wall jump: away from wall + upward
	if Input.is_action_just_pressed("jump"):
		player.velocity += current_wall * player.wall_jump_force
		player.velocity.y = player.wall_jump_up_force
		_detach()
		return

	if Input.is_action_just_pressed("grapple") and player.grapple_raycast.is_colliding() \
			and player.grapple_cooldown_timer <= 0.0:
		_detach()
		player.transition_to("Grapple")
		return

	if player.try_dash():
		_detach()
		player.transition_to("Dash")
		return

	if _timer > player.wall_run_max_time \
			or Vector2(player.velocity.x, player.velocity.z).length() < player.wall_run_min_speed:
		_detach()


func _detach() -> void:
	player.transition_to("InAir")


func exit() -> void:
	player.gravity_scale = 1.0
	player.remove_meta("wall_side")
