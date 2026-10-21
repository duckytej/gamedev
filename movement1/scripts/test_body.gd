extends Node3D

var spawn_protect :bool= true
func _on_area_3d_body_entered(_body: Node3D) -> void:
	if not spawn_protect:
		Globals.left-=1
		self.queue_free()

func _on_spawn_protection_timer_timeout() -> void:
	spawn_protect = false
