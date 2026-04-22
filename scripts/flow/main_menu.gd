extends Control


const INTRO_SCENE_PATH: String = "res://scenes/flow/intro_sequence.tscn"

@onready var start_button: Button = $Content/StartButton


func _ready() -> void:
	Audio.play_music("main_menu", Audio.MUSIC_MAIN_MENU)
	start_button.pressed.connect(_on_start_button_pressed)
	start_button.grab_focus()
	# DEBUG: skip to battle scene — uncomment to fast-track
	#SessionState.reset_session()
	#get_tree().change_scene_to_file("res://scenes/flow/upgrades_screen.tscn")
	#return


func _on_start_button_pressed() -> void:
	SessionState.reset_session()
	get_tree().change_scene_to_file(INTRO_SCENE_PATH)
