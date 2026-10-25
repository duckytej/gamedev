extends SceneTree

## Headless movement test: drives the player with simulated input and verifies
## state transitions, locomotion and stair stepping, without a renderer.
##
##   godot --headless --script res://misc/tests/movement_test.gd
##
## Exits non-zero on failure, so it can gate CI.

var _checks := 0
var _failures := 0

var _player: EyePlayer
var _visited := {}
var _max_y := -INF
var _max_slide_speed := 0.0
var _saw_slide_pose := false


func _initialize() -> void:
	_build()
	await _run()
	print("movement_test: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _build() -> void:
	_add_box(Vector3(60, 1, 60), Vector3(0, -0.5, 0))   # ground
	_add_box(Vector3(6, 0.5, 4), Vector3(0, 0.25, -4))   # 0.5 m step in front

	_player = (load("res://player/scenes/player.tscn") as PackedScene).instantiate()
	_player.position = Vector3(0, 0.2, 0)
	root.add_child(_player)


func _add_box(size: Vector3, at: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = at
	root.add_child(body)


func _run() -> void:
	await _frames(1)
	_player.state_machine.state_changed.connect(_on_state_changed)

	# Settle on the ground.
	await _frames(40)
	_check("starts idle", _player.state_machine.current_name == &"Idle")
	_check("is on the floor", _player.is_on_floor())

	# Normal movement is always at sprint speed (there is no sprint button).
	Input.action_press("move_forward")
	await _frames(30)
	_check("running by default", _player.state_machine.current_name == &"Run")
	_check("moved forward", _player.global_position.z < -0.5)

	# Continue over the step, tracking the highest point reached.
	_max_y = _player.global_position.y
	for i in 60:
		await physics_frame
		_max_y = maxf(_max_y, _player.global_position.y)
	Input.action_release("move_forward")
	await _frames(10)
	_check("climbed the step", _max_y >= 0.45)
	_check("did not get stuck", _player.global_position.z < -5.0)
	_check("never fell through the floor", _player.global_position.y > -0.5)

	# Jump.
	Input.action_press("jump")
	await _frames(3)
	Input.action_release("jump")
	await _frames(40)
	_check("jumped (visited Jump)", _visited.has(&"Jump"))
	_check("returned to the ground", _player.is_on_floor())
	_check("used the Land state", _visited.has(&"Land"))

	# Double jump, then keep holding to slam and chain into a slide.
	var stamina_before_slam := _player.vitals.stamina
	Input.action_press("move_forward")
	Input.action_press("jump")
	await _frames(3)
	Input.action_release("jump")
	await _frames(12)
	Input.action_press("jump")
	for _i in 90:
		await physics_frame
		if _player.state_machine.current_name == &"Slide":
			_max_slide_speed = maxf(_max_slide_speed, _player.get_horizontal_speed())
			_saw_slide_pose = _saw_slide_pose or _player.slide_pose_amount > 0.5
	Input.action_release("jump")
	Input.action_release("move_forward")
	_check("air-started jump hold triggers a slam", _visited.has(&"Slam"))
	_check("slam chains into a slide", _visited.has(&"Slide"))
	_check("slam-slide carries a strong burst",
		_max_slide_speed >= _player.config.slam_slide_speed)
	_check("slide compresses the body pose", _saw_slide_pose)
	_check("slamming and sliding costs no stamina",
		is_equal_approx(_player.vitals.stamina, stamina_before_slam))
	_check("slam and slide finish on the floor", _player.is_on_floor())

	# Let any last footstep playback finish before SceneTree quits, and give the
	# slide pose time to stand back up.
	await _frames(60)
	_check("slide pose restores after the slide", _player.slide_pose_amount < 0.05)


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _on_state_changed(_from: StringName, to: StringName) -> void:
	_visited[to] = true


func _check(label: String, condition: bool) -> void:
	_checks += 1
	if condition:
		print("  ok   ", label)
	else:
		_failures += 1
		printerr("  FAIL ", label)
		push_error("movement_test failed: " + label)
