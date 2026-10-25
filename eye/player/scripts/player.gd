extends CharacterBody3D
class_name EyePlayer

## First-person controller for the "eye" project.
##
## Architecture: this node is the *context* (state, config and shared motion
## math). Movement behaviour lives in independent state nodes under `States`,
## driven by `PlayerStateMachine`. Optional systems (grapple, wall sensing,
## weapons) are [PlayerAbility] nodes under `Abilities`; add or remove one and
## the rest of the player keeps working.
##
## The player owns the single `move_and_slide()` call per tick and the "feel"
## layer (slide pose, head-bob, landing dip, strafe/wall tilt, speed/scope FOV,
## recoil, footsteps). All tuning lives in [GameConfig] at
## `core/config/game_config.tres`.

@export var config: GameConfig

## Where `reset` returns the player. Defaults to the spawn transform.
@export var respawn_on_reset: bool = true

@onready var input: PlayerInput = $Input
@onready var state_machine: PlayerStateMachine = $States
@onready var abilities: PlayerAbilityHost = $Abilities
@onready var vitals: PlayerVitals = $Health
@onready var neck: Node3D = $Neck
@onready var camera: Camera3D = $Neck/Camera3D
@onready var collider: CollisionShape3D = $CollisionShape3D
@onready var footstep_player: AudioStreamPlayer = $FootstepPlayer
@onready var step_ahead: RayCast3D = $StairProbe/StepAhead
@onready var floor_below: RayCast3D = $StairProbe/FloorBelow

# --- Runtime state shared with the movement states ---------------------------
## Horizontal wish direction for this tick (camera-yaw relative, length 0..1).
var accel_dir := Vector3.ZERO
var coyote_timer := 0.0
var jump_buffer_timer := 0.0
var air_jumps_left := 0
var dash_cooldown_timer := 0.0
var slide_cooldown_timer := 0.0
var wall_run_cooldown_timer := 0.0

## Continuous jump-hold time and whether the current hold started in mid-air.
## Ground jumps use the hold for extra height; an air-started hold is what arms
## the slam, so holding a ground jump never turns into a slam at the apex.
var jump_hold_timer := 0.0
var jump_started_in_air := false

## Set by the weapon controller while the right mouse button is held. The player
## owns the blend so every consumer (FOV, lens, head-bob, sensitivity) agrees.
var scoped := false
var scope_blend := 0.0

## Slide body target in 0..1. States set this; the player resizes the body
## shape after the state machine has run, so one state cannot fight another over the
## shape. There is no manual crouch: only slides use the compressed pose.
var slide_pose_target := 0.0
var slide_pose_amount := 0.0

## Wall-run camera roll target (radians). Set by [PlayerWallRunState].
var wall_roll_target := 0.0

# --- Internal ----------------------------------------------------------------
const FOOTSTEP_STREAMS := [
	preload("res://addons/assets/sounds/footstep_01.wav"),
	preload("res://addons/assets/sounds/footstep_02.wav"),
	preload("res://addons/assets/sounds/footstep_03.wav"),
]
const MAX_STEP := 0.55
const STEP_PROBE_DISTANCE := 0.65

var _yaw := 0.0
var _pitch := 0.0
var _roll := 0.0
var _wall_roll := 0.0
var _dip := 0.0
var _headbob_time := 0.0
var _fall_speed := 0.0
var _distance_since_step := 0.0
var _snapped_to_stairs_last_frame := false
var _last_floor_frame := -1

var _capsule: CapsuleShape3D
var _cylinder: CylinderShape3D
var _stand_height := 1.8
var _stand_eye_height := 1.6
var _spawn_transform := Transform3D.IDENTITY

var _recoil_pitch := 0.0
var _recoil_yaw := 0.0

var _dead := false
var _respawn_timer := 0.0

## Reused result object for the stair-clearance / stand-up `test_move`.
var _clearance := KinematicCollision3D.new()


func _ready() -> void:
	if config == null:
		config = GameConfig.new()
		push_warning("EyePlayer: no GameConfig assigned; using defaults.")

	vitals.setup(config)
	vitals.died.connect(_on_died)

	camera.fov = clampf(config.base_fov, 1.0, 179.0)
	_yaw = neck.rotation.y
	_pitch = camera.rotation.x
	_spawn_transform = global_transform

	_capsule = collider.shape as CapsuleShape3D
	_cylinder = collider.shape as CylinderShape3D
	if _capsule != null:
		# Sub-resources are shared between scene instances; duplicate before
		# changing height so sliding one player cannot squash another.
		_capsule = _capsule.duplicate()
		collider.shape = _capsule
		_stand_height = _capsule.height
		collider.position.y = _capsule.height * 0.5
	elif _cylinder != null:
		_cylinder = _cylinder.duplicate()
		collider.shape = _cylinder
		_stand_height = _cylinder.height
		collider.position.y = _cylinder.height * 0.5
	_stand_eye_height = neck.position.y

	abilities.setup(self)
	state_machine.setup(self)

	if not Engine.is_editor_hint():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sensitivity := config.mouse_sensitivity * lerpf(
			1.0, config.scope_sensitivity_scale, scope_blend
		)
		_yaw -= event.relative.x * sensitivity
		_pitch = clampf(
			_pitch - event.relative.y * sensitivity,
			deg_to_rad(-config.max_pitch_degrees),
			deg_to_rad(config.max_pitch_degrees)
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

	if _dead:
		_respawn_timer -= delta
		velocity = Vector3.ZERO
		if _respawn_timer <= 0.0:
			respawn()
		return

	if input.reset_just_pressed and respawn_on_reset:
		respawn()
		return

	# Sensing first: states need this tick's wall hits, not last tick's.
	abilities.pre_move_update(delta)

	_update_timers(delta)
	accel_dir = _compute_accel_dir()
	# Only a slide asks for the compressed body pose; clear it every tick so a
	# state transition cannot leave the player stuck in it.
	slide_pose_target = 0.0

	state_machine.physics_update(delta)
	_update_slide_pose(delta)
	_clamp_horizontal_speed()

	# Stair handling: skip the normal slide when we step up onto a ledge.
	if not _snap_up_stairs(delta):
		move_and_slide()
		_snap_down_stairs()

	_post_move(delta)

	# Weapons/rope visuals run last so they use the final camera pose.
	abilities.post_move_update(delta)


# --- Timers ------------------------------------------------------------------

func _update_timers(delta: float) -> void:
	coyote_timer = maxf(coyote_timer - delta, 0.0)
	jump_buffer_timer = maxf(jump_buffer_timer - delta, 0.0)
	dash_cooldown_timer = maxf(dash_cooldown_timer - delta, 0.0)
	slide_cooldown_timer = maxf(slide_cooldown_timer - delta, 0.0)
	wall_run_cooldown_timer = maxf(wall_run_cooldown_timer - delta, 0.0)

	if is_on_floor():
		coyote_timer = config.coyote_time
		air_jumps_left = config.air_jumps

	if input.jump_just_pressed:
		jump_hold_timer = 0.0
		jump_started_in_air = not is_on_floor()
		jump_buffer_timer = config.jump_buffer_time
	elif input.jump_pressed:
		jump_hold_timer += delta
	else:
		jump_hold_timer = 0.0
		jump_started_in_air = false


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

	var horizontal_speed := get_horizontal_speed()
	_update_feel(delta, horizontal_speed)
	_update_footsteps(delta, horizontal_speed)


func _clamp_horizontal_speed() -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if horizontal.length() > config.max_horizontal_speed:
		horizontal = horizontal.normalized() * config.max_horizontal_speed
		velocity.x = horizontal.x
		velocity.z = horizontal.z


# --- Shared motion model (used by the states) --------------------------------

func apply_gravity(delta: float, scale: float = 1.0) -> void:
	velocity += get_gravity() * (config.gravity_scale * scale) * delta
	if velocity.y < -config.max_fall_speed:
		velocity.y = -config.max_fall_speed


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
	apply_friction(delta, config.friction if fric < 0.0 else fric)
	accelerate(accel_dir, wish_speed, config.ground_accel if accel < 0.0 else accel, delta)


func apply_air_movement(delta: float, wish_speed: float, accel: float) -> void:
	accelerate(accel_dir, wish_speed, accel, delta)


func apply_friction(delta: float, fric: float) -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var speed := horizontal.length()
	if speed <= 0.0:
		return
	var control := maxf(speed, 1.0)
	var new_speed := maxf(speed - control * fric * delta, 0.0)
	var factor := new_speed / speed
	velocity.x = horizontal.x * factor
	velocity.z = horizontal.z * factor


## Source-style velocity clipping for steep surfaces (surfing). Removes the
## component pushing into the surface while keeping tangential momentum.
func clip_velocity(normal: Vector3, overbounce: float = 1.0) -> void:
	var back := velocity.dot(normal)
	if back < 0.0:
		velocity -= normal * back * overbounce


## Returns true when the player is sliding along a steep, non-runnable surface.
## The air states call this so ramps feel like Source surf instead of a wall.
func apply_surf_clip() -> bool:
	if not is_on_wall():
		return false
	var normal := get_wall_normal()
	var angle := rad_to_deg(normal.angle_to(Vector3.UP))
	if absf(normal.normalized().y) <= cos(deg_to_rad(config.wall_run_min_angle_deg)):
		return false
	if angle <= rad_to_deg(floor_max_angle):
		return false
	clip_velocity(normal)
	return true


func get_horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


# --- Queries used by the states ----------------------------------------------

func wants_jump() -> bool:
	return jump_buffer_timer > 0.0 and coyote_timer > 0.0


func wants_air_jump() -> bool:
	return jump_buffer_timer > 0.0 and air_jumps_left > 0


## A slam is an air-started jump hold that is still held once the player is no
## longer rising. Holding a jump that began on the ground only adds height.
func wants_slam() -> bool:
	return not is_on_floor() \
		and jump_started_in_air \
		and input.jump_pressed \
		and jump_hold_timer >= config.slam_hold_time \
		and velocity.y <= 0.0


func consume_jump() -> void:
	jump_buffer_timer = 0.0
	coyote_timer = 0.0


func consume_air_jump() -> void:
	jump_buffer_timer = 0.0
	air_jumps_left = maxi(air_jumps_left - 1, 0)


## Speed required to auto-slide right now. Moving downhill on a ramp lowers the
## bar, which is what lets a fast descent chain straight into a slide.
func slide_engage_speed() -> float:
	if not is_on_floor():
		return config.slide_min_speed
	var normal := get_floor_normal()
	var slope := acos(clampf(normal.y, -1.0, 1.0))
	if slope < deg_to_rad(5.0):
		return config.slide_min_speed

	var downhill := Vector3.DOWN - normal * Vector3.DOWN.dot(normal)
	if downhill.length_squared() < 1e-6:
		return config.slide_min_speed
	downhill = downhill.normalized()
	var motion := Vector3(velocity.x, 0.0, velocity.z)
	if motion.dot(downhill) <= 0.0:
		return config.slide_min_speed

	var ramp_factor := clampf(slope / deg_to_rad(45.0), 0.0, 1.0)
	return lerpf(config.slide_min_speed, config.slide_ramp_min_speed, ramp_factor)


func can_slide() -> bool:
	if not is_on_floor() or slide_cooldown_timer > 0.0:
		return false
	return get_horizontal_speed() >= slide_engage_speed()


func can_dash() -> bool:
	return dash_cooldown_timer <= 0.0 \
		and vitals != null \
		and vitals.has_stamina(config.dash_stamina_cost)


func can_wall_run() -> bool:
	if is_on_floor() or wall_run_cooldown_timer > 0.0:
		return false
	if get_horizontal_speed() < config.wall_run_min_speed:
		return false
	var wall_sense := get_wall_sense()
	if wall_sense != null:
		return wall_sense.has_wall()
	if not is_on_wall():
		return false
	return absf(get_wall_normal().normalized().y) \
		<= cos(deg_to_rad(config.wall_run_min_angle_deg))


func can_grapple() -> bool:
	var grapple := get_grapple()
	return grapple != null \
		and grapple.can_attach() \
		and vitals != null \
		and vitals.has_stamina(config.grapple_stamina_cost)


func is_touching_wall() -> bool:
	return is_on_wall() and not is_on_floor()


func get_wall_sense() -> WallSense:
	return abilities.get_ability(&"wall_sense") as WallSense


func get_grapple() -> GrappleAbility:
	return abilities.get_ability(&"grapple") as GrappleAbility


func get_weapons() -> WeaponController:
	return abilities.get_ability(&"weapons") as WeaponController


## Wall data for `side` (-1 left, +1 right). Falls back to `is_on_wall()` when
## the optional WallSense node has been removed.
func get_wall(side: int) -> Dictionary:
	var wall_sense := get_wall_sense()
	if wall_sense != null:
		return wall_sense.get_wall(side)
	if not is_on_wall():
		return {}
	var normal := get_wall_normal()
	var camera_right := Basis(Vector3.UP, _yaw).x
	return {
		"point": get_wall_collision_point_if_any(),
		"normal": normal,
		"collider": null,
		"side": -1 if normal.dot(camera_right) < 0.0 else 1,
	}


func get_wall_collision_point_if_any() -> Vector3:
	for index in get_slide_collision_count():
		var collision := get_slide_collision(index)
		if collision != null and collision.get_normal().dot(Vector3.UP) < 0.5:
			return collision.get_position()
	return global_position


func preferred_wall_side() -> int:
	var wall_sense := get_wall_sense()
	if wall_sense != null:
		return wall_sense.preferred_side()
	var wall := get_wall(-1)
	if wall.is_empty():
		wall = get_wall(1)
	return int(wall.get("side", 0))


func register_landing() -> void:
	if _fall_speed > 6.0:
		_play_footstep(0.78, 0.5)
	_dip = -clampf(_fall_speed * config.landing_dip_scale, 0.05, 0.22)
	_fall_speed = 0.0
	air_jumps_left = config.air_jumps


## Adds a short view kick on top of the authored look angles. The offset decays
## in [method _update_feel], so recoil settles back without a permanent penalty.
func add_recoil(pitch_degrees: float, yaw_degrees: float = 0.0) -> void:
	_recoil_pitch = clampf(
		_recoil_pitch + deg_to_rad(pitch_degrees),
		deg_to_rad(-12.0),
		deg_to_rad(12.0)
	)
	_recoil_yaw = clampf(
		_recoil_yaw + deg_to_rad(yaw_degrees),
		deg_to_rad(-12.0),
		deg_to_rad(12.0)
	)


func respawn() -> void:
	global_transform = _spawn_transform
	velocity = Vector3.ZERO
	_fall_speed = 0.0
	_dead = false
	_respawn_timer = 0.0
	vitals.reset_vitals()
	slide_pose_target = 0.0
	slide_pose_amount = 0.0
	state_machine.transition_to(&"Idle")


## Called by [Damage] when this player damages something. The applied amount is
## already clipped to the target's remaining health, so overkill cannot fill the
## overhealth buffer.
func register_damage_dealt(amount: float) -> void:
	if _dead or vitals == null or config == null:
		return
	vitals.add_overhealth(amount * config.overhealth_gain_per_damage)


## Tries to parry an incoming shot. The weapon controller owns the sword and the
## facing check, so enemies only need this one call.
func try_parry(attacker_position: Vector3) -> bool:
	var weapons := get_weapons()
	if weapons == null:
		return false
	return weapons.try_parry(attacker_position)


func is_dead() -> bool:
	return _dead


func _on_died(_source: Node) -> void:
	if _dead:
		return
	_dead = true
	_respawn_timer = config.player_respawn_delay
	velocity = Vector3.ZERO
	scoped = false
	state_machine.transition_to(&"Idle")
	var weapons := get_weapons()
	if weapons != null:
		weapons.force_exit_scope()


## Current yaw used for movement and screen-relative probes.
func get_view_yaw() -> float:
	return _yaw


## Sets the look direction immediately. Useful for spawn orientation, cutscenes
## and tests; mouse input continues from the new angles.
func set_view_angles(yaw_radians: float, pitch_radians: float) -> void:
	_yaw = yaw_radians
	_pitch = clampf(
		pitch_radians,
		deg_to_rad(-config.max_pitch_degrees),
		deg_to_rad(config.max_pitch_degrees)
	)
	_recoil_pitch = 0.0
	_recoil_yaw = 0.0
	neck.rotation = Vector3(0.0, _yaw, _roll)
	camera.rotation = Vector3(_pitch, 0.0, 0.0)


# --- Slide pose / capsule ----------------------------------------------------

func set_slide_pose(value: float) -> void:
	slide_pose_target = clampf(value, 0.0, 1.0)


func _update_slide_pose(delta: float) -> void:
	var target := clampf(slide_pose_target, 0.0, 1.0)
	if target < slide_pose_amount and not _can_raise_from_slide():
		target = slide_pose_amount

	slide_pose_amount = move_toward(
		slide_pose_amount, target, config.slide_pose_speed * delta
	)

	if _capsule != null:
		var capsule_height := lerpf(_stand_height, config.slide_height, slide_pose_amount)
		if absf(_capsule.height - capsule_height) > 0.001:
			_capsule.height = capsule_height
			collider.position.y = capsule_height * 0.5
	elif _cylinder != null:
		var cylinder_height := lerpf(_stand_height, config.slide_height, slide_pose_amount)
		if absf(_cylinder.height - cylinder_height) > 0.001:
			_cylinder.height = cylinder_height
			collider.position.y = cylinder_height * 0.5

	neck.position.y = lerpf(_stand_eye_height, config.slide_eye_height, slide_pose_amount)


func _can_raise_from_slide() -> bool:
	if _capsule == null and _cylinder == null:
		return true
	var current := _capsule.height if _capsule != null else _cylinder.height
	var needed := _stand_height - current
	if needed <= 0.001:
		return true
	return not test_move(global_transform, Vector3(0.0, needed + 0.02, 0.0), _clearance)


# --- Stair stepping ----------------------------------------------------------
#
# Movement is snapped with raycasts rather than `test_move` on purpose: a capsule
# hitting the sharp corner of a step reports a diagonal normal, which looks like
# a slope and would be rejected as "not floor". A thin downward ray only ever
# hits the flat top of the step, so the normal is a clean up vector.

## Teleport up onto a step we are about to walk into. Returns true if we did.
func _snap_up_stairs(delta: float) -> bool:
	if not (is_on_floor() or _snapped_to_stairs_last_frame):
		return false

	var motion := Vector3(velocity.x, 0.0, velocity.z) * delta
	if motion.length_squared() < 1e-8:
		return false
	var forward := Vector3(motion.x, 0.0, motion.z).normalized()

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
	# Scope blend drives FOV, sensitivity, bob and roll together.
	scope_blend = move_toward(
		scope_blend, 1.0 if scoped else 0.0,
		config.scope_transition_speed * delta
	)

	var moving := is_on_floor() and horizontal_speed > 1.0

	# Head-bob (quieter while aiming).
	if moving:
		_headbob_time += delta * (horizontal_speed / maxf(config.walk_speed, 0.001)) \
			* config.headbob_frequency * TAU
		var bob_scale := lerpf(1.0, config.scope_headbob_scale, scope_blend)
		camera.position.y = sin(_headbob_time) * config.headbob_amplitude * bob_scale
		camera.position.x = cos(_headbob_time * 0.5) * config.headbob_amplitude * 0.6 * bob_scale
	else:
		var settle := 1.0 - exp(-9.0 * delta)
		camera.position.y = lerpf(camera.position.y, 0.0, settle)
		camera.position.x = lerpf(camera.position.x, 0.0, settle)

	# Landing dip (eases back to neutral).
	_dip = lerpf(_dip, 0.0, 1.0 - exp(-7.0 * delta))
	camera.position.y += _dip

	# Strafe + wall-run roll (reduced while scoped).
	var roll_scale := lerpf(1.0, config.scope_roll_scale, scope_blend)
	var target_roll := -input.move.x * deg_to_rad(config.strafe_tilt_degrees) * roll_scale
	_wall_roll = lerpf(_wall_roll, wall_roll_target, 1.0 - exp(-10.0 * delta))
	_roll = lerpf(_roll, target_roll + _wall_roll * roll_scale, 1.0 - exp(-8.0 * delta))

	# Recoil decays back to the authored aim.
	var recoil_decay := 1.0 - exp(-config.recoil_recovery * delta)
	_recoil_pitch = lerpf(_recoil_pitch, 0.0, recoil_decay)
	_recoil_yaw = lerpf(_recoil_yaw, 0.0, recoil_decay)

	neck.rotation = Vector3(0.0, _yaw + _recoil_yaw, _roll)
	camera.rotation = Vector3(_pitch + _recoil_pitch, 0.0, 0.0)

	# FOV: scope zoom wins over sprint/slide kicks.
	var target_fov := lerpf(config.base_fov, config.scope_fov, scope_blend)
	var kicks := 0.0
	if horizontal_speed > config.sprint_speed * 0.95:
		kicks += config.sprint_fov_kick
	if state_machine.current_name == &"Slide":
		kicks += config.slide_fov_kick
	if state_machine.current_name == &"WallRun":
		kicks += config.wall_run_fov_kick
	target_fov += kicks * (1.0 - scope_blend)
	var fov_speed := lerpf(6.0, config.scope_transition_speed, scope_blend)
	camera.fov = lerpf(camera.fov, target_fov, 1.0 - exp(-fov_speed * delta))


func _update_footsteps(delta: float, horizontal_speed: float) -> void:
	if is_on_floor() and horizontal_speed > 0.6 and slide_pose_amount < 0.6:
		_distance_since_step += horizontal_speed * delta
		var interval := config.step_interval
		if horizontal_speed > config.sprint_speed * 0.95:
			interval *= 0.85
		if _distance_since_step >= interval:
			_distance_since_step = 0.0
			_play_footstep(1.0 + randf_range(-0.08, 0.08), 0.0)
	else:
		_distance_since_step = minf(_distance_since_step, config.step_interval * 0.5)


func _play_footstep(pitch: float, extra_db: float) -> void:
	if FOOTSTEP_STREAMS.is_empty():
		return
	footstep_player.stream = FOOTSTEP_STREAMS[randi() % FOOTSTEP_STREAMS.size()]
	footstep_player.pitch_scale = clampf(pitch, 0.5, 2.0)
	footstep_player.volume_db = config.footstep_volume_db + extra_db
	footstep_player.play()
