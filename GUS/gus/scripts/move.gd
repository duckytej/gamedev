extends CharacterBody3D
class_name Player

# ===== CONFIGURATION =====
enum State { GROUND, AIR, WALL_RUN, SLIDE, GRAPPLE, DASH }
var current_state: State = State.AIR

# References
@onready var head: Node3D = $nek
@onready var camera: Camera3D = $nek/Camera3D
@onready var check_ray_left: RayCast3D = $RayCast3D2 # Ensure this points left
@onready var check_ray_right: RayCast3D = $RayCast3D  # Ensure this points right
@onready var grapple_ray: RayCast3D = %grap # Add a Raycast for grapple
@onready var grapple_mesh: ImmediateMesh = $GrappleLine.mesh # Add a MeshInstance3D with ImmediateMesh

# Movement Settings (Quake/Titanfall Tuned)
var speed_ground := 10.0
var speed_run := 15.0
var speed_air_cap := 2.0
var accel_ground := 7.0
var accel_air := 40.0
var friction := 6.0
var gravity := 25.0
var jump_force := 10.0

# Mechanics Variables
var jumps_left := 1
var grapple_point := Vector3.ZERO
var dash_cooldown_timer := 0.0
var headbob_time := 0.0

# Input
var wish_dir := Vector3.ZERO
var mouse_sens := 0.003

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Setup Grapple Line
	var mesh_inst = MeshInstance3D.new()
	mesh_inst.name = "GrappleLine"
	mesh_inst.mesh = ImmediateMesh.new()
	# Set material to be unshaded/bright
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color.CYAN
	mesh_inst.material_override = mat
	add_child(mesh_inst)
	grapple_mesh = mesh_inst.mesh

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		head.rotate_y(-event.relative.x * mouse_sens)
		camera.rotate_x(-event.relative.y * mouse_sens)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-89), deg_to_rad(89))

func _physics_process(delta: float) -> void:
	process_input()
	process_state_transitions()
	update_timers(delta)
	
	# Gravity (Applied everywhere except specific states)
	#if current_state != State.WALL_RUN and current_state != State.GRAPPLE and current_state != State.DASH:
		#velocity.y -= gravity * delta
	velocity.y-=gravity*delta
	
	# State Logic
	match current_state:
		State.GROUND:
			jumps_left = 1 # Reset double jump
			apply_friction(delta)
			apply_ground_accel(delta)
			if Input.is_action_just_pressed("jump"):
				velocity.y += jump_force
		
		State.AIR:
			apply_air_accel(delta)
			if Input.is_action_just_pressed("jump") and jumps_left > 0:
				velocity.y = jump_force
				jumps_left -= 1 # Double jump
		
		State.SLIDE:
			apply_slide_physics(delta)
			if Input.is_action_just_pressed("jump"):
				velocity.y = jump_force
				current_state = State.AIR
		
		State.WALL_RUN:
			apply_wall_run_physics(delta)
			if Input.is_action_just_pressed("jump"):
				perform_wall_jump()
				
		State.GRAPPLE:
			apply_grapple_physics(delta)
			
		State.DASH:
			# Dash is a fixed velocity state
			pass 

	move_and_slide()
	
	# Visuals
	handle_headbob(delta)
	draw_grapple_line()
func perform_wall_jump() ->void:
	var wall_normal = get_wall_normal_from_ray()
	if wall_normal == Vector3.ZERO:
		return
	
	# Direction away from wall + up + player input influence
	var jump_dir = (wall_normal + Vector3.UP).normalized()
	
	# Add lateral input for more control (like Titanfall)
	if wish_dir.length() > 0:
		# Blend between pure wall normal and input direction
		var input_along_wall = wish_dir.slide(wall_normal).normalized()
		jump_dir = (jump_dir + input_along_wall * 0.7).normalized()
	
	# Apply jump velocity
	velocity += jump_dir * (jump_force * 1.4)  # Slightly stronger than normal jump
	velocity.y += jump_force * 1.5  # Ensure upward boost
	
	# Reset abilities
	jumps_left = 1  # Allow double jump after wall jump
	current_state = State.AIR
# ===== STATE MANAGEMENT =====
func process_state_transitions() -> void:
	# GRAPPLE START
	if Input.is_action_pressed("grap") and current_state != State.GRAPPLE:
		if grapple_ray.is_colliding():
			grapple_point = grapple_ray.get_collision_point()
			if global_position.distance_to(grapple_point) < 30: # Max dist
				current_state = State.GRAPPLE
				jumps_left = 1 # Restore jump on grapple

	# GRAPPLE END
	if current_state == State.GRAPPLE:
		if not Input.is_action_pressed("grap") or global_position.distance_to(grapple_point) < 2.0:
			current_state = State.AIR

	# DASH
	if Input.is_action_just_pressed("dash") and dash_cooldown_timer <= 0:
		start_dash()
		return

	# GROUND / AIR
	if is_on_floor():
		if current_state != State.GROUND and current_state != State.SLIDE and current_state != State.DASH:
			if Input.is_action_pressed("crouch"):
				enter_slide()
			else:
				current_state = State.GROUND
	else:
		if current_state == State.GROUND or current_state == State.SLIDE:
			current_state = State.AIR
			
	# WALL RUN
	if current_state == State.AIR and Input.is_action_pressed("up"):
		if check_wall_run():
			current_state = State.WALL_RUN

func start_dash() -> void:
	current_state = State.DASH
	dash_cooldown_timer = 1.5
	# Dash towards look direction
	var dash_dir = -camera.global_transform.basis.z
	velocity = dash_dir * 50.0 # Instant burst
	# Dash only lasts a split second, handled by timer/friction
	await get_tree().create_timer(0.2).timeout
	if current_state == State.DASH:
		velocity *= 0.2 # Drag after dash
		current_state = State.AIR

# ===== PHYSICS CORE (QUAKE/SOURCE) =====
func apply_friction(delta: float) -> void:
	var speed = velocity.length()
	if speed < 0.1: return
	var drop = speed * friction * delta
	var new_speed = max(speed - drop, 0) / speed
	velocity.x *= new_speed
	velocity.z *= new_speed

func accelerate(target_dir: Vector3, target_speed: float, accel: float, delta: float) -> void:
	var current_speed = velocity.dot(target_dir)
	var add_speed = target_speed - current_speed
	if add_speed <= 0: return
	var accel_speed = accel * delta * target_speed
	if accel_speed > add_speed: accel_speed = add_speed
	velocity += target_dir * accel_speed

func apply_ground_accel(delta: float) -> void:
	accelerate(wish_dir, speed_run, accel_ground, delta)

func apply_air_accel(delta: float) -> void:
	# This creates the air-strafing
	accelerate(wish_dir, speed_air_cap, accel_air, delta)

func apply_grapple_physics(delta: float) -> void:
	var dir = (grapple_point - global_position).normalized()
	# Add force towards point
	velocity += dir * 80.0 * delta
	# Slight gravity to make it swing
	velocity.y -= gravity * 0.5 * delta
	# Dampen existing velocity slightly to prevent infinite orbiting
	velocity *= 0.98

func apply_wall_run_physics(delta: float) -> void:
	var wall_normal = get_wall_normal_from_ray()
	# Lock gravity
	velocity.y = 0 
	velocity.y -= gravity * 0.2 * delta # Tiny bit of drop
	
	# Source-style "Clip" (Project velocity along wall)
	var tangent = Vector3.UP.cross(wall_normal)
	if tangent.dot(-head.transform.basis.z) < 0: tangent = -tangent
	
	accelerate(tangent, speed_run * 1.5, accel_ground, delta)
	
	# Stick to wall
	velocity -= wall_normal * 5.0 * delta
	
	if not check_wall_run(): current_state = State.AIR

# ===== HELPERS & VISUALS =====
func process_input() -> void:
	var input_dir = Input.get_vector("left", "right", "up", "down")
	wish_dir = (head.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

func update_timers(delta: float) -> void:
	dash_cooldown_timer = max(0, dash_cooldown_timer - delta)

func handle_headbob(delta: float) -> void:
	if current_state == State.GROUND and velocity.length() > 2.0:
		headbob_time += delta * velocity.length() * 1.5
		var y_pos = sin(headbob_time) * 0.05
		camera.position.y = lerp(camera.position.y, y_pos, delta * 10)
	else:
		camera.position.y = lerp(camera.position.y, 0.0, delta * 5)

func draw_grapple_line() -> void:
	grapple_mesh.clear_surfaces()
	if current_state == State.GRAPPLE:
		grapple_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		# Draw from gun/hand position to point
		var start = to_local(head.global_position + Vector3(0, -0.2, 0)) # Offset slightly
		var end = to_local(grapple_point)
		grapple_mesh.surface_add_vertex(start)
		grapple_mesh.surface_add_vertex(end)
		grapple_mesh.surface_end()

func check_wall_run() -> bool:
	return check_ray_left.is_colliding() or check_ray_right.is_colliding()

func get_wall_normal_from_ray() -> Vector3:
	if check_ray_left.is_colliding(): return check_ray_left.get_collision_normal()
	if check_ray_right.is_colliding(): return check_ray_right.get_collision_normal()
	return Vector3.ZERO
	
func enter_slide() -> void:
	current_state = State.SLIDE
	velocity += velocity.normalized() * 10.0 # Boost
	
func apply_slide_physics(delta: float) -> void:
	# Minimal friction
	var speed = velocity.length()
	velocity *= 0.99 
	if speed < 5.0: current_state = State.GROUND
#extends  CharacterBody3D
#class_name Player
#
#@onready var nek: Node3D = $nek
#@onready var right: RayCast3D = $RayCast3D
#@onready var left: RayCast3D = $RayCast3D2
#@onready var cam: Camera3D = $nek/Camera3D
#
#@export var ground_accel:= 16
#@export var fric:= 2.0
#@export var max_gnd_vel=30
#const grav=10
##crouch, slide, dash
#
#@export var sl_fric:=1.5
#var sliding =false
#
#@export var max_vel=50
#@export var air_accel=7
#@export var air_move=10
#@export var air_cap=1.2
#
#var buffer:=0.0
#var coyotte:=0.0
#var wall_fric=0.9
#var walling=false
#var wn:=Vector3.ZERO
#
#var bob_hz:=2
#var bob_amp:=0.1
#var t_bob := 0.0
#@export var sens:=0.02
##fov variables
#const BASE_FOV := 80
#const FOV_CHANGE := 1.3
#const origin:=Vector3(0,0,0)
#
#var stamina:float=100
#func _ready() -> void:
	#Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	#floor_snap_length=0.5
#func _unhandled_input(event: InputEvent):
	#if event is InputEventMouseMotion:
		#nek.rotate_y(-event.relative.x * sens)
		#cam.rotate_x(-event.relative.y * sens)
		#cam.rotation.x = clamp(cam.rotation.x, deg_to_rad(-70), deg_to_rad(70))
#func _headbob(delta,time) -> void:
	#t_bob += delta * velocity.length() * float(is_on_floor())
	#var pos = Vector3.ZERO
	#pos.y = sin(time * bob_hz) * bob_amp
	#pos.x = cos(time * bob_hz / 2) * bob_amp
	#cam.transform.origin = origin+pos
	##fov
	#var velocity_clamped :float= clamp(velocity.length(), 0.5, max_vel/2.0) 
	#var target_fov :float= BASE_FOV + (FOV_CHANGE * velocity_clamped)
	#cam.fov = lerp(cam.fov, target_fov, delta * 8)
#
#
#func _physics_process(delta: float) -> void:
	#var input_dir = Input.get_vector("left", "right", "up", "down")
	#var dir = (nek.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	#move(dir,velocity,delta)
	#wallrun(delta)
	#jump(dir,delta)
	#_headbob(delta,t_bob)
	#move_and_slide()
#
#func move(dir,prev_vel,delta)-> void:
	#var speed :float= prev_vel.length()
	#var capped_speed :float= min((air_move * dir).length(), air_cap)
	#var tilt =dir.dot(get_floor_normal())
	#print(walling," speed:", (velocity.length()))
	#if is_on_floor() or walling:
		#if speed != 0:
			#var friction := sl_fric if (sliding or walling) else fric
			#var drop :float=  speed*friction*delta
			#prev_vel*=max(speed-drop,0) / speed
		#velocity= accelrate(dir,prev_vel,ground_accel+tilt,max_gnd_vel,delta,1)
	#else:
		#var accel_vel :float= air_move*air_accel*delta
		#var proj_vel :float= prev_vel.dot(dir)
		#if capped_speed - proj_vel>0:
			#velocity+= (dir*accel_vel)
	#velocity.y-=grav*delta
#
#func accelrate(accel_dir:Vector3,prev_vel:Vector3,accel:float,max_v:int,delta:float,move_vel:int) -> Vector3:
	#var proj_vel = prev_vel.dot(accel_dir)
	#var accel_vel = move_vel*accel*delta
	#if proj_vel+accel_vel>max_v:
		#accel_vel=max_v-proj_vel
	#return prev_vel+accel_dir*accel_vel
##v^2=u^2+2as
#func jump(dir,delta) -> void:
	##print(walling)
	#if is_on_floor():
		#coyotte=0.2
	#else:
		#coyotte-=delta
#
	#if Input.is_action_just_released("jump") and velocity.y>0.0:
		#velocity.y*=0.5
#
	#if Input.is_action_just_pressed("jump"):
		#buffer=0.15
		#if walling:
			#velocity.y+=800*delta
			#velocity+=800*wn*delta #wall bounce/jump
			#velocity+=dir*400*delta
			#
	#else:
		#buffer-=delta
	#if (buffer>0&&coyotte>0):
		#velocity.y+=50*delta
		#
#func wallrun(delta):
	##print(walling)
	#if !is_on_floor() and (left.is_colliding() or right.is_colliding()):
		#walling=true
		#if left.is_colliding():
			#wn=left.get_collision_normal()
		#else:
			#wn=right.get_collision_normal()
	#else:
		#walling=false
		#wn=Vector3.ZERO
	#if walling:
		#await get_tree().create_timer(0.1).timeout# allow jump first
		#if Input.is_action_pressed("jump")==false:
			#velocity-=wn*10*delta #push into wall
		#velocity.y*=wall_fric
			#
#
