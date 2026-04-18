class_name MonsterSpawner
extends Node


signal monster_spawned(monster: Monster)
signal wave_started(wave_number: int)
signal all_waves_completed()


@export var monster_scene: PackedScene
@export var monster_container_path: NodePath
@export var waves: Array[int] = [12, 24, 36]
@export var time_between_waves: Array[float] = [0.0, 4.0, 5.0]
@export var spawn_group_sizes: Array[int] = [2, 3, 5]
@export_range(0.0, 1.0, 0.05) var solo_spawn_chance: float = 0.1
@export_range(0.0, 10.0, 0.05) var time_between_groups: float = 0.5
@export var spawn_rect_position: Vector2 = Vector2(80.0, 120.0)
@export var spawn_rect_size: Vector2 = Vector2(1120.0, 520.0)
@export var monster_base_hp: float = 60.0
@export_range(0.0, 3.0, 0.05) var monster_hp_growth_per_wave: float = 0.35
@export var monster_lifetime_bonus_seconds: float = 0.0
@export var monster_move_speed_multiplier: float = 1.0

@onready var wave_timer: Timer = $WaveTimer
@onready var group_timer: Timer = $GroupTimer

var _monster_container: Node2D
var _current_wave_index: int = -1
var _remaining_to_spawn_in_wave: int = 0
var _alive_monsters: Array[Monster] = []
var _is_waiting_for_next_wave: bool = false
var _current_wave_delay_duration: float = 0.0
var _wave_is_active: bool = false
var _waves_completed: bool = false
var _has_started: bool = false


func _ready() -> void:
	_monster_container = get_node_or_null(monster_container_path) as Node2D
	if monster_scene == null:
		monster_scene = load("res://scenes/gameplay/monsters/monster.tscn")

	wave_timer.timeout.connect(_on_wave_timer_timeout)
	group_timer.timeout.connect(_on_group_timer_timeout)

	if waves.is_empty() or _monster_container == null:
		return


func begin_run() -> void:
	if _has_started:
		return

	if waves.is_empty() or _monster_container == null:
		return

	_has_started = true
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

	var requested_group_size: int = _pick_group_size()
	var spawned_count: int = 0
	for _index: int in requested_group_size:
		if _spawn_monster():
			spawned_count += 1

	_remaining_to_spawn_in_wave = maxi(0, _remaining_to_spawn_in_wave - spawned_count)
	if spawned_count <= 0:
		_finish_all_waves()
		return

	if _remaining_to_spawn_in_wave > 0:
		group_timer.start(time_between_groups)
	else:
		_on_wave_spawn_completed()


func _on_wave_spawn_completed() -> void:
	_wave_is_active = false
	group_timer.stop()

	if _alive_monsters.is_empty():
		_schedule_next_wave(0.0)
		return

	_is_waiting_for_next_wave = false
	_current_wave_delay_duration = 0.0


func _spawn_monster() -> bool:
	if _waves_completed:
		return false

	if _monster_container == null or not is_instance_valid(_monster_container):
		return false

	var monster: Monster = monster_scene.instantiate() as Monster
	if monster == null:
		return false

	monster.position = _random_spawn_position()
	monster.spawn_position = monster.position
	monster.max_hp = _get_wave_monster_hp(_current_wave_index)
	monster.move_bounds_position = spawn_rect_position
	monster.move_bounds_size = spawn_rect_size
	monster.lifetime_range_seconds = Vector2(
		maxf(0.5, monster.lifetime_range_seconds.x + monster_lifetime_bonus_seconds),
		maxf(0.6, monster.lifetime_range_seconds.y + monster_lifetime_bonus_seconds)
	)
	monster.move_speed *= maxf(0.2, monster_move_speed_multiplier)
	_alive_monsters.append(monster)
	monster.tree_exited.connect(_on_monster_tree_exited.bind(monster), CONNECT_ONE_SHOT)
	_add_spawned_monster.call_deferred(monster)
	return true


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


func _get_wave_monster_hp(wave_index: int) -> float:
	var safe_wave_index: int = maxi(0, wave_index)
	return maxf(1.0, monster_base_hp * pow(1.0 + monster_hp_growth_per_wave, safe_wave_index))


func _on_monster_tree_exited(monster: Monster) -> void:
	_alive_monsters.erase(monster)

	if not _can_run_runtime():
		return

	if _waves_completed:
		return

	if _wave_is_active:
		return

	if _remaining_to_spawn_in_wave > 0:
		return

	if not _alive_monsters.is_empty():
		return

	_schedule_next_wave(0.0)


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


func get_current_wave_total_monsters() -> int:
	if _current_wave_index < 0 or _current_wave_index >= waves.size():
		return 0

	return maxi(0, waves[_current_wave_index])


func get_current_wave_remaining_monsters() -> int:
	var total_monsters: int = get_current_wave_total_monsters()
	if total_monsters <= 0:
		return 0

	return maxi(0, _remaining_to_spawn_in_wave + _alive_monsters.size())


func get_current_wave_remaining_progress() -> float:
	var total_monsters: int = get_current_wave_total_monsters()
	if total_monsters <= 0:
		return 0.0

	return clampf(
		float(get_current_wave_remaining_monsters()) / float(total_monsters),
		0.0,
		1.0
	)


func are_waves_completed() -> bool:
	return _waves_completed


func _exit_tree() -> void:
	_has_started = false
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
