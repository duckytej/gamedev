class_name EnemyCube
extends StaticBody3D

## Minimal shootable target for the weapon prototype.
##
## It is deliberately a StaticBody3D: enemies stay put, projectiles and hit-scan
## queries can both hit the same collision layer, and the peripheral-vision
## highlighter can copy the mesh without any special case.
##
## Health is a child [HealthComponent], so [Damage] can find it on any collider
## that is part of this body. The floating label is presentation only.

@export var config: GameConfig

@onready var health: HealthComponent = $Health
@onready var mesh: MeshInstance3D = $Mesh
@onready var label: Label3D = $HealthLabel

var _label_time_left := 0.0
var _flash_tween: Tween


func _ready() -> void:
	add_to_group(&"highlightable")
	add_to_group(&"damageable")

	if mesh.material_override != null:
		# Scene sub-resources are shared by every instance; duplicate so one
		# enemy's hit flash cannot tint every other cube.
		mesh.material_override = mesh.material_override.duplicate()

	health.died.connect(_on_died)
	health.damaged.connect(_on_damaged)
	health.health_changed.connect(_on_health_changed)

	var maximum := config.enemy_max_health if config != null else health.max_health
	health.configure(maximum)
	label.visible = false


func _process(delta: float) -> void:
	if _label_time_left <= 0.0:
		return
	_label_time_left -= delta
	if _label_time_left <= 0.0:
		label.visible = false


func _on_health_changed(current: float, maximum: float) -> void:
	label.text = "%d" % int(ceil(current))
	label.modulate = Color(1.0, 1.0, 1.0).lerp(Color(1.0, 0.3, 0.25), 1.0 - current / maximum)
	if current < maximum:
		label.visible = true
		_label_time_left = config.enemy_health_label_time if config != null else 2.0


func _on_damaged(_amount: float, _current: float, _source: Node) -> void:
	_flash(Color(1.0, 0.55, 0.25))


func _flash(color: Color) -> void:
	var material := mesh.material_override as StandardMaterial3D
	if material == null:
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	material.emission_enabled = true
	material.emission = color * 3.0
	_flash_tween = create_tween()
	_flash_tween.tween_property(material, "emission", Color.BLACK, 0.18)


func _on_died(_source: Node) -> void:
	remove_from_group(&"highlightable")
	remove_from_group(&"damageable")
	collision_layer = 0
	collision_mask = 0
	label.visible = false

	var fade := config.enemy_death_fade if config != null else 0.28
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(mesh, "scale", Vector3.ZERO, fade) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property(mesh, "rotation", Vector3(0.0, PI, 0.0), fade)
	tween.chain().tween_callback(queue_free)
