extends Node
class_name HealthComponent

@export var max_health: float = 100.0
@export var invincibility_time: float = 0.5
@export var regen_rate: float = 0.0
@export var regen_delay: float = 5.0

var current_health: float
var is_invincible: bool = false
var invincibility_timer: float = 0.0
var regen_timer: float = 0.0
var last_damage_time: float = 0.0

signal health_changed(current: float, maximum: float)
signal died()

func _ready() -> void:
	current_health = max_health
	health_changed.emit(current_health, max_health)

func _process(delta: float) -> void:
	if is_invincible:
		invincibility_timer -= delta
		if invincibility_timer <= 0.0:
			is_invincible = false

	# Health regen
	if regen_rate > 0.0 and current_health < max_health and current_health > 0.0:
		regen_timer -= delta
		if regen_timer <= 0.0:
			current_health = min(current_health + regen_rate * delta, max_health)
			health_changed.emit(current_health, max_health)

func take_damage(amount: float, source: Node = null) -> void:
	if is_invincible or current_health <= 0.0:
		return

	current_health = clampf(current_health - amount, 0.0, max_health)
	health_changed.emit(current_health, max_health)
	last_damage_time = Time.get_ticks_msec() * 0.001
	regen_timer = regen_delay

	if invincibility_time > 0.0:
		is_invincible = true
		invincibility_timer = invincibility_time

	if current_health <= 0.0:
		died.emit()
		SignalBus.entity_died.emit(get_parent())

	SignalBus.damage_dealt.emit(get_parent(), amount, source)
	SignalBus.health_changed.emit(get_parent(), current_health, max_health)

func heal(amount: float) -> void:
	if current_health <= 0.0:
		return
	current_health = clampf(current_health + amount, 0.0, max_health)
	health_changed.emit(current_health, max_health)

func is_alive() -> bool:
	return current_health > 0.0

func get_health_fraction() -> float:
	return current_health / max_health if max_health > 0.0 else 0.0

func reset() -> void:
	current_health = max_health
	is_invincible = false
	invincibility_timer = 0.0
	regen_timer = 0.0
	health_changed.emit(current_health, max_health)