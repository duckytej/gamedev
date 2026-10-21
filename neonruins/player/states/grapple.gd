extends State

## Spiderman-style pendulum grapple.
## Preserves tangential velocity for swing arcs; steer input adds lateral force.
## Rope constrains distance to anchor; radial velocity is killed each frame.

var _anchor: Vector3 = Vector3.ZERO
var _rope_length: float = 0.0
var _line: MeshInstance3D = null

@export var steer_force: float = 14.0
@export var radial_kill_strength: float = 12.0


func enter() -> void:
	if not player.grapple_raycast.is_colliding() or player.grapple_cooldown_timer > 0.0:
		player.transition_to("InAir")
		return

	_anchor = player.grapple_raycast.get_collision_point()
	_rope_length = player.global_position.distance_to(_anchor)
	player.floor_snap_length = 0.0
	player.gravity_scale = player.grapple_gravity_mult

	_line = _create_line()
	SignalBus.player_grapple_started.emit(player)


func physics_process(delta: float) -> void:
	var to_anchor := _anchor - player.global_position
	var dist := to_anchor.length()

	if dist < 0.1:
		retract()
		return

	var dir_to_anchor := to_anchor / dist

	# Decompose velocity into radial (along rope) and tangential (perpendicular)
	var radial_speed := player.velocity.dot(dir_to_anchor)
	var radial_vel := dir_to_anchor * radial_speed
	var tangential_vel := player.velocity - radial_vel

	# Kill radial velocity to enforce rope constraint (inextensible rope)
	tangential_vel += radial_vel * (-radial_kill_strength * delta)

	# If player drifted beyond rope length, snap back
	if dist > _rope_length + 0.1:
		var overshoot := dist - _rope_length
		tangential_vel += dir_to_anchor * overshoot * radial_kill_strength * delta

	# Steer input adds tangential velocity perpendicular to rope in horizontal plane
	var steer_input := Input.get_axis("move_left", "move_right")
	if absf(steer_input) > 0.1:
		var rope_h := Vector3(dir_to_anchor.x, 0.0, dir_to_anchor.z)
		if rope_h.length_squared() > 0.001:
			rope_h = rope_h.normalized()
			var steer_dir := Vector3(-rope_h.z, 0.0, rope_h.x)
			tangential_vel += steer_dir * steer_input * steer_force * delta

	player.velocity = tangential_vel

	# Normal gravity still applies (creates the pendulum arc)
	player.gravity_scale = player.grapple_gravity_mult
	_update_line()

	# Release conditions
	if dist < player.grapple_min_distance or Input.is_action_just_released("grapple"):
		retract()
		return

	if Input.is_action_just_pressed("jump"):
		# Supercharge launch off the rope
		player.velocity += dir_to_anchor * player.grapple_launch_vel
		player.velocity.y = maxf(player.velocity.y, player.jump_velocity * 0.7)
		retract()
		player.transition_to("InAir")
		return

	if player.try_dash():
		retract()
		player.transition_to("Dash")
		return


func retract() -> void:
	player.floor_snap_length = 0.5
	player.gravity_scale = 1.0
	SignalBus.player_grapple_ended.emit(player)

	if _line:
		_line.queue_free()
		_line = null

	if player.is_on_floor():
		player.transition_to("Walk")
	else:
		player.transition_to("InAir")


func exit() -> void:
	if _line:
		_line.queue_free()
		_line = null


func _create_line() -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var mesh := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.0, 1.0, 0.85)
	mat.emission_enabled = true
	mat.emission = Color(0.0, 1.0, 0.85) * 2.0
	mesh_instance.mesh = mesh
	mesh_instance.top_level = true
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	mesh.surface_add_vertex(player.global_position + Vector3(0, 1.6, 0))
	mesh.surface_add_vertex(_anchor)
	mesh.surface_end()
	player.get_tree().current_scene.add_child(mesh_instance)
	return mesh_instance


func _update_line() -> void:
	if not _line or not _line.mesh:
		return
	var mesh := _line.mesh as ImmediateMesh
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	mesh.surface_add_vertex(player.camera.global_position - player.camera.global_basis.z * 0.3)
	mesh.surface_add_vertex(_anchor)
	mesh.surface_end()
