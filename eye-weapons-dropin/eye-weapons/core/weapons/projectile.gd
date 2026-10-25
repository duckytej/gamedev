class_name Projectile
extends Area3D
## Simple rocket/plasma projectile.
## Make a scene: Area3D + CollisionShape3D + this script (+ a mesh child),
## save as e.g. res://core/weapons/rocket.tscn, assign to
## WeaponResource.projectile_scene.

var velocity := Vector3.ZERO
var damage := 30.0
var life := 5.0
var blast_radius := 0.0  # >0 = explode and damage everything in radius
var gravity := 0.0       # >0 = arcing projectile (grenades). set before launch.
var _source: Object = null

func launch(dir: Vector3, speed: float, p_damage: float, p_source: Object) -> void:
	velocity = dir * speed
	damage = p_damage
	_source = p_source
	collision_mask = 0b1110  # everything except player layer 1
	monitoring = true
	if not is_node_ready():
		await ready
	look_at(global_position + dir)

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

func _physics_process(delta: float) -> void:
	velocity.y -= gravity * delta
	global_position += velocity * delta
	if velocity.length_squared() > 0.01:
		look_at(global_position + velocity.normalized())
	life -= delta
	if life <= 0.0:
		_explode()

func _on_body_entered(body: Node3D) -> void:
	_explode()

func _on_area_entered(_area: Area3D) -> void:
	_explode()

func _explode() -> void:
	if blast_radius > 0.0:
		var space := get_world_3d().direct_space_state
		var query := PhysicsShapeQueryParameters3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = blast_radius
		query.shape = sphere
		query.transform = Transform3D(Basis(), global_position)
		query.collision_mask = 0b1110
		for r in space.intersect_shape(query, 16):
			var node := r.collider as Node
			if node == null:
				continue
			var health := node.get_node_or_null("Health")
			if health != null and health.has_method("take_damage"):
				health.take_damage(damage, _source)
			elif r.collider.has_method("take_damage"):
				r.collider.call("take_damage", damage, _source)
		# hook here: explosion VFX + Audio.play("explosion")
	elif _source != null:
		pass
	queue_free()
