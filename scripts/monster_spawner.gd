class_name MonsterSpawner
extends Node

signal monster_spawned(monster: Monster)
signal wave_started(wave_number: int)
signal all_waves_completed()


@export var monster_scene: PackedScene
@export var monster_container_path: NodePath
@export var monsters: Array[Monster] = []
@export var waves: Array[int] = [10, 15, 20, 50]
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
var _remaining_in_wave: int = 0
var _is_waiting_for_next_wave: bool = false


func _ready() -> void:
	_monster_container = get_node_or_null(monster_container_path) as Node2D
	if monster_scene == null:
		monster_scene = load("res://scenes/monster.tscn")

	wave_timer.timeout.connect(_on_wave_timer_timeout)
	group_timer.timeout.connect(_on_group_timer_timeout)

	if waves.is_empty() or _monster_container == null:
		return

	_start_next_wave_after(_get_wave_delay(0))


func _start_next_wave_after(delay: float) -> void:
	_is_waiting_for_next_wave = true
	wave_timer.start(maxf(0.0, delay))


func _on_wave_timer_timeout() -> void:
	_current_wave_index += 1
	_is_waiting_for_next_wave = false
	if _current_wave_index >= waves.size():
		all_waves_completed.emit()
		return

	_remaining_in_wave = maxi(0, waves[_current_wave_index])
	wave_started.emit(_current_wave_index + 1)
	_spawn_next_group()


func _on_group_timer_timeout() -> void:
	_spawn_next_group()


func _spawn_next_group() -> void:
	if _remaining_in_wave <= 0:
		_start_next_wave_after(_get_wave_delay(_current_wave_index + 1))
		return

	var group_size: int = _pick_group_size()
	for _index in group_size:
		_spawn_monster()

	_remaining_in_wave -= group_size
	if _remaining_in_wave > 0:
		group_timer.start(time_between_groups)


func _spawn_monster() -> void:
	var monster: Monster = monster_scene.instantiate() as Monster
	if monster == null:
		return

	_monster_container.add_child(monster)
	monster.global_position = _random_spawn_position()
	monster.spawn_position = monster.global_position
	monsters.append(monster)
	monster.tree_exited.connect(_on_monster_tree_exited.bind(monster), CONNECT_ONE_SHOT)
	monster_spawned.emit(monster)


func _pick_group_size() -> int:
	var max_group_size: int = mini(_remaining_in_wave, _get_random_base_group_size())
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


func has_more_waves() -> bool:
	return _current_wave_index + 1 < waves.size()


func is_waiting_for_next_wave() -> bool:
	return _is_waiting_for_next_wave and not wave_timer.is_stopped()


func get_time_until_next_wave() -> float:
	if not is_waiting_for_next_wave():
		return 0.0

	return maxf(0.0, wave_timer.time_left)
