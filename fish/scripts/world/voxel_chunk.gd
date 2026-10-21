class_name VoxelChunk
extends StaticBody3D

const SIZE := 16

var voxel_size: float = 1.0
var chunk_coord: Vector3i
var world: Node

var _voxels: PackedByteArray
var _mesh_instance: MeshInstance3D
var _collision_shape: CollisionShape3D
var _dirty := true

static var _materials: Dictionary = {}


func _init() -> void:
	_voxels = PackedByteArray()
	_voxels.resize(SIZE * SIZE * SIZE)


func _ready() -> void:
	if _materials.is_empty():
		_materials = VoxelTypes.build_materials()
	_mesh_instance = MeshInstance3D.new()
	add_child(_mesh_instance)


static func local_index(x: int, y: int, z: int) -> int:
	return x + y * SIZE + z * SIZE * SIZE


func get_voxel_local(x: int, y: int, z: int) -> int:
	if x < 0 or y < 0 or z < 0 or x >= SIZE or y >= SIZE or z >= SIZE:
		return VoxelTypes.Type.AIR
	return _voxels[local_index(x, y, z)]


func set_voxel_local(x: int, y: int, z: int, type: int) -> void:
	if x < 0 or y < 0 or z < 0 or x >= SIZE or y >= SIZE or z >= SIZE:
		return
	_voxels[local_index(x, y, z)] = type
	_dirty = true


func mark_dirty() -> void:
	_dirty = true


func is_dirty() -> bool:
	return _dirty


# --- Greedy Meshing ---
#
# Sweeps along each of the 3 axes. For each slice perpendicular to the
# sweep axis, builds a 2D mask of (voxel_type, face_direction) pairs,
# then greedily merges adjacent identical entries into maximal rectangles.
# Each rectangle becomes one quad instead of one-quad-per-face, giving
# a large triangle reduction (typically 4-8x fewer triangles).
#
# Face direction is encoded in the mask value: positive type = front face
# (solid is in the -d direction), negative type = back face (solid is in
# the +d direction). Two mask entries merge only if both type and
# direction match.

func rebuild_mesh(neighbor_sampler: Callable = Callable()) -> void:
	if _mesh_instance == null:
		return

	var surfaces := {}  # type -> SurfaceTool

	for axis in range(3):
		# fast_ax is the mask row axis (ui, inner loop), slow_ax the column
		# axis (vj, outer loop). These are the concrete world axes du/dv are
		# measured along; they only equal {X,Y,Z} +1 modulo for axis 0.
		var fast_ax := 0
		var slow_ax := 0
		if axis == 0:
			fast_ax = 1  # ui -> Y
			slow_ax = 2  # vj -> Z
		elif axis == 1:
			fast_ax = 0  # ui -> X
			slow_ax = 2  # vj -> Z
		else:
			fast_ax = 0  # ui -> X
			slow_ax = 1  # vj -> Y

		var mask := []
		mask.resize(SIZE * SIZE)

		for d in range(-1, SIZE):
			# Build face mask for this slice
			var n := 0
			for vj in range(SIZE):
				for ui in range(SIZE):
					var px := 0
					var py := 0
					var pz := 0
					if axis == 0:
						px = d
						py = ui
						pz = vj
					elif axis == 1:
						px = ui
						py = d
						pz = vj
					else:
						px = ui
						py = vj
						pz = d

					var left_type: int
					var right_type: int

					if d >= 0:
						left_type = get_voxel_local(px, py, pz)
					else:
						left_type = _sample_border(px, py, pz, neighbor_sampler)

					var qx := 0
					var qy := 0
					var qz := 0
					if axis == 0:
						qx = d + 1
						qy = ui
						qz = vj
					elif axis == 1:
						qx = ui
						qy = d + 1
						qz = vj
					else:
						qx = ui
						qy = vj
						qz = d + 1

					if d < SIZE - 1:
						right_type = get_voxel_local(qx, qy, qz)
					else:
						right_type = _sample_border(qx, qy, qz, neighbor_sampler)

					var left_solid := VoxelTypes.is_solid(left_type)
					var right_solid := VoxelTypes.is_solid(right_type)

					if left_solid and not right_solid:
						mask[n] = left_type
					elif not left_solid and right_solid:
						mask[n] = -right_type
					else:
						mask[n] = 0

					n += 1

			# Greedy merge pass
			n = 0
			for j in range(SIZE):
				var i := 0
				while i < SIZE:
					var c: int = mask[n]
					if c == 0:
						n += 1
						i += 1
						continue

					var width := 1
					while i + width < SIZE and mask[n + width] == c:
						width += 1

					var height := 1
					var done := false
					while j + height < SIZE and not done:
						for k in range(width):
							if mask[n + k + height * SIZE] != c:
								done = true
								break
						if not done:
							height += 1

					var voxel_type: int
					var is_front: bool
					if c > 0:
						voxel_type = c
						is_front = true
					else:
						voxel_type = -c
						is_front = false

					var quad_x := 0
					var quad_y := 0
					var quad_z := 0
					if axis == 0:
						quad_x = d + 1
						quad_y = i
						quad_z = j
					elif axis == 1:
						quad_x = i
						quad_y = d + 1
						quad_z = j
					else:
						quad_x = i
						quad_y = j
						quad_z = d + 1

					var du := [0, 0, 0]
					du[fast_ax] = width
					var dv := [0, 0, 0]
					dv[slow_ax] = height

					_emit_greedy_quad(surfaces, voxel_type,
						Vector3i(quad_x, quad_y, quad_z),
						Vector3i(du[0], du[1], du[2]),
						Vector3i(dv[0], dv[1], dv[2]),
						axis, is_front)

					for l in range(height):
						for k in range(width):
							mask[n + k + l * SIZE] = 0

					i += width
					n += width

	var mesh := ArrayMesh.new()
	for type in surfaces:
		var st: SurfaceTool = surfaces[type]
		st.index()
		var arr := st.commit_to_arrays()
		if arr.is_empty():
			continue
		var mat: Material = _materials.get(type)
		if mat == null:
			continue
		var surf_idx := mesh.get_surface_count()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mesh.surface_set_material(surf_idx, mat)

	_mesh_instance.mesh = mesh
	_rebuild_collision(mesh)
	_dirty = false


func _sample_border(wx: int, wy: int, wz: int, sampler: Callable) -> int:
	if sampler.is_valid():
		var world_x := chunk_coord.x * SIZE + wx
		var world_y := chunk_coord.y * SIZE + wy
		var world_z := chunk_coord.z * SIZE + wz
		return sampler.call(world_x, world_y, world_z)
	return VoxelTypes.Type.AIR


func _emit_greedy_quad(surfaces: Dictionary, voxel_type: int,
		pos: Vector3i, du: Vector3i, dv: Vector3i, axis: int, is_front: bool) -> void:
	if not surfaces.has(voxel_type):
		var new_st := SurfaceTool.new()
		new_st.begin(Mesh.PRIMITIVE_TRIANGLES)
		surfaces[voxel_type] = new_st
	var st: SurfaceTool = surfaces[voxel_type]

	var vs := voxel_size
	var v0 := Vector3(pos) * vs
	var v1 := v0 + Vector3(du) * vs
	var v2 := v0 + Vector3(du + dv) * vs
	var v3 := v0 + Vector3(dv) * vs

	# Per-face winding. The four corners of the merged quad are reordered
	# to match the (proven) per-direction corner order from the original
	# mesher, so geometric normals stay consistent with the face direction
	# even though one quad now spans many voxels. Without this, half the
	# faces have inverted winding and render flat/pitch-black.
	var order: PackedInt32Array
	match [axis, is_front]:
		[0, true]:  order = PackedInt32Array([0, 1, 2, 3])
		[0, false]: order = PackedInt32Array([3, 2, 1, 0])
		[1, true]:  order = PackedInt32Array([0, 3, 2, 1])
		[1, false]: order = PackedInt32Array([3, 0, 1, 2])
		[2, true]:  order = PackedInt32Array([1, 2, 3, 0])
		[2, false]: order = PackedInt32Array([0, 3, 2, 1])
		_:          order = PackedInt32Array([0, 1, 2, 3])
	var corners: Array = [v0, v1, v2, v3]
	var c0: Vector3 = corners[order[0]]
	var c1: Vector3 = corners[order[1]]
	var c2: Vector3 = corners[order[2]]
	var c3: Vector3 = corners[order[3]]

	var normal := Vector3.ZERO
	normal[axis] = 1.0 if is_front else -1.0

	st.set_normal(normal)
	st.add_vertex(c0)
	st.set_normal(normal)
	st.add_vertex(c2)
	st.set_normal(normal)
	st.add_vertex(c1)

	st.set_normal(normal)
	st.add_vertex(c0)
	st.set_normal(normal)
	st.add_vertex(c3)
	st.set_normal(normal)
	st.add_vertex(c2)


func _rebuild_collision(mesh: ArrayMesh) -> void:
	var shape: ConcavePolygonShape3D = null
	if mesh.get_surface_count() > 0:
		shape = mesh.create_trimesh_shape()
		shape.backface_collision = true

	if _collision_shape == null:
		_collision_shape = CollisionShape3D.new()
		add_child(_collision_shape)
	_collision_shape.shape = shape
