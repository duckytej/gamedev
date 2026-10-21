class_name PostFxController
extends ColorRect

## Applies a [PostFxProfile] to the full-screen post-lens pass.
##
## Lives on a full-rect `ColorRect` inside a low `CanvasLayer` in `world.tscn`,
## drawn after the projection output and before the HUD. It owns the pass, so the
## effect can be tweaked or swapped without touching the lens addon.

## The effect settings. Edit `core/config/post_fx_profile.tres`.
@export var profile: PostFxProfile:
	set(value):
		_disconnect_profile()
		profile = value
		_connect_profile()
		if is_inside_tree():
			_apply()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_connect_profile()
	_apply()


func _exit_tree() -> void:
	_disconnect_profile()


## Re-read the profile and push it to the material immediately.
func refresh() -> void:
	_apply()


func _apply() -> void:
	if profile == null:
		return
	# Hiding the node also skips the draw call entirely.
	visible = profile.enabled
	if material is ShaderMaterial:
		profile.apply_to_material(material)


func _connect_profile() -> void:
	if profile != null and not profile.changed.is_connected(_apply):
		profile.changed.connect(_apply)


func _disconnect_profile() -> void:
	if profile != null and profile.changed.is_connected(_apply):
		profile.changed.disconnect(_apply)
