class_name GrenadeProjectile
extends Projectile

## Fused grenade with radial damage. By default it is sticky: the first surface
## it touches becomes the blast point, including a moving enemy. Disable
## `sticky_grenade` to restore the old bounce behaviour.
##
## Explosion uses a sphere overlap on the enemy layer, a per-target distance
## falloff and a world-only line-of-sight check, so walls block the blast. This
## is the same [Damage] pipeline used by the pistol and sniper, so any future
## damageable accepts grenades automatically.

signal damage_dealt(killed: bool)

const COLLISION_RADIUS := 0.12

var explosion_damage := 80.0
var explosion_min_damage := 20.0
var explosion_radius := 4.0
var fuse_time := 2.5
var sticky := true
var bounce := 0.35
var friction := 0.7
var explosion_color := Color(1.0, 0.48, 0.12)
var explosion_light_energy := 6.0
var explosion_visual_time := 0.4

var _fuse_left := 0.0
var _exploded := false
var _stuck := false
var _stick_target: Node3D
var _stick_offset := Vector3.ZERO


func setup_grenade(
	launch_velocity: Vector3,
	gravity: float,
	max_damage: float,
	min_damage: float,
	radius: float,
	fuse: float,
	lifetime: float,
	sticky_grenade: bool,
	bounce_factor: float,
	friction_factor: float,
	color: Color,
	light_energy: float,
	visual_time: float,
	owner_node: Node
) -> void:
	super.setup(launch_velocity, gravity, max_damage, COLLISION_RADIUS, lifetime, owner_node)
	explosion_damage = max_damage
	explosion_min_damage = min_damage
	explosion_radius = radius
	fuse_time = fuse
	sticky = sticky_grenade
	bounce = bounce_factor
	friction = friction_factor
	explosion_color = color
	explosion_light_energy = light_energy
	explosion_visual_time = visual_time
	_fuse_left = fuse_time


func _ready() -> void:
	radius = COLLISION_RADIUS
	super._ready()


func _physics_process(delta: float) -> void:
	if _exploded:
		return
	_fuse_left -= delta
	if _fuse_left <= 0.0:
		_explode()
		return

	if _stuck:
		# Keep following a moving target (an enemy walking away with a grenade
		# stuck to it) without running collision response again.
		max_lifetime -= delta
		if max_lifetime <= 0.0:
			queue_free()
			return
		_follow_stick_target()
		return

	super._physics_process(delta)


func _on_collision(collision: KinematicCollision3D) -> void:
	if sticky:
		_stick(collision)
		return

	var normal := collision.get_normal()
	var point := collision.get_position()
	global_position = point + normal * 0.01

	velocity = velocity.bounce(normal) * bounce
	# Scrub tangential energy so grenades settle instead of skating forever.
	velocity.x *= friction
	velocity.z *= friction
	if velocity.length_squared() < 1.0:
		velocity = Vector3.ZERO

	impacted.emit(point, normal, collision.get_collider())


func _stick(collision: KinematicCollision3D) -> void:
	var normal := collision.get_normal()
	var point := collision.get_position()
	_stuck = true
	velocity = Vector3.ZERO
	global_position = point + normal * 0.02

	_stick_target = collision.get_collider() as Node3D
	if _stick_target != null and is_instance_valid(_stick_target):
		_stick_offset = _stick_target.to_local(global_position)
	else:
		_stick_target = null

	# A stuck grenade must not be pushed around by physics for the rest of its
	# fuse, but it still needs to be found by neither bullets nor the player.
	collision_layer = 0
	collision_mask = 0
	impacted.emit(point, normal, collision.get_collider())


func _follow_stick_target() -> void:
	if _stick_target == null:
		return
	if not is_instance_valid(_stick_target):
		_stick_target = null
		return
	global_position = _stick_target.to_global(_stick_offset)


func is_stuck() -> bool:
	return _stuck


func _explode() -> void:
	if _exploded:
		return
	_exploded = true

	var any_damage := false
	var any_kill := false
	for result in _query_area():
		var collider: Object = result.get("collider")
		if collider == null:
			continue
		var health := Damage.find_health(collider)
		if health == null:
			continue

		var target := collider as Node3D
		var target_position := global_position
		if target != null:
			target_position = target.global_position
		var distance := global_position.distance_to(target_position)
		if distance > explosion_radius or not _has_line_of_sight(target_position):
			continue

		var falloff := 1.0 - clampf(distance / maxf(explosion_radius, 0.001), 0.0, 1.0)
		var amount := lerpf(explosion_min_damage, explosion_damage, falloff)
		var accepted := Damage.apply(collider, amount, source, target_position, Vector3.UP)
		if accepted:
			any_damage = true
			if not health.is_alive():
				any_kill = true

	if any_damage:
		damage_dealt.emit(any_kill)

	_spawn_explosion_visual()
	queue_free()


func _query_area() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var space := get_world_3d().direct_space_state
	if space == null:
		return results

	var sphere := SphereShape3D.new()
	sphere.radius = explosion_radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, global_position)
	query.collision_mask = PhysicsLayers.ENEMY
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [get_rid()]

	var raw := space.intersect_shape(query, 64)
	var seen: Dictionary = {}
	for entry in raw:
		var collider: Object = entry.get("collider")
		if collider == null:
			continue
		var health := Damage.find_health(collider)
		if health == null:
			continue
		var id := health.get_instance_id()
		if seen.has(id):
			continue
		seen[id] = true
		results.append(entry)
	return results


func _has_line_of_sight(target_position: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(
		global_position, target_position, PhysicsLayers.WORLD, [get_rid()]
	)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _spawn_explosion_visual() -> void:
	var parent := get_parent()
	if parent == null:
		return

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = explosion_color
	material.emission_enabled = true
	material.emission = explosion_color
	material.emission_energy_multiplier = 4.0
	material.no_depth_test = true

	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 16
	mesh.rings = 8

	var effect := MeshInstance3D.new()
	effect.name = "GrenadeExplosion"
	effect.mesh = mesh
	effect.material_override = material
	effect.top_level = true
	effect.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	effect.scale = Vector3.ONE * 0.2
	parent.add_child(effect)
	effect.global_position = global_position

	var light := OmniLight3D.new()
	light.light_color = explosion_color
	light.light_energy = explosion_light_energy
	light.omni_range = explosion_radius * 3.0
	light.shadow_enabled = false
	effect.add_child(light)

	var tween := effect.create_tween()
	tween.set_parallel(true)
	tween.tween_property(effect, "scale", Vector3.ONE * explosion_radius * 1.8, explosion_visual_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(
		material,
		"albedo_color",
		Color(explosion_color.r, explosion_color.g, explosion_color.b, 0.0),
		explosion_visual_time
	)
	tween.tween_property(light, "light_energy", 0.0, explosion_visual_time)
	tween.chain().tween_callback(effect.queue_free)
