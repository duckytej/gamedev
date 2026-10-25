class_name PlayerSlideState
extends GroundedState

## Momentum slide. There is no slide button: landing above the engagement speed
## (lower on a downhill ramp) or landing from a slam starts this state.
##
## Entry gives a large burst in the current travel direction. After that the
## slide bleeds speed faster than a sprint, gains a little on downhill ramps and
## can be jumped, grappled or dashed out of at any time. Holding jump after a slam
## is what makes the slam -> slide chain work.

var _time_left := 0.0


func enter(msg: Dictionary = {}) -> void:
	_time_left = player.config.slide_max_time
	player.set_slide_pose(1.0)
	var slammed := bool(msg.get("slam", false))

	var direction := Vector3(player.velocity.x, 0.0, player.velocity.z)
	if direction.length_squared() < 0.01:
		direction = player.accel_dir
	if direction.length_squared() < 0.01:
		direction = -player.camera.global_transform.basis.z
		direction.y = 0.0
	if direction.length_squared() > 0.01:
		direction = direction.normalized()

	# The burst is the point of the move: commit hard, cap it so a dash-slide
	# cannot become an uncapped launcher, then bleed down below sprint while the
	# slide lasts. A slam gets a guaranteed forward burst even when the player
	# dropped straight down, which is what makes the slam -> slide chain read.
	var speed := player.get_horizontal_speed() * player.config.slide_boost
	speed = maxf(speed, player.config.slide_ramp_min_speed)
	if slammed:
		speed = maxf(player.get_horizontal_speed(), player.config.slam_slide_speed)
		speed *= player.config.slam_slide_boost
	speed = minf(speed, player.config.slide_max_entry_speed)
	player.velocity.x = direction.x * speed
	player.velocity.z = direction.z * speed


func physics_update(delta: float) -> void:
	_time_left -= delta
	player.set_slide_pose(1.0)

	if player.wants_jump():
		machine.transition_to(&"Jump")
		return
	if try_start_grapple():
		return
	if player.input.dash_just_pressed and player.can_dash():
		machine.transition_to(&"Dash")
		return
	if not player.is_on_floor():
		machine.transition_to(&"Fall")
		return

	player.apply_friction(delta, player.config.slide_friction)

	# A downhill slide keeps feeding speed back in; a flat slide only slows.
	var normal := player.get_floor_normal()
	var downhill := Vector3.DOWN - normal * Vector3.DOWN.dot(normal)
	if downhill.length_squared() > 1e-6:
		downhill = downhill.normalized()
		var motion := Vector3(player.velocity.x, 0.0, player.velocity.z)
		if motion.dot(downhill) > 0.0:
			player.velocity += downhill * player.config.slide_slope_accel * delta

	# Low-grip steering: bend the trajectory without wiping momentum.
	var speed := player.get_horizontal_speed()
	if not player.accel_dir.is_zero_approx() and speed > 0.01:
		var target := player.accel_dir.normalized() * speed
		var steering := clampf(player.config.slide_steer * 8.0 * delta, 0.0, 1.0)
		player.velocity.x = lerpf(player.velocity.x, target.x, steering)
		player.velocity.z = lerpf(player.velocity.z, target.z, steering)

	if speed < player.config.slide_end_speed or _time_left <= 0.0:
		transition_to_locomotion()


func exit() -> void:
	player.slide_cooldown_timer = player.config.slide_cooldown
	player.set_slide_pose(0.0)
