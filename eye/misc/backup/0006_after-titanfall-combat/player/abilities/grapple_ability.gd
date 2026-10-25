class_name GrappleAbility
extends PlayerAbility

## Titanfall-inspired grapple: a raycast-anchored, reel-in rope that preserves
## tangential momentum for swinging.
##
## This node owns *targeting and presentation* only. The physics of the rope
## lives in [PlayerGrappleState] so the movement state machine remains the one
## place that decides how the player moves. Removing this node removes the
## ability cleanly: no state can enter `Grapple`, and no rope is drawn.

## Current anchor in world space. Only meaningful while [member attached].
var anchor: Vector3 = Vector3.ZERO
## Current rope length. The state reels it in over time.
var rope_length: float = 0.0
var attached: bool = false
var cooldown_timer: float = 0.0

var _query: PhysicsRayQueryParameters3D
var _has_cached_hit := false
var _cached_point := Vector3.ZERO
var _cached_normal := Vector3.ZERO
var _cached_collider: Object

var _rope: MeshInstance3D
var _rope_material: StandardMaterial3D
var _anchor_marker: MeshInstance3D
var _marker_material: StandardMaterial3D


func _on_setup() -> void:
	ability_id = &"grapple" if ability_id == &"" else ability_id

	_query = PhysicsRayQueryParameters3D.new()
	_query.collision_mask = player.config.grapple_collision_mask
	_query.collide_with_areas = false
	_query.collide_with_bodies = true
	_query.exclude = [player.get_rid()]

	_build_rope.call_deferred()


func _exit_tree() -> void:
	if is_instance_valid(_rope):
		_rope.queue_free()
	if is_instance_valid(_anchor_marker):
		_anchor_marker.queue_free()


func pre_move_update(delta: float) -> void:
	cooldown_timer = maxf(cooldown_timer - delta, 0.0)
	if attached:
		cooldown_timer = 0.0


func post_move_update(_delta: float) -> void:
	_update_rope()


## Raycast from the camera and cache the first valid anchor. Called only when
## the player presses the grapple button, so it costs nothing while idle.
func can_attach() -> bool:
	if player == null or attached or cooldown_timer > 0.0:
		return false
	if player.camera == null:
		return false

	var origin := player.camera.global_position
	var direction := -player.camera.global_transform.basis.z
	var to := origin + direction * player.config.grapple_max_distance

	_query.from = origin
	_query.to = to
	var hit := player.get_world_3d().direct_space_state.intersect_ray(_query)
	if hit.is_empty():
		_has_cached_hit = false
		return false

	var point: Vector3 = hit.position
	var distance := player.global_position.distance_to(point)
	if distance < player.config.grapple_min_distance \
			or distance > player.config.grapple_max_distance:
		_has_cached_hit = false
		return false

	_cached_point = point
	_cached_normal = hit.normal
	_cached_collider = hit.collider
	_has_cached_hit = true
	return true


## Attaches to the cached hit from [method can_attach].
func attach() -> bool:
	if attached:
		return true
	if not _has_cached_hit and not can_attach():
		return false

	anchor = _cached_point
	rope_length = maxf(
		get_origin().distance_to(anchor), player.config.grapple_rope_min_length
	)
	attached = true
	cooldown_timer = 0.0
	_has_cached_hit = false
	_update_rope()
	return true


func detach() -> void:
	if not attached:
		return
	attached = false
	cooldown_timer = player.config.grapple_cooldown
	_has_cached_hit = false
	_update_rope()


## Reels the rope in, never below the configured minimum.
func reel(delta: float) -> void:
	if not attached:
		return
	rope_length = maxf(
		rope_length - player.config.grapple_reel_speed * delta,
		player.config.grapple_rope_min_length
	)


## Physics origin of the rope (chest height), not the camera. Using the chest
## keeps the pendulum stable when the player looks up or down.
func get_origin() -> Vector3:
	if player == null:
		return Vector3.ZERO
	return player.global_position + Vector3(0.0, 1.2, 0.0)


func get_anchor() -> Vector3:
	return anchor


func get_rope_length() -> float:
	return rope_length


func get_to_anchor() -> Vector3:
	return anchor - get_origin()


func is_attached() -> bool:
	return attached


# --- Presentation ------------------------------------------------------------

func _build_rope() -> void:
	if player == null:
		return
	var hold_parent: Node = player.get_parent()
	if hold_parent == null:
		hold_parent = get_tree().current_scene

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = player.config.grapple_rope_color
	material.emission_enabled = true
	material.emission = player.config.grapple_rope_color
	material.emission_energy_multiplier = 2.0
	_rope_material = material

	var mesh := CylinderMesh.new()
	mesh.height = 1.0
	mesh.top_radius = player.config.grapple_rope_width
	mesh.bottom_radius = player.config.grapple_rope_width
	mesh.radial_segments = 6
	mesh.rings = 1
	mesh.cap_top = false
	mesh.cap_bottom = false

	_rope = MeshInstance3D.new()
	_rope.name = "GrappleRope"
	_rope.mesh = mesh
	_rope.material_override = material
	_rope.top_level = true
	_rope.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rope.visible = false
	hold_parent.add_child(_rope)

	var marker_material := StandardMaterial3D.new()
	marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker_material.albedo_color = player.config.grapple_rope_color
	marker_material.emission_enabled = true
	marker_material.emission = player.config.grapple_rope_color
	marker_material.emission_energy_multiplier = 2.5
	_marker_material = marker_material

	var marker_mesh := SphereMesh.new()
	marker_mesh.radius = 0.09
	marker_mesh.height = 0.18
	marker_mesh.radial_segments = 8
	marker_mesh.rings = 4

	_anchor_marker = MeshInstance3D.new()
	_anchor_marker.name = "GrappleAnchor"
	_anchor_marker.mesh = marker_mesh
	_anchor_marker.material_override = marker_material
	_anchor_marker.top_level = true
	_anchor_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_anchor_marker.visible = false
	hold_parent.add_child(_anchor_marker)


func _update_rope() -> void:
	if not is_instance_valid(_rope) or not is_instance_valid(_anchor_marker) or player == null:
		return
	if not attached:
		_rope.visible = false
		_anchor_marker.visible = false
		return

	var hand := player.camera.global_position \
		+ player.camera.global_transform.basis * Vector3(0.2, -0.14, -0.35)
	var to_anchor := anchor - hand
	var length := to_anchor.length()
	if length < 0.001:
		_rope.visible = false
		_anchor_marker.visible = false
		return

	var direction := to_anchor / length
	var basis := Basis(Quaternion(Vector3.UP, direction))
	_rope.global_transform = Transform3D(
		basis.scaled(Vector3(1.0, length, 1.0)),
		(hand + anchor) * 0.5
	)
	_rope.visible = true
	_anchor_marker.global_position = anchor
	_anchor_marker.visible = true
