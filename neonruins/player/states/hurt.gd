extends State

const HURT_DURATION: float = 0.25

var _timer: float = 0.0


func enter() -> void:
	_timer = HURT_DURATION


func physics_process(delta: float) -> void:
	player.apply_gravity(delta)
	_timer -= delta

	# Decelerate during hurt stun
	if player.is_on_floor():
		player.apply_friction(player.ground_friction * 1.5, delta)

	if _timer <= 0.0:
		if player.is_on_floor():
			player.transition_to("Walk")
		else:
			player.transition_to("InAir")
		return

	if Input.is_action_just_pressed("jump") and (player.is_on_floor() or player.coyote_timer > 0.0):
		player.jump_buffer_timer = 0.0
		player.transition_to("Jump")
