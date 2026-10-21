extends Resource
class_name WeaponResource

@export var weapon_name: String = "Sword"
@export var damage: float = 25.0
@export var attack_speed: float = 0.5
@export var stamina_cost: float = 20.0
@export var range_distance: float = 3.0
@export var max_combo: int = 3
@export var hit_active_start: float = 0.1
@export var hit_active_duration: float = 0.2
@export var knockback_force: float = 8.0
@export var stagger_amount: float = 0.3

# Ranged specific
@export var is_ranged: bool = false
@export var projectile_speed: float = 80.0
@export var ammo_max: int = 30
@export var reload_time: float = 1.5
@export var fire_rate: float = 0.15
@export var spread: float = 0.02
@export var recoil_force: float = 2.0
