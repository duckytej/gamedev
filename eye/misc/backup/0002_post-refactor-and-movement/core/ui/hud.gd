class_name HudStats
extends VBoxContainer

## Top-corner debug readout: player position, current movement state and FPS.
##
## Pulls the player from a group, so it keeps working when the player scene
## changes. Updates on a fixed interval instead of every frame to keep text
## churn (and its cost) negligible.

## Seconds between refreshes.
@export var update_interval: float = 0.1

## Group the player node belongs to.
@export var player_group: StringName = &"player"

@onready var _position_label: Label = $Position
@onready var _state_label: Label = $State
@onready var _fps_label: Label = $Fps

var _player: Node
var _elapsed: float = 0.0


func _ready() -> void:
	_resolve_player()
	_refresh()


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < update_interval:
		return
	_elapsed = 0.0
	_refresh()


func _resolve_player() -> void:
	if player_group == &"":
		return
	_player = get_tree().get_first_node_in_group(player_group)


func _refresh() -> void:
	if _player == null or not is_instance_valid(_player):
		_resolve_player()

	var position := Vector3.ZERO
	var state := "—"
	if _player != null:
		position = _player.global_position
		var machine: Object = _player.get("state_machine")
		if machine != null and "current_name" in machine:
			state = String(machine.current_name)

	_position_label.text = "POS    %.1f, %.1f, %.1f" % [position.x, position.y, position.z]
	_state_label.text = "STATE  %s" % state
	_fps_label.text = "FPS    %d" % Engine.get_frames_per_second()
