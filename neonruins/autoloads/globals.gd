extends Node

var players: Dictionary = {}
var enemies: Array = []
var local_player: Node = null
var is_host: bool = false
var game_map: Node = null

var config := {
	"city_size": 80,
	"block_size": 4.0,
	"max_building_height": 25,
	"street_spacing": 16,
	"street_width": 3,
	"enemy_count": 24,
}

func register_player(peer_id: int, player_node: Node) -> void:
	players[peer_id] = player_node
	SignalBus.player_spawned.emit(peer_id, player_node)

func unregister_player(peer_id: int) -> void:
	if players.has(peer_id):
		players.erase(peer_id)
		SignalBus.player_despawned.emit(peer_id)

func get_player(peer_id: int) -> Node:
	return players.get(peer_id)

func get_all_players() -> Array:
	return players.values()

func register_enemy(enemy: Node) -> void:
	enemies.append(enemy)

func unregister_enemy(enemy: Node) -> void:
	enemies.erase(enemy)

func get_nearest_enemy(pos: Node3D, max_dist: float = 50.0) -> Node3D:
	var nearest: Node3D = null
	var nearest_dist: float = max_dist
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		var dist = pos.global_position.distance_to(enemy.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = enemy
	return nearest

func get_nearest_player(pos: Node3D, max_dist: float = 50.0) -> Node3D:
	var nearest: Node3D = null
	var nearest_dist: float = max_dist
	for player in players.values():
		if player == pos:
			continue
		var dist = pos.global_position.distance_to(player.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = player
	return nearest
