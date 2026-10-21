extends CanvasLayer

@onready var health_bar: ProgressBar = $VitalsContainer/HealthFrame/HealthVBox/HealthBarContainer/HealthBar
@onready var health_value: Label = $VitalsContainer/HealthFrame/HealthVBox/HealthHeader/HealthValue
@onready var stamina_bar: ProgressBar = $VitalsContainer/StaminaFrame/StaminaVBox/StaminaBarContainer/StaminaBar
@onready var stamina_value: Label = $VitalsContainer/StaminaFrame/StaminaVBox/StaminaHeader/StaminaValue
@onready var lock_on_indicator: PanelContainer = $LockOnContainer/LockOnIndicator
@onready var fps_label: Label = $DebugContainer/DebugVBox/FPS
@onready var speed_label: Label = $DebugContainer/DebugVBox/Speed
@onready var state_label: Label = $DebugContainer/DebugVBox/State
@onready var pos_label: Label = $DebugContainer/DebugVBox/Pos
@onready var ammo_bar: ProgressBar = $AmmoContainer/AmmoVBox/AmmoBarContainer/AmmoBar
@onready var ammo_value: Label = $AmmoContainer/AmmoVBox/AmmoHeader/AmmoValue

var _lock_on_tween: Tween = null


func _ready() -> void:
	SignalBus.health_changed.connect(_on_health_changed)
	SignalBus.stamina_changed.connect(_on_stamina_changed)
	SignalBus.ammo_changed.connect(_on_ammo_changed)
	SignalBus.lock_on_changed.connect(_on_lock_on_changed)
	SignalBus.entity_died.connect(_on_entity_died)


func _on_health_changed(entity: Node, current: float, maximum: float) -> void:
	if entity != Globals.local_player:
		return

	health_bar.max_value = maximum
	health_bar.value = current
	health_value.text = "%d / %d" % [current, maximum]

	# Pulse when low
	if maximum > 0.0 and current / maximum < 0.3:
		health_bar.modulate = Color(1.0, 0.3, 0.35, absf(sin(Time.get_ticks_msec() * 0.01)) * 0.5 + 0.5)
	else:
		health_bar.modulate = Color.WHITE


func _on_stamina_changed(entity: Node, current: float, maximum: float) -> void:
	if entity != Globals.local_player:
		return

	stamina_bar.max_value = maximum
	stamina_bar.value = current
	stamina_value.text = "%d / %d" % [current, maximum]


func _on_ammo_changed(entity: Node, current: int, maximum: int) -> void:
	if entity != Globals.local_player:
		return

	ammo_bar.max_value = maximum
	ammo_bar.value = current

	if current == 0 and maximum > 0:
		ammo_value.text = "EMPTY"
	elif entity is Player and entity.ranged_system and entity.ranged_system.is_reloading:
		ammo_value.text = "RELOADING..."
	else:
		ammo_value.text = "%d / %d" % [current, maximum]


func _on_lock_on_changed(entity: Node, target: Node) -> void:
	if entity != Globals.local_player:
		return

	lock_on_indicator.visible = target != null

	if _lock_on_tween:
		_lock_on_tween.kill()
		_lock_on_tween = null

	if target:
		lock_on_indicator.modulate.a = 1.0
		_lock_on_tween = create_tween()
		_lock_on_tween.set_loops()
		_lock_on_tween.tween_property(lock_on_indicator, "modulate:a", 0.5, 0.5)
		_lock_on_tween.tween_property(lock_on_indicator, "modulate:a", 1.0, 0.5)


func _on_entity_died(entity: Node) -> void:
	if entity == Globals.local_player:
		# Fade vitals red on death
		var tween := create_tween()
		tween.tween_property(health_bar, "modulate", Color(1.0, 0.1, 0.1), 0.5)


func _process(_delta: float) -> void:
	fps_label.text = "FPS: %d" % Engine.get_frames_per_second()

	var player := Globals.local_player as Player if Globals.local_player is Player else null
	if player == null or not is_instance_valid(player):
		speed_label.text = "VEL: 0 km/h"
		state_label.text = "STATE: --"
		pos_label.text = "POS: 0, 0, 0"
		return

	var horiz_speed := Vector2(player.velocity.x, player.velocity.z).length()
	speed_label.text = "VEL: %d km/h" % int(horiz_speed * 3.6)

	if player.current_state:
		state_label.text = "STATE: %s" % player.current_state.name.to_upper()
	else:
		state_label.text = "STATE: --"

	pos_label.text = "POS: %.0f, %.0f, %.0f" % [
		player.global_position.x, player.global_position.y, player.global_position.z
	]
