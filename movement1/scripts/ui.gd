extends Control
@onready var player=$".."/player
var time=0
var count=0
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if Input.is_action_just_pressed("start"):
		count+=1
	if count%2!=0:
		time+=delta
	if Input.is_action_pressed("reset"):
		time=0
	var text =str(Engine.get_frames_per_second())
	$UI/stat/FPS.text="FPS: "+text
	$UI/stat/speed.text="Km/h: "+str(round(player.velocity.length()))
	$UI/stat/timer.text="Time: "+str(round(time))
	if Input.is_action_just_pressed("spawn"):
		Globals.left+=1
	$UI/stat/Label.text="left "+str(Globals.left)
