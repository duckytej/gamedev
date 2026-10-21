extends SceneTree

## Headless smoke test for the configuration wiring.
##
## Proves that profiles reach the nodes they configure and that the player's
## state machine is assembled. Run with:
##
##   godot --headless --script res://misc/tests/smoke_test.gd
##
## Exits non-zero if anything is misconfigured, so it can gate CI.

var _checks := 0
var _failures := 0

var _world: Node
var _projection: Node
var _post_fx: Node
var _player: Node


func _initialize() -> void:
	_build()
	# Let every `_ready()` in the instantiated scenes run before asserting.
	await process_frame
	await process_frame
	_verify()
	print("smoke_test: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _build() -> void:
	_world = (load("res://world/scenes/world.tscn") as PackedScene).instantiate()
	root.add_child(_world)
	_projection = _world.get_node_or_null("ScreenSpaceProjection")
	_post_fx = _world.get_node_or_null("PostFx/Screen")
	_player = (load("res://player/scenes/player.tscn") as PackedScene).instantiate()
	root.add_child(_player)


func _verify() -> void:
	_test_projection_profile()
	_test_post_fx_profile()
	_test_player_config()
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


func _test_projection_profile() -> void:
	var profile: ProjectionProfile = load("res://core/config/projection_profile.tres")
	_check("projection profile loads", profile is ProjectionProfile)
	if profile == null:
		return
	_check("mode is Panini", profile.projection_mode == ProjectionProfile.ProjectionMode.PANINI)
	_check("strength is 0.5", is_equal_approx(profile.strength, 0.5))
	_check("fill is 1.0", is_equal_approx(profile.fill, 1.0))
	_check("chromatic aberration is subtle", is_equal_approx(profile.ca_amount, 0.04))
	_check("vignette is set", is_equal_approx(profile.vignette_strength, 0.18))


func _test_post_fx_profile() -> void:
	var profile: PostFxProfile = load("res://core/config/post_fx_profile.tres")
	_check("post-fx profile loads", profile is PostFxProfile)
	if profile == null:
		return
	_check("post-fx enabled", profile.enabled)
	_check("post-fx sharpens", profile.sharpen_amount > 0.0)


func _test_player_config() -> void:
	var config: PlayerConfig = load("res://core/config/player_config.tres")
	_check("player config loads", config is PlayerConfig)
	if config == null:
		return
	_check("base_fov is 140", is_equal_approx(config.base_fov, 140.0))
	_check("walk_speed is 6.0", is_equal_approx(config.walk_speed, 6.0))


func _test_world_wiring() -> void:
	_check("world has a projection node", _projection != null)
	_check("projection node is in the 'projection' group",
		_projection != null and _projection.is_in_group(&"projection"))
	if _projection != null:
		var profile: ProjectionProfile = load("res://core/config/projection_profile.tres")
		_check("addon strength == profile", is_equal_approx(_projection.strength, profile.strength))
		_check("addon ca_amount == profile",
			is_equal_approx(_projection.ca_amount, profile.ca_amount))
		_check("addon vignette_strength == profile",
			is_equal_approx(_projection.vignette_strength, profile.vignette_strength))

	_check("world has a post-fx screen", _post_fx != null)
	if _post_fx != null:
		_check("post-fx has a shader material", _post_fx.material is ShaderMaterial)
		_check("post-fx has a profile", _post_fx.profile != null)

	var stats := _world.get_node_or_null("Hud/Stats")
	_check("hud has a stats readout", stats != null)
	_check("hud stats has position/state/fps labels",
		stats != null
		and stats.get_node_or_null("Position") != null
		and stats.get_node_or_null("State") != null
		and stats.get_node_or_null("Fps") != null)


func _test_player_wiring() -> void:
	_check("player has a config", _player.config != null)
	if _player.config != null:
		_check("player base_fov == config", is_equal_approx(_player.base_fov, _player.config.base_fov))

	var camera := _player.get_node_or_null("Neck/Camera3D")
	_check("player has a camera", camera != null)
	if camera != null and _player.config != null:
		_check("camera fov == config", is_equal_approx(camera.fov, _player.config.base_fov))

	var machine := _player.get_node_or_null("States")
	_check("player has a state machine", machine != null)
	if machine != null:
		for state_name in ["Idle", "Walk", "Run", "Jump", "Fall", "Land", "Slide", "WallRun", "Dash"]:
			_check("state machine has %s" % state_name, machine.has_state(StringName(state_name)))
		_check("state machine has an active state", machine.current != null)
