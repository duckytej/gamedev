class_name CityVoxelGenerator
extends Node

# Fills a VoxelWorld with a procedural ruined city.
#
# Design intent (from design discussion, keep this comment -- it's load-bearing):
#   - Dense per-column building placement (inspired by prototype B), not sparse
#     per-lot placement, so the skyline reads as crowded/alive.
#   - Road grid + non-overlapping lot logic (inspired by prototype A) so density
#     doesn't turn into visual noise -- streets still carve clean gaps.
#   - Rare tilted-cluster buildings (prototype B) for skyline chaos, cached per
#     cluster so tilt is consistent within a cluster, not per-building noise.
#   - A great wall ring at the city radius, with vertical extent tall enough
#     that reaching the top costs more grapple-stamina than a player can
#     sustain (see BuildingMorphSystem / GrappleAbility stamina cost curve --
#     that number lives in the ability, not here, but the wall's height is
#     what makes the constraint mean something).
#   - Morph intensity (see BuildingMorphSystem) increases continuously toward
#     city center. This generator just tags each column with its distance
#     factor so the morph system doesn't need to recompute placement logic.

@export var world: VoxelWorld
@export var city_radius: int = 90          # in voxels
@export var voxel_size: float = 1.0
@export var street_spacing: int = 16
@export var street_width: int = 3
@export var cluster_size: int = 9
@export var wall_height: int = 140          # deliberately far above sustainable grapple range
@export var wall_thickness: int = 4
@export var arena_radius: int = 18

var _noise_height := FastNoiseLite.new()
var _noise_density := FastNoiseLite.new()
var _tilt_cache: Dictionary = {}

# Column registry consumed by BuildingMorphSystem: world (x,z) -> column data.
# Populated during generation, read-only after.
var columns: Dictionary = {}


func generate() -> void:
	assert(world != null, "CityVoxelGenerator needs a VoxelWorld reference")
	_setup_noise()
	_generate_ground_and_roads()
	_generate_buildings()
	_generate_wall()
	_generate_arena()
	world.notify_generation_complete() if world.has_method("notify_generation_complete") else null


func _setup_noise() -> void:
	var seed_base := randi()
	_noise_height.seed = seed_base
	_noise_height.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise_height.frequency = 0.02

	_noise_density.seed = seed_base + 1000
	_noise_density.noise_type = FastNoiseLite.TYPE_CELLULAR
	_noise_density.frequency = 0.05


func _generate_ground_and_roads() -> void:
	for x in range(-city_radius, city_radius):
		for z in range(-city_radius, city_radius):
			if _is_street(x, z):
				world.set_voxel_at(x, 0, z, VoxelTypes.Type.ROAD)


func _is_street(x: int, z: int) -> bool:
	var mx := posmod(x, street_spacing)
	var mz := posmod(z, street_spacing)
	return mx < street_width or mz < street_width


func _generate_buildings() -> void:
	for x in range(-city_radius, city_radius):
		for z in range(-city_radius, city_radius):
			if _is_street(x, z):
				continue
			var dist := Vector2(x, z).length()
			if dist > city_radius - wall_thickness - 1:
				continue  # leave room for the wall ring
			if dist < arena_radius:
				continue  # arena owns this area

			var dist_factor: float = clampf(1.0 - dist / float(city_radius), 0.0, 1.0)
			_place_building_column(x, z, dist_factor)


func _place_building_column(x: int, z: int, dist_factor: float) -> void:
	# Density-first placement (prototype B instinct): evaluate every
	# non-street column rather than one building per lot.
	var density := absf(_noise_density.get_noise_2d(x, z))
	if density < 0.12:
		return  # empty lot / rubble gap, keeps density from being wall-to-wall

	var height := _pick_height(x, z, density)
	if height <= 0:
		return

	var tilt := _get_cluster_tilt(x, z)
	var is_tilted := tilt != Vector2.ZERO

	for y in range(1, height + 1):
		var type := _pick_voxel_type_for_layer(x, y, z, height)
		if is_tilted:
			# Tilted columns shear their offset per layer instead of true
			# mesh rotation (voxel grids don't rotate cleanly) -- gives the
			# leaning-skyline read from prototype B without needing rotated
			# collision shapes.
			var shear := Vector2(tilt.x, tilt.y) * (float(y) / height) * 0.15
			world.set_voxel_at(x + roundi(shear.x), y, z + roundi(shear.y), type)
		else:
			world.set_voxel_at(x, y, z, type)

	columns[Vector2i(x, z)] = {
		"base_height": height,
		"dist_factor": dist_factor,
		"tilted": is_tilted,
	}


func _pick_height(x: int, z: int, density: float) -> int:
	# Bucketed like prototype B, but density-gated so it doesn't fill 100%
	# of the map -- prototype A's restraint applied to prototype B's noise.
	if density < 0.25:
		return 1
	elif density < 0.4:
		return 15
	elif density < 0.55:
		return 25
	elif density < 0.7:
		return 40
	elif density < 0.85:
		return 60
	else:
		return 75


func _get_cluster_tilt(x: int, z: int) -> Vector2:
	var key := Vector2i(int(floor(float(x) / cluster_size)), int(floor(float(z) / cluster_size)))
	if not _tilt_cache.has(key):
		# Most clusters are upright. Only a minority tilt, so it reads as a
		# rare chaotic landmark, not constant visual noise.
		if randf() < 0.15:
			_tilt_cache[key] = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
		else:
			_tilt_cache[key] = Vector2.ZERO
	return _tilt_cache[key]


func _pick_voxel_type_for_layer(x: int, y: int, z: int, total_height: int) -> int:
	if y == total_height:
		return VoxelTypes.Type.CONCRETE_DARK  # roofline
	# Sparse windows: every few layers, some columns become glass.
	if y % 3 == 0 and absf(sin(x * 12.9898 + y * 78.233 + z * 37.719)) > 0.6:
		return VoxelTypes.Type.GLASS_LIT if (y % 6 == 0) else VoxelTypes.Type.GLASS
	return VoxelTypes.Type.CONCRETE


func _generate_wall() -> void:
	for x in range(-city_radius, city_radius):
		for z in range(-city_radius, city_radius):
			var dist := Vector2(x, z).length()
			if dist >= city_radius - wall_thickness and dist <= city_radius:
				for y in range(1, wall_height + 1):
					world.set_voxel_at(x, y, z, VoxelTypes.Type.WALL)


func _generate_arena() -> void:
	for x in range(-arena_radius, arena_radius):
		for z in range(-arena_radius, arena_radius):
			if Vector2(x, z).length() > arena_radius:
				continue
			world.set_voxel_at(x, 0, z, VoxelTypes.Type.ARENA_FLOOR)
