extends Control

@onready var host_button: Button = $PanelContainer/VBoxContainer/HostButton
@onready var join_button: Button = $PanelContainer/VBoxContainer/JoinButton
@onready var address_input: LineEdit = $PanelContainer/VBoxContainer/AddressInput
@onready var status_label: Label = $PanelContainer/VBoxContainer/StatusLabel

var lobby: Node

func _ready() -> void:
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	SignalBus.connection_succeeded.connect(_on_connection_succeeded)
	SignalBus.connection_failed.connect(_on_connection_failed)
	SignalBus.server_disconnected.connect(_on_server_disconnected)
	lobby = get_tree().root.get_node_or_null("Main/Lobby")

func _on_host_pressed() -> void:
	status_label.text = "Hosting..."
	if lobby:
		var err = lobby.host_game()
		if err != OK:
			status_label.text = "Failed to host: " + error_string(err)
	else:
		status_label.text = "Lobby node not found!"

func _on_join_pressed() -> void:
	status_label.text = "Connecting..."
	if lobby:
		var err = lobby.join_game(address_input.text)
		if err != OK:
			status_label.text = "Failed to connect: " + error_string(err)
	else:
		status_label.text = "Lobby node not found!"
func _on_connection_succeeded() -> void:
	status_label.text = ""
	hide()
	var player = Globals.local_player
	if player and player.has_method("capture_mouse"):
		player.capture_mouse()


func _on_connection_failed() -> void:
	status_label.text = "Connection failed!"


func _on_server_disconnected() -> void:
	show()
	status_label.text = "Disconnected from server."
	var player = Globals.local_player
	if player and player.has_method("release_mouse"):
		player.release_mouse()
