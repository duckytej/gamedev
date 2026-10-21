class_name Player
extends CharacterBody3D

enum State { IDLE, WALK, RUN, JUMP, FALL }

const WALK_SPEED := 6.5
const RUN_SPEED := 14.0
const JUMP_VELOCITY := 20.0
const ACCELERATION := 18.0
const FRICTION := 14.0
const AIR_CONTROL := 0.45
const MOUSE_SENSITIVITY := 0.002
const COYOTE_TIME := 0.12
const JUMP_BUFFER := 0.15

var _current_state: State = State.IDLE
var _gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity"))
var _coyote := 0.0
var _jump_buffer := 0.0
var _camera: Camera3D
var _yaw := 0.0
var _pitch := 0.0
var _state_label: Label
var _pos_label: Label


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_setup_camera()
	_setup_body()
	_setup_ui()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_yaw -= event.relative.x * MOUSE_SENSITIVITY
		_pitch -= event.relative.y * MOUSE_SENSITIVITY
		_pitch = clampf(_pitch, -1.4, 1.4)
		rotation.y = _yaw
		_camera.rotation.x = _pitch

	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _setup_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "Camera"
	_camera.position = Vector3(0, 1.6, 0)
	_camera.far = 300
	add_child(_camera)


func _setup_body() -> void:
	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 1.8
	col.shape = shape
	col.position = Vector3(0, 0.9, 0)
	add_child(col)

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "BodyMesh"
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.3
	capsule.height = 1.8
	mesh_inst.mesh = capsule
	mesh_inst.position = Vector3(0, 0.9, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.2, 0.25)
	mat.roughness = 0.7
	mat.metallic = 0.3
	mesh_inst.material_override = mat
	add_child(mesh_inst)


func _setup_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	_state_label = Label.new()
	_state_label.position = Vector2(20, 20)
	_state_label.add_theme_font_size_override("font_size", 16)
	_state_label.add_theme_color_override("font_color", Color(0.0, 0.9, 1.0))
	_state_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	_state_label.add_theme_constant_override("shadow_offset_x", 1)
	_state_label.add_theme_constant_override("shadow_offset_y", 1)
	canvas.add_child(_state_label)

	_pos_label = Label.new()
	_pos_label.position = Vector2(20, 44)
	_pos_label.add_theme_font_size_override("font_size", 13)
	_pos_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	_pos_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	_pos_label.add_theme_constant_override("shadow_offset_x", 1)
	_pos_label.add_theme_constant_override("shadow_offset_y", 1)
	canvas.add_child(_pos_label)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta

	_coyote = COYOTE_TIME if is_on_floor() else _coyote - delta
	if Input.is_action_just_pressed("jump"):
		_jump_buffer = JUMP_BUFFER
	else:
		_jump_buffer -= delta

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	var desired_speed := RUN_SPEED if Input.is_action_pressed("sprint") else WALK_SPEED
	var accel := ACCELERATION if is_on_floor() else ACCELERATION * AIR_CONTROL

	if direction.length() > 0:
		velocity.x = move_toward(velocity.x, direction.x * desired_speed, accel * delta)
		velocity.z = move_toward(velocity.z, direction.z * desired_speed, accel * delta)
	else:
		velocity.x = move_toward(velocity.x, 0, FRICTION * delta)
		velocity.z = move_toward(velocity.z, 0, FRICTION * delta)

	if _jump_buffer > 0.0 and _coyote > 0.0:
		velocity.y = JUMP_VELOCITY
		_jump_buffer = 0.0
		_coyote = 0.0

	move_and_slide()

	_update_state(direction)
	_state_label.text = "State: %s" % State.keys()[_current_state]
	_pos_label.text = "Pos: (%d, %d, %d)" % [int(global_position.x), int(global_position.y), int(global_position.z)]


func _update_state(direction: Vector3) -> void:
	if not is_on_floor():
		_current_state = State.FALL if velocity.y < 0 else State.JUMP
	elif direction.length() > 0:
		_current_state = State.RUN if Input.is_action_pressed("sprint") else State.WALK
	else:
		_current_state = State.IDLE
