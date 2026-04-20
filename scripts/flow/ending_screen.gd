extends Control


const MAIN_MENU_SCENE_PATH: String = "res://scenes/flow/main_menu.tscn"
const UPGRADES_SCENE_PATH: String = "res://scenes/flow/upgrades_screen.tscn"
const GAME_SCENE_PATH: String = "res://scenes/flow/game.tscn"
const MONSTER_ICON_SIZE: Vector2 = Vector2(34.0, 34.0)
const WINDOW_FADE_IN_DURATION: float = 0.32

@onready var title_label: Label = $Paper/Margin/Content/TitleLabel
@onready var summary_label: Label = $Paper/Margin/Content/SummaryLabel
@onready var results_scroll: ScrollContainer = $Paper/Margin/Content/ResultsScroll
@onready var killed_list: VBoxContainer = $Paper/Margin/Content/ResultsScroll/ResultsContent/KilledList
@onready var action_button: Button = $Paper/Margin/Content/ButtonsRow/ActionButton
@onready var population_counter = $PopulationCounter
@onready var paper: Panel = $Paper


func _ready() -> void:
	Audio.play_music("main_menu", Audio.MUSIC_MAIN_MENU)
	action_button.pressed.connect(_on_action_button_pressed)
	action_button.grab_focus()
	paper.modulate.a = 0.0
	_refresh_content()
	var fade_tween: Tween = create_tween()
	fade_tween.tween_property(paper, "modulate:a", 1.0, WINDOW_FADE_IN_DURATION)


func _refresh_content() -> void:
	var summary: Dictionary = SessionState.get_last_run_summary()
	var ending_mode: String = str(summary.get("ending_mode", "lose"))
	population_counter.set_population_value(SessionState.format_population(SessionState.get_population_current()))

	if ending_mode == "win":
		title_label.text = "The signal was recieved"
		summary_label.text = "You saved %s people" % SessionState.format_population(SessionState.get_population_current())
		results_scroll.visible = false
		action_button.text = "OK"
		return
	if ending_mode == "tier_complete":
		results_scroll.visible = true
		_rebuild_killed_monsters(summary)
		title_label.text = "Run Complete"
		summary_label.text = "All selected tasks are complete. Tier %d is unlocked." % int(summary.get("current_tier", SessionState.get_current_tier()))
		action_button.text = "OK"
		return
	if ending_mode == "retry":
		results_scroll.visible = true
		_rebuild_killed_monsters(summary)
		title_label.text = "Run Ended"
		summary_label.text = "Selected tasks are not complete yet. Spawn again to continue this tier."
		action_button.text = "Spawn Again"
		return

	results_scroll.visible = false
	title_label.text = "All gone"
	summary_label.text = ""
	action_button.text = "Try Again"


func _on_action_button_pressed() -> void:
	var summary: Dictionary = SessionState.get_last_run_summary()
	var ending_mode: String = str(summary.get("ending_mode", "lose"))
	if ending_mode == "tier_complete":
		get_tree().change_scene_to_file(UPGRADES_SCENE_PATH)
		return
	if ending_mode == "win":
		SessionState.reset_session()
		get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)
		return
	if ending_mode == "retry":
		get_tree().change_scene_to_file(GAME_SCENE_PATH)
		return
	SessionState.reset_session()
	get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)

func _rebuild_killed_monsters(summary: Dictionary) -> void:
	for child: Node in killed_list.get_children():
		child.queue_free()

	var killed_monsters: Dictionary = summary.get("killed_monsters", {})
	var monster_type_ids: Array[String] = []
	for monster_type_variant: Variant in killed_monsters.keys():
		monster_type_ids.append(str(monster_type_variant))
	monster_type_ids.sort()

	for monster_type_id: String in monster_type_ids:
		var count: int = int(killed_monsters.get(monster_type_id, 0))
		if count <= 0:
			continue

		var row: HBoxContainer = HBoxContainer.new()
		var icon_rect: TextureRect = TextureRect.new()
		var label: Label = Label.new()
		var texture_path: String = SessionState.get_monster_sprite_path(monster_type_id)
		var texture: Texture2D = null
		if not texture_path.is_empty():
			texture = load(texture_path) as Texture2D

		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 8)
		icon_rect.custom_minimum_size = MONSTER_ICON_SIZE
		icon_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.texture = texture
		label.text = "%s x %d" % [SessionState.get_monster_title(monster_type_id), count]
		row.add_child(icon_rect)
		row.add_child(label)
		killed_list.add_child(row)

	if killed_list.get_child_count() > 0:
		return

	var empty_label: Label = Label.new()
	empty_label.text = "No monsters killed."
	empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	killed_list.add_child(empty_label)
