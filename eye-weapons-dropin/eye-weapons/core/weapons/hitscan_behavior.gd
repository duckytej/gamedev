class_name HitscanBehavior
extends WeaponBehavior
## Instant raycast shot (pistol / AR / shotgun / sniper).
## Spawns a tracer + impact point; damage goes through deal_damage().

func fire(origin: Vector3, dir: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * res.range)
	# everything except the player (layer 1)
	query.collision_mask = 0b1110
	var player := manager.get_parent() as CollisionObject3D
	if player != null:
		query.exclude = [player.get_rid()]
	var hit := space.intersect_ray(query)
	var end := origin + dir * res.range
	if not hit.is_empty():
		end = hit.position
		deal_damage(hit.collider, res.damage)
		_impact_fx(end, hit.normal)
	_spawn_tracer(manager.muzzle_position(), end)
	# hook here: muzzle flash light, Audio.play("shot_<name>")


func _spawn_tracer(a: Vector3, b: Vector3) -> void:
	var length := a.distance_to(b)
	if length < 0.5:
		return
	var tracer := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.025, 0.025, length)
	tracer.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.85, 0.4)
	tracer.material_override = mat
	manager.get_tree().current_scene.add_child(tracer)
	tracer.global_transform = Transform3D(Basis.looking_at(b - a), (a + b) * 0.5)
	manager.get_tree().create_timer(0.06).timeout.connect(tracer.queue_free)


func _impact_fx(pos: Vector3, _normal: Vector3) -> void:
	# minimal impact spark. replace with your VFX (Obssidian pack etc.)
	var spark := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.06
	mesh.height = 0.12
	spark.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.7, 0.2)
	spark.material_override = mat
	manager.get_tree().current_scene.add_child(spark)
	spark.global_position = pos
	var tw := spark.create_tween()
	tw.tween_property(spark, "scale", Vector3.ZERO, 0.15)
	tw.tween_callback(spark.queue_free)
