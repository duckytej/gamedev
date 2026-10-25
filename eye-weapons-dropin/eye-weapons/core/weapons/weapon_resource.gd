class_name WeaponResource
extends Resource
## Data for one gun. New gun = new .tres file, zero new code.
## Create via: right-click in FileSystem -> New Resource -> WeaponResource.

enum FireType { HITSCAN, PROJECTILE, MELEE, CHIMERA }

@export var weapon_name := "Pistol"
@export var fire_type: FireType = FireType.HITSCAN

# damage + pacing
@export var damage := 25.0
@export var fire_interval := 0.15   # seconds between shots
@export var auto := false           # hold to fire, or click per shot

# ammo
@export var magazine_size := 12
@export var reserve_ammo := 60
@export var reload_time := 1.2

# feel (the DOOM knobs)
@export var spread_deg := 1.0        # base inaccuracy
@export var bloom_per_shot := 0.3    # spread growth per shot (decays over time)
@export var recoil_kick_deg := 0.5   # camera pitch kick per shot
@export var pellets := 1             # >1 = shotgun
@export var range := 200.0

# projectile (only used when fire_type == PROJECTILE)
@export var projectile_scene: PackedScene
@export var projectile_speed := 40.0

# presentation
@export var viewmodel: PackedScene   # your .vox gun parts assembled as a scene
@export var ads_fov := 55.0

# melee (only used when fire_type == MELEE)
@export var swing_time := 0.3        # WINDUP(30%) + SWING + RECOVER(50%)
@export var combo_hits := 3
