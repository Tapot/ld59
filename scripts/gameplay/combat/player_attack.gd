class_name PlayerAttack
extends Area2D


const ATTACKABLE_MONSTERS_GROUP: String = "attackable_monsters"
const HIT_PITCH_MIN: float = 0.88
const HIT_PITCH_MAX: float = 1.12
const HIT_COOLDOWN: float = 0.15
const HIT_VOLUME_BASE: float = -14.0
const HIT_VOLUME_RANGE: float = 1.5
const INACTIVE_COLOR: Color = Color(0.58, 0.86, 0.94, 0.72)
const ACTIVE_COLOR: Color = Color(1.0, 0.84, 0.32, 0.96)

@export var attack_radius: float = 24.0
@export var damage_per_second: float = 45.0
@export_range(0.05, 1.0, 0.05) var lifetime_slow_scale: float = 0.33333334
@export var stasis_field_enabled: bool = false
@export var attack_bounds_position: Vector2 = Vector2.ZERO
@export var attack_bounds_size: Vector2 = Vector2(1280.0, 720.0)

@onready var attack_range: CollisionShape2D = $AttackRange
@onready var cursor_ring: Line2D = $CursorRing
@onready var _hit_sfx_pool: Array[AudioStreamPlayer] = [$HitSfx1, $HitSfx2]

var _targeted_monsters: Array[Monster] = []
var _field_effect_monsters: Dictionary = {}
var _is_active_in_bounds: bool = false
var _hit_sfx_cooldown: float = 0.0


func _ready() -> void:
	refresh_runtime_configuration()
	Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)


func _exit_tree() -> void:
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	_release_all_field_effects()


func _process(_delta: float) -> void:
	var parent_node: Node2D = get_parent() as Node2D
	if parent_node == null:
		return

	var mouse_global_position: Vector2 = get_global_mouse_position()
	var attack_bounds_global_position: Vector2 = parent_node.global_position + attack_bounds_position
	_is_active_in_bounds = Rect2(attack_bounds_global_position, attack_bounds_size).has_point(mouse_global_position)
	visible = _is_active_in_bounds
	cursor_ring.default_color = ACTIVE_COLOR if _is_active_in_bounds else INACTIVE_COLOR

	if _is_active_in_bounds:
		global_position = mouse_global_position
		return

	_clear_targets_and_effects()


func _physics_process(delta: float) -> void:
	if _hit_sfx_cooldown > 0.0:
		_hit_sfx_cooldown -= delta

	if not _is_active_in_bounds :
		_release_all_field_effects()
		return

	_refresh_targets_from_distance()
	var damage_amount: float = damage_per_second * delta
	var dealt_damage: bool = false
	for monster: Monster in _targeted_monsters:
		if not is_instance_valid(monster):
			continue

		_apply_field_effects(monster)
		monster.take_damage(damage_amount)
		dealt_damage = true

	if dealt_damage and _hit_sfx_cooldown <= 0.0:
		_play_hit_sfx()
		_hit_sfx_cooldown = HIT_COOLDOWN


func refresh_runtime_configuration() -> void:
	var circle_shape: CircleShape2D = attack_range.shape as CircleShape2D
	if circle_shape != null:
		circle_shape.radius = attack_radius

	var base_radius: float = 20.0
	var scale_factor: float = attack_radius / base_radius
	cursor_ring.scale = Vector2(scale_factor, scale_factor)


func is_targeting_monster(monster: Monster) -> bool:
	return _targeted_monsters.has(monster)


func _refresh_targets_from_distance() -> void:
	var next_targets: Array[Monster] = []
	for node: Node in get_tree().get_nodes_in_group(ATTACKABLE_MONSTERS_GROUP):
		var monster: Monster = node as Monster
		if monster == null:
			continue
		if not is_instance_valid(monster):
			continue
		if not monster.is_alive_for_carry_over():
			continue
		if monster.global_position.distance_to(global_position) > attack_radius:
			continue
		next_targets.append(monster)

	for monster: Monster in _targeted_monsters:
		if next_targets.has(monster):
			continue
		_release_field_effects(monster)

	_targeted_monsters = next_targets


func _clear_targets_and_effects() -> void:
	_targeted_monsters.clear()
	_release_all_field_effects()


func _apply_field_effects(monster: Monster) -> void:
	var monster_id: int = monster.get_instance_id()
	if _field_effect_monsters.has(monster_id):
		return

	monster.push_lifetime_slow(lifetime_slow_scale)
	if stasis_field_enabled:
		monster.push_motion_lock()
	_field_effect_monsters[monster_id] = monster


func _release_field_effects(monster: Monster) -> void:
	if not is_instance_valid(monster):
		return

	var monster_id: int = monster.get_instance_id()
	if not _field_effect_monsters.has(monster_id):
		return

	monster.pop_lifetime_slow()
	if stasis_field_enabled:
		monster.pop_motion_lock()
	_field_effect_monsters.erase(monster_id)


func _release_all_field_effects() -> void:
	var active_monsters: Array = _field_effect_monsters.values()
	_field_effect_monsters.clear()
	for monster_variant: Variant in active_monsters:
		var monster: Monster = monster_variant as Monster
		if monster == null:
			continue
		if not is_instance_valid(monster):
			continue
		monster.pop_lifetime_slow()
		if stasis_field_enabled:
			monster.pop_motion_lock()


func _play_hit_sfx() -> void:
	if not is_inside_tree():
		return

	var hit_sounds: Array[AudioStream] = Audio.HIT_SOUNDS
	for player: AudioStreamPlayer in _hit_sfx_pool:
		if player == null:
			continue
		if not is_instance_valid(player):
			continue
		if not player.is_inside_tree():
			continue
		if not player.playing:
			player.stream = hit_sounds[randi() % hit_sounds.size()]
			player.pitch_scale = randf_range(HIT_PITCH_MIN, HIT_PITCH_MAX)
			var base_volume_db: float = HIT_VOLUME_BASE + randf_range(-HIT_VOLUME_RANGE, HIT_VOLUME_RANGE)
			player.volume_db = Audio.get_sfx_volume_db(base_volume_db)
			player.play()
			return
