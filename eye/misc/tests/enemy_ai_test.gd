extends SceneTree

## Headless test for the time-sliced enemy director, movement, shooting and the
## AI toggle. Enemies deliberately stay static until a director exists.
##
##   godot --headless --script res://misc/tests/enemy_ai_test.gd

const PLAYER_SCENE := preload("res://player/scenes/player.tscn")
const ENEMY_SCENE := preload("res://enemies/enemy_cube.tscn")

var _checks := 0
var _failures := 0

var _arena: Node3D
var _player: EyePlayer
var _director: EnemyDirector
var _enemies: Array[EnemyCube] = []


func _initialize() -> void:
	_build()
	await _run()
	print("enemy_ai_test: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _build() -> void:
	_arena = Node3D.new()
	_arena.name = "Arena"
	root.add_child(_arena)
	_add_box(Vector3(80, 1, 80), Vector3(0, -0.5, 0))

	_player = PLAYER_SCENE.instantiate() as EyePlayer
	_player.position = Vector3(0, 0.2, 0)
	_arena.add_child(_player)


func _run() -> void:
	await _frames(30)
	_check("player vitals are available", _player.vitals != null)

	# --- No director: no thinking, no movement, no shooting -------------------
	var static_enemy := _spawn_enemy(Vector3(0, 0.9, -4))
	await _frames(30)
	var static_position := static_enemy.global_position
	_check("enemy is static without a director", static_enemy.think_count == 0)
	_check("enemy does not shoot without a director", static_enemy.shots_fired == 0)
	_check("enemy position is stable without a director",
		static_enemy.global_position.distance_to(static_position) < 0.05)
	_check("player takes no damage without a director",
		is_equal_approx(_player.vitals.current_health, _player.config.player_max_health))

	# --- Director: registration, movement, shooting ---------------------------
	_director = EnemyDirector.new()
	_director.name = "EnemyDirector"
	_director.config = _player.config
	_arena.add_child(_director)
	var mover := _spawn_enemy(Vector3(0, 0.9, -12))
	var waiter := _spawn_enemy(Vector3(6, 0.9, -5))
	await _frames(4)

	_check("director sees the configured AI state", _director.ai_enabled)
	_check("director registered all enemies", _director.get_enemy_count() == 3)
	_check("director update budget is one by default",
		_player.config.enemy_ai_max_updates_per_tick == 1)
	_check("toggle action is bound", InputMap.has_action(&"toggle_enemy_ai"))

	var start_z := mover.global_position.z
	var start_health := _player.vitals.current_health
	var budget_ok := true
	var ticks_with_updates := 0
	var previous_total := _total_think_count()

	for _i in 90:
		await physics_frame
		if _director.last_tick_updates > _player.config.enemy_ai_max_updates_per_tick:
			budget_ok = false
		if _director.last_tick_updates > 0:
			ticks_with_updates += 1

	_check("director never exceeds its per-tick budget", budget_ok)
	_check("director spreads thinking over many ticks", ticks_with_updates > 20)
	_check("director actually dispatched brain updates",
		_total_think_count() > previous_total + 5)
	_check("every enemy gets a brain turn",
		static_enemy.think_count > 0 and mover.think_count > 0 and waiter.think_count > 0)
	_check("distant enemy moves toward the player",
		mover.global_position.z > start_z + 0.5)
	_check("enemy shoots the player", static_enemy.shots_fired > 0)
	_check("enemy shots hurt the player", _player.vitals.current_health < start_health)

	# --- AI off: no thoughts, no new shots ------------------------------------
	_toggle_with_action()
	await _frames(2)
	_check("toggle turns AI off", not _director.ai_enabled)
	var count_at_pause := _total_think_count()
	var shots_at_pause := _total_shot_count()
	await _frames(30)
	_check("paused AI dispatches no thoughts", _total_think_count() == count_at_pause)
	_check("paused AI fires no shots", _total_shot_count() == shots_at_pause)

	# --- AI on: updates resume ------------------------------------------------
	_toggle_with_action()
	await _frames(2)
	_check("toggle turns AI back on", _director.ai_enabled)
	var count_at_resume := _total_think_count()
	await _frames(30)
	_check("resumed AI dispatches thoughts again", _total_think_count() > count_at_resume)

	await _frames(2)


func _spawn_enemy(at: Vector3) -> EnemyCube:
	var enemy := ENEMY_SCENE.instantiate() as EnemyCube
	enemy.position = at
	_arena.add_child(enemy)
	_enemies.append(enemy)
	return enemy


func _toggle_with_action() -> void:
	var event := InputEventAction.new()
	event.action = &"toggle_enemy_ai"
	event.pressed = true
	_director._unhandled_input(event)


func _total_think_count() -> int:
	var total := 0
	for enemy in _enemies:
		if is_instance_valid(enemy):
			total += enemy.think_count
	return total


func _total_shot_count() -> int:
	var total := 0
	for enemy in _enemies:
		if is_instance_valid(enemy):
			total += enemy.shots_fired
	return total


func _add_box(size: Vector3, at: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = at
	_arena.add_child(body)


func _frames(count: int) -> void:
	for _i in count:
		await physics_frame


func _check(label: String, condition: bool) -> void:
	_checks += 1
	if condition:
		print("  ok   ", label)
	else:
		_failures += 1
		printerr("  FAIL ", label)
		push_error("enemy_ai_test failed: " + label)
