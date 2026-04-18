extends Control


const GAME_SCENE_PATH: String = "res://scenes/flow/game.tscn"


func _ready() -> void:
	var start_button: Button = $StartButton
	start_button.pressed.connect(_on_start_button_pressed)
	start_button.grab_focus()


func _on_start_button_pressed() -> void:
	SessionState.reset_session()
	SessionState.start_next_run()
	get_tree().change_scene_to_file(GAME_SCENE_PATH)
