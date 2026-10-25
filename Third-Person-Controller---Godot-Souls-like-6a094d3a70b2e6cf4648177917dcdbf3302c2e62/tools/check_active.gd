extends SceneTree

func _init():
	print("props:")
	for p in ClassDB.class_get_property_list("AnimationNodeStateMachine", true):
		print("  ", p.name)
	print("methods:")
	for m in ClassDB.class_get_method_list("AnimationNodeStateMachine", true):
		if not m.name.begins_with("_"):
			print("  ", m.name)
	var sm := AnimationNodeStateMachine.new()
	print("start_node via get: ", sm.get("start_node"))
	quit()
