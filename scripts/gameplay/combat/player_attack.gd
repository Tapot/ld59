class_name PlayerAttack
extends Area2D


@export var attack_radius: float = 20.0
@export var damage_per_second: float = 100.0
@export_range(0.05, 1.0, 0.05) var lifetime_slow_scale: float = 0.33333334
@export var attack_bounds_position: Vector2 = Vector2.ZERO
@export var attack_bounds_size: Vector2 = Vector2(1280.0, 720.0)

@onready var attack_range: CollisionShape2D = $AttackRange
@onready var cursor_ring: Line2D = $CursorRing

var _targeted_monsters: Array[Monster] = []
var _is_active_in_bounds: bool = false


func _ready() -> void:
	_apply_attack_radius()
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
	if not _is_active_in_bounds:
		return

	var damage_amount: float = damage_per_second * delta
	var monsters_to_damage: Array[Monster] = _targeted_monsters.duplicate()
	for monster: Monster in monsters_to_damage:
		if not is_instance_valid(monster):
			continue

		monster.take_damage(damage_amount)


func _on_area_entered(area: Area2D) -> void:
	var monster: Monster = area as Monster
	if monster == null:
		return

	if _targeted_monsters.has(monster):
		return

	_targeted_monsters.append(monster)
	monster.push_lifetime_slow(lifetime_slow_scale)
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


func _apply_attack_radius() -> void:
	var circle_shape: CircleShape2D = attack_range.shape as CircleShape2D
	if circle_shape != null:
		circle_shape.radius = attack_radius

	var base_radius: float = 20.0
	var scale_factor: float = attack_radius / base_radius
	cursor_ring.scale = Vector2(scale_factor, scale_factor)


func _clear_targeted_monsters() -> void:
	var monsters_to_release: Array[Monster] = _targeted_monsters.duplicate()
	for monster: Monster in monsters_to_release:
		_release_monster(monster)
