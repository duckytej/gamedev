extends Node3D

var noise = FastNoiseLite.new()

@export var terrain_size: int = 150  # Half-size (final map size = 2x this)
@export var max_height: int = 100  # Max height of terrain
@export var tunnel_threshold: float = 0.2  # Tunnels below this threshold
@export var crack_threshold: float = -0.6  # Cracks in the ground
@export var cube_size: float = 2  # Block size (increase for better performance)
@export var floating_rock_chance: float = 0.02  # Chance of floating rocks
@export var ground_height: int = 10  # Base ground level

var multi_mesh_instance: MultiMeshInstance3D  # MultiMesh for blocks
var static_body: StaticBody3D  # For collision

func _ready():
	noise.seed = randi()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX

	setup_multimesh()
	setup_collision()
	generate_terrain()

# Sets up the MultiMesh to optimize performance
func setup_multimesh():
	multi_mesh_instance = MultiMeshInstance3D.new()
	multi_mesh_instance.multimesh = MultiMesh.new()
	
	multi_mesh_instance.multimesh.mesh = BoxMesh.new()
	multi_mesh_instance.multimesh.mesh.size = Vector3(cube_size, cube_size, cube_size)

	multi_mesh_instance.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multi_mesh_instance.multimesh.instance_count = 0  # Start with zero instances

	add_child(multi_mesh_instance)

# Sets up collision for the terrain
func setup_collision():
	static_body = StaticBody3D.new()
	add_child(static_body)

# Function to generate terrain with tunnels, cracks, and alien-like features
func generate_terrain():
	var instances = []
	var collision_shapes = []

	for x in range(-terrain_size, terrain_size, int(cube_size)):
		for z in range(-terrain_size, terrain_size, int(cube_size)):
			var height_value = (noise.get_noise_2d(x, z) + 1) * 0.5  # Normalize 0-1
			var height = int(height_value * max_height)

			# Cracks in the ground (skips some terrain blocks)
			var crack_chance = noise.get_noise_2d(x * 0.2, z * 0.2)
			var is_crack = crack_chance < crack_threshold

			# Always ensure there is a base ground layer (no gaps)
			var min_y = 0 if is_crack else ground_height

			# Generate terrain
			for y in range(min_y, height, int(cube_size)):
				# Check for tunnels (hollow areas)
				var tunnel_check = noise.get_noise_3d(x, y, z)
				#if tunnel_check < tunnel_threshold:
					#continue  # Skip placing a block (creates a cave)

				instances.append(Transform3D(Basis(), position))
				collision_shapes.append(position)

			# Occasionally generate floating rocks
			if randf() < floating_rock_chance:
				var rock_pos = Vector3(x, height + 10, z)
				instances.append(Transform3D(Basis(), rock_pos))
				collision_shapes.append(rock_pos)

	# Update MultiMesh with generated instances
	multi_mesh_instance.multimesh.instance_count = instances.size()
	for i in range(instances.size()):
		multi_mesh_instance.multimesh.set_instance_transform(i, instances[i])

	# Add collision for each block
	add_collision_shapes(collision_shapes)

# Adds collision shapes to the terrain
func add_collision_shapes(positions):
	for pos in positions:
		var col_shape = CollisionShape3D.new()
		col_shape.shape = BoxShape3D.new()
		col_shape.shape.extents = Vector3(cube_size / 2, cube_size / 2, cube_size / 2)
		col_shape.position = pos
		static_body.add_child(col_shape)
