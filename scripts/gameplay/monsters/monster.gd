class_name Monster
extends Area2D


signal died(monster: Monster)

enum MonsterState {
	ALIVE,
	EXPIRING,
	DYING
}


@export var max_hp: float = 100.0
@export var lifetime_range_seconds: Vector2 = Vector2(5.0, 10.0)
@export var move_speed: float = 210.0
@export var roam_radius: float = 220.0
@export var idle_time_range: Vector2 = Vector2(1.1, 2.8)
@export var walk_time_range: Vector2 = Vector2(0.2, 0.45)
@export var expire_fade_duration: float = 0.3
@export var death_marker_duration: float = 0.5
@export var move_bounds_position: Vector2 = Vector2.ZERO
@export var move_bounds_size: Vector2 = Vector2(1280.0, 720.0)

@onready var sprite: Sprite2D = $Sprite2D
@onready var death_marker: ColorRect = $DeathMarker
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var hp_bar: ProgressBar = $HpBar
@onready var lifetime_bar: ProgressBar = $LifetimeBar
@onready var walk_timer: Timer = $WalkTimer

var hp: float = 0.0
var max_lifetime: float = 0.0
var remaining_lifetime: float = 0.0
var spawn_position: Vector2 = Vector2.ZERO
var walk_target: Vector2 = Vector2.ZERO
var is_walking: bool = false
var _lifetime_slow_count: int = 0
var _lifetime_slow_scale: float = 1.0
var _state: MonsterState = MonsterState.ALIVE
var _despawn_elapsed: float = 0.0
var _despawn_duration: float = 0.0


func _ready() -> void:
	hp = max_hp
	max_lifetime = _roll_lifetime()
	remaining_lifetime = max_lifetime
	spawn_position = position
	walk_target = position
	hp_bar.max_value = max_hp
	hp_bar.value = hp
	hp_bar.visible = false
	lifetime_bar.max_value = max_lifetime
	lifetime_bar.value = remaining_lifetime
	walk_timer.timeout.connect(_on_walk_timer_timeout)
	_schedule_idle()


func _process(delta: float) -> void:
	_update_despawn_visuals(delta)


func _physics_process(delta: float) -> void:
	if _state != MonsterState.ALIVE:
		return

	if _update_lifetime(delta):
		return

	if not is_walking:
		return

	var to_target: Vector2 = walk_target - position
	if to_target.length() <= move_speed * delta:
		position = walk_target
		is_walking = false
		_schedule_idle()
		return

	position += to_target.normalized() * move_speed * delta


func take_damage(amount: float) -> void:
	if _state != MonsterState.ALIVE:
		return

	hp = maxf(0.0, hp - amount)
	hp_bar.value = hp
	hp_bar.visible = hp < max_hp

	if hp <= 0.0:
		_start_death_sequence()


func _on_walk_timer_timeout() -> void:
	if is_walking:
		is_walking = false
		_schedule_idle()
		return

	var direction: Vector2 = _pick_walk_direction()
	var distance: float = randf_range(roam_radius * 0.7, roam_radius)
	var desired_target: Vector2 = position + direction * distance
	var offset_from_spawn: Vector2 = desired_target - spawn_position
	if offset_from_spawn.length() > roam_radius:
		offset_from_spawn = offset_from_spawn.normalized() * roam_radius
	walk_target = _clamp_to_move_bounds(spawn_position + offset_from_spawn)
	is_walking = true
	walk_timer.start(randf_range(walk_time_range.x, walk_time_range.y))


func _schedule_idle() -> void:
	walk_timer.start(randf_range(idle_time_range.x, idle_time_range.y))


func _update_lifetime(delta: float) -> bool:
	remaining_lifetime = maxf(0.0, remaining_lifetime - delta * _get_lifetime_tick_scale())
	lifetime_bar.value = remaining_lifetime

	if remaining_lifetime <= 0.0:
		_start_expire_sequence()
		return true

	return false


func _roll_lifetime() -> float:
	var min_lifetime: float = minf(lifetime_range_seconds.x, lifetime_range_seconds.y)
	var max_lifetime_value: float = maxf(lifetime_range_seconds.x, lifetime_range_seconds.y)
	return randf_range(min_lifetime, max_lifetime_value)


func push_lifetime_slow(slow_scale: float) -> void:
	_lifetime_slow_count += 1
	_lifetime_slow_scale = clampf(slow_scale, 0.0, 1.0)


func pop_lifetime_slow() -> void:
	_lifetime_slow_count = maxi(0, _lifetime_slow_count - 1)
	if _lifetime_slow_count == 0:
		_lifetime_slow_scale = 1.0


func _get_lifetime_tick_scale() -> float:
	if _lifetime_slow_count <= 0:
		return 1.0

	return _lifetime_slow_scale


func _start_expire_sequence() -> void:
	if _state != MonsterState.ALIVE:
		return

	_begin_despawn(MonsterState.EXPIRING, expire_fade_duration)
	sprite.visible = true
	death_marker.visible = false
	sprite.modulate.a = 1.0


func _start_death_sequence() -> void:
	if _state != MonsterState.ALIVE:
		return

	_begin_despawn(MonsterState.DYING, death_marker_duration)
	sprite.visible = false
	death_marker.visible = true
	death_marker.modulate.a = 1.0


func _begin_despawn(next_state: MonsterState, duration: float) -> void:
	_state = next_state
	_despawn_elapsed = 0.0
	_despawn_duration = maxf(0.001, duration)
	is_walking = false
	walk_timer.stop()
	_disable_attack_targeting()
	hp_bar.visible = false
	lifetime_bar.visible = false


func _update_despawn_visuals(delta: float) -> void:
	if _state == MonsterState.ALIVE:
		return

	_despawn_elapsed += delta
	var progress: float = clampf(_despawn_elapsed / _despawn_duration, 0.0, 1.0)

	if _state == MonsterState.EXPIRING:
		sprite.modulate.a = 1.0 - progress
	elif _state == MonsterState.DYING:
		death_marker.modulate.a = 1.0 - progress

	if progress < 1.0:
		return

	if _state == MonsterState.DYING:
		died.emit(self)

	queue_free()


func _disable_attack_targeting() -> void:
	monitorable = false
	collision_shape.disabled = true


func _pick_walk_direction() -> Vector2:
	var current_offset: Vector2 = position - spawn_position
	if current_offset.length() > 8.0 and randf() < 0.8:
		var jitter_angle: float = randf_range(-0.25, 0.25)
		return current_offset.normalized().rotated(jitter_angle)

	return Vector2.from_angle(randf_range(0.0, TAU))


func _clamp_to_move_bounds(target_position: Vector2) -> Vector2:
	return Vector2(
		clampf(target_position.x, move_bounds_position.x, move_bounds_position.x + move_bounds_size.x),
		clampf(target_position.y, move_bounds_position.y, move_bounds_position.y + move_bounds_size.y)
	)
