extends SceneTree

## Headless combat test: modular loadout, hit-scan damage, grenade area damage,
## charged sniper hit-scan and the scope impact preview. No renderer required.
##
##   godot --headless --script res://misc/tests/combat_test.gd

const PLAYER_SCENE := preload("res://player/scenes/player.tscn")
const ENEMY_SCENE := preload("res://enemies/enemy_cube.tscn")

var _checks := 0
var _failures := 0

var _arena: Node3D
var _player: EyePlayer
var _controller: WeaponController
var _enemy: EnemyCube
var _health: HealthComponent


func _initialize() -> void:
	_build()
	await _run()
	print("combat_test: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _build() -> void:
	_arena = Node3D.new()
	_arena.name = "Arena"
	root.add_child(_arena)
	_add_box(Vector3(40, 1, 40), Vector3(0, -0.5, 0))

	_player = PLAYER_SCENE.instantiate() as EyePlayer
	_player.position = Vector3(0, 0.2, 0)
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


func _spawn_enemy() -> void:
	if _enemy != null and is_instance_valid(_enemy):
		_enemy.queue_free()
		await physics_frame
	_enemy = ENEMY_SCENE.instantiate() as EnemyCube
	_enemy.position = Vector3(0, 0.9, -4)
	_arena.add_child(_enemy)
	_health = _enemy.get_node("Health") as HealthComponent
	await _frames(2)


func _run() -> void:
	await _frames(30)

	# --- Loadout -------------------------------------------------------------
	_controller = get_first_node_in_group(&"weapon_controller") as WeaponController
	_check("weapon controller exists", _controller != null)
	_check("player has an ability host", _player.abilities != null)
	if _controller == null:
		return
	_check("loadout has three weapons", _controller.get_weapons().size() == 3)
	_check("pistol is present", _controller.get_pistol() != null)
	_check("grenade is present", _controller.get_grenade() != null)
	_check("sniper is present", _controller.get_sniper() != null)
	_check("player has grapple ability", _player.get_grapple() != null)
	_check("player has wall sense", _player.get_wall_sense() != null)

	var hit_count := [0]
	var last_hit_was_kill := [false]
	_controller.hit_confirmed.connect(func(killed: bool) -> void:
		hit_count[0] += 1
		last_hit_was_kill[0] = killed
	)

	# --- Pistol hit-scan -----------------------------------------------------
	await _spawn_enemy()
	var start_health := _health.current_health
	Input.action_press("fire")
	await _frames(2)
	Input.action_release("fire")
	await _frames(3)
	_check("pistol deals low damage",
		_health.current_health < start_health
		and start_health - _health.current_health <= _player.config.pistol_damage + 0.01)
	_check("hit feedback emitted", hit_count[0] > 0)
	_check("non-lethal pistol hit does not report a kill", not last_hit_was_kill[0])

	# --- Grenade area damage -------------------------------------------------
	await _spawn_enemy()
	Input.action_press("fire")
	await _frames(36)  # past hold threshold, enough charge
	_check("grenade is charging", _controller.get_grenade().is_charging())
	_check("holding for a grenade does not fire the pistol",
		is_equal_approx(_health.current_health, _player.config.enemy_max_health))
	Input.action_release("fire")
	await _frames(3)
	_check("grenade projectile spawned", _count_projectiles() > 0)
	await _frames(190)
	_check("grenade damages the target",
		not is_instance_valid(_enemy) or _health.current_health < 100.0)

	# --- Scoped charged sniper ------------------------------------------------
	await _spawn_enemy()
	Input.action_press("aim")
	await _frames(4)
	_check("right mouse scopes", _controller.is_scoped())
	_check("player scope blend starts", _player.scoped)

	var sniper := _controller.get_sniper()
	Input.action_press("fire")
	await _frames(12)
	var preview := _arena.get_node_or_null("SniperImpactPreview") as MeshInstance3D
	_check("scope preview exists", preview != null)
	_check("scope preview is visible while aiming", preview != null and preview.visible)

	await _frames(int(ceil(_player.config.sniper_charge_time * 60.0)) + 6)
	_check("sniper reaches full charge",
		sniper != null and sniper.get_charge() >= _player.config.sniper_hitscan_threshold)

	Input.action_release("fire")
	await _frames(3)
	_check("full-charge sniper kills the target",
		not is_instance_valid(_enemy) or _health.current_health <= 0.0)
	Input.action_release("aim")
	await _frames(3)
	_check("releasing aim exits scope", not _controller.is_scoped())

	# --- Damage routing ------------------------------------------------------
	_check("enemy health starts at configured maximum",
		is_equal_approx(_player.config.enemy_max_health, 100.0))

	# --- Optional loadout removal -------------------------------------------
	var pistol := _controller.get_pistol()
	_check("pistol is removable", pistol != null)
	if pistol != null:
		pistol.queue_free()
		await _frames(3)
		_check("removing a weapon updates the loadout",
			_controller.get_pistol() == null and _controller.get_weapons().size() == 2)

	# --- Optional controller removal ---------------------------------------
	Input.action_press("aim")
	await _frames(3)
	var loadout := _controller
	_controller = null
	loadout.queue_free()
	await _frames(4)
	_check("removing the loadout exits scope", not _player.scoped)
	_check("removing the loadout cleans the world query",
		_arena.get_node_or_null("SniperHitscan") == null)
	_check("weapon controller leaves its group",
		get_first_node_in_group(&"weapon_controller") == null)


func _count_projectiles() -> int:
	return get_nodes_in_group(&"projectile").size()


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
		push_error("combat_test failed: " + label)
