extends SceneTree

## Headless test for player health, stamina, overhealth and the stagger burst.
##
##   godot --headless --script res://misc/tests/vitals_test.gd

const PLAYER_SCENE := preload("res://player/scenes/player.tscn")
const ENEMY_SCENE := preload("res://enemies/enemy_cube.tscn")

var _checks := 0
var _failures := 0

var _arena: Node3D
var _player: EyePlayer
var _enemy: EnemyCube
var _enemy_health: HealthComponent


func _initialize() -> void:
	_build()
	await _run()
	print("vitals_test: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _build() -> void:
	_arena = Node3D.new()
	_arena.name = "Arena"
	root.add_child(_arena)
	_add_box(Vector3(40, 1, 40), Vector3(0, -0.5, 0))

	_player = PLAYER_SCENE.instantiate() as EyePlayer
	_player.position = Vector3(0, 0.2, 0)
	_arena.add_child(_player)


func _run() -> void:
	await _frames(30)
	_check("vitals are installed", _player.vitals != null)
	if _player.vitals == null:
		return
	var vitals := _player.vitals

	_check("health starts at 100", is_equal_approx(vitals.current_health, 100.0))
	_check("stamina starts at 100", is_equal_approx(vitals.stamina, 100.0))
	_check("overhealth starts empty", is_equal_approx(vitals.overhealth, 0.0))

	# Running is free: only explicit actions may spend stamina.
	var stamina_before_run := vitals.stamina
	Input.action_press("move_forward")
	await _frames(20)
	Input.action_release("move_forward")
	_check("running costs no stamina", is_equal_approx(vitals.stamina, stamina_before_run))

	# Dash is an explicit action and spends its configured cost.
	Input.action_press("dash")
	await _frames(2)
	Input.action_release("dash")
	await _frames(2)
	_check("dash spends stamina",
		is_equal_approx(vitals.stamina, 100.0 - _player.config.dash_stamina_cost))
	_check("dash is still the active state",
		_player.state_machine.current_name == &"Dash")

	# Return to the arena origin so the pistol has a target ahead of it.
	_player.global_position = Vector3(0, 0.2, 0)
	_player.velocity = Vector3.ZERO
	await _frames(3)

	# A pistol shot spends stamina and credits its applied damage as overhealth.
	await _spawn_enemy(Vector3(0, 0.9, -4))
	var stamina_before_shot := vitals.stamina
	Input.action_press("fire")
	await _frames(1)
	Input.action_release("fire")
	await _frames(4)
	_check("firing spends stamina",
		vitals.stamina <= stamina_before_shot - _player.config.pistol_stamina_cost + 0.01)
	_check("damaging an enemy fills overhealth",
		is_equal_approx(vitals.overhealth, _player.config.pistol_damage))

	# Overhealth is damage absorption, not extra health.
	var health_before_hit := vitals.current_health
	var overhealth_before_hit := vitals.overhealth
	vitals.take_damage(20.0, null)
	_check("overhealth absorbs damage first",
		is_zero_approx(vitals.overhealth)
		and is_equal_approx(
			vitals.current_health, health_before_hit - (20.0 - overhealth_before_hit)
		))

	# The burst needs *more* than half, then spends the entire buffer.
	vitals.add_overhealth(vitals.max_overhealth * 0.5 - vitals.overhealth)
	_check("exactly half overhealth cannot burst", not vitals.can_burst())
	var burst := _player.get_node("Abilities/OverhealthBurst") as OverhealthBurst
	_check("burst rejects an under-threshold buffer", not burst.trigger())
	vitals.add_overhealth(10.0)
	_check("over half overhealth can burst", vitals.can_burst())

	var pistol := _player.get_weapons().get_pistol()
	var sniper := _player.get_weapons().get_sniper()
	pistol.ammo = 1
	pistol.begin_reload()
	sniper.ammo = 2
	var enemy_health_before := _enemy_health.current_health
	var burst_overhealth := vitals.overhealth
	_check("burst trigger succeeds", burst.trigger())
	_check("burst spends the whole buffer", is_zero_approx(vitals.overhealth))
	_check("burst cancels reload and refills the pistol",
		not pistol.is_reloading() and pistol.ammo == pistol.magazine_size)
	_check("burst refills the sniper", sniper.ammo == sniper.magazine_size)
	_check("burst staggers nearby visible enemies", _enemy.get_stagger_left() > 0.0)
	_check("burst damages nearby visible enemies",
		_enemy_health.current_health
			<= enemy_health_before
				- (_player.config.burst_damage + burst_overhealth
					* _player.config.burst_damage_per_overhealth) + 0.01)
	_check("burst does not refill its own buffer", is_zero_approx(vitals.overhealth))

	# Death empties actions and respawns with a full reset.
	vitals.take_damage(1000.0, null)
	await _frames(2)
	_check("lethal damage kills the player", _player.is_dead())
	await _frames(int(ceil(_player.config.player_respawn_delay * 60.0)) + 10)
	_check("player respawns", not _player.is_dead())
	_check("respawn restores health",
		is_equal_approx(vitals.current_health, _player.config.player_max_health))
	_check("respawn restores stamina",
		is_equal_approx(vitals.stamina, _player.config.player_max_stamina))
	_check("respawn clears overhealth", is_zero_approx(vitals.overhealth))
	_check("respawn becomes idle",
		_player.state_machine.current_name == &"Idle")

	await _frames(2)


func _spawn_enemy(at: Vector3) -> void:
	if _enemy != null and is_instance_valid(_enemy):
		_enemy.queue_free()
		await physics_frame
	_enemy = ENEMY_SCENE.instantiate() as EnemyCube
	_enemy.position = at
	_arena.add_child(_enemy)
	_enemy_health = _enemy.get_node("Health") as HealthComponent
	await _frames(2)


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
		push_error("vitals_test failed: " + label)
