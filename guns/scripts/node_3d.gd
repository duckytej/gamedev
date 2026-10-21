###extends Node3D
###
#### City generation settings
###@export var city_size: int = 60  # City radius
###@export var block_size: float = 4.0  # Larger blocks for city feel
###@export var ground_level: int = 0  # Base ground height
###@export var max_building_height: int = 25
###@export var street_width: int = 8  # Width of streets between blocks
###
###var noise_districts: FastNoiseLite
###var noise_buildings: FastNoiseLite
###var noise_destruction: FastNoiseLite
###
###func _ready():
	###print("Generating apocalyptic city...")
	###setup_noise()
	###generate_city()
	###print("City generation complete!")
###
###func setup_noise():
	###var base_seed = randi()
	###
	#### District/height variation noise
	###noise_districts = FastNoiseLite.new()
	###noise_districts.seed = base_seed
	###noise_districts.noise_type = FastNoiseLite.TYPE_SIMPLEX
	###noise_districts.frequency = 0.02
	###
	#### Building placement noise
	###noise_buildings = FastNoiseLite.new()
	###noise_buildings.seed = base_seed + 1000
	###noise_buildings.noise_type = FastNoiseLite.TYPE_CELLULAR
	###noise_buildings.frequency = 0.05
	###
	#### Destruction/damage noise
	###noise_destruction = FastNoiseLite.new()
	###noise_destruction.seed = base_seed + 2000
	###noise_destruction.noise_type = FastNoiseLite.TYPE_PERLIN
	###noise_destruction.frequency = 0.1
###
###func generate_city():
	#### First: Create the ground plane (walkable surface)
	###create_ground_plane()
	###
	#### Then: Generate city blocks and buildings
	###var buildings_created = 0
	###
	###var grid_radius = city_size
	###for gx in range(-grid_radius, grid_radius):
		###for gz in range(-grid_radius, grid_radius):
			#### Check if this should be a street (leave empty spaces)
			###if is_street_location(gx, gz):
				###continue
			###
			#### Get district/placement noise
			###var district_noise = noise_districts.get_noise_2d(gx, gz)
			###var building_noise = noise_buildings.get_noise_2d(gx, gz)
			###
			#### Place building or debris
			###if building_noise > -0.2:
				###var building_type = get_building_type(district_noise, gx, gz)
				###create_building(gx, gz, building_type)
				###buildings_created += 1
			###elif randf() < 0.3:
				###create_debris(gx, gz)
		###
		#### Progress update
		###if gx % 20 == 0:
			###print("Generated buildings in column ", gx, " - Total: ", buildings_created)
###
###func create_ground_plane():
	###"""Create a large walkable ground surface"""
	###print("Creating ground plane...")
	###
	###var ground_size = city_size * 2 + 20  # Make ground bigger than city
	###
	#### Create large ground plane
	###var ground_mesh = MeshInstance3D.new()
	###var plane_mesh = BoxMesh.new()
	###plane_mesh.size = Vector3(ground_size * block_size, 1.0, ground_size * block_size)
	###ground_mesh.mesh = plane_mesh
	###ground_mesh.position = Vector3(0, ground_level - 0.5, 0)
	###
	#### Ground material (concrete/asphalt look)
	###var ground_material = StandardMaterial3D.new()
	###ground_material.albedo_color = Color(0.25, 0.25, 0.3)  # Dark gray
	###ground_material.roughness = 0.9
	###ground_material.metallic = 0.1
	###ground_mesh.material_override = ground_material
	###
	#### Ground collision
	###var ground_body = StaticBody3D.new()
	###var ground_collision = CollisionShape3D.new()
	###var ground_shape = BoxShape3D.new()
	###ground_shape.size = plane_mesh.size
	###ground_collision.shape = ground_shape
	###ground_body.add_child(ground_collision)
	###ground_mesh.add_child(ground_body)
	###
	###add_child(ground_mesh)
###
###func is_street_location(x: int, z: int) -> bool:
	###"""Determine if this location should be a street/open space"""
	###var street_spacing = 16  # Distance between streets
	###
	###
	###
	###var on_x_street = norm_mod(x, street_spacing) < street_width
	###var on_z_street = norm_mod(z, street_spacing) < street_width
	###
	###return on_x_street or on_z_street
###func norm_mod(v: int, m: int) -> int:
		###var r = v % m
		###if r < 0:
			###r += m
		###return r
###
###func get_building_type(district_value: float, x: int, z: int) -> String:
	###"""Determine what type of building to create"""
	###var distance_from_center = sqrt(x * x + z * z)
	###var max_distance = city_size
	###var center_factor = 1.0 - (distance_from_center / max_distance)
	###
	#### Downtown area (center) - taller buildings
	###if center_factor > 0.7:
		###if district_value > 0.3:
			###return "skyscraper"
		###else:
			###return "office_building"
	###
	#### Mid-city - medium buildings
	###elif center_factor > 0.4:
		###if district_value > 0.1:
			###return "apartment"
		###else:
			###return "commercial"
	###
	#### Outer city - smaller buildings
	###else:
		###if district_value > -0.2:
			###return "house"
		###else:
			###return "warehouse"
###
###func create_building(x: int, z: int, building_type: String):
	###"""Create a building of specified type"""
	###var base_pos = Vector3(x * block_size, ground_level, z * block_size)
	###var building_width = randi_range(2, 4)  # Building footprint
	###var building_depth = randi_range(2, 4)
	###var building_height: int
	###var color: Color
	###
	#### Determine height and color based on type
	###match building_type:
		###"skyscraper":
			###building_height = randi_range(15, max_building_height)
			###color = Color(0.2, 0.2, 0.3)  # Dark blue-gray
		###"office_building":
			###building_height = randi_range(8, 15)
			###color = Color(0.3, 0.3, 0.35)  # Gray
		###"apartment":
			###building_height = randi_range(6, 12)
			###color = Color(0.35, 0.3, 0.25)  # Brownish
		###"commercial":
			###building_height = randi_range(3, 8)
			###color = Color(0.25, 0.3, 0.3)  # Greenish gray
		###"house":
			###building_height = randi_range(2, 5)
			###color = Color(0.4, 0.35, 0.3)  # Tan
		###"warehouse":
			###building_height = randi_range(3, 6)
			###building_width = randi_range(4, 6)  # Warehouses are wider
			###building_depth = randi_range(4, 6)
			###color = Color(0.3, 0.25, 0.2)  # Brown
		###_:
			###building_height = 3
			###color = Color(0.3, 0.3, 0.3)
	###
	#### Apply apocalyptic damage
	###var destruction_noise = noise_destruction.get_noise_2d(x, z)
	###if destruction_noise > 0.3:
		###building_height = int(building_height * randf_range(0.3, 0.8))  # Partially destroyed
		###color = color * 0.7  # Darker, damaged look
	###
	#### Create the building as a single large block
	###var building_mesh = MeshInstance3D.new()
	###var box_mesh = BoxMesh.new()
	###box_mesh.size = Vector3(
		###building_width * block_size,
		###building_height * block_size,
		###building_depth * block_size
	###)
	###building_mesh.mesh = box_mesh
	###building_mesh.position = base_pos + Vector3(
		###building_width * block_size * 0.5,
		###building_height * block_size * 0.5,
		###building_depth * block_size * 0.5
	###)
	###
	#### Building material
	###var material = StandardMaterial3D.new()
	###material.albedo_color = color
	###material.roughness = 0.8
	###material.metallic = 0.2
	###
	#### Add some variety with emission for broken windows/fires
	###if destruction_noise > 0.5:
		###material.emission_enabled = true
		###material.emission = Color(0.8, 0.3, 0.1) * 0.1  # Faint orange glow
	###
	###building_mesh.material_override = material
	###
	#### Building collision
	###var building_body = StaticBody3D.new()
	###var building_collision = CollisionShape3D.new()
	###var building_shape = BoxShape3D.new()
	###building_shape.size = box_mesh.size
	###building_collision.shape = building_shape
	###building_body.add_child(building_collision)
	###building_mesh.add_child(building_body)
	###
	###add_child(building_mesh)
	###
	#### Occasionally add rooftop details
	###if randf() < 0.3:
		###add_rooftop_details(base_pos, building_width, building_height, building_depth)
###
###func create_debris(x: int, z: int):
	###"""Create small debris piles and ruins"""
	###var debris_count = randi_range(1, 3)
	###
	###for i in range(debris_count):
		###var debris_pos = Vector3(
			###x * block_size + randf_range(-block_size, block_size),
			###ground_level,
			###z * block_size + randf_range(-block_size, block_size)
		###)
		###
		###var debris_mesh = MeshInstance3D.new()
		###var box_mesh = BoxMesh.new()
		###var debris_size = randf_range(0.5, 2.0)
		###box_mesh.size = Vector3(debris_size, debris_size * 0.5, debris_size)
		###debris_mesh.mesh = box_mesh
		###debris_mesh.position = debris_pos + Vector3(0, debris_size * 0.25, 0)
		###
		#### Debris material (darker, dirtier)
		###var material = StandardMaterial3D.new()
		###material.albedo_color = Color(0.2, 0.18, 0.16)  # Dark brown/gray
		###material.roughness = 1.0
		###debris_mesh.material_override = material
		###
		#### Debris collision
		###var debris_body = StaticBody3D.new()
		###var debris_collision = CollisionShape3D.new()
		###var debris_shape = BoxShape3D.new()
		###debris_shape.size = box_mesh.size
		###debris_collision.shape = debris_shape
		###debris_body.add_child(debris_collision)
		###debris_mesh.add_child(debris_body)
		###
		###add_child(debris_mesh)
###
###func add_rooftop_details(base_pos: Vector3, width: int, height: int, depth: int):
	###"""Add details like water tanks, vents, etc. to rooftops"""
	###var rooftop_y = ground_level + height * block_size
	###
	#### Water tank or AC unit
	###if randf() < 0.7:
		###var detail_mesh = MeshInstance3D.new()
		###var detail_box = BoxMesh.new()
		###var detail_size = randf_range(1.0, 2.5)
		###detail_box.size = Vector3(detail_size, detail_size, detail_size)
		###detail_mesh.mesh = detail_box
		###
		###detail_mesh.position = base_pos + Vector3(
			###randf_range(0, width * block_size),
			###rooftop_y + detail_size * 0.5,
			###randf_range(0, depth * block_size)
		###)
		###
		###var detail_material = StandardMaterial3D.new()
		###detail_material.albedo_color = Color(0.4, 0.35, 0.3)
		###detail_material.metallic = 0.6
		###detail_mesh.material_override = detail_material
		###
		###add_child(detail_mesh)
###
#### Utility functions for gameplay
###func get_random_rooftop_position() -> Vector3:
	###"""Get a random position on a building rooftop (useful for spawning)"""
	#### This would need to track building positions, simplified for now
	###return Vector3(
		###randf_range(-city_size, city_size) * block_size,
		###randf_range(5, max_building_height) * block_size,
		###randf_range(-city_size, city_size) * block_size
	###)
###
###func get_random_street_position() -> Vector3:
	###"""Get a random position on a street (useful for ground spawning)"""
	###var street_spacing = 16
	###var max_cells = int(city_size / street_spacing) * street_spacing
	###var street_index_x = randi() % max_cells
	###var world_x = street_index_x * block_size
	###var offset_x = randf_range(0, street_width) * block_size
	###
	###var sz = randf_range(-city_size, city_size) * block_size
	###return Vector3(world_x + offset_x, ground_level + 1, sz)
###
###
###func get_spawn_positions_near(center: Vector3, radius: float, count: int) -> Array[Vector3]:
	###"""Generate spawn positions for PvPvE combat"""
	###var positions: Array[Vector3] = []
	###
	###for i in range(count):
		###var angle = randf() * TAU
		###var distance = randf_range(radius * 0.3, radius)
		###var spawn_pos = center + Vector3(
			###cos(angle) * distance,
			###0,
			###sin(angle) * distance
		###)
		###spawn_pos.y = ground_level + 1  # Spawn on ground level
		###positions.append(spawn_pos)
	###
	###return positions
##
##extends Node3D
##
### CONFIG
##const WORLD_SIZE = 128
##const MAX_HEIGHT = 32
##const BLOCK_SIZE = 2
##
##const BLOCK_AIR = 0
##const BLOCK_SOLID = 1
##const BLOCK_RAMP = 2
##
##var noise := FastNoiseLite.new()
##
### Ramps (4 directions)
##var ramp_meshes = {
	##Vector3(1,0,0): preload("res://scenes/meshes/ramp_east.tscn"),
	##Vector3(-1,0,0): preload("res://scenes/meshes/ramp_west.tscn"),
	##Vector3(0,0,1): preload("res://scenes/meshes/ramp_south.tscn"),
	##Vector3(0,0,-1): preload("res://scenes/meshes/ramp_north.tscn")
##}
##
##
##var cube_scene := preload("res://scenes/meshes/block.tscn")
##
##func _ready():
	##noise.seed = randi()
	##noise.frequency = 0.05
	##
	##generate_world()
	##spawn_buildings()
##
##
### ------------------------
### TERRAIN
### ------------------------
##func generate_world():
	##for x in range(WORLD_SIZE):
		##for z in range(WORLD_SIZE):
			##var height = int(noise.get_noise_2d(x, z) * MAX_HEIGHT/2) + MAX_HEIGHT/2
			##for y in range(height):
				##var block_type = get_block_type(x, y, z)
				##if block_type == BLOCK_SOLID:
					##place_block(Vector3(x, y, z), BLOCK_SOLID)
				##elif block_type == BLOCK_RAMP:
					##place_ramp(Vector3(x, y, z), Vector3(1,0,0)) # default, we’ll rotate later
##
##
##func get_block_type(x: int, y: int, z: int) -> int:
	##var height = int(noise.get_noise_2d(x, z) * MAX_HEIGHT/2) + MAX_HEIGHT/2
	##if y < height:
		##var neighbor_height = int(noise.get_noise_2d(x+1, z) * MAX_HEIGHT/2) + MAX_HEIGHT/2
		##var slope = neighbor_height - height
		##if abs(slope) == 1:
			##return BLOCK_RAMP
		##return BLOCK_SOLID
	##return BLOCK_AIR
##
##
### ------------------------
### BUILDINGS
### ------------------------
##func spawn_buildings():
	##var spacing = 30
	##for x in range(0, WORLD_SIZE, spacing):
		##for z in range(0, WORLD_SIZE, spacing):
			##if randi() % 100 < 20: # 20% chance for a building
				##var h = int(noise.get_noise_2d(x, z) * MAX_HEIGHT/2) + MAX_HEIGHT/2
				##spawn_building(Vector3(x, h, z))
##
##
##func spawn_building(pos: Vector3):
	##var width = 8 + randi() % 6
	##var depth = 8 + randi() % 6
	##var height = 10 + randi() % 10
	##
	##for x in range(width):
		##for y in range(height):
			##for z in range(depth):
				##var is_edge = (x == 0 or x == width-1 or z == 0 or z == depth-1 or y == 0)
				##if is_edge:
					### Add variation: some blocks missing = ruined look
					##if randi() % 100 < 15:
						##continue
					##place_block(pos + Vector3(x, y, z), BLOCK_SOLID)
##
##
### ------------------------
### HELPERS
### ------------------------
##func place_block(pos: Vector3, block_type: int):
	##var block = cube_scene.instantiate()
	##block.transform.origin = pos * BLOCK_SIZE
	##add_child(block)
##
##func place_ramp(pos: Vector3, dir: Vector3):
	##var ramp = ramp_meshes[dir].instantiate()
	##ramp.transform.origin = pos * BLOCK_SIZE
	##add_child(ramp)
#extends Node3D
#
## ==========================
## CONFIG
## ==========================
#const WORLD_SIZE = 128
#const MAX_HEIGHT = 32
#const BLOCK_SIZE = 2
#
#const BLOCK_AIR   = 0
#const BLOCK_SOLID = 1
#const BLOCK_RAMP  = 2
#
#var noise := FastNoiseLite.new()
#
## Meshes
#var cube_scene := preload("res://scenes/meshes/block.tscn")   # simple cube with collider
#var ramp_scene := preload("res://scenes/meshes/ramp_north.tscn")   # diagonal half-cube ramp
#
#
## ==========================
## READY
## ==========================
#func _ready():
	#noise.seed = randi()
	#noise.frequency = 0.05
	#
	#generate_world()
	#spawn_buildings()
#
#
## ==========================
## TERRAIN
## ==========================
#func generate_world():
	#for x in range(WORLD_SIZE):
		#for z in range(WORLD_SIZE):
			#var height = int(noise.get_noise_2d(x, z) * MAX_HEIGHT/2) + MAX_HEIGHT/2
			#for y in range(height):
				#var block_info = get_block_type(x, y, z)
				#match block_info.type:
					#BLOCK_SOLID:
						#place_block(Vector3(x,y,z))
					#BLOCK_RAMP:
						#place_ramp(Vector3(x,y,z), block_info.dir)
#
#
#func get_block_type(x: int, y: int, z: int) -> Dictionary:
	#var height = int(noise.get_noise_2d(x, z) * MAX_HEIGHT/2) + MAX_HEIGHT/2
	#if y < height:
		## compare neighbor to detect slope
		#var neighbor_height = int(noise.get_noise_2d(x+1, z) * MAX_HEIGHT/2) + MAX_HEIGHT/2
		#var slope = neighbor_height - height
		#if slope == 1:
			#return {"type": BLOCK_RAMP, "dir": Vector3(1,0,0)}   # east
		#elif slope == -1:
			#return {"type": BLOCK_RAMP, "dir": Vector3(-1,0,0)}  # west
		#else:
			## check z direction slopes too
			#var neighbor_height_z = int(noise.get_noise_2d(x, z+1) * MAX_HEIGHT/2) + MAX_HEIGHT/2
			#var slope_z = neighbor_height_z - height
			#if slope_z == 1:
				#return {"type": BLOCK_RAMP, "dir": Vector3(0,0,1)}   # south
			#elif slope_z == -1:
				#return {"type": BLOCK_RAMP, "dir": Vector3(0,0,-1)}  # north
		#return {"type": BLOCK_SOLID}
	#return {"type": BLOCK_AIR}
#
#
## ==========================
## BUILDINGS
## ==========================
#func spawn_buildings():
	#var spacing = 30
	#for x in range(0, WORLD_SIZE, spacing):
		#for z in range(0, WORLD_SIZE, spacing):
			#if randi() % 100 < 20: # 20% chance to spawn a building
				#var h = int(noise.get_noise_2d(x, z) * MAX_HEIGHT/2) + MAX_HEIGHT/2
				#spawn_building(Vector3(x, h, z))
#
#
#func spawn_building(pos: Vector3):
	#var width = 8 + randi() % 6
	#var depth = 8 + randi() % 6
	#var height = 10 + randi() % 10
	#
	#for x in range(width):
		#for y in range(height):
			#for z in range(depth):
				#var is_edge = (x == 0 or x == width-1 or z == 0 or z == depth-1 or y == 0)
				#if is_edge:
					## random missing = ruined look
					#if randi() % 100 < 15:
						#continue
					#place_block(pos + Vector3(x,y,z))
#
#
## ==========================
## HELPERS
## ==========================
#func place_block(pos: Vector3):
	#var block = cube_scene.instantiate()
	#block.transform.origin = pos * BLOCK_SIZE
	#add_child(block)
#
#
#func place_ramp(pos: Vector3, dir: Vector3):
	#var ramp = ramp_scene.instantiate()
	#ramp.transform.origin = pos * BLOCK_SIZE
	#
	## rotate to face correct direction
	#if dir == Vector3(1,0,0):        # east
		#ramp.rotation_degrees = Vector3(0, 90, 0)
	#elif dir == Vector3(-1,0,0):     # west
		#ramp.rotation_degrees = Vector3(0, -90, 0)
	#elif dir == Vector3(0,0,-1):     # north
		#ramp.rotation_degrees = Vector3(0, 180, 0)
	#else:                            # south (default)
		#ramp.rotation_degrees = Vector3(0, 0, 0)
	#
	#add_child(ramp)
#extends Node3D
#
#@export var chunk_size: int = 32
#@export var noise_scale: float = 16.0
#@export var height_scale: float = 8.0
#@export var cube_scene: PackedScene
#@export var ramp_scene: PackedScene
#
#var noise := FastNoiseLite.new()
#
#func _ready():
	#noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	#noise.seed = randi()
#
	#generate_chunk(Vector3.ZERO)
#
#
#func generate_chunk(origin: Vector3):
	#for x in chunk_size:
		#for z in chunk_size:
			#var world_x = origin.x + x
			#var world_z = origin.z + z
#
			## Sample height from noise
			#var height = int(noise.get_noise_2d(world_x / noise_scale, world_z / noise_scale) * height_scale)
#
			## Place cubes from bottom up to height
			#for y in range(height + 1):
				#var block_pos = Vector3(world_x, y, world_z)
#
				#if y == height:
					## Decide if ramp needed
					#var ramp_dir = get_ramp_direction(world_x, y, world_z)
					#if ramp_dir != Vector3.ZERO:
						#spawn_ramp(block_pos, ramp_dir)
					#else:
						#spawn_cube(block_pos)
				#else:
					#spawn_cube(block_pos)
#
#
#func get_ramp_direction(x: int, y: int, z: int) -> Vector3:
	## Look at 4-neighbors and see if terrain drops steeply
	#var h = int(noise.get_noise_2d(x / noise_scale, z / noise_scale) * height_scale)
#
	#var neighbors = {
		#Vector3(1,0,0): int(noise.get_noise_2d((x+1)/noise_scale, z/noise_scale) * height_scale),
		#Vector3(-1,0,0): int(noise.get_noise_2d((x-1)/noise_scale, z/noise_scale) * height_scale),
		#Vector3(0,0,1): int(noise.get_noise_2d(x/noise_scale, (z+1)/noise_scale) * height_scale),
		#Vector3(0,0,-1): int(noise.get_noise_2d(x/noise_scale, (z-1)/noise_scale) * height_scale),
	#}
#
	#for dir in neighbors.keys():
		#var diff = h - neighbors[dir]
		#if diff == 1: # exactly 1 block drop, good for a ramp
			#return dir
	#return Vector3.ZERO
#
#
#func spawn_cube(pos: Vector3):
	#var cube = cube_scene.instantiate()
	#cube.position = pos
	#add_child(cube)
#
#
#func spawn_ramp(pos: Vector3, dir: Vector3):
	#var ramp = ramp_scene.instantiate()
	#ramp.position = pos
	## Rotate based on direction
	#if dir == Vector3(1,0,0):
		#ramp.rotation_degrees = Vector3(0, 90, 0)
	#elif dir == Vector3(-1,0,0):
		#ramp.rotation_degrees = Vector3(0, -90, 0)
	#elif dir == Vector3(0,0,1):
		#ramp.rotation_degrees = Vector3(0, 0, 0)
	#elif dir == Vector3(0,0,-1):
		#ramp.rotation_degrees = Vector3(0, 180, 0)
#
	#add_child(ramp)
extends Node3D
var block = preload("res://scenes/meshes/block.tscn")  # Load block scene
var noise = FastNoiseLite.new()
func _ready():
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.seed = randi()
	generate_heights()
func generate_heights():
	for z in range(-150,150,1):
		for x in range(-150,150,1):
			var height = (noise.get_noise_2d(x, z) * 100) 
			if height < 2:  
				height = 2
			var b = block.instantiate()
			b.transform.origin = Vector3(x, height/2, z) 
			b.scale.y = height
			add_child(b)
