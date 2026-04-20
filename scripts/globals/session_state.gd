extends Node


signal selection_changed()
signal objectives_changed()
signal population_changed(current_population: int, drain_per_second: int)
signal tier_changed(current_tier: int, highest_unlocked_tier: int)
signal run_started(run_index: int)
signal run_finished(summary: Dictionary)
signal session_reset()


const MONSTERS_CONFIG_PATH: String = "res://data/game/monsters.json"
const RUNES_CONFIG_PATH: String = "res://data/game/runes.json"
const TIERS_CONFIG_PATH: String = "res://data/game/tiers.json"
const POPULATION_CONFIG_PATH: String = "res://data/game/population.json"
const RUN_CONFIG_PATH: String = "res://data/game/run.json"
const MAX_UNLOCKED_SLOTS: int = 7

var _monster_definitions: Dictionary = {}
var _rune_definitions: Dictionary = {}
var _tier_definitions: Dictionary = {}
var _tier_numbers: Array[int] = []
var _population_config: Dictionary = {}
var _run_config: Dictionary = {}

var _current_tier: int = 1
var _highest_unlocked_tier: int = 1
var _unlocked_slots: int = 1
var _selected_rune_ids: Array[String] = []
var _selection_locked: bool = false
var _selected_rune_progress: Dictionary = {}
var _population_start: int = 0
var _population_current: int = 0
var _elapsed_run_time: float = 0.0
var _active_run_index: int = 0
var _run_active: bool = false
var _lingering_monsters: Array[Dictionary] = []
var _last_run_summary: Dictionary = {}
var _drain_per_second: int = 0
var _population_tick_remainder: float = 0.0


func _ready() -> void:
	_load_game_data()
	reset_session()


func reset_session() -> void:
	_load_game_data()
	_current_tier = 1
	_highest_unlocked_tier = 1
	_unlocked_slots = 1
	_selected_rune_ids.clear()
	_selection_locked = false
	_selected_rune_progress.clear()
	_population_start = int(_run_config.get("starting_population", 8153742618))
	_population_current = _population_start
	_elapsed_run_time = 0.0
	_active_run_index = 0
	_run_active = false
	_lingering_monsters.clear()
	_last_run_summary = {}
	_drain_per_second = 0
	_population_tick_remainder = 0.0
	session_reset.emit()
	tier_changed.emit(_current_tier, _highest_unlocked_tier)
	selection_changed.emit()
	objectives_changed.emit()
	population_changed.emit(_population_current, _drain_per_second)


func get_current_tier() -> int:
	return _current_tier


func get_highest_unlocked_tier() -> int:
	return _highest_unlocked_tier


func get_total_tiers() -> int:
	return _tier_numbers.size()


func get_unlocked_slots() -> int:
	return _unlocked_slots


func is_selection_locked() -> bool:
	return _selection_locked


func is_run_active() -> bool:
	return _run_active


func get_last_run_summary() -> Dictionary:
	return _last_run_summary.duplicate(true)


func get_population_start() -> int:
	return _population_start


func get_population_current() -> int:
	return _population_current


func set_population_current(value: int) -> void:
	_population_current = clampi(value, 0, _population_start)
	population_changed.emit(_population_current, _drain_per_second)


func get_current_drain_per_second() -> int:
	return _drain_per_second


func get_intro_counter_duration() -> float:
	return maxf(0.5, float(_run_config.get("intro_counter_duration", 1.8)))


func get_intro_preview_loss() -> int:
	var preview_loss_seconds: float = maxf(0.0, float(_run_config.get("intro_preview_loss_seconds", 2.0)))
	var base_drain: float = maxf(0.0, float(_population_config.get("base_drain", 1.0)))
	return maxi(0, int(round(base_drain * preview_loss_seconds)))


func get_run_attack_input_action() -> String:
	return str(_run_config.get("attack_input_action", "attack_hold"))


func is_manual_exit_enabled() -> bool:
	return bool(_run_config.get("manual_exit_enabled", true))


func should_carry_over_monsters() -> bool:
	return bool(_run_config.get("carry_over_enabled", true))


func get_base_group_interval() -> float:
	return maxf(0.05, float(_run_config.get("time_between_groups", 0.65)))


func get_current_tier_config() -> Dictionary:
	return _tier_definitions.get(_current_tier, {}).duplicate(true)


func get_monster_config(monster_type_id: String) -> Dictionary:
	return _monster_definitions.get(monster_type_id, {}).duplicate(true)


func get_monster_title(monster_type_id: String) -> String:
	var config: Dictionary = _monster_definitions.get(monster_type_id, {})
	var title: String = str(config.get("title", ""))
	if not title.is_empty():
		return title
	return monster_type_id.capitalize()


func get_rune_config(rune_id: String) -> Dictionary:
	return _rune_definitions.get(rune_id, {}).duplicate(true)


func get_available_runes_for_current_tier() -> Array[Dictionary]:
	var tier_config: Dictionary = get_current_tier_config()
	var available_ids: Array[String] = _array_variant_to_string_array(tier_config.get("available_runes", []))
	var runes: Array[Dictionary] = []
	for rune_id: String in available_ids:
		var rune_config: Dictionary = get_rune_config(rune_id)
		if rune_config.is_empty():
			continue
		runes.append(rune_config)
	return runes


func get_selected_rune_ids() -> Array[String]:
	return _selected_rune_ids.duplicate()


func set_selected_rune_ids(rune_ids: Array[String]) -> void:
	if _selection_locked:
		return

	var next_selection: Array[String] = []
	var allowed_ids: Dictionary = {}
	var available_runes: Array[Dictionary] = get_available_runes_for_current_tier()
	for rune_config: Dictionary in available_runes:
		allowed_ids[str(rune_config.get("id", ""))] = true

	for rune_id: String in rune_ids:
		if rune_id.is_empty():
			continue
		if not allowed_ids.has(rune_id):
			continue
		if next_selection.has(rune_id):
			continue
		if next_selection.size() >= _unlocked_slots:
			break
		next_selection.append(rune_id)

	_selected_rune_ids = next_selection
	selection_changed.emit()
	objectives_changed.emit()


func toggle_rune_selection(rune_id: String) -> void:
	if _selection_locked:
		return

	var next_selection: Array[String] = get_selected_rune_ids()
	if next_selection.has(rune_id):
		next_selection.erase(rune_id)
	else:
		next_selection.append(rune_id)
	set_selected_rune_ids(next_selection)


func is_selection_valid() -> bool:
	if _selected_rune_ids.is_empty():
		return false
	if _selected_rune_ids.size() > _unlocked_slots:
		return false

	var allowed_ids: Dictionary = {}
	var available_runes: Array[Dictionary] = get_available_runes_for_current_tier()
	for rune_config: Dictionary in available_runes:
		allowed_ids[str(rune_config.get("id", ""))] = true

	for rune_id: String in _selected_rune_ids:
		if not allowed_ids.has(rune_id):
			return false
	return true


func start_run() -> bool:
	if not is_selection_valid():
		return false

	_run_active = true
	_selection_locked = true
	_active_run_index += 1
	_elapsed_run_time = 0.0
	_drain_per_second = 0.0
	_initialize_objective_progress()
	selection_changed.emit()
	objectives_changed.emit()
	run_started.emit(_active_run_index)
	return true


func finish_run(outcome: String, kill_count: int) -> Dictionary:
	_run_active = false

	var tier_completed: bool = are_selected_rune_objectives_complete()
	var ending_mode: String = ""
	var next_scene_path: String = "res://scenes/flow/upgrades_screen.tscn"
	var previous_tier: int = _current_tier
	var next_tier: int = _current_tier

	if outcome == "loss" or _population_current <= 0.0:
		_population_current = 0
		ending_mode = "lose"
		next_scene_path = "res://scenes/flow/ending_screen.tscn"
	elif tier_completed:
		_apply_completed_rune_rewards()
		if _current_tier >= get_total_tiers():
			ending_mode = "win"
			next_scene_path = "res://scenes/flow/ending_screen.tscn"
		else:
			next_tier = mini(get_total_tiers(), _current_tier + 1)
			_current_tier = next_tier
			_highest_unlocked_tier = maxi(_highest_unlocked_tier, _current_tier)
			_selected_rune_ids.clear()
			_selected_rune_progress.clear()
			_selection_locked = false
			tier_changed.emit(_current_tier, _highest_unlocked_tier)
			selection_changed.emit()
			objectives_changed.emit()

	_last_run_summary = {
		"outcome": outcome,
		"kill_count": maxi(0, kill_count),
		"tier_completed": tier_completed,
		"ending_mode": ending_mode,
		"previous_tier": previous_tier,
		"current_tier": _current_tier,
		"next_tier": next_tier,
		"population_current": _population_current
	}

	run_finished.emit(_last_run_summary.duplicate(true))
	return {
		"next_scene_path": next_scene_path,
		"ending_mode": ending_mode
	}


func update_population(delta: float, active_monster_drain_units: float, allow_outside_run: bool = false) -> bool:
	if not _run_active and not allow_outside_run:
		return false
	if _population_current <= 0:
		return true

	_elapsed_run_time += maxf(0.0, delta)

	var base_drain: float = maxf(0.0, float(_population_config.get("base_drain", 1.0)))
	var time_scaling: float = maxf(0.0, float(_population_config.get("time_scaling", 0.0)))
	var rune_scaling: float = float(_population_config.get("rune_scaling", 0.0))
	var monster_scaling: float = maxf(0.0, float(_population_config.get("monster_scaling", 0.0)))
	var rune_units: float = _get_total_rune_drain_units() + get_effect_total("population_drain_multiplier_delta")
	var time_factor: float = 1.0 + (_elapsed_run_time * time_scaling)
	var rune_factor: float = maxf(0.1, 1.0 + (rune_units * rune_scaling))
	var monster_factor: float = maxf(0.1, 1.0 + (active_monster_drain_units * monster_scaling))

	var drain_value: float = base_drain * time_factor * rune_factor * monster_factor
	_drain_per_second = maxi(1, int(round(drain_value)))
	_population_tick_remainder += drain_value * maxf(0.0, delta)
	var loss_amount: int = int(floor(_population_tick_remainder))
	if loss_amount > 0:
		_population_tick_remainder -= float(loss_amount)
		_population_current = maxi(0, _population_current - loss_amount)
	population_changed.emit(_population_current, _drain_per_second)
	return _population_current <= 0


func register_monster_kill(monster_type_id: String) -> void:
	if _selected_rune_ids.is_empty():
		return

	var did_change: bool = false
	for rune_id: String in _selected_rune_ids:
		var rune_config: Dictionary = _rune_definitions.get(rune_id, {})
		var objective: Dictionary = rune_config.get("objective", {})
		if str(objective.get("monster_type", "")) != monster_type_id:
			continue

		var target_count: int = maxi(0, int(objective.get("count", 0)))
		var current_value: int = maxi(0, int(_selected_rune_progress.get(rune_id, 0)))
		var next_value: int = mini(target_count, current_value + 1)
		if next_value == current_value:
			continue

		_selected_rune_progress[rune_id] = next_value
		did_change = true

	if did_change:
		objectives_changed.emit()


func get_selected_objectives() -> Array[Dictionary]:
	var objectives: Array[Dictionary] = []
	for rune_id: String in _selected_rune_ids:
		var rune_config: Dictionary = _rune_definitions.get(rune_id, {})
		if rune_config.is_empty():
			continue

		var objective: Dictionary = rune_config.get("objective", {})
		var target_count: int = maxi(0, int(objective.get("count", 0)))
		var current_value: int = maxi(0, int(_selected_rune_progress.get(rune_id, 0)))
		var monster_type_id: String = str(objective.get("monster_type", ""))
		objectives.append({
			"rune_id": rune_id,
			"title": str(rune_config.get("title", rune_id)),
			"family": str(rune_config.get("family", "")),
			"monster_type": monster_type_id,
			"monster_title": get_monster_title(monster_type_id),
			"current": current_value,
			"target": target_count,
			"complete": current_value >= target_count and target_count > 0
		})
	return objectives


func are_selected_rune_objectives_complete() -> bool:
	var objectives: Array[Dictionary] = get_selected_objectives()
	if objectives.is_empty():
		return false

	for objective: Dictionary in objectives:
		if not bool(objective.get("complete", false)):
			return false
	return true


func add_lingering_monster(monster_data: Dictionary) -> void:
	if not should_carry_over_monsters():
		return

	var monster_type_id: String = str(monster_data.get("monster_type_id", ""))
	if monster_type_id.is_empty():
		return
	if not _monster_definitions.has(monster_type_id):
		return
	_lingering_monsters.append(monster_data.duplicate(true))


func consume_lingering_monsters_for_run() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for monster_data: Dictionary in _lingering_monsters:
		result.append(monster_data.duplicate(true))
	_lingering_monsters.clear()
	return result


func get_lingering_monster_count() -> int:
	return _lingering_monsters.size()


func get_lingering_monster_drain_units() -> float:
	var total_units: float = 0.0
	for monster_data: Dictionary in _lingering_monsters:
		var monster_type_id: String = str(monster_data.get("monster_type_id", ""))
		var monster_config: Dictionary = _monster_definitions.get(monster_type_id, {})
		if monster_config.is_empty():
			continue
		total_units += float(monster_config.get("drain_multiplier", 0.0))
	return total_units


func get_effect_total(stat_name: String) -> float:
	var total_value: float = 0.0
	for rune_id: String in _selected_rune_ids:
		var rune_config: Dictionary = _rune_definitions.get(rune_id, {})
		total_value += _get_effect_value_from_rune(rune_config, stat_name)
	return total_value


func get_attack_radius(base_value: float) -> float:
	return base_value + get_effect_total("attack_radius")


func get_damage_per_second(base_value: float) -> float:
	return base_value + get_effect_total("damage_per_second")


func get_lifetime_slow_scale(base_value: float) -> float:
	return clampf(base_value - get_effect_total("lifetime_slow_strength"), 0.05, 1.0)


func get_monster_lifetime_bonus_seconds() -> float:
	return get_effect_total("monster_lifetime_bonus_seconds")


func get_time_between_groups(base_value: float) -> float:
	var reduction_factor: float = get_effect_total("time_between_groups_factor")
	return maxf(0.05, base_value * (1.0 - reduction_factor))


func get_extra_monsters_per_group() -> int:
	return maxi(0, int(round(get_effect_total("extra_monsters_per_wave"))))


func is_stasis_field_enabled() -> bool:
	return get_effect_total("stasis_field_enabled") > 0.0


func is_monster_spawn_burst_enabled() -> bool:
	return get_effect_total("monster_spawn_burst_enabled") > 0.0


func is_monster_expire_burst_enabled() -> bool:
	return get_effect_total("monster_expire_burst_enabled") > 0.0


func is_monster_kill_burst_enabled() -> bool:
	return get_effect_total("monster_kill_burst_enabled") > 0.0


func get_monster_burst_projectile_count() -> int:
	return 1 + maxi(0, int(round(get_effect_total("monster_burst_projectile_count_bonus"))))


func get_monster_burst_pierce_count() -> int:
	return maxi(0, int(round(get_effect_total("monster_burst_pierce_bonus"))))


func get_monster_burst_range_bonus() -> float:
	return maxf(0.0, get_effect_total("monster_burst_range_bonus"))


func get_monster_burst_bounce_count() -> int:
	return maxi(0, int(round(get_effect_total("monster_burst_bounce_bonus"))))


func format_population(value: int) -> String:
	return _format_int_with_commas(maxi(0, value))


func _load_game_data() -> void:
	_load_monsters()
	_load_runes()
	_load_tiers()
	_population_config = _load_json_dictionary(POPULATION_CONFIG_PATH)
	_run_config = _load_json_dictionary(RUN_CONFIG_PATH)


func _load_monsters() -> void:
	_monster_definitions.clear()
	var definitions: Array = _load_json_array(MONSTERS_CONFIG_PATH)
	for definition_variant: Variant in definitions:
		if typeof(definition_variant) != TYPE_DICTIONARY:
			continue
		var definition: Dictionary = definition_variant
		var monster_id: String = str(definition.get("id", ""))
		if monster_id.is_empty():
			continue
		_monster_definitions[monster_id] = definition


func _load_runes() -> void:
	_rune_definitions.clear()
	var definitions: Array = _load_json_array(RUNES_CONFIG_PATH)
	for definition_variant: Variant in definitions:
		if typeof(definition_variant) != TYPE_DICTIONARY:
			continue
		var definition: Dictionary = definition_variant
		var rune_id: String = str(definition.get("id", ""))
		if rune_id.is_empty():
			continue
		_rune_definitions[rune_id] = definition


func _load_tiers() -> void:
	_tier_definitions.clear()
	_tier_numbers.clear()
	var definitions: Array = _load_json_array(TIERS_CONFIG_PATH)
	for definition_variant: Variant in definitions:
		if typeof(definition_variant) != TYPE_DICTIONARY:
			continue
		var definition: Dictionary = definition_variant
		var tier_number: int = maxi(1, int(definition.get("tier", 0)))
		_tier_numbers.append(tier_number)
		_tier_definitions[tier_number] = definition
	_tier_numbers.sort()


func _load_json_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("Missing config at %s" % path)
		return {}

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("Could not open config at %s" % path)
		return {}

	var parsed_data: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed_data) != TYPE_DICTIONARY:
		push_warning("Expected dictionary config at %s" % path)
		return {}
	return parsed_data


func _load_json_array(path: String) -> Array:
	if not FileAccess.file_exists(path):
		push_warning("Missing config at %s" % path)
		return []

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("Could not open config at %s" % path)
		return []

	var parsed_data: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed_data) != TYPE_ARRAY:
		push_warning("Expected array config at %s" % path)
		return []
	return parsed_data


func _initialize_objective_progress() -> void:
	for rune_id: String in _selected_rune_ids:
		if _selected_rune_progress.has(rune_id):
			continue
		_selected_rune_progress[rune_id] = 0


func _apply_completed_rune_rewards() -> void:
	var slot_bonus: int = maxi(0, int(round(get_effect_total("unlocked_slots"))))
	if slot_bonus > 0:
		_unlocked_slots = clampi(_unlocked_slots + slot_bonus, 1, MAX_UNLOCKED_SLOTS)


func _get_total_rune_drain_units() -> float:
	var total_units: float = 0.0
	for rune_id: String in _selected_rune_ids:
		var rune_config: Dictionary = _rune_definitions.get(rune_id, {})
		var drain_multiplier: float = float(rune_config.get("drain_multiplier", 1.0))
		total_units += drain_multiplier - 1.0
	return total_units


func _get_effect_value_from_rune(rune_config: Dictionary, stat_name: String) -> float:
	var total_value: float = 0.0
	if str(rune_config.get("effect_type", "")) == stat_name:
		total_value += float(rune_config.get("effect_value", 0.0))
	if str(rune_config.get("secondary_effect_type", "")) == stat_name:
		total_value += float(rune_config.get("secondary_effect_value", 0.0))
	return total_value


func _array_variant_to_string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if typeof(value) != TYPE_ARRAY:
		return result
	for item: Variant in value:
		result.append(str(item))
	return result


func _format_int_with_commas(value: int) -> String:
	var negative: bool = value < 0
	var digits: String = str(abs(value))
	var grouped: String = ""
	var digit_index: int = 0

	for index: int in range(digits.length() - 1, -1, -1):
		grouped = digits[index] + grouped
		digit_index += 1
		if index > 0 and digit_index % 3 == 0:
			grouped = "," + grouped

	if negative:
		return "-" + grouped
	return grouped
