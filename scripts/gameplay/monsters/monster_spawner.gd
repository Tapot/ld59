class_name MonsterSpawner
extends Node


signal monster_spawned(monster: Monster)
signal wave_started(wave_number: int)
signal all_waves_completed()


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
	_build_wave_plan()
	_carry_over_entries = SessionState.consume_lingering_monsters_for_run()
	_spawn_carry_over_monsters()

	if _waves.is_empty():
		_finish_all_waves()
		return

	_schedule_next_wave(_get_wave_delay(0))


func are_waves_completed() -> bool:
	return _waves_completed


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
		_schedule_next_wave(_get_wave_delay(_current_wave_index + 1))


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
	monster.spawn_position = monster.global_position
	_alive_monsters.append(monster)
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

	if _waves_completed:
		return
	if _wave_is_active:
		return
	if not _alive_monsters.is_empty():
		return

	_schedule_next_wave(_get_wave_delay(_current_wave_index + 1))


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
