class_name GunWeapon
extends WeaponBase

## Shared magazine/reload/stamina behaviour for the firearm weapons.
##
## `WeaponController` owns input; this class owns the round count. Reloading
## starts automatically when the magazine is empty (or manually through the
## controller), and the controller can halve the remaining time on a melee
## quickswitch or refill every magazine with an overhealth burst.

var magazine_size: int = 1
var ammo: int = 0
var reload_time: float = 1.0
var stamina_cost: float = 0.0

var _reloading := false
var _reload_remaining := 0.0


func configure_gun(size: int, time: float, cost: float) -> void:
	magazine_size = maxi(size, 1)
	reload_time = maxf(time, 0.01)
	stamina_cost = maxf(cost, 0.0)
	ammo = magazine_size
	_reloading = false
	_reload_remaining = 0.0


func update(delta: float) -> void:
	if _reloading:
		_reload_remaining = maxf(_reload_remaining - delta, 0.0)
		if _reload_remaining <= 0.0:
			_finish_reload()
		return
	if ammo <= 0:
		begin_reload()


## Checks the magazine, reload state and stamina, then consumes one round.
## Returns false when the trigger pull should not produce a shot.
func try_fire() -> bool:
	if not can_use() or _reloading:
		return false
	if ammo <= 0:
		begin_reload()
		return false
	if player.vitals != null and not player.vitals.try_spend_stamina(stamina_cost):
		return false
	ammo = maxi(ammo - 1, 0)
	return true


func begin_reload() -> void:
	if _reloading or ammo >= magazine_size:
		return
	_reloading = true
	_reload_remaining = reload_time


func cancel_reload() -> void:
	_reloading = false
	_reload_remaining = 0.0


## Quickswitching through melee cuts the remaining reload by `factor`.
func shorten_reload(factor: float) -> void:
	if not _reloading:
		return
	_reload_remaining *= clampf(factor, 0.0, 1.0)
	if _reload_remaining <= 0.0:
		_finish_reload()


func refill_ammo() -> void:
	_reloading = false
	_reload_remaining = 0.0
	ammo = magazine_size


func is_reloading() -> bool:
	return _reloading


func get_reload_remaining() -> float:
	return _reload_remaining


func get_ammo_text() -> String:
	if _reloading:
		return "%d/%d  RELOAD" % [ammo, magazine_size]
	return "%d/%d" % [ammo, magazine_size]


func _finish_reload() -> void:
	_reloading = false
	_reload_remaining = 0.0
	ammo = magazine_size
