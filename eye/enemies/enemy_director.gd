class_name EnemyDirector
extends Node

## Time-sliced scheduler for all enemy brains.
##
## Enemies do not run AI in their own `_physics_process`. They register here and
## this node spends a fixed budget of `enemy_ai_max_updates_per_tick` decisions
## per physics tick, round-robin. With the default budget of one, no two enemies
## ever think on the same tick and the cost stays flat as the enemy count grows.
## Each enemy accumulates real time and thinks at `enemy_ai_update_interval`.
##
## F1 (or anything that calls [method set_ai_enabled]) pauses all decisions while
## leaving the bodies and collisions in place.

@export var config: GameConfig

## Runtime master switch. Seeded from [member GameConfig.enemy_ai_enabled].
var ai_enabled := true

var last_tick_updates := 0

var _enemies: Array[EnemyCube] = []
var _cursor := 0
var _scan_timer := 0.0


func _ready() -> void:
	add_to_group(&"enemy_director")
	if config != null:
		ai_enabled = config.enemy_ai_enabled
	call_deferred("_scan_enemies")


func _physics_process(delta: float) -> void:
	_scan_timer -= delta
	if _scan_timer <= 0.0:
		_scan_timer = 2.0
		_scan_enemies()

	last_tick_updates = 0
	if not ai_enabled or _enemies.is_empty():
		return

	var interval := config.enemy_ai_update_interval if config != null else 0.1
	var budget := config.enemy_ai_max_updates_per_tick if config != null else 1

	for enemy in _enemies:
		if is_instance_valid(enemy):
			enemy.think_accumulator += delta

	var count := _enemies.size()
	for _attempt in count:
		if budget <= 0:
			break
		if _cursor >= count:
			_cursor = 0
		var enemy := _enemies[_cursor]
		_cursor = (_cursor + 1) % count
		if not is_instance_valid(enemy) or not enemy.ai_enabled:
			continue
		if enemy.think_accumulator < interval:
			continue
		var elapsed := enemy.think_accumulator
		enemy.think_accumulator = 0.0
		enemy.think(elapsed)
		last_tick_updates += 1
		budget -= 1


func register_enemy(enemy: EnemyCube) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	if _enemies.has(enemy):
		return
	_enemies.append(enemy)
	enemy.set_director(self)
	enemy.set_ai_active(ai_enabled)
	if _enemies.size() == 1:
		_cursor = 0


func set_ai_enabled(value: bool) -> void:
	if ai_enabled == value:
		return
	ai_enabled = value
	for enemy in _enemies:
		if is_instance_valid(enemy):
			enemy.set_ai_active(value)
	if not value:
		last_tick_updates = 0


func toggle_ai() -> void:
	set_ai_enabled(not ai_enabled)


func is_ai_enabled() -> bool:
	return ai_enabled


func get_enemy_count() -> int:
	return _enemies.size()


func get_debug_text() -> String:
	return "AI %s  %d" % ["ON" if ai_enabled else "OFF", _enemies.size()]


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_enemy_ai"):
		toggle_ai()


func _scan_enemies() -> void:
	var found := get_tree().get_nodes_in_group(&"enemy")
	for node in found:
		var enemy := node as EnemyCube
		if enemy != null:
			register_enemy(enemy)

	var index := _enemies.size() - 1
	while index >= 0:
		if not is_instance_valid(_enemies[index]):
			_enemies.remove_at(index)
			if _cursor > index:
				_cursor = maxi(_cursor - 1, 0)
		index -= 1
	if _enemies.is_empty():
		_cursor = 0
	elif _cursor >= _enemies.size():
		_cursor = 0
