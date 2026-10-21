class_name CityGenerator
extends Node

# Procedural ruined city, voxel core.
#
# Structure style (cant-inspired):
#   - Buildings are FOOTPRINTS, not single columns: rectangular bases with
#     45-degree chamfered corners. Flat wall planes + chamfered edges give
#     clean wallrun surfaces and smooth corner transitions.
#   - Tilted tower CLUSTERS: a lean vector is cached per cluster region so
#     every leaning tower inside one region shears the same direction --
#     reads as a coherent collapsed district, not random noise. Shear is
#     applied per-layer with rounding, producing long surfable diagonals.
#   - Floating platforms: solid slabs whose TOP SURFACE FOLLOWS A SLOPE
#     (single- or dual-axis), so they read as angled shards/ramps you can
#     surf down, not flat plates. Some get support columns to the ground.
#
# Destruction: all concrete/metal/glass/neon voxels are destructible via
# VoxelWorld.remove_voxels_in_sphere; roads/wall are structural.

@export var world: VoxelWorld
@export var city_radius: int = 100
@export var street_spacing: int = 16
@export var street_width: int = 3
@export var wide_street_width: int = 5
@export var wide_street_ratio: float = 0.10
@export var max_building_height: int = 42
@export var wall_height: int = 48
@export var wall_thickness: int = 3
@export var platform_count: int = 38
@export var lean_cluster_size: int = 24
@export var max_lean_shear: float = 5.0
@export var taper_min_height: int = 20
@export var taper_rate: float = 0.03
@export var lean_start_ratio: float = 0.45

var _noise_districts: FastNoiseLite
var _noise_destruction: FastNoiseLite
var _noise_neon: FastNoiseLite
var _noise_height: FastNoiseLite
var _rng := RandomNumberGenerator.new()
var _lean_cache: Dictionary = {}
var _work_accum := 0
var _wide_streets: Dictionary = {}
var _placed_buildings: Array[Dictionary] = []


func generate() -> void:
	assert(world != null)
	var seed_base := randi()
	_rng.seed = seed_base
	_setup_noise(seed_base)
	_precompute_wide_streets()
	_placed_buildings.clear()
	await _generate_ground_and_roads()
	await _generate_buildings()
	await _generate_platforms()
	await _generate_wall()


func _setup_noise(seed_base: int) -> void:
	_noise_districts = FastNoiseLite.new()
	_noise_districts.seed = seed_base
	_noise_districts.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise_districts.frequency = 0.015

	_noise_destruction = FastNoiseLite.new()
	_noise_destruction.seed = seed_base + 11
	_noise_destruction.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise_destruction.frequency = 0.06
	_noise_destruction.fractal_octaves = 4

	_noise_neon = FastNoiseLite.new()
	_noise_neon.seed = seed_base + 22
	_noise_neon.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise_neon.frequency = 0.025

	_noise_height = FastNoiseLite.new()
	_noise_height.seed = seed_base + 33
	_noise_height.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise_height.frequency = 0.008


func _precompute_wide_streets() -> void:
	_wide_streets.clear()
	var extent := city_radius + 20
	for coord in range(-extent, extent):
		var idx := floori(float(coord) / float(street_spacing))
		if not _wide_streets.has(idx):
			_wide_streets[idx] = _rng.randf() < wide_street_ratio


func _street_width_at(coord: int) -> int:
	var offset := posmod(coord, street_spacing)
	var idx := floori(float(coord) / float(street_spacing))
	var w := wide_street_width if _wide_streets.get(idx, false) else street_width
	return w if offset < w else 0



# Yield to the engine every ~12k voxel writes so generation streams in
# across frames instead of freezing the game on load.
func _spent(cost: int) -> void:
	_work_accum += cost
	if _work_accum > 12000:
		_work_accum = 0
		await get_tree().process_frame


func _place(x: int, y: int, z: int, type: int) -> void:
	world.set_voxel_at(x, y, z, type)


func _generate_ground_and_roads() -> void:
	var extent := city_radius + 20
	for x in range(-extent, extent):
		for z in range(-extent, extent):
			var t := VoxelTypes.Type.CONCRETE_DARK
			if Vector2(x, z).length() <= city_radius and _is_street(x, z):
				t = VoxelTypes.Type.ROAD_LINE if _is_center_line(x, z) else VoxelTypes.Type.ROAD
			_place(x, 0, z, t)
		await _spent(extent * 2)


func _is_street(x: int, z: int) -> bool:
	return _street_width_at(x) > 0 or _street_width_at(z) > 0


func _is_center_line(x: int, z: int) -> bool:
	var wx := _street_width_at(x)
	var wz := _street_width_at(z)
	var cx := wx > 0 and posmod(x, street_spacing) == wx / 2
	var cz := wz > 0 and posmod(z, street_spacing) == wz / 2
	return (cx and posmod(z, 6) < 3) or (cz and posmod(x, 6) < 3)


func _generate_buildings() -> void:
	var step := street_spacing
	for bx in range(-city_radius, city_radius - step + 1, step):
		for bz in range(-city_radius, city_radius - step + 1, step):
			var center := Vector2(bx + step / 2.0, bz + step / 2.0)
			var dist := center.length()
			if dist > city_radius - wall_thickness - 5:
				continue
			var block_seed := hash(Vector2i(bx, bz)) ^ _rng.seed
			var block_rng := RandomNumberGenerator.new()
			block_rng.seed = block_seed
			_generate_block(bx, bz, center, block_rng)
			await _spent(400)


func _generate_block(bx: int, bz: int, center: Vector2, rng: RandomNumberGenerator) -> void:
	var inner_start := street_width + 1
	var inner_size := street_spacing - inner_start * 2
	var center_factor := clampf(1.0 - center.length() / float(city_radius), 0.0, 1.0)

	var district := _noise_districts.get_noise_2d(center.x, center.y)
	if district < -0.55:
		# Dead zone: empty lot, maybe a rubble mound.
		if rng.randf() < 0.3:
			_scatter_rubble(bx + inner_start, bz + inner_start, inner_size, rng)
		return

	var rects: Array = []
	var roll := rng.randf()

	# cant-style tilted towers: rare, clustered, tall, leaning.
	if roll < 0.16 and center_factor > 0.3:
		var size := rng.randi_range(6, 9)
		var ox := bx + inner_start + rng.randi_range(0, maxi(inner_size - size, 0))
		var oz := bz + inner_start + rng.randi_range(0, maxi(inner_size - size, 0))
		rects.append({
			"pos": Vector2i(ox, oz),
			"size": Vector2i(size, size),
			"height": _pick_height(Vector2i(ox, oz), center_factor),
			"lean": _get_cluster_lean_with_neighbor(Vector2i(ox, oz), Vector2i(size, size)),
			"chamfer": 2,
		})
	elif roll < 0.62 or center_factor > 0.65:
		# One big footprint filling most of the block.
		var pad := rng.randi_range(1, 3)
		var w := inner_size - pad
		var d := inner_size - rng.randi_range(1, 3)
		var ox := bx + inner_start + rng.randi_range(0, maxi(inner_size - w, 0))
		var oz := bz + inner_start + rng.randi_range(0, maxi(inner_size - d, 0))
		rects.append({
			"pos": Vector2i(ox, oz),
			"size": Vector2i(w, d),
			"height": _pick_height(Vector2i(ox, oz), center_factor),
			"lean": Vector2.ZERO,
			"chamfer": 2,
		})
	else:
		# Two smaller buildings sharing the block.
		var half := inner_size / 2
		for q in range(2):
			var w := rng.randi_range(4, maxi(half - 1, 4))
			var d := rng.randi_range(4, maxi(inner_size - 2, 4))
			var qx := bx + inner_start + (q * half) + rng.randi_range(0, maxi(half - w, 0))
			var qz := bz + inner_start + rng.randi_range(0, maxi(inner_size - d, 0))
			rects.append({
				"pos": Vector2i(qx, qz),
				"size": Vector2i(mini(w, half), d),
				"height": _pick_height(Vector2i(qx, qz), center_factor * 0.8),
				"lean": Vector2.ZERO,
				"chamfer": 1,
			})

	for r in rects:
		_build_footprint(r["pos"], r["size"], r["height"], r["lean"], r["chamfer"], center_factor)
		_placed_buildings.append({"pos": r["pos"], "size": r["size"]})


func _pick_height(pos: Vector2i, center_factor: float) -> int:
	var h1 := (_noise_height.get_noise_2d(pos.x, pos.y) + 1.0) / 2.0
	var h2 := (_noise_height.get_noise_2d(pos.x * 1.7 + 50.0, pos.y * 1.3 + 50.0) + 1.0) / 2.0
	var height_var := (h1 * 0.65 + h2 * 0.35)

	var base_h: float
	if center_factor > 0.7:
		base_h = lerpf(22.0, float(max_building_height), height_var)
	elif center_factor > 0.4:
		base_h = lerpf(10.0, 24.0, height_var)
	else:
		base_h = lerpf(4.0, 14.0, height_var)

	var destruction := (_noise_destruction.get_noise_2d(pos.x * 1.7, pos.y * 2.3) + 1.0) / 2.0
	if destruction > 0.62:
		base_h *= randf_range(0.45, 0.7)
	return maxi(roundi(base_h), 2)


func _get_cluster_lean_with_neighbor(pos: Vector2i, size: Vector2i) -> Vector2:
	var neighbor := _find_nearest_building(pos, size)
	if neighbor["pos"] == Vector2i(-999999, -999999):
		# Fallback: use cached cluster lean.
		var center := Vector2(pos) + Vector2(size) * 0.5
		var key := Vector2i(floori(center.x / lean_cluster_size), floori(center.y / lean_cluster_size))
		if not _lean_cache.has(key):
			if _rng.randf() < 0.6:
				_lean_cache[key] = Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)).normalized()
			else:
				_lean_cache[key] = Vector2.ZERO
		return _lean_cache[key]
	# Tilt toward the nearest neighbor.
	var from := Vector2(pos) + Vector2(size) * 0.5
	var to := Vector2(neighbor["pos"]) + Vector2(neighbor["size"]) * 0.5
	return (to - from).normalized()


func _find_nearest_building(pos: Vector2i, size: Vector2i) -> Dictionary:
	var best_dist := INF
	var best := {"pos": Vector2i(-999999, -999999), "size": Vector2i(1, 1)}
	for b in _placed_buildings:
		var b_pos: Vector2i = b["pos"]
		var b_size: Vector2i = b["size"]
		# Skip buildings in the same block (overlapping footprint).
		if absi(pos.x - b_pos.x) < size.x + 1 and absi(pos.y - b_pos.y) < size.y + 1:
			continue
		var from := Vector2(pos) + Vector2(size) * 0.5
		var to := Vector2(b_pos) + Vector2(b_size) * 0.5
		var dist := from.distance_to(to)
		if dist < best_dist:
			best_dist = dist
			best = b
	return best


func _build_footprint(pos: Vector2i, size: Vector2i, height: int, lean: Vector2, chamfer: int, center_factor: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(pos) ^ _rng.seed
	var destruction := (_noise_destruction.get_noise_2d(pos.x * 0.37, pos.y * 0.41) + 1.0) / 2.0
	var is_ruined := destruction > 0.62
	var neon := (_noise_neon.get_noise_2d(pos.x * 0.23, pos.y * 0.29) + 1.0) / 2.0

	var body_type := _pick_body_material(center_factor, is_ruined)
	var roof_type := VoxelTypes.Type.CONCRETE_DARK if not is_ruined else VoxelTypes.Type.METAL_RUSTED

	var taper_inset_max := 0
	if height >= taper_min_height:
		taper_inset_max = clampi(roundi(float(height - taper_min_height) * taper_rate), 1, 4)

	for lx in range(size.x):
		for lz in range(size.y):
			if not _in_chamfered(lx, lz, size, chamfer):
				continue
			var wx := pos.x + lx
			var wz := pos.y + lz
			var col_h := height
			if is_ruined:
				# Jagged broken top: each column loses a random amount.
				col_h = maxi(2, height - rng.randi_range(0, maxi(height / 6, 1)))
			for y in range(1, col_h + 1):
				# Tapering: higher layers get narrower footprint.
				if taper_inset_max > 0 and not is_ruined:
					var progress := float(y) / float(col_h)
					var inset := roundi(progress * taper_inset_max)
					if lx < inset or lx >= size.x - inset or lz < inset or lz >= size.y - inset:
						continue

				# Shear: vertical base up to lean_start_ratio, then tilt.
				var shear := Vector2i.ZERO
				if lean != Vector2.ZERO:
					var lean_progress := clampf((float(y) / float(height) - lean_start_ratio) / (1.0 - lean_start_ratio), 0.0, 1.0)
					shear = Vector2i(
						roundi(lean.x * lean_progress * max_lean_shear),
						roundi(lean.y * lean_progress * max_lean_shear)
					)
				var vt := body_type
				if y == col_h:
					vt = roof_type
				elif _is_perimeter(lx, lz, size) and col_h >= 4 and y % 4 == 0:
					if rng.randf() < 0.55:
						vt = VoxelTypes.Type.GLASS_LIT if rng.randf() < 0.35 else VoxelTypes.Type.GLASS
				elif is_ruined and rng.randf() < 0.04:
					vt = VoxelTypes.Type.METAL_RUSTED
				_place(wx + shear.x, y, wz + shear.y, vt)
			# Rubble skirt at the base of ruined structures.
			if is_ruined and rng.randf() < 0.08:
				var rubble_h := rng.randi_range(1, 2)
				for ry in range(rubble_h):
					_place(wx, ry + 1, wz, VoxelTypes.Type.CONCRETE_DARK)

	# Neon edge strip on one chamfered corner of intact mid/high buildings.
	if neon > 0.72 and not is_ruined and height >= 10 and center_factor > 0.35:
		_add_neon_corner(pos, size, height, chamfer, lean)


func _in_chamfered(lx: int, lz: int, size: Vector2i, c: int) -> bool:
	if c <= 0:
		return true
	var mx := size.x - 1 - lx
	var mz := size.y - 1 - lz
	return (lx + lz >= c) and (mx + lz >= c) and (lx + mz >= c) and (mx + mz >= c)


func _is_perimeter(lx: int, lz: int, size: Vector2i) -> bool:
	return lx == 0 or lz == 0 or lx == size.x - 1 or lz == size.y - 1


func _pick_body_material(center_factor: float, is_ruined: bool) -> int:
	if is_ruined:
		return VoxelTypes.Type.CONCRETE_DARK if _rng.randf() > 0.3 else VoxelTypes.Type.METAL_RUSTED
	if center_factor > 0.6:
		return VoxelTypes.Type.CONCRETE_LIGHT if _rng.randf() > 0.5 else VoxelTypes.Type.CONCRETE
	return VoxelTypes.Type.CONCRETE


func _add_neon_corner(pos: Vector2i, size: Vector2i, height: int, chamfer: int, lean: Vector2) -> void:
	var colors := [
		VoxelTypes.Type.NEON_CYAN,
		VoxelTypes.Type.NEON_MAGENTA,
		VoxelTypes.Type.NEON_ORANGE,
		VoxelTypes.Type.NEON_GREEN,
	]
	var color: int = colors[_rng.randi() % colors.size()]
	# Corner cell sits just inside the chamfer diagonal.
	var cx := pos.x + mini(chamfer, size.x / 2)
	var cz := pos.y + mini(chamfer, size.y / 2)
	var strip_top := mini(height, 14)
	for y in range(1, strip_top + 1):
		var lean_progress := clampf((float(y) / float(strip_top) - lean_start_ratio) / (1.0 - lean_start_ratio), 0.0, 1.0)
		var shear := Vector2i(
			roundi(lean.x * lean_progress * max_lean_shear),
			roundi(lean.y * lean_progress * max_lean_shear)
		)
		_place(cx + shear.x, y, cz + shear.y, color)


func _scatter_rubble(ox: int, oz: int, area: int, rng: RandomNumberGenerator) -> void:
	for i in range(rng.randi_range(3, 7)):
		var x := ox + rng.randi_range(0, area - 1)
		var z := oz + rng.randi_range(0, area - 1)
		var h := rng.randi_range(1, 3)
		for y in range(1, h + 1):
			_place(x, y, z, VoxelTypes.Type.METAL_RUSTED if rng.randf() < 0.5 else VoxelTypes.Type.CONCRETE_DARK)


func _generate_platforms() -> void:
	var placed := 0
	var attempts := 0
	while placed < platform_count and attempts < platform_count * 8:
		attempts += 1
		var x := _rng.randf_range(-city_radius + 10, city_radius - 10)
		var z := _rng.randf_range(-city_radius + 10, city_radius - 10)
		if Vector2(x, z).length() > city_radius - wall_thickness - 4:
			continue
		var y := _rng.randi_range(14, 58)
		if _place_platform(roundi(x), y, roundi(z)):
			placed += 1
		await _spent(600)


func _place_platform(cx: int, cy: int, cz: int) -> bool:
	var half_x := _rng.randi_range(4, 10)
	var half_z := _rng.randi_range(4, 10)
	var thickness := _rng.randi_range(2, 4)
	var slope_mode := _rng.randf()
	var drop := _rng.randi_range(3, 8)
	var mat := VoxelTypes.Type.METAL_RUSTED if _rng.randf() < 0.6 else VoxelTypes.Type.CONCRETE_DARK

	# Slope direction: downhill toward -x/-z by default; flip sometimes.
	var flip := 1 if _rng.randf() < 0.5 else -1
	var span_f := float(maxi(half_x * 2, 1))

	for lx in range(-half_x, half_x + 1):
		for lz in range(-half_z, half_z + 1):
			# Rounded-corner plan: trim sharp rectangle corners slightly.
			if absi(lx) == half_x and absi(lz) == half_z:
				continue
			var top := cy
			var fx := float(lx + half_x) / span_f
			if slope_mode < 0.45:
				top += roundi(drop * fx * flip)
			elif slope_mode < 0.85:
				top += roundi(drop * fx * flip) + roundi(drop * 0.5 * float(lz + half_z) / float(maxi(half_z * 2, 1)))
			# else: flat slab (15%)
			for t in range(thickness):
				_place(cx + lx, top - t, cz + lz, mat)
			# Downhill edge lip: stops surf momentum from dumping you off.
			if slope_mode < 0.85 and lx == -half_x * flip and _rng.randf() < 0.6:
				_place(cx + lx, top + 1, cz + lz, mat)

	# Support column for lower platforms: thin metal pillar to the ground.
	if cy <= 34 and _rng.randf() < 0.5:
		for sx in range(cx - 1, cx + 1):
			for sz in range(cz - 1, cz + 1):
				var ground := world.get_height_at(sx, sz)
				for y in range(ground + 1, cy):
					_place(sx, y, sz, VoxelTypes.Type.METAL)
	return true


func _generate_wall() -> void:
	for x in range(-city_radius, city_radius):
		for z in range(-city_radius, city_radius):
			var dist := Vector2(x, z).length()
			if dist >= city_radius - wall_thickness and dist <= city_radius:
				for y in range(1, wall_height + 1):
					_place(x, y, z, VoxelTypes.Type.WALL)
		await _spent(city_radius * 4)
