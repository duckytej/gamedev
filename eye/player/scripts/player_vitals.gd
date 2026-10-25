class_name PlayerVitals
extends HealthComponent

## Player health, stamina and the overhealth (damage buffer) resource.
##
## Health is the normal [HealthComponent] pool. Overhealth is a second pool that
## fills when the player damages an enemy and is consumed before health. Stamina
## is spent only by explicit actions (dash, grapple attach, weapon use); walking,
## running, jumping, sliding and wall running are free.
##
## The whole overhealth pool can be spent on the stagger burst, but only while
## it is more than [member overhealth_burst_threshold] full.

signal stamina_changed(current: float, maximum: float)
signal overhealth_changed(current: float, maximum: float)

@export var max_stamina: float = 100.0
@export var max_overhealth: float = 50.0
@export var stamina_regen_per_second: float = 18.0
@export var stamina_regen_delay: float = 1.0
@export_range(0.01, 0.99, 0.01) var overhealth_burst_threshold: float = 0.5

var stamina: float = 0.0
var overhealth: float = 0.0

var _stamina_regen_timer := 0.0


func _ready() -> void:
	if current_health <= 0.0:
		current_health = max_health
	if stamina <= 0.0:
		stamina = max_stamina
	_emit_all()


## Copies the single source of truth into the runtime pools. Called by
## [EyePlayer] before any ability is set up.
func setup(game_config: GameConfig) -> void:
	if game_config == null:
		return
	max_health = maxf(game_config.player_max_health, 1.0)
	max_stamina = maxf(game_config.player_max_stamina, 1.0)
	max_overhealth = maxf(game_config.player_max_overhealth, 0.0)
	overhealth_burst_threshold = game_config.overhealth_burst_threshold
	stamina_regen_per_second = game_config.player_stamina_regen_per_second
	stamina_regen_delay = game_config.player_stamina_regen_delay
	reset_vitals()


func _process(delta: float) -> void:
	super._process(delta)

	if current_health <= 0.0:
		return

	if _stamina_regen_timer > 0.0:
		_stamina_regen_timer = maxf(_stamina_regen_timer - delta, 0.0)
		return
	if stamina < max_stamina:
		stamina = minf(stamina + stamina_regen_per_second * delta, max_stamina)
		stamina_changed.emit(stamina, max_stamina)


## Overhealth absorbs damage first. Returns true when the hit was accepted.
func take_damage(
	amount: float,
	source: Node = null,
	hit_position: Vector3 = Vector3.ZERO,
	hit_normal: Vector3 = Vector3.ZERO
) -> bool:
	if amount <= 0.0 or current_health <= 0.0 or is_invincible:
		return false

	var remaining := amount
	if overhealth > 0.0:
		var absorbed := minf(overhealth, remaining)
		overhealth -= absorbed
		remaining -= absorbed
		overhealth_changed.emit(overhealth, max_overhealth)

	last_damage_applied = minf(amount, remaining)
	if remaining > 0.0:
		var before := current_health
		current_health = clampf(current_health - remaining, 0.0, max_health)
		last_damage_applied = before - current_health
		health_changed.emit(current_health, max_health)

	damaged.emit(amount, current_health, source)

	if invincibility_time > 0.0:
		is_invincible = true
		_invincibility_timer = invincibility_time

	if current_health <= 0.0:
		died.emit(source)
	return true


## Adds overhealth from damage dealt to an enemy. Returns the amount gained.
func add_overhealth(amount: float) -> float:
	if amount <= 0.0 or current_health <= 0.0 or max_overhealth <= 0.0:
		return 0.0
	var before := overhealth
	overhealth = minf(overhealth + amount, max_overhealth)
	overhealth_changed.emit(overhealth, max_overhealth)
	return overhealth - before


func can_burst() -> bool:
	return max_overhealth > 0.0 \
		and overhealth > max_overhealth * overhealth_burst_threshold


## Spends the entire buffer and returns how much was spent. Returns 0 when the
## burst is not available, so callers cannot accidentally fire it early.
func consume_overhealth_for_burst() -> float:
	if not can_burst():
		return 0.0
	var spent := overhealth
	overhealth = 0.0
	overhealth_changed.emit(overhealth, max_overhealth)
	return spent


func has_stamina(cost: float) -> bool:
	return cost <= 0.0 or stamina + 0.0001 >= cost


func try_spend_stamina(cost: float) -> bool:
	if cost <= 0.0:
		return true
	if not has_stamina(cost):
		return false
	stamina = maxf(stamina - cost, 0.0)
	_stamina_regen_timer = stamina_regen_delay
	stamina_changed.emit(stamina, max_stamina)
	return true


func refill_stamina() -> void:
	stamina = max_stamina
	_stamina_regen_timer = 0.0
	stamina_changed.emit(stamina, max_stamina)


## Full reset used on spawn and after death.
func reset_vitals() -> void:
	current_health = max_health
	overhealth = 0.0
	stamina = max_stamina
	is_invincible = false
	_invincibility_timer = 0.0
	_stamina_regen_timer = 0.0
	last_damage_applied = 0.0
	_emit_all()


func get_overhealth_fraction() -> float:
	return overhealth / max_overhealth if max_overhealth > 0.0 else 0.0


func get_stamina_fraction() -> float:
	return stamina / max_stamina if max_stamina > 0.0 else 0.0


func _emit_all() -> void:
	health_changed.emit(current_health, max_health)
	stamina_changed.emit(stamina, max_stamina)
	overhealth_changed.emit(overhealth, max_overhealth)
