class_name PostFxController
extends ColorRect

## Applies the post-fx section of [GameConfig] to the full-screen post-lens pass.
##
## Lives on a full-rect `ColorRect` inside a low `CanvasLayer` in `world.tscn`,
## drawn after the projection output and before the HUD. It owns the pass, so the
## effect can be tweaked or swapped without touching the lens addon.

## Shared tuning resource. Edit `core/config/game_config.tres`.
@export var config: GameConfig:
	set(value):
		if config == value:
			return
		_disconnect_config()
		config = value
		_connect_config()
		if is_inside_tree():
			_apply()


func _ready() -> void:
	if config == null:
		config = GameConfig.new()
		push_warning("PostFxController: no GameConfig assigned; using defaults.")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_connect_config()
	_apply()


func _exit_tree() -> void:
	_disconnect_config()


## Re-read the config and push it to the material immediately.
func refresh() -> void:
	_apply()


func _apply() -> void:
	if config == null:
		return
	# Hiding the node also skips the draw call entirely.
	visible = config.post_fx_enabled
	if material is ShaderMaterial:
		var shader_material := material as ShaderMaterial
		shader_material.set_shader_parameter("enabled", config.post_fx_enabled)
		shader_material.set_shader_parameter("sharpen_amount", config.sharpen_amount)
		shader_material.set_shader_parameter("grain_amount", config.grain_amount)


func _connect_config() -> void:
	if config != null and not config.changed.is_connected(_apply):
		config.changed.connect(_apply)


func _disconnect_config() -> void:
	if config != null and config.changed.is_connected(_apply):
		config.changed.disconnect(_apply)
