class_name MeleeBehavior
extends WeaponBehavior
## Melee as a WeaponManager behavior — equips like any gun.
## States: IDLE -> WINDUP -> SWING -> RECOVER.
## Pressing attack during the last 30% of SWING queues the next combo hit.
## Hold-to-charge heavy attacks: extend this with a CHARGE state if you want them.
##
## Hit detection = swept sphere along the blade tip path (no tunneling).
## Needs a Marker3D named "BladeTip" as a child of the WeaponManager
## (tip of the visible swing arc). Falls back to a camera-forward
## sweep if the marker is missing.

enum MState { IDLE, WINDUP, SWING, RECOVER }

var mstate: int = MState.IDLE
var combo := 0
var _queued := false
var _t := 0.0
var _already_hit := {}
var _prev_tip := Vector3.ZERO
var _tip: Marker3D = null

const SWEEP_RADIUS := 0.3
const SWEEP_STEPS := 4


func setup(p_res: WeaponResource, p_manager: WeaponManager) -> void:
	super(p_res, p_manager)
	_tip = manager.get_node_or_null("BladeTip") as Marker3D


func fire(_origin: Vector3, _dir: Vector3) -> void:
	match mstate:
		MState.IDLE:
			_start_swing(0)
		MState.SWING:
			if _t / res.swing_time > 0.7:  # combo window: last 30%
				_queued = true
		_:
			pass


func _start_swing(combo_index: int) -> void:
	combo = combo_index
	mstate = MState.WINDUP
	_t = 0.0
	_queued = false
	_already_hit.clear()
	# hook here: Audio.play("swing_%d" % combo)


func _physics_process(delta: float) -> void:
	if mstate == MState.IDLE:
		return
	_t += delta
	match mstate:
		MState.WINDUP:
			if _t >= res.swing_time * 0.3:
				mstate = MState.SWING
				_t = 0.0
				_prev_tip = _tip_pos()
		MState.SWING:
			_sweep()
			if _t >= res.swing_time:
				if _queued and combo + 1 < res.combo_hits:
					_start_swing(combo + 1)
				else:
					mstate = MState.RECOVER
					_t = 0.0
		MState.RECOVER:
			if _t >= res.swing_time * 0.5:
				mstate = MState.IDLE


func _tip_pos() -> Vector3:
	if _tip != null:
		return _tip.global_position
	var cam := manager.camera
	return cam.global_position + -cam.global_transform.basis.z * 1.2


func _sweep() -> void:
	var from := _prev_tip
	var to := _tip_pos()
	_prev_tip = to
	var space := get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = SWEEP_RADIUS
	query.shape = sphere
	query.collision_mask = 0b0010  # enemies on layer 2
	for i in SWEEP_STEPS:
		var mid := from.lerp(to, (float(i) + 0.5) / SWEEP_STEPS)
		query.transform = Transform3D(Basis(), mid)
		for r in space.intersect_shape(query, 8):
			var c: Object = r.collider
			if c != self and not _already_hit.has(c):
				_already_hit[c] = true
				# later combo hits hurt more — rewards finishing the chain
				deal_damage(c, res.damage * (1.0 + 0.25 * combo))
