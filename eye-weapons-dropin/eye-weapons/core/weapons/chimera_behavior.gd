class_name ChimeraBehavior
extends WeaponBehavior
## The Chimera: ONE gun with four modes.
##
##   HIP (unscoped)
##     tap LMB (< tap_window)      -> pistol: weak hitscan
##     hold LMB, release           -> grenade launcher: arcing explosive,
##                                    charge scales damage + blast radius
##   SCOPED (RMB held)
##     tap LMB                     -> sniper projectile: fast, heavy
##     hold LMB, release < full    -> sniper hitscan (mid charge)
##     hold LMB, release at full   -> sniper hitscan + RICOCHET chains
##
## Mode switches are procedural: viewmodel pose lerps, FOV zooms, charge hum
## rises in pitch, tier milestones chime. All SFX go through the "Sfx" autoload
## (see core/sfx.gd + SOUNDS.md). All tuning lives in ChimeraGunResource.
##
## Requires on the player (see README "eye wiring"):
##   - var scope_zoom := 1.0            (weapon lerps this; camera FOV/sens read it)
##   - func add_camera_pitch(rad)       (recoil accumulator)
##   - input snapshot fields: shoot_pressed, shoot_just_pressed,
##     shoot_just_released, scope_pressed, scope_just_pressed, scope_just_released

signal scope_changed(scoped: bool)
signal charge_changed(frac: float, tier: int)  # tier: 0 idle, 1 charging, 2 mid-ready, 3 full

var cres: ChimeraGunResource
var scoped := false

var _player: Node = null
var _pressing := false
var _press_t := 0.0
var _charging := false
var _tier := 0
var _cooldown := 0.0

# procedural viewmodel animation (offsets from the vm's authored transform)
var _vm: Node3D = null
var _vm_base := Transform3D.IDENTITY
var _vm_found := false


func setup(p_res: WeaponResource, p_manager: WeaponManager) -> void:
	super(p_res, p_manager)
	cres = p_res as ChimeraGunResource
	_player = manager.get_parent()


func tick(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	_track_scope_input(delta)
	_track_trigger_input(delta)
	_animate_viewmodel(delta)
	_update_scope_zoom(delta)


# ---------------------------------------------------------------- input ----

func _track_scope_input(_delta: float) -> void:
	if _just_pressed("scope"):
		_set_scope(true)
	elif _just_released("scope"):
		_set_scope(false)


func _set_scope(on: bool) -> void:
	if on == scoped:
		return
	scoped = on
	_cancel_charge()  # switching modes never keeps a charge
	scope_changed.emit(scoped)
	_sfx("scope_in" if scoped else "scope_out")


func _track_trigger_input(delta: float) -> void:
	if _just_pressed("shoot"):
		if _cooldown > 0.0:
			return
		if manager.mag <= 0:
			_sfx("dry")
			_cooldown = 0.25
			return
		_pressing = true
		_press_t = 0.0
		_charging = false
		_tier = 0
	if _pressing:
		_press_t += delta
		if not _charging and _press_t >= cres.tap_window:
			_begin_charge()
		if _charging:
			_update_charge()
	if _just_released("shoot") and _pressing:
		_pressing = false
		_release_shot()


func _pressed(action: String) -> bool:
	var inp := _input_snapshot()
	if inp != null:
		return bool(inp.get(action + "_pressed"))
	return Input.is_action_pressed(action)


func _just_pressed(action: String) -> bool:
	var inp := _input_snapshot()
	if inp != null:
		return bool(inp.get(action + "_just_pressed"))
	return Input.is_action_just_pressed(action)


func _just_released(action: String) -> bool:
	var inp := _input_snapshot()
	if inp != null:
		return bool(inp.get(action + "_just_released"))
	return Input.is_action_just_released(action)


func _input_snapshot() -> Object:
	if _player != null and _player.get("input") != null:
		return _player.get("input")
	return null


# ---------------------------------------------------------------- charge ---

func _begin_charge() -> void:
	_charging = true
	_tier = 1
	charge_changed.emit(0.0, 1)
	_sfx("transform")          # the gun *reconfigures*: drum swings in / scope coils whine
	_sfx_loop("charge")        # rising hum while held


func _update_charge() -> void:
	var frac := _charge_frac()
	if scoped:
		if _press_t >= cres.full_charge_time and _tier < 3:
			_tier = 3
			_sfx("full_ready")   # full charge chime — the money sound
		elif _press_t >= cres.mid_charge_time and _tier < 2:
			_tier = 2
			_sfx("tier_ready")
	_sfx_loop_pitch(0.7 + frac * 0.9)
	charge_changed.emit(frac, _tier)


func _charge_frac() -> float:
	return clampf(
		(_press_t - cres.tap_window) / maxf(cres.full_charge_time - cres.tap_window, 0.01),
		0.0, 1.0)


func _cancel_charge() -> void:
	if _charging:
		_sfx_stop_loop("charge")
	_charging = false
	_pressing = false
	_tier = 0
	charge_changed.emit(0.0, 0)


func _release_shot() -> void:
	_sfx_stop_loop("charge")
	var was_charging := _charging
	var frac := _charge_frac()
	var tier := _tier
	_charging = false
	_tier = 0
	charge_changed.emit(0.0, 0)
	if not was_charging:
		if scoped:
			_fire_sniper_projectile()
		else:
			_fire_pistol()
	else:
		if scoped:
			if _press_t >= cres.full_charge_time:
				_fire_sniper_hitscan(cres.scoped_full_damage, true)
			else:
				_fire_sniper_hitscan(cres.scoped_mid_damage, false)
		else:
			_fire_grenade(frac)


# ---------------------------------------------------------------- firing ---

func _spend(cost: int) -> bool:
	if manager.mag < cost:
		_sfx("dry")
		return false
	manager.mag -= cost
	manager.ammo_changed.emit(manager.mag, manager.reserve)
	return true


func _kick(deg: float) -> void:
	if _player != null and _player.has_method("add_camera_pitch"):
		_player.add_camera_pitch(deg_to_rad(deg))


func _cam_basis() -> Basis:
	return manager.camera.global_transform.basis


func _fire_pistol() -> void:
	if not _spend(cres.ammo_pistol):
		return
	_cooldown = cres.pistol_interval
	var dir := -_cam_basis().z
	var hit := _ray(manager.camera.global_position, dir, cres.range)
	var end := manager.camera.global_position + dir * cres.range
	if hit:
		end = hit.position
		deal_damage(hit.collider, cres.pistol_damage)
	_tracer(manager.muzzle_position(), end, Color(1.0, 0.9, 0.5), 0.015)
	_sfx("pistol")
	_kick(0.3)


func _fire_grenade(frac: float) -> void:
	if not _spend(cres.ammo_grenade):
		return
	_cooldown = cres.grenade_interval
	var p := _spawn_projectile()
	if p == null:
		return
	p.set("damage", lerpf(cres.grenade_base_damage, cres.grenade_max_damage, frac))
	p.set("blast_radius", lerpf(cres.grenade_base_radius, cres.grenade_max_radius, frac))
	p.set("gravity", cres.grenade_gravity)
	p.call("launch", -_cam_basis().z, cres.grenade_speed, p.get("damage"), self)
	_sfx("grenade_launch", 0.9 + frac * 0.3)
	_kick(1.6)


func _fire_sniper_projectile() -> void:
	if not _spend(cres.ammo_sniper):
		return
	_cooldown = cres.sniper_interval
	var p := _spawn_projectile()
	if p == null:
		return
	p.set("damage", cres.sniper_projectile_damage)
	p.set("blast_radius", 0.0)
	p.set("gravity", 0.0)
	p.call("launch", -_cam_basis().z, cres.sniper_projectile_speed, p.get("damage"), self)
	_sfx("sniper_proj")
	_kick(1.0)


func _fire_sniper_hitscan(damage: float, with_ricochet: bool) -> void:
	if not _spend(cres.ammo_charged):
		return
	_cooldown = cres.charged_interval
	var origin := manager.camera.global_position
	var dir := -_cam_basis().z
	var already := {}
	var end := origin + dir * cres.range
	var hit := _ray(origin, dir, cres.range)
	if hit:
		end = hit.position
		already[hit.collider] = true
		deal_damage(hit.collider, damage)
		_impact_fx(end)
		if with_ricochet:
			_chain_ricochet(end, damage, already)
	_tracer(manager.muzzle_position(), end, Color(0.6, 0.9, 1.0), 0.03)
	_sfx("sniper_full" if with_ricochet else "sniper_hit")
	_kick(2.2 if with_ricochet else 1.4)


func _chain_ricochet(from: Vector3, damage: float, already: Dictionary) -> void:
	var dmg := damage
	var pos := from
	for i in cres.ricochet_count:
		dmg *= cres.ricochet_falloff
		var target := _nearest_damageable(pos, cres.ricochet_radius, already)
		if target == null:
			break
		already[target] = true
		var tpos := _target_center(target)
		_tracer(pos, tpos, Color(0.6, 0.9, 1.0), 0.02)
		deal_damage(target, dmg)
		_sfx("ricochet")
		pos = tpos


func _spawn_projectile() -> Node3D:
	if cres.projectile_scene == null:
		push_warning("Chimera: no projectile_scene on " + cres.weapon_name)
		return null
	var p := cres.projectile_scene.instantiate() as Node3D
	manager.get_tree().current_scene.add_child(p)
	p.global_position = manager.muzzle_position()
	return p


# ---------------------------------------------------------------- helpers --

func _ray(origin: Vector3, dir: Vector3, dist: float) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * dist)
	query.collision_mask = 0b1110
	var body := _player as CollisionObject3D
	if body != null:
		query.exclude = [body.get_rid()]
	return space.intersect_ray(query)


func _nearest_damageable(pos: Vector3, radius: float, exclude: Dictionary) -> Object:
	var space := get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	query.shape = sphere
	query.transform = Transform3D(Basis(), pos)
	query.collision_mask = 0b1110
	var best: Object = null
	var best_d := radius
	for r in space.intersect_shape(query, 12):
		var c: Object = r.collider
		if c == null or exclude.has(c):
			continue
		var node := c as Node
		var damageable := false
		if node != null and node.get_node_or_null("Health") != null:
			damageable = true
		elif c.has_method("take_damage"):
			damageable = true
		if not damageable:
			continue
		var d := (node.global_position as Vector3).distance_to(pos) \
			if node is Node3D else radius
		if d < best_d:
			best_d = d
			best = c
	return best


func _target_center(target: Object) -> Vector3:
	var n := target as Node3D
	if n != null:
		return n.global_position + Vector3(0, 1.0, 0)
	return manager.camera.global_position


func _tracer(a: Vector3, b: Vector3, color: Color, width: float) -> void:
	var length := a.distance_to(b)
	if length < 0.5:
		return
	var tracer := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width, width, length)
	tracer.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	tracer.material_override = mat
	manager.get_tree().current_scene.add_child(tracer)
	tracer.global_transform = Transform3D(Basis.looking_at(b - a), (a + b) * 0.5)
	manager.get_tree().create_timer(0.08).timeout.connect(tracer.queue_free)


func _impact_fx(pos: Vector3) -> void:
	var spark := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.08
	mesh.height = 0.16
	spark.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.6, 0.9, 1.0)
	spark.material_override = mat
	manager.get_tree().current_scene.add_child(spark)
	spark.global_position = pos
	var tw := spark.create_tween()
	tw.tween_property(spark, "scale", Vector3.ZERO, 0.18)
	tw.tween_callback(spark.queue_free)


# ---------------------------------------------------------------- feel -----

func _update_scope_zoom(delta: float) -> void:
	if _player == null or _player.get("scope_zoom") == null:
		return
	var target := cres.scope_zoom if scoped else 1.0
	var z := float(_player.get("scope_zoom"))
	_player.set("scope_zoom", lerpf(z, target, 1.0 - exp(-12.0 * delta)))


func _animate_viewmodel(delta: float) -> void:
	if not _vm_found:
		_vm = manager.get_viewmodel()
		if _vm != null:
			_vm_base = _vm.transform
			_vm_found = true
		else:
			return
	# pose targets, relative to the authored viewmodel transform
	var pos := Vector3.ZERO
	var rot := Vector3.ZERO
	if scoped:
		pos = Vector3(0.0, 0.06, 0.05)   # centers the gun under the scope
	else:
		pos = Vector3.ZERO
	if _charging:
		var frac := _charge_frac()
		pos += Vector3(0.0, 0.015, 0.09 + frac * 0.04)  # pulls back as it charges
		rot = Vector3(0.06 + frac * 0.1, 0.0, 0.0)
		# charge shake, grows with tier
		var shake := 0.004 * (1 + _tier)
		pos += Vector3(randf_range(-shake, shake), randf_range(-shake, shake), 0.0)
	var k := 1.0 - exp(-14.0 * delta)
	_vm.transform = Transform3D(
		(_vm_base.basis * Basis.from_euler(rot)).orthonormalized(),
		_vm_base.origin.lerp(_vm_base.origin + pos, k))
	# note: rotation snaps toward target while position lerps — good enough for
	# chunky voxel guns; use a quaternion slerp if you want it buttery.


# ---------------------------------------------------------------- sfx ------

func _sfx(sound_name: String, pitch := 1.0) -> void:
	var sfx := get_node_or_null("/root/Sfx")
	if sfx != null and sfx.has_method("play"):
		sfx.call("play", sound_name, pitch)


func _sfx_loop(sound_name: String) -> void:
	var sfx := get_node_or_null("/root/Sfx")
	if sfx != null and sfx.has_method("play_loop"):
		sfx.call("play_loop", sound_name)


func _sfx_stop_loop(sound_name: String) -> void:
	var sfx := get_node_or_null("/root/Sfx")
	if sfx != null and sfx.has_method("stop_loop"):
		sfx.call("stop_loop", sound_name)


func _sfx_loop_pitch(pitch: float) -> void:
	var sfx := get_node_or_null("/root/Sfx")
	if sfx != null and sfx.has_method("set_loop_pitch"):
		sfx.call("set_loop_pitch", "charge", pitch)
