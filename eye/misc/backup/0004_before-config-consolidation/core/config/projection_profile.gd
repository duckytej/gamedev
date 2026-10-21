class_name ProjectionProfile
extends ConfigResource

## Single source of truth for the screen-space lens look.
##
## One `ProjectionProfile` drives every tunable of the vendored
## `screenspace_projection` addon (projection mode, Panini strength, fill,
## sampling, chromatic aberration, vignette and render resolution). Assign it on
## a `ProjectionController` and the addon's script defaults, its `.tscn`
## material defaults, its shader defaults and any per-scene overrides no longer
## matter: this file wins.
##
## Camera FOV is deliberately NOT stored here. The lens auto-detects the active
## `Camera3D` FOV every frame, and FOV is a camera property owned by
## `PlayerConfig.base_fov`. One owner per setting.
##
## To add a new lens parameter: add the `@export`, add it to `apply_to()`'s
## `values` dictionary, and make sure the addon exposes a property with the
## same name. Nothing else in the project needs to change.

enum ProjectionMode {
	RECTILINEAR = 0,
	PANINI = 1,
	EQUIRECTANGULAR = 2,
	FISHEYE_STEREOGRAPHIC = 3,
	FISHEYE_EQUISOLID = 4,
}

@export var enabled: bool = true

@export_group("Lens")

## Projection model. Panini keeps vertical lines straight and is the intended
## look for this project (90-150 deg FOV).
@export var projection_mode: ProjectionMode = ProjectionMode.PANINI

## Panini: barrel strength D (0 = rectilinear, 0.3-0.5 typical).
## Other modes: rectilinear <-> projection blend (0..1).
@export_range(0.0, 1.0, 0.001) var strength: float = 1

## Auto-zoom that crops away empty corners. 0 = none, 1 = minimal valid crop.
@export_range(0.0, 1.0, 0.001) var fill: float = 1.0

## Panini vertical compensation for very wide angles.
@export_range(-1.0, 1.0, 0.001) var panini_s: float = 0.0

@export_group("Resolution")

## Linear resolution multiplier of the offscreen viewport. 1 = native, 2 = 2x.
@export_range(1.0, 4.0, 0.05) var upscale: float = 2.0

## How much of the extra resolution is temporal upscaling (FSR2) vs true
## supersampling. 0 = all upscaling (cheap), 1 = all supersampling (sharp).
@export_range(0.0, 1.0, 0.01) var supersample_amount: float = 0.5

@export_group("Sampling")

## Anisotropic filter radius caps (quality vs cost).
@export_range(1, 9, 1) var max_major_radius: int = 5
@export_range(0, 6, 1) var max_minor_radius: int = 3

@export_group("Chromatic Aberration")

@export_range(0.0, 1.0, 0.001) var ca_amount: float = 0.05
@export_range(0.01, 1.0, 0.001) var ca_amount_spread: float = 0.5
@export_range(360.0, 730.0) var ca_reference_wavelength: float = 540.0
@export_range(0.0, 5.0, 0.01) var ca_enable_start: float = 0.5
@export var ca_jitter: bool = true
@export_range(8, 64, 1) var ca_max_samples: int = 16
@export_range(0.0, 8.0, 0.01) var ca_samples_per_ca: float = 0.5

@export_group("Vignette")

@export_range(0.0, 1.0, 0.001) var vignette_strength: float = 0.18
@export_range(0.0, 1.0, 0.001) var vignette_spread: float = 0.5


## Push every value onto a `screenspace_projection` addon node.
##
## Uses duck-typed `Object.set()` so the game never imports the addon's script
## and stays compatible with upstream changes.
func apply_to(target: Object) -> void:
	apply_values(target, {
		"enabled": enabled,
		"projection_mode": projection_mode,
		"strength": strength,
		"fill": fill,
		"panini_s": panini_s,
		"upscale": upscale,
		"supersample_upscale_amount": supersample_amount,
		"max_major_radius": max_major_radius,
		"max_minor_radius": max_minor_radius,
		"ca_amount": ca_amount,
		"ca_amount_spread": ca_amount_spread,
		"ca_reference_wavelength": ca_reference_wavelength,
		"ca_enable_start": ca_enable_start,
		"ca_jitter": ca_jitter,
		"ca_max_samples": ca_max_samples,
		"ca_samples_per_ca": ca_samples_per_ca,
		"vignette_strength": vignette_strength,
		"vignette_spread": vignette_spread,
	})
