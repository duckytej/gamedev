class_name EyeWorld
extends Node3D

## Root of the entry scene.
##
## Two jobs:
## 1. **Self-heal the scene wiring.** If `world.tscn` ever loses its map or player
##    child (easy to do when a scene is re-saved by a tool), the missing piece is
##    instantiated from the exported scenes instead of silently running an empty
##    game.
## 2. **Validate the setup on startup.** Config invariants and required systems
##    are checked once, with actionable `push_error` messages, so a broken tweak
##    is obvious in the output rather than a blank screen.
##
## The smoke test calls [method validate] too, so the same checks gate CI.

const DEFAULT_MAP: PackedScene = preload("res://world/scenes/test_map.tscn")
const DEFAULT_PLAYER: PackedScene = preload("res://player/scenes/player.tscn")

## Shared tuning resource. Edit `core/config/game_config.tres`.
@export var config: GameConfig

## Map scene to fall back to when the scene tree has no node in the `map` group.
@export var map_scene: PackedScene = DEFAULT_MAP

## Player scene to fall back to when the scene tree has no node in the `player`
## group.
@export var player_scene: PackedScene = DEFAULT_PLAYER

## Where the fallback player is spawned.
@export var spawn_position := Vector3(0.0, 0.4, 10.0)

var world_root: Node


func _ready() -> void:
	if config == null:
		config = GameConfig.new()
		push_warning("EyeWorld: no GameConfig assigned; using defaults.")

	world_root = get_node_or_null("ScreenSpaceProjection/ProjectionInput")
	if world_root == null:
		world_root = find_child("ProjectionInput", true, false)
	if world_root == null:
		push_error(
			"EyeWorld: missing ScreenSpaceProjection/ProjectionInput. "
			+ "The lens addon or its viewport was renamed/removed."
		)
		return

	_ensure_map()
	_ensure_player()

	for issue in validate():
		push_error("EyeWorld: " + issue)


func _ensure_map() -> void:
	if get_tree().get_first_node_in_group(&"map") != null:
		return
	if map_scene == null:
		push_error("EyeWorld: no map in the scene and no map_scene assigned.")
		return
	var map := map_scene.instantiate()
	map.name = "Map"
	world_root.add_child(map)
	push_warning("EyeWorld: map was missing from world.tscn; instantiated the fallback.")


func _ensure_player() -> void:
	if get_tree().get_first_node_in_group(&"player") != null:
		return
	if player_scene == null:
		push_error("EyeWorld: no player in the scene and no player_scene assigned.")
		return
	var player := player_scene.instantiate()
	player.name = "Player"
	player.position = spawn_position
	world_root.add_child(player)
	push_warning("EyeWorld: player was missing from world.tscn; instantiated the fallback.")


## Returns a list of human-readable wiring/config problems. Empty means healthy.
func validate() -> PackedStringArray:
	var issues := PackedStringArray()

	if config == null:
		issues.append("no GameConfig assigned.")
	else:
		issues.append_array(config.validate())

	if get_tree().get_first_node_in_group(&"map") == null:
		issues.append("no map node (group 'map').")
	if get_tree().get_first_node_in_group(&"player") == null:
		issues.append("no player node (group 'player').")
	if get_tree().get_first_node_in_group(&"projection") == null:
		issues.append("no screen-space lens node (group 'projection').")
	if get_tree().get_first_node_in_group(&"threat_detector") == null:
		issues.append("no threat detector (group 'threat_detector').")
	if get_tree().get_first_node_in_group(&"threat_highlighter") == null:
		issues.append("no threat highlighter (group 'threat_highlighter').")
	if get_tree().get_first_node_in_group(&"post_fx") == null:
		issues.append("no post-fx pass (group 'post_fx').")
	if get_tree().get_first_node_in_group(&"enemy_director") == null:
		issues.append("no enemy director (group 'enemy_director').")
	var hud := get_tree().get_first_node_in_group(&"hud")
	if hud == null:
		issues.append("no HUD (group 'hud').")
	elif hud.get_node_or_null("Stats") == null:
		issues.append("HUD has no Stats readout.")
	elif hud.get_node_or_null("Vitals") == null:
		issues.append("HUD has no vitals readout.")

	var player := get_tree().get_first_node_in_group(&"player")
	if player != null:
		if player.get_node_or_null("Neck/Camera3D") == null:
			issues.append("player has no Neck/Camera3D.")
		if player.get_node_or_null("Health") == null:
			issues.append("player has no Health (PlayerVitals) component.")

	return issues
