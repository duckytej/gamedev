extends Area3D
class_name HitboxComponent

signal hit(target: Node, damage: float, knockback: Vector3)

@export var damage: float = 10.0
@export var knockback_force: float = 8.0
@export var hit_cooldown: float = 0.4
@export var stagger_amount: float = 10.0

## While true the hitbox damages anything overlapping it.
## Toggle in short windows for melee swings instead of toggling `monitoring`,
## which misses targets that were already inside the area.
var active: bool = false

var _hit_targets: Dictionary = {}


func _ready() -> void:
	monitoring = true


func _physics_process(_delta: float) -> void:
	if not active:
		return
	for area in get_overlapping_areas():
		_try_hit(area)


func _try_hit(area: Area3D) -> void:
	if not area is HurtboxComponent:
		return
	if area.get_parent() == get_parent():
		return  # never hit yourself

	var target := area.get_parent()
	if target == null or _hit_targets.has(target):
		return
	if not is_instance_valid(target):
		return

	_hit_targets[target] = true

	var kb_dir := global_position - (target as Node3D).global_position
	kb_dir.y = maxf(kb_dir.y * 0.5, 0.2)  # slight upward pop on knockback
	var kb: Vector3 = (kb_dir.normalized() if kb_dir.length() > 0.01 else Vector3.FORWARD) * knockback_force

	area.take_damage(damage, get_parent(), kb)
	hit.emit(target, damage, kb)
	SignalBus.attack_landed.emit(get_parent(), target, damage)

	var timer := get_tree().create_timer(hit_cooldown)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(target):
			_hit_targets.erase(target)
	)
