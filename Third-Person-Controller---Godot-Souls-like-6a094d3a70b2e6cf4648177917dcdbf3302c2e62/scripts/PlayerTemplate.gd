extends CharacterBody3D

# Reference to the AnimationTree that drives the character. Select it in the
# inspector (kept with the original name so existing scenes keep working).
@export var PlayerAnimationTree: NodePath
# Any parent node of the visible character mesh. It is rotated to face movement.
@export var PlayerCharacterMesh: NodePath

@export_group("Movement")
@export var gravity := 19.6
@export var jump_force := 9.0
@export var walk_speed := 1.3
@export var run_speed := 5.5
@export var dash_power := 12.0
@export var acceleration := 15.0
@export var air_acceleration := 4.0
@export var angular_acceleration := 10.0

# Names of the states in the AnimationTree state machine. These are state
# names, not animation names; the state machine maps them to animations.
const ROLL_STATE := &"Roll"
const IDLE_STATE := &"Idle"
const WALK_STATE := &"Walk"
const RUN_STATE := &"Run"
const JUMP_STATE := &"Jump"
const ATTACK1_STATE := &"Attack1"
const ATTACK2_STATE := &"Attack2"
const ATTACK3_STATE := &"Attack3"
const BIG_ATTACK_STATE := &"BigAttack"

# State flags (also mirrored into the AnimationTree conditions)
var is_attacking := false
var is_rolling := false
var is_walking := false
var is_running := false

# Current one-shot action (attack/roll) driven by the script, if any.
var _action_state := &""
var _action_time_left := 0.0

# Physics values
var direction := Vector3.BACK
var horizontal_velocity := Vector3.ZERO
var vertical_velocity := Vector3.ZERO
var movement_speed := 0.0

@onready var animation_tree: AnimationTree = _get_exported_node(PlayerAnimationTree) as AnimationTree
@onready var player_mesh: Node3D = _get_exported_node(PlayerCharacterMesh) as Node3D
@onready var playback: AnimationNodeStateMachinePlayback = _get_playback()
@onready var camera_pivot: Node3D = get_node_or_null("Camroot/h") as Node3D


func _get_exported_node(path: NodePath) -> Node:
	if path.is_empty():
		return null
	return get_node_or_null(path)


func _get_playback() -> AnimationNodeStateMachinePlayback:
	if animation_tree == null or animation_tree.tree_root == null:
		return null
	return animation_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback


func _ready() -> void:
	direction = Vector3.BACK.rotated(Vector3.UP, _camera_yaw())


func _camera_yaw() -> float:
	if camera_pivot != null:
		return camera_pivot.global_rotation.y
	return global_rotation.y


func _is_state(state: StringName) -> bool:
	return playback != null and playback.get_current_node() == state


func _is_attack_state() -> bool:
	return (
		_action_state == ATTACK1_STATE
		or _action_state == ATTACK2_STATE
		or _action_state == ATTACK3_STATE
		or _action_state == BIG_ATTACK_STATE
	)


func _dash_direction() -> Vector3:
	# Use the current movement direction; if standing still, dash forward.
	if direction.length_squared() > 0.0001:
		return direction.normalized()
	if player_mesh != null:
		return player_mesh.global_transform.basis.z.normalized()
	return Vector3.BACK.rotated(Vector3.UP, _camera_yaw())


# Returns the length in seconds of the animation used by a state machine state.
func _state_duration(state: StringName) -> float:
	if animation_tree == null or animation_tree.tree_root == null:
		return 0.5
	var state_machine := animation_tree.tree_root as AnimationNodeStateMachine
	if state_machine == null or not state_machine.has_node(state):
		return 0.5
	var state_node := state_machine.get_node(state)
	if state_node is AnimationNodeAnimation:
		var anim_name := (state_node as AnimationNodeAnimation).animation
		var player := animation_tree.get_node_or_null(animation_tree.anim_player)
		if player is AnimationPlayer:
			var anim := (player as AnimationPlayer).get_animation(anim_name)
			if anim != null:
				return anim.length
	return 0.5


# One-shot actions (attacks and rolls) are driven explicitly by the script.
# The state machine's own "auto" transitions do not fire reliably for
# non-looping animations in Godot 4, so the script returns to Idle when the
# animation has finished playing.
func _start_action(state: StringName, dash: bool, snap: bool = false) -> void:
	if playback == null:
		return
	if snap:
		playback.start(state)
	elif not _is_state(state):
		playback.travel(state)
	_action_state = state
	_action_time_left = _state_duration(state)
	if dash:
		horizontal_velocity = _dash_direction() * dash_power


func _update_action(delta: float) -> void:
	if _action_state == &"":
		return
	_action_time_left -= delta
	if _action_time_left > 0.0:
		return
	_action_state = &""
	_action_time_left = 0.0
	if playback != null and not _is_state(IDLE_STATE):
		playback.travel(IDLE_STATE)


func _handle_actions() -> void:
	var attack_pressed := Input.is_action_just_pressed("attack")
	var roll_pressed := Input.is_action_just_pressed("roll")
	var jump_pressed := Input.is_action_just_pressed("jump")

	var action_taken := false

	# Dodge roll. "start" is used instead of "travel" so the roll begins
	# immediately instead of blending through the locomotion states.
	if roll_pressed and not _is_attack_state() and _action_state != ROLL_STATE and not _is_state(JUMP_STATE):
		_start_action(ROLL_STATE, true, true)
		action_taken = true

	# Attacks and combos.
	if attack_pressed and not action_taken:
		if _action_state == ROLL_STATE:
			# Special attack out of a roll.
			_start_action(BIG_ATTACK_STATE, true)
			action_taken = true
		elif _action_state == ATTACK1_STATE:
			_start_action(ATTACK2_STATE, false)
			action_taken = true
		elif _action_state == ATTACK2_STATE:
			_start_action(ATTACK3_STATE, false)
			action_taken = true
		elif _action_state == &"" and _is_state(RUN_STATE) and is_on_floor():
			# Sprinting attack: a longer attack with a forward dash.
			_start_action(BIG_ATTACK_STATE, true)
			action_taken = true
		elif _action_state == &"" and (_is_state(IDLE_STATE) or _is_state(WALK_STATE)) and is_on_floor():
			_start_action(ATTACK1_STATE, false)
			action_taken = true

	# Jump (cannot jump during an attack or a roll).
	if jump_pressed and is_on_floor() and not action_taken and not _is_attack_state() and _action_state != ROLL_STATE:
		vertical_velocity = Vector3.UP * jump_force
		action_taken = true


func _physics_process(delta: float) -> void:
	var on_floor := is_on_floor()

	# --- Input / actions -----------------------------------------------------
	_handle_actions()
	_update_action(delta)

	# --- State flags ---------------------------------------------------------
	is_attacking = _action_state == ATTACK1_STATE or _action_state == ATTACK2_STATE \
		or _action_state == ATTACK3_STATE or _action_state == BIG_ATTACK_STATE
	is_rolling = _action_state == ROLL_STATE

	# --- Gravity -------------------------------------------------------------
	if not on_floor:
		vertical_velocity += Vector3.DOWN * gravity * delta
	elif vertical_velocity.y <= 0.0:
		# A small downward velocity keeps the body glued to slopes and floors.
		# Do not clear a positive velocity, otherwise a jump started this frame
		# would be immediately cancelled.
		vertical_velocity = Vector3.DOWN * 0.5

	# --- Movement direction (camera relative) --------------------------------
	var move_input := Vector3(
		Input.get_action_strength("left") - Input.get_action_strength("right"),
		0.0,
		Input.get_action_strength("forward") - Input.get_action_strength("backward")
	)
	var has_move_input := move_input.length_squared() > 0.0001
	if has_move_input:
		direction = move_input.rotated(Vector3.UP, _camera_yaw()).normalized()
		is_walking = true
	else:
		is_walking = false

	is_running = is_walking and Input.is_action_pressed("sprint")

	movement_speed = 0.0
	if has_move_input and not is_attacking and not is_rolling:
		movement_speed = run_speed if is_running else walk_speed

	# --- Character facing ----------------------------------------------------
	if player_mesh != null:
		var target_yaw := player_mesh.rotation.y
		if has_move_input:
			if Input.is_action_pressed("aim"):
				# While aiming/strafe-walking, face the camera direction.
				target_yaw = _camera_yaw()
			else:
				target_yaw = atan2(direction.x, direction.z)
		player_mesh.rotation.y = lerp_angle(
			player_mesh.rotation.y,
			target_yaw,
			clampf(angular_acceleration * delta, 0.0, 1.0)
		)

	# --- Horizontal velocity -------------------------------------------------
	var target_velocity := Vector3.ZERO
	if not is_attacking and not is_rolling:
		if has_move_input:
			target_velocity = direction * movement_speed
		var accel := acceleration if on_floor else air_acceleration
		horizontal_velocity = horizontal_velocity.lerp(
			target_velocity,
			clampf(accel * delta, 0.0, 1.0)
		)
	else:
		# Attacks and rolls keep some momentum but quickly bleed it off.
		var friction := 3.0 if _is_state(BIG_ATTACK_STATE) else 2.0
		horizontal_velocity = horizontal_velocity.lerp(
			Vector3.ZERO,
			clampf(friction * delta, 0.0, 1.0)
		)

	# --- Move ----------------------------------------------------------------
	velocity = horizontal_velocity + vertical_velocity
	up_direction = Vector3.UP
	move_and_slide()

	# --- AnimationTree conditions -------------------------------------------
	if animation_tree != null:
		animation_tree.set("parameters/conditions/IsOnFloor", on_floor)
		animation_tree.set("parameters/conditions/IsInAir", not on_floor)
		animation_tree.set("parameters/conditions/IsWalking", is_walking and not is_running)
		animation_tree.set("parameters/conditions/IsNotWalking", not is_walking)
		animation_tree.set("parameters/conditions/IsRunning", is_running)
		animation_tree.set("parameters/conditions/IsNotRunning", not is_running)
		animation_tree.set("parameters/conditions/IsNotMoving", not is_walking)
