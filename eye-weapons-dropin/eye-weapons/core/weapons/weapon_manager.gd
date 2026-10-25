class_name WeaponManager
extends Node3D
## Attach as a child of the Player (e.g. under Camera3D).
## Owns: gun state, ammo pools, input, spread bloom.
## Talks to the player ONLY through add_camera_pitch() and signals —
## never touches movement or camera-look code.

signal ammo_changed(mag: int, reserve: int)
signal weapon_changed(weapon_name: String)

enum State { IDLE, RELOAD }

@export var weapons: Array[WeaponResource] = []
@export var camera: Camera3D
@export var muzzle: Marker3D  # tracer / projectile spawn point

var state: int = State.IDLE
var current := 0
var mag := 0
var reserve := 0
var heat := 0.0  # spread bloom, 0..8, decays over time

var _behavior: WeaponBehavior = null
var _viewmodel: Node3D = null
var _cooldown := 0.0
var _reload_left := 0.0


func _ready() -> void:
	if camera == null:
		camera = get_viewport().get_camera_3d()
	if weapons.is_empty():
		push_warning("WeaponManager: assign WeaponResource .tres files in the inspector")
		return
	equip(0)


func equip(index: int) -> void:
	if index < 0 or index >= weapons.size():
		return
	if state != State.IDLE or index == current and _behavior != null:
		return
	current = index
	var res: WeaponResource = weapons[current]
	if _behavior != null:
		_behavior.queue_free()
		_behavior = null
	if _viewmodel != null:
		_viewmodel.queue_free()
		_viewmodel = null
	_behavior = _make_behavior(res)
	_behavior.setup(res, self)
	add_child(_behavior)
	if res.viewmodel != null:
		_viewmodel = res.viewmodel.instantiate()
		add_child(_viewmodel)
	mag = res.magazine_size
	reserve = res.reserve_ammo
	heat = 0.0
	state = State.IDLE
	_cooldown = 0.0
	ammo_changed.emit(mag, reserve)
	weapon_changed.emit(res.weapon_name)


func _make_behavior(res: WeaponResource) -> WeaponBehavior:
	match res.fire_type:
		WeaponResource.FireType.PROJECTILE:
			return ProjectileBehavior.new()
		WeaponResource.FireType.MELEE:
			return MeleeBehavior.new()
		WeaponResource.FireType.CHIMERA:
			return ChimeraBehavior.new()
		_:
			return HitscanBehavior.new()


func muzzle_position() -> Vector3:
	if muzzle != null:
		return muzzle.global_position
	return camera.global_position


## The currently equipped viewmodel (may be null). Used by behaviors for
## procedural animation (e.g. the Chimera's charge poses).
func get_viewmodel() -> Node3D:
	return _viewmodel


func _process(delta: float) -> void:
	if weapons.is_empty() or _behavior == null:
		return
	_cooldown = maxf(0.0, _cooldown - delta)
	heat = maxf(0.0, heat - delta * 6.0)  # bloom decay
	if state == State.RELOAD:
		_reload_left -= delta
		if _reload_left <= 0.0:
			_finish_reload(weapons[current])
		return
	# state == IDLE
	_handle_weapon_switch()
	var res: WeaponResource = weapons[current]
	if res.fire_type == WeaponResource.FireType.CHIMERA:
		# Chimera owns its whole input model (tap vs hold, scope, charge).
		_behavior.tick(delta)
		return
	var want_fire := Input.is_action_pressed("shoot") if res.auto else Input.is_action_just_pressed("shoot")
	if want_fire and _cooldown <= 0.0:
		if res.fire_type == WeaponResource.FireType.MELEE:
			_behavior.fire(camera.global_position, -camera.global_transform.basis.z)
			_cooldown = 0.2  # debounce: one click = one swing
		elif mag > 0:
			_fire(res)
		else:
			_dry_fire()
	if Input.is_action_just_pressed("reload"):
		_start_reload(res)


func _fire(res: WeaponResource) -> void:
	_cooldown = res.fire_interval
	mag -= 1
	heat = minf(heat + 1.0, 8.0)
	var tx := camera.global_transform
	var s := tan(deg_to_rad(res.spread_deg + heat * res.bloom_per_shot))
	var base_dir := -tx.basis.z
	for i in res.pellets:
		var dir := base_dir
		if res.pellets > 1 or s > 0.0:
			dir = (base_dir \
				+ tx.basis.x * randf_range(-s, s) \
				+ tx.basis.y * randf_range(-s, s)).normalized()
		_behavior.fire(camera.global_position, dir)
	_apply_recoil(res.recoil_kick_deg)
	ammo_changed.emit(mag, reserve)


func _apply_recoil(kick_deg: float) -> void:
	# The ONLY thing weapons ask of the player: a pitch accumulator.
	# Add this to player.gd:
	#   var recoil_pitch := 0.0
	#   func add_camera_pitch(rad: float) -> void: recoil_pitch += rad
	# and decay/apply recoil_pitch in your camera code each frame.
	var player := get_parent()
	if player != null and player.has_method("add_camera_pitch"):
		player.add_camera_pitch(deg_to_rad(kick_deg))


func _dry_fire() -> void:
	_cooldown = 0.25
	# hook your sound autoload here, e.g. Audio.play("dry_fire")


func _start_reload(res: WeaponResource) -> void:
	if res.fire_type == WeaponResource.FireType.MELEE:
		return
	if mag >= res.magazine_size or reserve <= 0:
		return
	state = State.RELOAD
	_reload_left = res.reload_time


func _finish_reload(res: WeaponResource) -> void:
	var need := res.magazine_size - mag
	var take := mini(need, reserve)
	mag += take
	reserve -= take
	state = State.IDLE
	ammo_changed.emit(mag, reserve)


func _handle_weapon_switch() -> void:
	for i in weapons.size():
		if Input.is_action_just_pressed("weapon_%d" % (i + 1)):
			equip(i)
