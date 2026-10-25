class_name WeaponBase
extends Node

## Base class for modular weapons.
##
## A weapon is a plain child node of [WeaponController]. It owns its cooldown and
## mechanics, but all shared services (camera pose, ray queries, tracers, muzzle
## flash, hit feedback) live in the controller. Removing a weapon node removes
## that weapon from the loadout; no `match` statement or enum needs editing.
##
## Input is routed by the controller using [PlayerInput] snapshots, so weapons
## never poll `Input` and remain deterministic for tests.

@export var enabled: bool = true

var player: EyePlayer
var controller: WeaponController


func setup(owner_player: EyePlayer, owner_controller: WeaponController) -> void:
	player = owner_player
	controller = owner_controller
	_on_setup()


func _exit_tree() -> void:
	# Let the controller drop this weapon from its cached loadout immediately.
	# Deleting a weapon node therefore disables it without leaving stale (freed)
	# references in the input router.
	if controller != null and is_instance_valid(controller):
		controller._on_weapon_removed(self)


## Called once after [member player] and [member controller] are assigned.
func _on_setup() -> void:
	pass


func can_use() -> bool:
	return enabled and player != null and is_instance_valid(player) and controller != null


## Called once when the primary fire button is pressed while not scoped.
func on_primary_pressed() -> void:
	pass


## Called once when the primary fire button is released while not scoped.
func on_primary_released() -> void:
	pass


## Called every tick, after the player and camera have moved.
func update(_delta: float) -> void:
	pass


func get_status_text() -> String:
	return ""
