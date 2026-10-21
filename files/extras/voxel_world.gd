class_name VoxelWorld
extends Node3D

# Owns all chunks. This is the ONLY object that should be doing
# cross-chunk coordinate math -- chunks themselves stay dumb and local.
#
# Usage:
#   voxel_world.set_voxel(world_pos, VoxelTypes.Type.CONCRETE)
#   voxel_world.remove_voxel(world_pos)          # destruction entry point
#   voxel_world.get_voxel(world_pos)
#
# Rebuilds are batched: chunks mark themselves dirty and get flushed
# once per frame in _process, not per-voxel. This matters a lot once
# combat starts blowing multiple voxels out per hit.

@export var voxel_size: float = 1.0
@export var chunk_scene_root_name := "chunks"

var _chunks: Dictionary = {}  # Vector3i chunk_coord -> VoxelChunk
var _dirty_chunks: Dictionary = {}  # Vector3i -> true


func _process(_delta: float) -> void:
	if _dirty_chunks.is_empty():
		return
	for coord in _dirty_chunks.keys():
		var chunk: VoxelChunk = _chunks.get(coord)
		if chunk != null:
			chunk.rebuild_mesh(Callable(self, "_sample_world_voxel"))
	_dirty_chunks.clear()


func world_to_voxel(world_pos: Vector3) -> Vector3i:
	return Vector3i(
		floori(world_pos.x / voxel_size),
		floori(world_pos.y / voxel_size),
		floori(world_pos.z / voxel_size)
	)


func voxel_to_chunk_coord(vx: int, vy: int, vz: int) -> Vector3i:
	return Vector3i(
		floori(float(vx) / VoxelChunk.SIZE),
		floori(float(vy) / VoxelChunk.SIZE),
		floori(float(vz) / VoxelChunk.SIZE)
	)


func _get_or_create_chunk(coord: Vector3i) -> VoxelChunk:
	if _chunks.has(coord):
		return _chunks[coord]
	var chunk := VoxelChunk.new()
	chunk.chunk_coord = coord
	chunk.voxel_size = voxel_size
	chunk.world = self
	chunk.position = Vector3(coord) * VoxelChunk.SIZE * voxel_size
	add_child(chunk)
	_chunks[coord] = chunk
	return chunk


func get_voxel(world_pos: Vector3) -> int:
	var v := world_to_voxel(world_pos)
	return _sample_world_voxel(v.x, v.y, v.z)


func _sample_world_voxel(vx: int, vy: int, vz: int) -> int:
	var cc := voxel_to_chunk_coord(vx, vy, vz)
	if not _chunks.has(cc):
		return VoxelTypes.Type.AIR
	var chunk: VoxelChunk = _chunks[cc]
	var lx := vx - cc.x * VoxelChunk.SIZE
	var ly := vy - cc.y * VoxelChunk.SIZE
	var lz := vz - cc.z * VoxelChunk.SIZE
	return chunk.get_voxel_local(lx, ly, lz)


func set_voxel(world_pos: Vector3, type: int) -> void:
	var v := world_to_voxel(world_pos)
	set_voxel_at(v.x, v.y, v.z, type)


func set_voxel_at(vx: int, vy: int, vz: int, type: int) -> void:
	var cc := voxel_to_chunk_coord(vx, vy, vz)
	var chunk := _get_or_create_chunk(cc)
	var lx := vx - cc.x * VoxelChunk.SIZE
	var ly := vy - cc.y * VoxelChunk.SIZE
	var lz := vz - cc.z * VoxelChunk.SIZE
	chunk.set_voxel_local(lx, ly, lz, type)
	_mark_dirty_with_border(cc, lx, ly, lz)


# Destruction entry point. Combat/explosion code should call this,
# not set_voxel directly, so destructibility rules stay centralized.
func remove_voxel(world_pos: Vector3) -> bool:
	var current := get_voxel(world_pos)
	if not VoxelTypes.is_destructible(current):
		return false
	set_voxel(world_pos, VoxelTypes.Type.AIR)
	return true


# Removes every destructible voxel inside a world-space sphere.
# Use for explosions / heavy melee impacts. Returns count removed.
func remove_voxels_in_sphere(center: Vector3, radius: float) -> int:
	var removed := 0
	var vr := ceili(radius / voxel_size)
	var vc := world_to_voxel(center)
	for dx in range(-vr, vr + 1):
		for dy in range(-vr, vr + 1):
			for dz in range(-vr, vr + 1):
				var offset := Vector3(dx, dy, dz) * voxel_size
				if offset.length() > radius:
					continue
				var vx := vc.x + dx
				var vy := vc.y + dy
				var vz := vc.z + dz
				var t := _sample_world_voxel(vx, vy, vz)
				if VoxelTypes.is_destructible(t):
					set_voxel_at(vx, vy, vz, VoxelTypes.Type.AIR)
					removed += 1
	return removed


# When a voxel on a chunk edge changes, the neighboring chunk's face
# culling at that boundary needs to be recomputed too.
func _mark_dirty_with_border(cc: Vector3i, lx: int, ly: int, lz: int) -> void:
	_dirty_chunks[cc] = true
	var s := VoxelChunk.SIZE
	if lx == 0: _dirty_chunks[cc + Vector3i(-1, 0, 0)] = true
	if lx == s - 1: _dirty_chunks[cc + Vector3i(1, 0, 0)] = true
	if ly == 0: _dirty_chunks[cc + Vector3i(0, -1, 0)] = true
	if ly == s - 1: _dirty_chunks[cc + Vector3i(0, 1, 0)] = true
	if lz == 0: _dirty_chunks[cc + Vector3i(0, 0, -1)] = true
	if lz == s - 1: _dirty_chunks[cc + Vector3i(0, 0, 1)] = true
