extends CharacterBody3D
var ground_accel := 16
var max_ground_vel := 40
var air_accel := 6
var max_air_vel := 100
var friction := 2.9
var grav :float = 10
var jagain :=2
var coyote :=0.0
var buffer := 0.0
var sltime :=0.4
var decre :=0.4
var air_cap :=1.3
var sagain:=false

#var air_move=50
@onready var ene=preload("res://scenes/test.tscn")
@onready var head = $nek/head
@onready var cam = $nek/head/Camera3D
@onready var nek = $nek
@onready var wal = $RayCast3D
@onready var wal2 = $RayCast3D2
var bob_freq :=2
var bob_amp :=0.08
var t_bob := 0.0
@onready var pcap = $CollisionShape3D
const tocrouch := 7
var defaultH :=2
var crouchH :=0.7
var free :=false
const max_step :=0.5
var _snapped_to_stairs_last_frame :=false
var _last_frame_was_on_floor :=-INF
var on_floor :=false
var dist :=0.0
const grap_default_timer := 0
const grap_max_limit :int= 30
const slamfactor: =0.5
var slaming: =false
var vel: =0
var preslam=0
var dashtimer=1
const sounds := {'steps':preload("res://Sounds/Footsteps/Step_Concrete_01.wav") , 'jump':preload("res://Sounds/Jump_01.wav"),
'landing':preload("res://Sounds/Landing_02.wav"),'slide':preload("res://Sounds/Sliding_Loop.wav"),'wallrun':preload("res://Sounds/WallRun_0.wav")}
var prev_audio := 'steps'

func _process(_delta:float) -> void:
	if Input.is_action_pressed("quit"):
		get_tree().quit()

func action_sounds(ty:String,cont := false,_r1 := -0.5 ,_r2 :=1.5):
	# make audio proper
	if !%action_audio.playing: 
		%action_audio.stream = sounds[ty]
		if not cont:
			#%action_audio.pitch_scale += randf_range(r1,r2)
			if randf() <0.4:
				return
		%action_audio.play()
		prev_audio = ty


func too(normal):
	return normal.angle_to(Vector3.UP) > self.floor_max_angle

func clip(normal:Vector3,overbounce:float,_delta:float) -> void:
	var back := velocity.dot(normal)*overbounce/2
	if back>=0: return
	#var collision = move_and_collide(velocity * delta)
	var change:= normal*back
	self.velocity -=change
	var adjust:=self.velocity.dot(normal)
	if adjust<0.0:
		#print(adjust)
		self.velocity-=normal*adjust
	#move_and_slide_own()

func accelrate(accel_dir:Vector3,prev_vel:Vector3,accel:float,max_vel:int,delta:float) -> Vector3:
	var proj_vel = prev_vel.dot(accel_dir)
	#print(accel_dir)
	var accel_vel = accel*delta
	if proj_vel+accel_vel>max_vel:
		accel_vel=max_vel-proj_vel
	return prev_vel+accel_dir*accel_vel


func move_ground(accel_dir:Vector3,prev_vel:Vector3,delta:float) -> Vector3:
	var speed :float= prev_vel.length()
	if speed != 0:
		var drop =  speed*friction*delta
		prev_vel*=max(speed-drop,0) / speed
	return accelrate(accel_dir,prev_vel,ground_accel,max_ground_vel,delta)


func move_air(accel_dir:Vector3,prev_vel:Vector3,delta:float) -> void:#should have prob called accel func
	var air_move := 12
	var proj_vel :float= prev_vel.dot(accel_dir)
	var capped_speed :float= min((air_move * accel_dir).length(), air_cap)
	#print(capped_speed)
	var add_speed_till_cap := capped_speed - proj_vel
	var accel_vel := air_move*air_accel*delta
	if add_speed_till_cap>0:#either or neither
		#accel_vel=max_air_vel-proj_vel
		#accel_vel = min(accel_vel, add_speed_till_cap)
		velocity+= (accel_dir*accel_vel)
#
	#capped_speed = min((air_move_speed * wish_dir).length(), air_cap)
	#var add_speed_till_cap = capped_speed - cur_speed_in_wish_dir
	#if add_speed_till_cap > 0:
		#var accel_vel = air_accel * air_move_speed * delta # Usually is adding this one.
		#accel_vel = min(accel_vel, add_speed_till_cap)
		#self.velocity += accel_speed * wish_dir

	if is_on_wall():
		jagain=2
		coyote=0.1
		if  rad_to_deg(get_wall_normal().angle_to(Vector3.UP))<89:
			if too(get_wall_normal()):
				self.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
			else:
				self.motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
			clip(get_wall_normal(), 1, delta) # Allows surf
		else:
			grav=7-velocity.length()
			grav= clamp(grav,0.4,9.9)
			if accel_dir==Vector3(0,0,0):
				velocity+=Vector3(get_wall_normal().x,get_wall_normal().y,get_wall_normal().z)
			if grav < 1:
				action_sounds('wallrun')
			if Input.is_action_just_pressed("ui_accept"):
				buffer=0.1
				velocity+=Vector3(7*get_wall_normal().x,7*get_wall_normal().y,7*get_wall_normal().z)
			else:
				buffer-=delta
	#return accelrate(accel_dir,prev_vel,air_accel,max_air_vel,delta)



func _snap_down_to_stairs_check() -> void:
	var did_snap := false
	var floor_below : bool = %below.is_colliding() and not too(%below.get_collision_normal())
	var was_on_floor_last_frame := Engine.get_physics_frames() == _last_frame_was_on_floor
	if not is_on_floor() and velocity.y <= 0 and (was_on_floor_last_frame or _snapped_to_stairs_last_frame) and floor_below:
		var body_test_result := KinematicCollision3D.new()
		if self.test_move(self.global_transform, Vector3(0,-max_step,0), body_test_result):
			var translate_y := body_test_result.get_travel().y
			self.position.y += translate_y
			apply_floor_snap()
			did_snap = true
	_snapped_to_stairs_last_frame = did_snap

func _snap_up_stairs_check(delta:float) -> bool:
	if not is_on_floor() and not _snapped_to_stairs_last_frame: return false
	var expected_move_motion := self.velocity * Vector3(1,0,1) * delta
	var step_pos_with_clearance := self.global_transform.translated(expected_move_motion + Vector3(0, max_step * 2, 0))
	# Run a body_test_motion slightly above the pos we expect to move to, towards the floor.
	#  We give some clearance above to ensure there's ample room for the player.
	#  If it hits a step <= max_step, we can teleport the player on top of the step
	#  along with their intended motion forward.
	var down_check_result = KinematicCollision3D.new()
	if (self.test_move(step_pos_with_clearance, Vector3(0,-max_step*2,0), down_check_result)
	and (down_check_result.get_collider().is_class("StaticBody3D") or down_check_result.get_collider().is_class("CSGShape3D"))):
		var step_height = ((step_pos_with_clearance.origin + down_check_result.get_travel()) - self.global_position).y
		# Note I put the step_height <= 0.01 in just because I noticed it prevented some physics glitchiness
		# 0.02 was found with trial and error. Too much and sometimes get stuck on a stair. Too little and can jitter if running into a ceiling.
		# The normal character controller (both jolt & default) seems to be able to handled steps up of 0.1 anyway
		if step_height > max_step or step_height <= 0.01 or (down_check_result.get_position() - self.global_position).y > max_step: return false
		%ahead.global_position = down_check_result.get_position() + Vector3(0,max_step,0) + expected_move_motion.normalized() * 0.1
		%ahead.force_raycast_update()
		if %ahead.is_colliding() and not too(%ahead.get_collision_normal()):
			self.global_position = step_pos_with_clearance.origin + down_check_result.get_travel()
			apply_floor_snap()
			_snapped_to_stairs_last_frame = true
			return true
	return false

func graple(delta: float)-> void:
	if Input.is_action_just_pressed("grap"):
		grap_location = %grap.get_collision_point()
	dist = global_position.distance_to(grap_location)
	if dist < grap_max_limit:
		grap_line = line(global_position+Vector3(0,0.1,0),grap_location)
		get_tree().get_root().add_child(grap_line)
		grap_timer = grap_default_timer
		velocity+=(grap_location-global_position)*delta*(1/dist*2)*8.5
		grav=1.5

var grap_line = line(Vector3.ZERO,Vector3.ZERO)
var grap_timer := 5 # 5 -> ready ,0 -> free 
var grap_location :Vector3  = Vector3.ZERO
var enable_grap = false

func _physics_process(delta:float) -> void:
	dashtimer-=delta
	if grap_timer == 0:
		grap_line.queue_free()
		grap_timer = grap_default_timer+1
	elif grap_timer == grap_default_timer+1:
		if %grap.is_colliding()&&Input.is_action_pressed("grap"):
			# draw line when u grap and lookin at walla
			enable_grap = true
	else:
		grap_timer -= 1
	
	if enable_grap:
		graple(delta)
		if Input.is_action_just_released("grap"):
			enable_grap = false
	var input_dir := Input.get_vector("left", "right", "up", "down")
	var direction :Vector3= (head.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if is_on_floor() or _snapped_to_stairs_last_frame:
		_last_frame_was_on_floor=Engine.get_physics_frames()
		jagain=2
		coyote=0.2
		velocity = move_ground(direction,velocity,delta)
		if abs(input_dir.length()) >1:
			action_sounds('steps',false,-0.8,1.2)
	else:
		move_air(direction,velocity,delta)
		velocity.y-=grav*delta
		#velocity = move_air(direction,velocity,delta)
		if !is_on_wall():
			coyote-=delta
			grav=9.8
	if Input.is_action_just_pressed("ui_accept"):
		if jagain==1:
			velocity.y+= 8
			jagain-=1
		else:
			buffer=0.15
			
			
	else:
		buffer-=delta
	t_bob += delta* velocity.length() * float(is_on_floor())
	cam.transform.origin = headbob(t_bob)
	
	dash(delta)
	jump()
	generate()
	crouch(delta)
	if sltime>=0.4:
		sltime=0.4
	if Input.is_action_pressed("free"):
		free= true
	else:
		free= false
		nek.rotation.y=lerp(nek.rotation.y,0.0,delta*5)
		
	if not _snap_up_stairs_check(delta):
		move_and_slide()
		_snap_down_to_stairs_check()
	if Input.is_action_just_pressed("reset"):
		velocity = Vector3(0,0,0)
		position = Vector3(-0,1,-23)
		
#func final_cleanup(mesh_instance: MeshInstance3D, persist_ms: float):
	#get_tree().get_root().add_child(mesh_instance)
	#if persist_ms == 1:
		#await get_tree().physics_frame
		#mesh_instance.queue_free()
	#elif persist_ms > 0:
		#await get_tree().create_timer(persist_ms).timeout
		#mesh_instance.queue_free()
	#else:
		#return mesh_instance

func line(pos1: Vector3, pos2: Vector3, color := Color.WHITE_SMOKE, _persist_ms :float= 0):
	# it make line what else bruh
	var mesh_instance := MeshInstance3D.new()
	var immediate_mesh := ImmediateMesh.new()
	# use immediate mesh to make custon polygons , by defining collection of points
	var material := ORMMaterial3D.new()

	mesh_instance.mesh = immediate_mesh
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	immediate_mesh.surface_add_vertex(pos1)
	immediate_mesh.surface_add_vertex(pos2)
	immediate_mesh.surface_end()

	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color

	return mesh_instance


func crouch(delta:float) -> void:
	var floor_below : bool = %below.is_colliding() and not too(%below.get_collision_normal())
	if Input.is_action_just_pressed("crouch"):
		preslam= velocity.y
	if Input.is_action_pressed("crouch")==false&&is_on_floor():
		sagain=false
	if !is_on_floor()&&Input.is_action_pressed("crouch")&&coyote<0.1&&buffer<0.1:
		velocity.y-=100*delta
		vel=int(velocity.y)
		slaming=true
		if Input.is_action_just_pressed("ui_accept"):
			if jagain==1:
				velocity.y+= 8
				jagain-=1
	#if %below.is_colliding()&&Input.is_action_just_pressed("crouch"):
		#velocity*=(velocity.y)
		
		
	if Input.is_action_pressed("crouch"):
		pcap.shape.height-=tocrouch*delta
		if(velocity.length()<11-velocity.dot((get_floor_normal()))):
			ground_accel=10
			%action_audio.stop()
			if is_on_floor()&&slaming==true&&sagain==false:
				velocity.x*=1.3
				velocity.y*=1.3
				velocity.y+=get_floor_normal().y*slamfactor*vel*delta*-1*50
				slaming=false
				sagain=true
			#max_ground_vel=20
			friction=4.2
		elif sltime>0:
			cam.fov=80
			friction=0.2
			action_sounds("slide")
			sltime-=decre*delta
			jagain=2
			if is_on_floor():
				slaming=false
				coyote=0.1
			if Input.is_action_just_pressed("ui_accept"):#boost
				velocity.y+=3
				action_sounds("jump")
		if sltime<=0:
			#print("slow")
			cam.fov=75
			friction=4
			%action_audio.stop()
	elif Input.is_action_just_released("crouch")||sltime<0:
		ground_accel=16
		max_ground_vel=50
		cam.fov=75
		friction=2.5
		sltime=0.4
		%action_audio.stop()
		if !floor_below:
			velocity.y=preslam
		
	elif not is_on_ceiling():
		pcap.shape.height+=tocrouch*delta
	pcap.shape.height= clamp(pcap.shape.height,crouchH,defaultH)

func jump() -> void:
	if buffer>0.0&& coyote>0.0&&jagain>0:
		jagain-=1
		coyote = 0
		buffer = 0
		velocity.y+= 6
		action_sounds('jump')
		

func _input(event) -> void:
	if event.is_action_released("ui_accept"):
		if velocity.y>0.0:
			velocity.y*=0.5
			if is_on_wall_only():
				velocity.x*=0.5*get_wall_normal().x
				velocity.x*=0.5*get_wall_normal().y
				action_sounds('wallrun')

func _unhandled_input(event) -> void:
	if event is InputEventMouseMotion:
		if free:
			nek.rotate_y(-event.relative.x*.002)
			nek.rotation.y=clamp(nek.rotation.y,deg_to_rad(-115),deg_to_rad(115))
		else:
			head.rotate_y(-event.relative.x*.002)
		cam.rotate_x(-event.relative.y*.002)
		cam.rotation.x= clamp(cam.rotation.x,-PI/2,PI/2)

func _ready() -> void:
	Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	cam.current=true

func headbob(time) -> Vector3:
	var pos := Vector3.ZERO
	pos.y = sin(time* bob_freq) * bob_amp
	pos.x = cos(time* bob_freq / 2) * bob_amp
	return pos



func generate():
	var front=-head.transform.basis.z.normalized()
	if Input.is_action_just_pressed("spawn"):
		var e=ene.instantiate()
		e.global_transform.origin = self.position + front *3
		get_parent().add_child(e)
func dash(delta):
	#print(dashtimer)
	var speed = 1000+velocity.length()*10
	var g=-head.transform.basis.z.normalized()
	if Input.is_action_just_pressed("dash")&&dashtimer<0&&!is_on_floor():
		dashtimer=1.5
		var move=g*speed*delta
		velocity+=move
