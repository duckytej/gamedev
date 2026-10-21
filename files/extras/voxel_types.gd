class_name VoxelTypes
extends RefCounted

# Central registry of voxel type IDs and their materials.
# Add new types here only -- nothing else should hardcode an int.

enum Type {
	AIR = 0,
	CONCRETE = 1,
	CONCRETE_DARK = 2,
	GLASS = 3,
	GLASS_LIT = 4,
	METAL = 5,
	METAL_RUSTED = 6,
	NEON = 7,
	ROAD = 8,
	WALL = 9,
	ARENA_FLOOR = 10,
	PLATFORM = 11,
}

const SOLID_TYPES := {
	Type.AIR: false,
	Type.CONCRETE: true,
	Type.CONCRETE_DARK: true,
	Type.GLASS: true,
	Type.GLASS_LIT: true,
	Type.METAL: true,
	Type.METAL_RUSTED: true,
	Type.NEON: true,
	Type.ROAD: true,
	Type.WALL: true,
	Type.ARENA_FLOOR: true,
	Type.PLATFORM: true,
}

# Types that are destructible via combat/environment damage.
# Roads, wall, and arena floor are intentionally excluded -- they are
# structural/level-bounding and should not be removable through normal play.
const DESTRUCTIBLE_TYPES := {
	Type.CONCRETE: true,
	Type.CONCRETE_DARK: true,
	Type.GLASS: true,
	Type.GLASS_LIT: true,
	Type.METAL: true,
	Type.METAL_RUSTED: true,
	Type.NEON: true,
	Type.PLATFORM: true,
}


static func is_solid(type: int) -> bool:
	return SOLID_TYPES.get(type, false)


static func is_destructible(type: int) -> bool:
	return DESTRUCTIBLE_TYPES.get(type, false)


static func build_materials() -> Dictionary:
	var mats := {}
	mats[Type.CONCRETE] = _mat(Color(0.42, 0.42, 0.45), 0.85, 0.05)
	mats[Type.CONCRETE_DARK] = _mat(Color(0.28, 0.28, 0.32), 0.9, 0.1)
	mats[Type.GLASS] = _glass(Color(0.15, 0.2, 0.25))
	mats[Type.GLASS_LIT] = _emissive(Color(0.9, 0.75, 0.4), 1.2)
	mats[Type.METAL] = _mat(Color(0.45, 0.48, 0.52), 0.4, 0.85)
	mats[Type.METAL_RUSTED] = _mat(Color(0.5, 0.35, 0.22), 0.9, 0.3)
	mats[Type.NEON] = _emissive(Color(0.0, 1.0, 0.85), 4.0)
	mats[Type.ROAD] = _mat(Color(0.18, 0.18, 0.22), 0.95, 0.02)
	mats[Type.WALL] = _mat(Color(0.3, 0.3, 0.35), 0.9, 0.1)
	mats[Type.ARENA_FLOOR] = _emissive(Color(0.0, 0.6, 0.8), 0.3, Color(0.12, 0.14, 0.18))
	mats[Type.PLATFORM] = _mat(Color(0.35, 0.36, 0.4), 0.7, 0.4)
	return mats


static func _mat(albedo: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.roughness = roughness
	m.metallic = metallic
	return m


static func _glass(albedo: Color) -> StandardMaterial3D:
	var m := _mat(albedo, 0.05, 0.1)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.render_priority = 1
	return m


static func _emissive(color: Color, strength: float, base: Color = Color(0.02, 0.02, 0.02)) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = base
	m.emission_enabled = true
	m.emission = color * strength
	m.metallic = 0.0
	return m
