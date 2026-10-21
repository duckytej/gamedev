extends  CharacterBody3D
class_name Player

@onready var nek: Node3D = $nek
@onready var right: RayCast3D = $RayCast3D
@onready var left: RayCast3D = $RayCast3D2
@onready var cam: Camera3D = $nek/Camera3D

@export var ground_accel:= 16
@export var fric:= 2
@export var max_gnd_vel=30
const grav=10
#crouch, slide, dash

@export var sl_fric:=1
var sliding =false

@export var max_vel=50
@export var air_accel=7
@export var air_move=10
@export var air_cap=1.2

var buffer:=0.0
var coyotte:=0.0
var wall_fric=0.9
var walling=false
var wn:=Vector3.ZERO

var bob_hz:=2
var bob_amp:=0.1
var t_bob := 0.0
var sens:=0.03
#fov variables
const BASE_FOV := 80
const FOV_CHANGE := 1.3
const origin:=Vector3(0,0,0)

var stamina:float=100
func _ready() -> void:
	Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	floor_snap_length=0.5
func _unhandled_input(event: InputEvent):
	if event is InputEventMouseMotion:
		nek.rotate_y(-event.relative.x * sens)
		cam.rotate_x(-event.relative.y * sens)
		cam.rotation.x = clamp(cam.rotation.x, deg_to_rad(-70), deg_to_rad(70))
func _headbob(delta,time) -> void:
	t_bob += delta * velocity.length() * float(is_on_floor())
	var pos = Vector3.ZERO
	pos.y = sin(time * bob_hz) * bob_amp
	pos.x = cos(time * bob_hz / 2) * bob_amp
	cam.transform.origin = origin+pos
	#fov
	var velocity_clamped :float= clamp(velocity.length(), 0.5, max_vel/2) 
	var target_fov :float= BASE_FOV + (FOV_CHANGE * velocity_clamped)
	cam.fov = lerp(cam.fov, target_fov, delta * 8)


func _physics_process(delta: float) -> void:
	var input_dir = Input.get_vector("left", "right", "up", "down")
	var dir = (nek.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	move(dir,velocity,delta)
	wallrun(delta)
	jump(dir,delta)
	move_and_slide()

func move(dir,prev_vel,delta)-> void:
	var speed :float= prev_vel.length()
	var capped_speed :float= min((air_move * dir).length(), air_cap)
	var tilt =dir.dot(get_floor_normal())
	#print("on_floor:", is_on_floor(), " vel.y:", velocity.y, " floor_normal:", get_floor_normal(), " speed:", (velocity.length()))
	if is_on_floor():
		if speed != 0:
			var friction := sl_fric if sliding else fric
			var drop :float=  speed*friction*delta
			prev_vel*=max(speed-drop,0) / speed
		velocity= accelrate(dir,prev_vel,ground_accel+tilt,max_gnd_vel,delta,1)
	else:
		var accel_vel :float= air_move*air_accel*delta
		var proj_vel :float= prev_vel.dot(dir)
		if capped_speed - proj_vel>0:
			velocity+= (dir*accel_vel)
	velocity.y-=grav*delta

func accelrate(accel_dir:Vector3,prev_vel:Vector3,accel:float,max_v:int,delta:float,move_vel:int) -> Vector3:
	var proj_vel = prev_vel.dot(accel_dir)
	var accel_vel = move_vel*accel*delta
	if proj_vel+accel_vel>max_v:
		accel_vel=max_v-proj_vel
	return prev_vel+accel_dir*accel_vel
#v^2=u^2+2as
func jump(dir,delta) -> void:
	#print(walling)
	if is_on_floor():
		coyotte=0.2
	else:
		coyotte-=delta

	if Input.is_action_just_released("jump") and velocity.y>0.0:
		velocity.y*=0.5

	if Input.is_action_just_pressed("jump"):
		buffer=0.15
		if walling:
			velocity.y+=500*delta
			velocity+=300*wn*delta #wall bounce/jump
			
	else:
		buffer-=delta
	if (buffer>0&&coyotte>0):
		velocity.y+=50*delta
		
func wallrun(delta):
	#print(walling)
	if !is_on_floor() and (left.is_colliding() or right.is_colliding()):
		walling=true
		if left.is_colliding():
			wn=left.get_collision_normal()
		else:
			wn=right.get_collision_normal()
	else:
		walling=false
		wn=Vector3.ZERO
	if walling:
		wall_fric-=clamp(velocity.length(),-0.1,0.1)
		velocity.y*=wall_fric
			
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
