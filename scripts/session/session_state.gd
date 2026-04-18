extends Node


signal runes_changed(total_runes: int)
signal upgrade_purchased(upgrade_id: String, new_level: int)
signal session_reset()
signal run_started(run_number: int)
signal run_finished(run_number: int, kills: int, natural_end: bool)


const UPGRADE_TREE_PATH: String = "res://data/meta/upgrade_tree.json"

var _upgrade_ids: Array[String] = []
var _upgrade_definitions: Dictionary = {}
var _runes: int = 0
var _run_number: int = 0
var _upgrade_levels: Dictionary = {}
var _last_run_kills: int = 0
var _last_run_was_natural_end: bool = false


func _ready() -> void:
	_load_upgrade_tree()
	reset_session()


func reset_session() -> void:
	_runes = 0
	_run_number = 0
	_last_run_kills = 0
	_last_run_was_natural_end = false
	_upgrade_levels.clear()

	for upgrade_id: String in _upgrade_ids:
		_upgrade_levels[upgrade_id] = 0

	session_reset.emit()
	runes_changed.emit(_runes)


func start_next_run() -> void:
	_run_number += 1
	run_started.emit(_run_number)


func finish_current_run(kills: int, natural_end: bool) -> void:
	_last_run_kills = maxi(0, kills)
	_last_run_was_natural_end = natural_end
	run_finished.emit(_run_number, _last_run_kills, natural_end)


func add_runes(amount: int) -> void:
	if amount <= 0:
		return

	_runes += amount
	runes_changed.emit(_runes)


func spend_runes(amount: int) -> bool:
	if amount <= 0:
		return true

	if _runes < amount:
		return false

	_runes -= amount
	runes_changed.emit(_runes)
	return true


func get_runes() -> int:
	return _runes


func get_run_number() -> int:
	return _run_number


func get_last_run_kills() -> int:
	return _last_run_kills


func was_last_run_natural_end() -> bool:
	return _last_run_was_natural_end


func get_upgrade_ids() -> Array[String]:
	var result: Array[String] = []
	for upgrade_id: String in _upgrade_ids:
		result.append(upgrade_id)
	return result


func get_visible_upgrade_ids() -> Array[String]:
	var visible_ids: Array[String] = []
	for upgrade_id: String in _upgrade_ids:
		if is_upgrade_visible(upgrade_id):
			visible_ids.append(upgrade_id)
	return visible_ids


func get_upgrade_definition(upgrade_id: String) -> Dictionary:
	return _upgrade_definitions.get(upgrade_id, {})


func get_upgrade_level(upgrade_id: String) -> int:
	return int(_upgrade_levels.get(upgrade_id, 0))


func is_upgrade_visible(upgrade_id: String) -> bool:
	var definition: Dictionary = get_upgrade_definition(upgrade_id)
	if definition.is_empty():
		return false

	var parents: Array = definition.get("parents", [])
	if parents.is_empty():
		return true

	for parent_variant: Variant in parents:
		var parent_id: String = str(parent_variant)
		if get_upgrade_level(parent_id) > 0:
			return true

	return false


func is_upgrade_maxed(upgrade_id: String) -> bool:
	return get_upgrade_level(upgrade_id) >= get_upgrade_max_level(upgrade_id)


func get_upgrade_max_level(upgrade_id: String) -> int:
	var definition: Dictionary = get_upgrade_definition(upgrade_id)
	return maxi(1, int(definition.get("max_level", 1)))


func get_upgrade_next_cost(upgrade_id: String) -> int:
	if is_upgrade_maxed(upgrade_id):
		return 0

	var definition: Dictionary = get_upgrade_definition(upgrade_id)
	var base_cost: int = maxi(1, int(definition.get("base_cost", 1)))
	var cost_growth: float = maxf(1.0, float(definition.get("cost_growth", 1.0)))
	var current_level: int = get_upgrade_level(upgrade_id)
	return maxi(1, int(round(base_cost * pow(cost_growth, current_level))))


func can_purchase_upgrade(upgrade_id: String) -> bool:
	if not is_upgrade_visible(upgrade_id):
		return false

	if is_upgrade_maxed(upgrade_id):
		return false

	return _runes >= get_upgrade_next_cost(upgrade_id)


func purchase_upgrade(upgrade_id: String) -> bool:
	if not can_purchase_upgrade(upgrade_id):
		return false

	var next_cost: int = get_upgrade_next_cost(upgrade_id)
	if not spend_runes(next_cost):
		return false

	var new_level: int = get_upgrade_level(upgrade_id) + 1
	_upgrade_levels[upgrade_id] = new_level
	upgrade_purchased.emit(upgrade_id, new_level)
	return true


func get_attack_radius(base_value: float) -> float:
	return base_value + _get_total_effect_value("attack_radius")


func get_damage_per_second(base_value: float) -> float:
	return base_value + _get_total_effect_value("damage_per_second")


func get_lifetime_slow_scale(base_value: float) -> float:
	return clampf(base_value - _get_total_effect_value("lifetime_slow_strength"), 0.05, 1.0)


func get_monster_lifetime_bonus_seconds() -> float:
	return _get_total_effect_value("monster_lifetime_bonus_seconds")


func get_monster_move_speed_multiplier() -> float:
	return maxf(0.2, 1.0 - _get_total_effect_value("monster_move_speed_factor"))


func get_time_between_groups(base_value: float) -> float:
	var reduction_factor: float = _get_total_effect_value("time_between_groups_factor")
	return maxf(0.05, base_value * (1.0 - reduction_factor))


func get_waves(base_waves: Array[int]) -> Array[int]:
	var extra_monsters: int = int(round(_get_total_effect_value("extra_monsters_per_wave")))
	var result: Array[int] = []

	for wave_size: int in base_waves:
		result.append(maxi(1, wave_size + extra_monsters))

	return result


func get_runes_for_monster_kill(was_in_signal_field: bool) -> int:
	var rune_base: float = 1.0 + _get_total_effect_value("runes_per_kill_flat")
	if was_in_signal_field:
		rune_base += float(get_bonus_runes_for_field_kill())

	var rune_multiplier: float = 1.0 + _get_total_effect_value("runes_per_kill_multiplier")
	return maxi(1, int(round(rune_base * rune_multiplier)))


func is_stasis_field_enabled() -> bool:
	return _get_total_effect_value("stasis_field_enabled") > 0.0


func get_bonus_runes_for_field_kill() -> int:
	return int(round(_get_total_effect_value("bonus_rune_kill_inside_field")))


func is_monster_spawn_burst_enabled() -> bool:
	return _get_total_effect_value("monster_spawn_burst_enabled") > 0.0


func is_monster_expire_burst_enabled() -> bool:
	return _get_total_effect_value("monster_expire_burst_enabled") > 0.0


func is_monster_kill_burst_enabled() -> bool:
	return _get_total_effect_value("monster_kill_burst_enabled") > 0.0


func get_monster_burst_projectile_count() -> int:
	return 1 + maxi(0, int(round(_get_total_effect_value("monster_burst_projectile_count_bonus"))))


func get_monster_burst_pierce_count() -> int:
	return maxi(0, int(round(_get_total_effect_value("monster_burst_pierce_bonus"))))


func get_monster_burst_range_bonus() -> float:
	return maxf(0.0, _get_total_effect_value("monster_burst_range_bonus"))


func get_monster_burst_bounce_count() -> int:
	return maxi(0, int(round(_get_total_effect_value("monster_burst_bounce_bonus"))))


func _get_total_effect_value(stat_name: String) -> float:
	var total_value: float = 0.0

	for upgrade_id: String in _upgrade_ids:
		var current_level: int = get_upgrade_level(upgrade_id)
		if current_level <= 0:
			continue

		var definition: Dictionary = get_upgrade_definition(upgrade_id)
		var effects: Array = definition.get("effects", [])
		for effect_variant: Variant in effects:
			if typeof(effect_variant) != TYPE_DICTIONARY:
				continue

			var effect: Dictionary = effect_variant
			if str(effect.get("stat", "")) != stat_name:
				continue

			total_value += float(effect.get("per_level", 0.0)) * float(current_level)

	return total_value


func _load_upgrade_tree() -> void:
	_upgrade_ids.clear()
	_upgrade_definitions.clear()

	if not FileAccess.file_exists(UPGRADE_TREE_PATH):
		push_warning("Upgrade tree config is missing at %s" % UPGRADE_TREE_PATH)
		return

	var file: FileAccess = FileAccess.open(UPGRADE_TREE_PATH, FileAccess.READ)
	if file == null:
		push_warning("Upgrade tree config could not be opened at %s" % UPGRADE_TREE_PATH)
		return

	var parsed_data: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed_data) != TYPE_ARRAY:
		push_warning("Upgrade tree config must be an array at %s" % UPGRADE_TREE_PATH)
		return

	var definitions: Array = parsed_data
	for definition_variant: Variant in definitions:
		if typeof(definition_variant) != TYPE_DICTIONARY:
			continue

		var definition: Dictionary = definition_variant
		var upgrade_id: String = str(definition.get("id", ""))
		if upgrade_id.is_empty():
			continue

		_upgrade_ids.append(upgrade_id)
		_upgrade_definitions[upgrade_id] = definition
