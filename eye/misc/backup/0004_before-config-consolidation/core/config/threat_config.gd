class_name ThreatConfig
extends ConfigResource

## Single source of truth for the peripheral-vision threat detector.
##
## Assign on a [ThreatDetector]; every field is copied onto the detector's
## runtime fields with duck-typed `Object.set()` (see [ConfigResource]), exactly
## like the movement and lens profiles. Edit the `.tres`, not the code.
##
## Angle convention: measured horizontally from the player's forward direction,
## 0 = dead ahead, negative = left, positive = right. The forward FOV is
## `+/-forward_half_angle_deg` (70 deg each side = the 140 deg Panini view),
## peripheral vision runs out to `peripheral_end_angle_deg` (110 deg), and
## everything beyond is the rear blindspot.

@export_group("Zones")

## Half-width of the normal forward view, in degrees (70 => a 140 deg view).
@export_range(1.0, 179.0, 0.5) var forward_half_angle_deg: float = 70.0

## Outer edge of peripheral vision, in degrees. Beyond this is the blindspot.
@export_range(1.0, 179.0, 0.5) var peripheral_end_angle_deg: float = 110.0

@export_group("Range")

## Objects farther than this are ignored entirely.
@export var max_distance: float = 30.0

## At (or closer than) this distance a highlight is at full intensity.
@export var near_distance: float = 4.0

## At this distance a highlight has faded out. `near < far <= max_distance`.
@export var far_distance: float = 22.0

@export_group("Detection")

## Seconds between detection passes. 0 = every physics tick.
@export var detect_interval: float = 0.05

## Physics layers that block line of sight (world geometry). Highlightable
## objects must live on a different layer so they never occlude each other.
@export_flags_3d_physics var los_collision_mask: int = 1

@export_group("Highlight")

## Highlight colour. Distance scales brightness, not hue.
@export var highlight_color: Color = Color(1.0, 0.18, 0.16)

## Opacity of a faded-out (far) highlight.
@export_range(0.0, 1.0, 0.01) var min_alpha: float = 0.12

## Opacity of a point-blank highlight.
@export_range(0.0, 1.0, 0.01) var max_alpha: float = 0.9


func apply_to(target: Object) -> void:
	if target == null:
		push_warning("ThreatConfig.apply_to: target is null.")
		return

	apply_values(target, {
		"forward_half_angle_deg": forward_half_angle_deg,
		"peripheral_end_angle_deg": peripheral_end_angle_deg,
		"max_distance": max_distance,
		"near_distance": near_distance,
		"far_distance": far_distance,
		"detect_interval": detect_interval,
		"los_collision_mask": los_collision_mask,
		"highlight_color": highlight_color,
		"min_alpha": min_alpha,
		"max_alpha": max_alpha,
	})
