extends Node3D

var block = preload("res://scenes/block.tscn")  # Load block scene
var noise = FastNoiseLite.new()

func _ready():
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
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
			
#extends Node3D
#
#var block = preload("res://scenes/block.tscn")  # Load block scene
#var noise = FastNoiseLite.new()
#var noise_moderator = FastNoiseLite.new()
#
#
#func _ready():
	#noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	##noise.seed = randi()
	#noise_moderator.seed = randi()
#
	#generate_heights()
#
#func generate_heights():
	#for z in range(-150,150,1):
		#for x in range(-150,150,1):
			#var height = ((noise.get_noise_2d(x,z)+1) * 40)# * (noise_moderator.get_noise_2d(x,z)+0.5)
			#if height < 10:  
				#height = 10
			#var b = block.instantiate()
			#b.transform.origin = Vector3(x, height/2, z) 
			#b.scale.y = height
			#add_child(b) 
