class_name Projectile
extends CharacterBody3D

## Shared swept projectile body.
##
## Uses `move_and_collide()` so even very fast rounds cannot tunnel through thin
## geometry. Gravity is applied every tick before the move; the sniper preview
## deliberately mirrors that order. Subclasses (grenades) override
## [method _on_collision] to stick or bounce instead of dying.

signal impacted(position: Vector3, normal: Vector3, collider: Object)
signal hit_confirmed(killed: bool)

@export var gravity_scale: float = 1.0
@export var damage: float = 0.0
@export var radius: float = 0.08
@export var max_lifetime: float = 8.0

var source: Node


func setup(
	launch_velocity: Vector3,
	gravity: float,
	hit_damage: float,
	hit_radius: float,
	lifetime: float,
	owner_node: Node
) -> void:
	velocity = launch_velocity
	gravity_scale = gravity
	damage = hit_damage
	radius = hit_radius
	max_lifetime = lifetime
	source = owner_node


func _ready() -> void:
	collision_layer = PhysicsLayers.PROJECTILE
	collision_mask = PhysicsLayers.HIT_MASK
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	up_direction = Vector3.UP

	var collision := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision != null:
		var sphere := collision.shape as SphereShape3D
		if sphere != null:
			sphere = sphere.duplicate()
			sphere.radius = maxf(radius, 0.001)
			collision.shape = sphere


func _physics_process(delta: float) -> void:
	max_lifetime -= delta
	if max_lifetime <= 0.0:
		queue_free()
		return

	velocity += get_gravity() * gravity_scale * delta
	var collision := move_and_collide(velocity * delta)
	if collision != null:
		_on_collision(collision)


## Default impact: damage a [HealthComponent] if present, report the hit, then
## free the projectile. Grenades override this to stick or bounce.
func _on_collision(collision: KinematicCollision3D) -> void:
	var collider := collision.get_collider()
	var position := collision.get_position()
	var normal := collision.get_normal()

	var accepted := Damage.apply(collider, damage, source, position, normal)
	if accepted:
		var health := Damage.find_health(collider)
		hit_confirmed.emit(health != null and not health.is_alive())
	impacted.emit(position, normal, collider)
	queue_free()
