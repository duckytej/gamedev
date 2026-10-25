extends Node
class_name ProjectionController

## Applies the lens section of [GameConfig] to the vendored
## `screenspace_projection` addon.
##
## This is the ONLY place in the game that talks to the lens addon, and it does
## so through duck-typed `Object.set()`: no scene overrides, no addon edits, no
## shader tweaking. Change `core/config/game_config.tres` and the look changes.
##
## The node it configures is found one of two ways:
## - `projection_path`: explicit path, if you want to be unambiguous.
## - otherwise the first node in `projection_group` (default `"projection"`).
##
## Camera FOV is intentionally not set here. The addon reads the active
## [Camera3D] every frame, and FOV is authored as [member GameConfig.base_fov].

## Shared tuning resource. Everything the addon exposes comes from here.
@export var config: GameConfig:
	set(value):
		if config == value:
			return
		_disconnect_config()
		config = value
		_connect_config()
		if is_inside_tree():
			_apply()

## Optional explicit path to the `screenspace_projection` node. Leave empty to
## resolve by group instead.
@export_node_path("Node3D") var projection_path: NodePath

## Group used to find the projection node when `projection_path` is empty.
@export var projection_group: StringName = &"projection"

var _projection: Object


func _ready() -> void:
	if config == null:
		config = GameConfig.new()
		push_warning("ProjectionController: no GameConfig assigned; using defaults.")

	_projection = _resolve_projection()
	if _projection == null:
		push_warning(
			"ProjectionController: no projection node found (path='%s', group='%s')."
			% [projection_path, projection_group]
		)
		return
	_connect_config()
	_apply()


func _exit_tree() -> void:
	_disconnect_config()


## Re-read the config and push it to the addon immediately.
func refresh() -> void:
	_apply()


func _resolve_projection() -> Object:
	if not projection_path.is_empty():
		return get_node_or_null(projection_path)
	if projection_group != &"":
		return get_tree().get_first_node_in_group(projection_group)
	return null


func _apply() -> void:
	if config == null:
		return
	if _projection == null or not is_instance_valid(_projection):
		_projection = _resolve_projection()
	if _projection == null:
		return

	# One direct, type-checked assignment per addon property. No mapping table and
	# no duplicated runtime fields, so a typo is a compile error rather than a
	# silent warning at runtime.
	_projection.set("enabled", config.lens_enabled)
	_projection.set("projection_mode", config.projection_mode)
	_projection.set("strength", config.lens_strength)
	_projection.set("fill", config.lens_fill)
	_projection.set("panini_s", config.lens_panini_s)
	_projection.set("upscale", config.lens_upscale)
	_projection.set("supersample_upscale_amount", config.lens_supersample)
	_projection.set("max_major_radius", config.lens_max_major_radius)
	_projection.set("max_minor_radius", config.lens_max_minor_radius)
	_projection.set("ca_amount", config.ca_amount)
	_projection.set("ca_amount_spread", config.ca_spread)
	_projection.set("ca_reference_wavelength", config.ca_reference_wavelength)
	_projection.set("ca_enable_start", config.ca_enable_start)
	_projection.set("ca_jitter", config.ca_jitter)
	_projection.set("ca_max_samples", config.ca_max_samples)
	_projection.set("ca_samples_per_ca", config.ca_samples_per_ca)
	_projection.set("vignette_strength", config.vignette_strength)
	_projection.set("vignette_spread", config.vignette_spread)

	# The addon re-pushes shader uniforms on its own `_process`, but do it now so
	# the very first rendered frame already reflects the config.
	if _projection.has_method("_apply_shader_params"):
		_projection.call("_apply_shader_params")


func _connect_config() -> void:
	if config != null and not config.changed.is_connected(_on_config_changed):
		config.changed.connect(_on_config_changed)


func _disconnect_config() -> void:
	if config != null and config.changed.is_connected(_on_config_changed):
		config.changed.disconnect(_on_config_changed)


func _on_config_changed() -> void:
	_apply()
