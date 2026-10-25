class_name HudStats
extends VBoxContainer

## Top-corner debug readout: player position, current movement state, FPS and the
## peripheral-vision threat line (nearest object's angle, distance and LOS).
##
## Pulls the player and the [ThreatDetector] from groups, so it keeps working
## when those scenes change. Updates on a fixed interval instead of every frame
## to keep text churn (and its cost) negligible.

## Seconds between refreshes.
@export var update_interval: float = 0.1

## Group the player node belongs to.
@export var player_group: StringName = &"player"

## Group the threat detector belongs to.
@export var detector_group: StringName = &"threat_detector"

@onready var _position_label: Label = $Position
@onready var _state_label: Label = $State
@onready var _fps_label: Label = $Fps
@onready var _threat_label: Label = get_node_or_null("Threat")
@onready var _highlight_label: Label = get_node_or_null("Highlight")

var _player: Node
var _detector: ThreatDetector
var _elapsed: float = 0.0


func _ready() -> void:
	_resolve_player()
	_resolve_detector()
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


func _resolve_detector() -> void:
	if detector_group == &"":
		return
	var node: Node = get_tree().get_first_node_in_group(detector_group)
	if node is ThreatDetector:
		_detector = node


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

	if _detector == null or not is_instance_valid(_detector):
		_resolve_detector()
	if _threat_label != null:
		_threat_label.text = "TGT    %s" % (
			String(_detector.debug_text) if _detector != null else "—"
		)
	if _highlight_label != null:
		_highlight_label.text = "HILITE %d" % (
			_detector.eligible_count if _detector != null else 0
		)
