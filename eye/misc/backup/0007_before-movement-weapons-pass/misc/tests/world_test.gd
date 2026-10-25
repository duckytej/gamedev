extends SceneTree

## Headless test for the entry scene's self-healing and health check.
##
## Removes the map and player from an instantiated `world.tscn` *before* adding
## it to the tree, then verifies `EyeWorld` reinstantiates both and reports a
## healthy setup. This is the regression test for the failure mode that broke the
## project once: a re-saved `world.tscn` silently losing its instanced children.
##
##   godot --headless --script res://misc/tests/world_test.gd

var _checks := 0
var _failures := 0


func _initialize() -> void:
	var world := (load("res://world/scenes/world.tscn") as PackedScene).instantiate() as EyeWorld

	for path in [
		"ScreenSpaceProjection/ProjectionInput/TestMap",
		"ScreenSpaceProjection/ProjectionInput/Player",
	]:
		var node := world.get_node_or_null(path)
		if node != null:
			node.get_parent().remove_child(node)
			node.free()

	root.add_child(world)
	await process_frame
	await process_frame

	_check("map is re-instantiated", get_first_node_in_group(&"map") != null)
	_check("player is re-instantiated", get_first_node_in_group(&"player") != null)
	_check("threat detector still exists", get_first_node_in_group(&"threat_detector") != null)
	_check("threat highlighter still exists",
		get_first_node_in_group(&"threat_highlighter") != null)

	var issues := world.validate()
	_check("world is healthy after self-healing", issues.is_empty())
	for issue in issues:
		printerr("    world: ", issue)

	print("world_test: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check(label: String, condition: bool) -> void:
	_checks += 1
	if condition:
		print("  ok   ", label)
	else:
		_failures += 1
		printerr("  FAIL ", label)
		push_error("world_test failed: " + label)
