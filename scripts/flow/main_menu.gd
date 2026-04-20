extends Control


const INTRO_SCENE_PATH: String = "res://scenes/flow/intro_sequence.tscn"

@onready var start_button: Button = $Paper/Margin/Content/StartButton


func _ready() -> void:
	start_button.pressed.connect(_on_start_button_pressed)
	start_button.grab_focus()


func _on_start_button_pressed() -> void:
	SessionState.reset_session()
	get_tree().change_scene_to_file(INTRO_SCENE_PATH)
