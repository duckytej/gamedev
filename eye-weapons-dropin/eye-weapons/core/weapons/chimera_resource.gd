class_name ChimeraGunResource
extends WeaponResource
## Tuning for the Chimera — one gun, four modes:
##   HIP + tap        = pistol (hitscan, negligible damage)
##   HIP + hold→release = grenade launcher (projectile + blast, charge scales it)
##   SCOPED + tap     = sniper projectile (fast, heavy)
##   SCOPED + hold    = charge → mid: sniper hitscan / full: hitscan + ricochet
##
## New gun feel = tweak these numbers. No code changes needed.

@export_group("Chimera - timing")
@export var tap_window := 0.22        # release before this = tap shot
@export var mid_charge_time := 0.9   # scoped hold: mid tier at this hold time
@export var full_charge_time := 1.6  # scoped hold: full tier at this hold time

@export_group("Chimera - hip")
@export var pistol_damage := 8.0
@export var pistol_interval := 0.18
@export var grenade_base_damage := 40.0
@export var grenade_max_damage := 80.0
@export var grenade_base_radius := 2.5
@export var grenade_max_radius := 4.5
@export var grenade_speed := 22.0
@export var grenade_gravity := 9.8
@export var grenade_interval := 0.8

@export_group("Chimera - scoped")
@export var sniper_projectile_damage := 70.0
@export var sniper_projectile_speed := 120.0
@export var sniper_interval := 0.9
@export var scoped_mid_damage := 90.0    # hitscan at mid charge
@export var scoped_full_damage := 110.0  # hitscan at full charge
@export var charged_interval := 1.2
@export var ricochet_count := 2
@export var ricochet_radius := 8.0
@export var ricochet_falloff := 0.6
@export var scope_zoom := 0.25           # camera fov multiplier while scoped

@export_group("Chimera - ammo costs")
@export var ammo_pistol := 1
@export var ammo_grenade := 3
@export var ammo_sniper := 2
@export var ammo_charged := 4
