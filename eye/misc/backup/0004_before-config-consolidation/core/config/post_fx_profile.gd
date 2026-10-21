class_name PostFxProfile
extends ConfigResource

## Single source of truth for the post-lens screen-space effects.
##
## Runs as one extra full-screen pass on top of the projection output (below the
## HUD), so it stays cheap: one texture fetch for the base image plus up to four
## neighbour taps. Edit this resource and the look changes; nothing else.

## Master switch. Off = pass-through (the pass is also hidden, so it costs nothing).
@export var enabled: bool = true

@export_group("Sharpening")

## Contrast Adaptive Sharpening amount. Counters FSR2 temporal softness and
## edge blur from the wide-anchor lens without ringing halos.
@export_range(0.0, 1.0, 0.01) var sharpen_amount: float = 0.45

@export_group("Grain")

## Optional film grain. Off by default; raise slightly to mask temporal
## upscaling shimmer at high FOV.
@export_range(0.0, 1.0, 0.01) var grain_amount: float = 0.0


func apply_to(target: Object) -> void:
	if target is ShaderMaterial:
		apply_to_material(target)
	else:
		push_warning("PostFxProfile.apply_to: expected a ShaderMaterial.")


func apply_to_material(material: ShaderMaterial) -> void:
	if material == null:
		push_warning("PostFxProfile.apply_to_material: material is null.")
		return
	material.set_shader_parameter("enabled", enabled)
	material.set_shader_parameter("sharpen_amount", sharpen_amount)
	material.set_shader_parameter("grain_amount", grain_amount)
