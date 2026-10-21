extends CharacterBody3D
class_name EyePlayer

## First-person controller for the "eye" project.
##
## Architecture: this node is the *context* (state, config and shared motion
## math). Movement behaviour lives in independent state nodes under `States`,
## driven by `PlayerStateMachine`. Adding a movement behaviour means adding one
## script under `player/states/` and one child node — nothing here changes.
##
## The player owns the single `move_and_slide()` call per tick and the "feel"
## layer (head-bob, landing dip, strafe tilt, sprint FOV kick, footsteps).
##
## All tuning lives in [PlayerConfig] (`core/config/player_config.tres`).

## Tuning data. Assigned in `player.tscn`; falls back to class defaults.
@export var config: PlayerConfig

@onready var input: PlayerInput = $Input
@onready var state_machine: PlayerStateMachine = $States
@onready var neck: Node3D = $Neck
@onready var camera: Camera3D = $Neck/Camera3D
@onready var footstep_player: AudioStreamPlayer = $FootstepPlayer
@onready var step_ahead: RayCast3D = $StairProbe/StepAhead
@onready var floor_below: RayCast3D = $StairProbe/FloorBelow

# --- Runtime tuning (populated from `config`) --------------------------------
var walk_speed: float
var sprint_speed: float
var ground_accel: float
var air_accel: float
var air_speed: float
var friction: float
var gravity_scale: float
var max_fall_speed: float
var jump_velocity: float
var coyote_time: float
var jump_buffer_time: float
var jump_cut_multiplier: float
var land_time: float
var slide_boost: float
var slide_friction: float
var slide_min_speed: float
var slide_max_time: float
var wall_run_speed: float
var wall_run_gravity_scale: float
var wall_run_max_time: float
var wall_run_min_speed: float
var wall_jump_push: float
var dash_speed: float
var dash_time: float
var dash_cooldown: float
var mouse_sensitivity: float
var max_pitch_degrees: float
var base_fov: float
var sprint_fov_kick: float
var headbob_frequency: float
var headbob_amplitude: float
var strafe_tilt_degrees: float
var step_interval: float
var footstep_volume_db: float
var landing_dip_scale: float

# --- Runtime state shared with the movement states ---------------------------
## Horizontal wish direction for this tick (camera-yaw relative, length 0..1).
var accel_dir := Vector3.ZERO
var coyote_timer := 0.0
var jump_buffer_timer := 0.0
var dash_cooldown_timer := 0.0
var wall_run_timer := 0.0

# --- Internal ----------------------------------------------------------------
const FOOTSTEP_STREAMS := [
	preload("res://addons/assets/sounds/footstep_01.wav"),
	preload("res://addons/assets/sounds/footstep_02.wav"),
	preload("res://addons/assets/sounds/footstep_03.wav"),
]
## Maximum step height the stair-snapping logic can climb.
const MAX_STEP := 0.55
## How far ahead of the feet the step probe sits (roughly capsule radius + margin).
const STEP_PROBE_DISTANCE := 0.5

var _yaw := 0.0
var _pitch := 0.0
var _roll := 0.0
var _dip := 0.0
var _headbob_time := 0.0
var _fall_speed := 0.0
var _distance_since_step := 0.0
var _snapped_to_stairs_last_frame := false
var _last_floor_frame := -1
## Reused result object for the stair-clearance `test_move`, so stair stepping
## allocates nothing per tick.
var _clearance := KinematicCollision3D.new()


func _ready() -> void:
	(config if config != null else PlayerConfig.new()).apply_to(self)

	# FOV is authored in the config; the screen-space lens reads it back from the
	# camera every frame, so this is the single source for the whole pipeline.
	base_fov = maxf(base_fov, 1.0)
	camera.fov = base_fov

	_yaw = neck.rotation.y
	_pitch = camera.rotation.x
	state_machine.setup(self)

	if not Engine.is_editor_hint():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * mouse_sensitivity
		_pitch = clampf(
			_pitch - event.relative.y * mouse_sensitivity,
			deg_to_rad(-max_pitch_degrees),
			deg_to_rad(max_pitch_degrees)
		)
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		state_machine.handle_input(event)


func _physics_process(delta: float) -> void:
	input.update()
	_update_timers(delta)
	accel_dir = _compute_accel_dir()

	state_machine.physics_update(delta)

	# Stair handling: skip the normal slide when we step up onto a ledge.
	if not _snap_up_stairs(delta):
		move_and_slide()
		_snap_down_stairs()

	_post_move(delta)


# --- Timers ------------------------------------------------------------------

func _update_timers(delta: float) -> void:
	coyote_timer = maxf(coyote_timer - delta, 0.0)
	jump_buffer_timer = maxf(jump_buffer_timer - delta, 0.0)
	dash_cooldown_timer = maxf(dash_cooldown_timer - delta, 0.0)
	wall_run_timer = maxf(wall_run_timer - delta, 0.0)

	if is_on_floor():
		coyote_timer = coyote_time
		wall_run_timer = wall_run_max_time
	if input.jump_just_pressed:
		jump_buffer_timer = jump_buffer_time


func _compute_accel_dir() -> Vector3:
	var direction := Basis(Vector3.UP, _yaw) * Vector3(input.move.x, 0.0, input.move.y)
	if direction.length() > 1.0:
		direction = direction.normalized()
	return direction


func _post_move(delta: float) -> void:
	if is_on_floor():
		_last_floor_frame = Engine.get_physics_frames()
	if not is_on_floor() and velocity.y < 0.0:
		_fall_speed = maxf(_fall_speed, -velocity.y)

	# Computed once and shared by the feel + footstep layers.
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	_update_feel(delta, horizontal_speed)
	_update_footsteps(delta, horizontal_speed)


# --- Shared motion model (used by the states) --------------------------------

func apply_gravity(delta: float, scale: float = 1.0) -> void:
	velocity += get_gravity() * (gravity_scale * scale) * delta
	if velocity.y < -max_fall_speed:
		velocity.y = -max_fall_speed


## Quake-style acceleration: add speed toward `direction` up to `wish_speed`.
func accelerate(direction: Vector3, wish_speed: float, accel: float, delta: float) -> void:
	if direction.is_zero_approx():
		return
	var current := velocity.dot(direction)
	var add := wish_speed - current
	if add <= 0.0:
		return
	velocity += direction * minf(accel * wish_speed * delta, add)


func apply_ground_movement(
	delta: float, wish_speed: float, fric: float = -1.0, accel: float = -1.0
) -> void:
	_apply_friction(delta, friction if fric < 0.0 else fric)
	accelerate(accel_dir, wish_speed, ground_accel if accel < 0.0 else accel, delta)


func apply_air_movement(delta: float, wish_speed: float, accel: float) -> void:
	accelerate(accel_dir, wish_speed, accel, delta)


func _apply_friction(delta: float, fric: float) -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var speed := horizontal.length()
	if speed <= 0.0:
		return
	var control := maxf(speed, 1.0)
	var new_speed := maxf(speed - control * fric * delta, 0.0)
	var factor := new_speed / speed
	velocity.x = horizontal.x * factor
	velocity.z = horizontal.z * factor


# --- Queries used by the states ----------------------------------------------

func wants_jump() -> bool:
	return jump_buffer_timer > 0.0 and coyote_timer > 0.0


func consume_jump() -> void:
	jump_buffer_timer = 0.0
	coyote_timer = 0.0


func can_slide() -> bool:
	if not is_on_floor():
		return false
	return Vector3(velocity.x, 0.0, velocity.z).length() > slide_min_speed


func can_dash() -> bool:
	return dash_cooldown_timer <= 0.0


func can_wall_run() -> bool:
	if is_on_floor() or not is_on_wall() or wall_run_timer <= 0.0:
		return false
	if absf(get_wall_normal().y) > 0.2:
		return false
	return Vector3(velocity.x, 0.0, velocity.z).length() > wall_run_min_speed


func is_touching_wall() -> bool:
	return is_on_wall() and not is_on_floor()


func register_landing() -> void:
	if _fall_speed > 6.0:
		_play_footstep(0.78, 0.5)
	_dip = -clampf(_fall_speed * landing_dip_scale, 0.05, 0.22)
	_fall_speed = 0.0


# --- Stair stepping ----------------------------------------------------------
#
# Movement is snapped with raycasts rather than `test_move` on purpose: a capsule
# hitting the sharp corner of a step reports a diagonal normal, which looks like
# a slope and would be rejected as \"not floor\". A thin downward ray only ever
# hits the flat top of the step, so the normal is a clean up vector.

## Teleport up onto a step we are about to walk into. Returns true if we did.
func _snap_up_stairs(delta: float) -> bool:
	if not (is_on_floor() or _snapped_to_stairs_last_frame):
		return false

	var motion := Vector3(velocity.x, 0.0, velocity.z) * delta
	if motion.length_squared() < 1e-8:
		return false
	var forward := Vector3(motion.x, 0.0, motion.z).normalized()

	# Probe the ground just ahead of the feet, starting above the tallest step we
	# can climb, so the ray lands on the step top and not its front face.
	step_ahead.global_position = global_position \
		+ Vector3(0.0, MAX_STEP + 0.1, 0.0) + forward * STEP_PROBE_DISTANCE
	step_ahead.force_raycast_update()
	if not step_ahead.is_colliding():
		return false

	var point := step_ahead.get_collision_point()
	var step_height := point.y - global_position.y
	if step_height <= 0.01 or step_height > MAX_STEP:
		return false
	if step_ahead.get_collision_normal().angle_to(Vector3.UP) > floor_max_angle:
		return false

	# Refuse to step up if there is not enough head room.
	if test_move(global_transform, Vector3(0.0, step_height, 0.0), _clearance):
		return false

	global_position.y = point.y
	global_position += motion
	apply_floor_snap()
	_snapped_to_stairs_last_frame = true
	return true


## Follow the floor downward when walking off a step, so we do not float.
func _snap_down_stairs() -> void:
	var was_on_floor_last_frame := _last_floor_frame == Engine.get_physics_frames() - 1
	if is_on_floor() or velocity.y > 0.0 or not (was_on_floor_last_frame or _snapped_to_stairs_last_frame):
		_snapped_to_stairs_last_frame = false
		return

	floor_below.global_position = global_position + Vector3(0.0, 0.1, 0.0)
	floor_below.force_raycast_update()
	if not floor_below.is_colliding():
		_snapped_to_stairs_last_frame = false
		return

	var point := floor_below.get_collision_point()
	if global_position.y - point.y > MAX_STEP:
		_snapped_to_stairs_last_frame = false
		return
	if floor_below.get_collision_normal().angle_to(Vector3.UP) > floor_max_angle:
		_snapped_to_stairs_last_frame = false
		return

	global_position.y = point.y
	apply_floor_snap()
	_snapped_to_stairs_last_frame = true


# --- Feel --------------------------------------------------------------------

func _update_feel(delta: float, horizontal_speed: float) -> void:
	var moving := is_on_floor() and horizontal_speed > 1.0

	# Head-bob.
	if moving:
		_headbob_time += delta * (horizontal_speed / maxf(walk_speed, 0.001)) * headbob_frequency * TAU
		camera.position.y = sin(_headbob_time) * headbob_amplitude
		camera.position.x = cos(_headbob_time * 0.5) * headbob_amplitude * 0.6
	else:
		var settle := 1.0 - exp(-9.0 * delta)
		camera.position.y = lerpf(camera.position.y, 0.0, settle)
		camera.position.x = lerpf(camera.position.x, 0.0, settle)

	# Landing dip (eases back to neutral).
	_dip = lerpf(_dip, 0.0, 1.0 - exp(-7.0 * delta))
	camera.position.y += _dip

	# Strafe tilt.
	var target_roll := -input.move.x * deg_to_rad(strafe_tilt_degrees)
	_roll = lerpf(_roll, target_roll, 1.0 - exp(-8.0 * delta))

	neck.rotation = Vector3(0.0, _yaw, _roll)
	camera.rotation = Vector3(_pitch, 0.0, 0.0)

	# Sprint FOV kick (the lens picks this up live).
	var target_fov := base_fov
	if input.sprint_pressed and horizontal_speed > 2.0:
		target_fov += sprint_fov_kick
	camera.fov = lerpf(camera.fov, target_fov, 1.0 - exp(-6.0 * delta))


func _update_footsteps(delta: float, horizontal_speed: float) -> void:
	if is_on_floor() and horizontal_speed > 0.6:
		_distance_since_step += horizontal_speed * delta
		var interval := step_interval
		if input.sprint_pressed:
			interval *= 0.85
		if _distance_since_step >= interval:
			_distance_since_step = 0.0
			_play_footstep(1.0 + randf_range(-0.08, 0.08), 0.0)
	else:
		_distance_since_step = minf(_distance_since_step, step_interval * 0.5)


func _play_footstep(pitch: float, extra_db: float) -> void:
	if FOOTSTEP_STREAMS.is_empty():
		return
	footstep_player.stream = FOOTSTEP_STREAMS[randi() % FOOTSTEP_STREAMS.size()]
	footstep_player.pitch_scale = clampf(pitch, 0.5, 2.0)
	footstep_player.volume_db = footstep_volume_db + extra_db
	footstep_player.play()
