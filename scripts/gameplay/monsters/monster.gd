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
@export var speed_wobble_amount: float = 0.25
@export var speed_wobble_frequency: float = 1.8
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
const FX_BOB_HEIGHT: float = 4.0
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
var walk_until_arrived: bool = false
var flee_radius: float = 120.0
var flee_speed_multiplier: float = 1.6
var orbit_radius: float = 100.0
var orbit_speed: float = 2.5

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
var _run_end_disappearing: bool = false
var _wobble_phase: float = 0.0
var _orbit_angle: float = 0.0
var _orbit_center: Vector2 = Vector2.ZERO


func configure_from_runtime(monster_config: Dictionary, carry_over_data: Dictionary = {}) -> void:
	monster_type_id = str(monster_config.get("id", "drifter"))
	monster_title = str(monster_config.get("title", monster_type_id.capitalize()))
	max_hp = maxf(1.0, float(monster_config.get("hp", max_hp)))
	var lifetime_seconds: float = maxf(0.5, float(monster_config.get("lifetime", lifetime_range_seconds.y)))
	lifetime_range_seconds = Vector2(lifetime_seconds, lifetime_seconds)
	move_speed = maxf(1.0, float(monster_config.get("speed", move_speed)))
	speed_wobble_amount = clampf(float(monster_config.get("speed_wobble_amount", speed_wobble_amount)), 0.0, 0.8)
	speed_wobble_frequency = maxf(0.1, float(monster_config.get("speed_wobble_frequency", speed_wobble_frequency)))
	drain_multiplier = maxf(0.1, float(monster_config.get("drain_multiplier", 1.0)))
	behavior_type = str(monster_config.get("behavior_type", "wander"))
	walk_until_arrived = bool(monster_config.get("walk_until_arrived", walk_until_arrived))
	flee_radius = maxf(40.0, float(monster_config.get("flee_radius", flee_radius)))
	flee_speed_multiplier = maxf(1.0, float(monster_config.get("flee_speed_multiplier", flee_speed_multiplier)))
	orbit_radius = maxf(30.0, float(monster_config.get("orbit_radius", orbit_radius)))
	orbit_speed = maxf(0.5, float(monster_config.get("orbit_speed", orbit_speed)))
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
	global_position = _clamp_to_move_bounds(global_position)
	spawn_global_position = _clamp_to_move_bounds(spawn_global_position)
	walk_target_global_position = _clamp_to_move_bounds(walk_target_global_position)
	hp_bar.custom_minimum_size.x = STATUS_BAR_WIDTH * 0.5
	lifetime_bar.custom_minimum_size.x = STATUS_BAR_WIDTH * 0.5
	hp_bar.max_value = max_hp
	hp_bar.value = hp
	hp_bar.visible = true
	lifetime_bar.max_value = max_lifetime
	lifetime_bar.value = remaining_lifetime
	walk_timer.timeout.connect(_on_walk_timer_timeout)
	_wobble_phase = randf_range(0.0, TAU)
	_orbit_angle = randf_range(0.0, TAU)
	_schedule_idle()


func _process(delta: float) -> void:
	_update_despawn_visuals(delta)
	_update_sprite_bob()


func _physics_process(delta: float) -> void:
	_update_burn_effect(delta)

	if _state != MonsterState.ALIVE:
		return

	if _update_lifetime(delta):
		return

	if _motion_lock_count > 0:
		return

	if behavior_type == "flee_cursor" and _try_flee_cursor(delta):
		return

	if behavior_type == "orbit":
		_update_orbit(delta)
		return

	if not is_walking:
		return

	var current_speed: float = _get_wobbled_speed()
	var to_target: Vector2 = walk_target_global_position - global_position
	if to_target.length() <= current_speed * delta:
		global_position = _clamp_to_move_bounds(walk_target_global_position)
		is_walking = false
		_schedule_idle()
		return

	global_position = _clamp_to_move_bounds(global_position + to_target.normalized() * current_speed * delta)


func take_damage(amount: float, show_hit_feedback: bool = true, show_burn_scorch_on_kill: bool = true) -> void:
	if _state != MonsterState.ALIVE:
		return

	if show_hit_feedback:
		_fx_damage_timer = FX_DAMAGE_WINDOW
	hp = maxf(0.0, hp - amount)
	hp_bar.value = hp

	if hp <= 0.0:
		_start_death_sequence(show_burn_scorch_on_kill)


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


func play_run_end_disappear(duration: float) -> void:
	if _run_end_disappearing:
		return

	_run_end_disappearing = true
	_disable_attack_targeting()
	remove_from_group("attackable_monsters")
	is_walking = false
	walk_timer.stop()
	set_physics_process(false)

	var fade_tween: Tween = create_tween()
	fade_tween.set_parallel(true)
	fade_tween.tween_property(self, "modulate:a", 0.0, maxf(0.01, duration))
	fade_tween.tween_property(sprite, "self_modulate:a", 0.0, maxf(0.01, duration))


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

	if behavior_type == "orbit":
		_pick_new_orbit_center()
		walk_timer.start(randf_range(walk_time_range.x, walk_time_range.y))
		return

	if is_walking:
		if walk_until_arrived:
			return
		is_walking = false
		_schedule_idle()
		return

	walk_target_global_position = _pick_walk_target_global_position()
	is_walking = true
	if not walk_until_arrived:
		walk_timer.start(randf_range(walk_time_range.x, walk_time_range.y))


func _schedule_idle() -> void:
	walk_timer.start(randf_range(idle_time_range.x, idle_time_range.y))


func _get_wobbled_speed() -> float:
	var wobble: float = sin(Time.get_ticks_msec() * 0.001 * speed_wobble_frequency * TAU + _wobble_phase)
	return move_speed * (1.0 + wobble * speed_wobble_amount)


func _get_wobble_value() -> float:
	return sin(Time.get_ticks_msec() * 0.001 * speed_wobble_frequency * TAU + _wobble_phase)


func _update_sprite_bob() -> void:
	if _state != MonsterState.ALIVE:
		sprite.position.y = 0.0
		return

	if not is_walking and speed_wobble_amount > 0.0:
		var idle_bob: float = abs(_get_wobble_value()) * FX_BOB_HEIGHT * 0.3
		sprite.position.y = -idle_bob
		return

	if not is_walking:
		sprite.position.y = 0.0
		return

	var bob: float = abs(_get_wobble_value()) * FX_BOB_HEIGHT
	sprite.position.y = -bob


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


func _start_death_sequence(show_burn_scorch: bool = true) -> void:
	if _state != MonsterState.ALIVE:
		return

	var fx_duration: float = death_particles.lifetime + 0.05
	if show_burn_scorch:
		fx_duration = maxf(fx_duration, burn_scorch.lifetime + 0.05)
	_begin_despawn(MonsterState.DYING, fx_duration)
	killed.emit(self)
	sprite.visible = false
	death_marker.visible = false
	death_particles.emitting = true
	burn_scorch.emitting = show_burn_scorch


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

	if walk_until_arrived:
		var target: Vector2 = Vector2(
			randf_range(Globals.MONSTERS_FIELD_MIN.x, Globals.MONSTERS_FIELD_MAX.x),
			randf_range(Globals.MONSTERS_FIELD_MIN.y, Globals.MONSTERS_FIELD_MAX.y)
		)
		while target.distance_to(global_position) < roam_radius * 0.5:
			target = Vector2(
				randf_range(Globals.MONSTERS_FIELD_MIN.x, Globals.MONSTERS_FIELD_MAX.x),
				randf_range(Globals.MONSTERS_FIELD_MIN.y, Globals.MONSTERS_FIELD_MAX.y)
			)
		return target

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


func _try_flee_cursor(delta: float) -> bool:
	if _fx_damage_timer > 0.0:
		return false

	var mouse_pos: Vector2 = get_global_mouse_position()
	var to_monster: Vector2 = global_position - mouse_pos
	var distance: float = to_monster.length()

	if distance > flee_radius:
		return false

	var flee_dir: Vector2 = to_monster.normalized()
	if distance < 1.0:
		flee_dir = Vector2.from_angle(randf_range(0.0, TAU))

	var flee_speed: float = _get_wobbled_speed()
	global_position = _clamp_to_move_bounds(global_position + flee_dir * flee_speed * delta)
	is_walking = true
	return true


func _update_orbit(delta: float) -> void:
	var mouse_pos: Vector2 = get_global_mouse_position()

	_orbit_angle += orbit_speed * delta
	if _orbit_angle > TAU:
		_orbit_angle -= TAU

	var wobble: float = sin(_orbit_angle * 3.0 + _wobble_phase) * 0.15
	var effective_radius: float = orbit_radius * (1.0 + wobble)

	var target: Vector2 = mouse_pos + Vector2(
		cos(_orbit_angle) * effective_radius,
		sin(_orbit_angle) * effective_radius
	)
	target = _clamp_to_move_bounds(target)

	var to_target: Vector2 = target - global_position
	var max_step: float = _get_wobbled_speed() * delta
	if to_target.length() <= max_step:
		global_position = target
	else:
		global_position = _clamp_to_move_bounds(global_position + to_target.normalized() * max_step)
	is_walking = true


func _pick_new_orbit_center() -> void:
	var offset: Vector2 = Vector2.from_angle(randf_range(0.0, TAU)) * randf_range(orbit_radius * 0.5, orbit_radius * 1.5)
	_orbit_center = _clamp_to_move_bounds(global_position + offset)


func _get_move_bounds_center() -> Vector2:
	return (Globals.MONSTERS_FIELD_MIN + Globals.MONSTERS_FIELD_MAX) * 0.5


func _clamp_to_move_bounds(target_position: Vector2) -> Vector2:
	var move_bounds_min: Vector2 = _get_move_bounds_min()
	var move_bounds_max: Vector2 = _get_move_bounds_max()
	return Vector2(
		clampf(target_position.x, move_bounds_min.x, move_bounds_max.x),
		clampf(target_position.y, move_bounds_min.y, move_bounds_max.y)
	)


func _get_move_bounds_min() -> Vector2:
	var inset_x: float = minf(_collision_radius, maxf(0.0, Globals.MONSTERS_FIELD_SIZE_X * 0.5 - 1.0))
	var inset_y: float = minf(_collision_radius, maxf(0.0, Globals.MONSTERS_FIELD_SIZE_Y * 0.5 - 1.0))
	return Vector2(
		Globals.MONSTERS_FIELD_MIN.x + inset_x,
		Globals.MONSTERS_FIELD_MIN.y + inset_y
	)


func _get_move_bounds_max() -> Vector2:
	var inset_x: float = minf(_collision_radius, maxf(0.0, Globals.MONSTERS_FIELD_SIZE_X * 0.5 - 1.0))
	var inset_y: float = minf(_collision_radius, maxf(0.0, Globals.MONSTERS_FIELD_SIZE_Y * 0.5 - 1.0))
	return Vector2(
		Globals.MONSTERS_FIELD_MAX.x - inset_x,
		Globals.MONSTERS_FIELD_MAX.y - inset_y
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

	var texture: Texture2D = load(_sprite_texture_path) as Texture2D
	if texture == null:
		push_warning("Could not load monster sprite from %s" % _sprite_texture_path)
		return

	sprite.texture = texture


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
