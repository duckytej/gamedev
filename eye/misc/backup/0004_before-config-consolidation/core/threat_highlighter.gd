class_name ThreatHighlighter
extends Node3D

## Turns [ThreatDetector]'s eligible threats into red silhouette overlays.
##
## Objects in the 70..110 deg peripheral zones sit outside the rendered Panini
## frustum, so they cannot be drawn where they are. Rather than add extra
## cameras, each eligible object gets a *ghost*: a copy of its meshes placed at
## a folded azimuth, so the real lens renders the ghost's exact shape in the
## side band — correct projection, correct occlusion-free overlay, no extra
## passes.
##
## The fold mirrors the over-the-shoulder part of the view back onto the near
## periphery:
##
##     display angle = sign(a) * (2 * forward_half_angle - |a|)
##
## so a body at +70 deg lands on the outer screen edge, +80 deg a little inward,
## and +110 deg right next to the +30 deg boundary — "70 at the edge, 110 closer
## to the centre, both on the right". The middle 60 deg (|a| < 30) is never
## covered.
##
## The ghost is a rigid rotation of the real object about the vertical axis
## through the camera, so its silhouette, size, distance and orientation are
## exact. It uses an unshaded, depth-test-disabled, distance-faded red material:
## the body keeps its normal colour and the overlay floats on top.
##
## Lives in the same 3D world as the detector (inside the projection
## SubViewport), so it is drawn by the real lens, Panini warp and all.

## Optional explicit detector. Empty = first node in `detector_group`.
@export var detector_path: NodePath

## Group used to find the detector when `detector_path` is empty.
@export var detector_group: StringName = &"threat_detector"

var _detector: ThreatDetector

## body (Node3D) -> ghost root (Node3D)
var _ghosts: Dictionary = {}
## body (Node3D) -> Array[StandardMaterial3D] used by the ghost
var _materials: Dictionary = {}
## Bodies eligible at the last detection tick. Placement is refreshed every
## frame so the overlay stays glued to the screen band while the player turns.
var _active: Array[Node3D] = []


func _ready() -> void:
	add_to_group(&"threat_highlighter")
	_resolve_detector()


func _process(_delta: float) -> void:
	if _detector == null or _active.is_empty():
		return
	var camera := _detector.get_camera()
	if camera == null:
		return

	for body in _active:
		if not is_instance_valid(body):
			continue
		var ghost: Node3D = _ghosts.get(body)
		if ghost == null or not is_instance_valid(ghost):
			continue

		# Re-derive the bearing from the *current* camera, not the last tick's
		# snapshot, so turning the head never drags the overlay behind.
		var azimuth_deg := _azimuth_deg(camera, body)
		if _detector.classify_deg(azimuth_deg) != Threat.Zone.PERIPHERAL:
			ghost.visible = false
			continue
		ghost.visible = true
		_place(ghost, body, camera, azimuth_deg)


func _resolve_detector() -> void:
	var node: Node = null
	if not detector_path.is_empty():
		node = get_node_or_null(detector_path)
	if node == null and detector_group != &"":
		node = get_tree().get_first_node_in_group(detector_group)
	if node is ThreatDetector:
		_detector = node
		if not _detector.threats_updated.is_connected(_on_threats_updated):
			_detector.threats_updated.connect(_on_threats_updated)


func _on_threats_updated(threats: Array[Threat]) -> void:
	if _detector == null:
		_resolve_detector()
	if _detector == null:
		return
	_sync(threats)


func _sync(threats: Array[Threat]) -> void:
	var camera := _detector.get_camera()
	if camera == null:
		return

	var live := {}
	_active.clear()
	for threat in threats:
		var body: Node3D = threat.target
		if body == null or not is_instance_valid(body):
			continue
		live[body] = true
		_active.append(body)
		var ghost := _ghost_for(body)
		_place(ghost, body, camera, threat.azimuth_deg)
		ghost.visible = true
		_style(body, threat.intensity)

	# Hide (and forget) anything no longer eligible.
	for body in _ghosts.keys():
		if not is_instance_valid(body):
			var stale: Node3D = _ghosts[body]
			if is_instance_valid(stale):
				stale.queue_free()
			_ghosts.erase(body)
			_materials.erase(body)
			continue
		if not live.has(body):
			var ghost: Node3D = _ghosts[body]
			if is_instance_valid(ghost):
				ghost.visible = false


# --- Ghost placement ---------------------------------------------------------

## Move a ghost so a rigid rotation about the camera's up-axis puts the body at
## its folded, on-screen azimuth.
func _place(ghost: Node3D, body: Node3D, camera: Camera3D, azimuth_deg: float) -> void:
	var display_deg := _detector.fold_deg(azimuth_deg)
	# A positive rotation about +Y *decreases* the azimuth (atan2(x, -z)), so a
	# body must be rotated by (azimuth - display) to land on the folded bearing.
	var twist := deg_to_rad(azimuth_deg - display_deg)

	var pivot := camera.global_position
	var body_transform := body.global_transform
	var offset := body_transform.origin - pivot
	var rotate := Basis(Vector3.UP, twist)

	ghost.global_transform = Transform3D(
		rotate * body_transform.basis,
		pivot + offset.rotated(Vector3.UP, twist)
	)


## Horizontal bearing of `body` from the camera, in signed degrees.
func _azimuth_deg(camera: Camera3D, body: Node3D) -> float:
	var basis := camera.global_transform.basis
	var offset := body.global_position - camera.global_position
	var azimuth := atan2(offset.dot(basis.x), offset.dot(-basis.z))
	return rad_to_deg(azimuth)


func _style(body: Node3D, intensity: float) -> void:
	var mats: Array = _materials.get(body, [])
	var alpha := lerpf(_detector.min_alpha, _detector.max_alpha, intensity)
	var brightness := lerpf(0.55, 1.0, intensity)
	var base := _detector.highlight_color
	var color := Color(
		base.r * brightness,
		base.g * brightness,
		base.b * brightness,
		alpha
	)
	for material in mats:
		if material.albedo_color != color:
			material.albedo_color = color


# --- Ghost construction ------------------------------------------------------

func _ghost_for(body: Node3D) -> Node3D:
	if _ghosts.has(body) and is_instance_valid(_ghosts[body]):
		return _ghosts[body]
	var ghost := _build_ghost(body)
	add_child(ghost)
	_ghosts[body] = ghost
	return ghost


## Replicate a body's visible meshes as ghosts. Works whether the body is a
## [MeshInstance3D] itself or a rig with mesh children.
func _build_ghost(body: Node3D) -> Node3D:
	var mats: Array[StandardMaterial3D] = []

	var root: Node3D
	var self_mesh := body as MeshInstance3D
	if self_mesh != null and self_mesh.mesh != null:
		root = _make_mesh_ghost(self_mesh.mesh, Transform3D.IDENTITY, mats)
	else:
		root = Node3D.new()
		var inverse := body.global_transform.affine_inverse()
		for mesh_instance in _find_meshes(body):
			var local := inverse * mesh_instance.global_transform
			root.add_child(_make_mesh_ghost(mesh_instance.mesh, local, mats))

	_materials[body] = mats
	return root


func _make_mesh_ghost(
	mesh: Mesh, transform: Transform3D, mats: Array[StandardMaterial3D]
) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	material.albedo_color = _detector.highlight_color
	mats.append(material)

	var ghost := MeshInstance3D.new()
	ghost.mesh = mesh
	ghost.transform = transform
	ghost.material_override = material
	ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ghost.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	return ghost


func _find_meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for child in node.get_children():
		var mesh_instance := child as MeshInstance3D
		if mesh_instance != null and mesh_instance.mesh != null:
			out.append(mesh_instance)
		out.append_array(_find_meshes(child))
	return out
