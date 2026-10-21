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
	# Find the nearest street intersection to spawn on.
	var spacing := 16
	for ring in range(0, 8):
		for dx in range(-ring, ring + 1):
			for dz in range(-ring, ring + 1):
				if absi(dx) != ring and absi(dz) != ring:
					continue
				var x := dx * spacing
				var z := dz * spacing
				var ground := voxel_world.get_height_at(x, z)
				if ground <= 1:
					player.global_position = Vector3(x + 0.5, ground + 2.0, z + 0.5)
					player.add_to_group("camera")
					return