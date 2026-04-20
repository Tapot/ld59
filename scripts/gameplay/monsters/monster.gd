class_name Monster
extends Area2D


signal killed(monster: Monster)
signal expired(monster: Monster)

enum MonsterState {
	ALIVE,
	EXPIRING,
	DYING
}


@export var max_hp: float = 100.0
@export var lifetime_range_seconds: Vector2 = Vector2(5.0, 10.0)
@export var move_speed: float = 210.0
@export var roam_radius: float = 220.0
@export var seek_center_jitter_radius: float = 90.0
@export var idle_time_range: Vector2 = Vector2(1.0, 2.8)
@export var walk_time_range: Vector2 = Vector2(0.2, 0.45)
@export var expire_fade_duration: float = 0.3
@export var death_marker_duration: float = 0.5

const FX_BURN_RAMP_SPEED: float = 6.0
const FX_BURN_COOLDOWN_SPEED: float = 3.0
const FX_BURN_PULSE_SPEED: float = 8.0
const FX_BURN_PULSE_AMOUNT: float = 0.25
const FX_BURN_MAX_WHITE: float = 0.7
const FX_SHAKE_MAX_OFFSET: float = 1.5
const FX_DAMAGE_WINDOW: float = 0.05
const STATUS_BAR_WIDTH: float = 72.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var death_marker: ColorRect = $DeathMarker
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var hp_bar: ProgressBar = $StatusLine/HpBar
@onready var lifetime_bar: ProgressBar = $StatusLine/LifetimeBar
@onready var walk_timer: Timer = $WalkTimer
@onready var death_particles: CPUParticles2D = $DeathParticles
@onready var burn_scorch: CPUParticles2D = $BurnScorch

var hp: float = 0.0
var max_lifetime: float = 0.0
var remaining_lifetime: float = 0.0
var spawn_global_position: Vector2 = Vector2.ZERO
var walk_target_global_position: Vector2 = Vector2.ZERO
var is_walking: bool = false
var monster_type_id: String = "drifter"
var monster_title: String = "Drifter"
var drain_multiplier: float = 1.0
var behavior_type: String = "wander"

var _sprite_scale: float = 0.32
var _sprite_tint: Color = Color.WHITE
var _sprite_texture_path: String = ""
var _collision_radius: float = 26.0
var _configured_start_hp: float = -1.0
var _configured_start_remaining_lifetime: float = -1.0
var _lifetime_slow_count: int = 0
var _lifetime_slow_scale: float = 1.0
var _motion_lock_count: int = 0
var _state: MonsterState = MonsterState.ALIVE
var _despawn_elapsed: float = 0.0
var _despawn_duration: float = 0.0
var _fx_burn_intensity: float = 0.0
var _fx_damage_timer: float = 0.0


func configure_from_runtime(monster_config: Dictionary, carry_over_data: Dictionary = {}) -> void:
	monster_type_id = str(monster_config.get("id", "drifter"))
	monster_title = str(monster_config.get("title", monster_type_id.capitalize()))
	max_hp = maxf(1.0, float(monster_config.get("hp", max_hp)))
	var lifetime_seconds: float = maxf(0.5, float(monster_config.get("lifetime", lifetime_range_seconds.y)))
	lifetime_range_seconds = Vector2(lifetime_seconds, lifetime_seconds)
	move_speed = maxf(1.0, float(monster_config.get("speed", move_speed)))
	drain_multiplier = maxf(0.1, float(monster_config.get("drain_multiplier", 1.0)))
	behavior_type = str(monster_config.get("behavior_type", "wander"))
	roam_radius = maxf(80.0, float(monster_config.get("roam_radius", roam_radius)))
	seek_center_jitter_radius = maxf(0.0, float(monster_config.get("seek_center_jitter_radius", seek_center_jitter_radius)))
	idle_time_range = _vector2_from_json(monster_config.get("idle_time_range", [idle_time_range.x, idle_time_range.y]), idle_time_range)
	walk_time_range = _vector2_from_json(monster_config.get("walk_time_range", [walk_time_range.x, walk_time_range.y]), walk_time_range)
	_sprite_scale = float(monster_config.get("sprite_scale", _sprite_scale))
	_sprite_tint = _color_from_json(monster_config.get("sprite_tint", [1.0, 1.0, 1.0, 1.0]), Color.WHITE)
	_sprite_texture_path = str(monster_config.get("sprite_texture_path", ""))
	_collision_radius = maxf(4.0, float(monster_config.get("collision_radius", _collision_radius)))

	_configured_start_hp = float(carry_over_data.get("hp", -1.0))
	_configured_start_remaining_lifetime = float(carry_over_data.get("remaining_lifetime", -1.0))


func _ready() -> void:
	add_to_group("attackable_monsters")
	hp = max_hp if _configured_start_hp <= 0.0 else clampf(_configured_start_hp, 1.0, max_hp)
	max_lifetime = _roll_lifetime()
	if _configured_start_remaining_lifetime > 0.0:
		remaining_lifetime = clampf(_configured_start_remaining_lifetime, 0.1, max_lifetime)
	else:
		remaining_lifetime = max_lifetime
	spawn_global_position = global_position
	walk_target_global_position = global_position
	is_walking = false
	_apply_sprite_texture()
	sprite.scale = Vector2.ONE * _sprite_scale
	sprite.offset = Vector2.ZERO
	sprite.modulate = _sprite_tint
	var circle_shape: CircleShape2D = collision_shape.shape as CircleShape2D
	if circle_shape != null:
		circle_shape.radius = _collision_radius
	hp_bar.custom_minimum_size.x = STATUS_BAR_WIDTH * 0.5
	lifetime_bar.custom_minimum_size.x = STATUS_BAR_WIDTH * 0.5
	hp_bar.max_value = max_hp
	hp_bar.value = hp
	hp_bar.visible = true
	lifetime_bar.max_value = max_lifetime
	lifetime_bar.value = remaining_lifetime
	walk_timer.timeout.connect(_on_walk_timer_timeout)
	_schedule_idle()


func _process(delta: float) -> void:
	_update_despawn_visuals(delta)


func _physics_process(delta: float) -> void:
	_update_burn_effect(delta)

	if _state != MonsterState.ALIVE:
		return

	if _update_lifetime(delta):
		return

	if _motion_lock_count > 0:
		return

	if not is_walking:
		return

	var to_target: Vector2 = walk_target_global_position - global_position
	if to_target.length() <= move_speed * delta:
		global_position = walk_target_global_position
		is_walking = false
		_schedule_idle()
		return

	global_position += to_target.normalized() * move_speed * delta


func take_damage(amount: float) -> void:
	if _state != MonsterState.ALIVE:
		return

	_fx_damage_timer = FX_DAMAGE_WINDOW
	hp = maxf(0.0, hp - amount)
	hp_bar.value = hp

	if hp <= 0.0:
		_start_death_sequence()


func is_alive_for_carry_over() -> bool:
	return _state == MonsterState.ALIVE and hp > 0.0


func get_population_drain_units() -> float:
	if not is_alive_for_carry_over():
		return 0.0
	return drain_multiplier


func to_lingering_data() -> Dictionary:
	return {
		"monster_type_id": monster_type_id,
		"hp": hp,
		"remaining_lifetime": remaining_lifetime
	}


func push_lifetime_slow(slow_scale: float) -> void:
	_lifetime_slow_count += 1
	_lifetime_slow_scale = clampf(slow_scale, 0.0, 1.0)


func pop_lifetime_slow() -> void:
	_lifetime_slow_count = maxi(0, _lifetime_slow_count - 1)
	if _lifetime_slow_count == 0:
		_lifetime_slow_scale = 1.0


func push_motion_lock() -> void:
	if _state != MonsterState.ALIVE:
		return

	_motion_lock_count += 1
	is_walking = false
	walk_timer.stop()


func pop_motion_lock() -> void:
	_motion_lock_count = maxi(0, _motion_lock_count - 1)
	if _motion_lock_count > 0:
		return

	if _state != MonsterState.ALIVE:
		return

	if walk_timer.is_stopped():
		_schedule_idle()


func _on_walk_timer_timeout() -> void:
	if _motion_lock_count > 0:
		return

	if is_walking:
		is_walking = false
		_schedule_idle()
		return

	walk_target_global_position = _pick_walk_target_global_position()
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


func _get_lifetime_tick_scale() -> float:
	if _lifetime_slow_count <= 0:
		return 1.0
	return _lifetime_slow_scale


func _start_expire_sequence() -> void:
	if _state != MonsterState.ALIVE:
		return

	_begin_despawn(MonsterState.EXPIRING, expire_fade_duration)
	expired.emit(self)
	sprite.visible = true
	death_marker.visible = false
	sprite.modulate.a = 1.0


func _start_death_sequence() -> void:
	if _state != MonsterState.ALIVE:
		return

	var fx_duration: float = maxf(death_particles.lifetime, burn_scorch.lifetime) + 0.05
	_begin_despawn(MonsterState.DYING, fx_duration)
	killed.emit(self)
	sprite.visible = false
	death_marker.visible = false
	death_particles.emitting = true
	burn_scorch.emitting = true


func _begin_despawn(next_state: MonsterState, duration: float) -> void:
	_state = next_state
	remove_from_group("attackable_monsters")
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

	queue_free()


func _disable_attack_targeting() -> void:
	set_deferred("monitorable", false)
	collision_shape.set_deferred("disabled", true)


func _update_burn_effect(delta: float) -> void:
	if _state != MonsterState.ALIVE:
		_fx_damage_timer = 0.0
		return

	if _fx_damage_timer > 0.0:
		_fx_damage_timer -= delta
		_fx_burn_intensity = minf(_fx_burn_intensity + FX_BURN_RAMP_SPEED * delta, 1.0)
	else:
		_fx_burn_intensity = maxf(_fx_burn_intensity - FX_BURN_COOLDOWN_SPEED * delta, 0.0)

	if _fx_burn_intensity <= 0.0:
		sprite.self_modulate = Color.WHITE
		sprite.offset = Vector2.ZERO
		return

	var shake_offset: Vector2 = Vector2(
		randf_range(-FX_SHAKE_MAX_OFFSET, FX_SHAKE_MAX_OFFSET),
		randf_range(-FX_SHAKE_MAX_OFFSET, FX_SHAKE_MAX_OFFSET)
	) * _fx_burn_intensity
	sprite.offset = shake_offset

	var pulse: float = (1.0 + sin(Time.get_ticks_msec() * 0.001 * FX_BURN_PULSE_SPEED * TAU)) * 0.5
	var white_amount: float = _fx_burn_intensity * (FX_BURN_MAX_WHITE - FX_BURN_PULSE_AMOUNT + pulse * FX_BURN_PULSE_AMOUNT)
	var color_scale: float = 1.0 + white_amount
	sprite.self_modulate = Color(color_scale, color_scale, color_scale, 1.0)


func _pick_walk_target_global_position() -> Vector2:
	if behavior_type == "seek_center":
		var center: Vector2 = _get_move_bounds_center()
		var offset: Vector2 = Vector2(
			randf_range(-seek_center_jitter_radius, seek_center_jitter_radius),
			randf_range(-seek_center_jitter_radius, seek_center_jitter_radius)
		)
		return _clamp_to_move_bounds(center + offset)

	var direction: Vector2 = _pick_walk_direction()
	var distance: float = randf_range(roam_radius * 0.55, roam_radius)
	var desired_target: Vector2 = global_position + direction * distance
	var offset_from_spawn: Vector2 = desired_target - spawn_global_position
	if offset_from_spawn.length() > roam_radius:
		offset_from_spawn = offset_from_spawn.normalized() * roam_radius
	return _clamp_to_move_bounds(spawn_global_position + offset_from_spawn)


func _pick_walk_direction() -> Vector2:
	var current_offset: Vector2 = global_position - spawn_global_position
	match behavior_type:
		"skitter":
			if current_offset.length() > 8.0 and randf() < 0.72:
				return current_offset.normalized().rotated(randf_range(-0.55, 0.55))
			return Vector2.from_angle(randf_range(0.0, TAU))
		"lumber":
			if current_offset.length() > 8.0 and randf() < 0.95:
				return current_offset.normalized().rotated(randf_range(-0.1, 0.1))
			return Vector2.from_angle(randf_range(0.0, TAU))
		_:
			if current_offset.length() > 8.0 and randf() < 0.8:
				return current_offset.normalized().rotated(randf_range(-0.25, 0.25))
			return Vector2.from_angle(randf_range(0.0, TAU))


func _get_move_bounds_center() -> Vector2:
	return (Globals.MONSTERS_FIELD_MIN + Globals.MONSTERS_FIELD_MAX) * 0.5


func _clamp_to_move_bounds(target_position: Vector2) -> Vector2:
	return Vector2(
		clampf(target_position.x, Globals.MONSTERS_FIELD_MIN.x, Globals.MONSTERS_FIELD_MAX.x),
		clampf(target_position.y, Globals.MONSTERS_FIELD_MIN.y, Globals.MONSTERS_FIELD_MAX.y)
	)


func _vector2_from_json(value: Variant, fallback: Vector2) -> Vector2:
	if typeof(value) != TYPE_ARRAY:
		return fallback

	var values: Array = value
	if values.size() < 2:
		return fallback

	return Vector2(float(values[0]), float(values[1]))


func _apply_sprite_texture() -> void:
	if _sprite_texture_path.is_empty():
		return

	var image_path: String = ProjectSettings.globalize_path(_sprite_texture_path)
	var image: Image = Image.load_from_file(image_path)
	if image == null or image.is_empty():
		push_warning("Could not load monster sprite from %s" % image_path)
		return

	sprite.texture = ImageTexture.create_from_image(image)


func _color_from_json(value: Variant, fallback: Color) -> Color:
	if typeof(value) != TYPE_ARRAY:
		return fallback

	var values: Array = value
	if values.size() < 3:
		return fallback

	var alpha: float = 1.0
	if values.size() >= 4:
		alpha = float(values[3])

	return Color(float(values[0]), float(values[1]), float(values[2]), alpha)
