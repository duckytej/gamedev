extends Node3D

var block = preload("res://scenes/block.tscn")
var noise = FastNoiseLite.new()

const MAP_SIZE = 100
const BLOCK_SPACING = 1.0
const CLUSTER_SIZE = 9
var tilt_cache = {}

func _ready():
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.seed = randi()
	noise.frequency = 0.015
	generate_city()

func generate_city():
	# Generate main buildings
	for z in range(-MAP_SIZE, MAP_SIZE, 1):
		for x in range(-MAP_SIZE, MAP_SIZE, 1):
			var height_noise = abs(noise.get_noise_2d(x, z))
			generate_building(x, z, height_noise)
	generate_platforms()

func generate_building(x, z, height_noise):
	var height = 0
	var tt = false
	var tx = 0.0
	var tz = 0.0
	
	if height_noise < 0.25:
		height = 1  # street level
	elif height_noise <= 0.4:
		height = 15 # small
	elif height_noise <= 0.5:
		height = 25
	elif height_noise < 0.6:
		height = 40 # medium
	elif height_noise < 0.75:
		tt = true
		height = 60 # tilted group
		var key = Vector2i(x / CLUSTER_SIZE, z / CLUSTER_SIZE)
		if not tilt_cache.has(key):
			tilt_cache[key] = Vector2(randf_range(-30, 30), randf_range(-30, 30))
		var tilt = tilt_cache[key]
		tx = tilt.x
		tz = tilt.y
	elif height_noise < 0.9:
		height = 75 # huge
	else:
		return  # skip for platforms
	
	var b = block.instantiate()
	if tt:
		b.transform.origin = Vector3(x * BLOCK_SPACING, (height / 2) - 5, z * BLOCK_SPACING)
	else:
		b.transform.origin = Vector3(x * BLOCK_SPACING, height / 2, z * BLOCK_SPACING)
	
	b.scale = Vector3(1.0, height, 1.0)
	b.rotation_degrees.x = tx
	b.rotation_degrees.z = tz
	
	$MultiMeshInstance3D.add_child(b)

func generate_platforms():
	var rng = RandomNumberGenerator.new()
	
	for i in range(25):  # 30 floating platforms
		var x = rng.randf_range(-MAP_SIZE, MAP_SIZE)
		var z = rng.randf_range(-MAP_SIZE, MAP_SIZE)
		var y = rng.randf_range(15, 65)
		
		var platform = block.instantiate()
		platform.transform.origin = Vector3(x, y, z)

		var size = rng.randf_range(5, 30)
		platform.scale = Vector3(size, 0.5, size)
		if rng.randf() < 0.4:
			platform.rotation_degrees.x = rng.randf_range(-25, 25)
			platform.rotation_degrees.z = rng.randf_range(-25, 25)
		$MultiMeshInstance3D.add_child(platform)

## Simple destructibility
#func _input(event):
	#if event is InputEventMouseButton and event.pressed:
		#if event.button_index == MOUSE_BUTTON_LEFT:
			#var camera = get_viewport().get_camera_3d()
			#var from = camera.project_ray_origin(event.position)
			#var to = from + camera.project_ray_normal(event.position) * 1000
			#
			#var space_state = get_world_3d().direct_space_state
			#var query = PhysicsRayQueryParameters3D.create(from, to)
			#var result = space_state.intersect_ray(query)
			#
			#if result:
				#var hit_object = result.collider
				#if hit_object.get_parent() is RigidBody3D:
					#destroy_block(hit_object.get_parent())
#
#func destroy_block(block):
	## Convert to rigid body for destruction physics
	#if not block is RigidBody3D:
		#var rigid_body = RigidBody3D.new()
		#var original_transform = block.transform
		#var original_scale = block.scale
		#var original_mesh = block.mesh
		#var original_material = block.material_override
		#
		## Remove original static body
		#remove_child(block)
		#block.queue_free()
		#
		## Create new rigid body
		#rigid_body.transform = original_transform
		#rigid_body.scale = original_scale
		#
		#var mesh_instance = MeshInstance3D.new()
		#mesh_instance.mesh = original_mesh
		#mesh_instance.material_override = original_material
		#rigid_body.add_child(mesh_instance)
		#
		## Add collision
		#var collision = CollisionShape3D.new()
		#var box_shape = BoxShape3D.new()
		#collision.shape = box_shape
		#rigid_body.add_child(collision)
		#
		#add_child(rigid_body)
		#block = rigid_body
	#
	## Apply destruction force
	#block.freeze = false
	#block.apply_impulse(Vector3.UP * 5 + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * 3, Vector3.ZERO)
	#
	## Remove after delay
	#await get_tree().create_timer(3.0).timeout
	#block.queue_free()
