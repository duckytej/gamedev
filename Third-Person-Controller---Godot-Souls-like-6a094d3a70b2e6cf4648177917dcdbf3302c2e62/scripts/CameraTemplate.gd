extends Node3D

# Parent node of the visible character mesh. Used for the auto-follow camera.
@export var PlayerCharacterMesh: NodePath

@export_group("Vertical Limits")
@export var cam_v_max := 75.0   # degrees
@export var cam_v_min := -55.0  # degrees

@export_group("Sensitivity")
@export var h_sensitivity := 0.1  # degrees per pixel of mouse movement
@export var v_sensitivity := 0.1  # degrees per pixel of mouse movement
@export var joystick_sensitivity := 2.5  # radians per second at full stick

@export_group("Smoothing")
@export var h_acceleration := 10.0
@export var v_acceleration := 10.0
@export var follow_speed := 4.0
@export var follow_delay := 1.0  # seconds before the camera auto-follows again

# Camera rotation in radians (pitch and yaw).
var camrot_h := 0.0
var camrot_v := 0.0
var joyview := Vector2()

# Used only to scale the auto-follow speed; the controller's actual run speed
# lives on the player script.
const FOLLOW_REFERENCE_SPEED := 5.5

@onready var h: Node3D = get_node_or_null("h") as Node3D
@onready var v: Node3D = get_node_or_null("h/v") as Node3D
@onready var control_stay_delay: Timer = get_node_or_null("control_stay_delay") as Timer
@onready var player_mesh: Node3D = _get_exported_node(PlayerCharacterMesh) as Node3D


func _get_exported_node(path: NodePath) -> Node:
	if path.is_empty():
		return null
	return get_node_or_null(path)


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	if h != null:
		camrot_h = h.rotation.y
	if v != null:
		camrot_v = v.rotation.x

	if control_stay_delay != null:
		control_stay_delay.wait_time = follow_delay

	# PlayerTemplate.tscn does not ship with a mesh; it is assigned by the user.
	if player_mesh == null:
		push_warning("CameraTemplate: 'Player Character Mesh' is not assigned; auto-follow is disabled.")


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		_start_follow_delay()
		camrot_h -= deg_to_rad(event.relative.x * h_sensitivity)
		camrot_v += deg_to_rad(event.relative.y * v_sensitivity)


func _start_follow_delay() -> void:
	if control_stay_delay != null:
		control_stay_delay.start()


func _get_horizontal_speed() -> float:
	var body := get_parent()
	if body is CharacterBody3D:
		return Vector3(body.velocity.x, 0.0, body.velocity.z).length()
	return 0.0


func _joystick_input(delta: float) -> void:
	var x := Input.get_action_strength("lookleft") - Input.get_action_strength("lookright")
	var y := Input.get_action_strength("lookdown") - Input.get_action_strength("lookup")
	joyview = Vector2(x, y)

	if absf(joyview.x) > 0.01 or absf(joyview.y) > 0.01:
		_start_follow_delay()
		camrot_h += joyview.x * joystick_sensitivity * delta
		camrot_v += joyview.y * joystick_sensitivity * delta


func _physics_process(delta: float) -> void:
	_joystick_input(delta)

	camrot_v = clampf(camrot_v, deg_to_rad(cam_v_min), deg_to_rad(cam_v_max))

	var can_auto_follow := control_stay_delay == null or control_stay_delay.is_stopped()
	var speed := _get_horizontal_speed()

	if can_auto_follow and player_mesh != null and speed > 0.15:
		# Slowly place the camera behind the character while it is moving.
		var weight := clampf(
			delta * follow_speed * clampf(speed / FOLLOW_REFERENCE_SPEED, 0.25, 1.0),
			0.0,
			1.0
		)
		h.rotation.y = lerp_angle(h.rotation.y, player_mesh.global_rotation.y, weight)
		camrot_h = h.rotation.y
	else:
		# Mouse / gamepad camera.
		h.rotation.y = lerp_angle(h.rotation.y, camrot_h, clampf(delta * h_acceleration, 0.0, 1.0))

	v.rotation.x = lerp_angle(v.rotation.x, camrot_v, clampf(delta * v_acceleration, 0.0, 1.0))
