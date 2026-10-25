class_name GrenadeWeapon
extends WeaponBase

## Held-throw grenade. A tap of LMB uses the pistol; holding past the configured
## threshold swaps to the grenade and charges throw speed. Release throws.
##
## The projectile is a separate scene node. Removing this weapon node removes
## both the charging behaviour and the projectile from the loadout.

const GRENADE_SCENE := preload("res://combat/projectiles/grenade_projectile.tscn")

var _charging := false
var _charge := 0.0


func _on_setup() -> void:
	_charging = false
	_charge = 0.0


func update(delta: float) -> void:
	if not _charging:
		return
	_charge = minf(
		_charge + delta / maxf(player.config.grenade_charge_time, 0.001), 1.0
	)


func begin_charge() -> void:
	if not can_use():
		return
	_charging = true
	_charge = 0.0


func cancel_charge() -> void:
	_charging = false
	_charge = 0.0


func release_charge() -> void:
	if not _charging or not can_use():
		cancel_charge()
		return

	var charge := _charge
	cancel_charge()

	var speed := lerpf(
		player.config.grenade_min_speed,
		player.config.grenade_max_speed,
		charge
	)
	var direction := controller.get_aim_direction()
	var velocity := direction * speed \
		+ player.velocity * player.config.grenade_velocity_inherit \
		+ Vector3.UP * player.config.grenade_throw_up

	var projectile := GRENADE_SCENE.instantiate() as GrenadeProjectile
	if projectile == null:
		return
	projectile.setup_grenade(
		velocity,
		player.config.grenade_gravity_scale,
		player.config.grenade_damage,
		player.config.grenade_min_damage,
		player.config.grenade_radius,
		player.config.grenade_fuse_time,
		player.config.grenade_lifetime,
		player.config.grenade_bounce,
		player.config.grenade_friction,
		player.config.grenade_explosion_color,
		player.config.grenade_explosion_light_energy,
		player.config.grenade_explosion_visual_time,
		player
	)
	projectile.damage_dealt.connect(controller.report_hit)

	var parent := player.get_parent()
	if parent == null:
		projectile.queue_free()
		return
	parent.add_child(projectile)
	projectile.global_position = controller.get_muzzle_position()

	controller.flash_muzzle(player.config.muzzle_flash_color)
	controller.apply_recoil(player.config.grenade_recoil * 0.5)


func get_status_text() -> String:
	if _charging:
		return "GRENADE  %3d%%" % int(round(_charge * 100.0))
	return "GRENADE  HOLD LMB"


func is_charging() -> bool:
	return _charging
