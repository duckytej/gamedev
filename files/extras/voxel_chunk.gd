class_name VoxelChunk
extends StaticBody3D

# One chunk of voxel data. Owns its own mesh + collision.
# Never talk to a chunk's neighbors directly -- go through VoxelWorld,
# which owns cross-chunk lookups. This keeps a chunk fully self-contained
# and safe to rebuild/thread in isolation later.

const SIZE := 16  # voxels per axis, per chunk

var voxel_size: float = 1.0
var chunk_coord: Vector3i
var world: Node  # back-reference to VoxelWorld, set by owner

var _voxels: PackedByteArray
var _mesh_instance: MeshInstance3D
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
	if _dirty:
		rebuild_mesh()


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


# Rebuilds mesh + collision from current voxel data.
# `neighbor_sampler` is a Callable(world_x, world_y, world_z) -> int,
# supplied by VoxelWorld so faces at chunk borders cull correctly
# against the ADJACENT chunk instead of always drawing.
func rebuild_mesh(neighbor_sampler: Callable = Callable()) -> void:
	if _mesh_instance == null:
		return  # not ready yet; _ready() will call this once it is

	var surfaces := {}  # type -> SurfaceTool
	var origin_world := Vector3(chunk_coord) * SIZE * voxel_size

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
		st.generate_normals()
		var arr_mesh := st.commit()
		var mat: Material = _materials.get(type)
		var surf_idx := mesh.get_surface_count()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr_mesh.surface_get_arrays(0))
		mesh.surface_set_material(surf_idx, mat)

	_mesh_instance.mesh = mesh
	_mesh_instance.position = Vector3.ZERO  # chunk node itself is positioned in world

	_rebuild_collision(mesh)
	_dirty = false


func _emit_voxel_faces(surfaces: Dictionary, x: int, y: int, z: int, type: int, sampler: Callable) -> void:
	if not surfaces.has(type):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		surfaces[type] = st
	var st: SurfaceTool = surfaces[type]

	var vs := voxel_size
	var base := Vector3(x, y, z) * vs

	# 6 face directions: offset, normal, and the 4 corner offsets (CCW when viewed from outside)
	var faces := [
		{"dir": Vector3i(1, 0, 0), "n": Vector3(1, 0, 0), "corners": [Vector3(1,0,0),Vector3(1,1,0),Vector3(1,1,1),Vector3(1,0,1)]},
		{"dir": Vector3i(-1, 0, 0), "n": Vector3(-1, 0, 0), "corners": [Vector3(0,0,1),Vector3(0,1,1),Vector3(0,1,0),Vector3(0,0,0)]},
		{"dir": Vector3i(0, 1, 0), "n": Vector3(0, 1, 0), "corners": [Vector3(0,1,0),Vector3(0,1,1),Vector3(1,1,1),Vector3(1,1,0)]},
		{"dir": Vector3i(0, -1, 0), "n": Vector3(0, -1, 0), "corners": [Vector3(0,0,1),Vector3(0,0,0),Vector3(1,0,0),Vector3(1,0,1)]},
		{"dir": Vector3i(0, 0, 1), "n": Vector3(0, 0, 1), "corners": [Vector3(1,0,1),Vector3(1,1,1),Vector3(0,1,1),Vector3(0,0,1)]},
		{"dir": Vector3i(0, 0, -1), "n": Vector3(0, 0, -1), "corners": [Vector3(0,0,0),Vector3(0,1,0),Vector3(1,1,0),Vector3(1,0,0)]},
	]

	for f in faces:
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
			continue  # face is hidden, cull it

		var corners: Array = f["corners"]
		var p0 := base + corners[0] * vs
		var p1 := base + corners[1] * vs
		var p2 := base + corners[2] * vs
		var p3 := base + corners[3] * vs

		st.set_normal(f["n"])
		st.add_vertex(p0)
		st.set_normal(f["n"])
		st.add_vertex(p1)
		st.set_normal(f["n"])
		st.add_vertex(p2)

		st.set_normal(f["n"])
		st.add_vertex(p0)
		st.set_normal(f["n"])
		st.add_vertex(p2)
		st.set_normal(f["n"])
		st.add_vertex(p3)


func _rebuild_collision(mesh: ArrayMesh) -> void:
	for child in get_children():
		if child is CollisionShape3D:
			child.queue_free()
	if mesh.get_surface_count() == 0:
		return
	var shape := mesh.create_trimesh_shape()
	if shape == null:
		return
	var col := CollisionShape3D.new()
	col.shape = shape
	add_child(col)
