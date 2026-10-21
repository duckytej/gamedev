class_name CityGenerator
extends Node

# Megastructure city generator, voxel core.
#
# Every city BLOCK (the area between 4 street intersections) gets filled
# with buildings that sit ON the block, never on the road. The block grid
# and street grid are offset: each block has a 3-wide street at a known
# internal position, and buildings are placed AFTER the street + gap.
#
# Some blocks absorb their right/down/both neighbors (street segments
# removed), creating merged mega-blocks. Quads (4-building layout) only
# appear in merged blocks where there's enough space.
#
# The perimeter wall is an irregular noise-driven voxel ring, ~200 tall,
# that cuts through the world as an oppressive megastructure boundary.
# Being voxels it enjoys greedy meshing, both-sided rendering, and
# structural (non-destructible) collision through the chunk system.
#
# Destruction: all concrete/metal/glass/neon voxels are destructible via
# VoxelWorld.remove_voxels_in_sphere; roads/wall are structural.

@export var world: VoxelWorld
@export var city_radius: int = 100
@export var street_spacing: int = 16
@export var street_width: int = 3
@export var max_building_height: int = 64
@export var wall_height: int = 200
@export var wall_thickness: int = 3
@export var platform_count: int = 38
@export var lean_cluster_size: int = 24
@export var max_lean_shear: float = 2.5
@export var taper_min_height: int = 20
@export var taper_rate: float = 0.03
@export var lean_start_ratio: float = 0.45
@export var block_merge_chance: float = 0.2

var _noise_districts: FastNoiseLite
var _noise_destruction: FastNoiseLite
var _noise_neon: FastNoiseLite
var _noise_height: FastNoiseLite
var _noise_wall: FastNoiseLite
var _rng := RandomNumberGenerator.new()
var _lean_cache: Dictionary = {}
var _work_accum := 0
var _placed_buildings: Array[Dictionary] = []

var _consumed_blocks: Dictionary = {}
var _merge_dir: Dictionary = {}
var _skip_v_lines: Dictionary = {}
var _skip_h_lines: Dictionary = {}


func generate() -> void:
	assert(world != null)
	var seed_base := randi()
	_rng.seed = seed_base
	_setup_noise(seed_base)
	_placed_buildings.clear()
	_precompute_block_merges()
	await _generate_ground_and_roads()
	await _generate_buildings()
	await _generate_platforms()
	await _generate_wall()


func _setup_noise(seed_base: int) -> void:
	_noise_districts = FastNoiseLite.new()
	_noise_districts.seed = seed_base
	_noise_districts.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise_districts.frequency = 0.012

	_noise_destruction = FastNoiseLite.new()
	_noise_destruction.seed = seed_base + 11
	_noise_destruction.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise_destruction.frequency = 0.05
	_noise_destruction.fractal_octaves = 4

	_noise_neon = FastNoiseLite.new()
	_noise_neon.seed = seed_base + 22
	_noise_neon.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise_neon.frequency = 0.02

	_noise_height = FastNoiseLite.new()
	_noise_height.seed = seed_base + 33
	_noise_height.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise_height.frequency = 0.007

	_noise_wall = FastNoiseLite.new()
	_noise_wall.seed = seed_base + 44
	_noise_wall.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise_wall.frequency = 0.015
	_noise_wall.fractal_octaves = 3


# --- Block merge precomputation ---

func _precompute_block_merges() -> void:
	_consumed_blocks.clear()
	_merge_dir.clear()
	_skip_v_lines.clear()
	_skip_h_lines.clear()
	var step := street_spacing
	var grid_min := ceili(float(-city_radius) / float(step)) * step
	var grid_limit := floori(float(city_radius) / float(step)) * step + step
	var last := grid_limit - step
	for bx in range(grid_min, grid_limit, step):
		for bz in range(grid_min, grid_limit, step):
			var key := Vector2i(bx, bz)
			if _consumed_blocks.has(key):
				continue
			if _rng.randf() >= block_merge_chance:
				continue
			var merge_right := _rng.randf() < 0.3
			var merge_down := _rng.randf() < 0.3
			var right_key := Vector2i(bx + step, bz)
			var down_key := Vector2i(bx, bz + step)
			var right_ok := right_key.x <= last and not _consumed_blocks.has(right_key) and not _merge_dir.has(right_key)
			var down_ok := down_key.y <= last and not _consumed_blocks.has(down_key) and not _merge_dir.has(down_key)
			if merge_right and right_ok:
				_consumed_blocks[right_key] = true
				_merge_dir[key] = "right" if not merge_down or not down_ok else "both"
				_add_skip_segment(_skip_v_lines, bx + step, bz, bz + step)
			if merge_down and down_ok:
				_consumed_blocks[down_key] = true
				if not _merge_dir.has(key):
					_merge_dir[key] = "down"
				else:
					_merge_dir[key] = "both"
				_add_skip_segment(_skip_h_lines, bz + step, bx, bx + step)


func _add_skip_segment(skip_map: Dictionary, line: int, a: int, b: int) -> void:
	if not skip_map.has(line):
		skip_map[line] = []
	skip_map[line].append(Vector2i(a, b))


func _line_segment_skipped(skip_map: Dictionary, line: int, coord: int) -> bool:
	if not skip_map.has(line):
		return false
	for seg: Vector2i in skip_map[line]:
		if coord >= seg.x and coord < seg.y:
			return true
	return false


# --- Helpers ---

func _spent(cost: int) -> void:
	_work_accum += cost
	if _work_accum > 12000:
		_work_accum = 0
		await get_tree().process_frame


func _place(x: int, y: int, z: int, type: int) -> void:
	world.set_voxel_at(x, y, z, type)


# --- Ground + Roads ---

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
	var offset_x := posmod(x, street_spacing)
	if offset_x < street_width:
		var line_x := x - offset_x
		if not _line_segment_skipped(_skip_v_lines, line_x, z):
			return true
	var offset_z := posmod(z, street_spacing)
	if offset_z < street_width:
		var line_z := z - offset_z
		if not _line_segment_skipped(_skip_h_lines, line_z, x):
			return true
	return false


func _is_center_line(x: int, z: int) -> bool:
	var mid := street_width / 2
	var cx := posmod(x, street_spacing) == mid
	var cz := posmod(z, street_spacing) == mid
	return (cx and posmod(z, 6) < 3) or (cz and posmod(x, 6) < 3)


# --- Buildings ---

func _generate_buildings() -> void:
	var step := street_spacing
	var grid_min := ceili(float(-city_radius) / float(step)) * step
	var grid_limit := floori(float(city_radius) / float(step)) * step + step
	for bx in range(grid_min, grid_limit, step):
		for bz in range(grid_min, grid_limit, step):
			var center := Vector2(bx + step / 2.0, bz + step / 2.0)
			if center.length() > city_radius - 4:
				continue
			if _consumed_blocks.has(Vector2i(bx, bz)):
				continue
			var block_seed := hash(Vector2i(bx, bz)) ^ _rng.seed
			var block_rng := RandomNumberGenerator.new()
			block_rng.seed = block_seed
			_generate_block(Vector2i(bx, bz), center, block_rng)
			await _spent(400)


func _generate_block(bx: Vector2i, center: Vector2, rng: RandomNumberGenerator) -> void:
	var step := street_spacing
	var gap := 1
	var dir: String = _merge_dir.get(bx, "")
	var center_factor := clampf(1.0 - center.length() / float(city_radius), 0.0, 1.0)

	# Compute where the street sits within this block.
	var street_pos := posmod(-bx.x, step)

	# Building origin: after the street + gap.
	var ox := bx.x + street_pos + street_width + gap
	var oz := bx.y + street_pos + street_width + gap

	# Single block size: fills the non-street area after the street.
	var inner_size := step - street_pos - street_width - gap

	# Merged block dimensions: span from this block's building origin
	# through the skipped street to the end of the neighbor block.
	var bw: int
	var bd: int
	if dir == "right" or dir == "both":
		bw = 2 * step - street_pos - street_width - gap
	else:
		bw = inner_size
	if dir == "down" or dir == "both":
		bd = 2 * step - street_pos - street_width - gap
	else:
		bd = inner_size

	var district := _noise_districts.get_noise_2d(center.x, center.y)
	if district < -0.65 and center_factor < 0.3:
		_build_footprint(
			Vector2i(ox, oz), Vector2i(bw, bd),
			_pick_height(Vector2i(bx.x, bx.y), center_factor * 0.5),
			Vector2.ZERO, 1, center_factor * 0.5
		)
		return

	var roll := rng.randf()

	if dir != "":
		_generate_merged_block(Vector2i(ox, oz), Vector2i(bw, bd), center_factor, rng)
	elif roll < 0.25 or center_factor > 0.60:
		_generate_quad(ox, oz, inner_size, center_factor, rng)
	elif roll < 0.50:
		_generate_single(ox, oz, inner_size, center_factor, rng)
	elif roll < 0.75:
		_generate_split(ox, oz, inner_size, center_factor, rng)
	else:
		_generate_l_shape(ox, oz, inner_size, center_factor, rng)


func _generate_quad(ox: int, oz: int, inner_size: int, center_factor: float, rng: RandomNumberGenerator) -> void:
	var half := inner_size / 2
	var gutter := maxi(1, (inner_size - half * 2) / 2)
	var lean := _get_cluster_lean(Vector2i(ox, oz), Vector2i(inner_size, inner_size))

	var layouts: Array[Vector2i] = [
		Vector2i(ox, oz),
		Vector2i(ox + half + gutter, oz),
		Vector2i(ox, oz + half + gutter),
		Vector2i(ox + half + gutter, oz + half + gutter),
	]

	for i in layouts.size():
		var qx := layouts[i].x
		var qz := layouts[i].y
		var w := mini(half, ox + inner_size - qx)
		var d := mini(half, oz + inner_size - qz)
		if w < 2 or d < 2:
			continue
		var h_factor := center_factor
		if i == 3:
			h_factor = center_factor * 0.9
		elif i > 0:
			h_factor = center_factor * rng.randf_range(0.75, 1.0)
		var h := _pick_height(Vector2i(qx, qz), h_factor)
		var use_lean := lean if i == 0 else Vector2.ZERO
		_build_footprint(Vector2i(qx, qz), Vector2i(w, d), h, use_lean, 1, h_factor)


func _generate_single(ox: int, oz: int, inner_size: int, center_factor: float, rng: RandomNumberGenerator) -> void:
	var lean := _get_cluster_lean(Vector2i(ox, oz), Vector2i(inner_size, inner_size))
	var h := _pick_height(Vector2i(ox, oz), center_factor)
	_build_footprint(Vector2i(ox, oz), Vector2i(inner_size, inner_size), h, lean, 2, center_factor)


func _generate_split(ox: int, oz: int, inner_size: int, center_factor: float, rng: RandomNumberGenerator) -> void:
	var half := inner_size / 2
	var gutter := maxi(1, (inner_size - half * 2) / 2)
	var lean := _get_cluster_lean(Vector2i(ox, oz), Vector2i(inner_size, inner_size))
	var horizontal := rng.randf() < 0.5

	for q in range(2):
		var qx: int
		var qz: int
		var w: int
		var d: int
		if horizontal:
			qx = ox
			qz = oz + q * (half + gutter)
			w = inner_size
			d = mini(half, oz + inner_size - qz)
		else:
			qx = ox + q * (half + gutter)
			qz = oz
			w = mini(half, ox + inner_size - qx)
			d = inner_size
		var h_factor := center_factor * rng.randf_range(0.8, 1.0)
		var h := _pick_height(Vector2i(qx, qz), h_factor)
		var use_lean := lean if q == 0 else Vector2.ZERO
		_build_footprint(Vector2i(qx, qz), Vector2i(w, d), h, use_lean, 1, h_factor)


func _generate_l_shape(ox: int, oz: int, inner_size: int, center_factor: float, rng: RandomNumberGenerator) -> void:
	var half := inner_size / 2
	var lean := _get_cluster_lean(Vector2i(ox, oz), Vector2i(inner_size, inner_size))

	# L-shape: two slabs forming an L, rotated randomly.
	var rot := rng.randi_range(0, 3)
	for q in range(2):
		var qx: int
		var qz: int
		var w: int
		var d: int
		match rot:
			0:
				qx = ox + (0 if q == 0 else half)
				qz = oz + (0 if q == 0 else half)
				w = (half if q == 0 else inner_size - half)
				d = (inner_size if q == 0 else half)
			1:
				qx = ox + (0 if q == 0 else half)
				qz = oz + (0 if q == 0 else 0)
				w = (half if q == 0 else inner_size - half)
				d = (inner_size if q == 0 else half)
			2:
				qx = ox + (0 if q == 0 else 0)
				qz = oz + (0 if q == 0 else half)
				w = (inner_size if q == 0 else half)
				d = (half if q == 0 else inner_size - half)
			3:
				qx = ox + (0 if q == 0 else half)
				qz = oz + (0 if q == 0 else 0)
				w = (half if q == 0 else inner_size - half)
				d = (inner_size if q == 0 else half)
		if w < 2 or d < 2:
			continue
		var h_factor := center_factor * rng.randf_range(0.85, 1.0)
		var h := _pick_height(Vector2i(qx, qz), h_factor)
		var use_lean := lean if q == 0 else Vector2.ZERO
		_build_footprint(Vector2i(qx, qz), Vector2i(w, d), h, use_lean, 1, h_factor)


func _generate_merged_block(building_pos: Vector2i, building_size: Vector2i, center_factor: float, rng: RandomNumberGenerator) -> void:
	var lean := _get_cluster_lean(building_pos, building_size)
	var roll := rng.randf()

	if roll < 0.35 or center_factor > 0.55:
		# Fill merged block with a quad of buildings.
		var bw := building_size.x
		var bd := building_size.y
		var half_x := bw / 2
		var half_y := bd / 2
		var gx := maxi(1, (bw - half_x * 2) / 2)
		var gy := maxi(1, (bd - half_y * 2) / 2)
		var layouts: Array[Vector4i] = [
			Vector4i(building_pos.x, building_pos.y, half_x, half_y),
			Vector4i(building_pos.x + half_x + gx, building_pos.y, bw - half_x - gx, half_y),
			Vector4i(building_pos.x, building_pos.y + half_y + gy, half_x, bd - half_y - gy),
			Vector4i(building_pos.x + half_x + gx, building_pos.y + half_y + gy, bw - half_x - gx, bd - half_y - gy),
		]
		for i in layouts.size():
			var l: Vector4i = layouts[i]
			if l.z < 3 or l.w < 3:
				continue
			var h_factor := center_factor * rng.randf_range(0.7, 1.0)
			var h := _pick_height(Vector2i(l.x, l.y), h_factor)
			var use_lean := lean if i == 0 else Vector2.ZERO
			_build_footprint(Vector2i(l.x, l.y), Vector2i(l.z, l.w), h, use_lean, 1, h_factor)
	elif roll < 0.65:
		# Two tall slabs, randomly oriented.
		var horizontal := rng.randf() < 0.5
		if horizontal:
			var half := building_size.y / 2
			var gutter := maxi(1, (building_size.y - half * 2) / 2)
			for q in range(2):
				var qz := building_pos.y + q * (half + gutter)
				var d := mini(half, building_pos.y + building_size.y - qz)
				var h := _pick_height(Vector2i(building_pos.x, qz), center_factor * rng.randf_range(0.8, 1.0))
				var use_lean := lean if q == 0 else Vector2.ZERO
				_build_footprint(Vector2i(building_pos.x, qz), Vector2i(building_size.x, d), h, use_lean, 1, center_factor)
		else:
			var half := building_size.x / 2
			var gutter := maxi(1, (building_size.x - half * 2) / 2)
			for q in range(2):
				var qx := building_pos.x + q * (half + gutter)
				var w := mini(half, building_pos.x + building_size.x - qx)
				var h := _pick_height(Vector2i(qx, building_pos.y), center_factor * rng.randf_range(0.8, 1.0))
				var use_lean := lean if q == 0 else Vector2.ZERO
				_build_footprint(Vector2i(qx, building_pos.y), Vector2i(w, building_size.y), h, use_lean, 1, center_factor)
	else:
		# Single mega-building filling the merged space.
		var h := _pick_height(building_pos, center_factor)
		_build_footprint(building_pos, building_size, h, lean, 3, center_factor)


func _pick_height(pos: Vector2i, center_factor: float) -> int:
	var h1 := (_noise_height.get_noise_2d(pos.x, pos.y) + 1.0) / 2.0
	var h2 := (_noise_height.get_noise_2d(pos.x * 1.7 + 50.0, pos.y * 1.3 + 50.0) + 1.0) / 2.0
	var height_var := (h1 * 0.65 + h2 * 0.35)

	var build_hash := float((pos.x * 73856093 ^ pos.y * 19349669) & 0x7FFFFFFF) / float(0x7FFFFFFF)
	height_var = clampf(height_var * 0.7 + build_hash * 0.3, 0.0, 1.0)

	var base_h: float
	if center_factor > 0.65:
		base_h = lerpf(14.0, float(max_building_height), height_var)
	elif center_factor > 0.35:
		base_h = lerpf(4.0, 24.0, height_var)
	else:
		base_h = lerpf(2.0, 10.0, height_var)

	var destruction := (_noise_destruction.get_noise_2d(pos.x * 1.7, pos.y * 2.3) + 1.0) / 2.0
	if destruction > 0.65:
		base_h *= randf_range(0.4, 0.65)
	return maxi(roundi(base_h), 2)


func _get_cluster_lean(pos: Vector2i, size: Vector2i) -> Vector2:
	var center := Vector2(pos) + Vector2(size) * 0.5
	var key := Vector2i(floori(center.x / lean_cluster_size), floori(center.y / lean_cluster_size))
	if not _lean_cache.has(key):
		if _rng.randf() < 0.55:
			_lean_cache[key] = Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)).normalized()
		else:
			_lean_cache[key] = Vector2.ZERO
	return _lean_cache[key]


func _build_footprint(pos: Vector2i, size: Vector2i, height: int, lean: Vector2, chamfer: int, center_factor: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(pos) ^ _rng.seed
	var destruction := (_noise_destruction.get_noise_2d(pos.x * 0.37, pos.y * 0.41) + 1.0) / 2.0
	var is_ruined := destruction > 0.65
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
				col_h = maxi(2, height - rng.randi_range(0, maxi(height / 6, 1)))
			for y in range(1, col_h + 1):
				if taper_inset_max > 0 and not is_ruined:
					var progress := float(y) / float(col_h)
					var inset := roundi(progress * taper_inset_max)
					if lx < inset or lx >= size.x - inset or lz < inset or lz >= size.y - inset:
						continue

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
				elif y == 1:
					vt = VoxelTypes.Type.CONCRETE_DARK
				_place(wx + shear.x, y, wz + shear.y, vt)
			if is_ruined and rng.randf() < 0.08:
				var rubble_h := rng.randi_range(1, 2)
				for ry in range(rubble_h):
					_place(wx, ry + 1, wz, VoxelTypes.Type.CONCRETE_DARK)

	if neon > 0.7 and not is_ruined and height >= 8 and center_factor > 0.3:
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
	var cx := pos.x + mini(chamfer, size.x / 2)
	var cz := pos.y + mini(chamfer, size.y / 2)
	var strip_top := mini(height, 18)
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


# --- Floating Platforms ---

func _generate_platforms() -> void:
	var placed := 0
	var attempts := 0
	while placed < platform_count and attempts < platform_count * 8:
		attempts += 1
		var x := _rng.randf_range(-city_radius + 10, city_radius - 10)
		var z := _rng.randf_range(-city_radius + 10, city_radius - 10)
		if Vector2(x, z).length() > city_radius - 6:
			continue
		var y := _rng.randi_range(16, 64)
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

	var flip := 1 if _rng.randf() < 0.5 else -1
	var span_f := float(maxi(half_x * 2, 1))

	for lx in range(-half_x, half_x + 1):
		for lz in range(-half_z, half_z + 1):
			if absi(lx) == half_x and absi(lz) == half_z:
				continue
			var top := cy
			var fx := float(lx + half_x) / span_f
			if slope_mode < 0.45:
				top += roundi(drop * fx * flip)
			elif slope_mode < 0.85:
				top += roundi(drop * fx * flip) + roundi(drop * 0.5 * float(lz + half_z) / float(maxi(half_z * 2, 1)))
			for t in range(thickness):
				_place(cx + lx, top - t, cz + lz, mat)
			if slope_mode < 0.85 and lx == -half_x * flip and _rng.randf() < 0.6:
				_place(cx + lx, top + 1, cz + lz, mat)

	if cy <= 38 and _rng.randf() < 0.5:
		for sx in range(cx - 1, cx + 1):
			for sz in range(cz - 1, cz + 1):
				var ground := world.get_height_at(sx, sz)
				for y in range(ground + 1, cy):
					_place(sx, y, sz, VoxelTypes.Type.METAL)
	return true


# --- Perimeter Wall (voxel ring, noise-driven radius, ~200 tall) ---

func _generate_wall() -> void:
	var noise_amp := 8.0
	var extent := city_radius + wall_thickness + 6
	var r_inner := float(city_radius - wall_thickness)
	var r_outer := float(city_radius + wall_thickness)
	var half_t := float(wall_thickness) / 2.0 + 0.5

	# Pass 1: collect the ring cells (2D footprint only).
	var ring_cells: Array[Vector2i] = []
	for x in range(-extent, extent + 1):
		for z in range(-extent, extent + 1):
			var r := Vector2(x, z).length()
			if r < r_inner - noise_amp or r > r_outer + noise_amp:
				continue
			var angle := atan2(float(z), float(x))
			var n := _noise_wall.get_noise_2d(cos(angle) * 2.0, sin(angle) * 2.0)
			var target := float(city_radius) + n * noise_amp
			if absf(r - target) <= half_t:
				ring_cells.append(Vector2i(x, z))
		await _spent(extent * 2)

	# Pass 2: extrude each ring cell up to wall_height.
	for cell: Vector2i in ring_cells:
		for y in range(wall_height):
			_place(cell.x, y, cell.y, VoxelTypes.Type.WALL)
		await _spent(wall_height)
