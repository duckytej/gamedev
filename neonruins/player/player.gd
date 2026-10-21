extends CharacterBody3D
class_name Player

# === COLLISION HEIGHTS ===
const FULL_HEIGHT: float = 2.0
const CROUCH_HEIGHT: float = 1.2

# === STATE MACHINE ===
var current_state: State = null
var states: Dictionary = {}

# === MOVEMENT (Titanfall 2 / Source inspired) ===
@export_group("Movement")
@export var walk_speed: float = 6.5
@export var run_speed: float = 14.0
@export var crouch_speed: float = 3.5
@export var max_ground_speed: float = 28.0
@export var max_air_speed: float = 35.0

@export var ground_accel: float = 18.0
@export var air_accel: float = 4.5
@export var ground_friction: float = 6.0
@export var air_friction: float = 0.05
@export var slide_friction: float = 0.12
@export var wall_friction: float = 0.15

# === JUMP SYSTEM ===
@export_group("Jump")
@export var jump_height: float = 2.2
@export var jump_time_to_peak: float = 0.26
@export var jump_time_to_fall: float = 0.34
@export var max_air_jumps: int = 1
@export var coyote_time: float = 0.18
@export var jump_buffer_time: float = 0.15
@export var variable_jump_height_mult: float = 0.5

var jump_gravity: float
var fall_gravity: float
var jump_velocity: float

var air_jumps_left: int = 0
var coyote_timer: float = 0.0
var jump_buffer_timer: float = 0.0
var jump_held: bool = false
var _variable_jump_cut_applied: bool = false

# === DASH SYSTEM ===
@export_group("Dash")
@export var dash_duration: float = 0.12
@export var dash_cooldown: float = 0.35
@export var dash_speed: float = 42.0
@export var dash_end_speed_mult: float = 1.2

var dash_cooldown_timer: float = 0.0

# === SLIDE SYSTEM ===
@export_group("Slide")
@export var slide_duration: float = 0.9
@export var slide_min_entry_speed: float = 10.0
@export var slide_boost: float = 1.4
@export var slide_grace_time: float = 0.15

var slide_grace_timer: float = 0.0
var was_sliding: bool = false

# === WALL RUN SYSTEM ===
@export_group("Wall Run")
@export var wall_run_gravity_mult: float = 0.25
@export var wall_run_force: float = 9.0
@export var wall_run_lateral_boost: float = 18.0
@export var wall_run_max_time: float = 1.8
@export var wall_run_min_speed: float = 8.0
@export var wall_run_cooldown: float = 0.3
@export var wall_jump_force: float = 13.0
@export var wall_jump_up_force: float = 10.0

var wall_run_cooldown_timer: float = 0.0
var last_wall_normal: Vector3 = Vector3.ZERO

# === GRAPPLE SYSTEM (Spiderman pendulum) ===
@export_group("Grapple")
@export var grapple_max_distance: float = 45.0
@export var grapple_min_distance: float = 2.5
@export var grapple_gravity_mult: float = 0.3
@export var grapple_cooldown: float = 0.8
@export var grapple_launch_vel: float = 14.0

var grapple_cooldown_timer: float = 0.0

# === CAMERA / VIEW ===
@export_group("Camera")
@export var mouse_sensitivity: float = 0.0022
@export var base_fov: float = 85.0
@export var sprint_fov: float = 95.0
@export var max_fov: float = 105.0
@export var fov_transition_speed: float = 12.0
@export var headbob_freq: float = 9.0
@export var headbob_amp: float = 0.06
@export var headbob_tilt_amp: float = 0.5

var camera_pitch: float = 0.0
var gravity_scale: float = 1.0
var t_bob: float = 0.0
var current_fov: float = 85.0

# === LOCK-ON ===
var lock_on_target: Node3D = null
var lock_on_active: bool = false

# === NETWORK INTERPOLATION (remote avatars) ===
var net_target_position: Vector3 = Vector3.ZERO
var net_target_rotation_y: float = 0.0
var _net_has_snapshot: bool = false
const NET_SEND_RATE: float = 30.0  # Hz
var _net_send_timer: float = 0.0

# === COMPONENTS / NODES ===
@onready var health_component: HealthComponent = $HealthComponent
@onready var stamina_component: StaminaComponent = $StaminaComponent
@onready var ranged_system: RangedSystem = $RangedSystem
@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var grapple_raycast: RayCast3D = $CameraPivot/Camera3D/GrappleRaycast
@onready var attack_hitbox: HitboxComponent = $CameraPivot/Camera3D/AttackPivot/AttackHitbox
@onready var hurtbox: HurtboxComponent = $HurtboxComponent
@onready var wall_raycast_left: RayCast3D = $RayCastWallLeft
@onready var wall_raycast_right: RayCast3D = $RayCastWallRight
@onready var ceiling_raycast: RayCast3D = $RayCastCeiling

# === WEAPONS ===
var melee_weapon: WeaponResource = preload("res://combat/default_melee.tres")
var ranged_weapon: WeaponResource = preload("res://combat/default_ranged.tres")

# === DEBUG ===
@export var show_debug: bool = false
var _debug_accumulator: float = 0.0


func _ready() -> void:
	_init_gravity()
	_init_states()

	# SubResources are shared between instances - duplicate so crouch/slide
	# resizing one player doesn't resize every other player.
	collision_shape.shape = collision_shape.shape.duplicate()

	if hurtbox:
		hurtbox.damaged.connect(_on_hurt)

	grapple_raycast.target_position = Vector3(0, 0, -grapple_max_distance)

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	current_fov = base_fov
	air_jumps_left = max_air_jumps


func _init_gravity() -> void:
	jump_gravity = (-2.0 * jump_height) / (jump_time_to_peak * jump_time_to_peak)
	fall_gravity = (-2.0 * jump_height) / (jump_time_to_fall * jump_time_to_fall)
	jump_velocity = sqrt(2.0 * -jump_gravity * jump_height)


func _init_states() -> void:
	for child in $States.get_children():
		if child is State:
			states[child.name] = child
			child.player = self

	if states.has("Idle"):
		current_state = states["Idle"]
		current_state.enter()


# === INPUT (authority only) ===
func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		camera_pivot.rotate_y(-event.relative.x * mouse_sensitivity)
		camera_pitch = clampf(camera_pitch - event.relative.y * mouse_sensitivity, -PI / 2, PI / 2)
		camera.rotation.x = camera_pitch

	if event.is_action_pressed("lock_on"):
		_toggle_lock_on()

	if event.is_action_pressed("quit"):
		get_tree().quit()

	if event.is_action_pressed("jump"):
		jump_held = true
		jump_buffer_timer = jump_buffer_time
	elif event.is_action_released("jump"):
		jump_held = false

	if current_state:
		current_state.handle_input(event)


# === PHYSICS ===
func _physics_process(delta: float) -> void:
	if is_multiplayer_authority():
		_physics_process_local(delta)
	else:
		_physics_process_remote(delta)


func _physics_process_local(delta: float) -> void:
	_update_timers(delta)
	_track_wall_normal()

	if current_state:
		current_state.physics_process(delta)

	move_and_slide()

	# Auto-recover standing height once headroom returns (e.g. after sliding
	# under a low ceiling)
	if not is_standing() and not ceiling_raycast.is_colliding() \
			and current_state != null and not current_state.name in ["Crouch", "Slide"]:
		set_crouched(false)

	# Throttled RPC sync (30 Hz instead of physics rate)
	_net_send_timer += delta
	if multiplayer.multiplayer_peer != null and _net_send_timer >= 1.0 / NET_SEND_RATE:
		_net_send_timer = 0.0
		sync_state.rpc(global_position, velocity, camera_pivot.rotation.y, current_state.name if current_state else "Idle")

	if show_debug:
		_debug_accumulator += delta
		if _debug_accumulator >= 0.2:
			_debug_accumulator = 0.0
			_print_debug()


func _process(delta: float) -> void:
	if is_multiplayer_authority():
		update_camera(delta)


func _physics_process_remote(delta: float) -> void:
	if not _net_has_snapshot:
		return
	# Interpolate remote avatar toward latest snapshot
	var t := minf(delta * 12.0, 1.0)
	global_position = global_position.lerp(net_target_position, t)
	rotation.y = lerp_angle(rotation.y, net_target_rotation_y, t)


@rpc("any_peer", "call_remote", "unreliable")
func sync_state(pos: Vector3, vel: Vector3, yaw: float, state_name: String) -> void:
	# Star topology: clients only reach the server, so the server relays
	# each snapshot to every other peer.
	if multiplayer.is_server():
		var sender := multiplayer.get_remote_sender_id()
		for peer_id in multiplayer.get_peers():
			if peer_id != sender:
				sync_state.rpc_id(peer_id, pos, vel, yaw, state_name)
		return
	net_target_position = pos
	net_target_rotation_y = yaw
	_net_has_snapshot = true
	velocity = vel


func _update_timers(delta: float) -> void:
	dash_cooldown_timer = maxf(dash_cooldown_timer - delta, 0.0)
	wall_run_cooldown_timer = maxf(wall_run_cooldown_timer - delta, 0.0)
	grapple_cooldown_timer = maxf(grapple_cooldown_timer - delta, 0.0)

	coyote_timer = coyote_time if is_on_floor() else maxf(coyote_timer - delta, 0.0)
	jump_buffer_timer = maxf(jump_buffer_timer - delta, 0.0)

	# Variable jump height - cut upward velocity once on early release
	if not jump_held and velocity.y > 0.0 and not _variable_jump_cut_applied:
		velocity.y *= variable_jump_height_mult
		_variable_jump_cut_applied = true

	# Slide grace period after leaving the floor mid-slide
	if was_sliding and not is_on_floor():
		slide_grace_timer -= delta
	else:
		slide_grace_timer = slide_grace_time
	was_sliding = current_state != null and current_state.name == "Slide"


func _track_wall_normal() -> void:
	if is_on_floor() or wall_run_cooldown_timer > 0.0:
		return
	for ray: RayCast3D in [wall_raycast_left, wall_raycast_right]:
		if ray.is_colliding():
			var n := ray.get_collision_normal()
			if absf(rad_to_deg(n.angle_to(Vector3.UP)) - 90.0) < 15.0:
				last_wall_normal = n
				return


# === MOVEMENT HELPERS (Source/Quake style) ===
func apply_gravity(delta: float) -> void:
	velocity.y += gravity_scale * (jump_gravity if velocity.y > 0.0 else fall_gravity) * delta


func accelerate(wish_dir: Vector3, wish_speed: float, accel: float, delta: float) -> void:
	var current_speed := velocity.dot(wish_dir)
	var add_speed := wish_speed - current_speed
	if add_speed <= 0.0:
		return
	var accel_speed := minf(accel * wish_speed * delta, add_speed)
	velocity.x += wish_dir.x * accel_speed
	velocity.z += wish_dir.z * accel_speed


func apply_friction(friction: float, delta: float) -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	if speed < 0.1:
		velocity.x = 0.0
		velocity.z = 0.0
		return
	var control := maxi(speed, 10.0)  # Source: minimum stop speed
	var drop := control * friction * delta
	var new_speed := maxf(speed - drop, 0.0)
	var mult := new_speed / speed
	velocity.x *= mult
	velocity.z *= mult


func apply_air_acceleration(wish_dir: Vector3, wish_speed: float, delta: float) -> void:
	# Quake-style air acceleration (enables air strafing / bhop)
	var wish_spd := minf(wish_speed, 30.0)
	var current_speed := velocity.dot(wish_dir)
	var add_speed := wish_spd - current_speed
	if add_speed <= 0.0:
		return
	var accel_speed := minf(air_accel * wish_speed * delta, add_speed)
	velocity.x += wish_dir.x * accel_speed
	velocity.z += wish_dir.z * accel_speed


func clamp_horizontal_speed(max_speed: float) -> void:
	var horiz := Vector2(velocity.x, velocity.z)
	if horiz.length() > max_speed:
		horiz = horiz.normalized() * max_speed
		velocity.x = horiz.x
		velocity.z = horiz.y


func get_input_direction() -> Vector3:
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	return (camera_pivot.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()


# === JUMP HELPERS ===
func reset_air_jumps() -> void:
	air_jumps_left = max_air_jumps


func set_crouched(crouched: bool) -> void:
	if crouched:
		mesh.scale.y = 0.6
		collision_shape.shape.height = CROUCH_HEIGHT
		collision_shape.position.y = CROUCH_HEIGHT * 0.5
	else:
		# Never stand into a ceiling - stay crouched until there is headroom
		if ceiling_raycast.is_colliding():
			return
		mesh.scale.y = 1.0
		collision_shape.shape.height = FULL_HEIGHT
		collision_shape.position.y = FULL_HEIGHT * 0.5


func is_standing() -> bool:
	return collision_shape.shape.height >= FULL_HEIGHT


func capture_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func release_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func try_buffered_ground_jump() -> bool:
	# Ground/coyote jump driven by the input buffer
	if jump_buffer_timer <= 0.0:
		return false
	if is_on_floor() or coyote_timer > 0.0:
		coyote_timer = 0.0
		jump_buffer_timer = 0.0
		return true
	return false


func try_dash() -> bool:
	if Input.is_action_just_pressed("dash") and dash_cooldown_timer <= 0.0:
		dash_cooldown_timer = dash_cooldown
		return true
	return false


# === STATE TRANSITIONS ===
func transition_to(state_name: String) -> void:
	if not states.has(state_name):
		push_error("State not found: %s" % state_name)
		return
	if current_state == states[state_name]:
		return
	if current_state:
		current_state.exit()
	current_state = states[state_name]
	current_state.enter()


# === CAMERA ===
func update_camera(delta: float) -> void:
	var horiz_speed := Vector2(velocity.x, velocity.z).length()

	# Headbob while grounded and moving
	if is_on_floor() and horiz_speed > 0.5:
		t_bob += delta * horiz_speed * 0.5
		var bob_y := sin(t_bob * headbob_freq) * headbob_amp
		var bob_x := cos(t_bob * headbob_freq * 0.5) * headbob_amp * 0.5
		var bob_tilt := sin(t_bob * headbob_freq) * deg_to_rad(headbob_tilt_amp)
		camera.position = Vector3(bob_x, bob_y, -1.0)
		camera.rotation.z = bob_tilt
	else:
		camera.position = camera.position.lerp(Vector3(0, 0, -1), delta * 15.0)
		camera.rotation.z = lerpf(camera.rotation.z, 0.0, delta * 15.0)
		t_bob = 0.0

	# Speed/state based FOV kick
	var target_fov := base_fov
	if current_state:
		match current_state.name:
			"Slide", "Dash", "WallRun", "Grapple":
				target_fov = sprint_fov
			"InAir":
				if horiz_speed > run_speed * 1.5:
					var t := clampf((horiz_speed - run_speed * 1.5) / (max_air_speed - run_speed * 1.5), 0.0, 1.0)
					target_fov = lerpf(sprint_fov, max_fov, t)
			_:
				if horiz_speed > walk_speed * 1.2:
					var t := clampf((horiz_speed - walk_speed * 1.2) / (run_speed - walk_speed * 1.2), 0.0, 1.0)
					target_fov = lerpf(base_fov, sprint_fov, t)

	current_fov = lerpf(current_fov, target_fov, 1.0 - exp(-fov_transition_speed * delta))
	camera.fov = current_fov

	# Lock-on camera assist
	if lock_on_active and lock_on_target and is_instance_valid(lock_on_target):
		var look_dir := (lock_on_target.global_position - camera.global_position).normalized()
		var target_yaw := atan2(-look_dir.x, -look_dir.z)
		var target_pitch := asin(clampf(look_dir.y, -1.0, 1.0))
		camera_pivot.rotation.y = lerp_angle(camera_pivot.rotation.y, target_yaw, 10.0 * delta)
		camera_pitch = lerp(camera_pitch, target_pitch, 10.0 * delta)
		camera.rotation.x = camera_pitch


# === LOCK-ON ===
func _toggle_lock_on() -> void:
	if lock_on_active:
		lock_on_active = false
		lock_on_target = null
		SignalBus.lock_on_changed.emit(self, null)
		return

	var nearest := _find_lock_on_target()
	if nearest:
		lock_on_active = true
		lock_on_target = nearest
		SignalBus.lock_on_changed.emit(self, nearest)


func _find_lock_on_target() -> Node3D:
	var cam_pos := camera.global_position
	var cam_dir := -camera.global_basis.z
	const MAX_DIST := 60.0
	const MAX_ANGLE := deg_to_rad(50.0)
	var best_target: Node3D = null
	var best_score: float = -1.0

	var candidates: Array[Node3D] = []
	candidates.assign(Globals.get_all_players())
	candidates.append_array(Globals.enemies)

	for candidate in candidates:
		if candidate == self or not candidate is Node3D:
			continue
		if not is_instance_valid(candidate):
			continue
		var to_target: Vector3 = candidate.global_position + Vector3(0, 1.0, 0) - cam_pos
		var dist := to_target.length()
		if dist > MAX_DIST or dist < 0.1:
			continue
		var angle := cam_dir.angle_to(to_target.normalized())
		if angle > MAX_ANGLE:
			continue
		var score := (1.0 - angle / MAX_ANGLE) * (1.0 - dist / MAX_DIST)
		if score > best_score:
			best_score = score
			best_target = candidate
	return best_target


# === DAMAGE REACTION ===
func _on_hurt(_amount: float, source: Node, knockback: Vector3) -> void:
	if not health_component.is_alive():
		return
	velocity += knockback
	if source is Node3D:
		# Face the damage source briefly for game feel
		var to_source: Vector3 = source.global_position - global_position
		camera_pivot.rotation.y = lerp_angle(camera_pivot.rotation.y, atan2(-to_source.x, -to_source.z), 0.3)
	transition_to("Hurt")


func _print_debug() -> void:
	print("State: %s | Vel: %.1f | Floor: %s | WallL: %s | WallR: %s" % [
		current_state.name if current_state else "null",
		Vector2(velocity.x, velocity.z).length(),
		is_on_floor(),
		wall_raycast_left.is_colliding(),
		wall_raycast_right.is_colliding(),
	])
