class_name ThreatDetector
extends Node3D

## Peripheral-vision threat detector.
##
## Every `detect_interval` seconds it scans the `highlightable` group (enemies,
## projectiles, ...) and classifies each object by its horizontal angle from the
## player's forward direction:
##
##   FORWARD      |az| <= forward_half_angle     already on screen  -> ignored
##   PERIPHERAL   forward_half < |az| <= end     -> highlighted (if visible)
##   REAR         |az| > end                     blindspot          -> ignored
##
## Eligible objects must also pass a line-of-sight raycast against world
## geometry. Each result carries its angle, distance, LOS and a distance-driven
## `intensity`; `ThreatHighlighter` turns them into red silhouette overlays.
##
## The node lives inside the same 3D world as the player (the projection
## `SubViewport`), so its raycasts use the real physics space and its highlights
## are drawn by the real lens.
##
## All tuning lives in `core/config/game_config.tres`.

signal threats_updated(threats: Array[Threat])

## Shared tuning resource. Assigned in `test_map.tscn`; falls back to defaults.
@export var config: GameConfig

@export_group("Wiring")

## Camera to measure from. Empty = the `player` group node's `Neck/Camera3D`.
@export_node_path("Camera3D") var camera_path: NodePath

## Group the player node belongs to.
@export var player_group: StringName = &"player"

## Group scanned for highlightable objects.
@export var highlightable_group: StringName = &"highlightable"

# --- Outputs -----------------------------------------------------------------
## Eligible threats this update (peripheral zone + clear line of sight).
var threats: Array[Threat] = []
## Number of eligible threats (cheap for the HUD to read).
var eligible_count: int = 0
## One-line readout for the HUD: nearest object's angle, distance, LOS and zone.
var debug_text: String = "—"

var _camera: Camera3D
var _space: PhysicsDirectSpaceState3D

# Reused query state: no per-tick allocations.
var _ray: PhysicsRayQueryParameters3D
var _exclude: Array[RID] = []

var _accum: float = 0.0


func _ready() -> void:
	if config == null:
		config = GameConfig.new()
		push_warning("ThreatDetector: no GameConfig assigned; using defaults.")
	add_to_group(&"threat_detector")

	_ray = PhysicsRayQueryParameters3D.new()
	_ray.collision_mask = config.los_collision_mask
	_ray.collide_with_areas = false
	_ray.collide_with_bodies = true

	_resolve_wiring()

	# One pass as soon as the world is ready, before the first interval elapses.
	call_deferred("refresh_now")


func _physics_process(delta: float) -> void:
	if config.detect_interval <= 0.0:
		refresh_now()
		return

	_accum += delta
	if _accum < config.detect_interval:
		return
	_accum = 0.0
	refresh_now()


## Run one detection pass immediately and emit `threats_updated`.
func refresh_now() -> void:
	if _camera == null or not is_instance_valid(_camera) or _space == null:
		_resolve_wiring()
	if _camera == null or not is_instance_valid(_camera) or _space == null:
		return

	var origin := _camera.global_position
	var basis := _camera.global_transform.basis
	var forward := -basis.z
	var right := basis.x
	var up := basis.y

	var eligible: Array[Threat] = []
	var nearest: Threat = null

	# `get_nodes_in_group` is only called on the detect interval, not per frame.
	for node in get_tree().get_nodes_in_group(highlightable_group):
		var target := node as Node3D
		if target == null or not is_instance_valid(target):
			continue

		var to_target := target.global_position - origin
		var distance := to_target.length()
		if distance < 0.01 or distance > config.max_distance:
			continue

		var dir := to_target / distance
		var azimuth := atan2(dir.dot(right), dir.dot(forward))
		var elevation := asin(clampf(dir.dot(up), -1.0, 1.0))

		var threat := Threat.new()
		threat.target = target
		threat.azimuth_deg = rad_to_deg(azimuth)
		threat.elevation_deg = rad_to_deg(elevation)
		threat.distance = distance
		threat.zone = classify_deg(threat.azimuth_deg)
		threat.intensity = intensity_for(distance)
		threat.los = _has_line_of_sight(origin, target.global_position)

		if nearest == null or threat.distance < nearest.distance:
			nearest = threat

		if threat.zone == Threat.Zone.PERIPHERAL and threat.los:
			eligible.append(threat)

	threats = eligible
	eligible_count = eligible.size()
	_update_debug(nearest)
	threats_updated.emit(threats)


## Classify a horizontal angle (degrees, signed) into a vision zone.
func classify_deg(azimuth_deg: float) -> Threat.Zone:
	var a := absf(azimuth_deg)
	if a <= config.forward_half_angle_deg:
		return Threat.Zone.FORWARD
	if a <= config.peripheral_end_angle_deg:
		return Threat.Zone.PERIPHERAL
	return Threat.Zone.REAR


## Distance -> 0..1 highlight intensity: 1 up close, smoothly fading to 0 at
## `far_distance`. "Brighter in red as it gets closer."
func intensity_for(distance: float) -> float:
	if config.far_distance <= config.near_distance:
		return 1.0
	return 1.0 - smoothstep(config.near_distance, config.far_distance, distance)


## Fold a peripheral angle onto the visible side band: `forward_half .. end`
## maps back toward the forward boundary (e.g. 70->70, 90->50, 110->30). Signs
## are preserved, so the two sides never cross the centre.
func fold_deg(azimuth_deg: float) -> float:
	var a := absf(azimuth_deg)
	var folded := clampf(2.0 * config.forward_half_angle_deg - a, 0.0, config.forward_half_angle_deg)
	return signf(azimuth_deg) * folded


## The active camera, used as the pivot when folding highlights on screen.
func get_camera() -> Camera3D:
	return _camera


# --- Internals ---------------------------------------------------------------

func _has_line_of_sight(from: Vector3, to: Vector3) -> bool:
	_ray.from = from
	_ray.to = to
	_ray.collision_mask = config.los_collision_mask
	_ray.exclude = _exclude
	return _space.intersect_ray(_ray).is_empty()


func _resolve_wiring() -> void:
	var player := _resolve_player()

	_camera = null
	if not camera_path.is_empty():
		_camera = get_node_or_null(camera_path) as Camera3D
	if _camera == null and player != null:
		_camera = player.get_node_or_null("Neck/Camera3D") as Camera3D
	if _camera == null and player != null:
		var c: Variant = player.get("camera")
		if c is Camera3D:
			_camera = c

	_space = get_world_3d().direct_space_state

	# Never let the player's own body block its line of sight.
	_exclude.clear()
	var body := player as CollisionObject3D
	if body != null:
		_exclude.append(body.get_rid())


func _resolve_player() -> Node:
	if player_group == &"":
		return null
	return get_tree().get_first_node_in_group(player_group)


func _update_debug(nearest: Threat) -> void:
	if nearest == null:
		debug_text = "none in range"
		return
	var zone := _zone_name(nearest.zone)
	var los := "yes" if nearest.los else "no"
	debug_text = "%s az %+.0f d %.1fm LOS %s (%s)" % [
		String(nearest.target.name), nearest.azimuth_deg, nearest.distance, los, zone,
	]


func _zone_name(zone: Threat.Zone) -> String:
	match zone:
		Threat.Zone.FORWARD:
			return "fwd"
		Threat.Zone.PERIPHERAL:
			return "periph"
		_:
			return "rear"
