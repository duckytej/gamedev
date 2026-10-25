class_name PlayerState
extends Node

## Base class for a single movement state.
##
## Each state is an independent child node of the player's `States` node; the
## [PlayerStateMachine] enters and exits them. A state reads the player's input
## snapshot, mutates `player.velocity`, and asks the machine for a transition.
## It never calls `move_and_slide()` (the player does that exactly once per tick).

var player: EyePlayer
var machine: PlayerStateMachine


## Called by the machine once, when the states are registered.
func setup(owner_player: EyePlayer, owner_machine: PlayerStateMachine) -> void:
	player = owner_player
	machine = owner_machine


## Called when this state becomes the active state.
func enter(_msg: Dictionary = {}) -> void:
	pass


## Called when leaving this state.
func exit() -> void:
	pass


## Per-physics-frame update while active.
func physics_update(_delta: float) -> void:
	pass


## Raw input forwarded while active (mouse look is handled by the player).
func handle_input(_event: InputEvent) -> void:
	pass


## Starts a grapple when the optional ability exists and has a target. Shared by
## every movement state so the input rule cannot drift between them.
func try_start_grapple() -> bool:
	if player.input.grapple_just_pressed and player.can_grapple():
		machine.transition_to(&"Grapple")
		return true
	return false


## Crouched locomotion uses the dedicated crouch speed instead of walk speed.
func locomotion_speed(speed: float) -> float:
	if player.input.crouch_pressed:
		return minf(speed, player.config.crouch_speed)
	return speed
