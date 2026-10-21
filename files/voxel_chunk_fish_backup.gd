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
static var _faces: Array = []


func _init() -> void:
	_voxels = PackedByteArray()
	_voxels.resize(SIZE * SIZE * SIZE)


func _ready() -> void:
	if _materials.is_empty():
		_materials = VoxelTypes.build_materials()
	if _faces.is_empty():
		_build_faces()
	_mesh_instance = MeshInstance3D.new()
	add_child(_mesh_instance)
	# No eager rebuild: chunks are born empty during world generation and
	# marked dirty on first write; VoxelWorld batches those rebuilds.


static func _build_faces() -> void:
	_faces = [
		{"dir": Vector3i(1, 0, 0), "n": Vector3(1, 0, 0), "corners": [Vector3(1,0,0),Vector3(1,1,0),Vector3(1,1,1),Vector3(1,0,1)]},
		{"dir": Vector3i(-1, 0, 0), "n": Vector3(-1, 0, 0), "corners": [Vector3(0,0,1),Vector3(0,1,1),Vector3(0,1,0),Vector3(0,0,0)]},
		{"dir": Vector3i(0, 1, 0), "n": Vector3(0, 1, 0), "corners": [Vector3(0,1,0),Vector3(0,1,1),Vector3(1,1,1),Vector3(1,1,0)]},
		{"dir": Vector3i(0, -1, 0), "n": Vector3(0, -1, 0), "corners": [Vector3(0,0,1),Vector3(0,0,0),Vector3(1,0,0),Vector3(1,0,1)]},
		{"dir": Vector3i(0, 0, 1), "n": Vector3(0, 0, 1), "corners": [Vector3(1,0,1),Vector3(1,1,1),Vector3(0,1,1),Vector3(0,0,1)]},
		{"dir": Vector3i(0, 0, -1), "n": Vector3(0, 0, -1), "corners": [Vector3(0,0,0),Vector3(0,1,0),Vector3(1,1,0),Vector3(1,0,0)]},
	]


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


func rebuild_mesh(neighbor_sampler: Callable = Callable()) -> void:
	if _mesh_instance == null:
		return

	var surfaces := {}

	for x in range(SIZE):
		for y in range(SIZE):
			for z in range(SIZE):
				var type := get_voxel_local(x, y, z)
				if not VoxelTypes.is_solid(type):
					continue
				_emit_voxel_faces(surfaces, x, y, z, type, neighbor_sampler)

	var mesh := ArrayMesh.new()
	for type in surfaces:
		var st: SurfaceTool = surfaces[type]
		st.index()
		# NOTE: no generate_normals() here -- per-vertex normals are already
		# set explicitly to the face direction during emission, and
		# generate_normals() would recompute them from winding order.
		var arr_mesh := st.commit()
		if arr_mesh == null or arr_mesh.get_surface_count() == 0:
			continue
		var mat: Material = _materials.get(type)
		if mat == null:
			continue
		var surf_idx := mesh.get_surface_count()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr_mesh.surface_get_arrays(0))
		mesh.surface_set_material(surf_idx, mat)

	_mesh_instance.mesh = mesh
	_rebuild_collision(mesh)
	_dirty = false


func _emit_voxel_faces(surfaces: Dictionary, x: int, y: int, z: int, type: int, sampler: Callable) -> void:
	if not surfaces.has(type):
		var new_st := SurfaceTool.new()
		new_st.begin(Mesh.PRIMITIVE_TRIANGLES)
		surfaces[type] = new_st
	var st: SurfaceTool = surfaces[type]

	var vs := voxel_size
	var base := Vector3(x, y, z) * vs

	for f: Dictionary in _faces:
		var d: Vector3i = f["dir"]
		var neighbor_type: int
		var nx := x + d.x
		var ny := y + d.y
		var nz := z + d.z
		if nx < 0 or ny < 0 or nz < 0 or nx >= SIZE or ny >= SIZE or nz >= SIZE:
			if sampler.is_valid():
				var wx := chunk_coord.x * SIZE + nx
				var wy := chunk_coord.y * SIZE + ny
				var wz := chunk_coord.z * SIZE + nz
				neighbor_type = sampler.call(wx, wy, wz)
			else:
				neighbor_type = VoxelTypes.Type.AIR
		else:
			neighbor_type = get_voxel_local(nx, ny, nz)

		if VoxelTypes.is_solid(neighbor_type):
			continue

		var corners: Array = f["corners"]
		var n: Vector3 = f["n"]

		# Godot front faces use CLOCKWISE winding viewed from outside.
		# Emit (p0, p2, p1) / (p0, p3, p2) -- the reverse of array order --
		# so walls are visible and collidable from outside the building.
		st.set_normal(n)
		st.add_vertex(base + corners[0] * vs)
		st.set_normal(n)
		st.add_vertex(base + corners[2] * vs)
		st.set_normal(n)
		st.add_vertex(base + corners[1] * vs)

		st.set_normal(n)
		st.add_vertex(base + corners[0] * vs)
		st.set_normal(n)
		st.add_vertex(base + corners[3] * vs)
		st.set_normal(n)
		st.add_vertex(base + corners[2] * vs)


func _rebuild_collision(mesh: ArrayMesh) -> void:
	var shape: ConcavePolygonShape3D = null
	if mesh.get_surface_count() > 0:
		shape = mesh.create_trimesh_shape()
		# Jolt trimeshes collide front-faces only by default; enable
		# backface collision so destruction holes and any edge cases
		# still block the player instead of letting them clip inside.
		shape.backface_collision = true

	if _collision_shape == null:
		_collision_shape = CollisionShape3D.new()
		add_child(_collision_shape)
	_collision_shape.shape = shape
