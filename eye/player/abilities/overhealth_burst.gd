class_name OverhealthBurst
extends PlayerAbility

## Spends the entire overhealth buffer on a radial stagger burst.
##
## The burst is only available while the buffer is more than half full (see
## [method PlayerVitals.can_burst]). It staggers every visible enemy in range,
## deals damage scaled by the buffer spent, and instantly refills every gun
## magazine, which is the "burst skips the reload" payoff.

func _on_setup() -> void:
	ability_id = &"burst" if ability_id == &"" else ability_id
	add_to_group(&"overhealth_burst")


func pre_move_update(_delta: float) -> void:
	if player == null or not player.input.burst_just_pressed:
		return
	trigger()


## Public so tests and other systems can invoke the burst deterministically.
func trigger() -> bool:
	if player == null or player.vitals == null or player.config == null:
		return false
	if not player.vitals.can_burst():
		return false

	var spent := player.vitals.consume_overhealth_for_burst()
	if spent <= 0.0:
		return false

	var config := player.config
	var damage := config.burst_damage + spent * config.burst_damage_per_overhealth
	var center := player.global_position + Vector3(0.0, 1.0, 0.0)

	for node in get_tree().get_nodes_in_group(&"enemy"):
		var enemy := node as Node3D
		if enemy == null or not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
			continue
		var target := enemy.global_position + Vector3(0.0, 0.9, 0.0)
		if center.distance_to(target) > config.burst_radius:
			continue
		if not _has_clear_line(center, target):
			continue
		if enemy.has_method("stagger"):
			enemy.call("stagger", config.burst_stagger_time)
		# Deliberately credit no player source: the burst consumes overhealth and
		# must not immediately refill the buffer it just spent.
		Damage.apply(enemy, damage, null, target, Vector3.UP)

	var weapons := player.get_weapons()
	if weapons != null:
		weapons.refill_all_ammo()

	player.add_recoil(3.0)
	_spawn_visual(center)
	return true


func _has_clear_line(from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.new()
	query.from = from
	query.to = to
	query.collision_mask = PhysicsLayers.WORLD
	query.exclude = [player.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty()


func _spawn_visual(center: Vector3) -> void:
	var holder := player.get_parent()
	if holder == null:
		return
	var config := player.config

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(
		config.burst_color.r, config.burst_color.g, config.burst_color.b, 0.42
	)
	material.emission_enabled = true
	material.emission = config.burst_color
	material.emission_energy_multiplier = 3.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED

	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 24
	sphere.rings = 12

	var ring := MeshInstance3D.new()
	ring.name = "OverhealthBurst"
	ring.mesh = sphere
	ring.material_override = material
	ring.top_level = true
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.scale = Vector3(0.25, 0.25, 0.25)
	holder.add_child(ring)
	ring.global_position = center

	var time := maxf(config.burst_visual_time, 0.05)
	var tween := ring.create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "scale", Vector3.ONE * config.burst_radius, time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(material, "albedo_color:a", 0.0, time)
	tween.chain().tween_callback(ring.queue_free)
