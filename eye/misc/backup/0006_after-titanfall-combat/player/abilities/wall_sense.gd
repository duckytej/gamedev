class_name WallSense
extends PlayerAbility

## Side probes for Titanfall-style wall running.
##
## Two rays per side (chest and knee height) are used instead of relying on
## `is_on_wall()`. `is_on_wall()` only reports a collision that already happened
## and has no idea which side the wall is on; proactive probes let the
## [PlayerWallRunState] commit to a side before contact, and still work while the
## body is sliding parallel to the surface.
##
## Every ray points outward from the capsule, so the returned normal faces back
## toward the player. A surface counts as a wall only when it is steep enough:
## ramps and stairs are rejected and stay normal walkable geometry.

@onready var _left_upper: RayCast3D = $LeftUpper
@onready var _left_lower: RayCast3D = $LeftLower
@onready var _right_upper: RayCast3D = $RightUpper
@onready var _right_lower: RayCast3D = $RightLower

var _probes: Dictionary = {}
## Local probe offsets captured before the rays are made top-level. They are
## re-oriented around the camera yaw every tick, so "left/right" always means
## screen-left/screen-right rather than world X.
var _probe_offsets: Dictionary = {}


func _on_setup() -> void:
	ability_id = &"wall_sense" if ability_id == &"" else ability_id
	_probes = {
		-1: [_left_upper, _left_lower],
		1: [_right_upper, _right_lower],
	}

	for side in [-1, 1]:
		var offsets: Array[Vector3] = []
		for ray in _probes[side]:
			offsets.append(ray.position)
			ray.top_level = true
			ray.collision_mask = PhysicsLayers.WORLD
		_probe_offsets[side] = offsets

	pre_move_update(0.0)


func pre_move_update(_delta: float) -> void:
	if player == null:
		return

	var right := _view_right()
	var reach := player.config.wall_detect_distance
	for side in [-1, 1]:
		var rays: Array = _probes.get(side, [])
		var offsets: Array = _probe_offsets.get(side, [])
		for index in rays.size():
			var ray: RayCast3D = rays[index]
			var offset: Vector3 = offsets[index]
			ray.global_transform = Transform3D(
				Basis.IDENTITY, player.global_position + right * offset.x + Vector3.UP * offset.y
			)
			ray.target_position = right * reach * float(side)
			ray.force_raycast_update()


func _view_right() -> Vector3:
	# Use the yaw value rather than the camera basis so probes see this tick's
	# mouse input instead of last frame's pose.
	var right := Basis(Vector3.UP, player.get_view_yaw()).x
	right.y = 0.0
	if right.length_squared() < 1e-6:
		return Vector3.RIGHT
	return right.normalized()


## True when either side has a runnable wall.
func has_wall() -> bool:
	return get_wall(-1).size() > 0 or get_wall(1).size() > 0


## Returns `{point, normal, collider, side}` for `side` (-1 left, +1 right), or
## an empty dictionary. The upper probe wins because it samples the surface the
## player's chest actually follows; the lower one catches ledges.
func get_wall(side: int) -> Dictionary:
	if player == null:
		return {}
	for ray in _probes.get(side, []):
		if not ray.is_colliding():
			continue
		var normal: Vector3 = ray.get_collision_normal()
		if not is_wall_normal(normal):
			continue
		return {
			"point": ray.get_collision_point(),
			"normal": normal,
			"collider": ray.get_collider(),
			"side": side,
		}
	return {}


## A surface is runnable when it is closer to vertical than
## `wall_run_min_angle_deg`. The normal of a vertical wall is horizontal (90 deg
## from up); a 45-deg ramp is rejected.
func is_wall_normal(normal: Vector3) -> bool:
	var unit := normal.normalized()
	# A runnable surface must be close to vertical. Testing only the angle from
	# UP would also accept downward-facing overhangs, so bound |y| instead.
	var max_vertical := cos(deg_to_rad(player.config.wall_run_min_angle_deg))
	return absf(unit.y) <= max_vertical


## Picks the wall the player is steering toward. When there is no lateral input,
## the current horizontal velocity decides, so simply running alongside a wall
## still starts a run.
func preferred_side() -> int:
	if player == null:
		return 0
	if absf(player.input.move.x) > 0.15:
		return -1 if player.input.move.x < 0.0 else 1
	var lateral := player.velocity.dot(_view_right())
	if absf(lateral) > 1.0:
		return -1 if lateral < 0.0 else 1
	if get_wall(-1).size() > 0 and get_wall(1).size() == 0:
		return -1
	if get_wall(1).size() > 0 and get_wall(-1).size() == 0:
		return 1
	return 0
