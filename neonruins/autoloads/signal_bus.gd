extends Node

# Health & Damage
signal damage_dealt(target: Node, amount: float, source: Node)
signal health_changed(entity: Node, current: float, maximum: float)
signal entity_died(entity: Node)

# Stamina
signal stamina_changed(entity: Node, current: float, maximum: float)
signal stamina_depleted(entity: Node)
signal stamina_exhausted(entity: Node)

# Ammo
signal ammo_changed(entity: Node, current: int, maximum: int)

# Combat
signal attack_started(attacker: Node, attack_type: String)
signal attack_landed(attacker: Node, target: Node, damage: float)
signal weapon_changed(entity: Node, weapon: Resource)
signal lock_on_changed(entity: Node, target: Node)

# Player Movement
signal player_landed(player: Node, speed: float)
signal player_wall_run(player: Node, wall_normal: Vector3)
signal player_grapple_started(player: Node)
signal player_grapple_ended(player: Node)
signal player_slide_started(player: Node)
signal player_dash_started(player: Node)

# Game State
signal player_spawned(peer_id: int, player: Node)
signal player_despawned(peer_id: int)
signal game_started()
signal round_ended(winner_id: int)

# Multiplayer
signal connection_succeeded()
signal connection_failed()
signal server_disconnected()
