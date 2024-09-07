extends Control
@onready var player=$".."/player

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass



# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	var text =str(Engine.get_frames_per_second())
	$Stats/UI/FPS.text="FPS: "+text
	$Stats/UI/speed.text="Km/h: "+str(round(player.velocity.length()))
	
