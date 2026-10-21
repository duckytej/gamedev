extends Node3D

@onready var voxel_world: VoxelWorld = $VoxelWorld
@onready var city_gen: CityGenerator = $VoxelWorld/CityGenerator
@onready var player: CharacterBody3D = $Player


func _ready() -> void:
	player.process_mode = Node.PROCESS_MODE_DISABLED
	city_gen.world = voxel_world
	await city_gen.generate()
	voxel_world.flush_all()
	_spawn_player()
	player.process_mode = Node.PROCESS_MODE_INHERIT


func _spawn_player() -> void:
	# Spawn on a street intersection near center (streets are guaranteed
	# building-free; intersections are open sky unless a platform floats over).
	var s := 8  # street_spacing/2 lands mid-street band for spacing 16
	var x := s
	var z := s
	while voxel_world.get_height_at(x, z) > 2:
		s += 16
		x = s
	var ground := voxel_world.get_height_at(x, z)
	player.global_position = Vector3(x + 0.5, ground + 2.5, z + 0.5)
