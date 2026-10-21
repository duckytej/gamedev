extends Node
class_name StaminaComponent

@export var max_stamina: float = 100.0
@export var regen_rate: float = 25.0
@export var regen_delay: float = 1.0
@export var exhaustion_penalty: float = 2.5
@export var sprint_drain: float = 15.0

var current_stamina: float
var regen_timer: float = 0.0
var is_exhausted: bool = false
var exhaustion_timer: float = 0.0

signal stamina_changed(current: float, maximum: float)

func _ready() -> void:
	current_stamina = max_stamina
	stamina_changed.emit(current_stamina, max_stamina)

func _process(delta: float) -> void:
	if regen_timer > 0.0:
		regen_timer -= delta
		return

	if is_exhausted:
		exhaustion_timer -= delta
		if exhaustion_timer <= 0.0:
			is_exhausted = false

	if current_stamina < max_stamina and not is_exhausted:
		current_stamina = clampf(current_stamina + regen_rate * delta, 0.0, max_stamina)
		stamina_changed.emit(current_stamina, max_stamina)

func consume(amount: float) -> bool:
	if current_stamina < amount or is_exhausted:
		return false

	current_stamina = clampf(current_stamina - amount, 0.0, max_stamina)
	regen_timer = regen_delay
	stamina_changed.emit(current_stamina, max_stamina)

	if current_stamina <= 0.0:
		is_exhausted = true
		exhaustion_timer = exhaustion_penalty
		SignalBus.stamina_depleted.emit(self)
	return true

func can_consume(amount: float) -> bool:
	return current_stamina >= amount and not is_exhausted

func get_stamina_fraction() -> float:
	return current_stamina / max_stamina if max_stamina > 0.0 else 0.0

func reset() -> void:
	current_stamina = max_stamina
	regen_timer = 0.0
	is_exhausted = false
	exhaustion_timer = 0.0
	stamina_changed.emit(current_stamina, max_stamina)