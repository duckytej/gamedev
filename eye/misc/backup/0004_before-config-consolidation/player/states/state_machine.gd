class_name PlayerStateMachine
extends Node

## Node-based state machine for the player's movement.
##
## Children of this node are [PlayerState] instances; each child's node name is
## its state name. The machine owns no physics: the player drives it once per
## physics tick and later calls `move_and_slide()`.

signal state_changed(previous: StringName, current: StringName)

## State to enter when the player spawns. Must match a child node name.
@export var initial_state: StringName = &"Idle"

var current: PlayerState
var current_name: StringName = &""
var previous_name: StringName = &""

var _states: Dictionary = {}
var _player: EyePlayer


func setup(player: EyePlayer) -> void:
	_player = player
	for child in get_children():
		if child is PlayerState:
			child.setup(player, self)
			_states[StringName(child.name)] = child
	transition_to(initial_state)


## Switch to the state named `name`. No-op if it is already active.
func transition_to(name: StringName, msg: Dictionary = {}) -> void:
	if not _states.has(name):
		push_warning("PlayerStateMachine: no state named '%s'." % name)
		return

	var next: PlayerState = _states[name]
	if next == current:
		return

	if current != null:
		current.exit()

	previous_name = current_name
	current = next
	current_name = name
	current.enter(msg)
	state_changed.emit(previous_name, current_name)


func physics_update(delta: float) -> void:
	if current != null:
		current.physics_update(delta)


func handle_input(event: InputEvent) -> void:
	if current != null:
		current.handle_input(event)


func has_state(name: StringName) -> bool:
	return _states.has(name)
