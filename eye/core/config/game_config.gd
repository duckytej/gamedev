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
## Default ground speed. There is no sprint button: moving normally runs at this
## speed, and sprinting is the baseline the other traversal moves are tuned
## around.
@export var sprint_speed: float = 9.5
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

@export_group("Player Vitals")

## Base health and stamina. Health is lost to enemy fire; stamina is spent only
## by the traversal/combat actions below, never by ordinary movement.
@export var player_max_health: float = 100.0
@export var player_max_stamina: float = 100.0
@export var player_stamina_regen_per_second: float = 18.0
@export var player_stamina_regen_delay: float = 1.0
@export var player_respawn_delay: float = 1.5

@export_group("Overhealth")

## Damage dealt to enemies fills this buffer, which absorbs incoming damage
## before health. At more than `overhealth_burst_threshold` of the maximum the
## whole buffer can be spent on the stagger burst below.
@export var player_max_overhealth: float = 50.0
@export var overhealth_gain_per_damage: float = 1.0
@export_range(0.01, 0.99, 0.01) var overhealth_burst_threshold: float = 0.5
@export var burst_radius: float = 7.0
@export var burst_damage: float = 35.0
@export var burst_damage_per_overhealth: float = 1.0
@export var burst_stagger_time: float = 2.2
@export var burst_visual_time: float = 0.38
@export var burst_color: Color = Color(0.42, 0.9, 1.0)

@export_group("Jump")

@export var jump_velocity: float = 5.2
@export var coyote_time: float = 0.12
@export var jump_buffer_time: float = 0.12
## Extra mid-air jumps. One gives the requested double jump. Wall jumps are
## always independent of this counter.
@export_range(0, 4, 1) var air_jumps: int = 1
## Velocity kept when jump is released early (variable jump height).
@export_range(0.0, 1.0, 0.05) var jump_cut_multiplier: float = 0.5
## Holding jump while grounded/rising adds this much upward acceleration for up
## to `jump_hold_max_time`, so a tap is a short hop and a held jump is higher.
@export var jump_hold_accel: float = 15.0
@export var jump_hold_max_time: float = 0.32
## Brief landing recovery before control returns.
@export var land_time: float = 0.1

@export_group("Slam")

## Hold jump this long (after a jump started in mid-air) while falling to slam.
@export var slam_hold_time: float = 0.16
## Downward speed applied when a slam starts.
@export var slam_speed: float = 24.0
## Fraction of horizontal momentum kept through a slam.
@export_range(0.0, 1.0, 0.01) var slam_horizontal_keep: float = 0.9
## Slam gravity multiplier. 1 = normal fall, >1 = faster plunge.
@export var slam_gravity_scale: float = 1.6
## Land a slam straight into a slide.
@export var slam_to_slide: bool = true

@export_group("Slide")

## Slide pose. The collision body is resized at runtime; the player has no
## manual crouch state. The crouch input was removed because slides are
## automatic (fast landing / slam), as in the movement prototype.
@export var slide_height: float = 1.1
@export var slide_eye_height: float = 0.9
@export var slide_pose_speed: float = 12.0

## Slides start with a large burst, then bleed below sprint speed. There is no
## slide button: landing fast or chaining a slam starts one.
@export var slide_boost: float = 1.6
## Hard cap on the burst speed so a dash-slide cannot become a free launcher.
@export var slide_max_entry_speed: float = 17.0
@export var slide_friction: float = 6.0
## Speed needed to auto-slide on flat ground (above sprint, so it takes a slam,
## dash, grapple or wall jump to start one).
@export var slide_min_speed: float = 10.5
## Much lower threshold when moving down a ramp.
@export var slide_ramp_min_speed: float = 3.0
## Downhill acceleration while sliding. Flat slides only lose speed.
@export var slide_slope_accel: float = 8.0
@export var slide_max_time: float = 1.5
@export var slide_end_speed: float = 3.0
@export var slide_cooldown: float = 0.3
@export var slide_fov_kick: float = 6.0
## How strongly steering bends a slide without killing momentum.
@export_range(0.0, 1.0, 0.01) var slide_steer: float = 0.3
## A slam landing always starts a slide with at least this much speed, even if
## the player dropped straight down. This is the slam -> slide chain from the
## movement prototype's crouch/slide function.
@export var slam_slide_speed: float = 14.0
@export var slam_slide_boost: float = 1.25

@export_group("Wall run")

## Base speed the run decays toward.
@export var wall_run_speed: float = 9.5
## Gravity starts almost off, then ramps toward normal so the runner visibly
## slides down the wall instead of floating along it.
@export_range(0.0, 1.0, 0.01) var wall_run_start_gravity_scale: float = 0.05
@export_range(0.0, 2.0, 0.01) var wall_run_end_gravity_scale: float = 0.9
@export var wall_run_gravity_ramp_time: float = 0.9
## Speed lost per second along the wall after the entry burst.
@export var wall_run_speed_decay: float = 3.5
## How quickly excess speed is bled down to the decaying target.
@export var wall_run_speed_bleed: float = 14.0
@export var wall_run_max_time: float = 1.6
@export var wall_run_min_speed: float = 4.0
## Initial multiplier on wall tangent speed (the "launch" onto the wall).
@export var wall_run_entry_speed_boost: float = 1.35
## Outward push of a wall jump.
@export var wall_jump_push: float = 7.5
## Upward impulse of a wall jump.
@export var wall_jump_up: float = 8.0
## Tangential speed multiplier on a wall jump, so leaving the wall also boosts.
@export_range(0.5, 2.0, 0.01) var wall_jump_tangent_boost: float = 1.2
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
## Ordinary movement is free; the dash is the only traversal move that spends
## stamina (grapple spends once on attach).
@export var dash_stamina_cost: float = 25.0

@export_group("Grapple")

@export var grapple_max_distance: float = 32.0
@export var grapple_min_distance: float = 2.0
## Rope is reeled in at this speed while attached. Deliberately slow: the winch
## pulls, it does not teleport the player to the anchor.
@export var grapple_reel_speed: float = 4.0
## Rope length the reel stops at. The rope can go slack below this without
## detaching; only release, jump, or over-stretch breaks the grapple.
@export var grapple_rope_min_length: float = 2.0
## Gentle constant acceleration toward the anchor. This is a pull, not a hard
## constraint: tangential momentum (the swing) is never removed.
@export var grapple_pull_accel: float = 24.0
## Extra pull when the player has moved past the reeled-in rope length.
@export var grapple_constraint_stiffness: float = 70.0
## Safety cap on the total spring pull, so a long over-stretch cannot launch the
## player at an unplayable speed in one tick.
@export var grapple_max_pull_accel: float = 90.0
@export_range(0.0, 1.0, 0.01) var grapple_gravity_scale: float = 0.5
## Stronger-than-normal air steering while swinging, so the player can rotate
## around the anchor instead of only being dragged in.
@export var grapple_air_accel: float = 12.0
@export var grapple_air_speed: float = 9.0
## Small upward velocity added on release. 0 = pure momentum preservation.
@export var grapple_release_boost: float = 1.5
@export var grapple_cooldown: float = 0.25
@export var grapple_max_speed: float = 45.0
## Charged once when the rope attaches; swinging/hanging is free.
@export var grapple_stamina_cost: float = 20.0
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
@export var pistol_magazine_size: int = 12
@export var pistol_reload_time: float = 1.4
@export var pistol_stamina_cost: float = 2.0

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
## Sticky grenade: the first surface it touches becomes the blast position.
## Disable to restore the bouncing behaviour.
@export var grenade_sticky: bool = true
@export_range(0.0, 1.0, 0.01) var grenade_bounce: float = 0.35
@export_range(0.0, 1.0, 0.01) var grenade_friction: float = 0.7
@export var grenade_lifetime: float = 8.0
@export var grenade_recoil: float = 0.5
@export var grenade_explosion_color: Color = Color(1.0, 0.48, 0.12)
@export var grenade_explosion_light_energy: float = 6.0
@export var grenade_explosion_visual_time: float = 0.4
@export var grenade_stamina_cost: float = 12.0

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
@export var sniper_magazine_size: int = 5
@export var sniper_reload_time: float = 2.4
@export var sniper_stamina_cost: float = 15.0
## Firing within this many seconds of scoping is a quickscope: an exact
## hit-scan along the crosshair with no bullet drop, inheritance or spread.
@export var sniper_quickscope_window: float = 0.22
@export var sniper_quickscope_damage: float = 90.0

@export_group("Weapons / Sword")

@export var sword_damage: float = 45.0
@export var sword_range: float = 2.6
@export var sword_fire_interval: float = 0.4
@export var sword_hit_radius: float = 0.36
@export var sword_stamina_cost: float = 8.0
## Time after pressing parry during which an enemy shot is deflected.
@export var sword_parry_window: float = 0.32
@export var sword_parry_cooldown: float = 0.65
## Total width of the parry cone; the enemy must be inside it.
@export_range(30.0, 360.0, 1.0) var sword_parry_arc_degrees: float = 150.0
@export var sword_parry_stagger_time: float = 2.2
@export var sword_parry_color: Color = Color(0.55, 0.95, 1.0)
@export var sword_recoil: float = 0.35
@export var sword_tracer_color: Color = Color(0.75, 0.95, 1.0)
## Returning from the melee quickswitch cuts the remaining reload by this much.
@export_range(0.1, 1.0, 0.05) var quickswitch_reload_factor: float = 0.5

@export_group("Combat")

@export var enemy_max_health: float = 100.0
@export var enemy_hit_flash_time: float = 0.12
@export var enemy_death_fade: float = 0.28
@export var enemy_health_label_time: float = 2.0

@export_group("Enemy AI")

## Master switch. The in-game F1 action toggles this at runtime as well.
@export var enemy_ai_enabled: bool = true
## Seconds between AI decisions for one enemy. Thinking is deliberately much
## slower than physics; movement itself still runs every tick.
@export var enemy_ai_update_interval: float = 0.1
## Hard budget of enemy brains per physics tick. One keeps the cost flat and
## guarantees enemies never all think on the same tick.
@export_range(1, 8, 1) var enemy_ai_max_updates_per_tick: int = 1
@export var enemy_detection_range: float = 28.0
@export var enemy_shoot_range: float = 18.0
@export var enemy_move_speed: float = 3.8
@export var enemy_acceleration: float = 10.0
@export var enemy_stop_distance: float = 6.0
@export var enemy_strafe_speed: float = 2.2
@export var enemy_fire_interval: float = 1.1
@export var enemy_damage: float = 8.0
@export var enemy_aim_height: float = 1.2
@export var enemy_los_collision_mask: int = 1
@export var enemy_tracer_color: Color = Color(1.0, 0.35, 0.25)
@export var enemy_stagger_color: Color = Color(0.35, 0.75, 1.0)

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
	if max_horizontal_speed <= sprint_speed:
		issues.append("max_horizontal_speed must be greater than sprint_speed.")
	if slide_height <= 0.0 or slide_height >= 1.8:
		issues.append("slide_height must be within 0..1.8.")
	if slide_eye_height <= 0.0 or slide_eye_height >= slide_height:
		issues.append("slide_eye_height must be > 0 and below slide_height.")
	if slide_pose_speed <= 0.0:
		issues.append("slide_pose_speed must be > 0.")
	if player_max_health <= 0.0 or player_max_stamina <= 0.0:
		issues.append("player max health and stamina must be > 0.")
	if player_max_overhealth < 0.0:
		issues.append("player_max_overhealth must be >= 0.")
	if player_stamina_regen_per_second < 0.0 or player_stamina_regen_delay < 0.0:
		issues.append("stamina regen rate/delay must be >= 0.")
	if player_respawn_delay < 0.0:
		issues.append("player_respawn_delay must be >= 0.")
	if overhealth_gain_per_damage < 0.0:
		issues.append("overhealth_gain_per_damage must be >= 0.")
	if overhealth_burst_threshold <= 0.0 or overhealth_burst_threshold >= 1.0:
		issues.append("overhealth_burst_threshold must be within 0..1.")
	if burst_radius <= 0.0 or burst_stagger_time < 0.0:
		issues.append("burst radius must be > 0 and stagger time >= 0.")
	if burst_damage < 0.0 or burst_damage_per_overhealth < 0.0:
		issues.append("burst damage values must be >= 0.")
	if air_jumps < 0:
		issues.append("air_jumps must be >= 0.")
	if jump_hold_accel < 0.0 or jump_hold_max_time < 0.0:
		issues.append("jump hold values must be >= 0.")
	if slam_hold_time < 0.0 or slam_speed <= 0.0:
		issues.append("slam hold time must be >= 0 and slam speed > 0.")
	if slam_gravity_scale < 0.0:
		issues.append("slam_gravity_scale must be >= 0.")
	if slide_max_time <= 0.0 or slide_cooldown < 0.0:
		issues.append("slide timing values must be non-negative (max time > 0).")
	if slide_min_speed < 0.0 or slide_ramp_min_speed < 0.0:
		issues.append("slide engagement speeds must be >= 0.")
	if slide_ramp_min_speed > slide_min_speed:
		issues.append("slide_ramp_min_speed must be <= slide_min_speed.")
	if slide_max_entry_speed < slide_min_speed:
		issues.append("slide_max_entry_speed must be >= slide_min_speed.")
	if slide_end_speed < 0.0 or slide_friction < 0.0:
		issues.append("slide end speed and friction must be >= 0.")
	if slam_slide_speed < slide_end_speed:
		issues.append("slam_slide_speed must be >= slide_end_speed.")
	if slam_slide_boost < 1.0:
		issues.append("slam_slide_boost must be >= 1.")
	if wall_run_max_time <= 0.0:
		issues.append("wall_run_max_time must be > 0.")
	if wall_run_min_speed < 0.0:
		issues.append("wall_run_min_speed must be >= 0.")
	if wall_run_start_gravity_scale < 0.0 or wall_run_end_gravity_scale < 0.0:
		issues.append("wall-run gravity scales must be >= 0.")
	if wall_run_gravity_ramp_time <= 0.0:
		issues.append("wall_run_gravity_ramp_time must be > 0.")
	if wall_run_speed_decay < 0.0 or wall_run_speed_bleed < 0.0:
		issues.append("wall-run speed decay/bleed must be >= 0.")
	if wall_run_entry_speed_boost < 1.0:
		issues.append("wall_run_entry_speed_boost must be >= 1.")
	if wall_jump_push < 0.0 or wall_jump_up < 0.0:
		issues.append("wall jump impulses must be >= 0.")
	if wall_jump_tangent_boost < 0.0:
		issues.append("wall_jump_tangent_boost must be >= 0.")
	if wall_detect_distance <= 0.0:
		issues.append("wall_detect_distance must be > 0.")
	if wall_run_min_angle_deg < 45.0 or wall_run_min_angle_deg >= 90.0:
		issues.append("wall_run_min_angle_deg must be within 45..90.")
	if wall_run_cooldown < 0.0:
		issues.append("wall_run_cooldown must be >= 0.")
	if dash_speed <= 0.0 or dash_time <= 0.0 or dash_cooldown < 0.0:
		issues.append("dash speed/time must be > 0 and cooldown >= 0.")
	if dash_stamina_cost < 0.0:
		issues.append("dash_stamina_cost must be >= 0.")
	if grapple_max_distance <= grapple_min_distance:
		issues.append("grapple_max_distance must be greater than grapple_min_distance.")
	if grapple_rope_min_length < 0.0 or grapple_reel_speed < 0.0:
		issues.append("grapple distances and reel speed must be >= 0.")
	if grapple_rope_min_length > grapple_max_distance:
		issues.append("grapple_rope_min_length must not exceed grapple_max_distance.")
	if grapple_pull_accel < 0.0 or grapple_constraint_stiffness <= 0.0:
		issues.append("grapple pull must be >= 0 and constraint stiffness > 0.")
	if grapple_max_pull_accel < grapple_pull_accel:
		issues.append("grapple_max_pull_accel must be >= grapple_pull_accel.")
	if grapple_air_accel < 0.0 or grapple_air_speed <= 0.0:
		issues.append("grapple air steering must have accel >= 0 and speed > 0.")
	if grapple_gravity_scale < 0.0 or grapple_max_speed <= 0.0:
		issues.append("grapple gravity must be >= 0 and max speed > 0.")
	if grapple_cooldown < 0.0:
		issues.append("grapple_cooldown must be >= 0.")
	if grapple_stamina_cost < 0.0:
		issues.append("grapple_stamina_cost must be >= 0.")
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
	if pistol_magazine_size < 1 or pistol_reload_time <= 0.0:
		issues.append("pistol magazine must be >= 1 and reload time > 0.")
	if pistol_stamina_cost < 0.0:
		issues.append("pistol_stamina_cost must be >= 0.")
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
	if grenade_stamina_cost < 0.0:
		issues.append("grenade_stamina_cost must be >= 0.")
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
	if sniper_magazine_size < 1 or sniper_reload_time <= 0.0:
		issues.append("sniper magazine must be >= 1 and reload time > 0.")
	if sniper_stamina_cost < 0.0:
		issues.append("sniper_stamina_cost must be >= 0.")
	if sniper_quickscope_window < 0.0:
		issues.append("sniper_quickscope_window must be >= 0.")
	if sniper_quickscope_damage < 0.0:
		issues.append("sniper_quickscope_damage must be >= 0.")
	if sword_damage < 0.0 or sword_range <= 0.0 or sword_hit_radius <= 0.0:
		issues.append("sword range/radius must be > 0 and damage >= 0.")
	if sword_fire_interval <= 0.0 or sword_stamina_cost < 0.0:
		issues.append("sword interval must be > 0 and stamina cost >= 0.")
	if sword_parry_window < 0.0 or sword_parry_cooldown < 0.0:
		issues.append("sword parry timings must be >= 0.")
	if sword_parry_arc_degrees < 0.0 or sword_parry_arc_degrees > 360.0:
		issues.append("sword_parry_arc_degrees must be within 0..360.")
	if quickswitch_reload_factor <= 0.0 or quickswitch_reload_factor > 1.0:
		issues.append("quickswitch_reload_factor must be within 0..1.")
	if enemy_ai_update_interval <= 0.0:
		issues.append("enemy_ai_update_interval must be > 0.")
	if enemy_ai_max_updates_per_tick < 1:
		issues.append("enemy_ai_max_updates_per_tick must be >= 1.")
	if enemy_detection_range <= 0.0 or enemy_shoot_range <= 0.0:
		issues.append("enemy detection/shoot ranges must be > 0.")
	if enemy_move_speed < 0.0 or enemy_acceleration < 0.0:
		issues.append("enemy move speed/acceleration must be >= 0.")
	if enemy_fire_interval <= 0.0 or enemy_damage < 0.0:
		issues.append("enemy fire interval must be > 0 and damage >= 0.")
	if enemy_stop_distance < 0.0 or enemy_strafe_speed < 0.0:
		issues.append("enemy stop distance/strafe speed must be >= 0.")
	if enemy_los_collision_mask < 0:
		issues.append("enemy_los_collision_mask must be >= 0.")
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
