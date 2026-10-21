extends Node

## Headless smoke test runner: boots alongside autoloads, instantiates the
## real main scene, pokes major systems (state machine, combat, enemies),
## prints PASS/FAIL per check, then quits with exit code.
## Run: godot --headless res://tests/test_runner.tscn


var _failures: Array[String] = []
var _checks: int = 0


func _ready() -> void:
	_run()


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failures.append(label)
		print("  FAIL: ", label)


func _run() -> void:
	print("=== NEONRUINS SMOKE TEST ===")

	var scene: PackedScene = load("res://scenes/main.tscn")
	_check(scene != null, "main.tscn loads")
	if scene == null:
		return _finish()

	var main := scene.instantiate()
	add_child(main)

	# Wait for deferred city generation + player spawn
	for i in range(30):
		await get_tree().physics_frame

	var world := main.get_node_or_null("City")
	_check(world != null, "City node exists")
	var buildings = world.get("building_data") if world else null
	_check(buildings != null and buildings.size() > 50,
			"buildings generated (%s)" % [buildings.size() if buildings != null else -1])

	var enemy_count_spawned: int = 0
	for child in world.get_children() if world else []:
		if child is Enemy:
			enemy_count_spawned += 1
	_check(enemy_count_spawned > 0, "enemies spawned (%d)" % enemy_count_spawned)

	var player := Globals.local_player as Player
	_check(player != null, "local player spawned")
	if player == null:
		return _finish()

	_check(is_instance_valid(player.current_state), "state machine initialized (%s)" % player.current_state.name)
	_check(player.ranged_system != null and player.ranged_system.weapon != null,
			"ranged system has weapon (%s)" % [player.ranged_system.weapon.resource_name])
	_check(player.ranged_system.ammo_current > 0, "ammo initialized (%d/%d)"
			% [player.ranged_system.ammo_current, player.ranged_system.weapon.ammo_max])

	# --- State machine via simulated input ---
	for i in range(60):
		await get_tree().physics_frame
		if player.current_state.name != "InAir":
			break

	Input.action_press("move_forward")
	for i in range(4):
		await get_tree().physics_frame
	_check(player.current_state.name == "Walk", "input moves Idle -> Walk (got %s)" % player.current_state.name)

	Input.action_press("crouch")
	for i in range(4):
		await get_tree().physics_frame
	_check(player.current_state.name == "Crouch", "crouch input enters Crouch (got %s)" % player.current_state.name)
	_check(not player.is_standing(), "crouch shrinks collider")

	Input.action_release("crouch")
	for i in range(6):
		await get_tree().physics_frame
	_check(player.current_state.name != "Crouch", "releasing crouch exits Crouch (got %s)" % player.current_state.name)
	_check(player.is_standing(), "collider restored after standing up")

	Input.action_press("dash")
	for i in range(4):
		await get_tree().physics_frame
		if player.current_state.name == "Dash":
			break
	_check(player.current_state.name == "Dash", "dash triggers while grounded (state=%s)" % player.current_state.name)

	Input.action_release("dash")
	Input.action_release("move_forward")
	for i in range(40):
		await get_tree().physics_frame
		if player.current_state.name != "Dash":
			break

	# --- Ranged system ---
	var rs := player.ranged_system
	var ammo_before: int = rs.ammo_current
	rs.try_fire()
	await get_tree().physics_frame
	_check(rs.ammo_current < ammo_before, "firing consumes ammo (%d -> %d)" % [ammo_before, rs.ammo_current])

	# --- Enemy lifecycle ---
	var enemy_scene: PackedScene = load("res://enemies/enemy.tscn")
	_check(enemy_scene != null, "enemy.tscn loads")
	if enemy_scene == null:
		return _finish()

	var enemy: Enemy = enemy_scene.instantiate()
	world.add_child(enemy)
	enemy.enemy_type = Enemy.EnemyType.GRUNT
	enemy.global_position = player.global_position + Vector3(4, 1, 4)
	Globals.register_enemy(enemy)
	for i in range(3):
		await get_tree().physics_frame

	# Track deaths from the start (enemy may die during the poise loop)
	var death_count: Array[int] = [0]
	var cb := func(_e: Node) -> void: death_count[0] += 1
	SignalBus.entity_died.connect(cb)

	_check(is_instance_valid(enemy) and not enemy.is_queued_for_deletion(), "test enemy alive")
	_check(enemy.health_component.current_health > 0.0, "enemy has health (%.0f)" % enemy.health_component.current_health)

	var hp_before: float = enemy.health_component.current_health
	enemy.hurtbox.take_damage(20.0, player, Vector3(2, 0, 0))
	await get_tree().physics_frame
	if is_instance_valid(enemy):
		_check(enemy.health_component.current_health < hp_before, "enemy takes damage")

	# Poise break via repeated hits
	for i in range(6):
		if not is_instance_valid(enemy) or enemy.current_state == Enemy.EnemyState.DEAD:
			break
		enemy.hurtbox.take_damage(15.0, player, Vector3.ZERO)
		await get_tree().physics_frame

	_check(death_count[0] > 0 or (is_instance_valid(enemy)
			and (enemy.is_staggered or enemy.current_state == Enemy.EnemyState.DEAD)),
			"repeated hits stagger or kill enemy")

	# Force the kill if it only staggered, so the death flow is exercised
	if is_instance_valid(enemy) and enemy.current_state != Enemy.EnemyState.DEAD:
		# Wait out any invincibility frames first
		for i in range(60):
			if not enemy.health_component.is_invincible:
				break
			await get_tree().physics_frame
		if is_instance_valid(enemy):
			enemy.health_component.take_damage(9999.0, player)
			for i in range(3):
				await get_tree().physics_frame

	SignalBus.entity_died.disconnect(cb)
	_check(death_count[0] > 0, "entity_died emitted on enemy kill")

	# --- Player hurt flow ---
	var php_before: float = player.health_component.current_health
	player.hurtbox.take_damage(10.0, null, Vector3(1, 0, 0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(player.health_component.current_health < php_before, "player takes damage")

	_finish()


func _finish() -> void:
	print("")
	if _failures.is_empty():
		print("ALL %d CHECKS PASSED" % _checks)
	else:
		print("%d/%d CHECKS FAILED:" % [_failures.size(), _checks])
		for f in _failures:
			print("  - ", f)
	get_tree().quit(0 if _failures.is_empty() else 1)
