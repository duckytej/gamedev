class_name WeaponController
extends PlayerAbility

## Loadout and input router for all weapons on the player.
##
## The controller is a [PlayerAbility] (`ability_id = "weapons"`), so it can be
## deleted without touching movement. It discovers [WeaponBase] children at
## runtime and routes the input snapshot:
##
## - tap LMB (unscoped, released before the hold threshold): pistol
## - hold LMB past `grenade_hold_threshold` (unscoped): charge/throw grenade
## - hold RMB: scope
## - LMB while scoped: charge sniper; release to fire
## - V: quick-switch to the sword and back
## - F: reload the active gun
##
## While the sword is out, LMB strikes and RMB parries. Returning from the sword
## halves any reload still in progress. An overhealth burst can refill every
## magazine instantly through [method refill_all_ammo].
##
## It also owns the shared hit feedback (tracers, muzzle flash, impact sparks)
## and the camera/hitscan queries, keeping individual weapons small.

signal hit_confirmed(killed: bool)

const MUZZLE_OFFSET := Vector3(0.18, -0.12, -0.45)

var _camera: Camera3D

var _weapons: Array[WeaponBase] = []
var _pistol: PistolWeapon
var _grenade: GrenadeWeapon
var _sniper: SniperWeapon
var _sword: SwordWeapon

var _scoped := false
var _melee_equipped := false
var _unscoped_hold := false
var _hold_time := 0.0
var _grenade_armed := false

var _flash_timer := 0.0
var _flash_light: OmniLight3D
var _flash_mesh: MeshInstance3D
var _flash_material: StandardMaterial3D
var _hit_query: PhysicsRayQueryParameters3D
var _hit_cast: ShapeCast3D


func _on_setup() -> void:
	ability_id = &"weapons" if ability_id == &"" else ability_id
	add_to_group(&"weapon_controller")
	_camera = player.camera

	_hit_query = PhysicsRayQueryParameters3D.new()
	_hit_query.collision_mask = PhysicsLayers.HIT_MASK
	_hit_query.collide_with_areas = false
	_hit_query.collide_with_bodies = true
	_hit_query.exclude = [player.get_rid()]

	_build_muzzle_flash()
	_build_hitscan_cast.call_deferred()

	for child in get_children():
		var weapon := child as WeaponBase
		if weapon == null:
			continue
		weapon.setup(player, self)
		_weapons.append(weapon)
		if weapon is PistolWeapon:
			_pistol = weapon
		elif weapon is GrenadeWeapon:
			_grenade = weapon
		elif weapon is SniperWeapon:
			_sniper = weapon
		elif weapon is SwordWeapon:
			_sword = weapon

	if _sniper != null:
		_sniper.set_scoped(false)
	if _sword != null:
		_sword.set_equipped(false)


func _exit_tree() -> void:
	# If the whole loadout is removed at runtime, do not leave the player zoomed
	# and do not leave the world-parented query node behind.
	if player != null and is_instance_valid(player):
		player.scoped = false
	if is_instance_valid(_hit_cast):
		_hit_cast.queue_free()
		_hit_cast = null


func post_move_update(delta: float) -> void:
	if not enabled or player == null:
		return
	_update_muzzle_flash(delta)
	_route_input(delta)

	for weapon in _weapons:
		if is_instance_valid(weapon) and weapon.enabled:
			weapon.update(delta)


func _route_input(delta: float) -> void:
	var input := player.input

	if input.melee_just_pressed and _weapon_usable(_sword):
		_toggle_melee()

	if _melee_equipped:
		if input.fire_just_pressed and _weapon_usable(_sword):
			_sword.on_primary_pressed()
		if input.aim_just_pressed and _weapon_usable(_sword):
			_sword.begin_parry()
		return

	if input.reload_just_pressed:
		var active_gun := _active_gun()
		if active_gun != null:
			active_gun.begin_reload()

	var want_scope := _weapon_usable(_sniper) and input.aim_pressed

	if want_scope != _scoped:
		_scoped = want_scope
		player.scoped = _scoped
		if _weapon_usable(_sniper):
			_sniper.set_scoped(_scoped)
		if not _scoped:
			_unscoped_hold = false
			_grenade_armed = false
			if _weapon_usable(_grenade):
				_grenade.cancel_charge()

	if _scoped:
		# Any unscoped hold is abandoned when the player aims.
		_unscoped_hold = false
		_grenade_armed = false
		if input.fire_just_pressed and _weapon_usable(_sniper):
			_sniper.begin_charge()
		if input.fire_just_released and _weapon_usable(_sniper):
			_sniper.release_charge()
		return

	if input.fire_just_pressed:
		_unscoped_hold = true
		_hold_time = 0.0
		_grenade_armed = false

	if _unscoped_hold and input.fire_pressed:
		_hold_time += delta
		if not _grenade_armed and _weapon_usable(_grenade) \
				and _hold_time >= player.config.grenade_hold_threshold:
			_grenade_armed = true
			_grenade.begin_charge()

	if input.fire_just_released:
		if _grenade_armed and _weapon_usable(_grenade):
			_grenade.release_charge()
		elif _unscoped_hold and _weapon_usable(_pistol):
			# Released before the hold threshold: this was a tap, not a throw.
			_pistol.on_primary_pressed()
		_unscoped_hold = false
		_grenade_armed = false


## Swaps between the firearm loadout and the sword. The return trip cuts every
## in-progress reload by the configured quickswitch factor.
func _toggle_melee() -> void:
	if _melee_equipped:
		_melee_equipped = false
		if _weapon_usable(_sword):
			_sword.set_equipped(false)
		var factor := player.config.quickswitch_reload_factor
		if _weapon_usable(_pistol):
			_pistol.shorten_reload(factor)
		if _weapon_usable(_sniper):
			_sniper.shorten_reload(factor)
		return

	_melee_equipped = true
	_sword.set_equipped(true)
	_scoped = false
	player.scoped = false
	if _weapon_usable(_sniper):
		_sniper.set_scoped(false)
	if _weapon_usable(_grenade):
		_grenade.cancel_charge()
	_unscoped_hold = false
	_grenade_armed = false


func _active_gun() -> GunWeapon:
	if _scoped and _weapon_usable(_sniper):
		return _sniper
	if _weapon_usable(_pistol):
		return _pistol
	if _weapon_usable(_sniper):
		return _sniper
	return null


# --- Shared services for weapons ---------------------------------------------

func get_camera_origin() -> Vector3:
	return _camera.global_position


func get_aim_direction() -> Vector3:
	return -_camera.global_transform.basis.z


func get_muzzle_position() -> Vector3:
	return _camera.global_transform * MUZZLE_OFFSET


## Single hit-scan ray. Returns an empty dictionary on miss.
func raycast(origin: Vector3, direction: Vector3, distance: float) -> Dictionary:
	_hit_query.from = origin
	_hit_query.to = origin + direction * distance
	return player.get_world_3d().direct_space_state.intersect_ray(_hit_query)


## Swept-sphere hit-scan. Used by a fully charged sniper shot and its preview.
## Returns `{position, normal, collider}` or an empty dictionary.
func shape_cast(
	origin: Vector3, direction: Vector3, distance: float, radius: float
) -> Dictionary:
	if _hit_cast == null:
		return {}
	var sphere := _hit_cast.shape as SphereShape3D
	if sphere == null:
		return {}
	sphere.radius = maxf(radius, 0.001)
	_hit_cast.global_transform = Transform3D(Basis.looking_at(direction, Vector3.UP), origin)
	_hit_cast.target_position = Vector3(0.0, 0.0, -distance)
	_hit_cast.enabled = true
	_hit_cast.force_shapecast_update()
	if not _hit_cast.is_colliding():
		_hit_cast.enabled = false
		return {}
	var result := {
		"position": _hit_cast.get_collision_point(0),
		"normal": _hit_cast.get_collision_normal(0),
		"collider": _hit_cast.get_collider(0),
	}
	_hit_cast.enabled = false
	return result


func report_hit(killed: bool) -> void:
	hit_confirmed.emit(killed)


func apply_recoil(pitch_degrees: float) -> void:
	player.add_recoil(pitch_degrees, randf_range(-0.25, 0.25) * pitch_degrees)


func flash_muzzle(color: Color = Color(1.0, 0.75, 0.35)) -> void:
	if _flash_light == null:
		return
	_flash_timer = player.config.muzzle_flash_time if player.config != null else 0.045
	_flash_light.light_color = color
	_flash_light.light_energy = player.config.muzzle_flash_energy if player.config != null else 3.0
	if _flash_mesh != null:
		_flash_mesh.visible = true
		if _flash_material != null:
			_flash_material.emission = color


func spawn_tracer(from: Vector3, to: Vector3, color: Color) -> void:
	var parent := player.get_parent()
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
	tracer.name = "WeaponTracer"
	tracer.mesh = immediate
	tracer.top_level = true
	tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(tracer)

	var life := player.config.tracer_time if player.config != null else 0.07
	get_tree().create_timer(life).timeout.connect(tracer.queue_free)


func spawn_impact(point: Vector3, normal: Vector3, color: Color) -> void:
	var parent := player.get_parent()
	if parent == null:
		return
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 3.0

	var mesh := SphereMesh.new()
	mesh.radius = 0.05
	mesh.height = 0.1
	mesh.radial_segments = 8
	mesh.rings = 4

	var spark := MeshInstance3D.new()
	spark.name = "ImpactSpark"
	spark.mesh = mesh
	spark.material_override = material
	spark.top_level = true
	spark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(spark)
	spark.global_position = point + normal * 0.03

	var tween := spark.create_tween()
	tween.set_parallel(true)
	tween.tween_property(spark, "scale", Vector3.ZERO, 0.18) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(spark.queue_free)


# --- Status / queries ---------------------------------------------------------

func is_scoped() -> bool:
	return _scoped


func get_status_text() -> String:
	if _melee_equipped and _weapon_usable(_sword):
		return _sword.get_status_text()
	if _scoped and _weapon_usable(_sniper):
		return "SCOPE  " + _sniper.get_status_text()
	if _grenade_armed and _weapon_usable(_grenade):
		return _grenade.get_status_text()
	if _weapon_usable(_pistol):
		return _pistol.get_status_text()
	if _weapon_usable(_sniper):
		return _sniper.get_status_text()
	return ""


## Refills all gun magazines and cancels their reloads. Used by the overhealth
## stagger burst (and available to tests).
func refill_all_ammo() -> void:
	for weapon in _weapons:
		if is_instance_valid(weapon) and weapon is GunWeapon:
			(weapon as GunWeapon).refill_ammo()


## Called by enemies before they apply a shot. Only a raised sword, a live parry
## window and an attacker inside the parry cone count.
func try_parry(attacker_position: Vector3) -> bool:
	if not _melee_equipped or not _weapon_usable(_sword) or not _sword.is_parrying():
		return false
	var to_attacker := attacker_position - _camera.global_position
	to_attacker.y = 0.0
	if to_attacker.length_squared() < 0.0001:
		return false
	var forward := get_aim_direction()
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return false
	var angle := rad_to_deg(forward.normalized().angle_to(to_attacker.normalized()))
	if angle > player.config.sword_parry_arc_degrees * 0.5:
		return false
	_sword.flash_parry()
	return true


## Exits scope and drops any charged attack. Called when the player dies or the
## loadout is disabled.
func force_exit_scope() -> void:
	_scoped = false
	if player != null and is_instance_valid(player):
		player.scoped = false
	if _weapon_usable(_sniper):
		_sniper.set_scoped(false)
	if _weapon_usable(_grenade):
		_grenade.cancel_charge()
	_unscoped_hold = false
	_grenade_armed = false


func is_melee_equipped() -> bool:
	return _melee_equipped


func get_weapons() -> Array[WeaponBase]:
	var valid: Array[WeaponBase] = []
	for weapon in _weapons:
		if is_instance_valid(weapon):
			valid.append(weapon)
	return valid


func get_pistol() -> PistolWeapon:
	return _pistol if _weapon_usable(_pistol) else null


func get_grenade() -> GrenadeWeapon:
	return _grenade if _weapon_usable(_grenade) else null


func get_sniper() -> SniperWeapon:
	return _sniper if _weapon_usable(_sniper) else null


func get_sword() -> SwordWeapon:
	return _sword if _weapon_usable(_sword) else null


## Called by [WeaponBase] as it leaves the tree, so deleting a weapon node also
## removes every cached reference and exits scope if the sniper disappeared.
func _on_weapon_removed(weapon: WeaponBase) -> void:
	_weapons.erase(weapon)
	if _pistol == weapon:
		_pistol = null
	if _grenade == weapon:
		_grenade = null
		_grenade_armed = false
	if _sniper == weapon:
		_sniper = null
		if _scoped:
			_scoped = false
			if player != null and is_instance_valid(player):
				player.scoped = false
	if _sword == weapon:
		_sword = null
		_melee_equipped = false


func _weapon_usable(weapon: Variant) -> bool:
	return weapon != null and is_instance_valid(weapon) and weapon.enabled


# --- Setup helpers ------------------------------------------------------------

func _build_muzzle_flash() -> void:
	if _camera == null:
		return
	_flash_light = OmniLight3D.new()
	_flash_light.name = "MuzzleLight"
	_flash_light.position = MUZZLE_OFFSET
	_flash_light.light_color = Color(1.0, 0.75, 0.35)
	_flash_light.light_energy = 0.0
	_flash_light.omni_range = 4.0
	_flash_light.shadow_enabled = false
	_camera.add_child(_flash_light)

	_flash_material = StandardMaterial3D.new()
	_flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_material.albedo_color = Color(1.0, 0.8, 0.4)
	_flash_material.emission_enabled = true
	_flash_material.emission = Color(1.0, 0.8, 0.4)
	_flash_material.emission_energy_multiplier = 4.0
	_flash_material.no_depth_test = true

	var mesh := SphereMesh.new()
	mesh.radius = 0.045
	mesh.height = 0.09
	mesh.radial_segments = 8
	mesh.rings = 4

	_flash_mesh = MeshInstance3D.new()
	_flash_mesh.name = "MuzzleFlash"
	_flash_mesh.position = MUZZLE_OFFSET
	_flash_mesh.mesh = mesh
	_flash_mesh.material_override = _flash_material
	_flash_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash_mesh.visible = false
	_camera.add_child(_flash_mesh)


func _build_hitscan_cast() -> void:
	var parent := player.get_parent()
	if parent == null:
		return
	_hit_cast = ShapeCast3D.new()
	_hit_cast.name = "SniperHitscan"
	_hit_cast.shape = SphereShape3D.new()
	_hit_cast.collision_mask = PhysicsLayers.HIT_MASK
	_hit_cast.collide_with_areas = false
	_hit_cast.collide_with_bodies = true
	_hit_cast.enabled = false
	_hit_cast.add_exception(player)
	parent.add_child(_hit_cast)


func _update_muzzle_flash(delta: float) -> void:
	if _flash_timer <= 0.0:
		return
	_flash_timer -= delta
	var strength := clampf(_flash_timer / maxf(player.config.muzzle_flash_time, 0.001), 0.0, 1.0)
	if _flash_light != null:
		_flash_light.light_energy = player.config.muzzle_flash_energy * strength
	if _flash_timer <= 0.0:
		if _flash_light != null:
			_flash_light.light_energy = 0.0
		if _flash_mesh != null:
			_flash_mesh.visible = false
