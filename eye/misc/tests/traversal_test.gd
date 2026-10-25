extends SceneTree

## Headless traversal test for the Titanfall-style additions: wall running,
## wall jumping and the optional grapple ability. This drives real input through
## the state machine, so it exercises sensing, state entry and momentum rules.
##
##   godot --headless --script res://misc/tests/traversal_test.gd

const PLAYER_SCENE := preload("res://player/scenes/player.tscn")

var _checks := 0
var _failures := 0

var _arena: Node3D
var _player: EyePlayer
var _visited := {}
var _jump_count := 0


func _initialize() -> void:
	_build()
	await _run()
	print("traversal_test: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _build() -> void:
	_arena = Node3D.new()
	_arena.name = "Arena"
	root.add_child(_arena)
	_add_box(Vector3(60, 1, 60), Vector3(0, -0.5, 0))
	# Tall wall on the right for wall running (left face at x = 1.75).
	_add_box(Vector3(0.5, 8, 30), Vector3(2.0, 4.0, 0))
	# Grapple target straight ahead, far enough downrange that the wall-run
	# landing lane never touches it (front face at z = -13.5).
	_add_box(Vector3(4.0, 5.0, 1.0), Vector3(0, 2.5, -14.0))

	_player = PLAYER_SCENE.instantiate() as EyePlayer
	_player.position = Vector3(1.15, 0.2, 6.0)
	_arena.add_child(_player)


func _add_box(size: Vector3, at: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = at
	_arena.add_child(body)


func _run() -> void:
	await _frames(2)
	_player.state_machine.state_changed.connect(_on_state_changed)
	await _frames(30)
	_check("starts grounded", _player.is_on_floor())

	# --- Wall run ------------------------------------------------------------
	Input.action_press("move_forward")
	Input.action_press("move_right")
	await _frames(24)
	Input.action_press("jump")
	await _frames(2)
	Input.action_release("jump")

	var wall_run_started := await _wait_for_state(&"WallRun", 60)
	_check("wall run starts from a jump beside a wall", wall_run_started)
	if wall_run_started:
		var start_jumps := _jump_count
		var y_before := _player.global_position.y
		var entry_speed := _player.get_horizontal_speed()
		_check("wall run entry exceeds sprint speed",
			entry_speed > _player.config.sprint_speed)
		await _frames(22)
		_check("wall run stays off the floor", _player.global_position.y > y_before - 1.0)
		_check("wall run bleeds speed while held",
			_player.get_horizontal_speed() < entry_speed)
		_check("wall run implants a camera roll", not is_zero_approx(_player.wall_roll_target))

		Input.action_press("jump")
		await _frames(2)
		Input.action_release("jump")
		_check("wall jump transitions to Jump", _jump_count > start_jumps)
		_check("wall jump pushes away from the wall", _player.velocity.x < -0.5)
		_check("wall jump boosts horizontal speed",
			_player.get_horizontal_speed() > _player.config.sprint_speed)
		_release_all()
		await _frames(100)
		_check("wall jump returns to the floor", _player.is_on_floor())

	_release_all()

	# --- Probe orientation ---------------------------------------------------
	# Facing +Z puts the +X wall on screen-left. This catches world-axis probes
	# that would only work while the camera faces -Z.
	_player.global_position = Vector3(1.15, 0.2, 6.0)
	_player.velocity = Vector3.ZERO
	_player.set_view_angles(PI, 0.0)
	await _frames(3)
	var wall_sense := _player.get_wall_sense()
	_check("wall probes follow view yaw (left wall found)",
		wall_sense != null and not wall_sense.get_wall(-1).is_empty())
	_check("wall probes follow view yaw (right wall empty)",
		wall_sense != null and wall_sense.get_wall(1).is_empty())
	_player.set_view_angles(0.0, 0.0)

	# --- Grapple -------------------------------------------------------------
	_player.global_position = Vector3(0.0, 0.2, 0.0)
	_player.velocity = Vector3.ZERO
	await _frames(20)
	_check("left the wall behind", _player.state_machine.current_name == &"Idle")

	var grapple := _player.get_grapple()
	_check("grapple ability is installed", grapple != null)
	if grapple != null:
		var start_z := _player.global_position.z
		var stamina_before_grapple := _player.vitals.stamina
		Input.action_press("grapple")
		await _frames(3)
		_check("grapple state entered", _player.state_machine.current_name == &"Grapple")
		_check("grapple is attached", grapple.is_attached())
		_check("grapple spend is charged once on attach",
			is_equal_approx(
				_player.vitals.stamina,
				stamina_before_grapple - _player.config.grapple_stamina_cost
			))
		var stamina_after_attach := _player.vitals.stamina
		await _frames(18)
		_check("grapple does not drain stamina while attached",
			is_equal_approx(_player.vitals.stamina, stamina_after_attach))
		_check("grapple pulls toward the anchor", _player.global_position.z < start_z - 0.4)
		var rope := _arena.get_node_or_null("GrappleRope") as MeshInstance3D
		_check("grapple rope is drawn", rope != null and rope.visible)

		Input.action_release("grapple")
		await _frames(4)
		_check("releasing grapple detaches", not grapple.is_attached())

	# --- Optional-ability removal --------------------------------------------
	# Removing the grapple node must not break the player or its states.
	var grapple_node := _player.abilities.get_node_or_null("Grapple")
	_check("grapple node is optional/removable", grapple_node != null)
	if grapple_node != null:
		grapple_node.queue_free()
		await _frames(3)
		_check("player survives without the grapple ability",
			_player.get_grapple() == null and _player.state_machine.current != null)
		_check("removing grapple cleans up its visuals",
			_arena.get_node_or_null("GrappleRope") == null
			and _arena.get_node_or_null("GrappleAnchor") == null)

	# Let any last footstep playback finish before SceneTree quits.
	await _frames(60)


func _wait_for_state(state: StringName, max_frames: int) -> bool:
	for _i in max_frames:
		if _player.state_machine.current_name == state:
			return true
		await physics_frame
	return false


func _release_all() -> void:
	for action in ["move_forward", "move_back", "move_left", "move_right", "jump", "grapple"]:
		if Input.is_action_pressed(action):
			Input.action_release(action)


func _frames(count: int) -> void:
	for _i in count:
		await physics_frame


func _on_state_changed(_from: StringName, to: StringName) -> void:
	_visited[to] = true
	if to == &"Jump":
		_jump_count += 1


func _check(label: String, condition: bool) -> void:
	_checks += 1
	if condition:
		print("  ok   ", label)
	else:
		_failures += 1
		printerr("  FAIL ", label)
		push_error("traversal_test failed: " + label)
