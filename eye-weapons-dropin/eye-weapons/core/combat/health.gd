class_name Health
extends Node
## Add as a child node named "Health" to anything damageable
## (enemies, barrels, the player). Weapons find it automatically.

signal died
signal damaged(amount: float, source: Object)

@export var max_hp := 100.0
var hp: float


func _ready() -> void:
	hp = max_hp


func take_damage(amount: float, source: Object = null) -> void:
	if hp <= 0.0:
		return
	hp -= amount
	damaged.emit(amount, source)
	if hp <= 0.0:
		died.emit()
