class_name MonsterSpawner
extends Node


signal monster_spawned(monster: Monster)
signal wave_started(wave_number: int)
signal all_waves_completed()
signal monster_plan_changed(remaining_monster_count: int, alive_monster_count: int)


@export var monster_scene: PackedScene
@export var monster_container_path: NodePath

@onready var wave_timer: Timer = $WaveTimer
@onready var group_timer: Timer = $GroupTimer

var _monster_container: Node2D
var _alive_monsters: Array[Monster] = []
var _waves: Array[Dictionary] = []
var _carry_over_entries: Array[Dictionary] = []
var _current_wave_index: int = -1
var _current_group_index: int = 0
var _current_groups: Array[Dictionary] = []
var _wave_is_active: bool = false
var _waves_completed: bool = false
var _has_started: bool = false
var _planned_monster_total: int = 0
var _killed_monster_total: int = 0


func _ready() -> void:
	_monster_container = get_node_or_null(monster_container_path) as Node2D
	if monster_scene == null:
		monster_scene = load("res://scenes/gameplay/monsters/monster.tscn")

	wave_timer.timeout.connect(_on_wave_timer_timeout)
	group_timer.timeout.connect(_on_group_timer_timeout)


func begin_run() -> void:
	if _has_started:
		return

	_has_started = true
	_planned_monster_total = 0
	_killed_monster_total = 0
	_carry_over_entries = SessionState.consume_lingering_monsters_for_run()
	_build_wave_plan()
	_recalculate_planned_monster_total()
	_spawn_carry_over_monsters()
	_emit_monster_plan_changed()

	if _waves.is_empty():
		_finish_all_waves()
		return

	_schedule_next_wave(_get_wave_delay(0))


func are_waves_completed() -> bool:
	return _waves_completed


func get_remaining_monster_count() -> int:
	return maxi(0, _planned_monster_total - _killed_monster_total)


func get_alive_monster_count() -> int:
	return _alive_monsters.size()


func get_planned_monster_type_ids() -> Array[String]:
	var planned_type_ids: Array[String] = []
	for carry_over_entry: Dictionary in _carry_over_entries:
		_append_monster_type_id(planned_type_ids, str(carry_over_entry.get("monster_type_id", "")))

	for wave: Dictionary in _waves:
		for group: Dictionary in wave.get("groups", []):
			_append_monster_type_id(planned_type_ids, str(group.get("monster_type", "")))
	return planned_type_ids


func _on_wave_timer_timeout() -> void:
	_start_next_wave()


func _on_group_timer_timeout() -> void:
	_spawn_current_group()


func _build_wave_plan() -> void:
	_waves.clear()
	var tier_config: Dictionary = SessionState.get_current_tier_config()
	var spawn_setup: Dictionary = tier_config.get("spawn_setup", {})
	var waves: Array = spawn_setup.get("waves", [])
	for wave_variant: Variant in waves:
		if typeof(wave_variant) != TYPE_DICTIONARY:
			continue

		var wave: Dictionary = wave_variant
		var groups: Array[Dictionary] = []
		var raw_groups: Array = wave.get("groups", [])
		for group_variant: Variant in raw_groups:
			if typeof(group_variant) != TYPE_DICTIONARY:
				continue

			var group: Dictionary = group_variant
			var group_count: int = maxi(0, int(group.get("count", 0))) + SessionState.get_extra_monsters_per_group()
			if group_count <= 0:
				continue

			var base_interval: float = SessionState.get_base_group_interval()
			var group_interval: float = SessionState.get_time_between_groups(float(group.get("group_interval", base_interval)))
			groups.append({
				"monster_type": str(group.get("monster_type", "")),
				"count": group_count,
				"group_interval": group_interval
			})

		if groups.is_empty():
			continue

		_waves.append({
			"delay": maxf(0.0, float(wave.get("delay", 0.0))),
			"groups": groups
		})

	_ensure_selected_objective_reachability()
	_frontload_selected_objective_monsters()


func _ensure_selected_objective_reachability() -> void:
	var required_counts: Dictionary = _get_required_objective_counts()
	if required_counts.is_empty():
		return

	var planned_counts: Dictionary = _get_planned_monster_counts()
	for monster_type_variant: Variant in required_counts.keys():
		var monster_type_id: String = str(monster_type_variant)
		var required_count: int = maxi(0, int(required_counts.get(monster_type_id, 0)))
		var planned_count: int = maxi(0, int(planned_counts.get(monster_type_id, 0)))
		var missing_count: int = required_count - planned_count
		if missing_count <= 0:
			continue
		_inject_required_monster_group(monster_type_id, missing_count)


func _get_required_objective_counts() -> Dictionary:
	var required_counts: Dictionary = {}
	var selected_objectives: Array[Dictionary] = SessionState.get_selected_objectives()
	for objective: Dictionary in selected_objectives:
		var monster_type_id: String = str(objective.get("monster_type", ""))
		if monster_type_id.is_empty() or monster_type_id == "any":
			continue

		var target_count: int = maxi(0, int(objective.get("target", 0)))
		var current_required: int = maxi(0, int(required_counts.get(monster_type_id, 0)))
		required_counts[monster_type_id] = maxi(current_required, target_count)
	return required_counts


func _get_required_objective_monster_type_ids() -> Array[String]:
	var required_type_ids: Array[String] = []
	var selected_objectives: Array[Dictionary] = SessionState.get_selected_objectives()
	for objective: Dictionary in selected_objectives:
		var monster_type_id: String = str(objective.get("monster_type", ""))
		if monster_type_id.is_empty() or monster_type_id == "any":
			continue
		if required_type_ids.has(monster_type_id):
			continue
		required_type_ids.append(monster_type_id)
	return required_type_ids


func _get_planned_monster_counts() -> Dictionary:
	var planned_counts: Dictionary = {}
	for carry_over_entry: Dictionary in _carry_over_entries:
		_add_monster_count(planned_counts, str(carry_over_entry.get("monster_type_id", "")), 1)

	for wave: Dictionary in _waves:
		for group: Dictionary in wave.get("groups", []):
			_add_monster_count(planned_counts, str(group.get("monster_type", "")), int(group.get("count", 0)))
	return planned_counts


func _inject_required_monster_group(monster_type_id: String, missing_count: int) -> void:
	if monster_type_id.is_empty() or missing_count <= 0:
		return

	if _waves.is_empty():
		_waves.append({
			"delay": 0.0,
			"groups": []
		})

	for wave_index: int in range(_waves.size() - 1, -1, -1):
		var wave: Dictionary = _waves[wave_index]
		var groups: Array = wave.get("groups", [])
		for group_index: int in range(groups.size() - 1, -1, -1):
			var group: Dictionary = groups[group_index]
			if str(group.get("monster_type", "")) != monster_type_id:
				continue

			group["count"] = maxi(0, int(group.get("count", 0))) + missing_count
			groups[group_index] = group
			wave["groups"] = groups
			_waves[wave_index] = wave
			return

	var final_wave_index: int = _waves.size() - 1
	var final_wave: Dictionary = _waves[final_wave_index]
	var final_groups: Array = final_wave.get("groups", [])
	final_groups.append({
		"monster_type": monster_type_id,
		"count": missing_count,
		"group_interval": SessionState.get_time_between_groups(SessionState.get_base_group_interval())
	})
	final_wave["groups"] = final_groups
	_waves[final_wave_index] = final_wave


func _frontload_selected_objective_monsters() -> void:
	var objective_type_ids: Array[String] = _get_required_objective_monster_type_ids()
	if objective_type_ids.is_empty():
		return

	if _waves.is_empty():
		_waves.append({
			"delay": 0.0,
			"groups": []
		})

	var frontload_groups: Array[Dictionary] = []
	for monster_type_id: String in objective_type_ids:
		if _carry_over_contains_monster_type(monster_type_id):
			continue
		if not _pull_monster_from_future_group(monster_type_id):
			continue
		frontload_groups.append({
			"monster_type": monster_type_id,
			"count": 1,
			"group_interval": SessionState.get_time_between_groups(SessionState.get_base_group_interval())
		})

	if frontload_groups.is_empty():
		return

	var first_wave: Dictionary = _waves[0]
	var first_groups: Array = first_wave.get("groups", [])
	var next_groups: Array[Dictionary] = []
	for group: Dictionary in frontload_groups:
		next_groups.append(group)
	for group_variant: Variant in first_groups:
		if typeof(group_variant) != TYPE_DICTIONARY:
			continue
		next_groups.append((group_variant as Dictionary).duplicate(true))
	first_wave["delay"] = 0.0
	first_wave["groups"] = next_groups
	_waves[0] = first_wave


func _add_monster_count(counts: Dictionary, monster_type_id: String, amount: int) -> void:
	if monster_type_id.is_empty() or amount <= 0:
		return
	counts[monster_type_id] = maxi(0, int(counts.get(monster_type_id, 0))) + amount


func _carry_over_contains_monster_type(monster_type_id: String) -> bool:
	for carry_over_entry: Dictionary in _carry_over_entries:
		if str(carry_over_entry.get("monster_type_id", "")) == monster_type_id:
			return true
	return false


func _pull_monster_from_future_group(monster_type_id: String) -> bool:
	for wave_index: int in range(_waves.size()):
		var wave: Dictionary = _waves[wave_index]
		var groups: Array = wave.get("groups", [])
		for group_index: int in range(groups.size()):
			var group: Dictionary = groups[group_index]
			if str(group.get("monster_type", "")) != monster_type_id:
				continue

			var next_count: int = maxi(0, int(group.get("count", 0))) - 1
			if next_count < 0:
				continue
			if next_count == 0:
				groups.remove_at(group_index)
			else:
				group["count"] = next_count
				groups[group_index] = group
			wave["groups"] = groups
			_waves[wave_index] = wave
			return true
	return false


func _spawn_carry_over_monsters() -> void:
	for carry_over_entry: Dictionary in _carry_over_entries:
		_spawn_monster_entry(str(carry_over_entry.get("monster_type_id", "")), carry_over_entry)


func _schedule_next_wave(delay: float) -> void:
	if _waves_completed:
		return

	if _current_wave_index + 1 >= _waves.size():
		_finish_all_waves()
		return

	group_timer.stop()
	wave_timer.stop()
	var next_delay: float = maxf(0.0, delay)
	if next_delay <= 0.0:
		_start_next_wave()
		return

	wave_timer.start(next_delay)


func _start_next_wave() -> void:
	if _waves_completed:
		return

	_current_wave_index += 1
	if _current_wave_index >= _waves.size():
		_finish_all_waves()
		return

	var current_wave: Dictionary = _waves[_current_wave_index]
	_current_groups = []
	for group: Dictionary in current_wave.get("groups", []):
		_current_groups.append(group.duplicate(true))
	_current_group_index = 0
	_wave_is_active = true
	wave_started.emit(_current_wave_index + 1)
	_spawn_current_group()


func _spawn_current_group() -> void:
	if _waves_completed:
		return

	if not _wave_is_active:
		return

	if _current_group_index >= _current_groups.size():
		_on_wave_spawn_completed()
		return

	var group: Dictionary = _current_groups[_current_group_index]
	var monster_type_id: String = str(group.get("monster_type", ""))
	var monster_count: int = maxi(0, int(group.get("count", 0)))
	for _spawn_index: int in monster_count:
		_spawn_monster_entry(monster_type_id, {})

	_current_group_index += 1
	if _current_group_index >= _current_groups.size():
		_on_wave_spawn_completed()
		return

	group_timer.start(maxf(0.05, float(group.get("group_interval", SessionState.get_base_group_interval()))))


func _on_wave_spawn_completed() -> void:
	_wave_is_active = false
	group_timer.stop()

	if _alive_monsters.is_empty():
		_schedule_next_wave(0.0)


func _spawn_monster_entry(monster_type_id: String, carry_over_data: Dictionary) -> bool:
	if _monster_container == null or not is_instance_valid(_monster_container):
		return false

	var monster_config: Dictionary = SessionState.get_monster_config(monster_type_id)
	if monster_config.is_empty():
		return false

	var monster: Monster = monster_scene.instantiate() as Monster
	if monster == null:
		return false

	var lifetime_bonus: float = SessionState.get_monster_lifetime_bonus_seconds()
	if lifetime_bonus != 0.0:
		monster_config["lifetime"] = maxf(0.5, float(monster_config.get("lifetime", 5.0)) + lifetime_bonus)

	monster.global_position = _random_spawn_position()
	monster.configure_from_runtime(monster_config, carry_over_data)
	monster.spawn_global_position = monster.global_position
	monster.walk_target_global_position = monster.global_position
	_alive_monsters.append(monster)
	monster.killed.connect(_on_spawned_monster_killed, CONNECT_ONE_SHOT)
	monster.tree_exited.connect(_on_monster_tree_exited.bind(monster), CONNECT_ONE_SHOT)
	_add_spawned_monster.call_deferred(monster)
	return true


func _get_wave_delay(wave_index: int) -> float:
	if wave_index < 0 or wave_index >= _waves.size():
		return 0.0
	return maxf(0.0, float(_waves[wave_index].get("delay", 0.0)))


func _random_spawn_position() -> Vector2:
	return Vector2(
		randf_range(Globals.MONSTERS_FIELD_MIN.x, Globals.MONSTERS_FIELD_MAX.x),
		randf_range(Globals.MONSTERS_FIELD_MIN.y, Globals.MONSTERS_FIELD_MAX.y)
	)


func _on_monster_tree_exited(monster: Monster) -> void:
	_alive_monsters.erase(monster)
	_emit_monster_plan_changed()

	if _waves_completed:
		return
	if _wave_is_active:
		return
	if not _alive_monsters.is_empty():
		return

	_schedule_next_wave(0.0)


func _on_spawned_monster_killed(_monster: Monster) -> void:
	_killed_monster_total += 1
	_emit_monster_plan_changed()


func _finish_all_waves() -> void:
	if _waves_completed:
		return

	_waves_completed = true
	_wave_is_active = false
	wave_timer.stop()
	group_timer.stop()
	all_waves_completed.emit()


func _exit_tree() -> void:
	_has_started = false
	_waves_completed = true
	_wave_is_active = false
	wave_timer.stop()
	group_timer.stop()


func _add_spawned_monster(monster: Monster) -> void:
	if _monster_container == null or not is_instance_valid(_monster_container):
		return
	if not is_instance_valid(monster):
		return

	_monster_container.add_child(monster)
	monster_spawned.emit(monster)
	_emit_monster_plan_changed()


func _recalculate_planned_monster_total() -> void:
	_planned_monster_total = 0
	for carry_over_entry: Dictionary in _carry_over_entries:
		if str(carry_over_entry.get("monster_type_id", "")).is_empty():
			continue
		_planned_monster_total += 1

	for wave: Dictionary in _waves:
		for group: Dictionary in wave.get("groups", []):
			_planned_monster_total += maxi(0, int(group.get("count", 0)))


func _emit_monster_plan_changed() -> void:
	monster_plan_changed.emit(get_remaining_monster_count(), get_alive_monster_count())


func _append_monster_type_id(monster_type_ids: Array[String], monster_type_id: String) -> void:
	if monster_type_id.is_empty():
		return
	if monster_type_ids.has(monster_type_id):
		return
	monster_type_ids.append(monster_type_id)
