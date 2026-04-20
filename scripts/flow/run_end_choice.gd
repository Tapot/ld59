extends Control


const GAME_SCENE_PATH: String = "res://scenes/flow/game.tscn"
const UPGRADES_SCENE_PATH: String = "res://scenes/flow/upgrades_screen.tscn"

@onready var summary_label: Label = $CenterPanel/Margin/Content/SummaryLabel
@onready var runes_label: Label = $CenterPanel/Margin/Content/RunesLabel
@onready var upgrades_button: Button = $CenterPanel/Margin/Content/ButtonsRow/UpgradesButton
@onready var spawn_again_button: Button = $CenterPanel/Margin/Content/ButtonsRow/SpawnAgainButton


func _ready() -> void:
	Audio.play_music("rune_room", Audio.MUSIC_RUNE_ROOM)
	upgrades_button.pressed.connect(_on_upgrades_button_pressed)
	spawn_again_button.pressed.connect(_on_spawn_again_button_pressed)
	spawn_again_button.grab_focus()
	_refresh_summary()


func _refresh_summary() -> void:
	summary_label.text = "Run complete. Kills: %d." % SessionState.get_last_run_kills()
	runes_label.text = "Runes banked: %d" % SessionState.get_runes()


func _on_upgrades_button_pressed() -> void:
	get_tree().change_scene_to_file(UPGRADES_SCENE_PATH)


func _on_spawn_again_button_pressed() -> void:
	SessionState.start_next_run()
	get_tree().change_scene_to_file(GAME_SCENE_PATH)
