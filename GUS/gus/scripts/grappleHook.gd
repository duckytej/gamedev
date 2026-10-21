extends Node
class_name GrappleHook

#Grappling
@onready var player: PlayerMovement = $".."
@export var ray : RayCast3D
var launched = false
var target : Vector3

var restLength = 5.0
@export var maxRestFraction = 0.9
@export var minRestFraction = 0.4
@export var stiffness = 4.25
@export var restLengthCurve : ProceduralCurve
@export var rope : Node3D
#@export var crosshair : CenterContainer
#var currentOffset := 1.0
#var crosshairLerpSpeed := 12.0

#func _ready() -> void:
	#crosshair.update_dynamic_offset(currentOffset)


func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed("shoot") and !launched:
		launch()
	
	if Input.is_action_just_released("shoot"):
		retract()
	
	if launched:
		handleGrapple(delta)

func _process(delta: float) -> void:
	handleRope()
	#if ray.is_colliding():
		#currentOffset = lerp(currentOffset, 0.001, crosshairLerpSpeed * delta)
	#else:
		#currentOffset = lerp(currentOffset, 1.0, crosshairLerpSpeed * delta)
	#crosshair.update_dynamic_offset(currentOffset)


func launch() -> void:
	if ray.is_colliding():
		target = ray.get_collision_point()
		launched = true
		player.floor_snap_length = 0
		restLength = player.global_position.distance_to(target) * maxRestFraction
		restLengthCurve.set_targets(player.global_position.distance_to(target) * minRestFraction, restLength)
		restLengthCurve.start()


func retract() -> void:
	launched = false
	player.floor_snap_length = player.floorSnapLength


func isLaunched() -> bool:
	return launched


func handleGrapple(delta : float) -> void:
	var target_dir = player.global_position.direction_to(target)
	var target_dist = player.global_position.distance_to(target)
	
	restLength = restLengthCurve.step(delta) if restLengthCurve.is_running() else restLengthCurve.targets["min"]
	
	var displacement = target_dist - restLength
	var magnitude = 0
	if displacement > 0:
		magnitude = displacement * stiffness
	
	var force = target_dir * magnitude
	force = lerp(force, player.velocity, 0.1)
	print(magnitude, " , ", restLength)
	player.velocity += force * delta

func handleRope() -> void:
	if !launched:
		rope.visible = false
		return
	
	rope.visible = true
	rope.look_at(target)
	rope.scale = Vector3(1, 1, player.global_position.distance_to(target))
	
