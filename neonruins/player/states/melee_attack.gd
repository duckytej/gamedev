extends State

const MAX_COMBO_CHAIN: int = 3

var _attack_timer: float = 0.0
var _combo_count: int = 0
var _can_combo: bool = false
var _swing_id: int = 0


func enter() -> void:
	_attack_timer = 0.0
	_combo_count = 0
	_can_combo = false
	_start_swing()


func physics_process(delta: float) -> void:
	player.apply_gravity(delta)
	_attack_timer -= delta
	if _attack_timer <= 0.0:
		_finish()
		return

	# Combo follow-up input
	if _can_combo and Input.is_action_just_pressed("melee_attack") \
			and _combo_count < MAX_COMBO_CHAIN - 1 \
			and player.stamina_component.can_consume(player.melee_weapon.stamina_cost):
		_combo_count += 1
		_start_swing()
		return

	# Slow drift movement during swing
	if player.is_on_floor():
		var wish_dir := player.get_input_direction()
		if wish_dir.length() > 0.1:
			var speed := player.walk_speed * 0.4
			player.velocity.x = lerpf(player.velocity.x, wish_dir.x * speed, 8.0 * delta)
			player.velocity.z = lerpf(player.velocity.z, wish_dir.z * speed, 8.0 * delta)
	else:
		player.velocity.x *= 0.92
		player.velocity.z *= 0.92


func _start_swing() -> void:
	var weapon := player.melee_weapon
	_attack_timer = weapon.attack_speed + weapon.hit_active_start + weapon.hit_active_duration
	_can_combo = false
	_swing_id += 1
	var swing := _swing_id

	if not player.stamina_component.consume(weapon.stamina_cost):
		SignalBus.stamina_exhausted.emit(player)
		_finish_early()
		return

	SignalBus.attack_started.emit(player, "melee_light_%d" % (_combo_count + 1))
	player.attack_hitbox.damage = weapon.damage
	player.attack_hitbox.knockback_force = weapon.knockback_force

	# Hit window opens after wind-up, closes after active duration.
	# Swing id guard prevents stale timers from reopening the window
	# after a combo or state exit.
	var tree := get_tree()
	tree.create_timer(weapon.hit_active_start).timeout.connect(func() -> void:
		if swing == _swing_id:
			player.attack_hitbox.active = true
	)
	tree.create_timer(weapon.hit_active_start + weapon.hit_active_duration).timeout.connect(func() -> void:
		if swing == _swing_id:
			player.attack_hitbox.active = false
			_can_combo = true
	)


func _finish() -> void:
	player.attack_hitbox.active = false
	if player.is_on_floor():
		player.transition_to("Walk")
	else:
		player.transition_to("InAir")


func _finish_early() -> void:
	_attack_timer = minf(_attack_timer, 0.1)


func exit() -> void:
	_swing_id += 1  # invalidate any pending hit-window timers
	player.attack_hitbox.active = false
