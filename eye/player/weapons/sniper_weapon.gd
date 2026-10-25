class_name SniperWeapon
extends GunWeapon

## Charged scope sniper.
##
## - Hold RMB to scope (handled by [WeaponController]).
## - LMB begins a charge; release fires.
## - Low charge: slow projectile with visible travel, gravity (bullet drop) and a
##   small collision sphere. Player velocity is inherited.
## - High charge: faster/flatter projectile and a larger hit sphere.
## - At `sniper_hitscan_threshold` the shot becomes a swept-sphere hit-scan.
## - Firing within `sniper_quickscope_window` of scoping is an exact hit-scan
##   along the crosshair: no spread, drop or movement inheritance.
##
## Every projectile shot factors **both** ballistics at once: the aim direction
## gets the player's inherited velocity (movement direction), then the projectile
## integrates gravity (bullet drop). The preview uses the same launch-velocity
## helper, speed and gravity, and switches to the same shape-cast used by the
## hit-scan shot at full charge.

const SNIPER_SCENE := preload("res://combat/projectiles/sniper_projectile.tscn")

var _scoped := false
var _charging := false
var _charge := 0.0
var _scope_time := 0.0
var _preview_timer := 0.0

## Test/debug readout: was the most recent accepted shot a quickscope?
var last_shot_quickscope := false

var _preview: MeshInstance3D


func _on_setup() -> void:
	configure_gun(
		player.config.sniper_magazine_size,
		player.config.sniper_reload_time,
		player.config.sniper_stamina_cost
	)
	_build_preview.call_deferred()


func _exit_tree() -> void:
	if is_instance_valid(_preview):
		_preview.queue_free()


func set_scoped(value: bool) -> void:
	_scoped = value
	if not _scoped:
		cancel_charge()
		_hide_preview()
		_scope_time = 0.0
	else:
		_scope_time = 0.0
		_preview_timer = player.config.sniper_preview_interval if player != null else 0.04


func begin_charge() -> void:
	if not can_use() or not _scoped:
		return
	if is_reloading() or ammo <= 0:
		begin_reload()
		return
	_charging = true
	_charge = 0.0
	_preview_timer = 0.0


func cancel_charge() -> void:
	_charging = false
	_charge = 0.0


func update(delta: float) -> void:
	super.update(delta)
	if not _scoped or player == null:
		_hide_preview()
		return

	if _scope_time < player.config.sniper_quickscope_window:
		_scope_time += delta
	else:
		_scope_time = player.config.sniper_quickscope_window

	if _charging:
		_charge = minf(
			_charge + delta / maxf(player.config.sniper_charge_time, 0.001), 1.0
		)

	_preview_timer += delta
	if _preview_timer >= player.config.sniper_preview_interval:
		_preview_timer = 0.0
		_update_preview()


func release_charge() -> void:
	if not _charging:
		return
	var charge := _charge
	cancel_charge()
	_fire(charge)
	_update_preview()


func get_status_text() -> String:
	if is_reloading():
		return "SNIPER  " + get_ammo_text()
	if _charging:
		if _charge >= player.config.sniper_hitscan_threshold:
			return "SNIPER  FULL  " + get_ammo_text()
		return "SNIPER  %3d%%  %s" % [int(round(_charge * 100.0)), get_ammo_text()]
	if _scoped and is_quickscope_ready():
		return "SNIPER  QUICKSCOPE  " + get_ammo_text()
	return "SNIPER  READY  " + get_ammo_text()


func is_quickscope_ready() -> bool:
	return _scoped and _scope_time < player.config.sniper_quickscope_window


func get_charge() -> float:
	return _charge


func is_charging() -> bool:
	return _charging


## Shared launch velocity for the real shot and the scope preview. It contains
## both the player's movement contribution and the direction that gravity will
## bend; neither replaces the other.
func get_launch_velocity(direction: Vector3, charge: float) -> Vector3:
	var speed := lerpf(
		player.config.sniper_min_speed, player.config.sniper_max_speed, charge
	)
	return direction * speed + player.velocity * player.config.sniper_velocity_inherit


func _fire(charge: float) -> void:
	last_shot_quickscope = false
	var quickscope := is_quickscope_ready()
	if not try_fire():
		return

	var origin := controller.get_camera_origin()
	var direction := controller.get_aim_direction()
	var range := player.config.sniper_range
	var max_radius := player.config.sniper_max_hit_radius
	var damage := lerpf(
		player.config.sniper_min_damage, player.config.sniper_max_damage, charge
	)

	if quickscope:
		last_shot_quickscope = true
		damage = maxf(damage, player.config.sniper_quickscope_damage)
		_fire_quickscope(origin, direction, range, damage)
	elif charge >= player.config.sniper_hitscan_threshold:
		_fire_hitscan(origin, direction, range, max_radius, damage)
	else:
		_fire_projectile(origin, direction, charge, damage)

	controller.flash_muzzle(player.config.muzzle_flash_color)
	controller.apply_recoil(player.config.sniper_recoil)


## Quickscope: an exact ray from the camera. No shape radius, player-velocity
## inheritance, gravity or spread is involved.
func _fire_quickscope(
	origin: Vector3, direction: Vector3, range: float, damage: float
) -> void:
	var hit := controller.raycast(origin, direction, range)
	var end := origin + direction * range
	if not hit.is_empty():
		end = hit.position
		var health := Damage.find_health(hit.collider)
		var accepted := Damage.apply(hit.collider, damage, player, hit.position, hit.normal)
		if accepted:
			controller.report_hit(health != null and not health.is_alive())
		controller.spawn_impact(hit.position, hit.normal, player.config.impact_color)
	controller.spawn_tracer(
		controller.get_muzzle_position(), end, player.config.sniper_tracer_color
	)


func _fire_hitscan(
	origin: Vector3, direction: Vector3, range: float, radius: float, damage: float
) -> void:
	var hit := controller.shape_cast(origin, direction, range, radius)
	var end := origin + direction * range
	if not hit.is_empty():
		end = hit.position
		var health := Damage.find_health(hit.collider)
		var accepted := Damage.apply(hit.collider, damage, player, hit.position, hit.normal)
		if accepted:
			controller.report_hit(health != null and not health.is_alive())
		controller.spawn_impact(hit.position, hit.normal, player.config.impact_color)
	controller.spawn_tracer(
		controller.get_muzzle_position(), end, player.config.sniper_tracer_color
	)


func _fire_projectile(
	origin: Vector3, direction: Vector3, charge: float, damage: float
) -> void:
	var speed := lerpf(
		player.config.sniper_min_speed, player.config.sniper_max_speed, charge
	)
	var radius := lerpf(
		player.config.sniper_min_hit_radius, player.config.sniper_max_hit_radius, charge
	)
	# Movement direction (inherited velocity) and bullet drop (projectile
	# gravity) are both active on every projectile shot.
	var velocity := get_launch_velocity(direction, charge)

	var projectile := SNIPER_SCENE.instantiate() as Projectile
	if projectile == null:
		return
	projectile.setup(
		velocity,
		player.config.sniper_gravity_scale,
		damage,
		radius,
		player.config.sniper_range / maxf(speed, 1.0) + 1.5,
		player
	)
	projectile.hit_confirmed.connect(controller.report_hit)
	projectile.impacted.connect(_on_projectile_impact)

	var parent := player.get_parent()
	if parent == null:
		projectile.queue_free()
		return
	parent.add_child(projectile)
	# Spawn from the camera, not the cosmetic muzzle. The preview predicts from
	# the camera, so this keeps the green dot honest at close range.
	projectile.global_position = origin

	# Short launch streak so the shot reads even before the projectile arrives.
	controller.spawn_tracer(
		controller.get_muzzle_position(),
		controller.get_muzzle_position() + direction * 10.0,
		player.config.sniper_tracer_color
	)


func _on_projectile_impact(point: Vector3, normal: Vector3) -> void:
	if player == null:
		return
	controller.spawn_impact(point, normal, player.config.impact_color)


# --- Prediction ---------------------------------------------------------------

func _update_preview() -> void:
	if not _scoped or player == null:
		_hide_preview()
		return

	var origin := controller.get_camera_origin()
	var direction := controller.get_aim_direction()

	if _charge >= player.config.sniper_hitscan_threshold:
		var hit := controller.shape_cast(
			origin, direction, player.config.sniper_range,
			player.config.sniper_max_hit_radius
		)
		if hit.is_empty():
			_hide_preview()
		else:
			_show_preview(hit.position, hit.normal)
		return

	var speed := lerpf(
		player.config.sniper_min_speed, player.config.sniper_max_speed, _charge
	)
	var velocity := get_launch_velocity(direction, _charge)
	var gravity := player.get_gravity() * player.config.sniper_gravity_scale
	var step := 1.0 / float(Engine.physics_ticks_per_second)
	var position := origin
	var elapsed := 0.0

	for _index in player.config.sniper_preview_steps:
		if elapsed >= player.config.sniper_preview_max_time:
			break

		# Must match Projectile._physics_process: gravity first, then move.
		velocity += gravity * step
		var next := position + velocity * step
		var segment := next - position
		var distance := segment.length()
		if distance > 0.0001:
			var hit := controller.raycast(position, segment / distance, distance)
			if not hit.is_empty():
				_show_preview(hit.position, hit.normal)
				return
		position = next
		elapsed += step

	_hide_preview()


func _show_preview(point: Vector3, normal: Vector3) -> void:
	if _preview == null:
		return
	_preview.global_position = point + normal * 0.02
	_preview.visible = true


func _hide_preview() -> void:
	if _preview != null:
		_preview.visible = false


func _build_preview() -> void:
	var parent := player.get_parent() if player != null else null
	if parent == null:
		return

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = player.config.sniper_preview_color
	material.emission_enabled = true
	material.emission = player.config.sniper_preview_color
	material.emission_energy_multiplier = 4.0
	material.no_depth_test = true

	var mesh := SphereMesh.new()
	mesh.radius = player.config.sniper_preview_radius
	mesh.height = player.config.sniper_preview_radius * 2.0
	mesh.radial_segments = 10
	mesh.rings = 6

	_preview = MeshInstance3D.new()
	_preview.name = "SniperImpactPreview"
	_preview.mesh = mesh
	_preview.material_override = material
	_preview.top_level = true
	_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_preview.visible = false
	parent.add_child(_preview)
