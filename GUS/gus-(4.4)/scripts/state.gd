extends CharacterBody3D

# --- MOVEMENT BASE ---
var ground_accel := 16.0
var air_accel := 6.0
var max_ground_vel := 40.0
var max_air_vel := 100.0
var friction := 3.0
var air_friction := 0.1
var base_grav := 9.8
var grav := 9.8

# --- JUMP SYSTEM ---
var coyote := 0.0
var buffer := 0.0
var jagain := 2
const JUMP_FORCE := 8.0

# --- DASH SYSTEM ---
var dash_cooldown := 1.5
var dash_timer := 0.0
const DASH_FORCE := 40.0

# --- GRAPPLE SYSTEM ---
const GRAPPLE_MAX_DIST := 30.0
const GRAPPLE_RELEASE_DIST := 2.0
const GRAPPLE_PULL_SPEED := 50.0
const GRAPPLE_LERP_SPEED := 4.0
const GRAPPLE_GRAVITY := 1.5
var grap_location: Vector3 = Vector3.ZERO
var grap_active := false
var grap_line: MeshInstance3D
var grap_timer := 0.0

# --- WALLRUN SYSTEM ---
const WALL_RUN_GRAVITY := 3.0
const WALL_RUN_FORCE := 8.0
const WALL_RUN_LATERAL_BOOST := 20.0
const WALL_RUN_MIN_ANGLE := 80.0
const WALL_RUN_MAX_ANGLE := 100.0
const WALL_RUN_FRICTION := 0.2
var wall_run_active := false
var last_wall_normal: Vector3 = Vector3.ZERO
var can_wallrun := true

# --- CROUCH / SLIDE ---
const CROUCH_HEIGHT := 0.7
const DEFAULT_HEIGHT := 2.0
const CROUCH_SPEED := 7.0
const SLIDE_MIN_SPEED := 8.0
const SLIDE_FRICTION := 0.5
const SLIDE_MOMENTUM_BOOST := 1.15
var sliding := false
var slide_start_speed := 0.0

# --- CAMERA / VIEW ---
var sens:= 0.002
var bob_freq := 1.0
var bob_amp := 0.08
var t_bob := 0.0
var base_fov := 80.0
var sprint_fov := 90.0
const FOV_SPEED_THRESHOLD := 30.0
const FOV_MAX := 100.0
var camera_pitch := 0.0
var camera_base_offset := Vector3(0, 2, -1)

# --- NODES ---
@onready var nek = $nek
@onready var cam = $nek/Camera3D
@onready var pcap = $CollisionShape3D
@onready var wall_raycast = $RayCast3D
@onready var wall_raycast2 = $RayCast3D2


# ----------------------------
# -------- INPUT LOOK --------
# ----------------------------
func _unhandled_input(event):
	if event is InputEventMouseMotion:
		nek.rotate_y(-event.relative.x * sens)
		camera_pitch = clamp(camera_pitch - event.relative.y * sens, -PI / 2, PI / 2)
		cam.rotation.x = camera_pitch


# ----------------------------
# ------- PHYSICS LOOP -------
# ----------------------------
func _physics_process(delta):
	handle_grapple(delta)
	handle_dash(delta)

	var input_dir = Input.get_vector("left", "right", "up", "down")
	var direction = (nek.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	if is_on_floor():
		handle_ground(direction, delta)
	else:
		handle_air(direction, delta)

	handle_jump(delta)
	handle_crouch(delta)
	handle_wallrun(direction, delta)

	# Apply gravity here (not in _process)
	if not grap_active and not wall_run_active and not is_on_floor():
		velocity.y -= grav * delta

	# Move and update velocity properly
	move_and_slide()

	# Camera & view adjustments
	cam.transform.origin = camera_base_offset + headbob(delta)
	update_fov(delta)

	# Timers
	dash_timer -= delta
	coyote = 0.2 if is_on_floor() else max(coyote - delta, 0.0)
	buffer = max(buffer - delta, 0.0)

	# Gradually restore gravity when not in special state
	if not grap_active and not wall_run_active:
		grav = lerp(grav, base_grav, delta * 5.0)


# ----------------------------
# ------- MOVEMENT CORE ------
# ----------------------------
func accelerate(accel_dir: Vector3, prev_vel: Vector3, accel: float, max_vel: float, delta: float) -> Vector3:
	var proj_vel = prev_vel.dot(accel_dir)
	var accel_vel = accel * delta
	if proj_vel + accel_vel > max_vel:
		accel_vel = max_vel - proj_vel
	return prev_vel + accel_dir * accel_vel

func handle_ground(accel_dir: Vector3, delta: float) -> void:
	var speed = velocity.length()
	if speed != 0:
		var current_friction = SLIDE_FRICTION if sliding else friction
		var drop = speed * current_friction * delta
		velocity *= max(speed - drop, 0) / speed

	if not sliding or accel_dir.length() > 0.1:
		velocity = accelerate(accel_dir, velocity, ground_accel, max_ground_vel, delta)

	jagain = 2
	can_wallrun = true
	last_wall_normal = Vector3.ZERO

func handle_air(accel_dir: Vector3, delta: float) -> void:
	var speed = velocity.length()
	if speed != 0:
		var drop = speed * air_friction * delta
		velocity *= max(speed - drop, 0) / speed

	velocity = accelerate(accel_dir, velocity, air_accel, max_air_vel, delta)


# ----------------------------
# ---------- JUMP ------------
# ----------------------------
func handle_jump(delta: float) -> void:
	if Input.is_action_just_pressed("ui_accept"):
		buffer = 0.15
	if buffer > 0.0 and coyote > 0.0 and jagain > 0:
		jagain -= 1
		coyote = 0.0
		buffer = 0.0
		velocity.y = JUMP_FORCE


# ----------------------------
# ---------- DASH ------------
# ----------------------------
func handle_dash(delta: float) -> void:
	if Input.is_action_just_pressed("dash") and dash_timer <= 0.0:
		dash_timer = dash_cooldown
		var forward = -nek.transform.basis.z.normalized()
		velocity += forward * DASH_FORCE


# ----------------------------
# -------- WALLRUN -----------
# ----------------------------
func handle_wallrun(accel_dir: Vector3, delta: float) -> void:
	if is_on_wall() and not is_on_floor() and can_wallrun:
		var wall_normal = get_wall_normal()
		if last_wall_normal.length() > 0 and wall_normal.dot(last_wall_normal) > 0.9:
			return

		var angle = rad_to_deg(wall_normal.angle_to(Vector3.UP))
		if angle > WALL_RUN_MIN_ANGLE and angle < WALL_RUN_MAX_ANGLE:
			var lateral_dir = wall_normal.cross(Vector3.UP).normalized()
			var move_dot = velocity.normalized().dot(lateral_dir)
			if abs(move_dot) > 0.3:
				var speed = velocity.length()
				if speed != 0:
					var drop = speed * WALL_RUN_FRICTION * delta
					velocity *= max(speed - drop, 0) / speed
				velocity.y = clamp(velocity.y + WALL_RUN_FORCE * delta, -10, 10)
				velocity += lateral_dir * sign(move_dot) * delta * WALL_RUN_LATERAL_BOOST
				grav = WALL_RUN_GRAVITY
				wall_run_active = true
				last_wall_normal = wall_normal
				can_wallrun = false
				return

	if wall_run_active:
		wall_run_active = false
		grav = base_grav


# ----------------------------
# --------- GRAPPLE ----------
# ----------------------------
func handle_grapple(delta: float) -> void:
	if Input.is_action_just_pressed("grap") and %grap.is_colliding():
		grap_location = %grap.get_collision_point()
		grap_active = true

		if grap_line:
			grap_line.queue_free()
			grap_line = null

		grap_line = draw_line(global_position, grap_location)

	if grap_active:
		var dist = global_position.distance_to(grap_location)
		if dist < GRAPPLE_MAX_DIST:
			velocity = velocity.lerp((grap_location - global_position).normalized() * GRAPPLE_PULL_SPEED, delta * GRAPPLE_LERP_SPEED)
			grav = GRAPPLE_GRAVITY
			update_grapple_line()

		if Input.is_action_just_released("grap") or dist < GRAPPLE_RELEASE_DIST:
			grap_active = false
			grav = base_grav
			if grap_line:
				grap_line.queue_free()
				grap_line = null


# ----------------------------
# --------- CROUCH -----------
# ----------------------------
func handle_crouch(delta: float) -> void:
	if Input.is_action_pressed("crouch"):
		pcap.shape.height = lerp(pcap.shape.height, CROUCH_HEIGHT, delta * CROUCH_SPEED)
		if is_on_floor() and velocity.length() > SLIDE_MIN_SPEED and not sliding:
			sliding = true
			slide_start_speed = velocity.length()
			var horizontal_vel = Vector3(velocity.x, 0, velocity.z)
			if horizontal_vel.length() > 0:
				horizontal_vel = horizontal_vel.normalized() * horizontal_vel.length() * SLIDE_MOMENTUM_BOOST
				velocity.x = horizontal_vel.x
				velocity.z = horizontal_vel.z
	else:
		pcap.shape.height = lerp(pcap.shape.height, DEFAULT_HEIGHT, delta * CROUCH_SPEED)
		sliding = false

	pcap.shape.height = clamp(pcap.shape.height, CROUCH_HEIGHT, DEFAULT_HEIGHT)


# ----------------------------
# -------- HEADBOB -----------
# ----------------------------
func headbob(delta: float) -> Vector3:
	t_bob += delta * velocity.length() * float(is_on_floor())
	var pos = Vector3.ZERO
	pos.y = sin(t_bob * bob_freq) * bob_amp
	pos.x = cos(t_bob * bob_freq / 2.0) * bob_amp
	return pos


# ----------------------------
# -------- CAMERA FOV --------
# ----------------------------
func update_fov(delta: float) -> void:
	var speed = velocity.length()
	var target_fov = base_fov
	if speed > FOV_SPEED_THRESHOLD:
		var speed_factor = min((speed - FOV_SPEED_THRESHOLD) / 50.0, 1.0)
		target_fov = lerp(sprint_fov, FOV_MAX, speed_factor)
	elif sliding or wall_run_active or dash_timer > 0.0:
		target_fov = sprint_fov

	cam.fov = lerp(cam.fov, target_fov, 1.0 - exp(-10.0 * delta))


# ----------------------------
# ---------- UTILS -----------
# ----------------------------
func draw_line(p1: Vector3, p2: Vector3, color := Color.WHITE_SMOKE) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var mesh := ImmediateMesh.new()
	var mat := ORMMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mesh_instance.mesh = mesh
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	mesh.surface_add_vertex(p1)
	mesh.surface_add_vertex(p2)
	mesh.surface_end()
	add_child(mesh_instance) # safer parent
	return mesh_instance

func update_grapple_line() -> void:
	if grap_line:
		var mesh = grap_line.mesh as ImmediateMesh
		if not mesh:
			return
		mesh.clear_surfaces()
		mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		mesh.surface_add_vertex(global_position)
		mesh.surface_add_vertex(grap_location)
		mesh.surface_end()

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	cam.current = true
