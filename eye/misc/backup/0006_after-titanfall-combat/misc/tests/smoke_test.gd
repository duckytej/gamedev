extends SceneTree

## Headless smoke test for the configuration wiring.
##
## Proves that the single GameConfig resource reaches the nodes it configures,
## that the entry scene actually contains a map + player + systems, and that the
## player's state machine is assembled. Run with:
##
##   godot --headless --script res://misc/tests/smoke_test.gd
##
## Exits non-zero if anything is misconfigured, so it can gate CI.

const CONFIG_PATH := "res://core/config/game_config.tres"

var _checks := 0
var _failures := 0

var _world: EyeWorld
var _projection: Node
var _post_fx: Node


func _initialize() -> void:
	_build()
	# Let every `_ready()` in the instantiated scenes run before asserting.
	await process_frame
	await process_frame
	_resolve_nodes()
	_verify()
	print("smoke_test: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _build() -> void:
	_world = (load("res://world/scenes/world.tscn") as PackedScene).instantiate() as EyeWorld
	root.add_child(_world)


func _resolve_nodes() -> void:
	_projection = get_first_node_in_group(&"projection")
	_post_fx = get_first_node_in_group(&"post_fx")


func _verify() -> void:
	_test_config()
	_test_world_wiring()
	_test_player_wiring()


func _check(label: String, condition: bool) -> void:
	_checks += 1
	if condition:
		print("  ok   ", label)
	else:
		_failures += 1
		printerr("  FAIL ", label)
		push_error("smoke_test failed: " + label)


func _test_config() -> void:
	var config: GameConfig = load(CONFIG_PATH)
	_check("game config loads", config is GameConfig)
	if config == null:
		return

	var issues := config.validate()
	_check("game config validates", issues.is_empty())
	for issue in issues:
		printerr("    config: ", issue)

	_check("mode is Panini", config.projection_mode == GameConfig.ProjectionMode.PANINI)
	_check("lens strength is 0.2", is_equal_approx(config.lens_strength, 0.2))
	_check("lens fill is 1.0", is_equal_approx(config.lens_fill, 1.0))
	_check("chromatic aberration is subtle", is_equal_approx(config.ca_amount, 0.04))
	_check("vignette is set", is_equal_approx(config.vignette_strength, 0.18))
	_check("post-fx enabled", config.post_fx_enabled)
	_check("post-fx sharpens", config.sharpen_amount > 0.0)
	_check("base_fov is 140", is_equal_approx(config.base_fov, 140.0))
	_check("walk_speed is 6.0", is_equal_approx(config.walk_speed, 6.0))
	_check("forward half angle is 70", is_equal_approx(config.forward_half_angle_deg, 70.0))
	_check("peripheral end angle is 110",
		is_equal_approx(config.peripheral_end_angle_deg, 110.0))
	_check("near < far <= max distance",
		config.near_distance < config.far_distance
		and config.far_distance <= config.max_distance)

	# The validator is the safety net for hand-edited resources: prove it bites.
	var broken := GameConfig.new()
	broken.near_distance = 50.0
	broken.far_distance = 10.0
	_check("validate rejects an inverted distance range", not broken.validate().is_empty())


func _test_world_wiring() -> void:
	_check("world has a projection node", _projection != null)
	_check("projection node is in the 'projection' group",
		_projection != null and _projection.is_in_group(&"projection"))

	var config: GameConfig = load(CONFIG_PATH)
	if _projection != null and config != null:
		_check("addon strength == config",
			is_equal_approx(_projection.strength, config.lens_strength))
		_check("addon ca_amount == config",
			is_equal_approx(_projection.ca_amount, config.ca_amount))
		_check("addon vignette_strength == config",
			is_equal_approx(_projection.vignette_strength, config.vignette_strength))

	_check("world has a post-fx screen", _post_fx != null)
	if _post_fx != null and config != null:
		_check("post-fx has a shader material", _post_fx.material is ShaderMaterial)
		_check("post-fx has a config", _post_fx.config == config)
		if _post_fx.material is ShaderMaterial:
			var material := _post_fx.material as ShaderMaterial
			_check("post-fx material matches config",
				is_equal_approx(material.get_shader_parameter("sharpen_amount"),
					config.sharpen_amount))

	var hud := get_first_node_in_group(&"hud")
	var stats: Node = hud.get_node_or_null("Stats") if hud != null else null
	_check("hud has a stats readout", stats != null)
	_check("hud stats has position/state/fps labels",
		stats != null
		and stats.get_node_or_null("Position") != null
		and stats.get_node_or_null("State") != null
		and stats.get_node_or_null("Fps") != null)
	_check("hud stats has a threat readout",
		stats != null and stats.get_node_or_null("Threat") != null)

	_check("entry scene contains a map", get_first_node_in_group(&"map") != null)

	var detector := get_first_node_in_group(&"threat_detector") as ThreatDetector
	_check("entry scene has a threat detector", detector != null)
	if detector != null:
		_check("detector has a config", detector.config != null)
		_check("detector resolved the player camera", detector.get_camera() != null)

	var highlighter := get_first_node_in_group(&"threat_highlighter")
	_check("entry scene has a threat highlighter", highlighter is ThreatHighlighter)

	# The world root's own health check must agree with every assertion above.
	var issues := _world.validate()
	_check("world.validate() reports no issues", issues.is_empty())
	for issue in issues:
		printerr("    world: ", issue)


func _test_player_wiring() -> void:
	var player := get_first_node_in_group(&"player") as EyePlayer
	_check("entry scene has a player", player != null)
	if player == null:
		return

	_check("player has a config", player.config != null)
	if player.config != null:
		_check("player uses the shared game config",
			player.config.resource_path == CONFIG_PATH)

	var camera := player.get_node_or_null("Neck/Camera3D") as Camera3D
	_check("player has a camera", camera != null)
	if camera != null and player.config != null:
		_check("camera fov == config", is_equal_approx(camera.fov, player.config.base_fov))

	var machine := player.get_node_or_null("States") as PlayerStateMachine
	_check("player has a state machine", machine != null)
	if machine != null:
		for state_name in ["Idle", "Walk", "Run", "Jump", "Fall", "Land", "Slide", "WallRun", "Grapple", "Dash"]:
			_check("state machine has %s" % state_name, machine.has_state(StringName(state_name)))
		_check("state machine has an active state", machine.current != null)

	var abilities := player.get_node_or_null("Abilities") as PlayerAbilityHost
	_check("player has an ability host", abilities != null)
	if abilities != null:
		_check("wall sense is installed", player.get_wall_sense() != null)
		_check("grapple is installed", player.get_grapple() != null)
		_check("weapons ability is installed", player.get_weapons() != null)

	var weapons := player.get_node_or_null("Abilities/Weapons") as WeaponController
	_check("weapon controller is wired", weapons != null)
	if weapons != null:
		_check("loadout has three weapons", weapons.get_weapons().size() == 3)

	var hud := get_first_node_in_group(&"hud")
	_check("hud has a scope overlay",
		hud != null and hud.get_node_or_null("ScopeOverlay") is ColorRect)
	_check("hud has a weapon status readout",
		hud != null and hud.get_node_or_null("WeaponStatus") is Label)
	var crosshair := hud.get_node_or_null("CrosshairCenter/Crosshair") as Control \
		if hud != null else null
	_check("hud never consumes mouse input",
		crosshair != null and crosshair.mouse_filter == Control.MOUSE_FILTER_IGNORE)
