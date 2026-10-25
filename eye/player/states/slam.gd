class_name PlayerSlamState
extends PlayerState

## Air slam: a downward plunge triggered by holding jump after an air-started
## jump. Horizontal momentum is mostly kept, the landing always hands off to
## [PlayerLandState] with `slam = true`, and that chains straight into a slide.

func enter(_msg: Dictionary = {}) -> void:
	player.set_slide_pose(0.0)
	player.velocity.y = minf(player.velocity.y, -player.config.slam_speed)
	player.velocity.x *= player.config.slam_horizontal_keep
	player.velocity.z *= player.config.slam_horizontal_keep


func physics_update(delta: float) -> void:
	player.apply_gravity(delta, player.config.slam_gravity_scale)

	if player.is_on_floor():
		machine.transition_to(&"Land", {"slam": true})
