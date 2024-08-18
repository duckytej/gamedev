#extends AIController3D
#@onready var t = $"../../target"
#var move = Vector3.ZERO
#
#func get_obs() -> Dictionary:
	#var obs = [
	#position.x,
	#position.y,
	#position.z,
	#t.position.x,
	#t.position.y,
	#t.position.z,
#]
	#return {"obs":obs}
#
#func get_reward() -> float:
	#return reward
	#
#func get_action_space() -> Dictionary:
	#return {
		#"move" : {
			#"size": 3,
			#"action_type": "continuous"
		#}
		#}
	#
#func set_action(action) -> void:	
	#move.x=action["move"][0]
	#move.y=action["move"][1]
	#move.z=action["move"][2]
