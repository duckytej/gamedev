class_name PlayerConfig
extends ConfigResource

## Single source of truth for the first-person controller's tuning.
##
## Assign one on the player (see `player/scenes/player.tscn`); `player.gd` reads
## it in `_ready()`. Edit this resource instead of the player script so movement,
## camera and "feel" values live in exactly one place.
##
## `base_fov` is also the FOV the screen-space lens picks up: the projection
## addon auto-detects the active `Camera3D`'s FOV, so this is the one knob for
## both the camera and the lens.

@export_group("Locomotion")

@export var walk_speed: float = 6.0
@export var sprint_speed: float = 9.5
## Quake-style ground acceleration (higher = snappier).
@export var ground_accel: float = 10.0
## Air steering strength (low = committed jumps).
@export var air_accel: float = 1.5
@export var air_speed: float = 6.0
@export var friction: float = 6.0
@export var gravity_scale: float = 1.0
@export var max_fall_speed: float = 30.0

@export_group("Jump")

@export var jump_velocity: float = 5.2
@export var coyote_time: float = 0.12
@export var jump_buffer_time: float = 0.12
## Velocity kept when jump is released early (variable jump height).
@export_range(0.0, 1.0, 0.05) var jump_cut_multiplier: float = 0.5
## Brief landing recovery before control returns.
@export var land_time: float = 0.1

@export_group("Slide")

@export var slide_boost: float = 1.35
@export var slide_friction: float = 1.5
@export var slide_min_speed: float = 4.0
@export var slide_max_time: float = 0.9

@export_group("Wall run")

@export var wall_run_speed: float = 9.0
@export_range(0.0, 1.0, 0.01) var wall_run_gravity_scale: float = 0.25
@export var wall_run_max_time: float = 1.3
@export var wall_run_min_speed: float = 4.0
@export var wall_jump_push: float = 7.0

@export_group("Dash")

@export var dash_speed: float = 18.0
@export var dash_time: float = 0.16
@export var dash_cooldown: float = 1.2

@export_group("Camera")

@export var mouse_sensitivity: float = 0.0022
@export_range(1.0, 90.0, 0.5) var max_pitch_degrees: float = 89.0
## Vertical FOV. Drives both the Camera3D and the screen-space lens.
@export_range(1.0, 179.0, 0.5) var base_fov: float = 140.0
@export var sprint_fov_kick: float = 8.0

@export_group("Feel")

@export var headbob_frequency: float = 2.2
@export var headbob_amplitude: float = 0.055
@export var strafe_tilt_degrees: float = 2.0
@export var step_interval: float = 2.1
@export var footstep_volume_db: float = -8.0
@export var landing_dip_scale: float = 0.016


## Copy every value onto a controller instance (`EyePlayer`).
## Property names match the controller's runtime fields.
func apply_to(target: Object) -> void:
	if target == null:
		push_warning("PlayerConfig.apply_to: target is null.")
		return

	apply_values(target, {
		"walk_speed": walk_speed,
		"sprint_speed": sprint_speed,
		"ground_accel": ground_accel,
		"air_accel": air_accel,
		"air_speed": air_speed,
		"friction": friction,
		"gravity_scale": gravity_scale,
		"max_fall_speed": max_fall_speed,
		"jump_velocity": jump_velocity,
		"coyote_time": coyote_time,
		"jump_buffer_time": jump_buffer_time,
		"jump_cut_multiplier": jump_cut_multiplier,
		"land_time": land_time,
		"slide_boost": slide_boost,
		"slide_friction": slide_friction,
		"slide_min_speed": slide_min_speed,
		"slide_max_time": slide_max_time,
		"wall_run_speed": wall_run_speed,
		"wall_run_gravity_scale": wall_run_gravity_scale,
		"wall_run_max_time": wall_run_max_time,
		"wall_run_min_speed": wall_run_min_speed,
		"wall_jump_push": wall_jump_push,
		"dash_speed": dash_speed,
		"dash_time": dash_time,
		"dash_cooldown": dash_cooldown,
		"mouse_sensitivity": mouse_sensitivity,
		"max_pitch_degrees": max_pitch_degrees,
		"base_fov": base_fov,
		"sprint_fov_kick": sprint_fov_kick,
		"headbob_frequency": headbob_frequency,
		"headbob_amplitude": headbob_amplitude,
		"strafe_tilt_degrees": strafe_tilt_degrees,
		"step_interval": step_interval,
		"footstep_volume_db": footstep_volume_db,
		"landing_dip_scale": landing_dip_scale,
	})
