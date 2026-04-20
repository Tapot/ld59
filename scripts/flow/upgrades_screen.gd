extends Control


const GAME_SCENE_PATH: String = "res://scenes/flow/game.tscn"
const MAIN_MENU_SCENE_PATH: String = "res://scenes/flow/main_menu.tscn"
const UI_FONT: FontFile = preload("res://assets/fonts/Jolly_Lodger/JollyLodger-Regular.ttf")
const SLOT_SIZE: Vector2 = Vector2(64, 64)
const RUNE_ICON_SIZE: Vector2 = Vector2(72, 72)
const SLOT_ICON_SIZE: Vector2 = Vector2(24, 24)
const RUNE_ICON_BASE_PATH: String = "res://assets/images/ui/runes_folder/"
const PAPER_FONT_COLOR: Color = Color.BLACK

@onready var tier_label: Label = $Paper/Margin/Content/Header/TierLabel
@onready var slot_label: Label = $Paper/Margin/Content/MainArea/RightPanel/SlotLabel
@onready var summon_button: Button = $Paper/Margin/Content/MainArea/RightPanel/ButtonsRow/SummonButton
@onready var main_menu_button: Button = $Paper/Margin/Content/MainArea/RightPanel/ButtonsRow/MainMenuButton
@onready var rune_list: VBoxContainer = $Paper/Margin/Content/MainArea/LeftPanel/RuneListScroll/RuneList
@onready var rune_list_scroll: ScrollContainer = $Paper/Margin/Content/MainArea/LeftPanel/RuneListScroll
@onready var pyramid_container: VBoxContainer = $Paper/Margin/Content/MainArea/RightPanel/PyramidScroll/PyramidContainer
@onready var pyramid_scroll: ScrollContainer = $Paper/Margin/Content/MainArea/RightPanel/PyramidScroll
@onready var population_counter = $PopulationCounter

var _powerup_player: AudioStreamPlayer
var _rune_cards: Dictionary = {}
var _slot_panels: Array[PanelContainer] = []
var _slot_icons: Array[TextureRect] = []
var _slot_labels: Array[Label] = []
var _highlighted_rune_id: String = ""
var _confirm_buttons: Dictionary = {}
var _card_panels: Dictionary = {}
var _selection_was_valid: bool = false
var _loss_transition_started: bool = false
var _population_ui_accum: float = 0.0
const POPULATION_UI_INTERVAL: float = 0.2


func _ready() -> void:
	Audio.play_music("rune_room", Audio.MUSIC_RUNE_ROOM)
	# DEBUG: unlock all tiers and max slots — uncomment to test full rune screen
	#SessionState._current_tier = SessionState.get_total_tiers()
	#SessionState._highest_unlocked_tier = SessionState._current_tier
	#SessionState._unlocked_slots = SessionState.MAX_UNLOCKED_SLOTS
	#SessionState._selection_locked = false
	_powerup_player = AudioStreamPlayer.new()
	_powerup_player.bus = "Master"
	add_child(_powerup_player)
	SessionState.selection_changed.connect(_refresh_screen)
	SessionState.tier_changed.connect(_on_tier_changed)
	SessionState.population_changed.connect(_on_population_changed)
	summon_button.pressed.connect(_on_summon_button_pressed)
	main_menu_button.pressed.connect(_on_main_menu_button_pressed)
	summon_button.grab_focus()
	_build_pyramid()
	_refresh_screen()
	_scroll_rune_list_to_bottom.call_deferred()
	_scroll_pyramid_to_top.call_deferred()


func _process(delta: float) -> void:
	if _loss_transition_started:
		return
	if SessionState.update_population(delta, SessionState.get_lingering_monster_drain_units(), true):
		_loss_transition_started = true
		SessionState.finish_run("loss", 0)
		get_tree().change_scene_to_file("res://scenes/flow/ending_screen.tscn")
		return
	_population_ui_accum += delta
	if _population_ui_accum >= POPULATION_UI_INTERVAL:
		_population_ui_accum = 0.0
		population_counter.set_population_value(SessionState.format_population(SessionState.get_population_current()))
		_refresh_population_progress()


func _refresh_screen() -> void:
	_refresh_header()
	_rebuild_rune_list()
	_refresh_pyramid()
	_refresh_buttons()


func _refresh_header() -> void:
	tier_label.text = "Tier %d / %d" % [SessionState.get_current_tier(), SessionState.get_total_tiers()]
	population_counter.set_population_value(SessionState.format_population(SessionState.get_population_current()))
	_refresh_population_progress()
	slot_label.text = "Slots: %d / %d" % [SessionState.get_selected_rune_ids().size(), SessionState.get_unlocked_slots()]


func _refresh_population_progress() -> void:
	var start_pop: int = SessionState.get_population_start()
	var ratio: float = float(SessionState.get_population_current()) / float(start_pop) if start_pop > 0 else 0.0
	population_counter.set_progress(ratio)


func _build_pyramid() -> void:
	_slot_panels.clear()
	_slot_icons.clear()
	_slot_labels.clear()
	for child: Node in pyramid_container.get_children():
		child.queue_free()

	var current_tier: int = SessionState.get_current_tier()

	# Past tiers: one row per tier, read-only, icon+name filled
	for tier: int in range(1, current_tier):
		var past_runes: Array[String] = SessionState.get_completed_rune_ids_for_tier(tier)
		var row: HBoxContainer = HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_BEGIN
		row.add_theme_constant_override("separation", 6)

		var row_size: int = _get_tier_slot_count(tier)
		for i: int in row_size:
			var panel: PanelContainer = _make_slot_panel()
			var rune_id: String = past_runes[i] if i < past_runes.size() else ""
			if rune_id.is_empty():
				_fill_slot_as_empty(panel, false)
			else:
				var rune_config: Dictionary = SessionState.get_rune_config(rune_id)
				_fill_slot_as_past(panel, rune_config)
			row.add_child(panel)

		pyramid_container.add_child(row)

	# Current tier row: interactive empty/filled slots
	var current_row: HBoxContainer = HBoxContainer.new()
	current_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	current_row.add_theme_constant_override("separation", 6)

	var unlocked: int = SessionState.get_unlocked_slots()
	for i: int in unlocked:
		var panel: PanelContainer = _make_slot_panel()
		var slot_index: int = i
		panel.gui_input.connect(_on_slot_gui_input.bind(slot_index))
		current_row.add_child(panel)
		_slot_panels.append(panel)

		var slot_content: VBoxContainer = panel.get_child(0) as VBoxContainer
		var icon: TextureRect = slot_content.get_child(0) as TextureRect
		var name_label: Label = slot_content.get_child(1) as Label
		_slot_icons.append(icon)
		_slot_labels.append(name_label)

	pyramid_container.add_child(current_row)


func _get_tier_slot_count(tier: int) -> int:
	var config: Dictionary = SessionState._tier_definitions.get(tier, {})
	return maxi(1, int(config.get("slots", 1)))


func _make_slot_panel() -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = SLOT_SIZE

	var slot_content: VBoxContainer = VBoxContainer.new()
	slot_content.alignment = BoxContainer.ALIGNMENT_CENTER
	slot_content.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var icon: TextureRect = TextureRect.new()
	icon.custom_minimum_size = SLOT_ICON_SIZE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot_content.add_child(icon)

	var name_label: Label = Label.new()
	name_label.add_theme_font_override("font", UI_FONT)
	name_label.add_theme_color_override("font_color", PAPER_FONT_COLOR)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 9)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.clip_text = true
	name_label.custom_minimum_size = Vector2(0, 24)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot_content.add_child(name_label)

	panel.add_child(slot_content)
	return panel


func _fill_slot_as_past(panel: PanelContainer, rune_config: Dictionary) -> void:
	var slot_content: VBoxContainer = panel.get_child(0) as VBoxContainer
	var icon: TextureRect = slot_content.get_child(0) as TextureRect
	var name_label: Label = slot_content.get_child(1) as Label
	var title: String = str(rune_config.get("title", "?"))
	icon.visible = true
	icon.texture = _get_rune_icon(rune_config)
	name_label.text = title
	name_label.remove_theme_font_size_override("font_size")
	name_label.add_theme_font_size_override("font_size", 9)
	panel.tooltip_text = title
	panel.add_theme_stylebox_override("panel", _make_slot_style_past())
	panel.mouse_default_cursor_shape = Control.CURSOR_ARROW


func _fill_slot_as_empty(panel: PanelContainer, highlighted: bool) -> void:
	var slot_content: VBoxContainer = panel.get_child(0) as VBoxContainer
	var icon: TextureRect = slot_content.get_child(0) as TextureRect
	var name_label: Label = slot_content.get_child(1) as Label
	icon.visible = false
	icon.texture = null
	name_label.text = "?"
	name_label.remove_theme_font_size_override("font_size")
	name_label.add_theme_font_size_override("font_size", 32)
	panel.tooltip_text = "Empty slot"
	if highlighted:
		panel.add_theme_stylebox_override("panel", _make_slot_style_current_empty())
	else:
		panel.add_theme_stylebox_override("panel", _make_slot_style_empty())
	panel.mouse_default_cursor_shape = Control.CURSOR_ARROW


func _make_slot_style_empty() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.06)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.4, 0.35, 0.28, 0.3)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style


func _make_slot_style_filled() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.35, 0.2, 0.2)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.3, 0.5, 0.3, 0.5)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style


func _on_slot_gui_input(event: InputEvent, slot_index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_slot_pressed(slot_index)


func _refresh_pyramid() -> void:
	var selected_ids: Array[String] = SessionState.get_selected_rune_ids()
	var locked: bool = SessionState.is_selection_locked()
	for i: int in _slot_panels.size():
		var slot_panel: PanelContainer = _slot_panels[i]
		var icon: TextureRect = _slot_icons[i]
		var name_label: Label = _slot_labels[i]
		if i < selected_ids.size():
			var rune_config: Dictionary = SessionState.get_rune_config(selected_ids[i])
			var title: String = str(rune_config.get("title", "?"))
			icon.visible = true
			icon.texture = _get_rune_icon(rune_config)
			name_label.text = title
			name_label.remove_theme_font_size_override("font_size")
			name_label.add_theme_font_size_override("font_size", 9)
			slot_panel.tooltip_text = title + "\nClick to remove"
			slot_panel.add_theme_stylebox_override("panel", _make_slot_style_current_filled())
			slot_panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if not locked else Control.CURSOR_ARROW
		else:
			_fill_slot_as_empty(slot_panel, true)


func _make_slot_style_past() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.25, 0.15, 0.18)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.25, 0.4, 0.25, 0.45)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style


func _make_slot_style_current_empty() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.35, 0.25, 0.1, 0.18)
	style.border_width_left = 3
	style.border_width_top = 3
	style.border_width_right = 3
	style.border_width_bottom = 3
	style.border_color = Color(0.95, 0.75, 0.25, 0.95)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style


func _make_slot_style_current_filled() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.35, 0.2, 0.25)
	style.border_width_left = 3
	style.border_width_top = 3
	style.border_width_right = 3
	style.border_width_bottom = 3
	style.border_color = Color(0.95, 0.75, 0.25, 0.95)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style


func _rebuild_rune_list() -> void:
	_rune_cards.clear()
	_confirm_buttons.clear()
	_card_panels.clear()
	_highlighted_rune_id = ""
	for child: Node in rune_list.get_children():
		child.queue_free()

	var selected_ids: Array[String] = SessionState.get_selected_rune_ids()
	var locked: bool = SessionState.is_selection_locked()
	var slots_full: bool = selected_ids.size() >= SessionState.get_unlocked_slots()

	for rune_config: Dictionary in SessionState.get_available_runes_for_current_tier():
		var rune_id: String = str(rune_config.get("id", ""))
		var is_selected: bool = selected_ids.has(rune_id)

		# --- Card panel background ---
		var panel: PanelContainer = PanelContainer.new()
		panel.add_theme_stylebox_override("panel", _make_card_style(is_selected))
		panel.gui_input.connect(_on_card_gui_input.bind(rune_id))
		panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

		# --- Horizontal: [content | equip button] ---
		var h_root: HBoxContainer = HBoxContainer.new()
		h_root.add_theme_constant_override("separation", 12)
		h_root.mouse_filter = Control.MOUSE_FILTER_IGNORE

		# --- Left: content column ---
		var content: VBoxContainer = VBoxContainer.new()
		content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content.add_theme_constant_override("separation", 4)
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var title_label: Label = Label.new()
		title_label.text = str(rune_config.get("title", ""))
		title_label.add_theme_font_override("font", UI_FONT)
		title_label.add_theme_color_override("font_color", PAPER_FONT_COLOR)
		title_label.add_theme_font_size_override("font_size", 22)
		title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(title_label)

		var body_row: HBoxContainer = HBoxContainer.new()
		body_row.add_theme_constant_override("separation", 8)
		body_row.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var icon: TextureRect = TextureRect.new()
		icon.texture = _get_rune_icon(rune_config)
		icon.custom_minimum_size = RUNE_ICON_SIZE
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body_row.add_child(icon)

		var desc_label: Label = Label.new()
		desc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_label.text = str(rune_config.get("description", ""))
		desc_label.add_theme_font_override("font", UI_FONT)
		desc_label.add_theme_color_override("font_color", PAPER_FONT_COLOR)
		desc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body_row.add_child(desc_label)

		content.add_child(body_row)

		var task_label: Label = Label.new()
		task_label.text = "Task: %s" % str(rune_config.get("task_description", ""))
		task_label.add_theme_font_override("font", UI_FONT)
		task_label.add_theme_color_override("font_color", PAPER_FONT_COLOR)
		task_label.add_theme_font_size_override("font_size", 14)
		task_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(task_label)

		var drain_label: Label = Label.new()
		drain_label.text = "Drain x%.2f" % float(rune_config.get("drain_multiplier", 1.0))
		drain_label.add_theme_font_override("font", UI_FONT)
		drain_label.add_theme_color_override("font_color", PAPER_FONT_COLOR)
		drain_label.add_theme_font_size_override("font_size", 14)
		drain_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(drain_label)

		h_root.add_child(content)

		# --- Right: equip/remove button, vertically centered ---
		var btn_container: CenterContainer = CenterContainer.new()
		btn_container.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var confirm_btn: Button = Button.new()
		confirm_btn.custom_minimum_size = Vector2(80, 36)
		confirm_btn.add_theme_font_override("font", UI_FONT)
		if is_selected:
			confirm_btn.text = "Remove"
			confirm_btn.visible = true
		else:
			confirm_btn.text = "Equip"
			confirm_btn.visible = false
		confirm_btn.disabled = locked or (slots_full and not is_selected)
		confirm_btn.pressed.connect(_on_rune_confirm_pressed.bind(rune_id))
		btn_container.add_child(confirm_btn)
		_confirm_buttons[rune_id] = confirm_btn

		h_root.add_child(btn_container)

		panel.add_child(h_root)
		rune_list.add_child(panel)
		_rune_cards[rune_id] = panel
		_card_panels[rune_id] = panel


func _make_card_style(is_selected: bool) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	if is_selected:
		style.bg_color = Color(0.28, 0.46, 0.24, 0.25)
	else:
		style.bg_color = Color(0.0, 0.0, 0.0, 0.08)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style


func _get_rune_icon(rune_config: Dictionary) -> Texture2D:
	var rune_id: String = str(rune_config.get("id", ""))
	var icon_name: String = rune_id
	match rune_id:
		"damage_focus_1":
			icon_name = "damage_icon_1"
		"damage_focus_2":
			icon_name = "damage_icon_2"
		"damage_focus_3":
			icon_name = "damage_icon_3"
		"damage_hold_1":
			icon_name = "signal_hold_1"
		"damage_stasis_1":
			icon_name = "stasis_field_1"
		"rupture_kill_1":
			icon_name = "rupture_projectile_1"
		"rupture_damage_1":
			icon_name = "rupture_payload_1"
		"rupture_shards_1":
			icon_name = "rupture_multishot_1"
		"rupture_lifetime_1":
			icon_name = "long_fuse_1"
		"rupture_pierce_1":
			icon_name = "needle_chain_1"
		"rupture_bounce_1":
			icon_name = "ricochet_1"
	var texture: Texture2D = load("%s%s.png" % [RUNE_ICON_BASE_PATH, icon_name]) as Texture2D
	return texture


func _on_card_gui_input(event: InputEvent, rune_id: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_rune_card_clicked(rune_id)


func _refresh_buttons() -> void:
	var selection_valid: bool = SessionState.is_selection_valid()
	summon_button.disabled = not selection_valid
	if selection_valid:
		summon_button.tooltip_text = "Start the run with the equipped runes."
	else:
		var selected_count: int = SessionState.get_selected_rune_ids().size()
		var unlocked: int = SessionState.get_unlocked_slots()
		if selected_count < unlocked:
			summon_button.tooltip_text = "Equip %d more rune%s to summon.\nChoose runes from the left and click Equip." % [
				unlocked - selected_count,
				"" if (unlocked - selected_count) == 1 else "s"
			]
		else:
			summon_button.tooltip_text = "Cannot summon right now."
	if selection_valid and not _selection_was_valid:
		_shake_summon_button()
	_selection_was_valid = selection_valid


func _play_powerup_sound() -> void:
	var sound: AudioStream = Audio.POWERUP_SOUNDS[randi() % Audio.POWERUP_SOUNDS.size()]
	_powerup_player.stream = sound
	_powerup_player.pitch_scale = randf_range(0.9, 1.1)
	Audio.suppress_next_button_click()
	_powerup_player.play()


func _scroll_rune_list_to_bottom() -> void:
	rune_list_scroll.scroll_vertical = rune_list_scroll.get_v_scroll_bar().max_value as int


func _scroll_pyramid_to_top() -> void:
	pyramid_scroll.scroll_vertical = pyramid_scroll.get_v_scroll_bar().max_value as int


func _shake_summon_button() -> void:
	var tween: Tween = create_tween()
	tween.tween_property(summon_button, "rotation_degrees", -2.0, 0.06)
	tween.tween_property(summon_button, "rotation_degrees", 2.0, 0.06)
	tween.tween_property(summon_button, "rotation_degrees", 0.0, 0.06)


func _on_rune_card_clicked(rune_id: String) -> void:
	if _highlighted_rune_id == rune_id:
		_highlighted_rune_id = ""
		_update_confirm_visibility()
		return
	_highlighted_rune_id = rune_id
	_update_confirm_visibility()


func _update_confirm_visibility() -> void:
	var selected_ids: Array[String] = SessionState.get_selected_rune_ids()
	for rid: String in _confirm_buttons.keys():
		var btn: Button = _confirm_buttons[rid] as Button
		if btn == null:
			continue
		var is_selected: bool = selected_ids.has(rid)
		var is_highlighted: bool = rid == _highlighted_rune_id
		btn.visible = is_highlighted or is_selected
		if is_selected:
			btn.text = "Remove"
		else:
			btn.text = "Equip"
		var panel: PanelContainer = _card_panels.get(rid) as PanelContainer
		if panel != null:
			if is_selected:
				panel.add_theme_stylebox_override("panel", _make_card_style(true))
			elif is_highlighted:
				var hl_style: StyleBoxFlat = _make_card_style(false)
				hl_style.bg_color = Color(0.0, 0.0, 0.0, 0.15)
				panel.add_theme_stylebox_override("panel", hl_style)
			else:
				panel.add_theme_stylebox_override("panel", _make_card_style(false))


func _on_rune_confirm_pressed(rune_id: String) -> void:
	var is_selected: bool = SessionState.get_selected_rune_ids().has(rune_id)
	if not is_selected:
		_play_powerup_sound()
	_highlighted_rune_id = ""
	SessionState.toggle_rune_selection(rune_id)


func _on_slot_pressed(slot_index: int) -> void:
	var selected_ids: Array[String] = SessionState.get_selected_rune_ids()
	if slot_index >= selected_ids.size():
		return
	SessionState.toggle_rune_selection(selected_ids[slot_index])


func _on_summon_button_pressed() -> void:
	# DEBUG: advance to next tier instead of starting run — comment out before commit
	#_debug_advance_tier()
	#return
	if not SessionState.start_run():
		return
	get_tree().change_scene_to_file(GAME_SCENE_PATH)


# DEBUG: skip the run and bump straight to the next tier
func _debug_advance_tier() -> void:
	var next_tier: int = mini(SessionState.get_total_tiers(), SessionState.get_current_tier() + 1)
	SessionState._completed_rune_ids_by_tier[SessionState._current_tier] = SessionState._selected_rune_ids.duplicate()
	SessionState._current_tier = next_tier
	SessionState._highest_unlocked_tier = maxi(SessionState._highest_unlocked_tier, next_tier)
	SessionState._selected_rune_ids.clear()
	SessionState._selected_rune_progress.clear()
	SessionState._selection_locked = false
	SessionState._sync_unlocked_slots_to_current_tier()
	SessionState.tier_changed.emit(SessionState._current_tier, SessionState._highest_unlocked_tier)
	SessionState.selection_changed.emit()
	SessionState.objectives_changed.emit()


func _on_main_menu_button_pressed() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)


func _on_tier_changed(_current_tier: int, _highest_unlocked_tier: int) -> void:
	_build_pyramid()
	_refresh_screen()
	_scroll_pyramid_to_top.call_deferred()


func _on_population_changed(_current_population: int, _drain_per_second: int) -> void:
	# Throttled via _process; intentionally no-op here to avoid per-tick UI updates.
	pass
