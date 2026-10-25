class_name Damage
extends RefCounted

## Central damage routing.
##
## Weapons/projectiles call [method apply] with whatever the physics query
## returned. This helper finds a [HealthComponent] on the collider, one of its
## children, or a parent body. That makes hit detection independent of scene
## structure: an enemy can be a StaticBody3D, CharacterBody3D or even an Area3D
## hurtbox without changing a single weapon.

## Finds a health component without assuming a node path beyond the common names
## `Health` and `HealthComponent`, then walks up the parent chain.
static func find_health(target: Object) -> HealthComponent:
	var node := target as Node
	while node != null:
		if node is HealthComponent:
			return node
		var direct := node.get_node_or_null("Health") as HealthComponent
		if direct != null:
			return direct
		var component := node.get_node_or_null("HealthComponent") as HealthComponent
		if component != null:
			return component
		node = node.get_parent()
	return null


## Applies damage and returns true when a health component accepted it.
static func apply(
	collider: Object,
	amount: float,
	source: Node = null,
	hit_position: Vector3 = Vector3.ZERO,
	hit_normal: Vector3 = Vector3.ZERO
) -> bool:
	if collider == null:
		return false

	var health := find_health(collider)
	if health != null:
		var accepted := health.take_damage(amount, source, hit_position, hit_normal)
		if accepted:
			_credit_player(source, health.last_damage_applied)
		return accepted

	# Duck-typed fallback for custom damageable nodes.
	var node := collider as Node
	if node != null and node.has_method("take_damage"):
		node.call("take_damage", amount, source, hit_position, hit_normal)
		_credit_player(source, amount)
		return true
	return false


## Damage dealt by the player feeds the overhealth buffer. Centralising this in
## [Damage] means every weapon/projectile contributes without knowing about
## vitals, and overkill is already clipped by the health component.
static func _credit_player(source: Node, applied: float) -> void:
	if applied <= 0.0:
		return
	if source is EyePlayer:
		var player := source as EyePlayer
		player.register_damage_dealt(applied)


## True when the collider (or one of its parents) has health.
static func is_damageable(collider: Object) -> bool:
	return find_health(collider) != null
