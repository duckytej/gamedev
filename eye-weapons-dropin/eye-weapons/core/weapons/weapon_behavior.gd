class_name WeaponBehavior
extends Node3D
## Base class for fire behaviors. The WeaponManager owns timing, ammo and
## state — the behavior only produces the effect of ONE trigger pull.
## Subclasses: HitscanBehavior, ProjectileBehavior, MeleeBehavior.

var res: WeaponResource
var manager: WeaponManager

func setup(p_res: WeaponResource, p_manager: WeaponManager) -> void:
	res = p_res
	manager = p_manager

func fire(_origin: Vector3, _dir: Vector3) -> void:
	push_warning("WeaponBehavior.fire() not implemented")


## Per-frame update owned by the behavior. The WeaponManager calls this every
## frame for CHIMERA weapons (which track holds/charges themselves) and ignores
## it for everything else.
func tick(_delta: float) -> void:
	pass

## Damage anything: prefers a child "Health" node, falls back to the
## body's own take_damage(). Every damageable in the game only needs
## to understand take_damage(amount, source).
func deal_damage(target: Object, amount: float) -> void:
	if target == null:
		return
	var node := target as Node
	if node != null:
		var health := node.get_node_or_null("Health")
		if health != null and health.has_method("take_damage"):
			health.take_damage(amount, self)
			return
	if target.has_method("take_damage"):
		target.call("take_damage", amount, self)
