class_name ProjectileBehavior
extends WeaponBehavior
## Spawns a real moving projectile (rocket / plasma). Dodgeable, chunky,
## more expensive than hitscan — use for the fun stuff.

func fire(_origin: Vector3, dir: Vector3) -> void:
	if res.projectile_scene == null:
		push_warning("ProjectileBehavior: no projectile_scene on " + res.weapon_name)
		return
	var p := res.projectile_scene.instantiate() as Node3D
	manager.get_tree().current_scene.add_child(p)
	p.global_position = manager.muzzle_position()
	if p.has_method("launch"):
		p.launch(dir, res.projectile_speed, res.damage, self)
	# hook here: Audio.play("rocket_fire")
