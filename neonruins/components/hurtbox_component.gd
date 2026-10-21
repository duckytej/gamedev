extends Area3D
class_name HurtboxComponent

signal damaged(amount: float, source: Node, knockback: Vector3)

@export var health_component: HealthComponent

func _ready() -> void:
	if not health_component:
		health_component = get_parent().get_node_or_null("HealthComponent")

func take_damage(amount: float, source: Node = null, knockback: Vector3 = Vector3.ZERO) -> void:
	if health_component:
		health_component.take_damage(amount, source)
	damaged.emit(amount, source, knockback)