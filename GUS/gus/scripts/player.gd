#extends CharacterBody3D
#var ground_accel := 16
#var max_ground_vel := 40
#var air_accel := 6
#var max_air_vel := 100
#var friction := 2.9
#var grav :float = 10
#var jagain :=2
#var coyote :=0.0
#var buffer := 0.0
#var sltime :=0.4
#var decre :=0.4
#var air_cap :=1.3
#var sagain:=false
#
#var bob_freq :=2
#var bob_amp :=0.08
#var t_bob := 0.0
#@onready var nek=$nek
#@onready var cam=$nek/Camera3D
#
#func _unhandled_input(event) -> void:
	#if event is InputEventMouseMotion:
		#if free:
			#nek.rotate_y(-event.relative.x*.002)
			#nek.rotation.y=clamp(nek.rotation.y,deg_to_rad(-115),deg_to_rad(115))
		#cam.rotate_y(-event.relative.y*.002)
		#cam.rotation.y= clamp(cam.rotation.x,-PI/2,PI/2)
#
#func accelrate(accel_dir:Vector3,prev_vel:Vector3,accel:float,max_vel:int,delta:float) -> Vector3:
	#var proj_vel = prev_vel.dot(accel_dir)
	##print(accel_dir)
	#var accel_vel = accel*delta
	#if proj_vel+accel_vel>max_vel:
		#accel_vel=max_vel-proj_vel
	#return prev_vel+accel_dir*accel_vel
	#
	#
#func _physics_process(delta:float) -> void:
	#var input_dir := Input.get_vector("left", "right", "up", "down")
	#print(input_dir)
	#var direction :Vector3= (nek.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	#if is_on_floor():
		#velocity=move_ground(direction,velocity,delta)
		#print(position)
	#else:
		#velocity.y-=grav*delta
	#move_and_slide()
		#
		#
#func _ready() -> void:
	#Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	#cam.current=true
#
#func headbob(time) -> Vector3:
	#var pos := Vector3.ZERO
	#pos.y = sin(time* bob_freq) * bob_amp
	#pos.x = cos(time* bob_freq / 2) * bob_amp
	#return pos
#
#
#func move_ground(accel_dir:Vector3,prev_vel:Vector3,delta:float) -> Vector3:
	#var speed :float= prev_vel.length()
	#if speed != 0:
		#var drop =  speed*friction*delta
		#prev_vel*=max(speed-drop,0) / speed
	#return accelrate(accel_dir,prev_vel,ground_accel,max_ground_vel,delta)
	
	
	#func handleCrouch(delta : float, forceCrouch : bool = false, forceUncrouch : bool = false) -> bool:
	#var height : float = collider.shape.height
	#var crouching : bool = Input.is_action_pressed("crouch") or (height < fullHeight - 0.1 and ceilingCheck.is_colliding()) or forceCrouch
	#crouching = false if forceUncrouch else crouching 
	#
	#if height != fullHeight or height != crouchHeight:
		#collider.shape.height = lerp(collider.shape.height, crouchHeight if crouching else fullHeight, delta * heightLerpSpeed)
		#head.position.y = lerp(head.position.y, headOffset if !crouching else headOffset/2, delta * heightLerpSpeed)
	#
	#return crouching
#func ground(delta : float) -> void:
	#isCrouching = handleCrouch(delta)
	#
	#floor_snap_length = floorSnapLength
	#gravity_vec = Vector3.ZERO
	#
	#if !isCrouching or (isCrouching and velocity.length() > startSlideThresh):
		#move(delta, floorAccel, floorDrag)
		#if isCrouching:
			#toSlide()
	#else:
		#move(delta, crouchAccel, floorDrag)
	#
	#groundToAir()

#func toSlide() -> bool:
	#if canSlideBoost:
		#applyForce(velocity.normalized() * slideBoostForce)
		#canSlideBoost = false
		#executeAfterTime(slideBoostTime, func(): canSlideBoost = true)
	#changeState(MOVESTATES.SLIDING)
	#return true
#func air(delta : float) -> void:
	#isCrouching = handleCrouch(delta, false, true)
	#
	#floor_snap_length = airSnapLength
	#
	#if hasJumped:
		#gravity_vec = (get_floor_normal() + Vector3.UP).normalized() * jump
		#hasJumped = false
	#else:
		#gravity_vec = Vector3.DOWN * gravity * delta
	#
	#move(delta, airAccel, airDrag)
#
	#
	#if is_on_floor() and !grappleHook.isLaunched():
		#if isCrouching and velocity.length() > startSlideThresh:
			#toSlide()
		#else:
			#changeState(MOVESTATES.GROUND)
			#hasLeftWallRun = false; hasRightWallRun = false
			#emit_signal("justLanded")
		#canJump = true
	#
	#if Input.is_action_just_pressed("jump"):
		#queueJump()
	#
	#if is_on_wall_only() and !grappleHook.isLaunched():
		#if wallrunPoint >= 1.0:
			#return
		#
		#var leftWall : bool = isWallRunningLeft(get_last_slide_collision().get_position())
		#if not ((leftWall and hasLeftWallRun) or (!leftWall and hasRightWallRun)):
			#wallrunPoint = 0.0
			#if leftWall:
				#hasLeftWallRun = true
				#hasRightWallRun = false
			#else:
				#hasLeftWallRun = false
				#hasRightWallRun = true
		#elif position.y > prevWallRunPoint.y:
			#return
		#
		#changeState(MOVESTATES.WALLRUNNING)
		#wallrunStartVel = velocity
#
#
#func slide(delta : float) -> void:
	#isCrouching = handleCrouch(delta, true)
	#if slideCurvePoint < 1.0:
		#slideCurvePoint += delta / slideDragTime
	#else:
		#slideCurvePoint = 1.0
	#
	#floor_snap_length = floorSnapLength
	#gravity_vec = Vector3.ZERO
	#
	#var isSlideDownward : bool = velocity.dot(get_floor_normal()) > 0
	#var angleCurveSamplePoint := get_floor_angle() / floor_max_angle if isSlideDownward else 0.0
	#
	#if isSlideDownward and velocity.length() < maxSlideSlopeSpeed:
		#applyForce(velocity.normalized() * delta * slideSlopeForce)
	#
	#var slideDrag : float = slideDragCurve.sample(slideCurvePoint) * slopeAngleDragCurve.sample(angleCurveSamplePoint)
	#
	#move(delta, slideAccel, slideDrag)
	#
	#if velocity.length() < endSlideSpeed:
		#changeState(MOVESTATES.GROUND)
		#slideCurvePoint = 0.0
	#
	#if groundToAir():
		#slideCurvePoint = 0.0
extends CharacterBody3D
#class_name PlayerCharacter

enum States {IDLE, WALK, RUN, CROUCH, SLIDE, JUMP, INAIR, ONWALL, DASH, GRAPPLE }
var current_state : States = States.IDLE

# == MOVEMENT variables ==
@export_group("Movement")
@export var walk_speed: float = 8
@export var run_speed: float = 16
@export var crouch_speed: float = 4
@export var slide_speed: float = 20
@export var dash_speed: float = 35
@export var grapple_speed: float = 35
@export var max_speed: float = 40

@export var walk_accel: float = 18
@export var run_accel: float = 24
@export var crouch_accel: float = 10
@export var air_accel: float = 7

@export var walk_decel: float = 10
@export var run_decel: float = 12
@export var crouch_decel: float = 7
@export var air_decel: float = 3

@export var slide_boost: float = 1.3
@export var max_slope_angle: float = 45

@export var move_speed_curve: Curve
@export var in_air_move_speed_curve: Curve

var move_velocity = Vector3.ZERO
var move_dir := Vector3.ZERO
var input_dir := Vector2.ZERO

# == JUMP variables ==
@export_group("Jump")
@export var jump_height: float = 2.5
@export var jump_time_to_peak: float = 0.24
@export var jump_time_to_fall: float = 0.32
@export var jump_cooldown: float = 0.13
@export var nb_jumps_in_air_allowed: int = 1
@export var coyote_time: float = 0.18
@export var jump_buffer_time: float = 0.15

var can_coyote := false
var coyote_timer := 0.0
var jump_buffer_timer := 0.0
var jumps_left: int

# == GRAVITY ==
@export_group("Gravity")
var jump_gravity: float
var fall_gravity: float
@export var wall_gravity_multiplier: float = 0.4

# == DASH variables ==
@export_group("Dash")
@export var dash_time: float = 0.14
@export var dash_cooldown: float = 0.4
@export var dashes_allowed: int = 1
var dash_timer := 0.0
var dash_count: int

# == SLIDE variables ==
@export_group("Slide")
@export var slide_time_max: float = 0.72
@export var slide_cooldown: float = 0.7
@export var slide_speed_addon: float = 7
var slide_timer: float = 0
var can_slide := true

# == GRAPPLE variables ==
@export_group("Grapple")
@export var grapple_max_dist: float = 25
@export var grapple_accel: float = 9
@export var dist_stop_grapple_ground: float = 1.8
@export var dist_stop_grapple_air: float = 1.6
@export var grapple_launch_velocity: float = 12
@export var grapple_cooldown: float = 1.2

var grapple_timer := 0.0
var grapple_active := false
var grapple_point := Vector3.ZERO

# == REFERENCES ==
@onready var camera_holder = $CameraHolder
@onready var stand_hitbox = $StandingHitbox
@onready var crouch_hitbox = $CrouchingHitbox
@onready var ceiling_check = $Raycasts/CeilingCheck
@onready var floor_check = $Raycasts/FloorCheck
@onready var grapple_check = $CameraHolder/Camera3D/GrappleHookCheck

@onready var mesh = $MeshInstance3D

func _ready():
	move_velocity = Vector3.ZERO
	jumps_left = nb_jumps_in_air_allowed
	dash_count = dashes_allowed

	jump_gravity = (-2.0 * jump_height) / (jump_time_to_peak * jump_time_to_peak)
	fall_gravity = (-2.0 * jump_height) / (jump_time_to_fall * jump_time_to_fall)

	#stand_hitbox.disabled = false
	#crouch_hitbox.disabled = true

func _process(_delta):
	update_movement_state()

func _physics_process(delta):
	get_input()
	update_state_logic(delta)
	move_and_slide()

func get_input():
	input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	move_dir = (camera_holder.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized() if input_dir.length() > 0 else Vector3.ZERO

func update_movement_state():
	if is_on_floor():
		if Input.is_action_pressed("crouch"):
			current_state = States.CROUCH
		elif input_dir.length() > 0.1 and Input.is_action_pressed("run"):
			current_state = States.RUN
		elif input_dir.length() > 0.1:
			current_state = States.WALK
		else:
			current_state = States.IDLE
	else:
		current_state = States.INAIR

func update_state_logic(delta):
	handle_coyote_and_jump_buffer(delta)
	handle_jump()
	handle_dash(delta)
	handle_slide(delta)
	handle_grapple(delta)
	update_velocity(delta)
	apply_gravity(delta)
	#apply_hitbox_scaling()

func handle_coyote_and_jump_buffer(delta):
	if is_on_floor():
		can_coyote = true
		coyote_timer = coyote_time
		jumps_left = nb_jumps_in_air_allowed
	else:
		if can_coyote:
			coyote_timer -= delta
			if coyote_timer <= 0:
				can_coyote = false
	if Input.is_action_just_pressed("jump"):
		jump_buffer_timer = jump_buffer_time
	else:
		jump_buffer_timer = max(0, jump_buffer_timer - delta)

func handle_jump():
	if (jump_buffer_timer > 0 and (is_on_floor() or can_coyote or jumps_left > 0)):
		move_velocity.y = sqrt(2.0 * -jump_gravity * jump_height)
		if not is_on_floor() and not can_coyote:
			jumps_left -= 1
		can_coyote = false
		jump_buffer_timer = 0

func apply_gravity(delta):
	if !is_on_floor():
		if move_velocity.y > 0:
			move_velocity.y += jump_gravity * delta
		else:
			move_velocity.y += fall_gravity * delta

func update_velocity(delta):
	var target_speed = get_target_speed()
	var cur_accel = get_acceleration()
	var cur_decel = get_deceleration()

	if move_dir.length() > 0.1:
		move_velocity.x = lerp(move_velocity.x, move_dir.x * target_speed, cur_accel * delta)
		move_velocity.z = lerp(move_velocity.z, move_dir.z * target_speed, cur_accel * delta)
	else:
		move_velocity.x = lerp(move_velocity.x, 0, cur_decel * delta)
		move_velocity.z = lerp(move_velocity.z, 0, cur_decel * delta)

	velocity = move_velocity

func get_target_speed():
	match current_state:
		States.WALK: return walk_speed
		States.RUN: return run_speed
		States.CROUCH: return crouch_speed
		States.SLIDE: return slide_speed
		States.DASH: return dash_speed
		States.GRAPPLE: return grapple_speed
		_: return walk_speed

func get_acceleration():
	match current_state:
		States.WALK: return walk_accel
		States.RUN: return run_accel
		States.CROUCH: return crouch_accel
		States.SLIDE: return run_accel
		States.DASH: return run_accel
		States.INAIR: return air_accel
		States.GRAPPLE: return run_accel
		_: return walk_accel

func get_deceleration():
	match current_state:
		States.WALK: return walk_decel
		States.RUN: return run_decel
		States.CROUCH: return crouch_decel
		States.SLIDE: return walk_decel
		States.DASH: return run_decel
		States.INAIR: return air_decel
		States.GRAPPLE: return 8
		_: return walk_decel

func handle_dash(delta):
	if Input.is_action_just_pressed("dash") and dash_count > 0 and dash_timer <= 0:
		current_state = States.DASH
		dash_timer = dash_time
		dash_count -= 1
	if current_state == States.DASH:
		dash_timer -= delta
		move_velocity = (camera_holder.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized() * dash_speed
		move_velocity.y = 0
		if dash_timer <= 0:
			current_state = States.INAIR

func handle_slide(delta):
	if Input.is_action_just_pressed("slide") and can_slide and is_on_floor() and velocity.length() > (run_speed * 0.8):
		current_state = States.SLIDE
		slide_timer = slide_time_max
		move_velocity = move_dir * (slide_speed + slide_speed_addon)
	if current_state == States.SLIDE:
		slide_timer -= delta
		if slide_timer <= 0 or (!Input.is_action_pressed("slide")):
			current_state = States.CROUCH
			slide_timer = 0
			move_velocity = move_dir * crouch_speed

func handle_grapple(delta):
	if Input.is_action_just_pressed("grapple") and grapple_check.is_colliding() and grapple_timer <= 0:
		current_state = States.GRAPPLE
		grapple_point = grapple_check.get_collision_point()
		grapple_active = true
		grapple_timer = grapple_cooldown

	if current_state == States.GRAPPLE and grapple_active:
		var dist = global_position.distance_to(grapple_point)
		var grapple_dir = global_position.direction_to(grapple_point)
		move_velocity = move_velocity.lerp(grapple_dir * grapple_speed, grapple_accel * delta)
		if (is_on_floor() and dist < dist_stop_grapple_ground) or (!is_on_floor() and dist < dist_stop_grapple_air) or Input.is_action_just_pressed("grapple"):
			grapple_active = false
			current_state = States.INAIR
			move_velocity.y = grapple_launch_velocity
		grapple_timer -= delta
	elif grapple_timer > 0:
		grapple_timer -= delta

#func apply_hitbox_scaling():
	#if current_state == States.CROUCH or current_state == States.SLIDE:
		#stand_hitbox.disabled = true
		#crouch_hitbox.disabled = false
		#mesh.scale.y = 0.7
	#else:
		#stand_hitbox.disabled = false
		#crouch_hitbox.disabled = true
		#mesh.scale.y = 1.0
