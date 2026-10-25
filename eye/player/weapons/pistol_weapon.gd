class_name PistolWeapon
extends GunWeapon

## Hit-scan sidearm with very low damage. One shot per click (no auto-fire);
## the cooldown only limits click-spamming and is fully config-driven. Uses the
## shared magazine/reload/stamina rules from [GunWeapon].

var _cooldown := 0.0


func _on_setup() -> void:
	configure_gun(
		player.config.pistol_magazine_size,
		player.config.pistol_reload_time,
		player.config.pistol_stamina_cost
	)


func update(delta: float) -> void:
	super.update(delta)
	_cooldown = maxf(_cooldown - delta, 0.0)


func on_primary_pressed() -> void:
	if not can_use() or _cooldown > 0.0:
		return
	if not try_fire():
		return
	_cooldown = player.config.pistol_fire_interval

	var origin := controller.get_camera_origin()
	var direction := controller.get_aim_direction()
	direction = _apply_spread(direction)

	var hit := controller.raycast(origin, direction, player.config.pistol_range)
	var end := origin + direction * player.config.pistol_range
	if not hit.is_empty():
		end = hit.position
		var accepted := Damage.apply(
			hit.collider,
			player.config.pistol_damage,
			player,
			hit.position,
			hit.normal
		)
		if accepted:
			var health := Damage.find_health(hit.collider)
			controller.report_hit(health != null and not health.is_alive())
		controller.spawn_impact(hit.position, hit.normal, player.config.impact_color)

	controller.spawn_tracer(controller.get_muzzle_position(), end, player.config.tracer_color)
	controller.flash_muzzle(player.config.muzzle_flash_color)
	controller.apply_recoil(player.config.pistol_recoil)


func get_status_text() -> String:
	return "PISTOL  " + get_ammo_text()


func _apply_spread(direction: Vector3) -> Vector3:
	var spread := deg_to_rad(player.config.pistol_spread_degrees)
	if spread <= 0.0:
		return direction
	var basis := player.camera.global_transform.basis
	return (direction
		+ basis.x * randf_range(-spread, spread)
		+ basis.y * randf_range(-spread, spread)).normalized()
