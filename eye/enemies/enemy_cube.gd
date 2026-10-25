class_name EnemyCube
extends CharacterBody3D

## Moving, shooting enemy.
##
## The enemy owns health, presentation and movement integration, but **not** its
## own AI clock. An [EnemyDirector] calls [method think] on a round-robin schedule
## and passes the accumulated time, so N enemies never all raycast/shoot on the
## same physics tick. Without a director the enemy stays put (which is also what
## keeps the deterministic weapon tests static).
##
## Health is a child [HealthComponent], so [Damage] can find it on any collider
## that is part of this body. The floating label is presentation only.

@export var config: GameConfig
@export var ai_enabled: bool = true

@onready var health: HealthComponent = $Health
@onready var mesh: MeshInstance3D = $Mesh
@onready var label: Label3D = $HealthLabel

## Set by the director. A very small time quantum (the director's accumulated
## delta) is passed back into [method think].
var think_accumulator: float = 0.0
var think_count: int = 0
var shots_fired: int = 0

var _label_time_left := 0.0
var _flash_tween: Tween
var _director: Node
var _player: EyePlayer
var _los_query: PhysicsRayQueryParameters3D

var _stagger_left := 0.0
var _fire_cooldown := 0.0
var _strafe_sign := 1.0
var _ai_active := false


func _ready() -> void:
	add_to_group(&"highlightable")
	add_to_group(&"damageable")
	add_to_group(&"enemy")

	if mesh.material_override != null:
		# Scene sub-resources are shared by every instance; duplicate so one
		# enemy's hit flash cannot tint every other cube.
		mesh.material_override = mesh.material_override.duplicate()

	health.died.connect(_on_died)
	health.damaged.connect(_on_damaged)
	health.health_changed.connect(_on_health_changed)

	var maximum := config.enemy_max_health if config != null else health.max_health
	health.configure(maximum)
	label.visible = false

	_los_query = PhysicsRayQueryParameters3D.new()
	_los_query.collision_mask = config.enemy_los_collision_mask if config != null else 1
	_los_query.collide_with_areas = false
	_los_query.collide_with_bodies = true
	_los_query.exclude = [get_rid()]

	_strafe_sign = -1.0 if randf() < 0.5 else 1.0
	_fire_cooldown = randf_range(0.35, 1.0) * _fire_interval()
	call_deferred("_register_with_director")


func _physics_process(delta: float) -> void:
	if health == null or not health.is_alive():
		return

	if not is_on_floor():
		velocity += get_gravity() * delta
	else:
		velocity.y = 0.0

	if not _ai_active or not ai_enabled or _stagger_left > 0.0:
		var braking := _acceleration() * delta
		velocity.x = move_toward(velocity.x, 0.0, braking)
		velocity.z = move_toward(velocity.z, 0.0, braking)

	move_and_slide()


func _process(delta: float) -> void:
	if _label_time_left <= 0.0:
		return
	_label_time_left -= delta
	if _label_time_left <= 0.0:
		label.visible = false


# --- Director / AI ------------------------------------------------------------

func set_director(director: Node) -> void:
	_director = director


func set_ai_active(active: bool) -> void:
	_ai_active = active
	if not active:
		velocity.x = 0.0
		velocity.z = 0.0


## One AI decision tick. Called only by [EnemyDirector]. `delta` is the time
## accumulated since this enemy last thought, so movement and cooldowns stay in
## seconds rather than frames.
func think(delta: float) -> void:
	think_count += 1
	if health == null or not health.is_alive() or not ai_enabled:
		return

	_fire_cooldown = maxf(_fire_cooldown - delta, 0.0)
	if _stagger_left > 0.0:
		_stagger_left = maxf(_stagger_left - delta, 0.0)
		velocity.x = 0.0
		velocity.z = 0.0
		return

	var player := _find_player()
	if player == null:
		return

	var target := player.global_position \
		+ Vector3.UP * (config.enemy_aim_height if config != null else 1.2)
	var origin := _eye_position()
	var flat := target - global_position
	flat.y = 0.0
	var distance := flat.length()
	if distance < 0.001:
		return

	_look_at_target(target)
	var los := _has_line_of_sight(origin, target)

	var detection := _detection_range()
	var desired := Vector3.ZERO
	var stop := config.enemy_stop_distance if config != null else 6.0
	if distance > detection:
		# Out of detection range: hold position instead of chasing across the map.
		pass
	elif distance > stop:
		desired = flat.normalized() * _move_speed()
	elif distance < stop * 0.6:
		desired = -flat.normalized() * _move_speed() * 0.7
	else:
		# Circle the player instead of standing in a perfect line.
		var tangent := Vector3(-flat.z, 0.0, flat.x).normalized()
		desired = tangent * (_strafe_speed() * _strafe_sign)

	var accel := _acceleration() * delta
	velocity.x = move_toward(velocity.x, desired.x, accel)
	velocity.z = move_toward(velocity.z, desired.z, accel)

	if los \
			and distance <= minf(_shoot_range(), detection) \
			and _fire_cooldown <= 0.0:
		_shoot(player, origin, target)


func _find_player() -> EyePlayer:
	if _player != null and is_instance_valid(_player) and not _player.is_dead():
		return _player
	_player = get_tree().get_first_node_in_group(&"player") as EyePlayer
	if _player != null and _player.is_dead():
		return null
	return _player


func _look_at_target(target: Vector3) -> void:
	var flat := target - global_position
	flat.y = 0.0
	if flat.length_squared() < 0.001:
		return
	var yaw := atan2(-flat.x, -flat.z)
	rotation.y = lerp_angle(rotation.y, yaw, 0.35)


func _has_line_of_sight(origin: Vector3, target: Vector3) -> bool:
	if _los_query == null:
		return false
	_los_query.from = origin
	_los_query.to = target
	var hit := get_world_3d().direct_space_state.intersect_ray(_los_query)
	return hit.is_empty()


func _shoot(player: EyePlayer, origin: Vector3, target: Vector3) -> void:
	_fire_cooldown = _fire_interval() * randf_range(0.85, 1.2)

	# A timed sword parry negates the shot and staggers the shooter.
	if player.try_parry(global_position):
		var parry_time := config.sword_parry_stagger_time if config != null else 2.0
		stagger(parry_time)
		return

	var direction := (target - origin).normalized()
	Damage.apply(player, _damage(), self, target, -direction)
	shots_fired += 1
	_spawn_tracer(origin, target, _tracer_color())


func stagger(duration: float) -> void:
	if duration <= 0.0 or health == null or not health.is_alive():
		return
	_stagger_left = maxf(_stagger_left, duration)
	velocity.x = 0.0
	velocity.z = 0.0
	_fire_cooldown = maxf(_fire_cooldown, duration)
	_flash(_stagger_color())


func get_stagger_left() -> float:
	return _stagger_left


func _register_with_director() -> void:
	var director := get_tree().get_first_node_in_group(&"enemy_director")
	if director != null and director.has_method("register_enemy"):
		director.call("register_enemy", self)


func _eye_position() -> Vector3:
	return global_position + Vector3.UP * 0.45


func _move_speed() -> float:
	return config.enemy_move_speed if config != null else 3.8


func _strafe_speed() -> float:
	return config.enemy_strafe_speed if config != null else 2.2


func _acceleration() -> float:
	return config.enemy_acceleration if config != null else 10.0


func _shoot_range() -> float:
	return config.enemy_shoot_range if config != null else 18.0


func _detection_range() -> float:
	return config.enemy_detection_range if config != null else 28.0


func _fire_interval() -> float:
	return config.enemy_fire_interval if config != null else 1.1


func _damage() -> float:
	return config.enemy_damage if config != null else 8.0


func _tracer_color() -> Color:
	return config.enemy_tracer_color if config != null else Color(1.0, 0.35, 0.25)


func _stagger_color() -> Color:
	return config.enemy_stagger_color if config != null else Color(0.35, 0.75, 1.0)


func _spawn_tracer(from: Vector3, to: Vector3, color: Color) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 2.0

	var immediate := ImmediateMesh.new()
	immediate.surface_begin(Mesh.PRIMITIVE_LINES, material)
	immediate.surface_add_vertex(from)
	immediate.surface_add_vertex(to)
	immediate.surface_end()

	var tracer := MeshInstance3D.new()
	tracer.name = "EnemyTracer"
	tracer.mesh = immediate
	tracer.top_level = true
	tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(tracer)
	get_tree().create_timer(0.065).timeout.connect(tracer.queue_free)


# --- Health / presentation ----------------------------------------------------

func _on_health_changed(current: float, maximum: float) -> void:
	label.text = "%d" % int(ceil(current))
	label.modulate = Color(1.0, 1.0, 1.0).lerp(Color(1.0, 0.3, 0.25), 1.0 - current / maximum)
	if current < maximum:
		label.visible = true
		_label_time_left = config.enemy_health_label_time if config != null else 2.0


func _on_damaged(_amount: float, _current: float, _source: Node) -> void:
	_flash(Color(1.0, 0.55, 0.25))


func _flash(color: Color) -> void:
	var material := mesh.material_override as StandardMaterial3D
	if material == null:
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	material.emission_enabled = true
	material.emission = color * 3.0
	_flash_tween = create_tween()
	var flash_time := config.enemy_hit_flash_time if config != null else 0.18
	_flash_tween.tween_property(material, "emission", Color.BLACK, flash_time)


func _on_died(_source: Node) -> void:
	remove_from_group(&"highlightable")
	remove_from_group(&"damageable")
	remove_from_group(&"enemy")
	_ai_active = false
	velocity = Vector3.ZERO
	set_physics_process(false)
	collision_layer = 0
	collision_mask = 0
	label.visible = false

	var fade := config.enemy_death_fade if config != null else 0.28
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(mesh, "scale", Vector3.ZERO, fade) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property(mesh, "rotation", Vector3(0.0, PI, 0.0), fade)
	tween.chain().tween_callback(queue_free)
