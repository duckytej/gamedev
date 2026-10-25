class_name PlayerAbility
extends Node3D

## Base class for optional player modules.
##
## Abilities live as children of `Player/Abilities` and are discovered by
## [PlayerAbilityHost]. Dropping a node in enables the feature; deleting it
## disables it without touching the movement states or the player script.
##
## Two update phases exist because ordering matters:
## - [method pre_move_update] runs after input sampling but before the movement
##   state machine (sensing, target acquisition).
## - [method post_move_update] runs after `move_and_slide()` and the camera
##   update (weapons, rope visuals), so effects use the final frame pose.

## Identifier used by [method PlayerAbilityHost.get_ability]. Keep unique.
@export var ability_id: StringName = &""

## Allows disabling an ability from the inspector while keeping it in the scene.
@export var enabled: bool = true

var player: EyePlayer


func setup(owner_player: EyePlayer) -> void:
	player = owner_player
	if enabled:
		_on_setup()


## Called once, after [member player] is assigned.
func _on_setup() -> void:
	pass


func pre_move_update(_delta: float) -> void:
	pass


func post_move_update(_delta: float) -> void:
	pass
