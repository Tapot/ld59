class_name Monster
extends Area2D


signal died(monster: Monster)


@export var max_hp: float = 100.0
@export var lifetime_range_seconds: Vector2 = Vector2(5.0, 10.0)
@export var move_speed: float = 65.0
@export var roam_radius: float = 120.0
@export var idle_time_range: Vector2 = Vector2(0.8, 2.4)
@export var walk_time_range: Vector2 = Vector2(0.6, 1.8)

@onready var hp_bar: ProgressBar = $HpBar
@onready var lifetime_bar: ProgressBar = $LifetimeBar
@onready var walk_timer: Timer = $WalkTimer

var hp: float = 0.0
var max_lifetime: float = 0.0
var remaining_lifetime: float = 0.0
var spawn_position: Vector2
var walk_target: Vector2
var is_walking: bool = false
var _lifetime_pause_count: int = 0


func _ready() -> void:
	hp = max_hp
	max_lifetime = _roll_lifetime()
	remaining_lifetime = max_lifetime
	spawn_position = global_position
	walk_target = global_position
	hp_bar.max_value = max_hp
	hp_bar.value = hp
	hp_bar.visible = false
	lifetime_bar.max_value = max_lifetime
	lifetime_bar.value = remaining_lifetime
	walk_timer.timeout.connect(_on_walk_timer_timeout)
	_schedule_idle()


func _physics_process(delta: float) -> void:
	if _update_lifetime(delta):
		return

	if not is_walking:
		return

	var to_target: Vector2 = walk_target - global_position
	if to_target.length() <= move_speed * delta:
		global_position = walk_target
		is_walking = false
		_schedule_idle()
		return

	global_position += to_target.normalized() * move_speed * delta


func take_damage(amount: float) -> void:
	hp = maxf(0.0, hp - amount)
	hp_bar.value = hp
	hp_bar.visible = hp < max_hp

	if hp <= 0.0:
		_die()


func _on_walk_timer_timeout() -> void:
	if is_walking:
		is_walking = false
		_schedule_idle()
		return

	var direction: Vector2 = Vector2.from_angle(randf_range(0.0, TAU))
	var distance: float = randf_range(roam_radius * 0.25, roam_radius)
	walk_target = spawn_position + direction * distance
	is_walking = true
	walk_timer.start(randf_range(walk_time_range.x, walk_time_range.y))


func _schedule_idle() -> void:
	walk_timer.start(randf_range(idle_time_range.x, idle_time_range.y))


func _update_lifetime(delta: float) -> bool:
	if _lifetime_pause_count > 0:
		return false

	remaining_lifetime = maxf(0.0, remaining_lifetime - delta)
	lifetime_bar.value = remaining_lifetime

	if remaining_lifetime <= 0.0:
		queue_free()
		return true

	return false


func _die() -> void:
	died.emit(self)
	queue_free()


func _roll_lifetime() -> float:
	var min_lifetime: float = minf(lifetime_range_seconds.x, lifetime_range_seconds.y)
	var max_lifetime_value: float = maxf(lifetime_range_seconds.x, lifetime_range_seconds.y)
	return randf_range(min_lifetime, max_lifetime_value)


func push_lifetime_pause() -> void:
	_lifetime_pause_count += 1


func pop_lifetime_pause() -> void:
	_lifetime_pause_count = maxi(0, _lifetime_pause_count - 1)
