class_name VoxelTypes
extends RefCounted

enum Type {
	AIR = 0,
	CONCRETE = 1,
	CONCRETE_DARK = 2,
	CONCRETE_LIGHT = 3,
	GLASS = 4,
	GLASS_BROKEN = 5,
	GLASS_LIT = 6,
	METAL = 7,
	METAL_RUSTED = 8,
	NEON_CYAN = 9,
	NEON_MAGENTA = 10,
	NEON_ORANGE = 11,
	NEON_GREEN = 12,
	ROAD = 13,
	ROAD_LINE = 14,
	WALL = 15,
}

const SOLID_TYPES := {
	Type.AIR: false,
	Type.CONCRETE: true,
	Type.CONCRETE_DARK: true,
	Type.CONCRETE_LIGHT: true,
	Type.GLASS: true,
	Type.GLASS_BROKEN: true,
	Type.GLASS_LIT: true,
	Type.METAL: true,
	Type.METAL_RUSTED: true,
	Type.NEON_CYAN: true,
	Type.NEON_MAGENTA: true,
	Type.NEON_ORANGE: true,
	Type.NEON_GREEN: true,
	Type.ROAD: true,
	Type.ROAD_LINE: true,
	Type.WALL: true,
}

# Structural types (roads, wall) survive explosions; everything built
# up from concrete/metal/glass/neon can be torn out by combat.
const DESTRUCTIBLE_TYPES := {
	Type.CONCRETE: true,
	Type.CONCRETE_DARK: true,
	Type.CONCRETE_LIGHT: true,
	Type.GLASS: true,
	Type.GLASS_BROKEN: true,
	Type.GLASS_LIT: true,
	Type.METAL: true,
	Type.METAL_RUSTED: true,
	Type.NEON_CYAN: true,
	Type.NEON_MAGENTA: true,
	Type.NEON_ORANGE: true,
	Type.NEON_GREEN: true,
}


static func is_solid(type: int) -> bool:
	return SOLID_TYPES.get(type, false)


static func is_destructible(type: int) -> bool:
	return DESTRUCTIBLE_TYPES.get(type, false)


static func build_materials() -> Dictionary:
	var mats := {}
	mats[Type.CONCRETE] = _mat(Color(0.42, 0.42, 0.45), 0.85, 0.05)
	mats[Type.CONCRETE_DARK] = _mat(Color(0.28, 0.28, 0.32), 0.9, 0.1)
	mats[Type.CONCRETE_LIGHT] = _mat(Color(0.55, 0.55, 0.6), 0.8, 0.03)
	mats[Type.GLASS] = _glass(Color(0.15, 0.2, 0.25))
	mats[Type.GLASS_BROKEN] = _mat(Color(0.2, 0.22, 0.25), 0.2, 0.05)
	mats[Type.GLASS_LIT] = _emissive(Color(0.9, 0.75, 0.4), 1.2)
	mats[Type.METAL] = _mat(Color(0.45, 0.48, 0.52), 0.4, 0.85)
	mats[Type.METAL_RUSTED] = _mat(Color(0.5, 0.35, 0.22), 0.9, 0.3)
	mats[Type.NEON_CYAN] = _emissive(Color(0.0, 0.9, 1.0), 4.0)
	mats[Type.NEON_MAGENTA] = _emissive(Color(0.9, 0.0, 0.7), 4.0)
	mats[Type.NEON_ORANGE] = _emissive(Color(1.0, 0.5, 0.0), 4.0)
	mats[Type.NEON_GREEN] = _emissive(Color(0.0, 1.0, 0.4), 4.0)
	mats[Type.ROAD] = _mat(Color(0.18, 0.18, 0.22), 0.95, 0.02)
	mats[Type.ROAD_LINE] = _emissive(Color(0.9, 0.8, 0.3), 2.0)
	mats[Type.WALL] = _mat(Color(0.3, 0.3, 0.35), 0.9, 0.1)
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


static func _emissive(color: Color, strength: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.02, 0.02, 0.02)
	m.emission_enabled = true
	m.emission = color * strength
	m.metallic = 0.0
	return m
