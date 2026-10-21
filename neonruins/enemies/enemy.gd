extends CharacterBody3D
class_name Enemy

enum EnemyState { IDLE, PATROL, CHASE, ATTACK, STAGGER, HURT, DEAD }
enum EnemyType { GRUNT, HEAVY, SNIPER, BOSS }

@export var enemy_type: EnemyType = EnemyType.GRUNT

# Config (overridden per type in _apply_type_stats)
@export var move_speed: float = 7.0
@export var run_speed: float = 12.0
@export var attack_range: float = 2.5
@export var detection_range: float = 30.0
@export var attack_damage: float = 18.0
@export var attack_cooldown: float = 1.8
@export var hurt_duration: float = 0.4
@export var stagger_threshold: float = 30.0
@export var stagger_duration: float = 1.2
@export var gravity: float = 24.0
@export var turn_speed: float = 8.0
@export var patrol_radius: float = 15.0
@export var lose_target_time: float = 5.0

# Components
@onready var health_component: HealthComponent = $HealthComponent
@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var hurtbox: HurtboxComponent = $HurtboxComponent
@onready var hitbox: HitboxComponent = $HitboxComponent
@onready var animation_player: AnimationPlayer = $AnimationPlayer

# Runtime
var current_state: EnemyState = EnemyState.IDLE
var attack_timer: float = 0.0
var hurt_timer: float = 0.0
var stagger_timer: float = 0.0
var target: Node3D = null
var target_lost_timer: float = 0.0
var patrol_target: Vector3 = Vector3.ZERO
var spawn_position: Vector3 = Vector3.ZERO
var accumulated_stagger: float = 0.0
var is_staggered: bool = false
var _attack_window_id: int = 0


func _ready() -> void:
	spawn_position = global_position

	# SubResources are shared between all instances of the scene; duplicate so
	# per-type tinting and death darkening don't affect every enemy.
	var mat := mesh.material_override
	if mat:
		mesh.material_override = mat.duplicate()

	health_component.died.connect(_on_died)
	hurtbox.damaged.connect(_on_hurt)

	_apply_type_stats()
	_get_new_patrol_target()


func _exit_tree() -> void:
	Globals.unregister_enemy(self)


func _apply_type_stats() -> void:
	match enemy_type:
		EnemyType.GRUNT:
			move_speed = 7.0
			run_speed = 12.0
			attack_damage = 15.0
			attack_range = 2.4
			health_component.max_health = 60.0
			stagger_threshold = 30.0
		EnemyType.HEAVY:
			move_speed = 4.5
			run_speed = 7.0
			attack_damage = 35.0
			attack_range = 3.0
			attack_cooldown = 2.5
			health_component.max_health = 200.0
			stagger_threshold = 60.0
			mesh.scale = Vector3(1.3, 1.3, 1.3)
		EnemyType.SNIPER:
			move_speed = 8.0
			run_speed = 14.0
			attack_damage = 25.0
			attack_range = 40.0
			detection_range = 60.0
			attack_cooldown = 3.0
			health_component.max_health = 40.0
			stagger_threshold = 20.0
		EnemyType.BOSS:
			move_speed = 6.0
			run_speed = 10.0
			attack_damage = 50.0
			attack_range = 4.0
			attack_cooldown = 2.0
			health_component.max_health = 500.0
			stagger_threshold = 100.0
			mesh.scale = Vector3(1.8, 1.8, 1.8)

	if mesh.material_override:
		match enemy_type:
			EnemyType.GRUNT:
				mesh.material_override.albedo_color = Color(0.45, 0.15, 0.15)
			EnemyType.HEAVY:
				mesh.material_override.albedo_color = Color(0.55, 0.1, 0.1)
			EnemyType.SNIPER:
				mesh.material_override.albedo_color = Color(0.2, 0.3, 0.5)
			EnemyType.BOSS:
				mesh.material_override.albedo_color = Color(0.7, 0.1, 0.1)

	health_component.current_health = health_component.max_health


func _physics_process(delta: float) -> void:
	if current_state == EnemyState.DEAD:
		return

	if not is_on_floor():
		velocity.y -= gravity * delta

	match current_state:
		EnemyState.IDLE:
			_state_idle(delta)
		EnemyState.PATROL:
			_state_patrol(delta)
		EnemyState.CHASE:
			_state_chase(delta)
		EnemyState.ATTACK:
			_state_attack(delta)
		EnemyState.STAGGER:
			_state_stagger()
		EnemyState.HURT:
			_state_hurt(delta)

	attack_timer = maxf(attack_timer - delta, 0.0)

	# Stagger recovery drains built-up poise damage
	if is_staggered:
		stagger_timer -= delta
		if stagger_timer <= 0.0:
			is_staggered = false
			current_state = EnemyState.CHASE if target else EnemyState.PATROL

	move_and_slide()


func _state_idle(_delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 8.0)
	velocity.z = move_toward(velocity.z, 0.0, 8.0)

	target = _find_target()
	if target:
		current_state = EnemyState.CHASE
		return

	if randf() < 0.01:
		_get_new_patrol_target()
		current_state = EnemyState.PATROL


func _state_patrol(delta: float) -> void:
	target = _find_target()
	if target:
		current_state = EnemyState.CHASE
		return

	if patrol_target == Vector3.ZERO or global_position.distance_to(patrol_target) < 2.0:
		_get_new_patrol_target()
		return

	var dir := patrol_target - global_position
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.ZERO
	velocity.x = dir.x * move_speed * 0.5
	velocity.z = dir.z * move_speed * 0.5
	_face_direction(dir, delta)


func _state_chase(delta: float) -> void:
	if not target or not is_instance_valid(target):
		target = null
		target_lost_timer = lose_target_time
		current_state = EnemyState.PATROL
		return

	var to_target := target.global_position - global_position
	var dist := to_target.length()
	var dir := Vector3(to_target.x, 0.0, to_target.z).normalized()

	# Enter attack range
	if dist < attack_range and attack_timer <= 0.0:
		current_state = EnemyState.ATTACK
		return

	# Lose interest when far away for a while
	if dist > detection_range * 1.5:
		target_lost_timer -= delta
		if target_lost_timer <= 0.0:
			target = null
			current_state = EnemyState.PATROL
			return
	else:
		target_lost_timer = lose_target_time

	# Sprint when far, walk when closing in
	var speed := run_speed if dist > attack_range * 2.0 else move_speed
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	_face_direction(dir, delta)

	# Strafe while circling in combat range
	if dist < attack_range * 3.0 and dist > attack_range:
		var strafe_sign := 1.0 if fmod(Time.get_ticks_msec() * 0.001 + get_instance_id(), 2.0) > 1.0 else -1.0
		var perp := Vector3(-dir.z, 0.0, dir.x) * strafe_sign
		velocity += perp * move_speed * 0.3


func _state_attack(delta: float) -> void:
	if not target or not is_instance_valid(target):
		current_state = EnemyState.CHASE
		return

	# Face target quickly
	var dir := target.global_position - global_position
	dir.y = 0.0
	_face_direction(dir.normalized(), delta * 2.0)

	# Hold position during wind-up
	velocity.x = move_toward(velocity.x, 0.0, 15.0)
	velocity.z = move_toward(velocity.z, 0.0, 15.0)

	if attack_timer <= 0.0:
		attack_timer = attack_cooldown
		_execute_attack()

	# Target fled mid-attack
	var dist := global_position.distance_to(target.global_position)
	if dist > attack_range * 1.6:
		current_state = EnemyState.CHASE


func _execute_attack() -> void:
	match enemy_type:
		EnemyType.SNIPER:
			_execute_ranged_attack()
		EnemyType.BOSS:
			if randf() < 0.4:
				_execute_heavy_attack()
			else:
				_execute_melee_attack(0.35, 1.5)
			_create_shockwave()
		_:
			_execute_melee_attack(0.25, 1.0)


func _open_hitbox_window(damage_mult: float, window: float) -> void:
	hitbox.damage = attack_damage * damage_mult
	hitbox.active = true
	_attack_window_id += 1
	var id := _attack_window_id
	var timer := get_tree().create_timer(window)
	timer.timeout.connect(func() -> void:
		if id == _attack_window_id and hitbox:
			hitbox.active = false
	)


func _execute_melee_attack(dmg_mult: float, window: float) -> void:
	_open_hitbox_window(dmg_mult, window)
	_play_animation("attack")


func _execute_heavy_attack() -> void:
	_open_hitbox_window(1.5, 0.45)
	_play_animation("heavy_attack")


func _execute_ranged_attack() -> void:
	if not target or not is_instance_valid(target):
		return

	var from := global_position + Vector3(0, 1.6, 0)
	var aim_at := target.global_position + Vector3(0, 1.0, 0)

	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, aim_at)
	query.collide_with_areas = true
	query.collision_mask = 1 | 4  # world geometry + player body/hurtbox
	query.exclude = [get_rid()]
	var result := space_state.intersect_ray(query)

	var end_point := aim_at
	if result:
		end_point = result.position
		var collider: Object = result.collider
		# Only damage what was actually aimed at (not walls in between)
		var victim: Node = null
		if collider is HurtboxComponent:
			victim = collider.get_parent()
		elif collider == target:
			victim = target
		if victim and victim != self and victim.has_node("HealthComponent"):
			victim.get_node("HealthComponent").take_damage(attack_damage, self)
			SignalBus.attack_landed.emit(self, victim, attack_damage)

	_create_tracer(from, end_point)
	_play_animation("shoot")


func _create_shockwave() -> void:
	var wave := MeshInstance3D.new()
	var wmesh := TorusMesh.new()
	wmesh.inner_radius = 0.9
	wmesh.outer_radius = 1.0
	var wmat := StandardMaterial3D.new()
	wmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wmat.albedo_color = Color(1.0, 0.3, 0.0, 0.9)
	wmat.emission_enabled = true
	wmat.emission = Color(1.0, 0.3, 0.0) * 3.0
	wave.mesh = wmesh
	wave.material_override = wmat
	wave.position = global_position + Vector3(0, 0.2, 0)
	get_tree().current_scene.add_child(wave)

	# AoE damage query
	var space_state := get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = attack_range * 2.0
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis.IDENTITY, global_position)
	params.collide_with_areas = true
	params.collision_mask = 4
	params.exclude = [get_rid()]
	for hit_result in space_state.intersect_shape(params, 8):
		var area = hit_result.collider
		if area is HurtboxComponent and area.get_parent() != self:
			area.take_damage(attack_damage * 0.75, self, (area.get_parent().global_position - global_position).normalized() * 12.0)

	var tween := wave.create_tween()
	tween.set_parallel(true)
	tween.tween_property(wave, "scale", Vector3(5.0, 1.0, 5.0), 0.4)
	tween.tween_property(wmat, "albedo_color:a", 0.0, 0.4)
	tween.chain().tween_callback(wave.queue_free)


func _create_tracer(from: Vector3, to: Vector3) -> void:
	var tracer := MeshInstance3D.new()
	var tmesh := ImmediateMesh.new()
	var tmat := StandardMaterial3D.new()
	tmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tmat.albedo_color = Color(1.0, 0.4, 0.1)
	tmat.emission_enabled = true
	tmat.emission = Color(1.0, 0.5, 0.1) * 6.0
	tracer.mesh = tmesh
	tracer.top_level = true
	tmesh.surface_begin(Mesh.PRIMITIVE_LINES, tmat)
	tmesh.surface_add_vertex(from)
	tmesh.surface_add_vertex(to)
	tmesh.surface_end()
	get_tree().current_scene.add_child(tracer)

	var tween := tracer.create_tween()
	tween.tween_property(tmat, "albedo_color:a", 0.0, 0.12)
	tween.tween_callback(tracer.queue_free)


func _play_animation(anim: String) -> void:
	if animation_player and animation_player.has_animation(anim):
		animation_player.play(anim)


func _state_stagger() -> void:
	velocity.x *= 0.85
	velocity.z *= 0.85


func _state_hurt(delta: float) -> void:
	velocity.x *= 0.85
	velocity.z *= 0.85

	hurt_timer -= delta
	if hurt_timer <= 0.0:
		current_state = EnemyState.CHASE if target and is_instance_valid(target) else EnemyState.PATROL


func _find_target() -> Node3D:
	var nearest: Node3D = null
	var nearest_dist := detection_range

	for candidate in Globals.get_all_players():
		if not is_instance_valid(candidate):
			continue
		var dist := global_position.distance_to(candidate.global_position)
		if dist >= nearest_dist:
			continue

		# Line-of-sight check against world geometry only
		var from := global_position + Vector3(0, 1.5, 0)
		var to: Vector3 = candidate.global_position + Vector3(0, 1.5, 0)
		var space_state := get_world_3d().direct_space_state
		var query := PhysicsRayQueryParameters3D.create(from, to)
		query.collision_mask = 1
		query.exclude = [get_rid()]
		var result := space_state.intersect_ray(query)

		if result.is_empty() or result.collider == candidate \
				or (result.collider is Node and result.collider.get_parent() == candidate):
			nearest_dist = dist
			nearest = candidate

	return nearest


func _get_new_patrol_target() -> void:
	var angle := randf() * TAU
	var dist := randf_range(patrol_radius * 0.3, patrol_radius)
	patrol_target = spawn_position + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)


func _face_direction(dir: Vector3, delta: float) -> void:
	if dir.length_squared() < 0.001:
		return
	rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), clampf(turn_speed * delta, 0.0, 1.0))


func _on_hurt(amount: float, _source: Node, knockback: Vector3) -> void:
	if current_state == EnemyState.DEAD:
		return

	accumulated_stagger += amount * 0.5

	# Poise break
	if accumulated_stagger >= stagger_threshold and not is_staggered:
		is_staggered = true
		stagger_timer = stagger_duration
		accumulated_stagger = 0.0
		current_state = EnemyState.STAGGER
		velocity += knockback * 0.5
		_flash(Color(1.0, 0.7, 0.2))
		return

	hurt_timer = hurt_duration
	current_state = EnemyState.HURT
	velocity += knockback
	_flash(Color(1.0, 0.3, 0.3))


func _flash(color: Color) -> void:
	if not mesh.material_override:
		return
	var mat := mesh.material_override as StandardMaterial3D
	mat.emission_enabled = true
	mat.emission = color * 2.0
	var tween := create_tween()
	tween.tween_property(mat, "emission", Color.BLACK, 0.18)


func _on_died() -> void:
	current_state = EnemyState.DEAD
	set_physics_process(false)
	hitbox.active = false
	hitbox.monitoring = false
	hurtbox.monitoring = false

	if mesh.material_override:
		mesh.material_override.albedo_color = Color(0.1, 0.05, 0.05)

	_drop_loot()

	var timer := get_tree().create_timer(3.0)
	timer.timeout.connect(queue_free)


func _drop_loot() -> void:
	if randf() < 0.3:
		_spawn_pickup(global_position + Vector3(randf_range(-1, 1), 1.0, randf_range(-1, 1)), 25.0)
	if randf() < 0.1:
		_spawn_pickup(global_position + Vector3(randf_range(-1, 1), 1.5, randf_range(-1, 1)), 50.0)


func _spawn_pickup(pos: Vector3, heal_amount: float) -> void:
	var pickup := Area3D.new()
	pickup.position = pos
	pickup.collision_layer = 0
	pickup.collision_mask = 1  # detect player/enemy bodies walking into it

	var shape := CollisionShape3D.new()
	var box := SphereShape3D.new()
	box.radius = 0.9
	shape.shape = box
	pickup.add_child(shape)

	var visual := MeshInstance3D.new()
	var vmesh := BoxMesh.new()
	vmesh.size = Vector3(0.5, 0.5, 0.5)
	var vmat := StandardMaterial3D.new()
	vmat.albedo_color = Color(0.2, 1.0, 0.2)
	vmat.emission_enabled = true
	vmat.emission = Color(0.2, 1.0, 0.2) * 2.0
	visual.mesh = vmesh
	visual.material_override = vmat
	visual.rotation_degrees.y = 45.0
	pickup.add_child(visual)

	pickup.body_entered.connect(func(body: Node3D) -> void:
		var hc := body.get_node_or_null("HealthComponent") as HealthComponent if body is Node else null
		if hc and hc.is_alive() and hc.current_health < hc.max_health:
			hc.heal(heal_amount)
			pickup.queue_free()
	)

	get_tree().current_scene.add_child(pickup)

	var spin := pickup.create_tween()
	spin.set_loops()
	spin.tween_property(visual, "rotation_degrees:y", visual.rotation_degrees.y + 360.0, 2.0)

	var despawn := pickup.get_tree().create_timer(30.0)
	despawn.timeout.connect(func() -> void:
		if is_instance_valid(pickup):
			pickup.queue_free()
	)
