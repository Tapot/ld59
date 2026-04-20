extends Control


const GAME_SCENE_PATH: String = "res://scenes/flow/game.tscn"
const MAIN_MENU_SCENE_PATH: String = "res://scenes/flow/main_menu.tscn"
const UPGRADE_NODE_SCENE: PackedScene = preload("res://scenes/ui/meta/upgrade_node.tscn")
const POWERUP_SOUNDS: Array[AudioStream] = [
	preload("res://audio/ld59_powerup1.mp3"),
	preload("res://audio/ld59_powerup2.mp3"),
]
const POWERUP_PITCH_MIN: float = 0.9
const POWERUP_PITCH_MAX: float = 1.1

@onready var summary_label: Label = $ScreenMargin/ScreenLayout/HeaderRow/TitleColumn/SummaryLabel
@onready var runes_label: Label = $ScreenMargin/ScreenLayout/HeaderRow/TopRight/RunesLabel
@onready var spawn_again_button: Button = $ScreenMargin/ScreenLayout/HeaderRow/TopRight/ButtonsRow/SpawnAgainButton
@onready var main_menu_button: Button = $ScreenMargin/ScreenLayout/HeaderRow/TopRight/ButtonsRow/MainMenuButton
@onready var upgrade_grid: GridContainer = $ScreenMargin/ScreenLayout/GraphFrame/GraphScroll/UpgradeGrid
@onready var powerup_sfx: AudioStreamPlayer = $PowerupSfx


func _ready() -> void:
	SessionState.runes_changed.connect(_on_runes_changed)
	SessionState.upgrade_purchased.connect(_on_upgrade_purchased)
	spawn_again_button.pressed.connect(_on_spawn_again_button_pressed)
	main_menu_button.pressed.connect(_on_main_menu_button_pressed)
	spawn_again_button.grab_focus()
	_refresh_screen()


func _refresh_screen() -> void:
	_refresh_header()
	_rebuild_grid()


func _refresh_header() -> void:
	runes_label.text = "Runes: %d" % SessionState.get_runes()

	var status_text: String = "Last run: %d kills." % SessionState.get_last_run_kills()
	if SessionState.was_last_run_natural_end():
		status_text += " Spend runes or start the next run."
	else:
		status_text += " Exit opened upgrades directly."

	summary_label.text = status_text


func _rebuild_grid() -> void:
	for child: Node in upgrade_grid.get_children():
		child.queue_free()

	var visible_ids: Array[String] = SessionState.get_visible_upgrade_ids()
	for upgrade_id: String in visible_ids:
		var definition: Dictionary = SessionState.get_upgrade_definition(upgrade_id)
		var upgrade_node: UpgradeNode = UPGRADE_NODE_SCENE.instantiate() as UpgradeNode
		if upgrade_node == null:
			continue

		upgrade_grid.add_child(upgrade_node)
		upgrade_node.configure(definition, SessionState.get_upgrade_level(upgrade_id))
		upgrade_node.purchase_requested.connect(_on_purchase_requested)


func _on_purchase_requested(upgrade_id: String) -> void:
	if not SessionState.purchase_upgrade(upgrade_id):
		return

	Globals.suppress_next_button_click()
	_play_powerup_sfx()
	_refresh_screen()


func _play_powerup_sfx() -> void:
	powerup_sfx.stream = POWERUP_SOUNDS[randi() % POWERUP_SOUNDS.size()]
	powerup_sfx.pitch_scale = randf_range(POWERUP_PITCH_MIN, POWERUP_PITCH_MAX)
	powerup_sfx.play()


func _on_runes_changed(_total_runes: int) -> void:
	_refresh_header()


func _on_upgrade_purchased(_upgrade_id: String, _new_level: int) -> void:
	_refresh_screen()


func _on_spawn_again_button_pressed() -> void:
	SessionState.start_next_run()
	get_tree().change_scene_to_file(GAME_SCENE_PATH)


func _on_main_menu_button_pressed() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)
