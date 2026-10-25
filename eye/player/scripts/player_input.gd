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
var melee_just_pressed := false
var burst_just_pressed := false
var reload_just_pressed := false
var reset_just_pressed := false

var _melee_was_pressed := false
var _burst_was_pressed := false
var _reload_was_pressed := false


func update() -> void:
	move = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	jump_pressed = Input.is_action_pressed("jump")
	jump_just_pressed = Input.is_action_just_pressed("jump")
	jump_just_released = Input.is_action_just_released("jump")
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
	# These are one-shot presses (especially the melee toggle), so derive the
	# edge from the held state. `Input.action_press` in headless tests can keep
	# `is_action_just_pressed` true for more than one physics tick, which would
	# toggle the sword twice.
	var melee_pressed := Input.is_action_pressed("melee")
	melee_just_pressed = melee_pressed and not _melee_was_pressed
	_melee_was_pressed = melee_pressed
	var burst_pressed := Input.is_action_pressed("burst")
	burst_just_pressed = burst_pressed and not _burst_was_pressed
	_burst_was_pressed = burst_pressed
	var reload_pressed := Input.is_action_pressed("reload")
	reload_just_pressed = reload_pressed and not _reload_was_pressed
	_reload_was_pressed = reload_pressed
	reset_just_pressed = Input.is_action_just_pressed("reset")
