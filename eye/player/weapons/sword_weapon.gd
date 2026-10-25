class_name SwordWeapon
extends WeaponBase

## Melee weapon and parry tool.
##
## The controller equips the sword with the `melee` action. LMB makes a short
## swept-sphere strike; RMB opens a brief parry window. Enemies call
## [method EyePlayer.try_parry] before applying their shot, so a timed parry
## negates the hit and staggers the shooter.

var equipped := false

var _cooldown := 0.0
var _parry_time := 0.0
var _parry_cooldown := 0.0


func _on_setup() -> void:
	equipped = false
	_cooldown = 0.0
	_parry_time = 0.0
	_parry_cooldown = 0.0


func update(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	_parry_time = maxf(_parry_time - delta, 0.0)
	_parry_cooldown = maxf(_parry_cooldown - delta, 0.0)


func set_equipped(value: bool) -> void:
	equipped = value
	if not equipped:
		_parry_time = 0.0


func on_primary_pressed() -> void:
	if not can_use() or not equipped or _cooldown > 0.0:
		return
	if player.vitals != null \
			and not player.vitals.try_spend_stamina(player.config.sword_stamina_cost):
		return

	_cooldown = player.config.sword_fire_interval
	var origin := controller.get_camera_origin()
	var direction := controller.get_aim_direction()
	var hit := controller.shape_cast(
		origin, direction, player.config.sword_range, player.config.sword_hit_radius
	)
	var end := origin + direction * player.config.sword_range
	if not hit.is_empty():
		end = hit.position
		var health := Damage.find_health(hit.collider)
		var accepted := Damage.apply(
			hit.collider,
			player.config.sword_damage,
			player,
			hit.position,
			hit.normal
		)
		if accepted:
			controller.report_hit(health != null and not health.is_alive())
		controller.spawn_impact(hit.position, hit.normal, player.config.sword_tracer_color)

	controller.spawn_tracer(
		controller.get_muzzle_position(), end, player.config.sword_tracer_color
	)
	controller.apply_recoil(player.config.sword_recoil)


## Opens the timed parry window. Returns true when the parry actually started.
func begin_parry() -> bool:
	if not equipped or _parry_cooldown > 0.0:
		return false
	_parry_time = player.config.sword_parry_window
	_parry_cooldown = player.config.sword_parry_window + player.config.sword_parry_cooldown
	return true


func is_parrying() -> bool:
	return equipped and _parry_time > 0.0


func flash_parry() -> void:
	var forward := controller.get_aim_direction()
	var point := controller.get_camera_origin() + forward * 1.1
	controller.spawn_impact(point, -forward, player.config.sword_parry_color)


func get_status_text() -> String:
	if not equipped:
		return "SWORD"
	if is_parrying():
		return "SWORD  PARRY"
	if _parry_cooldown > 0.0:
		return "SWORD  PARRY %.1fs" % _parry_cooldown
	return "SWORD  LMB strike · RMB parry"


func get_parry_cooldown() -> float:
	return _parry_cooldown
