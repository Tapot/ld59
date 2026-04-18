class_name MonsterSpawner
extends Node


signal monster_spawned(monster: Monster)
signal wave_started(wave_number: int)
signal all_waves_completed()


@export var monster_scene: PackedScene
@export var monster_container_path: NodePath
@export var monsters: Array[Monster] = []
@export var waves: Array[int] = [10, 20, 35]
@export var time_between_waves: Array[float] = [0.0, 10.3]
@export var spawn_group_sizes: Array[int] = [2, 3, 4]
@export_range(0.0, 1.0, 0.05) var solo_spawn_chance: float = 0.2
@export_range(0.0, 10.0, 0.1) var time_between_groups: float = 0.7
@export var spawn_rect_position: Vector2 = Vector2(80.0, 120.0)
@export var spawn_rect_size: Vector2 = Vector2(1120.0, 520.0)

@onready var wave_timer: Timer = $WaveTimer
@onready var group_timer: Timer = $GroupTimer

var _monster_container: Node2D
var _current_wave_index: int = -1
var _remaining_to_spawn_in_wave: int = 0
var _is_waiting_for_next_wave: bool = false
var _current_wave_delay_duration: float = 0.0
var _wave_is_active: bool = false
var _waves_completed: bool = false


func _ready() -> void:
	_monster_container = get_node_or_null(monster_container_path) as Node2D
	if monster_scene == null:
		monster_scene = load("res://scenes/monster.tscn")

	wave_timer.timeout.connect(_on_wave_timer_timeout)
	group_timer.timeout.connect(_on_group_timer_timeout)

	if waves.is_empty() or _monster_container == null:
		return

	_schedule_next_wave(_get_wave_delay(0))


func _on_wave_timer_timeout() -> void:
	_start_next_wave()


func _on_group_timer_timeout() -> void:
	_spawn_next_group()


func _schedule_next_wave(delay: float) -> void:
	if not _can_run_runtime():
		return

	if not has_more_waves():
		_finish_all_waves()
		return

	group_timer.stop()
	wave_timer.stop()

	_current_wave_delay_duration = maxf(0.0, delay)
	if _current_wave_delay_duration <= 0.0:
		_start_next_wave()
		return

	_is_waiting_for_next_wave = true
	wave_timer.start(_current_wave_delay_duration)


func _start_next_wave() -> void:
	if not _can_run_runtime():
		return

	if _waves_completed:
		return

	wave_timer.stop()
	group_timer.stop()
	_is_waiting_for_next_wave = false
	_current_wave_delay_duration = 0.0
	_wave_is_active = true

	_current_wave_index += 1
	if _current_wave_index >= waves.size():
		_finish_all_waves()
		return

	_remaining_to_spawn_in_wave = maxi(0, waves[_current_wave_index])
	wave_started.emit(_current_wave_index + 1)
	_spawn_next_group()


func _spawn_next_group() -> void:
	if not _can_run_runtime():
		return

	if not _wave_is_active:
		return

	if _remaining_to_spawn_in_wave <= 0:
		_on_wave_spawn_completed()
		return

	var group_size: int = _pick_group_size()
	for _index in group_size:
		_spawn_monster()

	_remaining_to_spawn_in_wave -= group_size
	if _remaining_to_spawn_in_wave > 0:
		group_timer.start(time_between_groups)
	else:
		_on_wave_spawn_completed()


func _on_wave_spawn_completed() -> void:
	_wave_is_active = false
	group_timer.stop()

	if monsters.is_empty():
		_schedule_next_wave(0.0)
		return

	_schedule_next_wave(_get_wave_delay(_current_wave_index + 1))


func _spawn_monster() -> void:
	if _waves_completed:
		return

	if _monster_container == null or not is_instance_valid(_monster_container):
		return

	var monster: Monster = monster_scene.instantiate() as Monster
	if monster == null:
		return

	monster.position = _random_spawn_position()
	monster.spawn_position = monster.position
	monster.move_bounds_position = spawn_rect_position
	monster.move_bounds_size = spawn_rect_size
	monsters.append(monster)
	monster.tree_exited.connect(_on_monster_tree_exited.bind(monster), CONNECT_ONE_SHOT)
	_add_spawned_monster.call_deferred(monster)


func _pick_group_size() -> int:
	var max_group_size: int = mini(_remaining_to_spawn_in_wave, _get_random_base_group_size())
	if randf() <= solo_spawn_chance:
		return 1

	return maxi(1, max_group_size)


func _get_random_base_group_size() -> int:
	if spawn_group_sizes.is_empty():
		return 1

	return maxi(1, spawn_group_sizes[randi_range(0, spawn_group_sizes.size() - 1)])


func _get_wave_delay(wave_index: int) -> float:
	if time_between_waves.is_empty():
		return 0.0

	var safe_index: int = mini(wave_index, time_between_waves.size() - 1)
	return maxf(0.0, time_between_waves[safe_index])


func _random_spawn_position() -> Vector2:
	return Vector2(
		randf_range(spawn_rect_position.x, spawn_rect_position.x + spawn_rect_size.x),
		randf_range(spawn_rect_position.y, spawn_rect_position.y + spawn_rect_size.y)
	)


func _on_monster_tree_exited(monster: Monster) -> void:
	monsters.erase(monster)

	if not _can_run_runtime():
		return

	if _waves_completed:
		return

	if _wave_is_active:
		return

	if _remaining_to_spawn_in_wave > 0:
		return

	if not monsters.is_empty():
		return

	if _is_waiting_for_next_wave:
		_start_next_wave()


func _finish_all_waves() -> void:
	if _waves_completed:
		return

	_waves_completed = true
	_wave_is_active = false
	_is_waiting_for_next_wave = false
	_current_wave_delay_duration = 0.0
	wave_timer.stop()
	group_timer.stop()
	all_waves_completed.emit()


func has_more_waves() -> bool:
	return not _waves_completed and _current_wave_index + 1 < waves.size()


func is_waiting_for_next_wave() -> bool:
	return _is_waiting_for_next_wave and not wave_timer.is_stopped()


func get_time_until_next_wave() -> float:
	if not is_waiting_for_next_wave():
		return 0.0

	return maxf(0.0, wave_timer.time_left)


func get_current_wave_delay_duration() -> float:
	return _current_wave_delay_duration


func get_total_waves() -> int:
	return waves.size()


func get_current_wave_number() -> int:
	return clampi(_current_wave_index + 1, 0, waves.size())


func are_waves_completed() -> bool:
	return _waves_completed


func _exit_tree() -> void:
	_waves_completed = true
	_wave_is_active = false
	_is_waiting_for_next_wave = false
	wave_timer.stop()
	group_timer.stop()


func _add_spawned_monster(monster: Monster) -> void:
	if _waves_completed:
		return

	if _monster_container == null or not is_instance_valid(_monster_container):
		return

	if not is_instance_valid(monster):
		return

	_monster_container.add_child(monster)
	monster_spawned.emit(monster)


func _can_run_runtime() -> bool:
	return is_inside_tree() and wave_timer.is_inside_tree() and group_timer.is_inside_tree()
