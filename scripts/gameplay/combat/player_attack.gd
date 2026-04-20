class_name PlayerAttack
extends Area2D


@export var attack_radius: float = 20.0
@export var damage_per_second: float = 100.0
@export_range(0.05, 1.0, 0.05) var lifetime_slow_scale: float = 0.33333334
@export var stasis_field_enabled: bool = false
@export var attack_bounds_position: Vector2 = Vector2.ZERO
@export var attack_bounds_size: Vector2 = Vector2(1280.0, 720.0)

const HIT_SOUNDS: Array[AudioStream] = [
	preload("res://audio/ld59_hit1.mp3"),
	preload("res://audio/ld59_hit2.mp3"),
]
const HIT_PITCH_MIN: float = 0.88
const HIT_PITCH_MAX: float = 1.12
const HIT_COOLDOWN: float = 0.15
const HIT_VOLUME_BASE: float = -14.0
const HIT_VOLUME_RANGE: float = 1.5

@onready var attack_range: CollisionShape2D = $AttackRange
@onready var cursor_ring: Line2D = $CursorRing
@onready var _hit_sfx_pool: Array[AudioStreamPlayer] = [$HitSfx1, $HitSfx2]

var _targeted_monsters: Array[Monster] = []
var _is_active_in_bounds: bool = false
var _hit_sfx_cooldown: float = 0.0


func _ready() -> void:
	refresh_runtime_configuration()
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)


func _process(_delta: float) -> void:
	var parent_node: Node2D = get_parent() as Node2D
	if parent_node == null:
		return

	var local_mouse_position: Vector2 = parent_node.to_local(get_global_mouse_position())
	_is_active_in_bounds = Rect2(attack_bounds_position, attack_bounds_size).has_point(local_mouse_position)
	visible = _is_active_in_bounds
	monitoring = _is_active_in_bounds

	if _is_active_in_bounds:
		position = local_mouse_position
		return

	_clear_targeted_monsters()


func _physics_process(delta: float) -> void:
	if _hit_sfx_cooldown > 0.0:
		_hit_sfx_cooldown -= delta

	if not _is_active_in_bounds:
		return

	var damage_amount: float = damage_per_second * delta
	var monsters_to_damage: Array[Monster] = _targeted_monsters.duplicate()
	var dealt_damage: bool = false
	for monster: Monster in monsters_to_damage:
		if not is_instance_valid(monster):
			continue

		monster.take_damage(damage_amount)
		dealt_damage = true

	if dealt_damage and _hit_sfx_cooldown <= 0.0:
		_play_hit_sfx()
		_hit_sfx_cooldown = HIT_COOLDOWN


func _on_area_entered(area: Area2D) -> void:
	var monster: Monster = area as Monster
	if monster == null:
		return

	if _targeted_monsters.has(monster):
		return

	_targeted_monsters.append(monster)
	monster.push_lifetime_slow(lifetime_slow_scale)
	if stasis_field_enabled:
		monster.push_motion_lock()
	var tree_exited_callable: Callable = _on_monster_tree_exited.bind(monster)
	if not monster.tree_exited.is_connected(tree_exited_callable):
		monster.tree_exited.connect(tree_exited_callable, CONNECT_ONE_SHOT)


func _on_area_exited(area: Area2D) -> void:
	var monster: Monster = area as Monster
	if monster == null:
		return

	_release_monster(monster)


func _on_monster_tree_exited(monster: Monster) -> void:
	_targeted_monsters.erase(monster)


func _release_monster(monster: Monster) -> void:
	if not _targeted_monsters.has(monster):
		return

	_targeted_monsters.erase(monster)
	if is_instance_valid(monster):
		monster.pop_lifetime_slow()
		if stasis_field_enabled:
			monster.pop_motion_lock()


func refresh_runtime_configuration() -> void:
	var circle_shape: CircleShape2D = attack_range.shape as CircleShape2D
	if circle_shape != null:
		circle_shape.radius = attack_radius

	var base_radius: float = 20.0
	var scale_factor: float = attack_radius / base_radius
	cursor_ring.scale = Vector2(scale_factor, scale_factor)


func is_targeting_monster(monster: Monster) -> bool:
	return _targeted_monsters.has(monster)


func _clear_targeted_monsters() -> void:
	var monsters_to_release: Array[Monster] = _targeted_monsters.duplicate()
	for monster: Monster in monsters_to_release:
		_release_monster(monster)


func _play_hit_sfx() -> void:
	for player: AudioStreamPlayer in _hit_sfx_pool:
		if not player.playing:
			player.stream = HIT_SOUNDS[randi() % HIT_SOUNDS.size()]
			player.pitch_scale = randf_range(HIT_PITCH_MIN, HIT_PITCH_MAX)
			player.volume_db = HIT_VOLUME_BASE + randf_range(-HIT_VOLUME_RANGE, HIT_VOLUME_RANGE)
			player.play()
			return
