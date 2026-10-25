class_name EyeHud
extends CanvasLayer

## Single HUD owner: debug readout, crosshair, scope overlay, weapon status and
## hit marker.
##
## Everything is resolved through groups (`player`, `weapon_controller`,
## `threat_detector`) so replacing the player or loadout does not require scene
## path edits. The stats text refreshes at a fixed interval; scope/crosshair
## feedback updates every frame because it is visual, not diagnostic.

@export var update_interval: float = 0.1
@export var player_group: StringName = &"player"
@export var detector_group: StringName = &"threat_detector"
@export var controller_group: StringName = &"weapon_controller"

@onready var _position_label: Label = $Stats/Position
@onready var _state_label: Label = $Stats/State
@onready var _speed_label: Label = get_node_or_null("Stats/Speed") as Label
@onready var _fps_label: Label = $Stats/Fps
@onready var _threat_label: Label = get_node_or_null("Stats/Threat") as Label
@onready var _highlight_label: Label = get_node_or_null("Stats/Highlight") as Label
@onready var _crosshair: Control = get_node_or_null("CrosshairCenter/Crosshair") as Control
@onready var _scope_overlay: ColorRect = get_node_or_null("ScopeOverlay") as ColorRect
@onready var _weapon_status: Label = get_node_or_null("WeaponStatus") as Label
@onready var _hit_marker: Label = get_node_or_null("HitMarkerCenter/HitMarker") as Label

var _player: EyePlayer
var _detector: ThreatDetector
var _controller: WeaponController
var _scope_material: ShaderMaterial

var _elapsed := 0.0
var _status_elapsed := 0.0
var _hit_timer := 0.0
var _hit_color := Color.WHITE

var _last_status := ""


func _ready() -> void:
	# The HUD is display-only. Without this, a centered crosshair label can eat
	# mouse-motion events and make looking around feel frozen.
	_ignore_mouse(self)
	_resolve_player()
	_resolve_detector()
	_resolve_controller()
	_refresh()

	if _scope_overlay != null:
		_scope_material = _scope_overlay.material as ShaderMaterial
		if _scope_material != null and _player != null and _player.config != null:
			_scope_material.set_shader_parameter("radius", _player.config.scope_overlay_radius)
			_scope_material.set_shader_parameter(
				"line_width", _player.config.scope_overlay_line_width
			)
			_scope_material.set_shader_parameter(
				"reticle_color", _player.config.scope_overlay_color
			)
			_scope_material.set_shader_parameter("intensity", 0.0)
		_scope_overlay.visible = false

	if _hit_marker != null:
		_hit_marker.visible = false


func _ignore_mouse(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_mouse(child)


func _process(delta: float) -> void:
	_elapsed += delta
	_status_elapsed += delta
	if _elapsed >= update_interval:
		_elapsed = 0.0
		_refresh()

	if _status_elapsed >= 0.05:
		_status_elapsed = 0.0
		_refresh_weapon_status()

	_update_scope(delta)


func _resolve_player() -> void:
	if player_group != &"":
		_player = get_tree().get_first_node_in_group(player_group) as EyePlayer


func _resolve_detector() -> void:
	if detector_group == &"":
		return
	var node := get_tree().get_first_node_in_group(detector_group)
	if node is ThreatDetector:
		_detector = node


func _resolve_controller() -> void:
	if controller_group == &"":
		return
	var node := get_tree().get_first_node_in_group(controller_group) as WeaponController
	if node == _controller:
		return
	if _controller != null and is_instance_valid(_controller):
		if _controller.hit_confirmed.is_connected(_on_hit_confirmed):
			_controller.hit_confirmed.disconnect(_on_hit_confirmed)
	_controller = node
	if _controller != null and not _controller.hit_confirmed.is_connected(_on_hit_confirmed):
		_controller.hit_confirmed.connect(_on_hit_confirmed)


func _refresh() -> void:
	if _player == null or not is_instance_valid(_player):
		_resolve_player()
	_resolve_controller()

	var position := Vector3.ZERO
	var state := "—"
	var speed := 0.0
	if _player != null:
		position = _player.global_position
		speed = _player.get_horizontal_speed()
		var machine: Object = _player.get("state_machine")
		if machine != null and "current_name" in machine:
			state = String(machine.current_name)

	_position_label.text = "POS    %.1f, %.1f, %.1f" % [position.x, position.y, position.z]
	_state_label.text = "STATE  %s" % state
	if _speed_label != null:
		_speed_label.text = "SPD    %.1f" % speed
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


func _refresh_weapon_status() -> void:
	if _weapon_status == null:
		return
	if _controller == null or not is_instance_valid(_controller):
		_resolve_controller()
	var text := ""
	if _controller != null:
		text = _controller.get_status_text()
	if text == _last_status:
		return
	_last_status = text
	_weapon_status.text = text
	_weapon_status.visible = not text.is_empty()


func _update_scope(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_resolve_player()

	var blend := 0.0
	if _player != null:
		blend = clampf(_player.scope_blend, 0.0, 1.0)

	if _crosshair != null:
		_crosshair.visible = blend < 0.98
		_crosshair.modulate.a = 1.0 - blend

	if _scope_overlay != null and _scope_material != null:
		var opacity := _player.config.scope_overlay_opacity if _player != null else 1.0
		_scope_material.set_shader_parameter("intensity", blend * opacity)
		var viewport_size := get_viewport().get_visible_rect().size
		if viewport_size.y > 0.0:
			_scope_material.set_shader_parameter(
				"aspect_ratio", viewport_size.x / viewport_size.y
			)
		_scope_overlay.visible = blend > 0.001

	if _hit_marker != null:
		if _hit_timer <= 0.0:
			_hit_marker.visible = false
		else:
			_hit_timer -= delta
			_hit_marker.visible = true
			var duration := _player.config.hit_marker_time if _player != null else 0.16
			var alpha := clampf(_hit_timer / maxf(duration, 0.001), 0.0, 1.0)
			_hit_marker.modulate = Color(_hit_color.r, _hit_color.g, _hit_color.b, alpha)


func _on_hit_confirmed(killed: bool) -> void:
	_hit_timer = _player.config.hit_marker_time if _player != null else 0.16
	_hit_color = Color(1.0, 0.25, 0.2) if killed else Color.WHITE
