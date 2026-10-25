class_name Threat
extends RefCounted

## One highlightable object as seen by [ThreatDetector] this update.
##
## A plain data carrier: the detector fills it in, the highlighter renders it.
## Keeping it separate from both means detection stays testable headlessly and
## the renderer can be swapped without touching the maths.

enum Zone {
	FORWARD,     ## Inside the normal forward FOV — already visible, not highlighted.
	PERIPHERAL,  ## In a left/right peripheral band — highlighted when visible.
	REAR,        ## Behind the player — the blindspot, never highlighted.
}

## The highlightable node this describes.
var target: Node3D

## Horizontal angle from the player's forward direction, in degrees.
## Negative = left, positive = right, 0 = dead ahead, +/-180 = directly behind.
var azimuth_deg: float = 0.0

## Vertical angle from the horizon, in degrees.
var elevation_deg: float = 0.0

## Straight-line distance from the camera, in metres (world units).
var distance: float = 0.0

## 0 = far/edge of range, 1 = point blank. Drives brightness and opacity.
var intensity: float = 0.0

## True when world geometry does not block the line from the camera to `target`.
var los: bool = false

## Which vision zone the angle falls into.
var zone: Zone = Zone.FORWARD


## -1 for the left half, +1 for the right half.
func side() -> int:
	return -1 if azimuth_deg < 0.0 else 1
