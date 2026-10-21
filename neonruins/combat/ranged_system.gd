extends Node
class_name RangedSystem

const DEFAULT_WEAPON := preload("res://combat/default_ranged.tres")

@export var weapon: WeaponResource

var ammo_current: int = 0
var fire_timer: float = 0.0
var is_reloading: bool = false
var reload_timer: float = 0.0
var player: Player


func _ready() -> void:
	player = get_parent() as Player
	if not player:
		push_warning("RangedSystem must be a child of a Player node")
		set_process(false)
		return
	if not weapon:
		weapon = DEFAULT_WEAPON
	ammo_current = weapon.ammo_max


func _process(delta: float) -> void:
	fire_timer = maxf(fire_timer - delta, 0.0)

	if is_reloading:
		reload_timer -= delta
		if reload_timer <= 0.0:
			_finish_reload()


func can_fire() -> bool:
	if not player or not weapon or is_reloading:
		return false
	return fire_timer <= 0.0 and ammo_current > 0


func try_fire() -> bool:
	if not can_fire():
		if ammo_current <= 0 and not is_reloading:
			start_reload()
		return false

	ammo_current -= 1
	fire_timer = weapon.fire_rate

	SignalBus.attack_started.emit(player, "ranged")
	SignalBus.ammo_changed.emit(player, ammo_current, weapon.ammo_max)

	_fire_hitscan()
	_apply_recoil()

	if ammo_current <= 0:
		start_reload()

	return true


func _fire_hitscan() -> void:
	var camera := player.camera
	if not camera:
		return

	var from := camera.global_position
	var dir := -camera.global_basis.z

	# Apply spread cone
	if weapon.spread > 0.0:
		dir = dir.normalized() \
				+ randf_range(-weapon.spread, weapon.spread) * camera.global_basis.x \
				+ randf_range(-weapon.spread, weapon.spread) * camera.global_basis.y
		dir = dir.normalized()

	var to := from + dir * maxf(weapon.range_distance, 100.0)

	var space_state := player.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = true   # hurtboxes are Area3D
	query.collide_with_bodies = true  # world geometry blocks shots
	query.collision_mask = 1 | 4      # world/player bodies + hurtbox layer
	query.exclude = [player.get_rid()]
	query.hit_from_inside = false

	var result := space_state.intersect_ray(query)

	var end_point := to
	if result:
		end_point = result.position
		_resolve_hit(result)

	_spawn_tracer(camera.global_position + dir * 0.4, end_point)


func _resolve_hit(result: Dictionary) -> void:
	var collider: Object = result.collider
	if collider == null:
		return

	# Hurtboxes are Area3D parented to their owner; route through them so the
	# owner receives the damage signal too. Plain bodies with a HealthComponent
	# are damaged directly.
	if collider is HurtboxComponent:
		var kb_dir: Vector3 = collider.get_parent().global_position - player.global_position if collider.get_parent() is Node3D else Vector3.FORWARD
		kb_dir.y = 0.3
		kb_dir = kb_dir.normalized() if kb_dir.length() > 0.01 else Vector3.FORWARD
		collider.take_damage(weapon.damage, player, kb_dir * weapon.knockback_force)
		SignalBus.attack_landed.emit(player, collider.get_parent(), weapon.damage)
	elif collider is Node and (collider as Node).get_node_or_null("HealthComponent") != null:
		var health_comp := (collider as Node).get_node("HealthComponent") as HealthComponent
		if health_comp:
			health_comp.take_damage(weapon.damage, player)
			SignalBus.attack_landed.emit(player, collider, weapon.damage)
	else:
		# World impact effect
		_create_impact(result.position, result.normal)


func _apply_recoil() -> void:
	if weapon.recoil_force <= 0.0:
		return
	# Kick the camera pitch up slightly
	player.camera_pitch += deg_to_rad(weapon.recoil_force * 0.5)
	player.velocity -= player.camera.global_basis.z * weapon.recoil_force * 0.2


func start_reload() -> void:
	if is_reloading or not weapon or ammo_current == weapon.ammo_max:
		return
	is_reloading = true
	reload_timer = weapon.reload_time
	SignalBus.ammo_changed.emit(player, ammo_current, weapon.ammo_max)


func _finish_reload() -> void:
	is_reloading = false
	if weapon:
		ammo_current = weapon.ammo_max
	SignalBus.ammo_changed.emit(player, ammo_current, weapon.ammo_max)


func get_ammo_fraction() -> float:
	if not weapon or weapon.ammo_max <= 0:
		return 0.0
	return float(ammo_current) / float(weapon.ammo_max)


# === VISUAL EFFECTS ===

func _spawn_tracer(from: Vector3, to: Vector3) -> void:
	var tracer := MeshInstance3D.new()
	var mesh := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.9, 0.4)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.85, 0.3) * 6.0
	tracer.mesh = mesh
	tracer.top_level = true
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	mesh.surface_add_vertex(from)
	mesh.surface_add_vertex(to)
	mesh.surface_end()

	var scene := player.get_tree().current_scene
	scene.add_child(tracer)

	var tween := tracer.create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.08)
	tween.tween_callback(tracer.queue_free)


func _create_impact(position: Vector3, normal: Vector3) -> void:
	var marker := MeshInstance3D.new()
	var mesh := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.8, 0.0)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.8, 0.0) * 5.0
	marker.mesh = mesh
	marker.top_level = true
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, mat)
	var p := position + normal * 0.05
	var s := 0.06
	mesh.surface_add_vertex(p + normal * s)
	mesh.surface_add_vertex(p + normal.cross(Vector3.UP).normalized() * s - Vector3.UP * s)
	mesh.surface_add_vertex(p - normal.cross(Vector3.UP).normalized() * s - Vector3.UP * s)
	mesh.surface_end()

	var scene := player.get_tree().current_scene
	scene.add_child(marker)

	var tween := marker.create_tween()
	tween.tween_interval(0.1)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.15)
	tween.tween_callback(marker.queue_free)
