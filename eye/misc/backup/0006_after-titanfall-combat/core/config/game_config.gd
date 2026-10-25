class_name GameConfig
extends Resource

## Single source of truth for every tunable in the project.
##
## There is deliberately only **one** config resource:
## `core/config/game_config.tres`. Scripts read fields from it directly instead
## of copying values into duplicate runtime properties, so adding a setting means
## adding one `@export` here (and using it), not editing three files.
##
## The resource is shared by the player, the lens controller, the post-fx
## controller and the threat detector. Sections mirror those systems; the
## inspector shows them as groups.
##
## Camera FOV has exactly one owner: [member base_fov]. The player writes it to
## its [Camera3D] and the vendored lens reads the camera back every frame.
##
## Run [method validate] after changing values (the world root and the smoke test
## both do) to catch impossible combinations such as `near_distance >
## far_distance`.

enum ProjectionMode {
	RECTILINEAR = 0,
	PANINI = 1,
	EQUIRECTANGULAR = 2,
	FISHEYE_STEREOGRAPHIC = 3,
	FISHEYE_EQUISOLID = 4,
}

# --- Player / locomotion ------------------------------------------------------

@export_group("Locomotion")

@export var walk_speed: float = 6.0
@export var sprint_speed: float = 9.5
@export var crouch_speed: float = 3.2
## Quake-style ground acceleration (higher = snappier).
@export var ground_accel: float = 10.0
## Air-steering strength. Low values keep jumps committed; high values feel
## closer to Titanfall/Source air control.
@export var air_accel: float = 4.0
@export var air_speed: float = 7.0
@export var friction: float = 6.0
@export var gravity_scale: float = 1.0
@export var max_fall_speed: float = 30.0
## Hard ceiling for horizontal speed after grapple/wall-run/dash. Prevents a
## single bad frame from producing an unplayable velocity.
@export var max_horizontal_speed: float = 45.0

## Crouch/slide body dimensions. The collision capsule is resized at runtime.
@export var crouch_height: float = 1.1
@export var crouch_eye_height: float = 0.9
@export var crouch_transition_speed: float = 12.0

@export_group("Jump")

@export var jump_velocity: float = 5.2
@export var coyote_time: float = 0.12
@export var jump_buffer_time: float = 0.12
## Extra mid-air jumps. 0 is Titanfall-strict; 1 is the movement1-style
## double jump. Wall jumps are always independent of this counter.
@export_range(0, 4, 1) var air_jumps: int = 0
## Velocity kept when jump is released early (variable jump height).
@export_range(0.0, 1.0, 0.05) var jump_cut_multiplier: float = 0.5
## Brief landing recovery before control returns.
@export var land_time: float = 0.1

@export_group("Slide")

@export var slide_boost: float = 1.35
@export var slide_friction: float = 1.5
@export var slide_min_speed: float = 4.0
@export var slide_max_time: float = 0.9
@export var slide_cooldown: float = 0.35
@export var slide_fov_kick: float = 6.0
## How strongly steering bends a slide without killing momentum.
@export_range(0.0, 1.0, 0.01) var slide_steer: float = 0.25

@export_group("Wall run")

@export var wall_run_speed: float = 9.5
@export_range(0.0, 1.0, 0.01) var wall_run_gravity_scale: float = 0.18
@export var wall_run_max_time: float = 1.6
@export var wall_run_min_speed: float = 4.0
## Outward push of a wall jump.
@export var wall_jump_push: float = 7.5
## Upward impulse of a wall jump.
@export var wall_jump_up: float = 8.0
## Fraction of tangential wall speed carried through a wall jump.
@export_range(0.0, 1.5, 0.01) var wall_jump_tangent_keep: float = 0.9
## Force that keeps the player glued to the wall while running it.
@export var wall_run_stick_force: float = 6.0
## Camera roll while wall-running (degrees).
@export var wall_run_tilt_degrees: float = 9.0
## Minimum time before the same wall can be grabbed again.
@export var wall_run_cooldown: float = 0.2
## Small upward kick when a wall-run starts, so it reads as a vault.
@export var wall_run_entry_boost: float = 1.5
@export var wall_run_fov_kick: float = 4.0
## Side probe reach; roughly capsule radius + a margin.
@export var wall_detect_distance: float = 0.75
## Minimum angle between a surface normal and world up. 75 accepts normals
## within 15 degrees of horizontal; ramps and floors are rejected.
@export_range(45.0, 89.9, 0.1) var wall_run_min_angle_deg: float = 75.0

@export_group("Dash")

@export var dash_speed: float = 18.0
@export var dash_time: float = 0.16
@export var dash_cooldown: float = 1.2

@export_group("Grapple")

@export var grapple_max_distance: float = 32.0
@export var grapple_min_distance: float = 2.0
## Rope is reeled in at this speed while attached (Titanfall-style pull).
@export var grapple_reel_speed: float = 9.0
## Rope length the reel stops at. The rope can go slack below this without
## detaching; only release, jump, or over-stretch breaks the grapple.
@export var grapple_rope_min_length: float = 2.0
## Radial acceleration toward the anchor.
@export var grapple_pull_accel: float = 55.0
@export_range(0.0, 1.0, 0.01) var grapple_gravity_scale: float = 0.45
## Position/velocity correction stiffness when the rope is taut.
@export var grapple_constraint_stiffness: float = 120.0
## Small upward velocity added on release. 0 = pure momentum preservation.
@export var grapple_release_boost: float = 1.5
@export var grapple_cooldown: float = 0.25
@export var grapple_max_speed: float = 45.0
@export var grapple_collision_mask: int = 1
@export var grapple_rope_width: float = 0.035
@export var grapple_rope_color: Color = Color(0.2, 1.0, 0.85)

@export_group("Camera")

@export var mouse_sensitivity: float = 0.0022
@export_range(1.0, 90.0, 0.5) var max_pitch_degrees: float = 89.0
## Vertical FOV. Drives both the Camera3D and the screen-space lens.
@export_range(1.0, 179.0, 0.5) var base_fov: float = 140.0
@export var sprint_fov_kick: float = 8.0
## Aim-down-sights vertical FOV.
@export_range(1.0, 179.0, 0.5) var scope_fov: float = 35.0
@export_range(0.05, 1.0, 0.01) var scope_sensitivity_scale: float = 0.45
@export var scope_transition_speed: float = 14.0
@export_range(0.0, 1.0, 0.01) var scope_headbob_scale: float = 0.15
@export_range(0.0, 1.0, 0.01) var scope_roll_scale: float = 0.25

@export_group("Scope Overlay")

@export_range(0.05, 0.9, 0.01) var scope_overlay_radius: float = 0.42
@export_range(0.0, 1.0, 0.01) var scope_overlay_opacity: float = 1.0
@export var scope_overlay_color: Color = Color(0.82, 1.0, 0.86)
@export_range(0.0, 0.02, 0.0001) var scope_overlay_line_width: float = 0.0012

@export_group("Feel")

@export var headbob_frequency: float = 2.2
@export var headbob_amplitude: float = 0.055
@export var strafe_tilt_degrees: float = 2.0
@export var step_interval: float = 2.1
@export var footstep_volume_db: float = -8.0
@export var landing_dip_scale: float = 0.016
@export var hit_marker_time: float = 0.16
@export var muzzle_flash_time: float = 0.045
@export var muzzle_flash_energy: float = 3.0
@export var tracer_time: float = 0.07
@export var recoil_recovery: float = 9.0
@export var tracer_color: Color = Color(1.0, 0.82, 0.45)
@export var sniper_tracer_color: Color = Color(0.4, 1.0, 0.55)
@export var impact_color: Color = Color(1.0, 0.7, 0.3)
@export var muzzle_flash_color: Color = Color(1.0, 0.75, 0.35)

@export_group("Weapons / Pistol")

@export var pistol_range: float = 120.0
@export var pistol_damage: float = 6.0
@export var pistol_fire_interval: float = 0.16
@export var pistol_spread_degrees: float = 0.35
@export var pistol_recoil: float = 0.3

@export_group("Weapons / Grenade")

## Hold left mouse longer than this to turn the click into a grenade throw.
@export var grenade_hold_threshold: float = 0.22
@export var grenade_charge_time: float = 0.8
@export var grenade_min_speed: float = 12.0
@export var grenade_max_speed: float = 24.0
@export var grenade_gravity_scale: float = 1.0
## Fraction of player velocity added to the throw (movement influences aim).
@export_range(0.0, 1.5, 0.01) var grenade_velocity_inherit: float = 0.5
@export var grenade_throw_up: float = 2.0
@export var grenade_fuse_time: float = 2.5
@export var grenade_radius: float = 4.0
@export var grenade_damage: float = 80.0
@export var grenade_min_damage: float = 20.0
@export_range(0.0, 1.0, 0.01) var grenade_bounce: float = 0.35
@export_range(0.0, 1.0, 0.01) var grenade_friction: float = 0.7
@export var grenade_lifetime: float = 8.0
@export var grenade_recoil: float = 0.5
@export var grenade_explosion_color: Color = Color(1.0, 0.48, 0.12)
@export var grenade_explosion_light_energy: float = 6.0
@export var grenade_explosion_visual_time: float = 0.4

@export_group("Weapons / Sniper")

@export var sniper_range: float = 300.0
@export var sniper_charge_time: float = 1.1
@export var sniper_min_damage: float = 35.0
@export var sniper_max_damage: float = 120.0
@export var sniper_min_speed: float = 80.0
@export var sniper_max_speed: float = 240.0
## Bullet drop multiplier at zero charge. 0 = flat trajectory.
@export var sniper_gravity_scale: float = 0.35
## Fraction of player velocity added to the shot.
@export_range(0.0, 1.5, 0.01) var sniper_velocity_inherit: float = 0.35
@export var sniper_min_hit_radius: float = 0.05
@export var sniper_max_hit_radius: float = 0.45
## At or above this charge the shot is hitscan (with the maximum hit radius).
@export_range(0.5, 1.0, 0.01) var sniper_hitscan_threshold: float = 0.99
@export var sniper_preview_steps: int = 96
@export var sniper_preview_max_time: float = 3.0
@export var sniper_preview_interval: float = 0.04
@export var sniper_preview_radius: float = 0.09
@export var sniper_preview_color: Color = Color(0.2, 1.0, 0.35)
@export var sniper_recoil: float = 1.2

@export_group("Combat")

@export var enemy_max_health: float = 100.0
@export var enemy_hit_flash_time: float = 0.12
@export var enemy_death_fade: float = 0.28
@export var enemy_health_label_time: float = 2.0

# --- Screen-space lens --------------------------------------------------------

@export_group("Lens")

@export var lens_enabled: bool = true

## Projection model. Panini keeps vertical lines straight and is the intended
## look for this project (90-150 deg FOV).
@export var projection_mode: ProjectionMode = ProjectionMode.PANINI

## Panini: barrel strength D (0 = rectilinear, 0.3-0.5 typical).
## Other modes: rectilinear <-> projection blend (0..1).
@export_range(0.0, 1.0, 0.001) var lens_strength: float = 1

## Auto-zoom that crops away empty corners. 0 = none, 1 = minimal valid crop.
@export_range(0.0, 1.0, 0.001) var lens_fill: float = 1.0

## Panini vertical compensation for very wide angles.
@export_range(-1.0, 1.0, 0.001) var lens_panini_s: float = 0.0

@export_group("Lens Resolution")

## Linear resolution multiplier of the offscreen viewport. 1 = native, 2 = 2x.
@export_range(1.0, 4.0, 0.05) var lens_upscale: float = 2.0

## How much of the extra resolution is temporal upscaling (FSR2) vs true
## supersampling. 0 = all upscaling (cheap), 1 = all supersampling (sharp).
@export_range(0.0, 1.0, 0.01) var lens_supersample: float = 0.5

@export_group("Lens Sampling")

## Anisotropic filter radius caps (quality vs cost).
@export_range(1, 9, 1) var lens_max_major_radius: int = 5
@export_range(0, 6, 1) var lens_max_minor_radius: int = 3

@export_group("Chromatic Aberration")

@export_range(0.0, 1.0, 0.001) var ca_amount: float = 0.04
@export_range(0.01, 1.0, 0.001) var ca_spread: float = 0.5
@export_range(360.0, 730.0) var ca_reference_wavelength: float = 540.0
@export_range(0.0, 5.0, 0.01) var ca_enable_start: float = 0.5
@export var ca_jitter: bool = true
@export_range(8, 64, 1) var ca_max_samples: int = 16
@export_range(0.0, 8.0, 0.01) var ca_samples_per_ca: float = 0.5

@export_group("Vignette")

@export_range(0.0, 1.0, 0.001) var vignette_strength: float = 0.18
@export_range(0.0, 1.0, 0.001) var vignette_spread: float = 0.5

# --- Post-lens effects --------------------------------------------------------

@export_group("Post FX")

## Master switch. Off = pass-through (the pass is also hidden, so it costs nothing).
@export var post_fx_enabled: bool = true

## Contrast Adaptive Sharpening amount. Counters FSR2 temporal softness and
## edge blur from the wide-anchor lens without ringing halos.
@export_range(0.0, 1.0, 0.01) var sharpen_amount: float = 0.45

## Optional film grain. Off by default; raise slightly to mask temporal
## upscaling shimmer at high FOV.
@export_range(0.0, 1.0, 0.01) var grain_amount: float = 0.0

# --- Peripheral threat vision ------------------------------------------------

@export_group("Threat Zones")

## Half-width of the normal forward view, in degrees (70 => a 140 deg view).
@export_range(1.0, 179.0, 0.5) var forward_half_angle_deg: float = 70.0

## Outer edge of peripheral vision, in degrees. Beyond this is the blindspot.
@export_range(1.0, 179.0, 0.5) var peripheral_end_angle_deg: float = 110.0

@export_group("Threat Range")

## Objects farther than this are ignored entirely.
@export var max_distance: float = 30.0

## At (or closer than) this distance a highlight is at full intensity.
@export var near_distance: float = 4.0

## At this distance a highlight has faded out. `near < far <= max_distance`.
@export var far_distance: float = 22.0

@export_group("Threat Detection")

## Seconds between detection passes. 0 = every physics tick.
@export var detect_interval: float = 0.05

## Physics layers that block line of sight (world geometry). Highlightable
## objects must live on a different layer so they never occlude each other.
@export_flags_3d_physics var los_collision_mask: int = 1

@export_group("Threat Highlight")

## Highlight colour. Distance scales brightness, not hue.
@export var highlight_color: Color = Color(1.0, 0.18, 0.16)

## Opacity of a faded-out (far) highlight.
@export_range(0.0, 1.0, 0.01) var min_alpha: float = 0.12

## Opacity of a point-blank highlight.
@export_range(0.0, 1.0, 0.01) var max_alpha: float = 0.9


## Returns a list of human-readable problems. Empty means the config is valid.
##
## The world root logs these on startup and the smoke test fails on them, so an
## impossible combination is caught immediately instead of producing mysterious
## behaviour at runtime.
func validate() -> PackedStringArray:
	var issues := PackedStringArray()

	if base_fov <= 1.0 or base_fov >= 179.0:
		issues.append("base_fov must be between 1 and 179 (got %.1f)." % base_fov)
	if walk_speed <= 0.0:
		issues.append("walk_speed must be > 0.")
	if sprint_speed < walk_speed:
		issues.append("sprint_speed should be >= walk_speed.")
	if crouch_speed <= 0.0 or crouch_speed > walk_speed:
		issues.append("crouch_speed must be > 0 and <= walk_speed.")
	if max_horizontal_speed <= sprint_speed:
		issues.append("max_horizontal_speed must be greater than sprint_speed.")
	if crouch_height <= 0.0 or crouch_height >= 1.8:
		issues.append("crouch_height must be within 0..1.8.")
	if crouch_eye_height <= 0.0 or crouch_eye_height >= crouch_height:
		issues.append("crouch_eye_height must be > 0 and below crouch_height.")
	if crouch_transition_speed <= 0.0:
		issues.append("crouch_transition_speed must be > 0.")
	if air_jumps < 0:
		issues.append("air_jumps must be >= 0.")
	if slide_max_time <= 0.0 or slide_cooldown < 0.0:
		issues.append("slide timing values must be non-negative (max time > 0).")
	if wall_run_max_time <= 0.0:
		issues.append("wall_run_max_time must be > 0.")
	if wall_run_min_speed < 0.0:
		issues.append("wall_run_min_speed must be >= 0.")
	if wall_jump_push < 0.0 or wall_jump_up < 0.0:
		issues.append("wall jump impulses must be >= 0.")
	if wall_detect_distance <= 0.0:
		issues.append("wall_detect_distance must be > 0.")
	if wall_run_min_angle_deg < 45.0 or wall_run_min_angle_deg >= 90.0:
		issues.append("wall_run_min_angle_deg must be within 45..90.")
	if wall_run_cooldown < 0.0:
		issues.append("wall_run_cooldown must be >= 0.")
	if dash_speed <= 0.0 or dash_time <= 0.0 or dash_cooldown < 0.0:
		issues.append("dash speed/time must be > 0 and cooldown >= 0.")
	if grapple_max_distance <= grapple_min_distance:
		issues.append("grapple_max_distance must be greater than grapple_min_distance.")
	if grapple_rope_min_length < 0.0 or grapple_reel_speed < 0.0:
		issues.append("grapple distances and reel speed must be >= 0.")
	if grapple_rope_min_length > grapple_max_distance:
		issues.append("grapple_rope_min_length must not exceed grapple_max_distance.")
	if grapple_pull_accel < 0.0 or grapple_constraint_stiffness <= 0.0:
		issues.append("grapple pull must be >= 0 and constraint stiffness > 0.")
	if grapple_gravity_scale < 0.0 or grapple_max_speed <= 0.0:
		issues.append("grapple gravity must be >= 0 and max speed > 0.")
	if grapple_cooldown < 0.0:
		issues.append("grapple_cooldown must be >= 0.")
	if scope_fov <= 1.0 or scope_fov >= base_fov:
		issues.append("scope_fov must be within 1..base_fov.")
	if scope_sensitivity_scale <= 0.0:
		issues.append("scope_sensitivity_scale must be > 0.")
	if scope_transition_speed <= 0.0:
		issues.append("scope_transition_speed must be > 0.")
	if scope_overlay_radius <= 0.0 or scope_overlay_radius >= 0.9:
		issues.append("scope_overlay_radius must be within 0..0.9.")
	if pistol_range <= 0.0 or pistol_damage < 0.0:
		issues.append("pistol range must be > 0 and damage >= 0.")
	if pistol_fire_interval <= 0.0 or pistol_spread_degrees < 0.0:
		issues.append("pistol fire interval must be > 0 and spread >= 0.")
	if grenade_hold_threshold <= 0.0 or grenade_charge_time <= 0.0:
		issues.append("grenade timing values must be > 0.")
	if grenade_max_speed < grenade_min_speed:
		issues.append("grenade_max_speed must be >= grenade_min_speed.")
	if grenade_fuse_time <= 0.0 or grenade_radius <= 0.0:
		issues.append("grenade fuse time and radius must be > 0.")
	if grenade_lifetime < grenade_fuse_time:
		issues.append("grenade_lifetime must be >= grenade_fuse_time.")
	if grenade_gravity_scale < 0.0:
		issues.append("grenade_gravity_scale must be >= 0.")
	if grenade_min_damage < 0.0 or grenade_min_damage > grenade_damage:
		issues.append("grenade_min_damage must be within 0..grenade_damage.")
	if sniper_charge_time <= 0.0 or sniper_range <= 0.0:
		issues.append("sniper charge time and range must be > 0.")
	if sniper_min_speed <= 0.0 or sniper_max_speed < sniper_min_speed:
		issues.append("sniper speeds must satisfy 0 < min <= max.")
	if sniper_gravity_scale < 0.0:
		issues.append("sniper_gravity_scale must be >= 0.")
	if sniper_min_hit_radius <= 0.0 or sniper_max_hit_radius < sniper_min_hit_radius:
		issues.append("sniper hit radii must satisfy 0 < min <= max.")
	if sniper_min_damage < 0.0 or sniper_max_damage < sniper_min_damage:
		issues.append("sniper damage range must be 0 <= min <= max.")
	if sniper_hitscan_threshold < 0.5 or sniper_hitscan_threshold > 1.0:
		issues.append("sniper_hitscan_threshold must be within 0.5..1.0.")
	if sniper_preview_steps < 8:
		issues.append("sniper_preview_steps must be at least 8.")
	if sniper_preview_max_time <= 0.0 or sniper_preview_interval <= 0.0:
		issues.append("sniper preview timing must be > 0.")
	if sniper_preview_radius <= 0.0:
		issues.append("sniper_preview_radius must be > 0.")
	if enemy_max_health <= 0.0:
		issues.append("enemy_max_health must be > 0.")
	if enemy_hit_flash_time < 0.0 or enemy_death_fade < 0.0 or enemy_health_label_time < 0.0:
		issues.append("enemy feedback timings must be >= 0.")
	if hit_marker_time <= 0.0 or muzzle_flash_time <= 0.0 or tracer_time <= 0.0:
		issues.append("hit marker, muzzle flash and tracer times must be > 0.")
	if step_interval <= 0.0:
		issues.append("step_interval must be > 0.")
	if lens_upscale < 1.0:
		issues.append("lens_upscale must be >= 1.")
	if projection_mode == ProjectionMode.PANINI \
			and (lens_strength < 0.0 or lens_strength > 1.0):
		issues.append("lens_strength must be within 0..1.")

	if forward_half_angle_deg <= 0.0 or forward_half_angle_deg >= 180.0:
		issues.append("forward_half_angle_deg must be within 0..180.")
	if peripheral_end_angle_deg <= forward_half_angle_deg \
			or peripheral_end_angle_deg > 180.0:
		issues.append(
			"peripheral_end_angle_deg must be greater than forward_half_angle_deg and <= 180."
		)
	if near_distance < 0.0:
		issues.append("near_distance must be >= 0.")
	if not (near_distance < far_distance and far_distance <= max_distance):
		issues.append("distance range must satisfy near_distance < far_distance <= max_distance.")
	if min_alpha > max_alpha:
		issues.append("min_alpha must be <= max_alpha.")
	if detect_interval < 0.0:
		issues.append("detect_interval must be >= 0.")

	return issues
