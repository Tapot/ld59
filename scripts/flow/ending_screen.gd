extends Control


const INTRO_SCENE_PATH: String = "res://scenes/flow/intro_sequence.tscn"
const MAIN_MENU_SCENE_PATH: String = "res://scenes/flow/main_menu.tscn"

@onready var title_label: Label = $Paper/Margin/Content/TitleLabel
@onready var summary_label: Label = $Paper/Margin/Content/SummaryLabel
@onready var action_button: Button = $Paper/Margin/Content/ButtonsRow/ActionButton
@onready var menu_button: Button = $Paper/Margin/Content/ButtonsRow/MenuButton
@onready var population_counter = $PopulationCounter


func _ready() -> void:
	action_button.pressed.connect(_on_action_button_pressed)
	menu_button.pressed.connect(_on_menu_button_pressed)
	action_button.grab_focus()
	_refresh_content()


func _refresh_content() -> void:
	var summary: Dictionary = SessionState.get_last_run_summary()
	var ending_mode: String = str(summary.get("ending_mode", "lose"))
	population_counter.set_population_value(SessionState.format_population(SessionState.get_population_current()))
	if ending_mode == "win":
		title_label.text = "Signal Delivered"
		summary_label.text = "You Saved %s People" % SessionState.format_population(SessionState.get_population_current())
		action_button.text = "Begin Again"
		return

	title_label.text = "Extinction"
	summary_label.text = "The last human is gone."
	action_button.text = "Try Again"


func _on_action_button_pressed() -> void:
	SessionState.reset_session()
	get_tree().change_scene_to_file(INTRO_SCENE_PATH)


func _on_menu_button_pressed() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)
