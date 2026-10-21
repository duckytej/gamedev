extends CharacterBody3D
class_name EyePlayer

## First-person player controller for the "eye" project.
##
## All tuning lives in a [PlayerConfig] resource (`config/player_config.tres`):
## movement, camera and "feel". This script only wires input -> physics -> feel
## so there is exactly one place to edit when dialing in the controller.
##
## Mouse look + WASD + sprint + jump with coyote time and a jump buffer, rounded
## out with head-bob, a sprint FOV kick, a landing dip, a subtle strafe tilt and
## distance-based footstep audio so it reads well through the wide lens.

## Tuning data. Assigned in `player.tscn`. If left empty, the resource's class
## defaults are used so the scene still runs.
@export var config: PlayerConfig

# Populated from `config` in _ready(). Edit the resource, not these fields.
var walk_speed: float
var sprint_speed: float
var jump_velocity: float
var ground_accel: float
var air_accel: float
var ground_friction: float
var gravity_scale: float
var coyote_time: float
var jump_buffer_time: float
var mouse_sensitivity: float
var max_pitch_degrees: float
var base_fov: float
var sprint_fov_kick: float
var headbob_frequency: float
var headbob_amplitude: float
var strafe_tilt_degrees: float
var step_interval: float
var footstep_volume_db: float

const FOOTSTEP_STREAMS := [
	preload("res://assets/sounds/footstep_01.wav"),
	preload("res://assets/sounds/footstep_02.wav"),
	preload("res://assets/sounds/footstep_03.wav"),
]

@onready var neck: Node3D = $Neck
@onready var camera: Camera3D = $Neck/Camera3D
@onready var footstep_player: AudioStreamPlayer = $FootstepPlayer

var _yaw := 0.0
var _pitch := 0.0
var _roll := 0.0
var _dip := 0.0
var _headbob_time := 0.0
var _coyote := 0.0
var _jump_buffer := 0.0
var _fall_speed := 0.0
var _distance_since_step := 0.0


func _ready() -> void:
	(config if config != null else PlayerConfig.new()).apply_to(self)

	# FOV is authored in the config; the screen-space lens reads it back from the
	# camera every frame, so this is the single source for the whole pipeline.
	base_fov = maxf(base_fov, 1.0)
	camera.fov = base_fov

	_yaw = neck.rotation.y
	_pitch = camera.rotation.x
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


func _physics_process(delta: float) -> void:
	var was_on_floor := is_on_floor()

	# --- Timers -----------------------------------------------------------
	_coyote = maxf(_coyote - delta, 0.0)
	_jump_buffer = maxf(_jump_buffer - delta, 0.0)
	if was_on_floor:
		_coyote = coyote_time
	if Input.is_action_just_pressed("jump"):
		_jump_buffer = jump_buffer_time

	# --- Gravity ----------------------------------------------------------
	if not was_on_floor:
		velocity += get_gravity() * gravity_scale * delta
		_fall_speed = maxf(_fall_speed, -velocity.y)

	# --- Jump -------------------------------------------------------------
	if _jump_buffer > 0.0 and _coyote > 0.0:
		velocity.y = jump_velocity
		_jump_buffer = 0.0
		_coyote = 0.0
		_fall_speed = 0.0

	# --- Horizontal movement ---------------------------------------------
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	# Move relative to yaw only, so head-bob and strafe tilt don't affect steering.
	var wish_dir := Basis(Vector3.UP, _yaw) * Vector3(input_dir.x, 0.0, input_dir.y)
	if wish_dir.length() > 0.0:
		wish_dir = wish_dir.normalized()

	# Read once per frame; reused by movement, feel and footsteps.
	var sprinting := Input.is_action_pressed("sprint")
	var speed := sprint_speed if sprinting else walk_speed
	var target := wish_dir * speed
	var rate := ground_accel if was_on_floor else air_accel
	if wish_dir == Vector3.ZERO and was_on_floor:
		rate = ground_friction
	var t := 1.0 - exp(-rate * delta)
	velocity.x = lerpf(velocity.x, target.x, t)
	velocity.z = lerpf(velocity.z, target.z, t)

	move_and_slide()

	var just_landed := is_on_floor() and not was_on_floor
	if just_landed:
		_dip = -clampf(_fall_speed * 0.016, 0.05, 0.22)
		if _fall_speed > 6.0:
			_play_footstep(0.78, 0.5)
		_fall_speed = 0.0

	# Compute the horizontal speed once and share it (avoids a sqrt per consumer).
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	_update_feel(delta, horizontal_speed, speed, input_dir, sprinting)
	_update_footsteps(delta, horizontal_speed, sprinting)


func _update_feel(
	delta: float, horizontal_speed: float, speed: float, input_dir: Vector2, sprinting: bool
) -> void:
	var moving := is_on_floor() and horizontal_speed > 1.0

	# Head-bob.
	if moving:
		_headbob_time += delta * (horizontal_speed / speed) * headbob_frequency * TAU
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
	var target_roll := -input_dir.x * deg_to_rad(strafe_tilt_degrees)
	_roll = lerpf(_roll, target_roll, 1.0 - exp(-8.0 * delta))

	neck.rotation = Vector3(0.0, _yaw, _roll)
	camera.rotation = Vector3(_pitch, 0.0, 0.0)

	# Sprint FOV kick (the lens picks this up live).
	var target_fov := base_fov
	if sprinting and horizontal_speed > 2.0:
		target_fov += sprint_fov_kick
	camera.fov = lerpf(camera.fov, target_fov, 1.0 - exp(-6.0 * delta))


func _update_footsteps(delta: float, horizontal_speed: float, sprinting: bool) -> void:
	if is_on_floor() and horizontal_speed > 0.6:
		_distance_since_step += horizontal_speed * delta
		var interval := step_interval
		if sprinting:
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
