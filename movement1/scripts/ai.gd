extends CharacterBody3D
var ground_accel = 20
var max_ground_vel = 50
var air_accel = 5
var max_air_vel = 100
var accel = 10
var friction = 2.5
var grav= 9.8
var jagain=2
@onready var head = $head
#@onready var cam = $head/Camera3D
var bob_freq=2
var bob_amp=0.08
var t_bob = 0.0
@onready var ai_controller_3d = $AIController3D
@onready var target = $"../target"

func accelrate(accel_dir,prev_vel,accel,max_vel,delta):
	var proj_vel = prev_vel.dot(accel_dir)
	var accel_vel = accel*delta
	if proj_vel+accel_vel>max_vel:
		accel_vel=max_vel-proj_vel
	return prev_vel+accel_dir*accel_vel

func move_ground(accel_dir,prev_vel,delta):
	var speed = prev_vel.length()
	print(speed)
	if speed != 0:
		var drop =  speed*friction*delta
		prev_vel*=max(speed-drop,0) / speed
	return accelrate(accel_dir,prev_vel,ground_accel,max_ground_vel,delta)

func move_air(accel_dir,prev_vel,delta):
	return accelrate(accel_dir,prev_vel,air_accel,max_air_vel,delta)
	
func _physics_process(delta):
	var input_dir = Input.get_vector("left", "right", "up", "down")
	var direction = (head.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	#print(velocity)

	t_bob += delta* velocity.length() * float(is_on_floor())
	#cam.transform.origin = headbob(t_bob)
	if Input.is_action_just_pressed("ui_accept")&&jagain>0:
		velocity.y+= 7.5/jagain
		jagain-=1
	velocity.x=ai_controller_3d.move.x
	#velocity.y=ai_controller_3d.move.y
	velocity.z=ai_controller_3d.move.z
	if is_on_floor():
		jagain=2
		velocity = move_ground(direction,velocity,delta)
	else:
		velocity = move_air(direction,velocity,delta)
		velocity.y-=grav*delta
	
	move_and_slide()


#func _unhandled_input(event):
	#if event is InputEventMouseMotion:
		#head.rotate_y(-event.relative.x*.002)
		##cam.rotate_x(-event.relative.y*.002)
		##cam.rotation.x= clamp(cam.rotation.x,-PI/2,PI/2)

func _ready():
	pass
	#Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	#cam.current=true

func headbob(time):
	var pos = Vector3.ZERO
	pos.y = sin(time* bob_freq) * bob_amp
	pos.x = cos(time* bob_freq / 2) * bob_amp
	
	return pos


func _on_target_body_entered(body):
	position=Vector3(-2,3,269)
	ai_controller_3d.reward += 10


func _on_bad_body_entered(body):
	position=Vector3(-2,3,269)
	ai_controller_3d.reward -= 10
