extends Node
class_name ProjectionController

## Applies a [ProjectionProfile] to the vendored `screenspace_projection` addon.
##
## This is the ONLY place in the game that talks to the lens addon, and it does
## so through duck-typed `Object.set()` (see [ProjectionProfile]): no scene
## overrides, no addon edits, no shader tweaking. Change the profile resource and
## the look changes.
##
## The node it configures is found one of two ways:
## - `projection_path`: explicit path, if you want to be unambiguous.
## - otherwise the first node in `projection_group` (default `"projection"`).
##
## Camera FOV is intentionally not set here. The addon reads the active
## [Camera3D] every frame, and FOV is authored in [PlayerConfig].

## The lens look. Everything the addon exposes comes from here.
@export var profile: ProjectionProfile:
	set(value):
		if profile == value:
			return
		_disconnect_profile()
		profile = value
		_connect_profile()
		if is_inside_tree():
			_apply()

## Optional explicit path to the `screenspace_projection` node. Leave empty to
## resolve by group instead.
@export_node_path("Node3D") var projection_path: NodePath

## Group used to find the projection node when `projection_path` is empty.
@export var projection_group: StringName = &"projection"

var _projection: Object


func _ready() -> void:
	_projection = _resolve_projection()
	if _projection == null:
		push_warning(
			"ProjectionController: no projection node found (path='%s', group='%s')."
			% [projection_path, projection_group]
		)
		return
	_connect_profile()
	_apply()


func _exit_tree() -> void:
	_disconnect_profile()


## Re-read the profile and push it to the addon immediately.
func refresh() -> void:
	_apply()


func _resolve_projection() -> Object:
	if not projection_path.is_empty():
		return get_node_or_null(projection_path)
	if projection_group != &"":
		return get_tree().get_first_node_in_group(projection_group)
	return null


func _apply() -> void:
	if profile == null:
		return
	if _projection == null or not is_instance_valid(_projection):
		_projection = _resolve_projection()
	if _projection == null:
		return

	profile.apply_to(_projection)

	# The addon re-pushes shader uniforms on its own `_process`, but do it now so
	# the very first rendered frame already reflects the profile.
	if _projection.has_method("_apply_shader_params"):
		_projection.call("_apply_shader_params")


func _connect_profile() -> void:
	if profile != null and not profile.changed.is_connected(_on_profile_changed):
		profile.changed.connect(_on_profile_changed)


func _disconnect_profile() -> void:
	if profile != null and profile.changed.is_connected(_on_profile_changed):
		profile.changed.disconnect(_on_profile_changed)


func _on_profile_changed() -> void:
	_apply()
