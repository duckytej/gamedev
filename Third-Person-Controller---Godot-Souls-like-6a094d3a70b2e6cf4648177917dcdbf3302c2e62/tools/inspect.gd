extends SceneTree

func _init():
	var player = load("res://player/HunterGodot.tscn").instantiate()
	root.add_child(player)
	await physics_frame
	await process_frame
	var skel: Skeleton3D = player.get_node("HunterMeshes/Armature/Skeleton3D")
	var hand := skel.find_bone("mixamorigRightHand")
	print("hand bone idx=", hand, " global pos=", skel.global_transform * skel.get_bone_global_pose(hand).origin)
	var att: Node3D = player.get_node_or_null("HunterMeshes/Armature/Skeleton3D/Bone-Hand")
	print("attachment=", att, " global=", att.global_transform.origin if att else "n/a")
	var ax: Node3D = player.get_node_or_null("HunterMeshes/Armature/Skeleton3D/Bone-Hand/AxHandle/GodotAx")
	print("axe=", ax, " global=", ax.global_transform.origin if ax else "n/a")
	print("axe mesh global aabb=", ax.get_node("Ax_GodotHunter").global_transform * ax.get_node("Ax_GodotHunter").get_aabb() if ax else "n/a")
	await physics_frame
	print("after frame att global=", att.global_transform.origin if att else "n/a")
	quit()
