class_name PlayerInput
extends Node

## Deterministic snapshot of the player's input for the current physics tick.
##
## The player calls `update()` once at the very top of `_physics_process`, so all
## states and abilities read the same frame-consistent data and never touch
## `Input` directly. That keeps states testable, free of process-order surprises
## and makes a future input-rebinding screen a single-file change.

var move := Vector2.ZERO
var jump_pressed := false
var jump_just_pressed := false
var jump_just_released := false
var sprint_pressed := false
var crouch_pressed := false
var crouch_just_pressed := false
var dash_just_pressed := false
var grapple_pressed := false
var grapple_just_pressed := false
var grapple_just_released := false
var fire_pressed := false
var fire_just_pressed := false
var fire_just_released := false
var aim_pressed := false
var aim_just_pressed := false
var aim_just_released := false
var reset_just_pressed := false


func update() -> void:
	move = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	jump_pressed = Input.is_action_pressed("jump")
	jump_just_pressed = Input.is_action_just_pressed("jump")
	jump_just_released = Input.is_action_just_released("jump")
	sprint_pressed = Input.is_action_pressed("sprint")
	crouch_pressed = Input.is_action_pressed("crouch")
	crouch_just_pressed = Input.is_action_just_pressed("crouch")
	dash_just_pressed = Input.is_action_just_pressed("dash")
	grapple_pressed = Input.is_action_pressed("grapple")
	grapple_just_pressed = Input.is_action_just_pressed("grapple")
	grapple_just_released = Input.is_action_just_released("grapple")
	fire_pressed = Input.is_action_pressed("fire")
	fire_just_pressed = Input.is_action_just_pressed("fire")
	fire_just_released = Input.is_action_just_released("fire")
	aim_pressed = Input.is_action_pressed("aim")
	aim_just_pressed = Input.is_action_just_pressed("aim")
	aim_just_released = Input.is_action_just_released("aim")
	reset_just_pressed = Input.is_action_just_pressed("reset")
