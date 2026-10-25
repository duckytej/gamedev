class_name HealthComponent
extends Node

## Reusable health for anything damageable (enemies, future destructibles, the
## player). Detection of this component is centralised in [Damage], so weapons
## never need to know the concrete enemy class.

signal health_changed(current: float, maximum: float)
signal damaged(amount: float, current: float, source: Node)
signal died(source: Node)

@export var max_health: float = 100.0
## 0 disables the short post-hit immunity used by fast-firing weapons.
@export var invincibility_time: float = 0.0

var current_health: float = 0.0
var is_invincible := false

var _invincibility_timer := 0.0


func _ready() -> void:
	if current_health <= 0.0:
		current_health = max_health
	health_changed.emit(current_health, max_health)


func _process(delta: float) -> void:
	if not is_invincible:
		return
	_invincibility_timer -= delta
	if _invincibility_timer <= 0.0:
		is_invincible = false


## Use for per-instance tuning (for example from GameConfig) after `_ready`.
func configure(maximum: float) -> void:
	max_health = maxf(maximum, 1.0)
	current_health = max_health
	is_invincible = false
	_invincibility_timer = 0.0
	health_changed.emit(current_health, max_health)


func take_damage(
	amount: float,
	source: Node = null,
	_hit_position: Vector3 = Vector3.ZERO,
	_hit_normal: Vector3 = Vector3.ZERO
) -> bool:
	if amount <= 0.0 or current_health <= 0.0 or is_invincible:
		return false

	current_health = clampf(current_health - amount, 0.0, max_health)
	health_changed.emit(current_health, max_health)
	damaged.emit(amount, current_health, source)

	if invincibility_time > 0.0:
		is_invincible = true
		_invincibility_timer = invincibility_time

	if current_health <= 0.0:
		died.emit(source)
	return true


func heal(amount: float) -> void:
	if current_health <= 0.0 or amount <= 0.0:
		return
	current_health = clampf(current_health + amount, 0.0, max_health)
	health_changed.emit(current_health, max_health)


func is_alive() -> bool:
	return current_health > 0.0


func get_fraction() -> float:
	return current_health / max_health if max_health > 0.0 else 0.0
