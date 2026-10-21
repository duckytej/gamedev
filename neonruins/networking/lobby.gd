extends Node

const DEFAULT_PORT: int = 7777
const MAX_CLIENTS: int = 4
const PLAYER_SCENE := preload("res://player/player.tscn")

var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()


func host_game(_address: String = "localhost") -> Error:
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(DEFAULT_PORT, MAX_CLIENTS)
	if err != OK:
		return err

	multiplayer.multiplayer_peer = peer
	_connect_signals()

	Globals.is_host = true
	SignalBus.connection_succeeded.emit()
	print("Hosting on port %d" % DEFAULT_PORT)
	return OK


func join_game(address: String) -> Error:
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(address if address.strip_edges() != "" else "127.0.0.1", DEFAULT_PORT)
	if err != OK:
		return err

	multiplayer.multiplayer_peer = peer
	_connect_signals()
	return OK


func leave_game() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	Globals.is_host = false


func _connect_signals() -> void:
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
		multiplayer.connected_to_server.connect(_on_connected_to_server)
		multiplayer.connection_failed.connect(_on_connection_failed)
		multiplayer.server_disconnected.connect(_on_server_disconnected)


# === CONNECTION CALLBACKS ===

func _on_peer_connected(id: int) -> void:
	print("Peer connected: ", id)
	if not multiplayer.is_server():
		return

	# Spawn the newcomer's avatar on the server
	_spawn_player_for_peer(id)

	# Tell everyone about the newcomer...
	var newcomer: Node = Globals.get_player(id)
	if newcomer:
		sync_player_spawn.rpc(id, newcomer.position, 0.0)

	# ...and tell the newcomer about everyone already here (host included)
	for pid: int in Globals.players:
		if pid == id or not is_instance_valid(Globals.players[pid]):
			continue
		var p: Node3D = Globals.players[pid]
		sync_player_spawn.rpc_id(id, pid, p.position, p.rotation.y)


func _on_peer_disconnected(id: int) -> void:
	print("Peer disconnected: ", id)
	sync_player_despawn.rpc(id)
	_despawn_player(id)


func _on_connected_to_server() -> void:
	print("Connected to server!")
	SignalBus.connection_succeeded.emit()


func _on_connection_failed() -> void:
	print("Connection failed!")
	leave_game()
	SignalBus.connection_failed.emit()


func _on_server_disconnected() -> void:
	print("Server disconnected!")
	_clear_all_remote_players()
	leave_game()
	SignalBus.server_disconnected.emit()


# === PLAYER SPAWN SYNC ===

func _spawn_player_for_peer(peer_id: int) -> void:
	var player := PLAYER_SCENE.instantiate()
	player.name = str(peer_id)
	player.set_multiplayer_authority(peer_id)
	player.position = Vector3(randf_range(-10, 10), 5, randf_range(-10, 10))
	Globals.game_map.add_child(player)
	Globals.register_player(peer_id, player)


func _despawn_player(peer_id: int) -> void:
	var player: Node = Globals.get_player(peer_id)
	if player and is_instance_valid(player) and peer_id != multiplayer.get_unique_id():
		player.queue_free()
	Globals.unregister_player(peer_id)


func _clear_all_remote_players() -> void:
	for pid: int in Globals.players.keys():
		var player: Node = Globals.players[pid]
		if is_instance_valid(player):
			player.queue_free()
	Globals.players.clear()


@rpc("any_peer", "call_remote", "reliable")
func sync_player_spawn(peer_id: int, position: Vector3, yaw: float) -> void:
	if peer_id == multiplayer.get_unique_id():
		return
	if Globals.get_player(peer_id):
		return  # already tracked

	var player := PLAYER_SCENE.instantiate()
	player.name = str(peer_id)
	player.set_multiplayer_authority(peer_id)
	Globals.game_map.add_child(player)
	player.position = position
	player.rotation.y = yaw
	Globals.register_player(peer_id, player)


@rpc("any_peer", "call_local", "reliable")
func sync_player_despawn(peer_id: int) -> void:
	_despawn_player(peer_id)
