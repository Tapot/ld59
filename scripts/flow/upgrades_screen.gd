extends Control


const GAME_SCENE_PATH: String = "res://scenes/flow/game.tscn"
const MAIN_MENU_SCENE_PATH: String = "res://scenes/flow/main_menu.tscn"

@onready var tier_label: Label = $Paper/Margin/Content/Header/TierLabel
@onready var summary_label: Label = $Paper/Margin/Content/Header/SummaryLabel
@onready var slot_label: Label = $Paper/Margin/Content/StatusRow/SlotLabel
@onready var summon_button: Button = $Paper/Margin/Content/ButtonsRow/SummonButton
@onready var main_menu_button: Button = $Paper/Margin/Content/ButtonsRow/MainMenuButton
@onready var cards_grid: GridContainer = $Paper/Margin/Content/CardsScroll/CardsGrid
@onready var population_counter = $PopulationCounter

var _card_buttons: Dictionary = {}
var _selection_was_valid: bool = false
var _loss_transition_started: bool = false


func _ready() -> void:
	Audio.play_music("rune_room", Audio.MUSIC_RUNE_ROOM)
	SessionState.selection_changed.connect(_refresh_screen)
	SessionState.tier_changed.connect(_on_tier_changed)
	SessionState.population_changed.connect(_on_population_changed)
	summon_button.pressed.connect(_on_summon_button_pressed)
	main_menu_button.pressed.connect(_on_main_menu_button_pressed)
	summon_button.grab_focus()
	_refresh_screen()


func _process(delta: float) -> void:
	if _loss_transition_started:
		return
	if SessionState.update_population(delta, SessionState.get_lingering_monster_drain_units(), true):
		_loss_transition_started = true
		SessionState.finish_run("loss", 0)
		get_tree().change_scene_to_file("res://scenes/flow/ending_screen.tscn")


func _refresh_screen() -> void:
	_refresh_header()
	_rebuild_cards()
	_refresh_buttons()


func _refresh_header() -> void:
	var last_summary: Dictionary = SessionState.get_last_run_summary()
	var summary_text: String = "Choose the runes for this tier. Selected rune effects apply in the next core run."
	if SessionState.is_selection_locked():
		summary_text = "Loadout locked. Finish every selected rune objective to unlock the next tier."
	elif not last_summary.is_empty():
		if bool(last_summary.get("tier_completed", false)):
			summary_text = "Tier %d unlocked. Pick a new loadout." % SessionState.get_current_tier()
		elif str(last_summary.get("outcome", "")) == "manual_exit":
			summary_text = "The run ended early. Lingering monsters will return."
		elif str(last_summary.get("outcome", "")) == "natural":
			summary_text = "The field is clear. If objectives remain, summon again."

	tier_label.text = "Tier %d / %d" % [SessionState.get_current_tier(), SessionState.get_total_tiers()]
	summary_label.text = summary_text
	population_counter.set_population_value(SessionState.format_population(SessionState.get_population_current()))
	slot_label.text = "Slots: %d / %d" % [SessionState.get_selected_rune_ids().size(), SessionState.get_unlocked_slots()]


func _rebuild_cards() -> void:
	_card_buttons.clear()
	for child: Node in cards_grid.get_children():
		child.queue_free()

	var selected_ids: Array[String] = SessionState.get_selected_rune_ids()
	for rune_config: Dictionary in SessionState.get_available_runes_for_current_tier():
		var rune_id: String = str(rune_config.get("id", ""))
		var card_button: Button = Button.new()
		card_button.toggle_mode = true
		card_button.custom_minimum_size = Vector2(0.0, 146.0)
		card_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		card_button.text = _format_rune_card_text(rune_config)
		card_button.button_pressed = selected_ids.has(rune_id)
		card_button.disabled = SessionState.is_selection_locked()
		card_button.pressed.connect(_on_rune_card_pressed.bind(rune_id))
		cards_grid.add_child(card_button)
		_card_buttons[rune_id] = card_button

	_refresh_card_states()


func _refresh_buttons() -> void:
	var selection_valid: bool = SessionState.is_selection_valid()
	summon_button.disabled = not selection_valid
	if selection_valid and not _selection_was_valid:
		_shake_summon_button()
	_selection_was_valid = selection_valid


func _refresh_card_states() -> void:
	var selected_ids: Array[String] = SessionState.get_selected_rune_ids()
	var slots_full: bool = selected_ids.size() >= SessionState.get_unlocked_slots()
	for rune_id: String in _card_buttons.keys():
		var card_button: Button = _card_buttons[rune_id] as Button
		if card_button == null:
			continue
		card_button.button_pressed = selected_ids.has(rune_id)
		if SessionState.is_selection_locked():
			card_button.disabled = true
			continue
		card_button.disabled = slots_full and not selected_ids.has(rune_id)


func _format_rune_card_text(rune_config: Dictionary) -> String:
	var drain_multiplier: float = float(rune_config.get("drain_multiplier", 1.0))
	var drain_text: String = "Drain x%.2f" % drain_multiplier
	var task_description: String = str(rune_config.get("task_description", ""))
	return "%s\n%s\n%s\nTask: %s\n%s" % [
		str(rune_config.get("title", "")),
		str(rune_config.get("family", "")),
		str(rune_config.get("description", "")),
		task_description,
		drain_text
	]


func _shake_summon_button() -> void:
	var tween: Tween = create_tween()
	tween.tween_property(summon_button, "rotation_degrees", -2.0, 0.06)
	tween.tween_property(summon_button, "rotation_degrees", 2.0, 0.06)
	tween.tween_property(summon_button, "rotation_degrees", 0.0, 0.06)


func _on_rune_card_pressed(rune_id: String) -> void:
	SessionState.toggle_rune_selection(rune_id)


func _on_summon_button_pressed() -> void:
	if not SessionState.start_run():
		return
	get_tree().change_scene_to_file(GAME_SCENE_PATH)


func _on_main_menu_button_pressed() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)


func _on_tier_changed(_current_tier: int, _highest_unlocked_tier: int) -> void:
	_refresh_screen()


func _on_population_changed(_current_population: int, _drain_per_second: int) -> void:
	population_counter.set_population_value(SessionState.format_population(SessionState.get_population_current()))
