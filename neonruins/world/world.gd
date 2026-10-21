extends Node3D

# Procedural ruined-city generator.
# Block-based placement prevents overlapping buildings.
# Central Cybergrind arena + great wall perimeter.

const NEON_COLORS: Array[Color] = [
	Color(0.0, 1.0, 0.85),   # cyan
	Color(1.0, 0.0, 0.6),    # magenta
	Color(1.0, 0.45, 0.0),   # orange
	Color(0.2, 1.0, 0.3),    # green
]

const SIGN_WORDS: Array[String] = [
	"OPEN", "CLOSED", "WARNING", "DANGER", "EXIT", "ENTRY",
	"NO SIGNAL", "OFFLINE", "REBOOT", "ACCESS DENIED",
	"SYSTEM ERROR", "ALERT", "ZONE 7", "SECTOR 12", "BLOCK C", "CORE HUB",
]

var noise_districts: FastNoiseLite
var noise_buildings: FastNoiseLite
var noise_destruction: FastNoiseLite
var noise_detail: FastNoiseLite
var noise_neon: FastNoiseLite
var noise_height: FastNoiseLite

var city_size: int = 80
var block_size: float = 4.0
var max_building_height: int = 25
var street_spacing: int = 16
var street_width: int = 3

var mat_concrete: StandardMaterial3D
var mat_concrete_dark: StandardMaterial3D
var mat_concrete_light: StandardMaterial3D
var mat_metal: StandardMaterial3D
var mat_metal_rusted: StandardMaterial3D
var mat_glass: StandardMaterial3D
var mat_glass_broken: StandardMaterial3D
var mat_glass_lit: StandardMaterial3D
var mat_neon: Array[StandardMaterial3D] = []
var mat_emissive_fire: StandardMaterial3D
var mat_road: StandardMaterial3D
var mat_road_line: StandardMaterial3D
var mat_arena_floor: StandardMaterial3D
var mat_wall: StandardMaterial3D

var building_data: Array[Dictionary] = []
var spawn_positions: Array[Vector3] = []


func _ready() -> void:
	Globals.game_map = self
	city_size = Globals.config.city_size
	block_size = Globals.config.block_size
	max_building_height = Globals.config.max_building_height
	street_spacing = Globals.config.street_spacing
	street_width = Globals.config.street_width

	_setup_materials()
	_setup_noise()
	call_deferred("_generate_city")


func _setup_materials() -> void:
	mat_concrete = _make_mat(Color(0.42, 0.42, 0.45), 0.85, 0.05)
	mat_concrete_dark = _make_mat(Color(0.28, 0.28, 0.32), 0.9, 0.1)
	mat_concrete_light = _make_mat(Color(0.55, 0.55, 0.6), 0.8, 0.03)
	mat_metal = _make_mat(Color(0.45, 0.48, 0.52), 0.4, 0.85)
	mat_metal_rusted = _make_mat(Color(0.5, 0.35, 0.22), 0.9, 0.3)

	mat_glass = _make_mat(Color(0.15, 0.2, 0.25), 0.05, 0.1)
	mat_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_glass.render_priority = 1
	mat_glass_broken = _make_mat(Color(0.18, 0.2, 0.22), 0.2, 0.05)

	# Lit window — warm interior glow visible from outside
	mat_glass_lit = StandardMaterial3D.new()
	mat_glass_lit.albedo_color = Color(0.0, 0.0, 0.0)
	mat_glass_lit.emission_enabled = true
	mat_glass_lit.emission = Color(0.9, 0.75, 0.4) * 1.2
	mat_glass_lit.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_glass_lit.render_priority = 1

	for c in NEON_COLORS:
		mat_neon.append(_make_emissive(c, 4.0))

	mat_emissive_fire = _make_emissive(Color(1.0, 0.3, 0.05), 5.0)

	mat_road = _make_mat(Color(0.18, 0.18, 0.22), 0.95, 0.02)
	mat_road_line = _make_emissive(Color(1.0, 0.95, 0.6), 2.0)

	mat_arena_floor = _make_mat(Color(0.12, 0.14, 0.18), 0.7, 0.6)
	mat_arena_floor.emission_enabled = true
	mat_arena_floor.emission = Color(0.0, 0.6, 0.8) * 0.3

	mat_wall = _make_mat(Color(0.3, 0.3, 0.35), 0.9, 0.1)


func _make_mat(albedo: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.roughness = roughness
	m.metallic = metallic
	return m


func _make_emissive(color: Color, strength: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.02, 0.02, 0.02)
	m.emission_enabled = true
	m.emission = color * strength
	m.metallic = 0.0
	return m


func _setup_noise() -> void:
	var base_seed := randi()

	noise_districts = FastNoiseLite.new()
	noise_districts.seed = base_seed
	noise_districts.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise_districts.frequency = 0.015

	noise_buildings = FastNoiseLite.new()
	noise_buildings.seed = base_seed + 1000
	noise_buildings.noise_type = FastNoiseLite.TYPE_CELLULAR
	noise_buildings.frequency = 0.045
	noise_buildings.cellular_distance_function = FastNoiseLite.CellularDistanceFunction.DISTANCE_MANHATTAN

	noise_destruction = FastNoiseLite.new()
	noise_destruction.seed = base_seed + 2000
	noise_destruction.noise_type = FastNoiseLite.TYPE_PERLIN
	noise_destruction.frequency = 0.06
	noise_destruction.fractal_octaves = 4

	noise_detail = FastNoiseLite.new()
	noise_detail.seed = base_seed + 3000
	noise_detail.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise_detail.frequency = 0.12

	noise_neon = FastNoiseLite.new()
	noise_neon.seed = base_seed + 4000
	noise_neon.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise_neon.frequency = 0.025

	noise_height = FastNoiseLite.new()
	noise_height.seed = base_seed + 5000
	noise_height.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise_height.frequency = 0.008


func _generate_city() -> void:
	print("Generating ruined city... (%d x %d blocks)" % [city_size * 2, city_size * 2])

	_create_road_network()
	_generate_buildings()
	_create_arena()
	_create_great_wall()
	_create_neon_signage()
	_create_parkour_elements()
	_create_atmosphere()
	_spawn_player()
	_spawn_enemies()

	print("City generation complete! Buildings: %d | Spawns: %d" % [building_data.size(), spawn_positions.size()])


# === ROAD NETWORK ===

func _create_road_network() -> void:
	var span := city_size * block_size

	var ground := MeshInstance3D.new()
	var plane := BoxMesh.new()
	var road_size := span * 2.0 + 20.0
	plane.size = Vector3(road_size, 1.0, road_size)
	ground.mesh = plane
	ground.position = Vector3(0, -0.5, 0)
	ground.material_override = mat_road
	add_child(ground)

	var body := StaticBody3D.new()
	body.position = Vector3(0, -0.5, 0)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = plane.size
	col.shape = shape
	body.add_child(col)
	add_child(body)

	for gx in range(-city_size, city_size + 1, street_spacing):
		_create_road_strip_x(gx * block_size, -span - 10.0, span * 2.0 + 20.0)
		_create_road_strip_z(gx * block_size, -span - 10.0, span * 2.0 + 20.0)


func _create_road_strip_x(x: float, z_start: float, length: float) -> void:
	var strip := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.4, 0.08, length)
	strip.mesh = box
	strip.position = Vector3(x, 0.04, z_start + length * 0.5)
	strip.material_override = mat_road
	add_child(strip)

	for i in range(int(length / 6.0)):
		var line := MeshInstance3D.new()
		var lbox := BoxMesh.new()
		lbox.size = Vector3(0.15, 0.02, 2.0)
		line.mesh = lbox
		line.position = Vector3(x, 0.09, z_start + 3.0 + i * 6.0)
		line.material_override = mat_road_line
		add_child(line)


func _create_road_strip_z(z: float, x_start: float, length: float) -> void:
	var strip := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(length, 0.08, 0.4)
	strip.mesh = box
	strip.position = Vector3(x_start + length * 0.5, 0.04, z)
	strip.material_override = mat_road
	add_child(strip)

	for i in range(int(length / 6.0)):
		var line := MeshInstance3D.new()
		var lbox := BoxMesh.new()
		lbox.size = Vector3(2.0, 0.02, 0.15)
		line.mesh = lbox
		line.position = Vector3(x_start + 3.0 + i * 6.0, 0.09, z)
		line.material_override = mat_road_line
		add_child(line)


# === BUILDINGS (block-based, no overlaps) ===

func _generate_buildings() -> void:
	# Iterate over city blocks (each block is the area between streets)
	var half := city_size / street_spacing
	for bx in range(-half, half):
		for bz in range(-half, half):
			# Block origin in grid coords
			var gx0 := bx * street_spacing + street_width
			var gz0 := bz * street_spacing + street_width
			var block_cells := street_spacing - street_width  # usable cells per side

			if block_cells <= 0:
				continue

			var center_gx := bx * street_spacing + street_spacing * 0.5
			var center_gz := bz * street_spacing + street_spacing * 0.5
			var dist_from_center := sqrt(center_gx * center_gx + center_gz * center_gz)
			var center_factor := clampf(1.0 - (dist_from_center / (city_size * 0.7)), 0.0, 1.0)

			var block_noise := noise_buildings.get_noise_2d(center_gx, center_gz)
			if block_noise < -0.7:
				# Sparse block — scattered debris only
				for i in range(randi_range(1, 4)):
					_create_debris_at(
						randf_range(gx0, gx0 + block_cells) * block_size,
						randf_range(gz0, gz0 + block_cells) * block_size
					)
				continue

			# Determine how many buildings fit in this block (2-5)
			var num_buildings: int
			if center_factor > 0.6:
				num_buildings = randi_range(2, 3)  # downtown: dense big buildings
			elif center_factor > 0.3:
				num_buildings = randi_range(2, 4)
			else:
				num_buildings = randi_range(3, 5)  # outskirts: more buildings

			# Place buildings evenly across the block
			var positions: Array[Vector2] = []
			if num_buildings == 1:
				positions.append(Vector2(
					gx0 + block_cells * 0.5,
					gz0 + block_cells * 0.5
				))
			elif num_buildings == 2:
				positions.append(Vector2(gx0 + block_cells * 0.25, gz0 + block_cells * 0.5))
				positions.append(Vector2(gx0 + block_cells * 0.75, gz0 + block_cells * 0.5))
			elif num_buildings == 3:
				positions.append(Vector2(gx0 + block_cells * 0.25, gz0 + 0.25))
				positions.append(Vector2(gx0 + block_cells * 0.75, gz0 + 0.25))
				positions.append(Vector2(gx0 + block_cells * 0.5, gz0 + block_cells * 0.75))
			else:
				var step := block_cells * 0.33
				positions.append(Vector2(gx0 + step, gz0 + step))
				positions.append(Vector2(gx0 + block_cells - step, gz0 + step))
				positions.append(Vector2(gx0 + step, gz0 + block_cells - step))
				positions.append(Vector2(gx0 + block_cells - step, gz0 + block_cells - step))

			for pos in positions:
				var gx := int(pos.x)
				var gz := int(pos.y)
				_create_building(
					gx, gz, block_cells,
					noise_districts.get_noise_2d(gx, gz),
					noise_height.get_noise_2d(gx, gz),
					noise_destruction.get_noise_2d(gx, gz),
					noise_detail.get_noise_2d(gx, gz),
					center_factor,
				)


func _create_building(gx: int, gz: int, block_cells: int, district_val: float,
		height_noise: float, destruction_val: float, detail_noise: float,
		center_factor: float) -> void:

	var destroyed := destruction_val > 0.35 or (destruction_val > 0.1 and randf() < 0.2)
	var archetype := _pick_archetype(district_val, center_factor, destroyed)
	var height := _calc_height(archetype, height_noise, destruction_val)

	# Scale building size to block — fills most of the cell
	var width := clampi(randi_range(block_cells - 2, block_cells), 2, 8)
	var depth := clampi(randi_range(block_cells - 2, block_cells), 2, 8)

	var world_x := gx * block_size
	var world_z := gz * block_size
	var building_pos := Vector3(
		world_x + width * block_size * 0.5,
		height * block_size * 0.5,
		world_z + depth * block_size * 0.5
	)

	var structure := _build_structure(width, depth, height, archetype, destroyed,
			detail_noise, world_x, world_z)
	structure.position = building_pos
	add_child(structure)

	var body := StaticBody3D.new()
	body.position = building_pos
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(width * block_size, height * block_size, depth * block_size)
	col.shape = shape
	body.add_child(col)
	add_child(body)

	building_data.append({
		"position": building_pos,
		"height": height * block_size,
		"width": width * block_size,
		"depth": depth * block_size,
		"roof_y": building_pos.y + height * block_size * 0.5,
		"archetype": archetype,
	})

	if height > 6:
		spawn_positions.append(Vector3(building_pos.x, building_pos.y + height * block_size * 0.5 + 2.0, building_pos.z))


func _pick_archetype(district: float, center: float, destroyed: bool) -> String:
	var base: String
	if center > 0.7:
		base = "skyscraper" if district > 0.2 else "office_tower"
	elif center > 0.4:
		base = "apartment_block" if district > 0.0 else "commercial"
	else:
		base = "house" if district > -0.2 else "warehouse"
	return "ruined_" + base if destroyed else base


func _calc_height(archetype: String, height_noise: float, destruction_val: float) -> int:
	var base_height := 5
	match archetype:
		"skyscraper":
			base_height = randi_range(18, max_building_height)
		"office_tower":
			base_height = randi_range(12, 20)
		"ruined_skyscraper":
			base_height = randi_range(10, 18)
		"ruined_office":
			base_height = randi_range(6, 12)
		"apartment_block":
			base_height = randi_range(8, 14)
		"ruined_apartment":
			base_height = randi_range(4, 8)
		"commercial":
			base_height = randi_range(4, 8)
		"ruined_commercial":
			base_height = randi_range(3, 5)
		"house":
			base_height = randi_range(2, 4)
		"ruined_house":
			base_height = randi_range(2, 3)
		"warehouse":
			base_height = randi_range(3, 6)
		"ruined_warehouse":
			base_height = randi_range(2, 4)

	base_height = int(base_height * lerpf(0.7, 1.3, (height_noise + 1.0) * 0.5))

	if destruction_val > 0.35:
		base_height = int(base_height * randf_range(0.4, 0.7))

	return maxi(base_height, 2)


func _build_structure(w: int, d: int, h: int, arch: String, destroyed: bool,
		detail: float, world_x: float, world_z: float) -> Node3D:
	var root := Node3D.new()

	var main := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(w * block_size, h * block_size, d * block_size)
	main.mesh = box
	main.material_override = _get_archetype_material(arch, destroyed)
	root.add_child(main)

	if not destroyed or randf() < 0.5:
		_add_facade_details(root, w, d, h, destroyed)

	_add_rooftop_details(root, w, d, h, destroyed)

	if destroyed:
		_add_destruction_details(root, w, d, h)

	# Neon placement — use actual world position for noise
	if noise_neon.get_noise_2d(world_x, world_z) > 0.0 or randf() < 0.4:
		_add_building_neon(root, w, d, h)

	return root


func _get_archetype_material(arch: String, destroyed: bool) -> StandardMaterial3D:
	if destroyed:
		return mat_metal_rusted if randf() < 0.5 else mat_concrete_dark
	match arch:
		"skyscraper", "office_tower":
			return mat_concrete_light
		"apartment_block", "commercial":
			return mat_concrete
		"house":
			return mat_concrete_dark
		"warehouse":
			return mat_metal
		_:
			return mat_concrete


func _add_facade_details(root: Node3D, w: int, d: int, h: int, destroyed: bool) -> void:
	var floor_h := block_size * 3.0
	var floors := maxi(1, int(h * block_size / floor_h))
	var half_w := w * block_size * 0.5
	var half_d := d * block_size * 0.5

	for f in range(floors):
		var fy := -h * block_size * 0.5 + f * floor_h + floor_h * 0.5

		for face in [[0.0, half_d + 0.04], [0.0, -half_d - 0.04]]:
			_add_window_row(root, w, fy, Vector3(face[0], fy, face[1]), 0.0, destroyed)
		_add_window_row(root, d, fy, Vector3(half_w + 0.04, fy, 0.0), 90.0, destroyed)
		_add_window_row(root, d, fy, Vector3(-half_w - 0.04, fy, 0.0), 90.0, destroyed)

		if randf() < 0.2 and not destroyed:
			_add_balcony(root, w, d, fy)


func _add_window_row(root: Node3D, span_cells: int, fy: float, origin: Vector3,
		yaw_deg: float, destroyed: bool) -> void:
	var win_count := maxi(1, int(span_cells * block_size / 3.5))
	for i in range(win_count):
		if destroyed and randf() < 0.6:
			continue

		var offset := (i - (win_count - 1) * 0.5) * 3.5
		var win := MeshInstance3D.new()
		var wbox := BoxMesh.new()
		wbox.size = Vector3(2.2, 1.8, 0.08)
		win.mesh = wbox
		win.position = origin
		win.rotation_degrees.y = yaw_deg
		if absf(yaw_deg) > 1.0:
			win.position.z += offset
		else:
			win.position.x += offset

		# Intact buildings get mostly lit windows; broken get dark
		if destroyed:
			win.material_override = mat_glass_broken
		else:
			win.material_override = mat_glass_lit if randf() < 0.65 else mat_glass
		root.add_child(win)


func _add_balcony(root: Node3D, w: int, d: int, fy: float) -> void:
	var side := randi_range(0, 3)
	var bal := MeshInstance3D.new()
	var bbox := BoxMesh.new()

	match side:
		0:
			bal.position = Vector3(randf_range(-w, w) * block_size * 0.25, fy - 1.0, d * block_size * 0.5 + 0.75)
			bbox.size = Vector3(3.0, 0.15, 1.5)
		1:
			bal.position = Vector3(randf_range(-w, w) * block_size * 0.25, fy - 1.0, -d * block_size * 0.5 - 0.75)
			bbox.size = Vector3(3.0, 0.15, 1.5)
		2:
			bal.position = Vector3(w * block_size * 0.5 + 0.75, fy - 1.0, randf_range(-d, d) * block_size * 0.25)
			bbox.size = Vector3(1.5, 0.15, 3.0)
		_:
			bal.position = Vector3(-w * block_size * 0.5 - 0.75, fy - 1.0, randf_range(-d, d) * block_size * 0.25)
			bbox.size = Vector3(1.5, 0.15, 3.0)

	bal.mesh = bbox
	bal.material_override = mat_metal
	root.add_child(bal)

	var rail := MeshInstance3D.new()
	var rbox := BoxMesh.new()
	rail.position = bal.position
	match side:
		0:
			rail.position.z += 0.7
			rbox.size = Vector3(3.2, 0.8, 0.1)
		1:
			rail.position.z -= 0.7
			rbox.size = Vector3(3.2, 0.8, 0.1)
		2:
			rail.position.x += 0.7
			rbox.size = Vector3(0.1, 0.8, 3.2)
		_:
			rail.position.x -= 0.7
			rbox.size = Vector3(0.1, 0.8, 3.2)

	rail.mesh = rbox
	rail.material_override = mat_metal_rusted
	root.add_child(rail)


func _add_rooftop_details(root: Node3D, w: int, d: int, h: int, destroyed: bool) -> void:
	var roof_y := h * block_size * 0.5
	var roof_mat := mat_metal_rusted if destroyed else mat_metal

	for i in range(randi_range(0, 4)):
		var obj := MeshInstance3D.new()
		var obox := BoxMesh.new()
		var os := randf_range(1.2, 2.8)
		obox.size = Vector3(os, os * randf_range(0.5, 1.2), os)
		obj.mesh = obox
		obj.position = Vector3(
			randf_range(-w * block_size * 0.35, w * block_size * 0.35),
			roof_y + obox.size.y * 0.5,
			randf_range(-d * block_size * 0.35, d * block_size * 0.35)
		)
		obj.material_override = roof_mat
		root.add_child(obj)

	if h > 12 and randf() < 0.3:
		var ant := MeshInstance3D.new()
		var abox := BoxMesh.new()
		abox.size = Vector3(0.2, randf_range(4, 10), 0.2)
		ant.mesh = abox
		ant.position = Vector3(randf_range(-1, 1), roof_y + abox.size.y * 0.5, randf_range(-1, 1))
		ant.material_override = mat_metal_rusted
		root.add_child(ant)

		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.1, 0.1)
		light.light_energy = 0.5
		light.omni_range = 8.0
		light.position = ant.position + Vector3(0, abox.size.y * 0.5 + 0.5, 0)
		root.add_child(light)

		var tween := light.create_tween()
		tween.set_loops()
		tween.tween_property(light, "light_energy", 0.05, 0.5).set_delay(randf_range(0.5, 2.0))
		tween.tween_property(light, "light_energy", 0.5, 0.1)


func _add_destruction_details(root: Node3D, w: int, d: int, h: int) -> void:
	var half_w := w * block_size * 0.45
	var half_d := d * block_size * 0.45
	var half_h := h * block_size * 0.4

	for i in range(randi_range(3, 8)):
		var reb := MeshInstance3D.new()
		var rbox := BoxMesh.new()
		rbox.size = Vector3(0.1, randf_range(1, 4), 0.1)
		reb.mesh = rbox
		reb.position = Vector3(
			randf_range(-half_w, half_w),
			randf_range(-half_h, half_h),
			(half_d if randf() < 0.5 else -half_d) + randf_range(-0.3, 0.3)
		)
		reb.rotation_degrees = Vector3(randf_range(-30, 30), 0, randf_range(-30, 30))
		reb.material_override = mat_metal_rusted
		root.add_child(reb)

	for i in range(randi_range(2, 5)):
		var ds := randf_range(0.8, 2.5)
		var deb_pos := Vector3(
			randf_range(-half_w, half_w),
			ds * 0.2,
			randf_range(-half_d, half_d)
		)

		var deb := MeshInstance3D.new()
		var dbox := BoxMesh.new()
		dbox.size = Vector3(ds, ds * 0.4, ds)
		deb.mesh = dbox
		deb.position = deb_pos
		deb.material_override = mat_concrete_dark
		root.add_child(deb)

		var db := StaticBody3D.new()
		db.position = deb_pos
		var dcol := CollisionShape3D.new()
		var dshape := BoxShape3D.new()
		dshape.size = dbox.size
		dcol.shape = dshape
		db.add_child(dcol)
		add_child(db)

	if randf() < 0.3:
		_add_fire_effect(root, w, d, h)


func _add_fire_effect(root: Node3D, w: int, d: int, h: int) -> void:
	for i in range(randi_range(2, 5)):
		var fire := MeshInstance3D.new()
		var fbox := BoxMesh.new()
		var fs := randf_range(0.5, 1.2)
		fbox.size = Vector3(fs, fs * 1.5, fs)
		fire.mesh = fbox
		fire.position = Vector3(
			randf_range(-w * block_size * 0.3, w * block_size * 0.3),
			randf_range(-h * block_size * 0.2, h * block_size * 0.3),
			randf_range(-d * block_size * 0.3, d * block_size * 0.3)
		)

		var fmat := mat_emissive_fire.duplicate() as StandardMaterial3D
		fire.material_override = fmat
		root.add_child(fire)

		var base_color := Color(1.0, 0.3, 0.05)
		var tween := fire.create_tween()
		tween.set_loops()
		tween.tween_property(fmat, "emission", base_color * 2.0, randf_range(0.1, 0.3))
		tween.tween_property(fmat, "emission", base_color * 5.0, randf_range(0.1, 0.3))


func _add_building_neon(root: Node3D, w: int, d: int, h: int) -> void:
	var neon_mat: StandardMaterial3D = mat_neon.pick_random()

	var strip := MeshInstance3D.new()
	var sbox := BoxMesh.new()
	sbox.size = Vector3(0.15, h * block_size * 0.8, 0.15)
	strip.mesh = sbox
	strip.position = Vector3(w * block_size * 0.5 - 0.1, 0, d * block_size * 0.5 - 0.1)
	strip.material_override = neon_mat
	root.add_child(strip)

	var haccent := MeshInstance3D.new()
	var hbox := BoxMesh.new()
	hbox.size = Vector3(w * block_size * 0.6, 0.1, 0.15)
	haccent.mesh = hbox
	haccent.position = Vector3(0, h * block_size * 0.1, d * block_size * 0.5 - 0.1)
	haccent.material_override = neon_mat
	root.add_child(haccent)


func _create_debris_at(wx: float, wz: float) -> void:
	for i in range(randi_range(1, 3)):
		var size := randf_range(0.6, 3.0)
		var pos := Vector3(wx + randf_range(-4, 4), size * 0.25, wz + randf_range(-4, 4))

		var deb := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(size, size * randf_range(0.3, 0.6), size)
		deb.mesh = box
		deb.position = pos
		deb.rotation_degrees = Vector3(randf_range(-15, 15), randf_range(0, 360), randf_range(-15, 15))
		deb.material_override = mat_concrete_dark
		add_child(deb)

		var body := StaticBody3D.new()
		body.position = pos
		body.rotation_degrees = deb.rotation_degrees
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = box.size
		col.shape = shape
		body.add_child(col)
		add_child(body)


# === CYBERGRIND ARENA (center) ===

func _create_arena() -> void:
	var arena_radius := 30.0
	var arena_height := 0.5

	# Raised circular platform
	var arena := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = arena_radius
	cylinder.bottom_radius = arena_radius
	cylinder.height = arena_height
	arena.mesh = cylinder
	arena.position = Vector3(0, arena_height * 0.5, 0)
	arena.material_override = mat_arena_floor
	add_child(arena)

	var arena_body := StaticBody3D.new()
	arena_body.position = arena.position
	var arena_col := CollisionShape3D.new()
	var arena_shape := CylinderShape3D.new()
	arena_shape.radius = arena_radius
	arena_shape.height = arena_height
	arena_col.shape = arena_shape
	arena_body.add_child(arena_col)
	add_child(arena_body)

	# Neon ring around the edge
	for i in range(32):
		var angle := i * TAU / 32.0
		var next_angle := (i + 1) * TAU / 32.0
		var seg := MeshInstance3D.new()
		var sbox := BoxMesh.new()
		var seg_len := arena_radius * TAU / 32.0
		sbox.size = Vector3(seg_len, 0.3, 0.3)
		seg.mesh = sbox
		seg.position = Vector3(
			cos(angle) * arena_radius,
			arena_height + 0.15,
			sin(angle) * arena_radius
		)
		seg.look_at_from_position(seg.position,
				Vector3(cos(next_angle) * arena_radius, arena_height + 0.15, sin(next_angle) * arena_radius),
				Vector3.UP)
		seg.material_override = mat_neon[0]
		add_child(seg)

	# Four pillars at cardinal points
	for i in range(4):
		var angle := i * TAU / 4.0
		var pillar := MeshInstance3D.new()
		var pbox := BoxMesh.new()
		pbox.size = Vector3(2, 12, 2)
		pillar.mesh = pbox
		pillar.position = Vector3(
			cos(angle) * (arena_radius + 3),
			6,
			sin(angle) * (arena_radius + 3)
		)
		pillar.material_override = mat_metal
		add_child(pillar)

		var pillar_body := StaticBody3D.new()
		pillar_body.position = pillar.position
		var pillar_col := CollisionShape3D.new()
		var pillar_shape := BoxShape3D.new()
		pillar_shape.size = pbox.size
		pillar_col.shape = pillar_shape
		pillar_body.add_child(pillar_col)
		add_child(pillar_body)

		# Neon strip on pillar
		var neon_strip := MeshInstance3D.new()
		var nbox := BoxMesh.new()
		nbox.size = Vector3(0.1, 12, 0.1)
		neon_strip.mesh = nbox
		neon_strip.position = pillar.position + Vector3(1.05, 0, 0)
		neon_strip.material_override = mat_neon[i % mat_neon.size()]
		add_child(neon_strip)


# === GREAT WALL (perimeter) ===

func _create_great_wall() -> void:
	var span := city_size * block_size + 20.0
	var wall_height := 40.0
	var wall_thickness := 4.0

	for axis in range(2):  # 0 = X walls, 1 = Z walls
		for side in range(-1, 2, 2):
			var wall := MeshInstance3D.new()
			var wbox := BoxMesh.new()
			if axis == 0:
				wbox.size = Vector3(span * 2.0 + wall_thickness * 2, wall_height, wall_thickness)
				wall.position = Vector3(0, wall_height * 0.5, side * span)
			else:
				wbox.size = Vector3(wall_thickness, wall_height, span * 2.0 + wall_thickness * 2)
				wall.position = Vector3(side * span, wall_height * 0.5, 0)
			wall.mesh = wbox
			wall.material_override = mat_wall
			add_child(wall)

			var body := StaticBody3D.new()
			body.position = wall.position
			var col := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = wbox.size
			col.shape = shape
			body.add_child(col)
			add_child(body)

			# Neon strip along the top
			var neon := MeshInstance3D.new()
			var nbox := BoxMesh.new()
			if axis == 0:
				nbox.size = Vector3(span * 2.0, 0.2, 0.2)
				neon.position = Vector3(0, wall_height, side * span)
			else:
				nbox.size = Vector3(0.2, 0.2, span * 2.0)
				neon.position = Vector3(side * span, wall_height, 0)
			neon.mesh = nbox
			neon.material_override = mat_neon[1]
			add_child(neon)


# === NEON SIGNAGE ===

func _create_neon_signage() -> void:
	var span := city_size * block_size
	var districts := [
		{"pos": Vector3(0, 25, -span * 0.8), "text": "DOWNTOWN"},
		{"pos": Vector3(-span * 0.7, 20, 0), "text": "SECTOR 7"},
		{"pos": Vector3(span * 0.7, 20, 0), "text": "INDUSTRIAL"},
		{"pos": Vector3(0, 18, span * 0.8), "text": "RESIDENTIAL"},
	]

	for i in range(districts.size()):
		var sign_root := _make_neon_sign(districts[i]["text"], mat_neon[i % mat_neon.size()])
		sign_root.position = districts[i]["pos"]
		add_child(sign_root)

	for b in building_data:
		if randf() < 0.15:
			var sign_root := _make_neon_sign(SIGN_WORDS.pick_random(), mat_neon.pick_random())
			sign_root.position = Vector3(
				b["position"].x + randf_range(-b["width"] * 0.4, b["width"] * 0.4),
				b["roof_y"] + randf_range(2, 8),
				b["position"].z + randf_range(-b["depth"] * 0.4, b["depth"] * 0.4)
			)
			add_child(sign_root)


func _make_neon_sign(text: String, mat: StandardMaterial3D) -> Node3D:
	var root := Node3D.new()
	var char_w := 1.2
	var total_w := text.length() * char_w

	for i in range(text.length()):
		var c := MeshInstance3D.new()
		var cbox := BoxMesh.new()
		cbox.size = Vector3(char_w * 0.8, 1.5, 0.1)
		c.mesh = cbox
		c.position = Vector3((i - text.length() * 0.5 + 0.5) * char_w, 0, 0)
		c.material_override = mat
		root.add_child(c)

	var back := MeshInstance3D.new()
	var bbox := BoxMesh.new()
	bbox.size = Vector3(total_w + 1.0, 2.2, 0.3)
	back.mesh = bbox
	back.position = Vector3(0, 0, -0.2)
	back.material_override = mat_concrete_dark
	root.add_child(back)

	return root


# === PARKOUR ELEMENTS ===

func _create_parkour_elements() -> void:
	for b in building_data:
		if b["height"] > 20 and randf() < 0.3:
			var nearest: Dictionary = {}
			var nearest_dist := 60.0
			for other in building_data:
				if other == b or other["height"] < 15:
					continue
				var dist: float = b["position"].distance_to(other["position"])
				if dist < nearest_dist:
					nearest_dist = dist
					nearest = other
			if not nearest.is_empty():
				_connect_with_pipe(b, nearest)

	for i in range(15):
		var b1: Dictionary = building_data.pick_random()
		var b2: Dictionary = building_data.pick_random()
		if b1 == b2:
			continue
		if b1["position"].distance_to(b2["position"]) < 40.0:
			continue
		_create_zip_line(b1, b2)

	for i in range(5):
		_create_crane()

	for i in range(8):
		_create_billboard()

	for i in range(15):
		_create_vent_shaft()


func _connect_with_pipe(b1: Dictionary, b2: Dictionary) -> void:
	var mid: Vector3 = (b1["position"] + b2["position"]) * 0.5
	var height: float = maxf(b1["roof_y"], b2["roof_y"]) + randf_range(2, 6)
	var flat_delta := Vector2(b2["position"].x - b1["position"].x, b2["position"].z - b1["position"].z)
	if flat_delta.length() < 1.0:
		return
	var flat_dist := flat_delta.length()

	var pipe := MeshInstance3D.new()
	var pbox := BoxMesh.new()
	pbox.size = Vector3(0.6, 0.6, flat_dist)
	pipe.mesh = pbox
	pipe.top_level = true
	pipe.look_at_from_position(Vector3(mid.x, height, mid.z),
			Vector3(b2["position"].x, height, b2["position"].z), Vector3.UP)
	pipe.material_override = mat_metal_rusted
	add_child(pipe)

	for t in [0.0, 0.5, 1.0]:
		var anchor: Vector3 = b1["position"].lerp(b2["position"], t)
		var sup := MeshInstance3D.new()
		var sbox := BoxMesh.new()
		sbox.size = Vector3(0.4, height, 0.4)
		sup.mesh = sbox
		sup.top_level = true
		sup.position = Vector3(anchor.x, height * 0.5, anchor.z)
		sup.material_override = mat_metal_rusted
		add_child(sup)


func _create_zip_line(b1: Dictionary, b2: Dictionary) -> void:
	var line := MeshInstance3D.new()
	var lmesh := ImmediateMesh.new()
	var lmat := StandardMaterial3D.new()
	lmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lmat.albedo_color = Color(0.0, 0.6, 1.0)
	lmat.emission_enabled = true
	lmat.emission = Color(0.0, 0.6, 1.0) * 1.5
	line.mesh = lmesh
	line.top_level = true
	lmesh.surface_begin(Mesh.PRIMITIVE_LINES, lmat)
	lmesh.surface_add_vertex(Vector3(b1["position"].x, b1["roof_y"] + 0.5, b1["position"].z))
	lmesh.surface_add_vertex(Vector3(b2["position"].x, b2["roof_y"] + 0.5, b2["position"].z))
	lmesh.surface_end()
	add_child(line)


func _create_crane() -> void:
	var x := randf_range(-city_size * block_size * 0.8, city_size * block_size * 0.8)
	var z := randf_range(-city_size * block_size * 0.8, city_size * block_size * 0.8)
	var h := randf_range(25, 45)
	var arm_len := randf_range(15, 25)

	var root := Node3D.new()
	root.position = Vector3(x, 0, z)

	var base := MeshInstance3D.new()
	var bbox := BoxMesh.new()
	bbox.size = Vector3(6, 4, 6)
	base.mesh = bbox
	base.position = Vector3(0, 2, 0)
	base.material_override = mat_metal_rusted
	root.add_child(base)

	var tower := MeshInstance3D.new()
	var tbox := BoxMesh.new()
	tbox.size = Vector3(1.5, h, 1.5)
	tower.mesh = tbox
	tower.position = Vector3(0, h * 0.5 + 2, 0)
	tower.material_override = mat_metal_rusted
	root.add_child(tower)

	var arm_pivot := Node3D.new()
	arm_pivot.position = Vector3(0, h + 2.6, 0)
	arm_pivot.rotation_degrees.y = randf_range(0, 360)
	root.add_child(arm_pivot)

	var arm := MeshInstance3D.new()
	var abox := BoxMesh.new()
	abox.size = Vector3(arm_len, 1.2, 1.2)
	arm.mesh = abox
	arm.position = Vector3(arm_len * 0.5, 0, 0)
	arm.material_override = mat_metal_rusted
	arm_pivot.add_child(arm)

	var cw := MeshInstance3D.new()
	var cbox := BoxMesh.new()
	cbox.size = Vector3(3, 2, 3)
	cw.mesh = cbox
	cw.position = Vector3(-arm_len * 0.4, 0, 0)
	cw.material_override = mat_concrete_dark
	arm_pivot.add_child(cw)

	var cable := MeshInstance3D.new()
	var clmesh := ImmediateMesh.new()
	var clmat := StandardMaterial3D.new()
	clmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	clmat.albedo_color = Color(0.15, 0.15, 0.18)
	cable.mesh = clmesh
	clmesh.surface_begin(Mesh.PRIMITIVE_LINES, clmat)
	clmesh.surface_add_vertex(Vector3(arm_len * 0.5, -0.6, 0))
	clmesh.surface_add_vertex(Vector3(arm_len * 0.5, -h - 2.0, 0))
	clmesh.surface_end()
	arm_pivot.add_child(cable)

	var body := StaticBody3D.new()
	body.position = root.position + Vector3(0, 2, 0)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(6, 4, 6)
	col.shape = shape
	body.add_child(col)
	add_child(body)

	add_child(root)


func _create_billboard() -> void:
	var x := randf_range(-city_size * block_size * 0.9, city_size * block_size * 0.9)
	var z := randf_range(-city_size * block_size * 0.9, city_size * block_size * 0.9)
	var h := randf_range(12, 20)

	var root := Node3D.new()
	root.position = Vector3(x, 0, z)
	root.rotation_degrees.y = randf_range(0, 360)

	var pole := MeshInstance3D.new()
	var pbox := BoxMesh.new()
	pbox.size = Vector3(0.8, h, 0.8)
	pole.mesh = pbox
	pole.position = Vector3(0, h * 0.5, 0)
	pole.material_override = mat_metal_rusted
	root.add_child(pole)

	var board := MeshInstance3D.new()
	var bbox := BoxMesh.new()
	bbox.size = Vector3(10, 6, 0.2)
	board.mesh = bbox
	board.position = Vector3(0, h + 3, 0)
	board.material_override = mat_concrete_dark
	root.add_child(board)

	var border_mat: StandardMaterial3D = mat_neon.pick_random()
	for edge_idx in range(4):
		var edge := MeshInstance3D.new()
		var ebox := BoxMesh.new()
		if edge_idx < 2:
			ebox.size = Vector3(10.2, 0.15, 0.2)
			edge.position = Vector3(0, h + 3.0 + (3.1 if edge_idx == 0 else -3.1), 0.1)
		else:
			ebox.size = Vector3(0.15, 6.2, 0.2)
			edge.position = Vector3(5.1 if edge_idx == 2 else -5.1, h + 3, 0.1)
		edge.mesh = ebox
		edge.material_override = border_mat
		root.add_child(edge)

	var ad_mat: StandardMaterial3D = mat_neon.pick_random().duplicate()
	ad_mat.emission_energy_multiplier = 2.0
	var ad := MeshInstance3D.new()
	var admesh := ImmediateMesh.new()
	ad.mesh = admesh
	admesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, ad_mat)
	for p in range(8):
		var px := randf_range(-4.5, 4.5)
		var py := randf_range(-2.5, 2.5)
		var ps := randf_range(0.4, 0.9)
		admesh.surface_add_vertex(Vector3(px, py + ps, 0.15))
		admesh.surface_add_vertex(Vector3(px - ps, py - ps, 0.15))
		admesh.surface_add_vertex(Vector3(px + ps, py - ps, 0.15))
	admesh.surface_end()
	ad.position = Vector3(0, h + 3, 0)
	root.add_child(ad)

	var body := StaticBody3D.new()
	body.position = root.position + Vector3(0, (h + 6.0) * 0.5, 0)
	body.rotation_degrees.y = root.rotation_degrees.y
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(10, h + 6.0, 1.0)
	col.shape = shape
	body.add_child(col)
	add_child(body)

	add_child(root)


func _create_vent_shaft() -> void:
	var x := randf_range(-city_size * block_size * 0.95, city_size * block_size * 0.95)
	var z := randf_range(-city_size * block_size * 0.95, city_size * block_size * 0.95)
	var h := randf_range(3, 8)

	var vent := MeshInstance3D.new()
	var vbox := BoxMesh.new()
	vbox.size = Vector3(2.5, h, 2.5)
	vent.mesh = vbox
	vent.position = Vector3(x, h * 0.5, z)
	vent.material_override = mat_metal_rusted
	add_child(vent)

	var grate := MeshInstance3D.new()
	var gbox := BoxMesh.new()
	gbox.size = Vector3(2.7, 0.2, 2.7)
	grate.mesh = gbox
	grate.position = Vector3(x, h + 0.1, z)
	grate.material_override = mat_metal
	add_child(grate)

	var body := StaticBody3D.new()
	body.position = Vector3(x, h * 0.5, z)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.5, h, 2.5)
	col.shape = shape
	body.add_child(col)
	add_child(body)


# === ATMOSPHERE ===

func _create_atmosphere() -> void:
	var span := city_size * block_size
	for i in range(30):
		var fog := MeshInstance3D.new()
		var fbox := BoxMesh.new()
		var fs := randf_range(8, 20)
		fbox.size = Vector3(fs, 0.5, fs)
		fog.mesh = fbox
		fog.position = Vector3(
			randf_range(-span, span),
			randf_range(0.5, 3),
			randf_range(-span, span)
		)
		var fmat := StandardMaterial3D.new()
		fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		fmat.albedo_color = Color(0.15, 0.14, 0.18, 0.12)
		fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fog.material_override = fmat
		fog.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(fog)

		var drift := fog.create_tween()
		drift.set_loops()
		drift.tween_property(fog, "position:x", fog.position.x + randf_range(-10, 10), randf_range(20, 40)) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		drift.tween_property(fog, "position:x", fog.position.x, randf_range(20, 40)) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


# === SPAWNING ===

func _spawn_player() -> void:
	if multiplayer.multiplayer_peer != null and not multiplayer.is_server():
		return

	var spawn_pos := Vector3(0, 5, 0)
	if not spawn_positions.is_empty():
		spawn_pos = spawn_positions.pick_random()

	var player_scene := preload("res://player/player.tscn")
	var player := player_scene.instantiate()
	player.name = "Player"
	add_child(player)
	player.global_position = spawn_pos

	var peer_id := multiplayer.get_unique_id() if multiplayer.multiplayer_peer != null else 1
	player.set_multiplayer_authority(peer_id)
	player.name = str(peer_id)

	Globals.local_player = player
	Globals.register_player(peer_id, player)

	var lobby_ui_scene := preload("res://ui/lobby_ui.tscn")
	add_child(lobby_ui_scene.instantiate())

	var hud_scene := preload("res://ui/hud.tscn")
	add_child(hud_scene.instantiate())


func _spawn_enemies() -> void:
	if multiplayer.multiplayer_peer != null and not multiplayer.is_server():
		return

	var enemy_count: int = Globals.config.get("enemy_count", 24)
	if enemy_count <= 0 or building_data.is_empty():
		return

	var enemy_scene := preload("res://enemies/enemy.tscn")

	for i in range(enemy_count):
		var enemy := enemy_scene.instantiate()

		var roll := randf()
		if roll < 0.55:
			enemy.enemy_type = 0
		elif roll < 0.75:
			enemy.enemy_type = 1
		elif roll < 0.93:
			enemy.enemy_type = 2
		else:
			enemy.enemy_type = 3

		# Spawn enemies away from the player start (0,0,0) — minimum 80 units out
		# (sniper detection_range=60, attack_range=40 — need big buffer)
		var min_spawn_dist := 80.0
		var pos := Vector3.ZERO
		for _attempt in range(20):
			if i % 2 == 0 and not spawn_positions.is_empty():
				pos = spawn_positions.pick_random() + Vector3(randf_range(-2, 2), 1, randf_range(-2, 2))
			elif not building_data.is_empty():
				var b: Dictionary = building_data.pick_random()
				pos = Vector3(
					b["position"].x + randf_range(-b["width"], b["width"]) * 0.6,
					1.5,
					b["position"].z + randf_range(-b["depth"], b["depth"]) * 0.6
				)
			else:
				var angle := randf() * TAU
				var dist := randf_range(min_spawn_dist, min_spawn_dist + 40.0)
				pos = Vector3(cos(angle) * dist, 1.5, sin(angle) * dist)
			if pos.length() >= min_spawn_dist:
				break
		enemy.position = pos
		add_child(enemy)
		Globals.register_enemy(enemy)
